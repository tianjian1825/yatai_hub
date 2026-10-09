import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yatai_hub/main.dart';
import 'package:yatai_hub/pages/main_page.dart';
import 'package:yatai_hub/pages/part_time/part_time_task_detail_page.dart';
import 'package:yatai_hub/pages/chat/chat_page.dart';
import 'package:yatai_hub/pages/part_time/parttime_record_detail_page.dart';
import 'package:yatai_hub/pages/part_time/settlement_detail_page.dart';
import 'package:yatai_hub/pages/part_time/part_time_pending_page.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/services/jpush_service.dart';
import 'package:yatai_hub/services/user_service.dart';

/// 推送跳转路由器
///
/// 协议（与后端约定，详见 PR 描述）：
/// - `action = open_part_time_hall`        → 兼职 Tab → 子 Tab「接单列表」
/// - `action = open_part_time_task` + `task_id` → 兼职 Tab → push PartTimeTaskDetailPage
/// - `action = open_part_time_clock` + `clock_id` → push ParttimeRecordDetailPage（打卡记录详情）
/// - `action = open_part_time_settlement` + `settle_id` → push SettlementDetailPage（结算单详情）
/// - `action = open_part_time_register`     → PartTimePendingPage（审核中 / 驳回原因 + 重新提交，已通过自动进主 App）
///
/// 校验：登录态 + 非游客 + 兼职用户（roleid=275），任一不满足静默忽略。
/// 例外：`open_part_time_comment` / `open_part_time_register` 跨角色，仅校验登录态 + 非游客。
/// 冷启动：用户点通知唤起 App 时，extras 可能在 MainPage 挂载前到达；
/// [_pending] 缓存最后一次未消费的动作，等 [consumePending] 触发。
class PushRouterService {
  static final PushRouterService _instance = PushRouterService._internal();
  factory PushRouterService() => _instance;
  PushRouterService._internal();

  static const String _actionHall = 'open_part_time_hall';
  static const String _actionTask = 'open_part_time_task';
  static const String _actionComment = 'open_part_time_comment';
  static const String _actionClock = 'open_part_time_clock';
  static const String _actionSettlement = 'open_part_time_settlement';
  static const String _actionRegister = 'open_part_time_register';

  /// 与 Android MainActivity 约定的推送跳转通道
  static const MethodChannel _nativeChannel = MethodChannel(
    'com.suixinpai.push',
  );

  StreamSubscription<Map<String, dynamic>>? _sub;
  Map<String, dynamic>? _pending;
  bool _started = false;

  /// 同一通知的去重签名 + 时间戳。
  /// 部分 ROM（如 MIUI）点击同一条通知会**同时**触发极光主通道
  /// （onOpenNotification）与厂商通道（onNewIntent → JMessageExtra），
  /// 导致同一动作派发两次（push 两个 ChatPage，需返回两次）。
  /// 按业务字段签名 + 短时间窗去重，避免重复跳转。
  String? _lastSignature;
  DateTime? _lastSignatureAt;

