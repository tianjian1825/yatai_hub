import 'package:flutter/material.dart';

/// 统一的列表空状态组件。
///
/// 视觉规范（全项目统一）：
/// - 图标：64px，颜色 `0xFFB8C0CC`
/// - 主文案：14px，颜色 `0xFF999999`
/// - 副文案（可选）：12px，颜色 `0xFFBBBBBB`
///
/// 默认自带居中布局（`Center` + `Padding`），可直接放入 `body`。
/// 若需放进可滚动列表以支持下拉刷新，请在外层包裹固定高度的容器，
/// 例如 `ListView(children: [SizedBox(height: 360, child: EmptyStateWidget(...))])`。
class EmptyStateWidget extends StatelessWidget {
  /// 空状态图标，按页面语义传入，默认 `Icons.inbox_outlined`。
  final IconData icon;

  /// 主文案，必填。
  final String message;

  /// 副文案，可选，展示在主文案下方。
  final String? description;

  /// 图标尺寸，默认遵循规范 64px。
  final double iconSize;

  /// 可选操作区（如「刷新」「去上传」按钮），展示在文案下方。
  final Widget? action;

  /// 整体内边距。
  final EdgeInsetsGeometry padding;

  const EmptyStateWidget({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.description,
    this.iconSize = 64,
    this.action,
    this.padding = const EdgeInsets.all(32),
  });

  static const Color _iconColor = Color(0xFFB8C0CC);
  static const Color _titleColor = Color(0xFF999999);
  static const Color _subtitleColor = Color(0xFFBBBBBB);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: _iconColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _titleColor),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _subtitleColor),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
