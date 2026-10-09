import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// 轻量浮层提示（Overlay 实现）
///
/// 用 `rootOverlay` 插到最上层，因此在 bottomSheet / Dialog 之上也能看见——
/// `ScaffoldMessenger` 的 SnackBar 会被打开的底部弹窗挡住，弹窗内提示一律用本方法。
///
/// 外观：毛玻璃深色胶囊 + 图标，淡入上浮进场、淡出退场；连续调用时替换上一条
/// （不会叠成两层）。
void showOverlayToast(
  BuildContext context,
  String message, {
  IconData? icon = Icons.check_circle_outline,
  Duration duration = const Duration(milliseconds: 1400),
}) {
  if (message.trim().isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
    return;
  }

  // 上一条还在就先撤掉，避免两条叠在一起
  _dismissCurrent();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastLayer(
      message: message,
      icon: icon,
      visible: duration,
      onDismissed: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

void _dismissCurrent() {
  final prev = _current;
  _current = null;
  if (prev != null && prev.mounted) prev.remove();
}

class _ToastLayer extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Duration visible;
  final VoidCallback onDismissed;

  const _ToastLayer({
    required this.message,
    required this.icon,
    required this.visible,
    required this.onDismissed,
  });

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(widget.visible, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 24,
      right: 24,
      // 键盘弹起时跟着上移，避免落到输入法后面
      bottom: bottomInset + MediaQuery.of(context).size.height * 0.18,
      child: IgnorePointer(
        // 必须包 Material：Overlay 里没有 Material 祖先时 DefaultTextStyle 是
        // Flutter 的 _errorTextStyle（红字 + 黄色双下划线），Text 只覆盖了颜色
        // 字号，decoration 会被继承下来，文字底下就多出两条黄线。
        child: Material(
          type: MaterialType.transparency,
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(_curve),
              child: Center(child: _buildPill()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill() {
    // 毛玻璃只有「透出背后内容」才看得出来：底色压到 0.55、blur 加到 26，
    // 背后的文字/头像会明显被磨成色块（纯色区域上仍近似半透明胶囊）。
    // 文字靠 shadow 提高对比，保证半透明底下依然清晰。
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2430).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 17, color: Colors.white),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    // 显式关掉下划线，双保险（另一层保障是外面的 Material）
                    decoration: TextDecoration.none,
                    // 半透明底色下压住背景文字，保证可读
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
