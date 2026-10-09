import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yatai_hub/utils/map_launcher.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';

/// 群聊内「医院信息查询 / 客户资料查询」两个弹窗共用的展示组件。
///
/// 统一约定：
/// - 每行右侧一个复制按钮（点一下复制值，弹 toast），整行长按也可复制；
/// - 地址行整行可点 → 拉起系统地图导航（[openAddressInMap]）；
/// - 值为空的行由调用方直接不渲染（不显示 "-" 占位）。
const Color kQuerySheetPrimary = Color(0xFF1F6FF4);
const Color kQuerySheetLabel = Color(0xFF999999);
const Color kQuerySheetValue = Color(0xFF333333);

void copyToClipboard(BuildContext context, String label, String value) {
  final text = value.trim();
  if (text.isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  // SnackBar 会被打开的底部弹窗遮住，这里用 rootOverlay 浮层提示
  showOverlayToast(context, '$label 已复制');
}

/// 一行「标签 + 值 + 复制按钮」
class QueryInfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// 值为地址时传入：整行可点 → 打开地图导航
  final bool isAddress;

  /// 值可点跳转（如官网）时传入
  final VoidCallback? onTapValue;

  /// 是否可复制。枚举型的值（如合作状态）复制没意义，传 false 去掉复制入口
  final bool copyable;

  const QueryInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.isAddress = false,
    this.onTapValue,
    this.copyable = true,
  });

  @override
  Widget build(BuildContext context) {
    final tappable = isAddress || onTapValue != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tappable
          ? () {
              if (onTapValue != null) {
                onTapValue!();
              } else {
                openAddressInMap(context, value);
              }
            }
          : null,
      onLongPress: copyable
          ? () => copyToClipboard(context, label, value)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: kQuerySheetLabel),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: tappable ? kQuerySheetPrimary : kQuerySheetValue,
                ),
              ),
            ),
            if (isAddress)
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 1),
                child: Icon(
                  Icons.navigation_outlined,
                  size: 15,
                  color: kQuerySheetPrimary,
                ),
              ),
            if (copyable)
              _CopyButton(onTap: () => copyToClipboard(context, label, value)),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CopyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.only(left: 8, right: 2, top: 1),
        child: Icon(Icons.copy_rounded, size: 15, color: kQuerySheetPrimary),
      ),
    );
  }
}

/// 分组卡片：标题 + 右上角「复制本组」+ 内容
class QuerySection extends StatelessWidget {
  final String title;

  /// 「复制本组」用的纯文本；为空则不显示该按钮
  final String? copyPayload;
  final List<Widget> children;

  const QuerySection({
    super.key,
    required this.title,
    required this.children,
    this.copyPayload,
  });

  @override
  Widget build(BuildContext context) {
    final payload = copyPayload?.trim() ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ),
              if (payload.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => copyToClipboard(context, title, payload),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '复制本组',
                      style: TextStyle(fontSize: 12, color: kQuerySheetPrimary),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// 弹窗顶部标题栏
class QuerySheetHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const QuerySheetHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 加载失败占位（带重试）
class QuerySheetError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const QuerySheetError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Color(0xFFB2B2B2)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
