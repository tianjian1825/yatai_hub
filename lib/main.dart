import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yatai_hub/pages/main_page.dart';
import 'package:yatai_hub/pages/login_page.dart';
import 'package:yatai_hub/pages/part_time/part_time_pending_page.dart';
import 'package:yatai_hub/pages/material_upload_page.dart';
import 'package:yatai_hub/services/upload_queue_manager.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/services/department_service.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/privacy_policy_service.dart';
import 'package:yatai_hub/services/cache_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/services/jpush_service.dart';
import 'package:yatai_hub/services/push_router_service.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/share_intent_service.dart';
import 'package:yatai_hub/widgets/privacy_policy_dialog.dart';
import 'package:yatai_hub/theme/app_theme.dart';

void main() async {
  // 设置系统状态栏样式
  WidgetsFlutterBinding.ensureInitialized();

  // 限制图片内存缓存，防止长列表滑动时内存持续飙升
  PaintingBinding.instance.imageCache.maximumSize = 100; // 最多缓存100张解码图片
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      100 * 1024 * 1024; // 最多100MB

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // 透明状态栏
      statusBarIconBrightness: Brightness.dark, // 深色图标（适合白色背景）
      statusBarBrightness: Brightness.light, // iOS适配
    ),
  );

  // 初始化服务
  final initResult = await _initializeServices();

  runApp(
    YataiHubApp(
      isLoggedIn: initResult['isLoggedIn'] as bool,
      needsPrivacyPolicy: initResult['needsPrivacyPolicy'] as bool,
      isPartTimePending: initResult['isPartTimePending'] as bool? ?? false,
    ),
  );
}

/// 初始化应用服务
/// 返回登录状态和是否需要显示隐私政策
Future<Map<String, dynamic>> _initializeServices() async {
  // 初始化上传队列管理器（包含网络服务初始化）
  final uploadQueueManager = UploadQueueManager();
  await uploadQueueManager.initialize();

  // 自动缓存清理（非阻塞）
  CacheService().autoCleanupIfNeeded().catchError((e) {
    if (kDebugMode) print('[启动] 自动缓存清理失败: $e');
    return false;
  });

  // 检查隐私政策——启动弹窗暂时屏蔽，需要恢复时还原为：
  // final needsPrivacyPolicy = await PrivacyPolicyService().needsToShowPolicy();
  const needsPrivacyPolicy = false;

  // PushRouter 始终订阅（无 jpush 时 stream 没事件，安全），方便登录后立即接管跳转。
  // 注意：JPush 本体不在此启动期立即 initialize ——
  // 用户卸载重装但未退出登录的场景下，后端仍持有旧 RID 绑定，
  // 若启动就 init SDK，未登录态也会收到推送。改为「真正登录 + 非游客 + 隐私同意」才 init。
  PushRouterService().start();

  // 群聊前台推送编排：订阅透传 onMessage（前台实时刷新）+ onNotification（在会话页时清通知栏）。
  // JPush 未 init 时 stream 无事件，安全；与 PushRouter 一样始终订阅，登录后即生效。
  ParttimeChatService().startForegroundCoordinator();

  // 系统分享接收（相册/文件管理「分享到本 App」）始终订阅；
  // 登录态/游客校验在 ShareIntentService 内部完成，未登录静默忽略。
  ShareIntentService().start();

  // 检查登录状态
  final authService = AuthService();
  final isLoggedIn = await authService.isLoggedIn();

  // 线路已固定为海外，不再做 IP 定位/自动检测

  // 如果已登录，验证登录状态是否有效
  if (isLoggedIn) {
    final isValid = await authService.validateLoginStatus();

    if (isValid) {
      // 登录有效，初始化用户服务
      final userService = UserService();

      // 预加载部门列表（异步，不阻塞启动）
      final departmentService = DepartmentService();
      departmentService.preload().catchError((e) {
        if (kDebugMode) print('预加载部门列表失败: $e');
      });

      // 从服务器获取用户基本信息
      try {
        final success = await userService.initUserInfo();
        if (!success) {
          if (kDebugMode) print('初始化用户信息失败：服务器返回失败');
        }
      } catch (e) {
        if (kDebugMode) print('初始化用户信息异常: $e');
      }

      // 启动时已登录 + 非游客 + 已同意隐私：初始化极光推送并上报 RID
      // bindDeviceRegistrationId 内部会再次 guard 游客，双重保险
      final isGuest = await GuestModeService().isGuestMode();
      if (!isGuest && !needsPrivacyPolicy) {
        JPushService().initialize().catchError((e) {
          if (kDebugMode) print('[启动] 初始化极光推送失败: $e');
        });
      }
      authService.bindDeviceRegistrationId();

      // 兼职用户且尚未审核通过：启动落地到审核中拦截页
      final isPartTimePending = await userService.isPartTimePendingReview();

      return {
        'isLoggedIn': true,
        'needsPrivacyPolicy': needsPrivacyPolicy,
        'isPartTimePending': isPartTimePending,
      };
    } else {
      // 登录已失效
      return {
        'isLoggedIn': false,
        'needsPrivacyPolicy': needsPrivacyPolicy,
        'isPartTimePending': false,
      };
    }
  }

  return {
    'isLoggedIn': false,
    'needsPrivacyPolicy': needsPrivacyPolicy,
    'isPartTimePending': false,
  };
}

