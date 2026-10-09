import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 群成员圆形头像：有 avatar 时显示网络图（磁盘缓存 + 缩放解码），
/// avatar 为空 / 加载中 / 加载失败均回退首字文字头像。
/// 群成员列表与 @提及选择器共用。
class ChatMemberAvatar extends StatelessWidget {
  final String avatar;
  final String username;
  final double size;

  const ChatMemberAvatar({
    super.key,
    required this.avatar,
    required this.username,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: const Color(0xFFE8F0FE),
      alignment: Alignment.center,
      child: Text(
        username.isEmpty ? '?' : username.characters.first,
        style: const TextStyle(color: Color(0xFF1F6FF4), fontSize: 16),
      ),
    );
    return ClipOval(
      child: avatar.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: avatar,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * 3).round(),
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}
