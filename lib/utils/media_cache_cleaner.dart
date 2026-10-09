import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 选择图片 / 视频上传完成后，清理 image_picker / file_picker 产生的临时副本
///
/// image_picker 在选择时会把文件（含 imageQuality 压缩后的 scaled_ 副本）复制到
/// 应用缓存目录，上传成功后这些副本即无用。逻辑对齐 UploadQueueManager 的
/// 缓存清理：只删缓存目录中的文件，不动用户原始文件。
class MediaCacheCleaner {
  /// 清理单个已上传的本地临时文件（及其 scaled_ 原始副本）
  static Future<void> cleanPickedFile(String localPath) async {
    if (localPath.isEmpty) return;
    try {
      final file = File(localPath);
      if (!file.existsSync()) return;

      // 收集缓存目录
      final cachePaths = <String>[];
      try {
        cachePaths.add((await getTemporaryDirectory()).path);
      } catch (_) {}
      if (Platform.isAndroid) {
        try {
          final dirs = await getExternalCacheDirectories();
          if (dirs != null) cachePaths.addAll(dirs.map((d) => d.path));
        } catch (_) {}
      }

      final filePath = file.path;
      final isCacheFile = cachePaths.any((p) => filePath.startsWith(p)) ||
          filePath.contains('image_picker') ||
          filePath.contains('file_picker') ||
          filePath.contains('/cache/') ||
          filePath.contains('\\cache\\');
      // 非缓存文件（可能是用户原始文件），不删除
      if (!isCacheFile) return;

      await file.delete();

      // image_picker 使用 imageQuality 时会生成 scaled_ 压缩副本，
      // 同时残留原始副本，一并清理
      final fileName = filePath.split(Platform.pathSeparator).last;
      if (fileName.startsWith('scaled_')) {
        final originalName = fileName.substring(7);
        final dir = file.parent;
        try {
          if (await dir.exists()) {
            await for (final entity
                in dir.list(recursive: true, followLinks: false)) {
              if (entity is File &&
                  entity.path.split(Platform.pathSeparator).last ==
                      originalName) {
                try {
                  await entity.delete();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('[临时文件清理] 失败: $localPath - $e');
    }
  }

  /// 批量清理
  static Future<void> cleanPickedFiles(Iterable<String> localPaths) async {
    for (final p in localPaths) {
      await cleanPickedFile(p);
    }
  }
}
