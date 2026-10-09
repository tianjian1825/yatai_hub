import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/models/order_entry_meta.dart';
import 'package:yatai_hub/services/schedule_api.dart';

/// 录单元数据缓存服务 - 单例模式
class OrderEntryMetaService {
  static final OrderEntryMetaService _instance =
      OrderEntryMetaService._internal();
  factory OrderEntryMetaService() => _instance;
  OrderEntryMetaService._internal();

  static const String _keyMeta = 'cached_order_entry_meta';
  static const String _keyTimestamp = 'cached_order_entry_meta_timestamp';

  // 缓存有效期：24小时
  static const int _cacheValidDuration = 24 * 60 * 60 * 1000;

  // 内存缓存
  OrderEntryMeta? _meta;

  /// 获取元数据
  Future<OrderEntryMeta?> getMeta({bool forceRefresh = false}) async {
    // 内存缓存命中
    if (_meta != null && !forceRefresh) {
      return _meta;
    }

    // 尝试从磁盘缓存获取
    if (!forceRefresh) {
      final cached = await _loadFromCache();
      if (cached != null) {
        _meta = cached;
        return cached;
      }
    }

    // 从服务器获取
    try {
      final meta = await ScheduleApi.getOrderEntryMeta();
      if (meta != null) {
        _meta = meta;
        await _saveToCache(meta);
      }
      return meta;
    } catch (e) {
      if (kDebugMode) print('[录单元数据] 获取失败: $e');
      // 失败时尝试返回过期缓存
      final cached = await _loadFromCache(ignoreExpiration: true);
      if (cached != null) {
        _meta = cached;
        return cached;
      }
      return null;
    }
  }

  /// 预加载（用于 app 启动或页面初始化）
  Future<void> preload() async {
    try {
      await getMeta();
    } catch (e) {
      if (kDebugMode) print('[录单元数据] 预加载失败: $e');
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _meta = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMeta);
    await prefs.remove(_keyTimestamp);
  }

  Future<OrderEntryMeta?> _loadFromCache({
    bool ignoreExpiration = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!ignoreExpiration) {
        final timestamp = prefs.getInt(_keyTimestamp) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - timestamp > _cacheValidDuration) {
          return null;
        }
      }

      final jsonStr = prefs.getString(_keyMeta);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return OrderEntryMeta.fromJson(json);
      }
    } catch (e) {
      if (kDebugMode) print('[录单元数据] 从缓存加载失败: $e');
    }
    return null;
  }

  Future<void> _saveToCache(OrderEntryMeta meta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(meta.toJson());
      await prefs.setString(_keyMeta, jsonStr);
      await prefs.setInt(_keyTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) print('[录单元数据] 保存缓存失败: $e');
    }
  }
}
