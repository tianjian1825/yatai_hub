import 'package:flutter/material.dart';

/// 全局统一的搜索输入框。
///
/// 统一三件事：
/// 1. 外观 —— 高 40 / 圆角 8 / 底色 [fillColor]（默认 `#F6F6F6`）；
/// 2. 前置图标 —— 一律 `Icons.search` 20px `#B2B2B2`（此前随心拍用的是
///    `assets/images/history_search.png`，消息/通讯录用的是 `#999999`）；
/// 3. 图标与文字的纵向对齐 —— 输入框走 `isCollapsed` + 零 padding，让它的
///    高度等于文本行高，再由 Row 统一居中。旧写法（`contentPadding:
///    vertical: 10` + `isDense`，或 `prefixIcon` + `contentPadding: zero`）
///    会让 Material 额外预留 baseline 空间，文字中线比图标低 1~2px。
///
/// 尾部按钮按需拼装：[showClear] 打开后有输入内容时自动出现清除图标，
/// [onSearch] 非空时出现文字按钮（[searchLabel]）。
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.onSearch,
    this.searchLabel = '搜索',
    this.actionColor = const Color(0xFF709BF7),
    this.showClear = false,
    this.onClear,
    this.textInputAction = TextInputAction.search,
    this.fillColor = const Color(0xFFF6F6F6),
  });

  final TextEditingController controller;
  final String hintText;

  /// 为 false 时输入与搜索按钮同时禁用（当前无调用方使用，留给「该筛选下搜索无意义」的场景）。
  final bool enabled;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 非空时在尾部显示文字按钮；为空则不显示（即时搜索的页面用不到）。
  final VoidCallback? onSearch;
  final String searchLabel;

  /// 搜索按钮文字色，各业务模块主色不同（随心拍蓝、会议纪要粉）。
  final Color actionColor;

  /// 是否启用清除按钮；启用后由本组件监听 [controller] 决定显隐。
  final bool showClear;
  final VoidCallback? onClear;

  final TextInputAction textInputAction;
  final Color fillColor;

  static const Color _iconColor = Color(0xFFB2B2B2);
  static const Color _hintColor = Color(0xFFB2B2B2);
  static const Color _textColor = Color(0xFF333333);
  static const Color _disabledActionColor = Color(0xFFCCCCCC);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, size: 20, color: _iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: textInputAction,
              style: const TextStyle(fontSize: 14, color: _textColor),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(fontSize: 14, color: _hintColor),
                // isCollapsed + 零 padding 是对齐的关键，勿改回 isDense
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (showClear)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    controller.clear();
                    onClear?.call();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Icon(Icons.close, size: 18, color: _iconColor),
                  ),
                );
              },
            ),
          if (onSearch != null)
            TextButton(
              onPressed: enabled ? onSearch : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                searchLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? actionColor : _disabledActionColor,
                ),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
