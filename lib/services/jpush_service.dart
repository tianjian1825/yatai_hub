import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';

/// 极光推送服务
///
/// 接入说明：
/// - Android: manifestPlaceholders 已在 app/build.gradle.kts 配置 JPUSH_APPKEY
/// - iOS: AppKey 通过 setup(appKey: ...) 显式传入
/// - FCM: 海外设备通过 jiguang-google 厂商插件转发离线消息
class JPushService {
  static final JPushService _instance = JPushService._internal();
  factory JPushService() => _instance;
  JPushService._internal();

  static const String _appKey = '147d3e2e76653c9af88b1cdd';
  static const String _channel = 'developer-default';

  /// 与 MainActivity 约定的原生通道（清通知栏用，复用 PushRouter 的通道名）
  static const MethodChannel _pushChannel = MethodChannel('com.suixinpai.push');

  final JPushFlutterInterface _jpush = JPush.newJPush();
  bool _initialized = false;

  /// 设备唯一注册 ID，业务侧用于上报后端绑定用户
  String? _registrationId;
  String? get registrationId => _registrationId;

  /// RID 就绪信号，外部可 await 拿到首次回填的 RID
  final Completer<String> _registrationIdCompleter = Completer<String>();

  /// RID 首次就绪的 Future。用于「awaitRegistrationId 超时放弃」后挂迟到补报：
  /// 首装弱网 / iOS 首启联网授权晚给时，SDK 注册可能远超同步等待窗口，
  /// 注册成功回填 completer 时经此唤醒补报逻辑。可能永不完成（一直注册失败）。
  Future<String> get onRegistrationIdReady => _registrationIdCompleter.future;

  /// 收到自定义消息（前台透传）
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// 收到通知（前台 / 后台都会回调）
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotification =>
      _notificationController.stream;

  /// 用户点击通知打开 App
  final _opentNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onOpenNotification =>
      _opentNotificationController.stream;

  /// 最近一次未消费的「通知点击」事件。
  ///
  /// 冷启动场景下 jpush_flutter 的 dart handler 可能晚于 native 触发，
  /// 此时 broadcast stream 没有 buffer 会丢事件；同步保留一份给 PushRouter 兜底。
  Map<String, dynamic>? _pendingOpenNotification;
  Map<String, dynamic>? get pendingOpenNotification => _pendingOpenNotification;

  /// PushRouter 消费完后清除缓存，避免重复 dispatch。
  void consumePendingOpenNotification() {
    _pendingOpenNotification = null;
  }

  /// 初始化 JPush。
  ///
  /// 必须在用户同意隐私政策后调用。
  Future<void> initialize() async {
    if (_initialized) return;
    // 先置位防并发重入；setup 链路失败时回滚，允许下次登录流程重试
    _initialized = true;
    try {
      _doInitialize();
    } catch (e) {
      _initialized = false;
      rethrow;
    }

    // 冷启动点击推送：此时 resumed 可能早于本次 initialize 完成，
    // 导致生命周期里的 clearBadge 因 SDK 未就绪被跳过，故 init 完成后补清一次。
    await clearBadge();
  }

