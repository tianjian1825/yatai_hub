import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:yatai_hub/pages/main_page.dart';
import 'package:yatai_hub/pages/material_upload_page.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';

/// 系统分享接收器
///
/// 处理从相册 / 文件管理「分享到本 App」进来的图片 / 视频 / 文件：
/// 已登录（非游客）→ 直接加入素材上传队列并切到「上传」Tab；
/// 未登录或游客模式 → 静默忽略（用户决定的处理策略）。
///
/// 设计仿 [PushRouterService]：
/// - 启动期 [start] 始终订阅热接收流，并取一次冷启动数据；
/// - [_pending] 缓存最后一批未消费的文件路径；
/// - 冷启动时上传页可能尚未挂载，由 [MaterialUploadPageState] 在异步初始化
///   完成后调用 [consumePending] 触发入队。
class ShareIntentService {
  static final ShareIntentService _instance = ShareIntentService._internal();
  factory ShareIntentService() => _instance;
  ShareIntentService._internal();

  StreamSubscription<List<SharedFile>>? _sub;
  List<String>? _pending;
  bool _started = false;

  /// 启动分享接收。多次调用幂等。
  void start() {
    if (_started) return;
    _started = true;

    // 热接收：App 运行期间用户从外部分享进来
    _sub = FlutterSharingIntent.instance.getMediaStream().listen(
      _onShared,
      onError: (Object e) {
        if (kDebugMode) print('[ShareIntent] getMediaStream 错误: $e');
      },
    );

    // 冷启动：App 由分享动作唤起，取一次初始数据后 reset 避免重复消费
    // ignore: discarded_futures
    FlutterSharingIntent.instance.getInitialSharing().then((files) {
      if (files.isEmpty) return;
      _onShared(files);
      // ignore: discarded_futures
      FlutterSharingIntent.instance.reset();
    }).catchError((Object e) {
      if (kDebugMode) print('[ShareIntent] getInitialSharing 错误: $e');
    });
  }

  /// 上传页异步初始化完成后调用，消费冷启动期间到达的分享。
  void consumePending() {
    if (_pending != null && _pending!.isNotEmpty) {
      _dispatch();
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    _pending = null;
  }

  Future<void> _onShared(List<SharedFile> files) async {
    // 仅接收带本地路径的媒体/文件类型；TEXT/URL/WEB_SEARCH 无文件可上传，丢弃。
    // 注：音频（如小米录音机）由插件归为 FILE 类型，在此被接收。
    final paths = files
        .where((f) =>
            f.value != null &&
            f.value!.isNotEmpty &&
            (f.type == SharedMediaType.IMAGE ||
                f.type == SharedMediaType.VIDEO ||
                f.type == SharedMediaType.FILE ||
                f.type == SharedMediaType.OTHER))
        .map((f) => f.value!)
        .toList();
    if (paths.isEmpty) {
      if (kDebugMode) print('[ShareIntent] 分享内容无可上传文件，忽略');
      return;
    }

    // 登录态 + 游客校验：未登录或游客一律静默忽略
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) {
      if (kDebugMode) print('[ShareIntent] 未登录，静默忽略分享 ${paths.length} 个文件');
      return;
    }
    final isGuest = await GuestModeService().isGuestMode();
    if (isGuest) {
      if (kDebugMode) print('[ShareIntent] 游客模式，静默忽略分享 ${paths.length} 个文件');
      return;
    }

    _pending = paths;
    _dispatch();
  }

  void _dispatch() {
    final paths = _pending;
    if (paths == null || paths.isEmpty) return;

    final upload = MaterialUploadPageState.activeInstance;
    final main = MainPageState.activeInstance;
    if (upload == null || main == null) {
      // 上传页尚未挂载（冷启动 / 仍停在登录页）→ 保留 _pending，等 consumePending
      if (kDebugMode) print('[ShareIntent] 上传页未就绪，缓存待消费 ${paths.length} 个文件');
      return;
    }

    _pending = null;
    main.switchToUpload();
    // 上传页在 IndexedStack 常驻，先切 Tab 再入队即可正确刷新
    // ignore: discarded_futures
    upload.ingestSharedFiles(paths);
  }
}
