import 'package:flutter/rendering.dart';

/// 响应式素材网格代理。
///
/// 用 [SliverGridDelegateWithMaxCrossAxisExtent] 按可用宽度自适应列数：
/// 手机上保持约 3 列，平板/折叠屏等宽屏自动增加列数，图块尺寸维持与手机
/// 接近，避免宽屏上 3 列把单张图片拉得过大。
///
/// [maxCrossAxisExtent] 控制单个图块的最大宽度（默认 140）：
/// 常见手机宽度（约 320~430）下换算仍为 3 列，宽屏则按比例增加列数。
SliverGridDelegate responsiveMaterialGridDelegate({
  double maxCrossAxisExtent = 140,
  double crossAxisSpacing = 6,
  double mainAxisSpacing = 6,
  double childAspectRatio = 1,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCrossAxisExtent,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    childAspectRatio: childAspectRatio,
  );
}
