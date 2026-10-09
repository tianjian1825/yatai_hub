/// App 版本信息单一出处。
///
/// ⚠️ 与 pubspec.yaml 的 `version: x.y.z+build` 手动保持一致，发版时同步更新。
/// 纯 Dart 无运行时读取 pubspec 版本的 API（需 package_info_plus 等插件），
/// 本项目不引入额外依赖，故以常量维护。
class AppInfo {
  /// 版本名，对应 pubspec `version` 的 x.y.z 部分
  static const String version = '1.0.0';

  /// 构建号，对应 pubspec `version` 的 +N 部分
  static const String buildNumber = '1';

  /// 版本名+构建号，如 1.3.5+35（用于 User-Agent 等）
  static const String fullVersion = '$version+$buildNumber';
}
