import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// 远程图片 / 视频的「保存到相册」与「分享」工具
///
/// 复用 material_preview_page 的下载 + gal + share_plus 实现，
/// 供留言板等需要长按保存 / 分享的场景调用。
class MediaSaver {
  static const String _album = '亚太HUB';

  static const List<String> _videoExtensions = [
    'mp4', 'avi', 'mov', 'mkv', 'flv', 'webm',
    'm4v', '3gp', '3g2', 'wmv', 'mpeg', 'mpg',
  ];

  /// 根据 URL 判断是否视频
  ///
  /// 优先按「路径部分」的扩展名判断；NAS 等场景可能把文件名放在 query
  /// （如 `?path=xxx.mp4`）或路径中带后缀参数，故再兜底扫描整个 URL 是否
  /// 出现 `.mp4` 等视频后缀，避免视频被误判成图片。
  static bool isVideo(String url) {
    final lower = url.toLowerCase().trim();
    // 1. 路径部分（去掉 query）末尾扩展名
    final path = lower.split('?')[0];
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 &&
        _videoExtensions.contains(path.substring(lastDot + 1))) {
      return true;
    }
    // 2. 兜底：整个 URL 中出现 .<视频后缀>（应对文件名在 query 中的情况）
    for (final ext in _videoExtensions) {
      if (lower.contains('.$ext')) return true;
    }
    return false;
  }

  static String _extension(String url) {
    final path = Uri.parse(url.split('?')[0]).path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1) return path.substring(lastDot);
    return '.jpg';
  }

  /// 弹出「保存到相册 / 分享」操作菜单
  static void showActionSheet(BuildContext context, String url) {
    final video = isVideo(url);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(video ? '保存视频到相册' : '保存图片到相册'),
              onTap: () {
                Navigator.pop(sheetContext);
                saveToGallery(context, url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(sheetContext);
                share(context, url);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  /// 下载并保存到系统相册
  static Future<void> saveToGallery(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final video = isVideo(url);

    // iOS 需先确认相册权限（gal 比 permission_handler 更可靠）
    if (Platform.isIOS) {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (context.mounted) _showPermissionDialog(context);
          return;
        }
      }
    }

    messenger.showSnackBar(SnackBar(
      content: Text(video ? '正在下载视频...' : '正在保存图片...'),
      duration: Duration(seconds: video ? 2 : 1),
    ));

    try {
      final clean = Uri.encodeFull(url.split('?')[0]);
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/mb_${DateTime.now().millisecondsSinceEpoch}${_extension(url)}';
      await Dio().download(clean, filePath);

      if (video) {
        await Gal.putVideo(filePath, album: _album);
      } else {
        await Gal.putImage(filePath, album: _album);
      }

      final file = File(filePath);
      if (await file.exists()) await file.delete();

      messenger.showSnackBar(SnackBar(
        content: Text(video ? '视频保存成功' : '图片保存成功'),
      ));
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_galMessage(e))));
    } catch (e) {
      if (kDebugMode) print('[留言板保存] $e');
      messenger.showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 下载到临时目录后调用系统分享
  static Future<void> share(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final video = isVideo(url);

    messenger.showSnackBar(SnackBar(
      content: Text(video ? '正在准备分享视频...' : '正在准备分享图片...'),
      duration: Duration(seconds: video ? 2 : 1),
    ));

    try {
      final clean = Uri.encodeFull(url.split('?')[0]);
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/mb_share_${DateTime.now().millisecondsSinceEpoch}${_extension(url)}';
      await Dio().download(clean, filePath);

      await SharePlus.instance
          .share(ShareParams(files: [XFile(filePath)], text: '分享'));

      // 延迟删除，确保分享流程读取完成
      Future.delayed(const Duration(seconds: 5), () async {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      });
    } catch (e) {
      if (kDebugMode) print('[留言板分享] $e');
      messenger.showSnackBar(const SnackBar(content: Text('分享失败')));
    }
  }

  static String _galMessage(GalException e) {
    switch (e.type) {
      case GalExceptionType.accessDenied:
        return '相册权限被拒绝，请在设置中开启';
      case GalExceptionType.notEnoughSpace:
        return '存储空间不足';
      case GalExceptionType.notSupportedFormat:
        return '不支持的文件格式';
      case GalExceptionType.unexpected:
        return '保存失败';
    }
  }

  static void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要相册权限'),
        content: const Text('保存图片和视频需要相册权限，请在设置中开启"添加照片"权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
