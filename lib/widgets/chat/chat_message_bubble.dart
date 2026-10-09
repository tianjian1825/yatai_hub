import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/utils/media_saver.dart';
import 'package:yatai_hub/widgets/image_preview_page.dart';

/// 群聊单条消息气泡
///
/// - 系统灰条（msg_type=2）/ 已撤回：居中灰字
/// - 普通消息：本人右侧蓝气泡 / 他人左侧白气泡，含头像、引用快照(可点)、@高亮、图片宫格
/// - 乐观态：pending 转圈、failed 红叹号(可重发)
class ChatMessageBubble extends StatelessWidget {
  static const Color _primary = Color(0xFF1F6FF4);

  final ChatMessage message;
  final int? currentUserId;
  final bool highlighted;

  /// 点击引用快照块（跳转定位到原消息）
  final void Function(int quoteMessageId)? onQuoteTap;

  /// 长按气泡（弹引用/复制/撤回菜单）
  final void Function(ChatMessage message)? onLongPress;

  /// 失败重发
  final void Function(ChatMessage message)? onRetry;

  /// 长按他人头像（快捷 @ 该成员）
  final void Function(ChatMessage message)? onAvatarLongPress;

  /// 点击他人头像（弹用户名片：基本信息 + 发起私聊）
  final void Function(ChatMessage message)? onAvatarTap;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.currentUserId,
    this.highlighted = false,
    this.onQuoteTap,
    this.onLongPress,
    this.onRetry,
    this.onAvatarLongPress,
    this.onAvatarTap,
  });

  bool get _isMine => message.isMine(currentUserId);

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _buildSystem();

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.68;
    // 他人头像：点击 → 弹用户名片；长按 → 快捷 @ 该成员（自己的头像不响应）
    final canTapAvatar = !_isMine && message.userId > 0 && onAvatarTap != null;
    final canMention =
        !_isMine && message.userId > 0 && onAvatarLongPress != null;
    final avatar = (canTapAvatar || canMention)
        ? GestureDetector(
            onTap: canTapAvatar ? () => onAvatarTap!.call(message) : null,
            onLongPress: canMention
                ? () => onAvatarLongPress!.call(message)
                : null,
            child: _buildAvatar(),
          )
        : _buildAvatar();
    final column = Column(
      crossAxisAlignment: _isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!_isMine && message.username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              message.username,
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_isMine) _buildStatus(),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: GestureDetector(
                onLongPress: message.pending
                    ? null
                    : () => onLongPress?.call(message),
                child: _buildBubbleBody(context),
              ),
            ),
            if (!_isMine) const SizedBox(width: 4),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
          child: Text(
            _formatTime(message.createdAt),
            style: const TextStyle(fontSize: 10, color: Color(0xFFBBBBBB)),
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlighted
          ? _primary.withAlpha((0.12 * 255).round())
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: _isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: _isMine
            ? [Flexible(child: column), const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), Flexible(child: column)],
      ),
    );
  }

  // ——————————————————— 系统灰条 / 撤回 ———————————————————

  Widget _buildSystem() {
    final String text;
    if (message.recalled) {
      text = _isMine
          ? '你撤回了一条消息'
          : '${message.username.isEmpty ? "对方" : message.username} 撤回了一条消息';
    } else {
      text = message.content;
    }
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x14000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
      ),
    );
  }

  // ——————————————————— 气泡体 ———————————————————

  Widget _buildBubbleBody(BuildContext context) {
    final bg = _isMine ? _primary : Colors.white;
    final textColor = _isMine ? Colors.white : const Color(0xFF1A1A1A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: _isMine ? null : Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.quoteMessageId > 0) _buildQuote(),
          if (message.content.isNotEmpty) _buildContent(textColor),
          if (message.media.isNotEmpty) ...[
            if (message.content.isNotEmpty) const SizedBox(height: 6),
            _buildImageGrid(context, message.media),
          ],
        ],
      ),
    );
  }

  Widget _buildQuote() {
    final q = message.quote;
    final onMine = _isMine;
    final boxColor = onMine ? const Color(0x33FFFFFF) : const Color(0xFFF2F3F5);
    final textColor = onMine ? Colors.white70 : const Color(0xFF666666);
    final String text;
    if (q == null) {
      text = '引用的消息不可用';
    } else {
      final preview = q.image.isNotEmpty && q.content.isEmpty
          ? (q.isVideo ? '[视频]' : '[图片]')
          : q.content;
      text = '${q.username.isEmpty ? "用户${q.userId}" : q.username}：$preview';
    }
    return GestureDetector(
      onTap: q == null ? null : () => onQuoteTap?.call(q.messageId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: textColor, height: 1.3),
        ),
      ),
    );
  }

  /// 文本内容，@片段高亮
  Widget _buildContent(Color textColor) {
    final mentionColor = _isMine ? Colors.white : _primary;
    final spans = <TextSpan>[];
    final reg = RegExp(r'@[^\s@]+');
    final content = message.content;
    int last = 0;
    for (final m in reg.allMatches(content)) {
      if (m.start > last) {
        spans.add(TextSpan(text: content.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: content.substring(m.start, m.end),
          style: TextStyle(color: mentionColor, fontWeight: FontWeight.w600),
        ),
      );
      last = m.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, color: textColor, height: 1.4),
        children: spans,
      ),
    );
  }

  // ——————————————————— 图片宫格 ———————————————————

  /// 格子加载缩略图（[ChatMedia.displayUrl]），预览 / 保存到相册仍用原件
  Widget _buildImageGrid(BuildContext context, List<ChatMedia> media) {
    final originals = media.map((e) => e.url).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 0; i < media.length; i++)
          GestureDetector(
            onTap: () => showImagePreview(
              context,
              imageUrls: originals,
              initialIndex: i,
            ),
            onLongPress: () =>
                MediaSaver.showActionSheet(context, originals[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  _buildThumb(media[i], 120),
                  if (media[i].isVideo)
                    const Positioned.fill(
                      child: Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white70,
                          size: 30,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumb(ChatMedia m, double size) {
    // 视频没有截帧（老消息 / 后端截帧失败）时保持黑块，不去把视频当图片加载
    if (m.isVideo && m.thumb.isEmpty) {
      return Container(width: size, height: size, color: Colors.black87);
    }
    return CachedNetworkImage(
      imageUrl: m.displayUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        width: size,
        height: size,
        color: const Color(0xFFF0F0F0),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      // 截帧文件可能是 0 字节（后端 ffmpeg 失败时会落空文件）→ 回退黑块
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        color: m.isVideo ? Colors.black87 : const Color(0xFFF0F0F0),
        child: m.isVideo
            ? null
            : const Icon(
                Icons.broken_image,
                color: Color(0xFFBBBBBB),
                size: 24,
              ),
      ),
    );
  }

  // ——————————————————— 头像 / 状态 / 时间 ———————————————————

  Widget _buildAvatar() {
    final url = _normalizeAvatar(message.avatar);
    if (url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          placeholder: (_, _) => _avatarFallback(),
          errorWidget: (_, _, _) => _avatarFallback(),
        ),
      );
    }
    return _avatarFallback();
  }

  /// 头像 URL 规范化：后端通常已拼完整 URL；若仍是相对路径则补域名前缀兜底。
  String _normalizeAvatar(String a) {
    if (a.isEmpty) return '';
    if (a.startsWith('http://') || a.startsWith('https://')) return a;
    return 'https://img-kf.beise.com${a.startsWith('/') ? a : '/$a'}';
  }

  Widget _avatarFallback() {
    final ch = message.username.isEmpty
        ? '?'
        : message.username.characters.first;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE8F0FE),
        shape: BoxShape.circle,
      ),
      child: Text(
        ch,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _primary,
        ),
      ),
    );
  }

  /// 本人气泡左侧的发送状态（转圈 / 失败重发）
  Widget _buildStatus() {
    if (message.pending) {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
      );
    }
    if (message.failed) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => onRetry?.call(message),
          child: const Icon(Icons.error, color: Color(0xFFFF4D4F), size: 20),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
