import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'list_cache_service.dart';
import 'upload_queue_manager.dart';

/// 缓存管理服务
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    int totalSize = 0;

    try {
      // 1. 图片缓存目录
      final cacheDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(cacheDir);

      // 2. 应用缓存目录
      if (Platform.isAndroid) {
        final externalCacheDir = await getExternalCacheDirectories();
        if (externalCacheDir != null) {
          for (final dir in externalCacheDir) {
            totalSize += await _getDirectorySize(dir);
          }
        }
      }

      // 3. 应用文档目录中的临时文件
      final appDocDir = await getApplicationDocumentsDirectory();
      final tempFiles = appDocDir.listSync().whereType<File>();
      for (final file in tempFiles) {
        if (file.path.contains('temp') || file.path.contains('cache')) {
          totalSize += await file.length();
        }
      }
    } catch (e) {
      debugPrint('获取缓存大小失败: $e');
    }

    return totalSize;
  }

  /// 获取目录大小
  Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('获取目录大小失败: ${dir.path}, $e');
    }
    return size;
  }

  /// 清除所有缓存
  Future<bool> clearAllCache() async {
    try {
      // 1. 清除图片缓存
      await clearImageCache();

      // 2. 清除列表数据缓存
      await ListCacheService().clearAllCache();

      // 3. 清除临时目录
      final cacheDir = await getTemporaryDirectory();
      await _clearDirectory(cacheDir);

      // 4. 清除外部缓存目录 (Android)
      if (Platform.isAndroid) {
        final externalCacheDir = await getExternalCacheDirectories();
        if (externalCacheDir != null) {
          for (final dir in externalCacheDir) {
            await _clearDirectory(dir);
          }
        }
      }

      // 5. 清除SharedPreferences中的其他缓存数据（保留用户登录信息）
      await _clearCachedPreferences();

      // 6. 清理本地文件已被删除的上传任务（从内存和持久化中移除）
      await UploadQueueManager().removeTasksWithMissingFiles();

      return true;
    } catch (e) {
      debugPrint('清除缓存失败: $e');
      return false;
    }
  }

  /// 清除图片缓存
  Future<void> clearImageCache() async {
    try {
      // 清除内存中的图片缓存
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 清除 CachedNetworkImage 的缓存
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      debugPrint('清除图片缓存失败: $e');
    }
  }

  /// 清除目录内容
  Future<void> _clearDirectory(Directory dir) async {
    try {
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            debugPrint('删除文件失败: ${entity.path}, $e');
          }
        }
      }
    } catch (e) {
      debugPrint('清除目录失败: ${dir.path}, $e');
    }
  }

  /// 清除目录内容（跳过指定路径的文件）
  ///
  /// [skipPaths] 需要跳过的文件路径集合，如果文件在某个子目录中，该子目录也会被保留
  Future<void> _clearDirectorySkippingPaths(
    Directory dir,
    Set<String> skipPaths,
  ) async {
    if (skipPaths.isEmpty) {
      // 没有需要跳过的路径，直接清理
      await _clearDirectory(dir);
      return;
    }

    try {
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          try {
            bool shouldSkip = false;

            if (entity is File) {
              shouldSkip = skipPaths.contains(entity.path);
            } else if (entity is Directory) {
              // 如果目录中包含需要跳过的文件，则保留整个目录
              shouldSkip = skipPaths.any(
                (path) => path.startsWith('${entity.path}/'),
              );
            }

            if (shouldSkip) {
              continue;
            }

            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            debugPrint('删除文件失败: ${entity.path}, $e');
          }
        }
      }
    } catch (e) {
      debugPrint('清除目录失败: ${dir.path}, $e');
    }
  }

  /// 清除SharedPreferences中的缓存数据（保留用户登录信息）
  ///
  /// [keepUploadTasks] 是否保留上传任务数据（自动清理时为 true，手动清理时为 false）
  Future<void> _clearCachedPreferences({bool keepUploadTasks = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();

    // 需要保留的key（用户登录信息、用户数据和用户偏好设置）
    final keysToKeep = [
      'user_access_token',
      'user_sign',
      'is_logged_in',
      'user_id',
      'uid',
      'username',
      'user_avatar',
      'user_department',
      'user_department_id',
      'user_center_cache',
      'schedule_flag',
      // 上传页面用户偏好设置（提交后需保留）
      'cached_current_type',
      'cached_category_id',
      'cached_visibility_id',
      'cached_department_ids',
      'cached_departments',
      'cached_upload_region',
    ];

    for (final key in keys) {
      // 只清除缓存相关的key，保留用户信息
      if (key.startsWith('cached_') ||
          key.startsWith('upload_task_') ||
          key.startsWith('department_') ||
          key.contains('cache')) {
        // 自动清理时保留上传任务数据
        if (keepUploadTasks && key.contains('upload_task')) {
          continue;
        }
        if (!keysToKeep.contains(key)) {
          await prefs.remove(key);
        }
      }
    }
  }

  /// 自动清理：缓存超过5GB时自动清理（跳过上传任务文件）
  static const int _autoCleanupThreshold = 5 * 1024 * 1024 * 1024; // 5GB

  Future<bool> autoCleanupIfNeeded() async {
    try {
      final size = await getCacheSize();
      if (size >= _autoCleanupThreshold) {
        debugPrint('[缓存] 缓存大小 ${formatFileSize(size)} 超过5GB，自动清理');

        // 获取活跃上传任务的文件路径，自动清理时需要跳过这些文件
        final uploadPaths = UploadQueueManager().getActiveUploadFilePaths();

        // 1. 清除图片缓存
        await clearImageCache();

        // 2. 清除列表数据缓存
        await ListCacheService().clearAllCache();

        // 3. 清除临时目录（跳过上传文件）
        final cacheDir = await getTemporaryDirectory();
        await _clearDirectorySkippingPaths(cacheDir, uploadPaths);

        // 4. 清除外部缓存目录（跳过上传文件）
        if (Platform.isAndroid) {
          final externalCacheDir = await getExternalCacheDirectories();
          if (externalCacheDir != null) {
            for (final dir in externalCacheDir) {
              await _clearDirectorySkippingPaths(dir, uploadPaths);
            }
          }
        }

        // 5. 清除SharedPreferences缓存但保留上传任务数据
        await _clearCachedPreferences(keepUploadTasks: true);

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[缓存] 自动清理检查失败: $e');
      return false;
    }
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';

    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}
