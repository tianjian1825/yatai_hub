import 'package:flutter/material.dart';
import 'package:yatai_hub/services/cache_service.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/pages/login_page.dart';
import 'package:yatai_hub/pages/user_center/about_page.dart';
import 'package:yatai_hub/pages/user_center/account_management_page.dart';

/// 应用设置页面
class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final CacheService _cacheService = CacheService();
  final AuthService _authService = AuthService();
  final GuestModeService _guestModeService = GuestModeService();

  String _cacheSize = '计算中...';
  bool _isClearing = false;
  bool _isGuestMode = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
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

  /// 加载缓存大小
  Future<void> _loadCacheSize() async {
    final size = await _cacheService.getCacheSize();
    if (mounted) {
      setState(() {
        _cacheSize = CacheService.formatFileSize(size);
      });
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存吗？\n这将清除图片缓存、临时文件等，不会影响您的账号信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定', style: TextStyle(color: Color(0xFF366CDF))),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    final success = await _cacheService.clearAllCache();

    if (mounted) {
      setState(() {
        _isClearing = false;
      });

      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
        // 重新计算缓存大小
        _loadCacheSize();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清除缓存失败，请重试')));
      }
    }
  }

  /// 退出登录
  Future<void> _handleLogout() async {
    // 显示确认对话框（统一显示为"退出登录"）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // 执行退出：游客模式也调用 logout
      if (_isGuestMode) {
        await _guestModeService.exitGuestMode();
      }
      await _authService.logout();

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
          '应用设置',
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
          // 设置项列表
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // 清除缓存
                _buildSettingItem(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: const Color(0xFF366CDF),
                  title: '清除缓存',
                  trailing: _isClearing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _cacheSize,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575),
                          ),
                        ),
                  onTap: _isClearing ? null : _clearCache,
                ),
                _buildDivider(),

                // 账号管理
                _buildSettingItem(
                  icon: Icons.manage_accounts_outlined,
                  iconColor: const Color(0xFF366CDF),
                  title: '账号管理',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCCCCCC),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AccountManagementPage(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                // 关于
                _buildSettingItem(
                  icon: Icons.info_outline,
                  iconColor: const Color(0xFF366CDF),
                  title: '关于',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCCCCCC),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AboutPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Spacer(),
          // 退出登录按钮
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleLogout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '退出登录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
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
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: Color(0xFFEEEEEE),
    );
  }
}
