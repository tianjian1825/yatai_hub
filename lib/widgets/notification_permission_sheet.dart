import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/services/jpush_service.dart';

/// 通知权限关闭提示（底部弹窗）
///
/// 已登录用户启动进入 MainPage 后检测系统通知权限，若被关闭则从底部弹出提示：
/// - 「去开启」→ 打开系统的本 App 通知设置页（iOS 拒绝过授权后无法二次拉起
///   系统授权弹窗，只能引导到设置页手动打开；Android 8+ 直达本 App 通知设置）
/// - 「我知道了」→ 关闭弹窗；勾选「不再提示」则持久化，后续启动不再检测提示
class NotificationPermissionSheet extends StatefulWidget {
  const NotificationPermissionSheet({super.key});

  /// 持久化的「不再提示」标记
  static const String _keyPromptDisabled =
      'notification_permission_prompt_disabled';

  /// 检测并按需弹出提示。在 MainPage 挂载后调用（此时必然已登录）。
  static Future<void> maybeShow(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyPromptDisabled) == true) return;
      // 游客模式不接收推送，无需提示
      if (await GuestModeService().isGuestMode()) return;
      // null = SDK 未初始化 / 查询失败，不打扰；
      // iOS 未授权过(notDetermined)也返回 false，此时提示同样成立
      final enabled = await JPushService().isNotificationEnabled();
      if (enabled != false) return;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (_) => const NotificationPermissionSheet(),
      );
    } catch (e) {
      if (kDebugMode) print('[NotificationPermission] 检测提示失败: $e');
    }
  }

  @override
  State<NotificationPermissionSheet> createState() =>
      _NotificationPermissionSheetState();
}

class _NotificationPermissionSheetState
    extends State<NotificationPermissionSheet> {
  bool _dontRemind = false;

  Future<void> _persistDontRemindIfChecked() async {
    if (!_dontRemind) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      NotificationPermissionSheet._keyPromptDisabled,
      true,
    );
  }

  void _onDismiss() {
    // ignore: discarded_futures
    _persistDontRemindIfChecked();
    Navigator.of(context).pop();
  }

  void _onOpenSettings() {
    // ignore: discarded_futures
    _persistDontRemindIfChecked();
    JPushService().openNotificationSettings();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              size: 44,
              color: Color(0xFF366CDF),
            ),
            const SizedBox(height: 12),
            const Text(
              '通知权限未开启',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '当前无法收到群聊消息、任务派单等重要提醒，建议在系统设置中开启本应用的通知权限。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _dontRemind = !_dontRemind),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _dontRemind,
                      activeColor: const Color(0xFF366CDF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (v) =>
                          setState(() => _dontRemind = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '不再提示',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _onDismiss,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF666666),
                      side: const BorderSide(color: Color(0xFFDDDDDD)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('我知道了'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onOpenSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF366CDF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('去开启'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
