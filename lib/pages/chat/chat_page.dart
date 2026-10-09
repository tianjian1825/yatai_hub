import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_query.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/models/upload_file.dart';
import 'package:yatai_hub/pages/part_time/part_time_task_detail_page.dart';
import 'package:yatai_hub/services/chat_context_service.dart';
import 'package:yatai_hub/services/chat_message_repository.dart';
import 'package:yatai_hub/services/jpush_service.dart';
import 'package:yatai_hub/services/nas_upload_service.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/utils/media_cache_cleaner.dart';
import 'package:yatai_hub/utils/media_saver.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_members_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_message_bubble.dart';
import 'package:yatai_hub/widgets/chat/chat_user_card_sheet.dart';
import 'package:yatai_hub/widgets/chat/client_profile_sheet.dart';
import 'package:yatai_hub/widgets/chat/hospital_info_sheet.dart';
import 'package:yatai_hub/widgets/chat/mention_picker_sheet.dart';

/// 「会话」全屏页（任务群 / 科室群 / 私聊共用）
///
/// 跨角色（发起人/兼职执行人/责任客服/管理员）均可进入。
/// 反向列表（最新在底）、本地秒显+网络对齐、after_id 增量、引用跳转定位、撤回、@提及。
///
/// [convType]=1 任务群（[taskId]=任务 ID）、2 科室群（[taskId]=科室 ID）、
/// 3 私聊（[taskId]=私聊会话 ID）。
/// - 科室群没有任务上下文，菜单里只保留「群成员」，成员也不可增删（后端
///   `can_manage=false`）。
/// - 私聊不是群：**没有右上角菜单**（任务详情/群成员/两个查询都不适用，成员管理
///   接口对 conv_type=3 也一律被后端拒绝），且**没有 @ 功能**（`mention_*` 恒空）。
class ChatPage extends StatefulWidget {
  final int taskId;
  final String title;

  /// 会话类型：1=任务群（默认）2=科室群 3=私聊
  final int convType;

  /// 推送/引用进入时定位到的消息 ID（可空）
  final int? locateMessageId;

  const ChatPage({
    super.key,
    required this.taskId,
    this.title = '群聊',
    this.convType = 1,
    this.locateMessageId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const Color _primary = Color(0xFF1F6FF4);
  static const int _maxMedia = 9;

  final ChatMessageRepository _repo = ChatMessageRepository();
  final ParttimeChatService _service = ParttimeChatService();
  final ChatContextService _contextService = ChatContextService();

  /// 本会话定位键（conv_type + task_id），所有接口/本地库调用都用它
  late final ChatTarget _target = ChatTarget.of(widget.convType, widget.taskId);

  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// 倒序存储：_messages[0] = 最新（视觉底部）
  final List<ChatMessage> _messages = [];

  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _fetching = false;
  bool _hasMoreOld = true;
  bool _atBottom = true;

  /// around 重建窗口后不在最新位置 → 显示「回到最新」
  bool _notAtLatest = false;

  String? _error;
  int _oldestId = 0;
  int _lastReadId = 0;
  int _markedReadId = 0;
  int _newMsgBadge = 0;
  int _highlightMessageId = 0;
  Timer? _highlightTimer;

  int? _currentUserId;
  String _myName = '';
  String _myAvatar = '';
  int _myRole = 0;

  /// AppBar 标题（初始用入参，best-effort 用任务详情的医院名补全）
  late String _title;

  /// 任务关联的客户 / 医院，决定菜单里「医院信息查询」「客户资料查询」是否出现
  ChatTaskContext? _taskContext;

  ChatMessage? _quoteTarget;
  final Map<String, int> _mentionedNames = {};

  /// 输入框上一次的文本，用来判定「本次编辑是不是刚敲了一个 @」
  String _lastInputText = '';

  /// @选人弹窗是否已打开，防止重复拉起
  bool _mentionPickerOpen = false;
  final List<_DraftImage> _draftImages = [];

  StreamSubscription<ChatTarget>? _fgSub;

  int get _newestId {
    for (final m in _messages) {
      if (m.messageId > 0) return m.messageId;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    WidgetsBinding.instance.addObserver(this);
    final picker = ImagePickerPlatform.instance;
    if (picker is ImagePickerAndroid) {
      picker.useAndroidPhotoPicker = true;
    }
    _service.enterChat(_target);
    _positions.itemPositions.addListener(_onPositionsChanged);
    _fgSub = _service.onForegroundNewMessage.listen((t) {
      if (t == _target) _fetchNew();
    });
    _clearNotifications(); // 进入会话即清掉此前收到的通知栏残留
    // 从推送/上个路由(登录、搜索框等)进入时，键盘可能仍在收起动画中，
    // viewInsets.bottom 尚未归零；Scaffold(resizeToAvoidBottomInset) 会按这段
    // 残留键盘高度预留空白，把输入框顶起。进入会话后主动收起，触发 inset 归零。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dismissResidualKeyboard();
    });
    _bootstrap();
    // 只有任务群的 task_id 才是任务 ID：科室群是科室 ID、私聊是会话 ID，
    // 查任务详情无意义，而且 chat_task_context 按裸 taskId 做主键，会撞号污染缓存
    if (_target.isTask) _loadTaskContext();
  }

  /// 加载群聊所属任务的关联客户 / 医院（菜单里两个查询入口的显隐依据）。
  /// 本地快照先用，再拉一次任务详情刷新；失败则维持本地值（可能都没有 → 不显示入口）。
  Future<void> _loadTaskContext() async {
    final cached = await _contextService.localContext(widget.taskId);
    if (mounted && cached != null) setState(() => _taskContext = cached);
    final fresh = await _contextService.refreshContext(widget.taskId);
    if (mounted && fresh != null) setState(() => _taskContext = fresh);
  }

  /// 收起从上个路由残留的键盘，消除 Scaffold 预留的键盘高度空白。
  void _dismissResidualKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    // 焦点已随上个路由销毁(primaryFocus 为空)时 unfocus 是空操作，
    // 再强制平台收起 IME，确保下发 inset 归零的 metrics 回调。
    // ignore: discarded_futures
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 清通知栏残留：进入 / 回到会话页时调用。
  /// JPush 无法按 task 精确清（OS 通知 id 未回传），全清——用户在聊天可接受。
  void _clearNotifications() {
    // ignore: discarded_futures
    JPushService().clearAllNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.leaveChat(_target);
    _positions.itemPositions.removeListener(_onPositionsChanged);
    _fgSub?.cancel();
    _highlightTimer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _fetchNew();
      _clearNotifications(); // 切后台收到通知后回到本会话页，清掉通知栏
    }
  }