  /// 启动推送跳转分发。多次调用幂等。
  ///
  /// 两路事件源（任一触发都会走 [_onOpen]）：
  /// 1. 极光主通道（无 intent 跳转目标）：通过 [JPushService.onOpenNotification]
  /// 2. 厂商通道（FCM/华为/小米/vivo/OPPO/魅族）：极光 SDK ≥ 4.6.0 走 intent
  ///    跳转后不会再触发 onNotifyMessageOpened；改由 MainActivity 从
  ///    intent.extras.JMessageExtra 解析，通过 [_nativeChannel] 推给 dart。
  void start() {
    if (_started) return;
    _started = true;

    // 路径 1：极光主通道 stream + 冷启动缓存兜底
    _sub = JPushService().onOpenNotification.listen(_onOpen);
    final cached = JPushService().pendingOpenNotification;
    if (cached != null) {
      if (kDebugMode) print('[PushRouter] 消费 JPush 冷启动缓存: $cached');
      JPushService().consumePendingOpenNotification();
      _onOpen(cached);
    }

    // 路径 2：原生 channel —— 接收热启动的 onLaunchPushExtras + 主动拉取冷启动缓存
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchPushExtras') {
        final arg = call.arguments;
        if (arg is String && arg.isNotEmpty) {
          _processJMessageExtra(arg);
        }
      }
      return null;
    });
    // ignore: discarded_futures
    _pullLaunchPushExtras();
  }

  Future<void> _pullLaunchPushExtras() async {
    try {
      final raw = await _nativeChannel.invokeMethod<String>(
        'getLaunchPushExtras',
      );
      if (raw == null || raw.isEmpty) return;
      if (kDebugMode) print('[PushRouter] native 冷启动 JMessageExtra: $raw');
      _processJMessageExtra(raw);
    } catch (e) {
      if (kDebugMode) print('[PushRouter] 拉取 native extras 失败: $e');
    }
  }

  /// 解析极光厂商通道注入的 JMessageExtra（外层 JSON，业务 extras 在 n_extras 内）
  void _processJMessageExtra(String raw) {
    try {
      final outer = jsonDecode(raw);
      if (outer is! Map) return;
      final nExtras = outer['n_extras'];
      Map<String, dynamic>? extrasMap;
      if (nExtras is Map) {
        extrasMap = Map<String, dynamic>.from(nExtras);
      } else if (nExtras is String && nExtras.isNotEmpty) {
        try {
          final parsed = jsonDecode(nExtras);
          if (parsed is Map) extrasMap = Map<String, dynamic>.from(parsed);
        } catch (_) {}
      }
      if (extrasMap == null || extrasMap.isEmpty) {
        if (kDebugMode) print('[PushRouter] JMessageExtra 无 n_extras 字段，丢弃');
        return;
      }
      _onOpen({'extras': extrasMap});
    } catch (e) {
      if (kDebugMode) print('[PushRouter] 解析 JMessageExtra 异常: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    _pending = null;
  }

  /// MainPage 挂载完成后调用，消费冷启动期间到达的待处理动作。
  void consumePending() {
    if (_pending != null) {
      // ignore: discarded_futures
      _dispatch();
    }
  }

  void _onOpen(Map<String, dynamic> message) {
    final extras = _extractExtras(message);
    if (extras == null) {
      if (kDebugMode) print('[PushRouter] 未识别的通知 payload: $message');
      return;
    }
    final action = extras['action']?.toString();
    if (action == null || action.isEmpty) return;

    // 去重：两路事件源（极光主通道 + 厂商通道 intent）在部分 ROM 会同时触发，
    // 同一通知的业务字段完全一致，5s 内相同签名只派发一次。
    final sig = _signature(extras);
    final now = DateTime.now();
    if (_lastSignature == sig &&
        _lastSignatureAt != null &&
        now.difference(_lastSignatureAt!) < const Duration(seconds: 5)) {
      if (kDebugMode) print('[PushRouter] 重复通知派发，忽略: $sig');
      return;
    }
    _lastSignature = sig;
    _lastSignatureAt = now;

    _pending = extras;
    // ignore: discarded_futures
    _dispatch();
  }

  /// 用业务字段拼出去重签名（与平台无关，两路 extras 内容一致）。
  String _signature(Map<String, dynamic> extras) {
    final action = extras['action']?.toString() ?? '';
    const keys = ['task_id', 'message_id', 'clock_id', 'settle_id'];
    final parts = keys.map((k) => '$k=${extras[k] ?? ''}').join('&');
    return '$action|$parts';
  }

  Future<void> _dispatch() async {
    final extras = _pending;
    if (extras == null) return;
    final action = extras['action']?.toString();
    if (action == null || action.isEmpty) {
      _pending = null;
      return;
    }

    // 登录态 + 角色校验
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) {
      if (kDebugMode) print('[PushRouter] 未登录，忽略 action=$action');
      _pending = null;
      return;
    }
    final isGuest = await GuestModeService().isGuestMode();
    if (isGuest) {
      if (kDebugMode) print('[PushRouter] 游客模式，忽略 action=$action');
      _pending = null;
      return;
    }

    // 群聊跨角色：comment 对所有登录非游客用户开放（成员含发起人/客服/管理员），
    // 不限兼职、不切兼职 Tab，直接 push 群聊页并定位 message_id。
    if (action == _actionComment) {
      _dispatchComment(extras);
      return;
    }

    // 注册审核状态（驳回 / 首次通过）：跳转审核状态页。
    // 待审核 / 驳回用户角色可能尚未就绪，故不限兼职，仅校验登录态 + 非游客。
    if (action == _actionRegister) {
      _dispatchRegister();
      return;
    }

    final isPartTime = await UserService().isPartTimeUser();
    if (!isPartTime) {
      if (kDebugMode) print('[PushRouter] 非兼职用户，忽略 action=$action');
      _pending = null;
      return;
    }

    // MainPage 是否就绪：优先取静态注册的活实例，多入口 push 也能命中
    final mainState = MainPageState.activeInstance;
    if (mainState == null) {
      if (kDebugMode) print('[PushRouter] MainPage 尚未挂载，等待消费');
      // 多数情况下 MainPage initState 的 postFrameCallback 会触发 consumePending；
      // 但若用户当前停在登录页 / 审核页（非 MainPage），延迟 800ms 再试一次兜底。
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_pending != null && MainPageState.activeInstance != null) {
          // ignore: discarded_futures
          _dispatch();
        }
      });
      return; // 保留 _pending
    }

    // 关闭可能存在的二级页（如旧的详情页）
    YataiHubApp.navigatorKey.currentState?.popUntil((route) => route.isFirst);

    switch (action) {
      case _actionHall:
        mainState.switchToPartTime(subTab: 1);
        _pending = null;
        break;
      case _actionTask:
        final taskId = _asInt(extras['task_id']);
        if (taskId == null || taskId <= 0) {
          if (kDebugMode) {
            print('[PushRouter] task_id 缺失/无效，降级到接单大厅: $extras');
          }
          mainState.switchToPartTime(subTab: 1);
          _pending = null;
          break;
        }
        mainState.switchToPartTime(subTab: 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          YataiHubApp.navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => PartTimeTaskDetailPage(taskId: taskId),
            ),
          );
        });
        _pending = null;
        break;
      case _actionClock:
        final clockId = _asInt(extras['clock_id']);
        if (clockId == null || clockId <= 0) {
          if (kDebugMode) {
            print('[PushRouter] clock_id 缺失/无效，降级到我已接单: $extras');
          }
          mainState.switchToPartTime(subTab: 0);
          _pending = null;
          break;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          YataiHubApp.navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) =>
                  ParttimeRecordDetailPage.fromClockId(clockId: clockId),
            ),
          );
        });
        _pending = null;
        break;
      case _actionSettlement:
        final settleId = _asInt(extras['settle_id']);
        if (settleId == null || settleId <= 0) {
          if (kDebugMode) {
            print('[PushRouter] settle_id 缺失/无效，降级到我已接单: $extras');
          }
          mainState.switchToPartTime(subTab: 0);
          _pending = null;
          break;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          YataiHubApp.navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => SettlementDetailPage(id: settleId),
            ),
          );
        });
        _pending = null;
        break;
      default:
        if (kDebugMode) print('[PushRouter] 未识别 action: $action');
        _pending = null;
    }
  }

  /// 会话跳转（跨角色，不限兼职）：push 会话页并定位 message_id。
  /// `conv_type=2` 时 task_id 是科室 ID（科室群），`=3` 时是私聊会话 ID（私聊）。
  void _dispatchComment(Map<String, dynamic> extras) {
    final mainState = MainPageState.activeInstance;
    if (mainState == null) {
      if (kDebugMode) print('[PushRouter] MainPage 尚未挂载，等待消费(comment)');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_pending != null && MainPageState.activeInstance != null) {
          // ignore: discarded_futures
          _dispatch();
        }
      });
      return; // 保留 _pending
    }
    final taskId = _asInt(extras['task_id']);
    if (taskId == null || taskId <= 0) {
      if (kDebugMode) print('[PushRouter] 群聊 task_id 缺失/无效: $extras');
      _pending = null;
      return;
    }
    final messageId = _asInt(extras['message_id']);
    // 科室群播报（兼职上下班打卡等）带 conv_type=2，task_id 是科室 ID；
    // 私聊带 3，task_id 是私聊会话 ID；缺省/非法=任务群
    final rawConvType = _asInt(extras['conv_type']) ?? 1;
    final convType = (rawConvType == 2 || rawConvType == 3) ? rawConvType : 1;
    // 推送 extras 带 title（群名，私聊为发送者姓名），用作首屏标题，避免显示占位
    final title = extras['title']?.toString() ?? '';
    YataiHubApp.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      YataiHubApp.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            taskId: taskId,
            convType: convType,
            title: title.isNotEmpty ? title : _fallbackChatTitle(convType),
            locateMessageId: (messageId != null && messageId > 0)
                ? messageId
                : null,
          ),
        ),
      );
    });
    _pending = null;
  }

  /// extras 未带 title 时的标题占位
  String _fallbackChatTitle(int convType) => switch (convType) {
    2 => '科室群聊',
    3 => '私聊',
    _ => '群聊',
  };

  /// 注册审核状态跳转：跳到审核拦截页（[PartTimePendingPage] 审核中 / 驳回共用）。
  /// 该页自洽——已通过会自动 pushReplacement 进入主 App，故无论何种状态都安全。
  /// 用 pushAndRemoveUntil 清栈，避免在已有拦截页上重复堆叠。
  void _dispatchRegister() {
    final navigator = YataiHubApp.navigatorKey.currentState;
    if (navigator == null) {
      if (kDebugMode) print('[PushRouter] navigator 未就绪，等待消费(register)');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_pending != null && YataiHubApp.navigatorKey.currentState != null) {
          // ignore: discarded_futures
          _dispatch();
        }
      });
      return; // 保留 _pending
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PartTimePendingPage()),
      (route) => false,
    );
    _pending = null;
  }

  /// JPush 不同平台 extras 字段格式略不同，统一拍平到 `Map<String, dynamic>`。
  Map<String, dynamic>? _extractExtras(Map<String, dynamic> message) {
    dynamic extras = message['extras'];
    // Android 极光把业务 extras 再包一层 cn.jpush.android.EXTRA，先解开
    if (extras is Map && extras['cn.jpush.android.EXTRA'] != null) {
      extras = extras['cn.jpush.android.EXTRA'];
    }
    if (extras is Map) {
      final m = Map<String, dynamic>.from(extras);
      if (m['action'] != null) return m;
    }
    if (extras is String && extras.isNotEmpty) {
      try {
        final decoded = jsonDecode(extras);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    // 部分平台把字段直接平铺到 message 顶层（iOS 等）
    if (message['action'] != null) return Map<String, dynamic>.from(message);
    return null;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
