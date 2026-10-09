import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐私政策服务 - 管理隐私政策版本和用户接受状态
class PrivacyPolicyService {
  static final PrivacyPolicyService _instance =
      PrivacyPolicyService._internal();
  factory PrivacyPolicyService() => _instance;
  PrivacyPolicyService._internal();

  // 当前隐私政策版本号（硬编码）
  // 更新隐私政策时，手动修改此版本号即可触发用户重新确认
  static const String currentVersion = '1.0';

  // SharedPreferences 键名
  static const String _keyAcceptedVersion = 'privacy_policy_accepted_version';
  static const String _keyAcceptedDate = 'privacy_policy_accepted_date';

  /// 检查是否需要显示隐私政策
  /// 返回 true 如果：
  /// 1. 首次启动（无接受记录）
  /// 2. 版本已更新（已接受版本 ≠ 当前版本）
  Future<bool> needsToShowPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acceptedVersion = prefs.getString(_keyAcceptedVersion);

      // 如果没有接受记录，说明是首次启动
      if (acceptedVersion == null || acceptedVersion.isEmpty) {
        if (kDebugMode) print('首次启动，需要显示隐私政策');
        return true;
      }

      // 检查版本是否匹配
      if (acceptedVersion != currentVersion) {
        if (kDebugMode) {
          print('隐私政策版本已更新: $acceptedVersion -> $currentVersion');
        }
        return true;
      }

      // 版本匹配，不需要显示
      if (kDebugMode) print('隐私政策已接受，当前版本: $currentVersion');
      return false;
    } catch (e) {
      if (kDebugMode) print('检查隐私政策状态失败: $e');
      // 出错时保守处理，显示隐私政策
      return true;
    }
  }

  /// 保存用户接受隐私政策
  /// 保存当前版本号和接受日期
  Future<void> acceptPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      await prefs.setString(_keyAcceptedVersion, currentVersion);
      await prefs.setString(_keyAcceptedDate, now);

      if (kDebugMode) {
        print('隐私政策已接受保存: 版本=$currentVersion, 日期=$now');
      }
    } catch (e) {
      if (kDebugMode) print('保存隐私政策接受状态失败: $e');
      // 即使保存失败，也不阻止用户继续使用（优雅降级）
      // 下次启动会重新提示
    }
  }

  /// 获取已接受的版本号
  Future<String?> getAcceptedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAcceptedVersion);
    } catch (e) {
      if (kDebugMode) print('获取已接受版本失败: $e');
      return null;
    }
  }

  /// 获取接受日期
  Future<DateTime?> getAcceptanceDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString(_keyAcceptedDate);
      if (dateStr != null && dateStr.isNotEmpty) {
        return DateTime.parse(dateStr);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('获取接受日期失败: $e');
      return null;
    }
  }

  /// 清除隐私政策接受记录（用于测试）
  Future<void> clearAcceptance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAcceptedVersion);
      await prefs.remove(_keyAcceptedDate);
    } catch (e) {
      if (kDebugMode) print('清除隐私政策接受记录失败: $e');
    }
  }
}
