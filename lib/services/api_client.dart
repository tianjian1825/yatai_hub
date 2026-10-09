import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:yatai_hub/app_info.dart';
import 'package:yatai_hub/main.dart';
import 'package:yatai_hub/pages/login_page.dart';
import 'package:yatai_hub/services/auth_service.dart';

/// 认证失效异常
class AuthException implements Exception {
  final String message;
  AuthException([this.message = '未登录或登录已过期']);

  @override
  String toString() => message;
}

/// API 配置类
class ApiConfig {
  // 测试环境
  static const String baseUrlTest = 'http://10.29.91.46:8000/';

  // 正式环境
  static const String baseUrlProd = 'https://oa.aimei.group';
  

  // 当前使用的 base URL
  static String get baseUrl => baseUrlProd;

  // 连接超时时间
  static const int connectTimeout = 60000;

  // 接收超时时间
  static const int receiveTimeout = 60000;
}

/// API 客户端类
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio _dio;
  final AuthService _authService = AuthService();

  /// 是否正在处理登录失效跳转，防止多个 401 同时触发多次跳转
  static bool _isHandlingAuthExpired = false;

  /// 与后端约定回退时区，取不到本机 IANA 时区名时使用（UTC+8）。
  static const String _fallbackTimezone = 'Asia/Shanghai';

  /// 本机 IANA 时区名（如 Asia/Seoul），解析一次后缓存，随请求带 X-Timezone。
  static String? _cachedTimezone;
  static Future<String>? _resolvingTimezone;

  /// 解析本机 IANA 时区名并缓存；插件异常时回退 [_fallbackTimezone]。
  Future<String> _timezoneName() {
    if (_cachedTimezone != null) return Future.value(_cachedTimezone);
    return _resolvingTimezone ??= FlutterTimezone.getLocalTimezone()
        .then((info) {
          final name = info.identifier.trim();
          return _cachedTimezone = name.isEmpty ? _fallbackTimezone : name;
        })
        .catchError((_) => _cachedTimezone = _fallbackTimezone);
  }

  factory ApiClient() {
    return _instance;
  }

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: ApiConfig.receiveTimeout),
        headers: {
          'frontend': 'frontend',
          // 自定义 User-Agent：保留 dart:io 默认段，再追加 app 版本 / 平台 / 系统版本
          'user-agent': _buildUserAgent(),
        },
      ),
    );

    // 添加请求拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 统一携带 Bearer Token
          final accessToken = await _authService.getAccessToken();
          if (accessToken != null && accessToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }

          // 统一携带本机 IANA 时区名，供后端按用户时区格式化时间
          options.headers['X-Timezone'] = await _timezoneName();

          if (kDebugMode) {
            debugPrint('[API请求] ${options.method} ${options.uri}');
            if (options.data != null) {
              debugPrint('[API请求数据] ${options.data}');
            }
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // 处理响应
          if (kDebugMode) {
            debugPrint(
              '[API响应] ${response.requestOptions.method} ${response.requestOptions.uri}',
            );
            debugPrint('[API响应码] ${response.statusCode}');
            debugPrint('[API响应数据] ${response.data}');
          }

          final data = response.data;

          // 检查是否需要登录
          if (data is Map && data['code'] == 401) {
            handleAuthExpired();
            if (kDebugMode) {
              debugPrint('[API错误] 需要登录: ${response.requestOptions.uri}');
            }
            return handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: AuthException(),
              ),
            );
          }

          return handler.next(response);
        },
        onError: (DioException e, handler) {
          // 处理错误
          String errorMessage = '网络请求失败';

          if (e.type == DioExceptionType.connectionTimeout) {
            errorMessage = '连接超时';
          } else if (e.type == DioExceptionType.receiveTimeout) {
            errorMessage = '接收超时';
          } else if (e.type == DioExceptionType.badResponse) {
            // 提供更详细的错误信息
            final statusCode = e.response?.statusCode;
            final responseData = e.response?.data;
            errorMessage = '服务器错误 (${statusCode ?? "未知状态码"})';

            if (kDebugMode) {
              debugPrint(
                '[API错误] ${e.requestOptions.method} ${e.requestOptions.uri}',
              );
              debugPrint('[错误状态码] $statusCode');
              debugPrint('[错误响应] $responseData');
            }

            if (statusCode == 401) {
              handleAuthExpired();
              return handler.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  response: e.response,
                  type: DioExceptionType.badResponse,
                  error: AuthException(),
                ),
              );
            }

            // 尝试从响应中提取错误信息
            if (responseData is Map) {
              if (responseData['msg'] != null) {
                errorMessage = responseData['msg'].toString();
              } else if (responseData['detail'] != null) {
                final detail = responseData['detail'];
                if (detail is Map && detail['msg'] != null) {
                  errorMessage = detail['msg'].toString();
                } else if (detail is String) {
                  errorMessage = detail;
                } else {
                  errorMessage = detail.toString();
                }
              }
            }
          } else if (e.type == DioExceptionType.cancel) {
            errorMessage = '请求已取消';
          } else if (e.type == DioExceptionType.connectionError) {
            errorMessage = '网络连接失败，请检查网络设置';
            if (kDebugMode) {
              debugPrint('[API错误] 连接错误: ${e.message}');
            }
          }

          return handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: errorMessage,
            ),
          );
        },
      ),
    );
  }

  Dio get dio => _dio;

  /// 构建自定义 User-Agent。
  ///
  /// 保留 dart:io 默认的 `Dart/<主.次> (dart:io)`（从 [Platform.version] 还原，
  /// 随 Dart 升级自动跟进），再用 ` / ` 依次追加：
  /// - App 版本号（[AppInfo.fullVersion]，如 `1.3.5+35`）
  /// - 平台（`ios` / `android` / `windows`，纯 Dart 拿不到具体机型）
  /// - 系统版本（如 `17.4 (Build 21E219)` / `13 (API 33)`）
  ///
  /// 形如：`Dart/3.12 (dart:io) / 1.3.5+35 / ios / 17.4 (Build 21E219)`
  static String _buildUserAgent() {
    // dart:io 默认 UA 段：取主.次版本
    final dartFull = Platform.version.split(' ').first; // 如 3.12.0
    final dp = dartFull.split('.');
    final dartMajorMinor = dp.length >= 2 ? '${dp[0]}.${dp[1]}' : dartFull;

    return [
      'Dart/$dartMajorMinor (dart:io)',
      AppInfo.fullVersion,
      Platform.operatingSystem,
      _osVersionLabel(),
    ].join(' / ');
  }

  /// 清洗系统版本串，去掉各平台冗余前缀（平台名已单独成段）。
  static String _osVersionLabel() {
    final raw = Platform.operatingSystemVersion;
    if (Platform.isIOS) {
      // iOS 形如 "Version 17.4 (Build 21E219)"
      return raw.replaceFirst('Version ', '');
    }
    if (Platform.isAndroid) {
      // Android 形如 "Android 13 (API 33)"
      return raw.replaceFirst('Android ', '');
    }
    return raw;
  }

  /// GET 请求
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await _dio.get(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// POST 请求
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PUT 请求
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.put(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// DELETE 请求
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.delete(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// POST FormData 请求（用于文件上传）
  Future<Response> postFormData(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    return await _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options:
          options ?? Options(headers: {'Content-Type': 'multipart/form-data'}),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// 获取当前 access_token
  Future<String?> getAccessToken() async {
    return await _authService.getAccessToken();
  }

  /// 处理登录失效，清除认证信息并跳转到登录页面
  void handleAuthExpired() {
    if (_isHandlingAuthExpired) return;
    // 主动退出登录中，logout 接口或在途请求返回 401 不再弹"登录已失效"弹窗
    if (_authService.isLoggingOut) return;
    _isHandlingAuthExpired = true;

    final context = YataiHubApp.navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('提示'),
            content: const Text('登录已失效，请重新登录'),
            actions: <Widget>[
              TextButton(
                child: const Text('确定'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      ).then((_) {
        performLogoutAndRedirect();
      });
    } else {
      performLogoutAndRedirect();
    }
  }

  void performLogoutAndRedirect() {
    _authService.logout().then((_) {
      final navigator = YataiHubApp.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
      _isHandlingAuthExpired = false;
    });
  }
}