class YataiHubApp extends StatefulWidget {
  final bool isLoggedIn;
  final bool needsPrivacyPolicy;
  final bool isPartTimePending;

  /// 全局导航键，供 ApiClient 等服务访问
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const YataiHubApp({
    super.key,
    required this.isLoggedIn,
    required this.needsPrivacyPolicy,
    this.isPartTimePending = false,
  });

  @override
  State<YataiHubApp> createState() => _YataiHubAppState();
}

class _YataiHubAppState extends State<YataiHubApp>
    with WidgetsBindingObserver {
  final UploadQueueManager _uploadQueueManager = UploadQueueManager();

  // 前台恢复时检测停用的并发护栏，避免多次 resume 叠加请求
  bool _checkingDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 检查并显示隐私政策对话框
    if (widget.needsPrivacyPolicy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPrivacyPolicyDialog();
      });
    }

    // 设置初始状态为前台
    _uploadQueueManager.setAppInForeground(true);

    // 设置通知点击回调
    _uploadQueueManager.notificationService.onNotificationTap =
        _handleNotificationTap;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App 进入前台
        _uploadQueueManager.setAppInForeground(true);
        // 对账灵动岛：无进行中的任务则清掉可能残留的灵动岛（兜底卡住场景）
        _uploadQueueManager.reconcileLiveActivity();
        // 取消完成通知（用户已经看到了）
        _uploadQueueManager.notificationService.cancelCompletionNotification();
        // iOS：回到前台清除推送角标。
        // APNs payload 带 badge 会被系统自动置数，点击通知不会自动清，
        // 需 App 主动 setBadge(0)。覆盖「点击推送跳转」「从后台切回」两种场景。
        JPushService().clearBadge();
        // 每次回到前台检测兼职账号是否被管理员停用（在线时被停用场景）
        _checkPartTimeDisabledOnResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App 进入后台
        _uploadQueueManager.setAppInForeground(false);
        _uploadQueueManager.saveTasks();
        break;
      case AppLifecycleState.detached:
        // App 被关闭
        _uploadQueueManager.saveTasks();
        break;
      case AppLifecycleState.hidden:
        // App 隐藏（多窗口模式下）
        _uploadQueueManager.setAppInForeground(false);
        break;
    }
  }

  /// 前台恢复时检测兼职账号是否被管理员停用。
  ///
  /// 覆盖「用户在线时被停用」场景：强制重新拉取 getUserInfo，若 disabled==1
  /// 则把整个路由栈替换为 [PartTimePendingPage]（由其依据 audit_status 区分展示）。
  /// 拦截页已在栈中时跳过——页面自身会在 resume 刷新状态，无需重复 push。
  Future<void> _checkPartTimeDisabledOnResume() async {
    if (_checkingDisabled) return;
    // 拦截页已在前台，交由其自身的 resume 刷新接管
    if (PartTimePendingPage.isActive) return;
    _checkingDisabled = true;
    try {
      final authService = AuthService();
      if (!await authService.isLoggedIn()) return;
      if (await GuestModeService().isGuestMode()) return;
      final userService = UserService();
      if (!await userService.isPartTimeUser()) return;

      final ok = await userService.refreshUserInfo();
      if (!ok) return; // 网络异常等，下次 resume 再试，不打扰用户
      if (await userService.getDisabled() != 1) return; // 正常，无需拦截

      final navigator = YataiHubApp.navigatorKey.currentState;
      if (navigator == null || PartTimePendingPage.isActive) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PartTimePendingPage()),
        (route) => false,
      );
    } catch (e) {
      if (kDebugMode) print('[前台恢复] 兼职停用检测失败: $e');
    } finally {
      _checkingDisabled = false;
    }
  }

  /// 处理通知点击
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;

    // 解析 payload
    if (payload.startsWith('completion:') || payload.startsWith('progress:')) {
      final navigator = YataiHubApp.navigatorKey.currentState;
      if (navigator == null) return;

      // 检查是否包含编辑记录ID
      // payload 格式: completion:upload 或 completion:upload:editId=123
      int? editId;
      if (payload.contains('editId=')) {
        final parts = payload.split('editId=');
        if (parts.length > 1) {
          editId = int.tryParse(parts[1]);
        }
      }

      if (editId != null) {
        // 如果有编辑记录ID，跳转到编辑页面
        navigator
            .pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainPage()),
              (route) => route.isFirst, // 先返回到主页面
            )
            .then((_) {
              // 切到「上传」Tab（索引随「消息」Tab 显隐动态变化，用语义方法定位）
              MainPageState.activeInstance?.switchToUpload();
              // 然后跳转到编辑页面
              navigator.pushNamed(
                '/material-upload',
                arguments: {'editId': editId},
              );
            });
      } else {
        // 普通上传，导航到素材上传页
        navigator
            .pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainPage()),
              (route) => route.isFirst, // 只保留第一个路由（登录页或初始页）
            )
            .then((_) => MainPageState.activeInstance?.switchToUpload());
      }
    }
  }

  /// 显示隐私政策对话框
  Future<void> _showPrivacyPolicyDialog() async {
    if (!mounted) return;

    final context = YataiHubApp.navigatorKey.currentContext;
    if (context == null) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) _showPrivacyPolicyDialog(); // 重试
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PrivacyPolicyDialog(),
    );

    if (accepted == true) {
      final privacyService = PrivacyPolicyService();
      await privacyService.acceptPolicy();
      // 隐私同意后不立即 init jpush，等用户登录态才启动 SDK，
      // 避免未登录态收到旧 RID 绑定下发的推送
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: YataiHubApp.navigatorKey,
      navigatorObservers: [FocusClearObserver()],
      title: '亚太HUB',
      debugShowCheckedModeBanner: false,
      // 本地化配置 - 支持中文
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'), // 中文简体
        Locale('en', 'US'), // 英文
      ],
      theme: AppTheme.light,
      // 根据登录状态决定初始页面
      // 兼职用户（roleid=275）且 disabled=1：拦截到审核中提示页
      home: !widget.isLoggedIn
          ? const LoginPage()
          : widget.isPartTimePending
          ? const PartTimePendingPage()
          : const MainPage(),
      builder: (context, child) {
        return _KeyboardDismissHandler(child: child ?? const SizedBox.shrink());
      },
      // 配置路由
      onGenerateRoute: (settings) {
        if (settings.name == '/material-upload') {
          // 从参数中提取 editId
          final args = settings.arguments as Map<String, dynamic>?;
          final editId = args?['editId'] as int?;

          return MaterialPageRoute(
            builder: (context) => MaterialUploadPage(editId: editId),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

/// 全局键盘收起管理器
///
/// 点击非输入区域时自动收起键盘，同时避免输入框之间切换时键盘闪烁。
/// 注：弹窗关闭后的焦点恢复问题由 [FocusClearObserver] 处理。
class _KeyboardDismissHandler extends StatefulWidget {
  final Widget child;
  const _KeyboardDismissHandler({required this.child});

  @override
  State<_KeyboardDismissHandler> createState() =>
      _KeyboardDismissHandlerState();
}

class _KeyboardDismissHandlerState extends State<_KeyboardDismissHandler> {
  /// 记录 tapDown 时的焦点，用于判断焦点是否在输入框间转移
  FocusNode? _tapDownFocus;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) {
        // 在 tap 处理前记录当前焦点
        _tapDownFocus = FocusManager.instance.primaryFocus;
      },
      onTap: () {
        final prev = _tapDownFocus;
        _tapDownFocus = null;
        if (prev == null) return;
        // 延迟一帧检查：如果焦点没变（点击了非输入区域），才收起键盘
        // 如果焦点转移到了另一个输入框，则不收起（避免闪烁）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final current = FocusManager.instance.primaryFocus;
          if (current != null && identical(current, prev)) {
            current.unfocus();
          }
        });
      },
      child: widget.child,
    );
  }
}

/// 全局弹窗焦点清理观察器
///
/// 监听 Navigator 的路由变化，当弹窗类路由（Dialog、BottomSheet 等）关闭时，
/// 主动清除底层页面 FocusScope 对之前输入框的焦点记忆，
/// 防止弹窗关闭后自动聚焦到之前的输入框并拉起键盘。
///
/// 相比在 didChangeMetrics 里全局拦截键盘收起事件，此方案只针对弹窗关闭场景，
/// 不会干扰用户在输入框之间的正常切换。
class FocusClearObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 只处理弹窗类路由（Dialog、BottomSheet 等 PopupRoute 子类）
    if (route is PopupRoute) {
      // 延后一帧执行，确保路由动画完成后再清理焦点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentFocus = FocusManager.instance.primaryFocus;
        if (currentFocus != null) {
          currentFocus.unfocus();
        }
      });
    }
  }
}
