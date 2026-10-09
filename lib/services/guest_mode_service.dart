import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 游客模式服务 - 管理游客访问状态
class GuestModeService {
  static final GuestModeService _instance = GuestModeService._internal();
  factory GuestModeService() => _instance;
  GuestModeService._internal();

  /// 游客专用 Sign
  static const String guestSign =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI3NDkiLCJkaW5nX3VzZXJpZCI6IjE2OTE0NjY2MTYwODczNTczIiwidXNlcm5hbWUiOiJcdTY1YjlcdTYzNzdcdTYyYTUiLCJuaWNrbmFtZSI6IkRhcnJlbiBGYW5nIiwicmVhbG5hbWUiOiJcdTY1YjlcdTYzNzdcdTYyYTUiLCJyb2xlaWQiOjksInJvbGVuYW1lIjoiXHU1YmEyXHU2NzBkXHU0ZWUzXHU4ODY4Iiwic3RhdHVzIjoxLCJlbWFpbCI6ImppZWJhby5mYW5nQGZveG1haWwuY29tIiwibW9iaWxlIjoiIiwiYXZhdGFyIjoiaHR0cHM6Ly9pbWcta2YuYmVpc2UuY29tL3VwbG9hZGZpbGUvMjAyNC8xMjI1LzIwMjQxMjI1MTE0MDM0ODczMjI1LmpwZyIsInNpdGVpZCI6MTEsImxhc3RfbG9naW5fdGltZSI6MTc4MjQ1Mjk3OCwibG9naW5faXAiOiIzOS4xNjUuNjUuNDQiLCJkaXNhYmxlZCI6MCwiZXhwIjoxNzg1MDQ0OTc4fQ.-g-QC3-Ah6FIT4aebGu21ba9uVsafOEmFSIoFc1dxis';

  static const String _keyIsGuestMode = 'is_guest_mode';

  /// 检查当前是否为游客模式
  Future<bool> isGuestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyIsGuestMode) ?? false;
    } catch (e) {
      if (kDebugMode) print('检查游客模式失败: $e');
      return false;
    }
  }

  /// 以游客身份登录
  Future<bool> loginAsGuest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_access_token', guestSign);
      await prefs.setString('user_sign', guestSign);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool(_keyIsGuestMode, true);
      return true;
    } catch (e) {
      if (kDebugMode) print('游客模式登录失败: $e');
      return false;
    }
  }

  /// 退出游客模式
  Future<void> exitGuestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_access_token');
      await prefs.remove('user_sign');
      await prefs.setBool('is_logged_in', false);
      await prefs.remove(_keyIsGuestMode);
    } catch (e) {
      if (kDebugMode) print('退出游客模式失败: $e');
    }
  }

  /// 显示游客模式不可用提示
  static void showGuestModeNotAvailable(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('游客模式不可用'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