  // ——————————————————— 加载 ———————————————————

  Future<void> _bootstrap() async {
    _currentUserId = int.tryParse(await UserService().getBackendUserId() ?? '');
    _myName = await UserService().getUsername() ?? '';
    _myAvatar = await UserService().getUserAvatar() ?? '';
    _myRole = await UserService().getRoleId();

    // 本地秒显
    final local = await _repo.localRecent(_target);
    final meta = await _repo.localSyncMeta(_target);
    if (mounted && local.isNotEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(local.reversed);
        _oldestId = local.first.messageId;
        _hasMoreOld = meta?.hasMoreOld ?? true;
        _lastReadId = meta?.lastReadId ?? 0;
        _loading = false;
      });
    }

    // 网络对齐
    final r = await _repo.fetchInitial(_target);
    if (!mounted) return;
    if (r.errorMessage != null) {
      if (_messages.isEmpty) {
        setState(() {
          _loading = false;
          _error = r.errorMessage;
        });
      }
    } else {
      setState(() {
        _messages
          ..clear()
          ..addAll(r.list.reversed);
        _oldestId = r.oldestId > 0
            ? r.oldestId
            : (_messages.isNotEmpty ? _messages.last.messageId : 0);
        _hasMoreOld = r.hasMoreOld;
        _lastReadId = r.lastReadId;
        _newMsgBadge = 0;
        _loading = false;
        _error = null;
        // 后端 group_name 作群标题（跨角色可用）
        if (r.groupName.isNotEmpty) _title = r.groupName;
      });
      _markedReadId = _newestId;
    }

    // 推送/引用定位
    final locate = widget.locateMessageId;
    if (locate != null && locate > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToMessage(locate),
      );
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOld || _oldestId <= 0) return;
    _loadingOlder = true;
    final r = await _repo.loadOlder(_target, _oldestId);
    if (!mounted) {
      _loadingOlder = false;
      return;
    }
    if (r.errorMessage == null && r.list.isNotEmpty) {
      setState(() {
        for (final m in r.list.reversed) {
          if (m.messageId <= 0) continue;
          if (_messages.any((e) => e.messageId == m.messageId)) continue;
          _messages.add(m);
        }
        _oldestId = _messages.isNotEmpty ? _messages.last.messageId : _oldestId;
        _hasMoreOld = r.hasMoreOld;
      });
    } else {
      setState(() => _hasMoreOld = r.hasMoreOld);
      if (r.errorMessage != null) _toast(r.errorMessage!);
    }
    _loadingOlder = false;
  }

  Future<void> _fetchNew() async {
    if (_fetching) return;
    _fetching = true;
    try {
      int afterId = _newestId;
      if (afterId <= 0) return;
      final collected = <ChatMessage>[];
      while (true) {
        final r = await _repo.fetchNew(_target, afterId);
        if (r.errorMessage != null || r.list.isEmpty) break;
        collected.addAll(r.list);
        if (!r.hasMoreNew) break;
        final next = r.newestId > 0 ? r.newestId : r.list.last.messageId;
        if (next <= afterId) break;
        afterId = next;
      }
      if (collected.isNotEmpty && mounted) _appendNew(collected);
    } finally {
      _fetching = false;
    }
  }

  /// 追加增量消息（fresh 正序 旧→新）
  void _appendNew(List<ChatMessage> fresh) {
    final wasAtBottom = _atBottom;
    int added = 0;
    setState(() {
      for (final m in fresh) {
        if (m.messageId <= 0) continue;
        if (_messages.any((e) => e.messageId == m.messageId)) continue;
        _messages.insert(0, m);
        added++;
      }
    });
    if (added == 0) return;
    final atLatest = wasAtBottom && !_notAtLatest;
    // 群里的新消息就地写进本地会话摘要 + 广播给列表，省掉「返回后等网络」的闪动。
    // 停在历史位置时未读不清零（人没看到），交给网络刷新给准数。
    final latest = _latestPersisted();
    if (latest != null) {
      // ignore: discarded_futures
      _repo.touchConversationSummary(_target, latest, clearUnread: atLatest);
    }
    if (atLatest) {
      _scrollToBottom();
      _advanceRead(_newestId);
    } else {
      setState(() => _newMsgBadge += added);
    }
  }

  /// 内存里已落库的最新一条（跳过 messageId=0 的乐观消息）。
  /// [_messages] 是新→旧，第一条有真实 id 的就是最新。
  ChatMessage? _latestPersisted() {
    for (final m in _messages) {
      if (m.messageId > 0) return m;
    }
    return null;
  }

  // ——————————————————— 滚动 / 位置 ———————————————————

  void _onPositionsChanged() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final indices = positions.map((e) => e.index);
    final minIndex = indices.reduce((a, b) => a < b ? a : b);
    final maxIndex = indices.reduce((a, b) => a > b ? a : b);

    final atBottom = minIndex == 0;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
      if (atBottom) _onReachBottom();
    }
    if (maxIndex >= _messages.length - 2 && _hasMoreOld && !_loadingOlder) {
      _loadOlder();
    }
  }

  void _onReachBottom() {
    if (_newMsgBadge != 0) setState(() => _newMsgBadge = 0);
    _advanceRead(_newestId);
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_itemScroll.isAttached) return;
    if (animate) {
      _itemScroll.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _itemScroll.jumpTo(index: 0);
    }
  }

  void _scrollToIndex(int index) {
    if (!_itemScroll.isAttached) return;
    _itemScroll.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.4,
    );
  }

  Future<void> _advanceRead(int upToId) async {
    if (upToId <= 0 || upToId <= _markedReadId) return;
    _markedReadId = upToId;
    await _service.markRead(target: _target, upToId: upToId);
  }

  // ——————————————————— 引用跳转 ———————————————————

  Future<void> _jumpToMessage(int anchorId) async {
    if (anchorId <= 0) return;
    final idx = _messages.indexWhere((m) => m.messageId == anchorId);
    if (idx >= 0) {
      // 目标已在可见区间（如消息很少、整屏都看得到，尤其推送定位到最新那条）时，
      // 不要再 scrollTo+alignment——否则会把消息顶到视口 40% 处、下方留出大片空白。
      // 仅当目标不在当前可见范围时才滚动定位。
      final visible = _positions.itemPositions.value.map((e) => e.index);
      if (!visible.contains(idx)) _scrollToIndex(idx);
      _highlight(anchorId);
      return;
    }
    // 不在内存：本地 around 优先，网络 around_id 兜底，重建窗口
    final r = await _repo.locateMessage(_target, anchorId);
    if (!mounted) return;
    if (r.errorMessage != null || r.list.isEmpty) {
      _toast(r.errorMessage ?? '原消息不存在或已删除');
      return;
    }
    setState(() {
      _messages
        ..clear()
        ..addAll(r.list.reversed);
      _oldestId = _messages.isNotEmpty ? _messages.last.messageId : 0;
      _hasMoreOld = r.hasMoreOld;
      _notAtLatest = true; // 重建窗口后不在最新
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newIdx = _messages.indexWhere((m) => m.messageId == anchorId);
      if (newIdx >= 0) _scrollToIndex(newIdx);
      _highlight(anchorId);
    });
  }

  void _highlight(int messageId) {
    setState(() => _highlightMessageId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightMessageId = 0);
    });
  }

  Future<void> _backToLatest() async {
    setState(() {
      _notAtLatest = false;
      _loading = true;
    });
    final r = await _repo.fetchInitial(_target);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.errorMessage == null) {
        _messages
          ..clear()
          ..addAll(r.list.reversed);
        _oldestId = r.oldestId > 0
            ? r.oldestId
            : (_messages.isNotEmpty ? _messages.last.messageId : 0);
        _hasMoreOld = r.hasMoreOld;
        _lastReadId = r.lastReadId;
        _newMsgBadge = 0;
      }
    });
    _markedReadId = _newestId;
    _scrollToBottom(animate: false);
  }

  // ——————————————————— 发送 ———————————————————

  Future<void> _send() async {
    final content = _inputController.text.trim();
    final uploaded = _draftImages.where((d) => d.url != null).toList();
    final urls = uploaded.map((d) => d.url!).toList();
    // media 与 urls 同序等长：后端按序落库，缩略图靠它带过去
    final media = uploaded.map((d) => d.toMedia()).toList();
    if (_draftImages.any((d) => d.uploading)) {
      _toast('图片上传中，请稍候');
      return;
    }
    if (_draftImages.any((d) => d.failed)) {
      _toast('有图片上传失败，请删除后重试');
      return;
    }
    if (content.isEmpty && urls.isEmpty) {
      _toast('请输入要发送的内容');
      return;
    }

    // 私聊无 @：不解析文本里的 @片段，当普通文字发出去
    final mentionAll = !_target.isPrivate && content.contains('@所有人');
    final mentionIds = <int>[];
    if (!_target.isPrivate) {
      _mentionedNames.forEach((name, id) {
        if (content.contains('@$name')) mentionIds.add(id);
      });
    }

    final clientMsgId =
        'c_${widget.taskId}_${DateTime.now().microsecondsSinceEpoch}';
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final quote = _quoteTarget;
    final optimistic = ChatMessage.optimistic(
      taskId: widget.taskId,
      userId: _currentUserId ?? 0,
      username: _myName,
      roleid: _myRole,
      avatar: _myAvatar,
      createdAt: nowSec,
      clientMsgId: clientMsgId,
      content: content,
      images: urls,
      media: media,
      quoteMessageId: quote?.messageId ?? 0,
      quote: quote == null ? null : _quoteSnapshot(quote),
      mentionAll: mentionAll,
      mentionUserIds: mentionIds,
    );

    setState(() {
      _messages.insert(0, optimistic);
      _inputController.clear();
      _lastInputText = '';
      _draftImages.clear();
      _quoteTarget = null;
      _mentionedNames.clear();
      _sending = true;
    });
    _scrollToBottom();

    final r = await _service.send(
      target: _target,
      content: content,
      images: urls,
      media: media,
      quoteMessageId: quote?.messageId ?? 0,
      clientMsgId: clientMsgId,
      mentionUserIds: mentionIds,
      mentionAll: mentionAll,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      final idx = _messages.indexWhere(
        (m) => m.clientMsgId == clientMsgId && m.pending,
      );
      if (idx < 0) return;
      if (r.success) {
        if (r.messageId > 0 &&
            _messages.any((m) => m.messageId == r.messageId)) {
          _messages.removeAt(idx); // 推送/增量已抢先插入同条
        } else {
          final confirmed = optimistic.confirmed(r.messageId, r.createdAt);
          _messages[idx] = confirmed;
          // ignore: discarded_futures
          _repo.persist(_target, [confirmed]);
          // 自己发的这条就是会话最后一条，就地对齐本地会话摘要（返回列表不闪动）
          // ignore: discarded_futures
          _repo.touchConversationSummary(_target, confirmed, clearUnread: true);
        }
        if (r.messageId > _markedReadId) _markedReadId = r.messageId;
      } else {
        _messages[idx] = optimistic.markFailed();
        _toast(r.message ?? '发送失败');
      }
    });
  }

  /// 三个点菜单：任务详情 / 群成员 / 医院信息查询 / 客户资料查询
  ///
  /// 科室群没有关联任务，只保留「群成员」。
  void _showChatMenu() {
    final isDept = _target.isDepartment;
    showChatBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: (_) => ChatSheetMenu(
        actions: [
          if (!isDept)
            ChatSheetAction(
              icon: Icons.assignment_outlined,
              label: '查看任务详情',
              onTap: () {
                Navigator.pop(context);
                _openTaskDetail();
              },
            ),
          ChatSheetAction(
            icon: Icons.group_outlined,
            label: '群成员',
            onTap: () {
              Navigator.pop(context);
              _openMembers();
            },
          ),
          // 任务上下文未就绪（或该任务无关联客户/医院）时不显示对应入口
          if (_taskContext?.hasHospital == true)
            ChatSheetAction(
              icon: Icons.local_hospital_outlined,
              label: '医院信息查询',
              onTap: () {
                Navigator.pop(context);
                _openHospitalInfo();
              },
            ),
          if (_taskContext?.hasClient == true)
            ChatSheetAction(
              icon: Icons.badge_outlined,
              label: '客户资料查询',
              onTap: () {
                Navigator.pop(context);
                _openClientProfile();
              },
            ),
        ],
      ),
    );
  }

  void _openHospitalInfo() {
    final ctx = _taskContext;
    if (ctx == null || !ctx.hasHospital) return;
    // ignore: discarded_futures
    showHospitalInfoSheet(
      context,
      hospitalId: ctx.hospitalId,
      fallbackName: ctx.hospitalName,
    );
  }

  void _openClientProfile() {
    final ctx = _taskContext;
    if (ctx == null || !ctx.hasClient) return;
    // ignore: discarded_futures
    showClientProfileSheet(context, clientId: ctx.clientId);
  }

  /// 打开群成员管理。邀请 / 移除成员后端会生成系统灰条消息，但推送只发给被
  /// 操作的成员，操作者本人收不到推送；关闭弹窗后主动增量拉一次，把这期间产生
  /// 的系统消息补到会话里。
  /// 群成员里也能点人发起私聊，弹窗关闭后把 intent 带回来跳转（弹窗自己不 push）
  Future<void> _openMembers() async {
    final intent = await showChatMembersSheet(
      context,
      _target,
      viewerRoleid: _myRole,
    );
    if (!mounted) return;
    _fetchNew();
    if (intent != null) _pushPrivateChat(intent);
  }

  void _openTaskDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartTimeTaskDetailPage(taskId: widget.taskId),
      ),
    );
  }

  ChatMessageQuote _quoteSnapshot(ChatMessage m) {
    final c = m.content.length > 50 ? m.content.substring(0, 50) : m.content;
    return ChatMessageQuote(
      messageId: m.messageId,
      userId: m.userId,
      username: m.username,
      content: c,
      image: m.images.isNotEmpty ? m.images.first : '',
      imageThumb: m.media.isNotEmpty ? m.media.first.thumb : '',
      // 乐观发送时本地也带上类型，引用条不用等服务端回包就能显示「[视频]」
      imageType: m.media.isNotEmpty
          ? (m.media.first.isVideo ? 'video' : 'image')
          : '',
    );
  }

  Future<void> _retry(ChatMessage failed) async {
    final idx = _messages.indexWhere(
      (m) => m.clientMsgId == failed.clientMsgId,
    );
    if (idx < 0) return;
    setState(
      () => _messages[idx] = failed.copyWith(pending: true, failed: false),
    );
    final r = await _service.send(
      target: _target,
      content: failed.content,
      images: failed.images,
      media: failed.media,
      quoteMessageId: failed.quoteMessageId,
      clientMsgId: failed.clientMsgId ?? '',
      mentionUserIds: failed.mentionUserIds,
      mentionAll: failed.mentionAll,
    );
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere(
        (m) => m.clientMsgId == failed.clientMsgId,
      );
      if (i < 0) return;
      if (r.success) {
        if (r.messageId > 0 &&
            _messages.any((m) => m.messageId == r.messageId)) {
          _messages.removeAt(i);
        } else {
          final confirmed = failed.confirmed(r.messageId, r.createdAt);
          _messages[i] = confirmed;
          // ignore: discarded_futures
          _repo.persist(_target, [confirmed]);
        }
      } else {
        _messages[i] = failed.markFailed();
        _toast(r.message ?? '发送失败');
      }
    });
  }

  // ——————————————————— 长按菜单 / 撤回 / 引用 / @ ———————————————————

  void _showMessageMenu(ChatMessage m) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final canRecall = m.canRecall(_currentUserId, nowSec);
    showChatBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: (_) => ChatSheetMenu(
        actions: [
          ChatSheetAction(
            icon: Icons.format_quote,
            label: '引用',
            onTap: () {
              Navigator.pop(context);
              _setQuote(m);
            },
          ),
          if (m.content.isNotEmpty)
            ChatSheetAction(
              icon: Icons.copy_rounded,
              label: '复制',
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: m.content));
                _toast('已复制', icon: Icons.check_circle_outline);
              },
            ),
          if (canRecall)
            ChatSheetAction(
              icon: Icons.undo,
              label: '撤回',
              danger: true,
              onTap: () {
                Navigator.pop(context);
                _recall(m);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _recall(ChatMessage m) async {
    final r = await _service.recall(m.messageId);
    if (!mounted) return;
    if (r.success) {
      setState(() {
        final idx = _messages.indexWhere((e) => e.messageId == m.messageId);
        if (idx >= 0) _messages[idx] = _messages[idx].markRecalled();
      });
      // ignore: discarded_futures
      _repo.markRecalledLocal(_target, m.messageId);
      // 撤回的是最后一条时，会话摘要要跟着变成 [消息已撤回]
      final latest = _latestPersisted();
      if (latest != null && latest.messageId == m.messageId) {
        // ignore: discarded_futures
        _repo.touchConversationSummary(_target, latest, clearUnread: true);
      }
    } else {
      _toast(r.message ?? '撤回失败');
    }
  }

  void _setQuote(ChatMessage m) {
    setState(() => _quoteTarget = m);
    _inputFocus.requestFocus();
  }

  Future<void> _onMentionPressed() async {
    final t = await showMentionPicker(
      context,
      _target,
      selfUserId: _currentUserId,
    );
    if (t == null) return;
    final insert = t.all ? '@所有人 ' : '@${t.username} ';
    _insertMention(insert);
    if (!t.all) _mentionedNames[t.username] = t.userId;
    _inputFocus.requestFocus();
  }

  /// 输入框文本变化：用户刚敲入 `@` 时自动拉起选人弹窗（私聊无 @，不触发）。
  ///
  /// 只认「本次编辑恰好在光标前插入了一个 @」这一种情况——把光标前一位删掉能还原成
  /// 上次的文本才算数。这样粘贴一段含 @ 的文字、或在别处改字都不会误弹。
  /// 程序化改写文本不会回调 onChanged，基线由 [_insertMention] / 发送后清空处同步。
  void _onInputChanged(String text) {
    final prev = _lastInputText;
    _lastInputText = text;
    if (_target.isPrivate || _mentionPickerOpen || _sending) return;
    final sel = _inputController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final caret = sel.baseOffset;
    if (caret < 1 || caret > text.length) return;
    if (!_isAtSign(text[caret - 1])) return;
    if (text.replaceRange(caret - 1, caret, '') != prev) return;
    // ignore: discarded_futures
    _autoMention(caret - 1);
  }

  /// 半角 / 中文输入法下的全角 @
  static bool _isAtSign(String ch) => ch == '@' || ch == '＠';

  /// 手输 `@` 触发的选人：选中后用结果替换掉刚敲的那个 @（避免出现 `@@张三`）；
  /// 取消则保留用户输入的 @ 原样，只把键盘拉回来。
  Future<void> _autoMention(int atIndex) async {
    _mentionPickerOpen = true;
    MentionTarget? t;
    try {
      t = await showMentionPicker(context, _target, selfUserId: _currentUserId);
    } finally {
      _mentionPickerOpen = false;
    }
    if (!mounted) return;
    if (t == null) {
      _inputFocus.requestFocus();
      return;
    }
    final insert = t.all ? '@所有人 ' : '@${t.username} ';
    // 弹窗期间输入框失焦改不了，位置理应还在；仍校验一次，对不上就退化为光标处插入
    final text = _inputController.text;
    final hit = atIndex < text.length && _isAtSign(text[atIndex]);
    _insertMention(
      insert,
      replace: hit ? (start: atIndex, end: atIndex + 1) : null,
    );
    if (!t.all) _mentionedNames[t.username] = t.userId;
    _inputFocus.requestFocus();
  }

  /// 长按他人头像：快捷 @ 该成员并拉起键盘（已 @ 过则不重复插入）。私聊无 @。
  void _mentionFromAvatar(ChatMessage m) {
    if (_target.isPrivate) return;
    final name = m.username.trim();
    if (name.isEmpty || m.userId <= 0) return;
    HapticFeedback.selectionClick();
    _mentionedNames[name] = m.userId;
    if (!_inputController.text.contains('@$name')) {
      _insertMention('@$name ');
    }
    _inputFocus.requestFocus();
  }

  /// 点击他人头像：弹用户名片（基本信息 + 拨号 + 发起私聊）。
  /// 私聊页里已经在和对方对话，名片只展示资料、不给「发起私聊」。
  Future<void> _openUserCard(ChatMessage m) async {
    if (m.userId <= 0) return;
    final intent = await showChatUserCardSheet(
      context,
      userId: m.userId,
      username: m.username,
      avatar: m.avatar,
      roleid: m.roleid,
      viewerRoleid: _myRole,
      allowPrivateChat: !_target.isPrivate,
    );
    if (intent == null || !mounted) return;
    _pushPrivateChat(intent);
  }

  /// 进私聊会话（名片、群成员两个入口共用）
  void _pushPrivateChat(ChatPrivateChatIntent intent) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          taskId: intent.convId,
          convType: 3,
          title: intent.peerName.isEmpty ? '私聊' : intent.peerName,
        ),
      ),
    );
  }

  /// 在光标处插入 @片段（无光标时追加到末尾）；
  /// 传 [replace] 则改为替换该区间（手输 @ 触发时用来吃掉用户敲的那个 @）
  void _insertMention(String insert, {({int start, int end})? replace}) {
    final text = _inputController.text;
    final sel = _inputController.selection;
    final at = replace?.start ?? (sel.isValid ? sel.start : text.length);
    final end = replace?.end ?? (sel.isValid ? sel.end : text.length);
    _inputController.text = text.replaceRange(at, end, insert);
    _inputController.selection = TextSelection.collapsed(
      offset: at + insert.length,
    );
    // 程序化改写不回调 onChanged，手动同步基线，否则下一次手输 @ 的判定会落空
    _lastInputText = _inputController.text;
  }

  // ——————————————————— 图片草稿 ———————————————————

  Future<void> _pickMedia() async {
    final remaining = _maxMedia - _draftImages.length;
    if (remaining <= 0) {
      _toast('最多上传 $_maxMedia 个文件');
      return;
    }
    final picker = ImagePicker();
    final List<XFile> picked = [];
    try {
      if (remaining == 1) {
        final f = await picker.pickMedia(imageQuality: 85);
        if (f != null) picked.add(f);
      } else {
        picked.addAll(
          await picker.pickMultipleMedia(imageQuality: 85, limit: remaining),
        );
      }
    } catch (e) {
      _toast('选择失败: $e');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    final drafts = picked
        .take(remaining)
        .map(
          (x) => _DraftImage(
            localPath: x.path,
            isVideo: MediaSaver.isVideo(x.name),
          ),
        )
        .toList();
    setState(() => _draftImages.addAll(drafts));
    for (final d in drafts) {
      _uploadDraft(d);
    }
  }

  Future<void> _uploadDraft(_DraftImage draft) async {
    try {
      // 视频也要传 1：后端据此走 ffmpeg 截帧（video_frame），否则视频在列表里
      // 只能画一个黑块。缩略图 URL 无法由原图 URL 推导，必须原样带走。
      final info = await NasUploadService().uploadFile(
        file: UploadFile.fromPath(draft.localPath),
        generateThumbnail: true,
      );
      if (!mounted) return;
      setState(() {
        draft.url = info.fileUrl;
        // previewUrl 优先 thumbnail → video_frame → 原件；与原件相同即视为无缩略图
        final preview = info.previewUrl;
        draft.thumb = preview == info.fileUrl ? '' : preview;
        draft.uploading = false;
        draft.failed = info.fileUrl.isEmpty;
      });
      if (info.fileUrl.isNotEmpty) {
        // ignore: discarded_futures
        MediaCacheCleaner.cleanPickedFile(draft.localPath);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        draft.uploading = false;
        draft.failed = true;
      });
    }
  }

  /// 统一走全局浮层提示（原来是输入框上方一条黄色提示条，与其他页面观感不一）
  void _toast(String msg, {IconData icon = Icons.info_outline}) {
    if (!mounted) return;
    showOverlayToast(context, msg, icon: icon);
  }

  // ——————————————————— build ———————————————————

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
        // 私聊不是群：任务详情 / 群成员 / 医院信息 / 客户资料都不适用，整个菜单不给
        actions: [
          if (!_target.isPrivate)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: '更多',
              onPressed: _showChatMenu,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildList(),
                if (_newMsgBadge > 0) _buildNewMsgPill(),
                if (_notAtLatest) _buildBackToLatestPill(),
              ],
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFB2B2B2)),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFF666666))),
            const SizedBox(height: 12),
            TextButton(onPressed: _bootstrap, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '还没有消息，来说点什么吧',
          style: TextStyle(color: Color(0xFF999999), fontSize: 14),
        ),
      );
    }
    // 每帧算一次锚点，itemBuilder 里只做一次 id 比对
    final unreadAnchorId = _computeUnreadAnchorId();
    return GestureDetector(
      onTap: () => _inputFocus.unfocus(),
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScroll,
        itemPositionsListener: _positions,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _messages.length + (_hasMoreOld ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final msg = _messages[index];
          final bubble = ChatMessageBubble(
            key: ValueKey(
              msg.messageId > 0 ? 'm${msg.messageId}' : 'c${msg.clientMsgId}',
            ),
            message: msg,
            currentUserId: _currentUserId,
            highlighted:
                msg.messageId > 0 && msg.messageId == _highlightMessageId,
            onQuoteTap: _jumpToMessage,
            onLongPress: _showMessageMenu,
            onRetry: _retry,
            onAvatarLongPress: _mentionFromAvatar,
            onAvatarTap: _openUserCard,
          );
          final isFirstUnread =
              unreadAnchorId > 0 && msg.messageId == unreadAnchorId;
          if (isFirstUnread) {
            return Column(children: [_buildUnreadDivider(), bubble]);
          }
          return bubble;
        },
      ),
    );
  }

  /// 「以下为新消息」分隔线挂在哪条消息上（0=不显示）。
  ///
  /// 口径对齐后端未读统计 `_count_unread_pointer`
  /// （`msg_type=1 AND recalled=0 AND user_id != 自己 AND id > last_read`）：
  /// 只有**别人发的、非系统、未撤回**的消息才算新消息。
  ///
  /// 自己发的消息 id 必然大于进会话时定格的 [_lastReadId]，旧实现只判
  /// 「id > _lastReadId 且上一条已读」，所以自己一发言分隔线就跑到自己气泡上方，
  /// 且此后一直挂着。
  ///
  /// [_messages] 是新→旧：遇到已读区就停，途中每条他人消息都覆盖 anchor，
  /// 最后留下的是未读区里最旧的那条 —— 中间夹着自己发的消息也不会打断。
  int _computeUnreadAnchorId() {
    if (_lastReadId <= 0) return 0;
    int anchor = 0;
    for (final m in _messages) {
      if (m.messageId <= 0) continue; // 乐观发送中（本地 id=0），不能据此判已读区
      if (m.messageId <= _lastReadId) break; // 进入已读区
      if (m.isSystem) continue; // 系统灰条 / 撤回不计未读
      if (m.isMine(_currentUserId)) continue; // 自己发的不算新消息
      anchor = m.messageId;
    }
    return anchor;
  }

  Widget _buildUnreadDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 40),
      child: Row(
        children: [
          Expanded(child: Divider(color: Color(0xFFE0E0E0))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '以下为新消息',
              style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ),
          Expanded(child: Divider(color: Color(0xFFE0E0E0))),
        ],
      ),
    );
  }

  Widget _buildNewMsgPill() {
    return Positioned(
      right: 12,
      bottom: 12,
      child: GestureDetector(
        onTap: () {
          _scrollToBottom();
          setState(() => _newMsgBadge = 0);
          _advanceRead(_newestId);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.1 * 255).round()),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, size: 14, color: _primary),
              const SizedBox(width: 4),
              Text(
                '$_newMsgBadge 条新消息',
                style: const TextStyle(fontSize: 12, color: _primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackToLatestPill() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: Center(
        child: GestureDetector(
          onTap: _backToLatest,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.vertical_align_bottom,
                  size: 14,
                  color: Colors.white,
                ),
                SizedBox(width: 4),
                Text(
                  '回到最新',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      // 键盘避让交给 Scaffold(resizeToAvoidBottomInset:默认 true) + 下方 SafeArea，
      // 这里不要再叠加 viewInsets.bottom，否则会多顶起一个键盘高度的空白。
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_quoteTarget != null) _buildQuoteBar(),
            if (_draftImages.isNotEmpty) _buildDraftImages(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _sending ? null : _pickMedia,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: const Color(0xFF666666),
                  tooltip: '添加图片/视频',
                ),
                // 私聊只有两个人，@ 没有意义（后端 mention_* 也恒空）
                if (!_target.isPrivate)
                  IconButton(
                    onPressed: _sending ? null : _onMentionPressed,
                    icon: const Icon(Icons.alternate_email),
                    color: const Color(0xFF666666),
                    tooltip: '提醒谁看',
                  ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      // 敲 @ 自动拉起选人弹窗（与左侧 @ 按钮等价）
                      onChanged: _onInputChanged,
                      decoration: InputDecoration(
                        hintText: '说点什么…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F6F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildSendButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteBar() {
    final q = _quoteTarget!;
    final name = q.username.isEmpty ? '用户${q.userId}' : q.username;
    final preview = q.content.isNotEmpty
        ? q.content
        : (q.images.isNotEmpty ? '[图片]' : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '引用 $name：$preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _quoteTarget = null),
            child: const Icon(Icons.close, size: 16, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftImages() {
    return Container(
      height: 70,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _draftImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = _draftImages[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _buildDraftThumb(d),
              ),
              if (d.uploading)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (d.failed)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _draftImages.remove(d)),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDraftThumb(_DraftImage d) {
    const double size = 64;
    if (d.isVideo) {
      // 上传完成拿到截帧后用帧图垫底；未上传完 / 截帧失败仍是黑底图标
      final frame = d.thumb;
      return Container(
        width: size,
        height: size,
        color: Colors.black87,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (frame.isNotEmpty)
              CachedNetworkImage(
                imageUrl: frame,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            const Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 24),
            ),
          ],
        ),
      );
    }
    // 图片草稿：有缩略图先用缩略图（省流量），否则原图
    final preview = d.thumb.isNotEmpty ? d.thumb : d.url;
    if (preview != null && preview.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: preview,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => _draftPlaceholder(size),
        errorWidget: (_, _, _) => _draftPlaceholder(size),
      );
    }
    return Image.file(
      File(d.localPath),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _draftPlaceholder(size),
    );
  }

  Widget _draftPlaceholder(double size) => Container(
    width: size,
    height: size,
    color: const Color(0xFFEFEFEF),
    child: const Icon(Icons.image, color: Color(0xFFBBBBBB)),
  );

  Widget _buildSendButton() {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: _sending ? null : _send,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('发送'),
      ),
    );
  }
}

/// 待发送图片草稿
class _DraftImage {
  final String localPath;
  final bool isVideo;
  String? url;

  /// 上传接口返回的缩略图 / 视频截帧 URL；截帧失败或后端未生成时为空
  String thumb = '';
  bool uploading;
  bool failed;

  _DraftImage({this.localPath = '', this.isVideo = false})
    : uploading = true,
      failed = false;

  /// 转发送用的富媒体项（url 已确认非空时调用）
  ChatMedia toMedia() =>
      ChatMedia(url: url ?? '', thumb: thumb, isVideo: isVideo);
}
