import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/pages/chat/chat_contacts_page.dart';
import 'package:yatai_hub/pages/chat/chat_page.dart';
import 'package:yatai_hub/services/chat_message_repository.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/widgets/app_search_field.dart';
import 'package:yatai_hub/widgets/chat/chat_member_avatar.dart';

/// 「消息」Tab —— 最近会话列表（任务群 + 科室群 + 私聊，后端混排返回）
///
/// 本地缓存秒显 + 网络对齐，按最后消息时间倒序，行带未读红点 / @提醒；
/// 科室群（`conv_type=2`）用青色图标 + 「科室」标签区分，私聊（`conv_type=3`）
/// 用对方圆形头像。
///
/// 右上角通讯录入口仅非兼职账号（roleid≠275）可见——只有他们能发起私聊。
class ChatConversationsPage extends StatefulWidget {
  const ChatConversationsPage({super.key});

  @override
  State<ChatConversationsPage> createState() => ChatConversationsPageState();
}

class ChatConversationsPageState extends State<ChatConversationsPage> {
  static const Color _primary = Color(0xFF1F6FF4);

  /// 科室群用区分色（任务群蓝、科室群青）
  static const Color _dept = Color(0xFF12A594);

  final ChatMessageRepository _repo = ChatMessageRepository();
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  /// 每页会话数（后端 page_size 上限 50）
  static const int _pageSize = 20;

  /// 网络已加载的会话（按页累加，(convType,taskId) 去重）
  List<ChatConversation> _list = const [];

  /// 本地库全量 + 网络已见行的并集，只喂给搜索。
  ///
  /// 接口没有 keyword 参数（后端 chat_conversations 只收 page/page_size），
  /// 搜索只能在本地做；若只搜 [_list]，第 2 页之后没加载的会话就搜不到。
  /// 这份并集里凡是网络回过的行都已被最新值覆盖，其余是本地库的旧值。
  List<ChatConversation> _localAll = const [];

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// 已加载页码与后端 total（total 是我的会话总数，后端全量排序后 array_slice）
  int _page = 1;
  int _total = 0;

  bool get _hasMore => _list.length < _total;

  /// 本地搜索关键词（按群名 / 最后一条消息匹配，不发请求）
  String _query = '';

  /// 是否显示通讯录入口（仅非兼职：兼职不能主动发起私聊，接口也会拒）
  bool _canUseContacts = false;

