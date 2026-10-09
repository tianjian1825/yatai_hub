import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/services/api_client.dart';
import '../models/user_register_info.dart';

/// 兼职用户个人资料（注册信息）服务
///
/// 对应接口 GET /v1/user/register_info（按登录用户 userid 查询）。
/// 带内存 + SharedPreferences 双层缓存，进入页面先展示缓存再后台刷新。
class UserRegisterInfoService {
  static final UserRegisterInfoService _instance =
      UserRegisterInfoService._internal();
  factory UserRegisterInfoService() => _instance;
  UserRegisterInfoService._internal();

  static const String _cacheKey = 'cached_user_register_info';

  // 内存缓存
  UserRegisterInfo? _cached;

  /// 读取本地缓存（内存优先，其次磁盘）。无缓存返回 null。
  Future<UserRegisterInfo?> getCached() async {
    if (_cached != null) return _cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _cached = UserRegisterInfo.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
        return _cached;
      }
    } catch (e) {
      if (kDebugMode) print('读取个人资料缓存失败: $e');
    }
    return null;
  }

  /// 从服务器获取个人资料，成功后写入缓存。失败返回 null。
  Future<UserRegisterInfo?> fetch() async {
    try {
      final response = await ApiClient().dio.get('/v1/user/register_info');
      if (response.data['code'] == 0 && response.data['data'] != null) {
        final info = UserRegisterInfo.fromJson(
          Map<String, dynamic>.from(response.data['data']),
        );
        _cached = info;
        await _saveToCache(info);
        return info;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('获取个人资料失败: $e');
      return null;
    }
  }

  /// 重新提交审核申请（POST /v1/user/register_info_update）
  ///
  /// 仅 parttime_audit_status 为 0（待审核）或 2（已驳回）可调用；
  /// 已通过（1）后端会返回「资料已审核通过，不可修改」。
  /// 成功后状态自动回到待审核、清空驳回原因，这里主动刷新缓存。
  ///
  /// 返回 (true, msg) 成功 / (false, errorMessage) 失败。
  Future<({bool success, String? message})> submitUpdate({
    required String realname,
    required int krLanguageLevel,
    required List<Map<String, String>> krParttimeFiles,
    // 手机号为选填，留空时不下发该字段
    String? mobile,
    String? wechat,
    String? gender,
    String? birthday,
    String? krPhone,
    String? krAddress,
  }) async {
    try {
      final body = <String, dynamic>{
        'realname': realname,
        'mobile': ?mobile,
        'wechat': ?wechat,
        'kr_language_level': krLanguageLevel,
        'kr_parttime_files': krParttimeFiles,
        'gender': ?gender,
        'birthday': ?birthday,
        'kr_phone': ?krPhone,
        'kr_address': ?krAddress,
      };
      final response = await ApiClient().dio.post(
        '/v1/user/register_info_update',
        data: body,
      );
      final data = response.data;
      final code = data is Map ? data['code'] : null;
      final msg = data is Map ? data['msg']?.toString() : null;
      if (code == 0 || code == '0') {
        // 重新提交成功，状态回到待审核；刷新缓存以拉取最新审核状态
        await fetch();
        return (success: true, message: msg ?? '已重新提交，请等待管理员审核');
      }
      return (success: false, message: msg ?? '提交失败，请重试');
    } catch (e) {
      if (kDebugMode) print('重新提交审核失败: $e');
      return (success: false, message: '提交失败，请重试');
    }
  }

  Future<void> _saveToCache(UserRegisterInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(info.toJson()));
    } catch (e) {
      if (kDebugMode) print('保存个人资料缓存失败: $e');
    }
  }

  /// 清除缓存（登出 / 切换账号时调用）
  Future<void> clearCache() async {
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      if (kDebugMode) print('清除个人资料缓存失败: $e');
    }
  }
}
