import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/widgets/bottom_tabbar.dart';
import 'package:yatai_hub/widgets/notification_permission_sheet.dart';
import 'package:yatai_hub/pages/material_upload_page.dart';
import 'package:yatai_hub/pages/part_time/part_time_page.dart';
import 'package:yatai_hub/pages/chat/chat_conversations_page.dart';
import 'package:yatai_hub/pages/user_center_page.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/services/push_router_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/chat_message_repository.dart';

/// 底栏 Tab 种类（声明式，便于动态「消息」Tab 插拔时安全计算索引）
enum _MainTab { partTime, chat, upload, my }

/// 主页面 - 包含底部导航栏和页面切换
class MainPage extends StatefulWidget {
  final int initialIndex;

  const MainPage({super.key, this.initialIndex = 0});

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  /// 当前活跃的 MainPage State 实例（用于 PushRouter 等外部模块跨页面调度方法）。
  static MainPageState? _activeInstance;
  static MainPageState? get activeInstance => _activeInstance;

  static const String _keyShowChatTab = 'show_chat_tab';

  late int _currentIndex;
  bool _isGuest = false;

  /// 「消息」Tab：非兼职常显（要用通讯录发私聊），兼职仅在有会话时显示。
  /// 默认隐藏，`show_chat_tab` 持久化「上次是否有会话」用于冷启动秒显。
  bool _showChatTab = false;
  bool _chatHasUnread = false;

  StreamSubscription<void>? _convSub;
  StreamSubscription<ChatTarget>? _unreadSub;
  StreamSubscription<ChatTarget>? _readSub;