  StreamSubscription<void>? _convSub;
  StreamSubscription<ChatTarget>? _readSub;
  StreamSubscription<ChatConvSummary>? _summarySub;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _loadContactsPermission();
    _convSub = ParttimeChatService().onConversationsChanged.listen((_) {
      _refresh();
    });
    _readSub = ParttimeChatService().onTaskRead.listen((target) {
      // 某会话已读 → 该行未读清零（即时反馈，下次刷新与服务端对齐）
      // 任务群与科室群 ID 会撞号，必须连 conv_type 一起比
      // 搜索源 _localAll 一起清，否则搜出来的那条还挂着红点
      if (mounted) setState(() => _clearUnreadAt(target));
    });
    // 群聊页内收发消息 → 就地改内存那一行（用户还在群里时列表就已对齐）
    _summarySub = ParttimeChatService().onConversationSummaryUpdated.listen((s) {
      if (mounted) setState(() => _applySummary(s));
    });
    _scrollCtrl.addListener(_onScroll);
    _bootstrap();
  }

  /// 应用会话摘要补丁：只改最后一条消息/时间（+可选清未读），不动 title /
  /// member_count —— 群聊页手里没有那些字段。
  ///
  /// 补丁只打给**已在列表里**的会话；没见过的会话交给网络刷新补齐整行。
  /// `lastMessageId <= s.lastMessageId` 防乱序：撤回旧消息、慢到的增量不该把更新
  /// 的摘要盖回去。
  void _applySummary(ChatConvSummary s) {
    List<ChatConversation> patch(List<ChatConversation> src) {
      final idx = src.indexWhere((c) => c.target == s.target);
      if (idx < 0 || src[idx].lastMessageId > s.lastMessageId) return src;
      final row = src[idx].copyWith(
        lastMessageId: s.lastMessageId,
        lastMessage: s.lastMessage,
        lastMessageTime: s.lastMessageTime,
        unreadCount: s.readCleared ? 0 : null,
        hasMention: s.readCleared ? false : null,
      );
      return (List.of(src)..[idx] = row)..sort(_compareConv);
    }

    _list = patch(_list);
    _localAll = patch(_localAll);
  }

  /// 把某会话的未读/提及清零（[_list] 与 [_localAll] 同步改）
  void _clearUnreadAt(ChatTarget target) {
    List<ChatConversation> clear(List<ChatConversation> src) {
      final idx = src.indexWhere((c) => c.target == target);
      if (idx < 0 || (src[idx].unreadCount == 0 && !src[idx].hasMention)) {
        return src;
      }
      return List.of(src)
        ..[idx] = src[idx].copyWith(unreadCount: 0, hasMention: false);
    }

    _list = clear(_list);
    _localAll = clear(_localAll);
  }

  @override
  void dispose() {
    _convSub?.cancel();
    _readSub?.cancel();
    _summarySub?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContactsPermission() async {
    final isPartTime = await UserService().isPartTimeUser();
    if (mounted && !isPartTime) setState(() => _canUseContacts = true);
  }

  /// 当前关键词下可见的会话列表。
  ///
  /// 空关键词走网络分页结果 [_list]；有关键词时在 [_localAll] 上匹配，这样第 2 页
  /// 之后尚未加载的会话也能被搜到（搜索命中后照常进会话，ChatPage 只认 target）。
  List<ChatConversation> get _visibleList {
    if (_query.isEmpty) return _list;
    final q = _query.toLowerCase();
    return (_localAll.isEmpty ? _list : _localAll)
        .where(
          (c) =>
              c.title.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  /// 会话排序，口径与后端 chat_conversations 的 usort 一致：科室群整体置顶，
  /// 私聊与任务群按最后消息时间倒序混排，同一时间戳再按 last_message_id 倒序。
  ///
  /// 前端也得排：分页结果是按页拼起来的，合并新行 / 本地库兜底之后顺序会乱。
  static int _compareConv(ChatConversation a, ChatConversation b) {
    final ra = a.isDepartment ? 1 : 0;
    final rb = b.isDepartment ? 1 : 0;
    if (ra != rb) return rb - ra;
    if (a.lastMessageTime != b.lastMessageTime) {
      return b.lastMessageTime - a.lastMessageTime;
    }
    return b.lastMessageId - a.lastMessageId;
  }

  /// 用 [incoming] 覆盖 [base] 中同会话的行、追加新行，再统一排序。
  ///
  /// 去重键是 (conv_type, task_id)：三类会话的 ID 来自不同表会撞号，只按 taskId
  /// 去重会把任务群 #5 和科室群 #5 当成一条。
  static List<ChatConversation> _mergeConvs(
    List<ChatConversation> base,
    List<ChatConversation> incoming,
  ) {
    final map = <ChatTarget, ChatConversation>{};
    for (final c in base) {
      map[c.target] = c;
    }
    for (final c in incoming) {
      map[c.target] = c;
    }
    return map.values.toList()..sort(_compareConv);
  }

  /// 供底栏「消息」Tab 双击刷新（与其他 Tab 一致）：已经滚回顶部，顺带重置分页
  void refreshToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    _refresh(reset: true);
  }

  Future<void> _bootstrap() async {
    final local = await _repo.localConversations();
    if (mounted && local.isNotEmpty) {
      setState(() {
        _localAll = local;
        // 秒显只取一页：本地库是全量，直接铺完会在网络返回第一页后「变少」
        _list = local.take(_pageSize).toList();
        _loading = false;
      });
    }
    await _refresh(reset: true);
  }

  // 并发刷新（onConversationsChanged / 退群聊返回 / 下拉）乱序返回时，
  // 用代次只采纳最后一次拉取，避免过期列表把已读行的未读数写回去。
  int _refreshGen = 0;

  /// 拉第 1 页。
  ///
  /// [reset]=true（下拉 / Tab 双击 / 首次）回到单页状态；false（推送广播、从会话页
  /// 或通讯录返回）只更新已有行并补新会话，**不截断**用户已经加载出来的后续页。
  Future<void> _refresh({bool reset = false}) async {
    final gen = ++_refreshGen;
    final r = await _repo.fetchConversations(page: 1, pageSize: _pageSize);
    if (!mounted || gen != _refreshGen) return;
    if (r.message == null) {
      setState(() {
        _total = r.total;
        if (reset) _page = 1;
        _list = reset ? (List.of(r.list)..sort(_compareConv))
                      : _mergeConvs(_list, r.list);
        // 搜索源始终合并：拿网络最新值覆盖本地旧值，分页外的行保留
        _localAll = _mergeConvs(_localAll, r.list);
        _loading = false;
        _error = null;
      });
    } else if (_list.isEmpty) {
      setState(() {
        _loading = false;
        _error = r.message;
      });
    }
  }

  void _onScroll() {
    // 搜索是本地全量匹配，结果一次铺完，不参与分页
    if (_query.isNotEmpty || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      // ignore: discarded_futures
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final r = await _repo.fetchConversations(page: next, pageSize: _pageSize);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (r.message != null) return;
      _page = next;
      _total = r.total;
      // 翻页期间来了新消息会让后端排序变动，同一条可能在两页都出现；
      // 按 target 去重即可，漏掉的那条下次刷新会补回来
      _list = _mergeConvs(_list, r.list);
      _localAll = _mergeConvs(_localAll, r.list);
    });
  }

  void _openChat(ChatConversation c) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              taskId: c.taskId,
              convType: c.convType,
              title: c.title.isEmpty ? _defaultTitle(c) : c.title,
            ),
          ),
        )
        .then((_) => _syncAfterChat());
  }

  /// 从会话页返回：先用本地库对齐内存已有行，再走网络。
  ///
  /// 群聊页收发消息时已经把摘要写进 sqlite 并广播过，正常情况下内存早就对了，
  /// 这一步是兜底 —— 列表页在群聊期间被重建（内存丢了、只剩 sqlite 秒显）时靠它。
  /// 直接网络刷新的话，返回那一刻列表还是进群前的旧摘要与旧排序，等响应回来才跳，
  /// 就是那个「消息闪动」。
  Future<void> _syncAfterChat() async {
    final local = await _repo.localConversations();
    if (!mounted) return;
    if (local.isNotEmpty) {
      setState(() {
        // 只 patch 已加载的行，不把本地全量灌进 _list（那会冲掉分页状态）
        _list = _patchExisting(_list, local);
        _localAll = _mergeConvs(_localAll, local);
      });
    }
    await _refresh();
  }

  /// 用 [incoming] 覆盖 [base] 中**已存在**的行，不追加新行（与 [_mergeConvs]
  /// 的区别就在这），避免本地全量把分页出来的 [_list] 撑成全量。
  static List<ChatConversation> _patchExisting(
    List<ChatConversation> base,
    List<ChatConversation> incoming,
  ) {
    if (base.isEmpty || incoming.isEmpty) return base;
    final patch = {for (final c in incoming) c.target: c};
    return base.map((c) => patch[c.target] ?? c).toList()..sort(_compareConv);
  }

  String _defaultTitle(ChatConversation c) {
    if (c.isDepartment) return '科室群聊';
    if (c.isPrivate) return '私聊';
    return '任务群聊';
  }

  void _openContacts() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ChatContactsPage()))
        // 通讯录里可能刚发起了私聊，回来补一次列表
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 顶栏规格与兼职页 (part_time_page) 对齐：40 高 / 16 号居中 / 滚动不染色，
      // 切 Tab 时标题基线不跳动。改这里记得同步那边。
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 40,
        centerTitle: true,
        title: const Text(
          '消息',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_canUseContacts)
            IconButton(
              icon: const Icon(Icons.quick_contacts_dialer_outlined),
              iconSize: 22,
              // 40 高的顶栏放不下 IconButton 默认 48 的点击区，收紧约束防溢出
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 40),
              color: const Color(0xFF1E1E1E),
              tooltip: '通讯录',
              onPressed: _openContacts,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              // 下拉是明确的「重来一遍」，回到第 1 页
              onRefresh: () => _refresh(reset: true),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      // 上下留白对称：此前 4/10 在视觉上把搜索框顶得贴近标题栏
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AppSearchField(
        controller: _searchCtrl,
        hintText: '搜索消息',
        onChanged: (v) => setState(() => _query = v.trim()),
        showClear: true,
        onClear: () {
          setState(() => _query = '');
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF999999)),
            ),
          ),
        ],
      );
    }
    final visible = _visibleList;
    if (visible.isEmpty) {
      // 区分「整体无会话」与「搜索无结果」；能发私聊的账号顺手指路通讯录
      final emptyText = _list.isEmpty
          ? (_canUseContacts ? '暂无消息\n点右上角通讯录可发起私聊' : '暂无消息')
          : '未找到与「$_query」相关的会话';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF999999),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
    }
    // 搜索态一次铺完不分页，故只在无关键词时给 footer
    final showFooter = _query.isEmpty && (_hasMore || _loadingMore);
    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 76, color: Color(0xFFF0F0F0)),
      itemBuilder: (context, i) {
        if (i >= visible.length) return _buildFooter();
        return _buildRow(visible[i], isFirst: i == 0);
      },
    );
  }

  /// 加载更多指示（滚动到底自动触发，这里只负责显示状态）
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _loadingMore
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                '上拉加载更多',
                style: TextStyle(color: Color(0xFF999999), fontSize: 13),
              ),
      ),
    );
  }

  Widget _buildRow(ChatConversation c, {bool isFirst = false}) {
    final title = c.title.isEmpty ? _defaultTitle(c) : c.title;
    return InkWell(
      onTap: () => _openChat(c),
      child: Padding(
        // 首行上间距收窄：搜索框下方本就有留白，叠满 12 看着像多出一块空白；
        // 但归零会让头像贴住搜索框、首行明显比其余行矮，取 6 折中
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: isFirst ? 6 : 12,
          bottom: 12,
        ),
        child: Row(
          children: [
            _buildAvatar(c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 群名 + 科室标签整体占满除时间外的宽度（不能用
                      // Flexible + Spacer：两者都是 flex:1 会平分剩余宽度，
                      // 群名只能拿到一半，长群名被无谓截断）
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                // 私聊恒 2 人，不拼成员数
                                c.isPrivate || c.memberCount <= 0
                                    ? title
                                    : '$title(${c.memberCount})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                            if (c.isDepartment) ...[
                              const SizedBox(width: 6),
                              _deptTag(),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(c.lastMessageTime),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (c.hasMention) ...[
                        const Text(
                          '[有人@我] ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFF4D4F),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          c.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 科室群标签（与任务群区分）
  Widget _deptTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _dept.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('科室', style: TextStyle(fontSize: 10, color: _dept)),
    );
  }

  Widget _buildAvatar(ChatConversation c) {
    final badge = c.unreadCount;
    final isDept = c.isDepartment;
    final accent = isDept ? _dept : _primary;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 私聊用对方圆形头像（空/失败回退首字），群聊用方形类型图标
          if (c.isPrivate)
            ChatMemberAvatar(
              avatar: c.avatar,
              username: c.title.isEmpty ? '私' : c.title,
              size: 48,
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDept ? Icons.local_hospital_outlined : Icons.groups,
                color: accent,
                size: 26,
              ),
            ),
          if (badge > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D4F),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return '${two(dt.hour)}:${two(dt.minute)}';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) return '昨天';
    return '${two(dt.month)}-${two(dt.day)}';
  }
}
