import 'package:url_launcher/url_launcher.dart';

/// 调起系统拨号盘并预填号码（通讯录行、群聊用户名片共用）
///
/// 用 `tel:` = ACTION_DIAL：只把号码填进拨号盘，**不直接呼出**，拨不拨由用户按
/// 拨号键决定，因此不需要 CALL_PHONE 权限。平台侧要放行该协议，否则系统直接报
/// 找不到可处理的应用：Android 需在 manifest 的 `<queries>` 里声明 DIAL + tel，
/// iOS 需 `LSApplicationQueriesSchemes` 加 `tel`。
///
/// 返回 null=已调起；非空=可直接展示给用户的失败原因。
Future<String?> dialPhoneNumber(String mobile) async {
  final number = mobile.trim();
  if (number.isEmpty) return '号码为空';
  // 号码里可能带空格 / 连字符 / 括号，tel: 只保留数字与 + 号
  final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return '号码格式不正确：$number';
  try {
    final ok = await launchUrl(
      Uri(scheme: 'tel', path: cleaned),
      mode: LaunchMode.externalApplication,
    );
    return ok ? null : '无法调起拨号盘：$number';
  } catch (_) {
    return '当前设备不支持拨号';
  }
}