  @override
  void initState() {
    super.initState();
    _activeInstance = this;
    _currentIndex = widget.initialIndex;
    _initialize();
    // MainPage 挂载完毕后消费冷启动期间缓存的推送跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushRouterService().consumePending();
    });
    // 延迟检测系统通知权限：错开启动期的推送跳转/系统授权弹窗（iOS 首启
    // applyPushAuthority 弹窗期间不宜叠加），关闭则从底部提示引导开启
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // ignore: discarded_futures
        NotificationPermissionSheet.maybeShow(context);
      }
    });
    // 被拉入新群 / 新消息 → 点亮「消息」Tab + 红点
    _convSub = ParttimeChatService().onConversationsChanged.listen((_) {
      _checkChatTab();
    });
    _unreadSub = ParttimeChatService().onUnreadChanged.listen((_) {
      if (mounted && !_chatHasUnread) setState(() => _chatHasUnread = true);
    });
    // 某会话已读后重算「消息」Tab 红点（是否还有未读会话）
    _readSub = ParttimeChatService().onTaskRead.listen((_) {
      _checkChatTab();
    });
  }

  @override
  void dispose() {
    _convSub?.cancel();
    _unreadSub?.cancel();
    _readSub?.cancel();
    if (identical(_activeInstance, this)) {
      _activeInstance = null;
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final isGuest = await GuestModeService().isGuestMode();
    _isGuest = isGuest;

    if (mounted) {
      setState(() {});
    }

    // 群聊：决定是否显示「消息」Tab（非游客）
    if (!isGuest) {
      // ignore: discarded_futures
      _checkChatTab();
    }
  }

  /// 拉取会话列表，决定「消息」Tab 显隐与红点（启动 + 被拉入新群时调用）
  ///
  /// 显隐规则：**非兼职账号（roleid≠275）常显** —— 他们有通讯录权限，Tab 是发起
  /// 私聊的唯一入口，若按「有会话才显示」，零会话的人永远进不去。兼职仍按有会话
  /// 才显示（他们不能主动发起私聊）。
  ///
  /// 两个请求各管一件事，并发发出：
  /// - 显隐看 conversations 的 `total`（会话总数），`page_size=1` 只为省传输，
  ///   后端本来就是全量组装后 array_slice；
  /// - 红点看 `chat/unread_count`（task_id=0 汇总三类会话，不受分页影响）。
  ///   以前是拿会话列表第 1 页 20 条 `any(unread>0)`，未读会话排在 20 名之外时
  ///   红点就漏了。
  ///
  /// 多事件源（onConversationsChanged / onTaskRead / 启动）会并发触发本方法，
  /// 拉取乱序返回时，「已读后(unread=0)」的结果可能被「读前突发(unread>0)」的过期
  /// 响应覆盖，导致红点清不掉。用代次标记，只让最后一次发起的拉取写入状态。
  int _chatTabCheckGen = 0;
  Future<void> _checkChatTab() async {
    if (_isGuest) return;
    final gen = ++_chatTabCheckGen;
    final isPartTime = await UserService().isPartTimeUser();
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_keyShowChatTab) ?? false;
    if ((cached || !isPartTime) && !_showChatTab && mounted) {
      _setShowChatTab(true);
    }
    final convFuture = ChatMessageRepository().fetchConversations(
      page: 1,
      pageSize: 1,
    );
    final unreadFuture = ParttimeChatService().getAllUnread();
    final r = await convFuture;
    final unread = await unreadFuture;
    if (!mounted || gen != _chatTabCheckGen) return; // 过期结果丢弃
    final has = r.message == null && (r.total > 0 || r.list.isNotEmpty);
    final hasUnread = unread.total > 0;
    await prefs.setBool(_keyShowChatTab, has); // 缓存只记「有无会话」这一事实
    final show = has || !isPartTime;
    if (show != _showChatTab || hasUnread != _chatHasUnread) {
      _setShowChatTab(show, hasUnread: hasUnread);
    }
  }

  /// 切换「消息」Tab 显隐，并把 _currentIndex 重映射到原 Tab，避免错位
  void _setShowChatTab(bool show, {bool? hasUnread}) {
    final before = _visibleTabs;
    final currentTab = (_currentIndex >= 0 && _currentIndex < before.length)
        ? before[_currentIndex]
        : null;
    setState(() {
      _showChatTab = show;
      if (hasUnread != null) _chatHasUnread = hasUnread;
      final after = _visibleTabs;
      if (currentTab != null) {
        final ni = after.indexOf(currentTab);
        _currentIndex = ni >= 0 ? ni : _currentIndex.clamp(0, after.length - 1);
      }
    });
  }

  // 各页面 GlobalKey（保持 IndexedStack 重建时的 State）
  final GlobalKey<PartTimePageState> _partTimePageKey =
      GlobalKey<PartTimePageState>();
  final GlobalKey<ChatConversationsPageState> _chatPageKey =
      GlobalKey<ChatConversationsPageState>();
  final GlobalKey<State<MaterialUploadPage>> _uploadPageKey =
      GlobalKey<State<MaterialUploadPage>>();
  final GlobalKey<State<UserCenterPage>> _userCenterPageKey =
      GlobalKey<State<UserCenterPage>>();

  /// 当前可见 Tab 列表（顺序即底栏顺序）
  List<_MainTab> get _visibleTabs {
    final tabs = <_MainTab>[_MainTab.partTime];
    if (_showChatTab) tabs.add(_MainTab.chat);
    tabs.add(_MainTab.upload);
    tabs.add(_MainTab.my);
    return tabs;
  }

  Widget _pageFor(_MainTab tab) {
    switch (tab) {
      case _MainTab.partTime:
        return PartTimePage(key: _partTimePageKey);
      case _MainTab.chat:
        return ChatConversationsPage(key: _chatPageKey);
      case _MainTab.upload:
        return MaterialUploadPage(key: _uploadPageKey);
      case _MainTab.my:
        return UserCenterPage(key: _userCenterPageKey);
    }
  }

  BottomTabItem _tabItemFor(_MainTab tab) {
    switch (tab) {
      case _MainTab.partTime:
        return const BottomTabItem(
          label: '兼职',
          assetIcon: 'assets/images/tab/home.png',
          assetActiveIcon: 'assets/images/tab/home-light.png',
          materialIcon: Icons.work_outline,
        );
      case _MainTab.chat:
        return BottomTabItem(
          label: '消息',
          assetIcon: 'assets/images/tab/chat.png',
          assetActiveIcon: 'assets/images/tab/chat-light.png',
          materialIcon: Icons.forum_outlined,
          showBadge: _chatHasUnread,
        );
      case _MainTab.upload:
        return const BottomTabItem(
          label: '上传',
          assetIcon: 'assets/images/tab/upload.png',
          assetActiveIcon: 'assets/images/tab/upload-light.png',
          materialIcon: Icons.cloud_upload_outlined,
        );
      case _MainTab.my:
        return const BottomTabItem(
          label: '我的',
          assetIcon: 'assets/images/tab/my.png',
          assetActiveIcon: 'assets/images/tab/my-light.png',
          materialIcon: Icons.person_outline,
        );
    }
  }

  /// 切到「兼职」主 Tab，可选切到指定子 Tab。
  void switchToPartTime({int? subTab}) {
    final i = _visibleTabs.indexOf(_MainTab.partTime);
    if (i < 0) return;
    if (_currentIndex != i) {
      setState(() => _currentIndex = i);
    }
    if (subTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _partTimePageKey.currentState?.switchToTab(subTab);
      });
    }
  }

  /// 切到「上传」主 Tab（系统分享接收入口调用）。
  void switchToUpload() {
    final i = _visibleTabs.indexOf(_MainTab.upload);
    if (i < 0) return;
    if (_currentIndex != i) {
      setState(() => _currentIndex = i);
    }
  }

  void _onTap(int index) {
    FocusScope.of(context).unfocus();
    final tabs = _visibleTabs;
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];

    if (index == _currentIndex) {
      // 双击当前 Tab → 回到顶部 / 刷新
      switch (tab) {
        case _MainTab.partTime:
          _partTimePageKey.currentState?.refreshToTop();
          break;
        case _MainTab.chat:
          _chatPageKey.currentState?.refreshToTop();
          break;
        default:
          break;
      }
      return;
    }

    setState(() => _currentIndex = index);
    if (tab == _MainTab.my) {
      (_userCenterPageKey.currentState as dynamic)?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs;
    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: IndexedStack(
          index: safeIndex,
          children: [for (final t in tabs) _pageFor(t)],
        ),
        bottomNavigationBar: BottomTabbar(
          currentIndex: safeIndex,
          items: [for (final t in tabs) _tabItemFor(t)],
          onTap: _onTap,
        ),
        extendBody: true,
      ),
    );
  }
}
