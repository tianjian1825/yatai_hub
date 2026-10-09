import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 线路设置服务 - 线路已固定为「海外」
///
/// 亚太HUB 固定使用海外线路，不再提供国内/海外切换与 IP 自动检测。
/// [getBrowseRoute] / [getUploadRoute] 恒返回 [routeOverseas]；
/// setter 保留仅为兼容历史调用点，不影响读取结果。
class RouteSettingsService {
  static final RouteSettingsService _instance =
      RouteSettingsService._internal();

  factory RouteSettingsService() => _instance;

  RouteSettingsService._internal();

  // SharedPreferences 键
  static const String _keyBrowseRoute = 'cached_browse_region'; // 浏览线路
  static const String _keyUploadRoute = 'cached_upload_region'; // 上传线路
  static const String _keyAutoDetectEnabled =
      'route_auto_detect_enabled'; // 自动检测标志

  // 线路常量
  static const int routeDomestic = 1; // 国内线路
  static const int routeOverseas = 0; // 海外线路

  /// 获取浏览线路 —— 固定为海外
  Future<int> getBrowseRoute() async {
    return routeOverseas;
  }

  /// 设置浏览线路
  ///
  /// [route] 线路值，1=国内, 0=海外
  Future<bool> setBrowseRoute(int route) async {
    try {
      if (route != routeDomestic && route != routeOverseas) {
        throw ArgumentError('无效的线路值: $route，必须是 0 或 1');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyBrowseRoute, route);

      return true;
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 设置浏览线路失败: $e');
      return false;
    }
  }

  /// 获取上传线路 —— 固定为海外
  Future<int> getUploadRoute() async {
    return routeOverseas;
  }

  /// 设置上传线路
  ///
  /// [route] 线路值，1=国内, 0=海外
  Future<bool> setUploadRoute(int route) async {
    try {
      if (route != routeDomestic && route != routeOverseas) {
        throw ArgumentError('无效的线路值: $route，必须是 0 或 1');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyUploadRoute, route);

      return true;
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 设置上传线路失败: $e');
      return false;
    }
  }

  /// 检查是否启用自动检测
  ///
  /// 默认返回 true（首次启动时启用）
  Future<bool> isAutoDetectEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 如果键不存在，返回 true（首次启动默认启用）
      if (!prefs.containsKey(_keyAutoDetectEnabled)) {
        return true;
      }

      return prefs.getBool(_keyAutoDetectEnabled) ?? true;
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 检查自动检测标志失败: $e');
      return true;
    }
  }

  /// 设置自动检测标志
  ///
  /// [enabled] 是否启用自动检测
  Future<void> setAutoDetectEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoDetectEnabled, enabled);
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 设置自动检测标志失败: $e');
    }
  }

  /// 获取线路描述文本
  String _getRouteDescription(int route) {
    return route == routeDomestic ? '国内' : '海外';
  }

  /// 获取线路描述（公开方法）
  String getRouteDescription(int route) {
    return _getRouteDescription(route);
  }

  /// 判断线路是否为国内
  bool isDomestic(int route) {
    return route == routeDomestic;
  }

  /// 清除所有线路设置
  Future<void> clearSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_keyBrowseRoute);
      await prefs.remove(_keyUploadRoute);
      await prefs.remove(_keyAutoDetectEnabled);
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 清除线路设置失败: $e');
    }
  }

  /// 获取线路设置摘要（用于调试）
  Future<Map<String, dynamic>> getSettingsSummary() async {
    try {
      final browseRoute = await getBrowseRoute();
      final uploadRoute = await getUploadRoute();
      final autoDetect = await isAutoDetectEnabled();

      return {
        'browseRoute': browseRoute,
        'browseRouteDesc': _getRouteDescription(browseRoute),
        'uploadRoute': uploadRoute,
        'uploadRouteDesc': _getRouteDescription(uploadRoute),
        'autoDetectEnabled': autoDetect,
      };
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 获取设置摘要失败: $e');
      return {};
    }
  }

  /// 重置为默认设置
  ///
  /// 浏览线路：国内（1）
  /// 上传线路：海外（0）
  /// 自动检测：启用（true）
  Future<void> resetToDefault() async {
    try {
      await setBrowseRoute(routeDomestic);
      await setUploadRoute(routeOverseas);
      await setAutoDetectEnabled(true);
    } catch (e) {
      if (kDebugMode) print('[RouteSettings] 重置默认设置失败: $e');
    }
  }
}
