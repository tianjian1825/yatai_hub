import 'package:flutter/material.dart';

/// 底栏单项配置。图标优先用 asset（[assetIcon]/[assetActiveIcon]），
/// 无 asset 时用 Material 图标 [materialIcon]（如动态「消息」Tab）。
class BottomTabItem {
  final String label;
  final String? assetIcon;
  final String? assetActiveIcon;
  final IconData? materialIcon;

  /// 右上角未读小红点
  final bool showBadge;

  const BottomTabItem({
    required this.label,
    this.assetIcon,
    this.assetActiveIcon,
    this.materialIcon,
    this.showBadge = false,
  });
}

/// 底部导航栏组件（声明式）
///
/// 由 MainPage 按角色 + 动态「消息」Tab 计算 [items] 后传入，本组件纯渲染。
class BottomTabbar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomTabItem> items;

  const BottomTabbar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  static const Color _active = Color(0xFF2979FF);
  static const Color _inactive = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD7DDED).withAlpha((0.5 * 255).round()),
            offset: const Offset(0, -4),
            blurRadius: 20,
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < items.length; i++) _buildTabItem(i, items[i]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, BottomTabItem item) {
    final isActive = currentIndex == index;
    final color = isActive ? _active : _inactive;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIcon(item, isActive, color),
            const SizedBox(height: 6),
            Text(item.label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(BottomTabItem item, bool isActive, Color color) {
    Widget icon;
    if (item.assetIcon != null) {
      icon = Image.asset(
        isActive ? (item.assetActiveIcon ?? item.assetIcon!) : item.assetIcon!,
        width: 22,
        height: 22,
        errorBuilder: (context, error, stackTrace) =>
            Icon(item.materialIcon ?? Icons.circle, size: 22, color: color),
      );
    } else {
      icon = Icon(item.materialIcon ?? Icons.circle, size: 22, color: color);
    }
    if (!item.showBadge) return icon;
    return SizedBox(
      width: 28,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          icon,
          Positioned(
            right: 0,
            top: -2,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D4F),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
