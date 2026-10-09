import 'package:flutter/material.dart';

/// 群聊相关底部弹窗的统一外壳与元件
///
/// 群聊里有 6 个底部弹窗（更多菜单、消息长按菜单、群成员、@选人、邀请成员、
/// 医院/客户查询），此前各自写 `showModalBottomSheet` 参数，圆角、遮罩深浅、
/// 有无拖拽条都不一致。统一走 [showChatBottomSheet] + [ChatSheetHandle]。
const Color kChatSheetPrimary = Color(0xFF1F6FF4);
const Color kChatSheetDanger = Color(0xFFFF4D4F);

Future<T?> showChatBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: builder,
  );
}

/// 顶部拖拽指示条（提示"可下拉关闭"）
class ChatSheetHandle extends StatelessWidget {
  const ChatSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E2E6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 菜单型弹窗的一行操作（圆底图标 + 标题）
class ChatSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 破坏性操作（撤回等）用红色
  final bool danger;

  const ChatSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? kChatSheetDanger : kChatSheetPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: danger ? kChatSheetDanger : const Color(0xFF1E1E1E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单型弹窗容器：拖拽条 + 操作列表 + 安全区
class ChatSheetMenu extends StatelessWidget {
  final List<Widget> actions;

  const ChatSheetMenu({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChatSheetHandle(),
          const SizedBox(height: 4),
          ...actions,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
