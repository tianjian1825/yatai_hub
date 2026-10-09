import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 列表数据缓存服务
/// 为各类列表数据提供统一的本地缓存功能
/// 支持自定义过期时间和缓存键
class ListCacheService {
  static final ListCacheService _instance = ListCacheService._internal();
  factory ListCacheService() => _instance;
  ListCacheService._internal();

  /// 默认缓存有效期：48小时
  static const int defaultCacheDuration = 48 * 60 * 60 * 1000; // 毫秒

  /// 缓存键前缀
  static const String _keyPrefix = 'list_cache_';
  static const String _timestampSuffix = '_timestamp';

  /// 保存列表缓存
  /// [key] 缓存键（会自动添加前缀）
  /// [data] 要缓存的数据（支持任何可JSON序列化的对象）
  /// [expirationMs] 过期时间（毫秒），默认48小时
  Future<bool> saveCache(
    String key,
    dynamic data, {
    int expirationMs = defaultCacheDuration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_keyPrefix$key';
      final timestampKey = '$cacheKey$_timestampSuffix';

      // 序列化数据
      final jsonString = jsonEncode(data);

      // 保存数据和时间戳
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(cacheKey, jsonString);
      await prefs.setInt(timestampKey, timestamp);

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 保存失败: $key, 错误: $e');
      }
      return false;
    }
  }

  /// 获取列表缓存
  /// [key] 缓存键
  /// [expirationMs] 过期时间（毫秒），默认48小时
  /// [ignoreExpiration] 是否忽略过期检查，默认false
  /// 返回 null 表示缓存不存在或已过期
  Future<dynamic> getCache(
    String key, {
    int expirationMs = defaultCacheDuration,
    bool ignoreExpiration = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_keyPrefix$key';
      final timestampKey = '$cacheKey$_timestampSuffix';

      // 检查缓存是否存在
      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) {
        return null;
      }

      // 检查是否过期
      if (!ignoreExpiration) {
        final timestamp = prefs.getInt(timestampKey);
        if (timestamp == null) {
          return null;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final age = now - timestamp;

        if (age > expirationMs) {
          return null;
        }
      } else {}

      // 反序列化数据
      return jsonDecode(jsonString);
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 读取失败: $key, 错误: $e');
      }
      return null;
    }
  }

  /// 获取缓存时间戳
  /// 返回缓存创建的时间，如果不存在则返回null
  Future<DateTime?> getCacheTimestamp(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_keyPrefix$key';
      final timestampKey = '$cacheKey$_timestampSuffix';

      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 获取时间戳失败: $key, 错误: $e');
      }
      return null;
    }
  }

  /// 检查缓存是否存在且未过期
  Future<bool> isCacheValid(
    String key, {
    int expirationMs = defaultCacheDuration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_keyPrefix$key';
      final timestampKey = '$cacheKey$_timestampSuffix';

      // 检查缓存是否存在
      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) return false;

      // 检查是否过期
      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) return false;

      final now = DateTime.now().millisecondsSinceEpoch;
      final age = now - timestamp;

      return age <= expirationMs;
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 检查缓存有效性失败: $key, 错误: $e');
      }
      return false;
    }
  }

  /// 删除指定缓存
  Future<bool> removeCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_keyPrefix$key';
      final timestampKey = '$cacheKey$_timestampSuffix';

      await prefs.remove(cacheKey);
      await prefs.remove(timestampKey);

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 删除缓存失败: $key, 错误: $e');
      }
      return false;
    }
  }

  /// 清除所有列表缓存
  Future<bool> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 找出所有列表缓存相关的键
      final cacheKeys = keys
          .where((key) => key.startsWith(_keyPrefix))
          .toList();

      // 批量删除
      for (final key in cacheKeys) {
        await prefs.remove(key);
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 清除所有缓存失败: $e');
      }
      return false;
    }
  }

  /// 获取所有缓存的大小（近似值，基于JSON字符串长度）
  Future<int> getTotalCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int totalSize = 0;
      for (final key in keys) {
        if (key.startsWith(_keyPrefix) && !key.endsWith(_timestampSuffix)) {
          final value = prefs.getString(key);
          if (value != null) {
            totalSize += value.length;
          }
        }
      }

      return totalSize;
    } catch (e) {
      if (kDebugMode) {
        print('[列表缓存] 获取缓存大小失败: $e');
      }
      return 0;
    }
  }

  /// 获取缓存的统计信息
  Future<CacheStats> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      final cacheKeys = keys
          .where(
            (key) =>
                key.startsWith(_keyPrefix) && !key.endsWith(_timestampSuffix),
          )
          .toList();

      int totalSize = 0;
      int validCount = 0;
      int expiredCount = 0;

      for (final key in cacheKeys) {
        final value = prefs.getString(key);
        if (value != null) {
          totalSize += value.length;

          // 检查是否过期
          final timestampKey = '$key$_timestampSuffix';
          final timestamp = prefs.getInt(timestampKey);
          if (timestamp != null) {
            final age = DateTime.now().millisecondsSinceEpoch - timestamp;
            if (age <= defaultCacheDuration) {
              validCount++;
            } else {
              expiredCount++;
            }
          }
        }
      }

      return CacheStats(
        totalCount: cacheKeys.length,
        validCount: validCount,
        expiredCount: expiredCount,
        totalSize: totalSize,
      );
    } catch (e) {
      return CacheStats(
        totalCount: 0,
        validCount: 0,
        expiredCount: 0,
        totalSize: 0,
      );
    }
  }
}

/// 缓存统计信息
class CacheStats {
  final int totalCount; // 总缓存数
  final int validCount; // 有效缓存数
  final int expiredCount; // 过期缓存数
  final int totalSize; // 总大小（字节）

  CacheStats({
    required this.totalCount,
    required this.validCount,
    required this.expiredCount,
    required this.totalSize,
  });

  /// 格式化大小
  String get formattedSize {
    if (totalSize < 1024) {
      return '${totalSize}B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  @override
  String toString() {
    return 'CacheStats(总计: $totalCount, 有效: $validCount, 过期: $expiredCount, 大小: $formattedSize)';
  }
}
