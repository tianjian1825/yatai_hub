import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// 全局配色常量。
///
/// 历史代码里色值散落在各页面的本地 const（如商务模块每个文件各自的 `_pink`），
/// 新代码统一从这里取。
class AppColors {
  AppColors._();

  /// 主题蓝 —— 日期选择器、加载指示器等 Material 自带控件的强调色
  static const primary = Color(0xFF709BF7);

  /// 深蓝 —— AppBar 背景 / 品牌主色
  static const primaryDark = Color(0xFF366CDF);

  /// 商务（BD）/ 会议纪要模块强调色
  static const pink = Color(0xFFF594BC);
  static const pinkLight = Color(0xFFFEE6F2);
}

class AppTheme {
  AppTheme._();

  /// 全局蓝色主题（AppBar 仍用深蓝，与历史观感一致）
  static ThemeData get light =>
      _build(AppColors.primary, appBarColor: AppColors.primaryDark);

  /// 商务（BD）/ 会议纪要模块：白底 + 粉色强调
  static ThemeData get pink =>
      _build(AppColors.pink, appBarColor: AppColors.pink);

  /// `showDatePicker` / `showDateRangePicker` / `showTimePicker` 的 builder。
  ///
  /// 这些弹层的 context 来自 Navigator，**不会**继承调用点所在页面的 Theme，
  /// 所以粉色模块必须显式传 `pink: true`。
  static Widget pickerBuilder(
    BuildContext context,
    Widget? child, {
    bool pink = false,
  }) {
    return Theme(
      data: pink ? AppTheme.pink : AppTheme.light,
      child: child ?? const SizedBox.shrink(),
    );
  }

  static ThemeData _build(Color seed, {required Color appBarColor}) {
    // ColorScheme.fromSeed 的 M3 tonalSpot 算法会把种子色的色度压到 chroma 36
    // 并取 tone 40（#366CDF 会被算成发灰的 #495D92），所以必须 copyWith 把
    // primary 拉回指定色，否则所有自带控件都是灰蓝的。
    final scheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: seed,
      onPrimary: Colors.white,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // 全局主题这里仍是深蓝 #366CDF，与历史一致（AppBar 同色）
      primaryColor: appBarColor,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // M3 日期选择器默认底色是 surfaceContainerHigh（灰白），显式压成纯白
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: seed,
        headerForegroundColor: Colors.white,
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: Colors.white,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: seed),
      // 页面转场动画配置
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
