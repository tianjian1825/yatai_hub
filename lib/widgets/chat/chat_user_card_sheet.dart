import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yatai_hub/models/chat_contact.dart';
import 'package:yatai_hub/services/chat_message_repository.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:yatai_hub/utils/phone_dialer.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_member_avatar.dart';

/// 「发起私聊」的结果。弹窗自己不 push 路由（widgets 不依赖 pages），
/// 由调用方拿这个去 push `ChatPage(convType: 3, taskId: convId)`。
class ChatPrivateChatIntent {
  final int convId;
  final String peerName;
  const ChatPrivateChatIntent({required this.convId, required this.peerName});
}

/// 群聊内点他人头像弹出的用户名片：基本信息 + 拨号 + 发起私聊
///
/// 底部按钮（文案「发消息」）**不按角色显隐**：群里点到谁都能发起（后端会放开
/// `chat/private/open` 原先「仅非兼职可发起、对方必须是兼职」的限制）。因此这里
/// 只挡两种情况：私聊页内部（[allowPrivateChat]=false，已经在跟对方聊了）和
/// 非法 user_id。真发不出去时由后端 msg 原样提示，不在前端提前判死。
///
/// 数据来源只有两处，**不存在「查某个用户详情」的接口**：
/// - 消息体自带的 user_id / username / avatar / roleid（立即可显）
/// - 通讯录（`/v1/parttime_task/contacts`）里的 `mobile` 与 `conv_id`：先查本地
///   缓存表，没命中再按姓名打一次通讯录接口兜底。该接口目前只列兼职、且仅
///   roleid≠275 可访问，所以查不到手机号是常态（名片就不显示手机号那行），
///   查得到只是顺带把号码和已有会话 ID 一起拿到（后者可跳过 private/open）。
///
/// [viewerRoleid] 由调用方传入（ChatPage 已有 `_myRole`），兼职查看者直接跳过
/// 通讯录查询——接口对他关闭，白打一次 403。
Future<ChatPrivateChatIntent?> showChatUserCardSheet(
  BuildContext context, {
  required int userId,
  required String username,
  required String avatar,
  required int roleid,
  required int viewerRoleid,
  bool allowPrivateChat = true,
}) {
  return showChatBottomSheet<ChatPrivateChatIntent>(
    context: context,
    isScrollControlled: false,
    builder: (_) => ChatUserCardSheet(
      userId: userId,
      username: username,
      avatar: avatar,
      roleid: roleid,
      viewerRoleid: viewerRoleid,
      allowPrivateChat: allowPrivateChat,
    ),
  );
}

class ChatUserCardSheet extends StatefulWidget {
  final int userId;
  final String username;
  final String avatar;
  final int roleid;
  final int viewerRoleid;
  final bool allowPrivateChat;

  const ChatUserCardSheet({
    super.key,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.roleid,
    required this.viewerRoleid,
    this.allowPrivateChat = true,
  });

  @override
  State<ChatUserCardSheet> createState() => _ChatUserCardSheetState();
}

class _ChatUserCardSheetState extends State<ChatUserCardSheet> {
  static const Color _primary = Color(0xFF1F6FF4);

  final ChatMessageRepository _repo = ChatMessageRepository();

  ChatContact? _contact;
  bool _opening = false;

  /// 查看者是兼职：通讯录接口对他关闭，不去查手机号（不影响发起私聊）
  bool get _viewerIsPartTime => widget.viewerRoleid == UserService.rolePartTime;

  /// 对方是兼职（只认消息体给的 roleid：通讯录命中不再作为判据——放开限制后
  /// 名片可能是任意角色，而通讯录只收兼职，拿它反推会漏判也会误判）
  bool get _peerIsPartTime => widget.roleid == UserService.rolePartTime;

  bool get _canPrivateChat => widget.allowPrivateChat && widget.userId > 0;

  String get _name =>
      widget.username.trim().isEmpty ? '用户${widget.userId}' : widget.username;

  String get _avatar {
    final fromContact = _contact?.avatar ?? '';
    return fromContact.isNotEmpty ? fromContact : widget.avatar;
  }

  String get _mobile => _contact?.mobile.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _lookupContact();
  }

  /// 本地通讯录命中即用（手机号 + conv_id 都在里面）；没命中再按姓名打一次接口。
  /// 兼职查看者直接跳过——接口会拒。
  Future<void> _lookupContact() async {
    if (_viewerIsPartTime || widget.userId <= 0) return;
    final local = await _repo.localContact(widget.userId);
    if (!mounted) return;
    if (local != null) {
      setState(() => _contact = local);
      return;
    }
    final keyword = widget.username.trim();
    if (keyword.isEmpty) return;
    // 关键词查询不落库（残缺子集会污染离线快照），只取本次命中的那一行
    final r = await _repo.fetchContacts(keyword: keyword, pageSize: 50);
    if (!mounted) return;
    ChatContact? hit;
    for (final e in r.list) {
      if (e.userId == widget.userId) {
        hit = e;
        break;
      }
    }
    if (hit != null) setState(() => _contact = hit);
  }

  Future<void> _openPrivateChat() async {
    if (_opening) return;
    // 通讯录里已有会话 ID：直接进，跳过 private/open
    final existing = _contact?.convId ?? 0;
    if (existing > 0) {
      Navigator.pop(
        context,
        ChatPrivateChatIntent(convId: existing, peerName: _name),
      );
      return;
    }
    setState(() => _opening = true);
    final r = await ParttimeChatService().openPrivateChat(widget.userId);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!r.success || r.taskId <= 0) {
      _toast(r.message ?? '发消息失败');
      return;
    }
    // ignore: discarded_futures
    _repo.cacheContactConvId(widget.userId, r.taskId);
    if (!mounted) return;
    Navigator.pop(
      context,
      ChatPrivateChatIntent(
        convId: r.taskId,
        peerName: r.peerName.isNotEmpty ? r.peerName : _name,
      ),
    );
  }

  Future<void> _dial() async {
    final err = await dialPhoneNumber(_mobile);
    if (err != null) _toast(err);
  }

  void _copyMobile() {
    Clipboard.setData(ClipboardData(text: _mobile));
    _toast('已复制手机号', icon: Icons.check_circle_outline);
  }

  /// 弹窗内提示必须走浮层：SnackBar 会被 bottomSheet 挡住
  void _toast(String msg, {IconData icon = Icons.info_outline}) {
    if (!mounted) return;
    showOverlayToast(context, msg, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChatSheetHandle(),
          _buildHeader(),
          if (_mobile.isNotEmpty) ...[
            const Divider(height: 1),
            _buildMobileRow(),
          ],
          if (_canPrivateChat) ...[
            const SizedBox(height: 8),
            _buildPrivateChatButton(),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          ChatMemberAvatar(avatar: _avatar, username: _name, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
                if (_peerIsPartTime) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '兼职',
                      style: TextStyle(fontSize: 11, color: _primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          const Text(
            '手机号',
            style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _mobile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: const Color(0xFF999999),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            tooltip: '复制',
            onPressed: _copyMobile,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.phone_outlined, size: 20),
            color: _primary,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            tooltip: '拨打 $_mobile',
            onPressed: _dial,
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateChatButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: _opening ? null : _openPrivateChat,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          icon: _opening
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('发消息'),
        ),
      ),
    );
  }
}
