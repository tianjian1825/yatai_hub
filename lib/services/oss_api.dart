import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// OSS 相关 API 服务（签名获取、直传、护照识别）
class OssApi {
  static final Dio _client = ApiClient().dio;

  /// 获取 OSS 直传签名
  static Future<Map<String, dynamic>?> getDirectUploadSign(
    String filename,
  ) async {
    try {
      final response = await _client.get(
        '/v1/oss/get_oss_direct_upload_sign',
        queryParameters: {'filename': filename},
      );

      if (kDebugMode) {
        print('[OSS签名] 响应: ${response.data}');
      }

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        return data['data'] as Map<String, dynamic>;
      }
      throw Exception(
        data is Map ? (data['msg']?.toString() ?? '获取OSS签名失败') : '获取OSS签名失败',
      );
    } catch (e) {
      if (kDebugMode) print('[OSS签名] 获取失败: $e');
      rethrow;
    }
  }

  /// 注册前 OSS 直传签名（无需登录态）
  ///
  /// 限制：jpg/jpeg/png/pdf，≤ 10MB，签名 5 分钟有效，固定写入 register/tmp/
  static Future<Map<String, dynamic>?> getRegisterUploadSign(
    String filename,
  ) async {
    try {
      final response = await _client.get(
        '/v1/oss/get_register_upload_sign',
        queryParameters: {'filename': filename},
      );

      if (kDebugMode) {
        print('[OSS注册签名] 响应: ${response.data}');
      }

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        return data['data'] as Map<String, dynamic>;
      }
      throw Exception(
        data is Map ? (data['msg']?.toString() ?? '获取上传签名失败') : '获取上传签名失败',
      );
    } catch (e) {
      if (kDebugMode) print('[OSS注册签名] 获取失败: $e');
      rethrow;
    }
  }

  /// 阿里云 OSS 直传（使用签名配置上传文件）
  /// 返回文件的完整 URL
  static Future<String?> uploadToOss({
    required File file,
    required Map<String, dynamic> signData,
  }) async {
    try {
      final host = signData['host'] as String;
      final key = signData['key'] as String;
      final policy = signData['policy'] as String;
      final signature = signData['signature'] as String;
      final accessKeyId = signData['accessKeyId'] as String;

      final formData = FormData.fromMap({
        'key': key,
        'policy': policy,
        'OSSAccessKeyId': accessKeyId,
        'Signature': signature,
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
        ),
      });

      final ossDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 120),
        ),
      );

      final response = await ossDio.post(
        host,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        final imageUrl = '$host/$key';
        if (kDebugMode) print('[OSS上传] 成功: $imageUrl');
        return imageUrl;
      }

      if (kDebugMode) {
        print('[OSS上传] 失败, statusCode: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[OSS上传] 异常: $e');
      rethrow;
    }
  }

  /// 护照 OCR 识别
  static Future<Map<String, dynamic>?> recognizePassport(
    String imageUrl,
  ) async {
    try {
      final response = await _client.post(
        '/v1/oss/oss_recognize_passport',
        data: {'image_url': imageUrl},
      );

      if (kDebugMode) {
        print('[护照识别] 响应: ${response.data}');
      }

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        return data['data'] as Map<String, dynamic>?;
      }
      throw Exception(
        data is Map ? (data['msg']?.toString() ?? '护照识别失败') : '护照识别失败',
      );
    } catch (e) {
      if (kDebugMode) print('[护照识别] 失败: $e');
      rethrow;
    }
  }

  /// 注册前护照 OCR 识别（无需登录态）
  ///
  /// 与 [recognizePassport] 逻辑一致，区别仅在于免登录、只支持按 image_url 识别。
  /// 配合 [getRegisterUploadSign] 直传到 register/tmp/ 后用返回的 URL 调用。
  static Future<Map<String, dynamic>?> recognizePassportForRegister(
    String imageUrl,
  ) async {
    try {
      final response = await _client.post(
        '/v1/oss/oss_recognize_passport_register',
        data: {'image_url': imageUrl},
      );

      if (kDebugMode) {
        print('[注册护照识别] 响应: ${response.data}');
      }

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        return data['data'] as Map<String, dynamic>?;
      }
      throw Exception(
        data is Map ? (data['msg']?.toString() ?? '护照识别失败') : '护照识别失败',
      );
    } catch (e) {
      if (kDebugMode) print('[注册护照识别] 失败: $e');
      rethrow;
    }
  }
}
