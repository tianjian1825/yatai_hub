import 'package:flutter/material.dart';
import 'package:yatai_hub/services/cache_service.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/pages/login_page.dart';

/// 账号管理页面
class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final CacheService _cacheService = CacheService();
  final AuthService _authService = AuthService();
  final GuestModeService _guestModeService = GuestModeService();

  bool _isGuestMode = false;

  @override
  void initState() {
    super.initState();
    _checkGuestMode();
  }

  // 检查是否游客模式
  Future<void> _checkGuestMode() async {
    final isGuest = await _guestModeService.isGuestMode();
    if (mounted) {
      setState(() {
        _isGuestMode = isGuest;
      });
    }
  }

  /// 注销账号
  Future<void> _handleDeleteAccount() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销账号'),
        content: const Text('注销账号后将清除所有账号数据并自动退出登录，此操作不可恢复。\n\n确定要注销账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定注销', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // 清除缓存
      await _cacheService.clearAllCache();

      // 执行退出：游客模式也调用 logout
      if (_isGuestMode) {
        await _guestModeService.exitGuestMode();
      }
      await _authService.logout();

      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('账号已注销')));
      }

      // 跳转到登录页面并清除所有路由
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '账号管理',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // 账号管理项列表
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // 注销账号
                _buildSettingItem(
                  icon: Icons.person_remove_outlined,
                  iconColor: Colors.red,
                  title: '注销账号',
                  subtitle: '注销后将清除所有账号数据',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCCCCCC),
                  ),
                  onTap: _handleDeleteAccount,
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
