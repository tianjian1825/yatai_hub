import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/services/api_client.dart';
import 'package:yatai_hub/services/department_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/services/list_cache_service.dart';
import 'package:yatai_hub/services/jpush_service.dart';
import 'package:yatai_hub/services/parttime_clock_service.dart';
import 'package:yatai_hub/services/settlement_service.dart';
import 'package:yatai_hub/services/chat_local_db.dart';
import 'package:yatai_hub/services/user_register_info_service.dart';
import 'package:yatai_hub/services/user_service.dart';

/// 登录结果
class LoginResult {
  final bool success;
  final String? errorMessage;

  const LoginResult({required this.success, this.errorMessage});

  factory LoginResult.ok() => const LoginResult(success: true);
  factory LoginResult.fail([String? message]) =>
      LoginResult(success: false, errorMessage: message ?? '登录失败，请重试');
}

/// 认证服务 - 管理登录状态和用户认证
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _keyAccessToken = 'user_access_token';
  static const String _legacyKeySign = 'user_sign';
  static const String _keyIsLoggedIn = 'is_logged_in';

  /// 是否正在主动退出登录。
  /// 主动登出会清除 token 并跳转登录页，期间 logout 接口或在途请求若返回 401，
  /// 不应再弹"登录已失效"弹窗。重新登录成功（saveAccessToken）后复位。
  bool isLoggingOut = false;

  /// 获取当前 Access Token（兼容旧 sign 键）
  Future<String?> getAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAccessToken) ??
          prefs.getString(_legacyKeySign);
    } catch (e) {
      return null;
    }
  }

  /// 兼容旧方法名
  Future<String?> getSign() async {
    return getAccessToken();
  }

  /// 保存 Access Token（并写入旧 sign 键以兼容历史代码）
  Future<bool> saveAccessToken(String accessToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccessToken, accessToken);
      await prefs.setString(_legacyKeySign, accessToken);
      await prefs.setBool(_keyIsLoggedIn, true);
      UserService().resetUserInfoInitState();
      // 重新登录成功，恢复正常的登录失效提醒
      isLoggingOut = false;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 兼容旧方法名
  Future<bool> saveSign(String sign) async {
    return saveAccessToken(sign);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
      final accessToken =
          prefs.getString(_keyAccessToken) ?? prefs.getString(_legacyKeySign);

      // 只有当标记为已登录且有token时才返回true
      return isLoggedIn && accessToken != null && accessToken.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('检查登录状态失败: $e');
      return false;
    }
  }

  /// 账号密码登录（POST /v1/login/account）
  ///
  /// [username] 支持姓名 / 手机号 / 邮箱
  ///
  /// 错误码：
  /// - 2001 账号或密码为空
  /// - 2002 账号或密码错误
  /// - 2003 账号未审核或已禁用
  Future<LoginResult> loginWithAccount({
    required String username,
    required String password,
  }) async {
    try {
      final client = ApiClient();

      final response = await client.post(
        '/v1/login/account',
        data: {'username': username, 'password': password},
      );

      Map<String, dynamic>? jsonData;
      if (response.data is String) {
        try {
          jsonData = jsonDecode(response.data);
        } catch (e) {
          if (kDebugMode) print('JSON解析失败: $e');
        }
      } else if (response.data is Map) {
        jsonData = Map<String, dynamic>.from(response.data);
      }

      if (jsonData == null) return LoginResult.fail();

      // 以是否拿到 access_token 作为成功的唯一标准，
      // 后端成功/失败的 code 约定不一致（失败时 code 可能为 1），不能仅凭 code 判断
      final code = jsonData['code'];
      final data = jsonData['data'];
      if (data is Map) {
        final accessToken = data['access_token']?.toString();
        if (accessToken != null && accessToken.isNotEmpty) {
          await saveAccessToken(accessToken);
          _postLoginBindDevice();
          return LoginResult.ok();
        }
      }

      // 业务错误，优先展示后端返回的 msg
      final msg = jsonData['msg']?.toString() ?? _mapAccountLoginCode(code);
      return LoginResult.fail(msg);
    } on DioException catch (e) {
      if (kDebugMode) print('账号登录请求异常: $e');
      // 业务错误码可能放在 detail
      final detailCode = _extractDetailCode(e);
      final fallback = _mapAccountLoginCode(detailCode);
      return LoginResult.fail(_extractErrorMessage(e) ?? fallback);
    } catch (e) {
      if (kDebugMode) print('账号登录异常: $e');
      return LoginResult.fail();
    }
  }

  /// 注册（POST /v1/register）
  ///
  /// 成功返回 (true, msg)，失败返回 (false, errorMessage)
  Future<({bool success, String? message})> register({
    required String realname,
    required String email,
    required String password,
    required int krLanguageLevel,
    required List<Map<String, String>> krParttimeFiles,
    // 手机号 / 性别 / 出生日期 / 韩国住址 / 微信 ID 为选填，留空时不下发对应字段
    String? mobile,
    String? gender,
    String? birthday,
    String? krAddress,
    String? wechat,
  }) async {
    try {
      final client = ApiClient();

      final body = <String, dynamic>{
        'realname': realname,
        'email': email,
        'password': password,
        'mobile': ?mobile,
        'gender': ?gender,
        'birthday': ?birthday,
        'kr_address': ?krAddress,
        'wechat': ?wechat,
        'kr_language_level': krLanguageLevel,
        'kr_parttime_files': krParttimeFiles,
      };

      final response = await client.post('/v1/register', data: body);

      Map<String, dynamic>? jsonData;
      if (response.data is String) {
        try {
          jsonData = jsonDecode(response.data);
        } catch (_) {}
      } else if (response.data is Map) {
        jsonData = Map<String, dynamic>.from(response.data);
      }

      if (jsonData == null) {
        return (success: false, message: '注册失败，请重试');
      }

      final code = jsonData['code'];
      final isSuccess = code == 0 || code == '0';
      final msg = jsonData['msg']?.toString();

      if (isSuccess) {
        return (success: true, message: msg ?? '注册成功，请等待管理员审核');
      }

      // 2004 邮箱已被注册
      if (code == 2004 || code == '2004') {
        return (success: false, message: msg ?? '该邮箱已注册');
      }

      return (success: false, message: msg ?? '注册失败，请重试');
    } on DioException catch (e) {
      if (kDebugMode) print('注册请求异常: $e');
      final detailCode = _extractDetailCode(e);
      String? msg = _extractErrorMessage(e);
      if (msg == null && (detailCode == 2004 || detailCode == '2004')) {
        msg = '该邮箱已注册';
      }
      return (success: false, message: msg ?? '注册失败，请重试');
    } catch (e) {
      if (kDebugMode) print('注册异常: $e');
      return (success: false, message: '注册失败，请重试');
    }
  }

  String _mapAccountLoginCode(dynamic code) {
    final c = code is num ? code.toInt() : int.tryParse(code?.toString() ?? '');
    switch (c) {
      case 2001:
        return '账号或密码不能为空';
      case 2002:
        return '账号或密码错误';
      case 2003:
        return '账号未审核或已禁用';
      default:
        return '登录失败，请重试';
    }
  }

  dynamic _extractDetailCode(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) return detail['code'];
      }
      if (data is String) {
        final json = jsonDecode(data);
        if (json is Map) {
          final detail = json['detail'];
          if (detail is Map) return detail['code'];
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从 DioException 响应中提取错误信息
  /// 失败格式: {"detail":{"msg":"...","code":"-1","data":[]}}
  String? _extractErrorMessage(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          return detail['msg']?.toString();
        }
        // detail 本身可能是字符串
        if (detail is String) {
          return detail;
        }
      }
      if (data is String) {
        final json = jsonDecode(data);
        if (json is Map) {
          final detail = json['detail'];
          if (detail is Map) return detail['msg']?.toString();
          if (detail is String) return detail;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 登录成功后的推送处理：ensure 初始化 JPush + 恢复推送 + 上报 RID（fire-and-forget）
  ///
  /// 未登录态前 jpush 不 initialize，登录成功时才启动 SDK；用户卸载重装但未退出登录的
  /// 场景下，登录页期间不会收到推送（后端旧 RID 绑定无法触达设备）。
  void _postLoginBindDevice() {
    // ignore: discarded_futures
    _ensureJPushAndBind();
  }

  Future<void> _ensureJPushAndBind() async {
    try {
      // 注意：本 App 未启用隐私弹窗（main.dart 中 needsPrivacyPolicy 硬编码
      // false），acceptPolicy 永远不会被写入，needsToShowPolicy 恒为 true。
      // 此处不能像 suixinpai 那样用它做 guard，否则登录路径的
      // initialize/resumePush/bind 整段被跳过——退登(stopPush)后再登录
      // 推送会永久停止。若未来恢复隐私弹窗，需连同此处 guard 一起加回。
      // 游客模式不绑定 / 不接收推送（共用 token，避免错绑到游客底账号）
      if (await GuestModeService().isGuestMode()) return;
      // initialize 内部 idempotent，多次调用安全
      await JPushService().initialize();
      await JPushService().resumePush();
      await bindDeviceRegistrationId();
    } catch (e) {
      if (kDebugMode) print('[postLogin] jpush 初始化 / 绑定失败: $e');
    }
  }

  /// 绑定极光 Registration ID 到当前登录用户
  ///
  /// 登录成功 / App 启动检测到已登录态时调用。覆盖写入，可重复调用。
  /// 游客模式跳过（共用 token，避免把 RID 绑到游客底账号）。
  /// fire-and-forget：失败不影响主流程。
  Future<void> bindDeviceRegistrationId() async {
    try {
      if (await GuestModeService().isGuestMode()) {
        if (kDebugMode) print('[bindDevice] 游客模式，跳过上报');
        return;
      }
      final rid = await JPushService().awaitRegistrationId();
      if (rid == null || rid.isEmpty) {
        if (kDebugMode) print('[bindDevice] RID 未就绪，挂迟到补报');
        _scheduleLateBind();
        return;
      }
      final client = ApiClient();
      final response = await client.post(
        '/v1/user/bind_device',
        // app=parttime 标识独立兼职 APP，按 APP 分别投递推送
        data: {'registration_id': rid, 'app': 'parttime'},
      );
      if (kDebugMode) {
        print('[bindDevice] 上报成功 rid=$rid, resp=${response.data}');
      }
    } catch (e) {
      if (kDebugMode) print('[bindDevice] 上报失败: $e');
    }
  }

  /// RID 迟到补报是否已挂载（会话级一次即可，就绪后 awaitRegistrationId 直接命中）
  bool _lateBindScheduled = false;

  /// RID 未在同步等待窗口内就绪（首装弱网 / iOS 首启联网授权晚给）时，
  /// 挂到 RID 就绪信号上补报一次，避免整个会话都收不到定向推送。
  void _scheduleLateBind() {
    if (_lateBindScheduled) return;
    _lateBindScheduled = true;
    // ignore: discarded_futures
    JPushService().onRegistrationIdReady.then(
      (_) => bindDeviceRegistrationId(),
    );
  }

  /// 退出登录
  ///
  /// 流程：
  /// 1. 调用 POST /v1/user/logout 通知后端清空 registration_id（接口失败仅记录日志，不阻断本地清理）
  /// 2. 停止本地极光推送，避免下个用户登录前残留消息
  /// 3. 清除本地 token / 登录态 / 用户缓存
  Future<void> logout() async {
    // 标记进入登出流程，抑制此期间 401 触发的"登录已失效"弹窗
    isLoggingOut = true;
    // 1. 通知后端 —— JWT 服务端无状态，此调用主要为了清空 registration_id
    try {
      final client = ApiClient();
      // app=parttime 只解绑本 APP 的 token，避免误清用户在 OA APP 上的绑定
      final response =
          await client.post('/v1/user/logout', data: {'app': 'parttime'});
      if (kDebugMode) print('[logout] 服务端响应: ${response.data}');
    } catch (e) {
      if (kDebugMode) print('[logout] 调用后端 logout 失败（忽略，继续本地清理）: $e');
    }
    // 2. 停推送
    try {
      await JPushService().stopPush();
    } catch (e) {
      if (kDebugMode) print('停止推送失败: $e');
    }
    // 3. 本地清理
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_legacyKeySign);
      await prefs.setBool(_keyIsLoggedIn, false);
      // 清除用户信息缓存（含 bd_flag/schedule_flag/follow_up_flag 等权限字段），
      // 避免下个账号在 initUserInfo() 覆写前的窗口期拿到上个账号的权限
      await UserService().clearUserCache();
      // 清除部门缓存，避免跨账号串数据
      await DepartmentService().clearCache();
      // 清除列表分页缓存，避免上个账号的列表数据残留
      await ListCacheService().clearAllCache();
      // 清除兼职打卡本地缓存，避免上个账号状态残留到下个账号
      await ParttimeClockService().clearLocal();
      // 清除钱包首页本地缓存，避免跨账号串数据
      await SettlementService().clearCache();
      // 清除个人资料缓存，避免上个账号信息残留
      await UserRegisterInfoService().clearCache();
      // 清除群聊离线库与「消息」Tab 显隐缓存，避免跨账号串数据
      await ChatLocalDb().clearAll();
      await prefs.remove('show_chat_tab');
    } catch (e) {
      if (kDebugMode) print('退出登录失败: $e');
    }
  }

  /// 验证登录状态（通过获取用户信息）
  /// 返回true表示登录有效，false表示需要重新登录
  Future<bool> validateLoginStatus() async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      // 复用 UserService 的初始化逻辑，避免启动阶段重复调用 getUserInfo。
      // 成功后会被 UserService 缓存，后续再次 initUserInfo 不会发起新请求。
      final initSuccess = await UserService().initUserInfo();
      if (initSuccess) {
        return true;
      }

      // 接口失败时，保守处理：有 token 则保持登录态，避免网络抖动导致误登出。
      return true;
    } catch (e) {
      if (kDebugMode) print('验证登录状态异常: $e');
      // 网络异常时，如果有token就保持登录状态
      // 避免因为网络问题导致用户被强制登出
      final accessToken = await getAccessToken();
      final hasToken = accessToken != null && accessToken.isNotEmpty;
      if (kDebugMode) print('验证异常但有token($hasToken)，保持登录状态');
      return hasToken;
    }
  }
}
