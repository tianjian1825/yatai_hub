import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_contact.dart';
import 'package:yatai_hub/pages/chat/chat_page.dart';
import 'package:yatai_hub/services/chat_message_repository.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:yatai_hub/utils/phone_dialer.dart';
import 'package:yatai_hub/widgets/app_search_field.dart';
import 'package:yatai_hub/widgets/chat/chat_member_avatar.dart';

/// 通讯录（私聊入口）—— 列全部兼职人员，点击发起或继续私聊
///
/// 仅 `roleid ≠ 275` 的账号可用（后端接口本身也拦兼职），入口在「消息」Tab 右上角。
/// 本地缓存秒显 + 网络对齐；搜索走接口（有分页），失败/离线回退本地模糊匹配。
///
/// 点击一行（列表不区分两种情况，对用户是同一个动作）：
/// - `conv_id > 0`（已有会话）→ 直接进 [ChatPage]，跳过 private/open
/// - `conv_id == 0` → 先 `chat/private/open` get-or-create 拿会话 ID 再进
///
/// 行右侧有 `mobile` 时给拨号按钮（[_dial] 调系统拨号盘），与整行点击互不干扰。
class ChatContactsPage extends StatefulWidget {
  const ChatContactsPage({super.key});

  @override
  State<ChatContactsPage> createState() => _ChatContactsPageState();
}

class _ChatContactsPageState extends State<ChatContactsPage> {
  static const Color _primary = Color(0xFF1F6FF4);

  final ChatMessageRepository _repo = ChatMessageRepository();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<ChatContact> _list = [];

  Timer? _debounce;
  String _keyword = '';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// 正在发起私聊的联系人（行内转圈，避免重复点）
  int _openingUserId = 0;

  bool get _hasMore => _list.length < _total;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        !_loading &&
        _hasMore) {
      _load();
    }
  }

  Future<void> _bootstrap() async {
    final local = await _repo.localContacts();
    if (mounted && local.isNotEmpty) {
      setState(() {
        _list
          ..clear()
          ..addAll(local);
        _total = local.length;
        _loading = false;
      });
    }
    await _load(refresh: true);
  }

  void _onSearchChanged(String v) {
    setState(() {}); // 清除按钮随输入即时显隐（请求本身仍去抖）
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _keyword = v.trim();
      _load(refresh: true);
    });
  }

  // 搜索去抖与下拉刷新可能并发，用代次只采纳最后一次拉取，
  // 避免上一个关键词的结果盖掉当前关键词的列表。
  int _loadGen = 0;
  Future<void> _load({bool refresh = false}) async {
    final gen = ++_loadGen;
    if (refresh) {
      setState(() {
        if (_list.isEmpty) _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final r = await _repo.fetchContacts(
      keyword: _keyword,
      page: refresh ? 1 : _page + 1,
    );
    if (!mounted || gen != _loadGen) return;
    if (r.message != null) {
      // 网络失败：刷新时回退本地（离线可用），加载更多时只提示
      if (refresh) {
        final local = await _repo.localContacts(keyword: _keyword);
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _loading = false;
          _list
            ..clear()
            ..addAll(local);
          _total = local.length;
          _error = local.isEmpty ? r.message : null;
        });
      } else {
        setState(() => _loadingMore = false);
        _toast(r.message!);
      }
      return;
    }
    setState(() {
      if (refresh) {
        _list
          ..clear()
          ..addAll(r.list);
        _loading = false;
        _error = null;
      } else {
        _list.addAll(r.list);
        _page += 1;
        _loadingMore = false;
      }
      _total = r.total;
    });
  }

  /// 点击一行：已有会话直接进，否则先 get-or-create
  Future<void> _openChat(ChatContact c) async {
    if (_openingUserId != 0) return;
    if (c.hasConversation) {
      _pushChat(convId: c.convId, title: c.username);
      return;
    }
    setState(() => _openingUserId = c.userId);
    final r = await ParttimeChatService().openPrivateChat(c.userId);
    if (!mounted) return;
    setState(() => _openingUserId = 0);
    if (!r.success || r.taskId <= 0) {
      _toast(r.message ?? '发消息失败');
      return;
    }
    // 会话 ID 写回本地 + 内存，下次点该人不再打 open
    // ignore: discarded_futures
    _repo.cacheContactConvId(c.userId, r.taskId);
    final idx = _list.indexWhere((e) => e.userId == c.userId);
    if (idx >= 0) {
      setState(() => _list[idx] = _list[idx].copyWith(convId: r.taskId));
    }
    _pushChat(
      convId: r.taskId,
      title: r.peerName.isNotEmpty ? r.peerName : c.username,
    );
  }

  /// 从私聊页返回后**不**重新拉通讯录：聊天不会改变联系人行的任何展示内容，
  /// `conv_id` 也已在 [_openChat] 里同步到内存与本地库，再打一次纯属浪费请求。
  void _pushChat({required int convId, required String title}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          taskId: convId,
          convType: 3,
          title: title.isEmpty ? '私聊' : title,
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    showOverlayToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '通讯录',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: AppSearchField(
        controller: _searchCtrl,
        hintText: '搜索姓名',
        onChanged: _onSearchChanged,
        showClear: true,
        onClear: () {
          _keyword = '';
          FocusScope.of(context).unfocus();
          _load(refresh: true);
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.isEmpty) {
      final text =
          _error ?? (_keyword.isEmpty ? '暂无联系人' : '未找到「$_keyword」相关人员');
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF999999), fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _list.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 72, color: Color(0xFFF0F0F0)),
      itemBuilder: (context, i) {
        if (i >= _list.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildRow(_list[i]);
      },
    );
  }

  Widget _buildRow(ChatContact c) {
    final name = c.username.isEmpty ? '用户${c.userId}' : c.username;
    final opening = _openingUserId == c.userId;
    return InkWell(
      onTap: opening ? null : () => _openChat(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ChatMemberAvatar(avatar: c.avatar, username: name, size: 44),
            const SizedBox(width: 12),
            // 不区分「已有会话 / 新建」：`conv_id` 只用于内部跳过 private/open，
            // 已有会话本来也会出现在「消息」Tab，列表统一单行更干净
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            // 发起私聊中（private/open 在飞）：转圈占位，避免行内毫无反馈
            if (opening) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            // 拨号：行右侧唯一的按钮（进私聊是整行点击，不再放聊天图标）。
            // IconButton 自带手势识别会吃掉点击，不会冒泡触发整行的「进私聊」。
            // 后端没给 mobile（未登记）时不显示。
            if (c.hasMobile)
              IconButton(
                icon: const Icon(Icons.phone_outlined, size: 20),
                color: _primary,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                tooltip: '拨打 ${c.mobile}',
                onPressed: () => _dial(c.mobile),
              ),
          ],
        ),
      ),
    );
  }

  /// 调起系统拨号盘（实现与群聊用户名片共用 [dialPhoneNumber]）
  Future<void> _dial(String mobile) async {
    final err = await dialPhoneNumber(mobile);
    if (err != null) _toast(err);
  }
}