  void _doInitialize() {
    _jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onReceiveNotification: $message');
        _notificationController.add(message);
      },
      onOpenNotification: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onOpenNotification: $message');
        _pendingOpenNotification = message;
        _opentNotificationController.add(message);
      },
      onReceiveMessage: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onReceiveMessage: $message');
        _messageController.add(message);
      },
      onReceiveNotificationAuthorization: (Map<String, dynamic> message) async {
        if (kDebugMode) {
          print('[JPush] onReceiveNotificationAuthorization: $message');
        }
      },
      onNotifyMessageUnShow: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onNotifyMessageUnShow: $message');
      },
      onInAppMessageShow: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onInAppMessageShow: $message');
      },
      onCommandResult: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onCommandResult: $message');
      },
      onInAppMessageClick: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onInAppMessageClick: $message');
      },
      onConnected: (Map<String, dynamic> message) async {
        if (kDebugMode) print('[JPush] onConnected: $message');
      },
    );

    // 3.0+ 必须先调用 setAuth，sdk 才会联网注册
    _jpush.setAuth(enable: true);

    _jpush.setup(
      appKey: _appKey,
      channel: _channel,
      production: !kDebugMode,
      debug: kDebugMode,
    );

    if (Platform.isIOS) {
      _jpush.applyPushAuthority(
        const NotificationSettingsIOS(sound: true, alert: true, badge: true),
      );
    }

    // 不 await：插件端在 SDK 注册成功前不回调（首装弱网 / iOS 联网授权
    // 未放行时可能挂起数分钟），阻塞会拖住 initialize 之后的 resumePush 等步骤。
    // RID 迟到时经此回填 completer，唤醒挂在 onRegistrationIdReady 上的补报。
    _jpush
        .getRegistrationID()
        .then((rid) {
          if (kDebugMode) print('[JPush] registrationID = $rid');
          if (rid.isEmpty) return;
          _registrationId = rid;
          if (!_registrationIdCompleter.isCompleted) {
            _registrationIdCompleter.complete(rid);
          }
        })
        .catchError((e) {
          if (kDebugMode) print('[JPush] 获取 registrationID 失败: $e');
        });
  }

  /// 等待 RID 就绪。已就绪立即返回；未就绪则等待 SDK 回调，最长 [timeout]。
  ///
  /// 注意：在用户尚未同意隐私政策、JPush 未 initialize 时返回 null。
  Future<String?> awaitRegistrationId({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_registrationId != null && _registrationId!.isNotEmpty) {
      return _registrationId;
    }
    if (!_initialized) return null;
    try {
      return await _registrationIdCompleter.future.timeout(timeout);
    } on TimeoutException {
      if (kDebugMode) print('[JPush] awaitRegistrationId 超时');
      return null;
    }
  }

  /// 停止接收推送（退登场景使用）。再次登录时调用 [resumePush]。
  Future<void> stopPush() async {
    if (!_initialized) return;
    try {
      _jpush.stopPush();
    } catch (e) {
      if (kDebugMode) print('[JPush] stopPush 失败: $e');
    }
  }

  /// 恢复接收推送
  Future<void> resumePush() async {
    if (!_initialized) return;
    try {
      _jpush.resumePush();
    } catch (e) {
      if (kDebugMode) print('[JPush] resumePush 失败: $e');
    }
  }

  /// 绑定 alias（建议使用业务用户 ID）
  Future<void> setAlias(String alias) async {
    if (!_initialized) return;
    try {
      await _jpush.setAlias(alias);
    } catch (e) {
      if (kDebugMode) print('[JPush] setAlias 失败: $e');
    }
  }

  /// 解绑 alias（退登时调用）
  Future<void> deleteAlias() async {
    if (!_initialized) return;
    try {
      await _jpush.deleteAlias();
    } catch (e) {
      if (kDebugMode) print('[JPush] deleteAlias 失败: $e');
    }
  }

  /// 设置标签（如角色、地区）
  Future<void> setTags(List<String> tags) async {
    if (!_initialized) return;
    try {
      await _jpush.setTags(tags);
    } catch (e) {
      if (kDebugMode) print('[JPush] setTags 失败: $e');
    }
  }

  /// 清空角标（iOS）
  Future<void> clearBadge() async {
    if (!_initialized || !Platform.isIOS) return;
    try {
      await _jpush.setBadge(0);
    } catch (e) {
      if (kDebugMode) print('[JPush] clearBadge 失败: $e');
    }
  }

  /// 清空通知栏全部通知。
  ///
  /// 用于「App 在前台且正停留在某任务群聊页」时，收到该会话推送通知后清掉系统
  /// 通知栏（jpush_flutter 无法据业务 message_id 精确定位 OS 通知 id，故全清——
  /// 用户既在前台聊天，清掉托盘通知是合理行为）。
  ///
  /// Android 优先走系统级 NotificationManager.cancelAll()（按 UID 清，无视贴出
  /// 通知的进程/channel）：JPushInterface.clearAllNotifications 在部分国产 ROM 上
  /// 对「长连接连上后补投」的通知清不掉（不在 SDK 记账表里），native cancelAll 才可靠。
  /// 同时不依赖 [_initialized]，覆盖冷启动 init 未完成时进入会话页的清除。
  Future<void> clearAllNotifications() async {
    if (Platform.isAndroid) {
      try {
        await _pushChannel.invokeMethod('clearAllNotifications');
      } catch (e) {
        if (kDebugMode) print('[JPush] native clearAllNotifications 失败: $e');
      }
    }
    // 极光侧再清一次：同步其内部通知计数 / iOS 走此路径
    if (!_initialized) return;
    try {
      await _jpush.clearAllNotifications();
    } catch (e) {
      if (kDebugMode) print('[JPush] clearAllNotifications 失败: $e');
    }
  }

  /// 系统通知权限是否开启。
  ///
  /// iOS 仅 Authorized 视为开启（denied / 未请求过均为 false）；
  /// Android 查 NotificationManagerCompat.areNotificationsEnabled。
  /// 未初始化或查询异常返回 null（调用方视为「未知，不提示」）。
  Future<bool?> isNotificationEnabled() async {
    if (!_initialized) return null;
    try {
      return await _jpush.isNotificationEnabled();
    } catch (e) {
      if (kDebugMode) print('[JPush] isNotificationEnabled 失败: $e');
      return null;
    }
  }

  /// 打开系统的本 App 通知设置页。
  ///
  /// iOS 无法二次拉起系统授权弹窗（denied 后只能去设置），此 API 打开
  /// 本 App 的系统设置页；Android 8+ 打开本 App 通知设置页。
  void openNotificationSettings() {
    if (!_initialized) return;
    try {
      _jpush.openSettingsForNotification();
    } catch (e) {
      if (kDebugMode) print('[JPush] openNotificationSettings 失败: $e');
    }
  }
}
