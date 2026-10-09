import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/chat_member_avatar.dart';

/// @提及选择结果：@所有人 或 @某成员
class MentionTarget {
  final bool all;
  final int userId;
  final String username;
  const MentionTarget.all() : all = true, userId = 0, username = '';
  const MentionTarget.member(this.userId, this.username) : all = false;
}

/// @提及成员选择浮层（成员列表 + @所有人）。
/// 排除当前用户自己（[selfUserId]）。
Future<MentionTarget?> showMentionPicker(
  BuildContext context,
  ChatTarget target, {
  int? selfUserId,
}) {
  return showChatBottomSheet<MentionTarget>(
    context: context,
    builder: (_) => _MentionPickerSheet(target: target, selfUserId: selfUserId),
  );
}

class _MentionPickerSheet extends StatefulWidget {
  final ChatTarget target;
  final int? selfUserId;
  const _MentionPickerSheet({required this.target, this.selfUserId});

  @override
  State<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<_MentionPickerSheet> {
  static const Color _primary = Color(0xFF1F6FF4);

  bool _loading = true;
  List<ChatMember> _list = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ParttimeChatService().getMembers(widget.target);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _list = r.list
          .where((m) => m.userId != (widget.selfUserId ?? -1))
          .toList();
      _error = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            const ChatSheetHandle(),
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                '选择提醒的人',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
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
      itemCount: _list.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F0FE),
              child: Icon(Icons.group, color: _primary, size: 20),
            ),
            title: const Text('所有人'),
            onTap: () => Navigator.of(context).pop(const MentionTarget.all()),
          );
        }
        final m = _list[i - 1];
        return ListTile(
          leading: ChatMemberAvatar(avatar: m.avatar, username: m.username),
          title: Text(m.username.isEmpty ? '用户${m.userId}' : m.username),
          onTap: () => Navigator.of(
            context,
          ).pop(MentionTarget.member(m.userId, m.username)),
        );
      },
    );
  }
}
