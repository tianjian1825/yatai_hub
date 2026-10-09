import 'package:flutter/material.dart';

/// 护照拍摄注意事项 —— 全局复用的说明底部弹窗 + 可点击提示入口。
///
/// 所有「护照拍照上传识别」的页面都应在上传入口旁放一个 [PassportCaptureGuideHint]，
/// 用户点击后弹出 [showPassportCaptureGuide]，指导如何拍出可被 OCR 识别的护照照片。
/// 文案对齐《护照拍摄规范》原型。

const Color _kPrimary = Color(0xFF1F6FF4);

/// 弹出「护照拍摄注意事项」底部说明弹窗。
Future<void> showPassportCaptureGuide(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _PassportCaptureGuideSheet(),
  );
}

/// 上传入口旁的「拍摄注意事项」提示行，点击弹出说明。
class PassportCaptureGuideHint extends StatelessWidget {
  /// 提示文案，默认「如何拍出可识别的护照？」。
  final String text;

  /// 是否使用紧凑样式（仅一行小字 + 箭头，适合放在按钮附近）。
  final bool compact;

  const PassportCaptureGuideHint({
    super.key,
    this.text = '如何拍出可识别的护照？',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showPassportCaptureGuide(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 14, color: _kPrimary),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: _kPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _kPrimary),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showPassportCaptureGuide(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.camera_alt_outlined, size: 16, color: _kPrimary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  color: _kPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              '查看拍摄注意事项',
              style: TextStyle(fontSize: 12, color: _kPrimary),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _kPrimary),
          ],
        ),
      ),
    );
  }
}

class _PassportCaptureGuideSheet extends StatelessWidget {
  const _PassportCaptureGuideSheet();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: _kPrimary, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '护照拍摄规范',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    splashRadius: 18,
                    color: const Color(0xFF999999),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 样本护照示例：叠加 1/2/3 拍摄要点标记（对齐原型）
                    _sampleFigure(),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        '样本护照（测试数据），仅作拍摄参考，非真实证件',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 拍摄要点
                    _card(
                      title: '拍摄要点',
                      children: [
                        _point(
                          index: 1,
                          title: '整页拍全',
                          desc: '护照四个角都要在画面里，别拍一半、别被手指或证件套挡住。',
                        ),
                        _point(
                          index: 2,
                          title: '拍清楚不反光',
                          desc:
                              '光线均匀，避开灯光白斑，关闪光灯；姓名、护照号、生日等文字清晰不模糊。',
                        ),
                        _point(
                          index: 3,
                          title: '底部两行机读码必须拍全',
                          desc: '就是最下面那两行「<<<」字符，缺一个字符都会识别失败。',
                          highlight: true,
                          isLast: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 正确 / 错误对照
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _tipBlock(
                            good: true,
                            title: '请传',
                            items: const ['相机原图'],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _tipBlock(
                            good: false,
                            title: '误传',
                            items: const [
                              '截图 / 微信压缩图',
                              '缩略图 / 小图',
                              '封面页 / 签证页',
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '我知道了',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 样本护照示例图 + 1/2/3 拍摄要点标记（位置对齐原型：①左上角/②右侧中部/③底部机读码）。
  Widget _sampleFigure() {
    return AspectRatio(
      aspectRatio: 924 / 640,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/passport_sample.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // ① 整页拍全 —— 左上角
          const Align(
            alignment: Alignment(-1, -1),
            child: _MarkerDot(index: 1),
          ),
          // ② 拍清楚不反光 —— 右侧约 38% 高度
          const Align(
            alignment: Alignment(1, -0.24),
            child: _MarkerDot(index: 2),
          ),
          // ③ 底部机读码 —— 底部居中（最关键，红色）
          const Align(
            alignment: Alignment(0, 1),
            child: _MarkerDot(index: 3, crit: true),
          ),
        ],
      ),
    );
  }

  /// 带标题的浅灰卡片容器。
  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _point({
    required int index,
    required String title,
    required String desc,
    bool highlight = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _kPrimary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E1E1E),
                        ),
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '最关键',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFF5222D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 正确 / 错误对照块。[good] 决定配色与图标。
  Widget _tipBlock({
    required bool good,
    required String title,
    required List<String> items,
  }) {
    final Color accent =
        good ? const Color(0xFF34A853) : const Color(0xFFF5222D);
    final Color bg = good ? const Color(0xFFEAF7EE) : const Color(0xFFFDECEC);
    final IconData icon = good ? Icons.check_circle : Icons.cancel;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(
                  bottom: item == items.last ? 0 : 6),
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Color(0xFF555555),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 叠加在示例图上的编号标记（白边圆点），对齐要点列表的编号。
class _MarkerDot extends StatelessWidget {
  final int index;
  final bool crit;

  const _MarkerDot({required this.index, this.crit = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: crit ? const Color(0xFFF5222D) : _kPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
