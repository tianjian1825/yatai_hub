import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_member_avatar.dart';
import 'package:yatai_hub/widgets/chat/chat_staff_picker_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_user_card_sheet.dart';

/// 群成员列表（AppBar 三点入口）。
/// can_manage=true（发起人/责任客服/管理员）显示「邀请」+ 每行(非群主/非自己)「移除」；
/// 兼职用户、以及**科室群**（成员随科室自动同步）后端返回 can_manage=false，
/// 自动只读。本期不做退群。
///
/// 点一行（自己那行除外）弹 [ChatUserCardSheet] 用户名片，可从名片发起私聊。真选了
/// 私聊就把本弹窗一起 pop 掉并把 [ChatPrivateChatIntent] 交回调用方跳转——弹窗不
/// 自己 push 路由（widgets 不依赖 pages），也免得私聊页压在两层 sheet 底下。
///
/// [viewerRoleid] 透传给名片（只用于决定是否查通讯录拿手机号，不影响私聊按钮显隐）。
Future<ChatPrivateChatIntent?> showChatMembersSheet(
  BuildContext context,
  ChatTarget target, {
  required int viewerRoleid,
}) {
  return showChatBottomSheet<ChatPrivateChatIntent>(
    context: context,
    builder: (_) =>
        ChatMembersSheet(target: target, viewerRoleid: viewerRoleid),
  );
}

class ChatMembersSheet extends StatefulWidget {
  final ChatTarget target;
  final int viewerRoleid;
  const ChatMembersSheet({
    super.key,
    required this.target,
    required this.viewerRoleid,
  });

  @override
  State<ChatMembersSheet> createState() => _ChatMembersSheetState();
}

class _ChatMembersSheetState extends State<ChatMembersSheet> {
  static const Color _primary = Color(0xFF1F6FF4);

  bool _loading = true;
  bool _busy = false;
  List<ChatMember> _list = const [];
  bool _canManage = false;
  String? _error;

  /// 当前登录用户，用于标「我」并隐藏自己的移除按钮
  int? _selfUserId;

  @override
  void initState() {
    super.initState();
    _loadSelf();
    _load();
  }

  Future<void> _loadSelf() async {
    final id = int.tryParse(await UserService().getBackendUserId() ?? '');
    if (mounted && id != null) setState(() => _selfUserId = id);
  }

  Future<void> _load() async {
    final r = await ParttimeChatService().getMembers(widget.target);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _list = r.list;
      _canManage = r.canManage;
      _error = r.message;
    });
  }

  Future<void> _invite() async {
    final existing = _list.map((m) => m.userId).toSet();
    final picked = await showChatStaffPicker(
      context,
      existingMemberIds: existing,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final r = await ParttimeChatService().invite(
      target: widget.target,
      userIds: picked,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.success) _list = r.list;
    });
    _toast(r.success ? '已邀请 ${r.added.length} 人' : (r.message ?? '邀请失败'));
  }

  Future<void> _remove(ChatMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定将「${m.username}」移出群聊？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除', style: TextStyle(color: Color(0xFFFF4D4F))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final r = await ParttimeChatService().removeMember(
      target: widget.target,
      userId: m.userId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.success) _list = r.list;
    });
    if (!r.success) _toast(r.message ?? '移除失败');
  }

  /// 点一行：弹用户名片（资料 + 拨号 + 发起私聊）。发起了私聊就连本弹窗一起关，
  /// 把结果交回 [showChatMembersSheet] 的调用方去跳转。
  Future<void> _openCard(ChatMember m) async {
    if (m.userId <= 0) return;
    final intent = await showChatUserCardSheet(
      context,
      userId: m.userId,
      username: m.username,
      avatar: m.avatar,
      roleid: m.roleid,
      viewerRoleid: widget.viewerRoleid,
    );
    if (intent == null || !mounted) return;
    Navigator.pop(context, intent);
  }

  /// 弹窗内提示必须用浮层：SnackBar 会被这个 bottomSheet 挡住
  void _toast(String msg) {
    if (!mounted) return;
    showOverlayToast(context, msg, icon: Icons.info_outline);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const ChatSheetHandle(),
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Text(
            '群成员${_list.isEmpty ? '' : '(${_list.length})'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (_canManage)
            TextButton.icon(
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('邀请'),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xFF999999))),
      );
    }
    return ListView.separated(
      itemCount: _list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _list[i];
        final isSelf = _selfUserId != null && m.userId == _selfUserId;
        return ListTile(
          // 自己那行不弹名片（没有跟自己私聊这回事）
          onTap: (_busy || isSelf) ? null : () => _openCard(m),
          leading: ChatMemberAvatar(avatar: m.avatar, username: m.username),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  m.username.isEmpty ? '用户${m.userId}' : m.username,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (m.isOwner) ...[
                const SizedBox(width: 6),
                _tag('群主', _primary),
              ],
              if (isSelf) ...[
                const SizedBox(width: 6),
                _tag('我', const Color(0xFF34C759)),
              ],
            ],
          ),
          // 群主与自己都不给移除按钮（退群本期不做）
          trailing: (_canManage && !m.isOwner && !isSelf)
              ? TextButton(
                  onPressed: _busy ? null : () => _remove(m),
                  child: const Text(
                    '移除',
                    style: TextStyle(color: Color(0xFFFF4D4F)),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
