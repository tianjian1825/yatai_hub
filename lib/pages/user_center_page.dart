import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/pages/user_center/my_works_tab.dart';
import 'package:yatai_hub/pages/part_time/my_parttime_tab.dart';
import 'package:yatai_hub/pages/user_center/app_settings_page.dart';
import 'package:yatai_hub/pages/user_center/user_profile_page.dart';
import 'package:yatai_hub/pages/part_time/wallet_page.dart';

/// 个人中心页面
class UserCenterPage extends StatefulWidget {
  const UserCenterPage({super.key});

  @override
  State<UserCenterPage> createState() => _UserCenterPageState();
}

class _UserCenterPageState extends State<UserCenterPage>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String _username = '';
  String _userAvatar = '';
  String _userDepartment = '';

  // 游客模式
  final GuestModeService _guestModeService = GuestModeService();
  bool _isGuestMode = false;
  // 兼职用户（roleid==275）
  bool _isPartTime = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _initPage();
  }

  // 初始化页面：先检查游客模式与角色，再加载用户信息
  Future<void> _initPage() async {
    final isGuest = await _guestModeService.isGuestMode();
    final isPartTime = !isGuest && await _userService.isPartTimeUser();
    if (mounted) {
      setState(() {
        _isGuestMode = isGuest;
        _isPartTime = isPartTime;
      });
    }
    // 无论游客模式还是正常模式，都加载用户信息
    _loadUserInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载用户信息
  Future<void> _loadUserInfo() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });
    }

    try {
      bool hasCachedData = false;

      // 先从缓存加载基本信息并立即显示
      final username = await _userService.getUsername();
      final avatar = await _userService.getUserAvatar();
      final department = await _userService.getUserDepartment();

      if (mounted) {
        setState(() {
          if (username != null) {
            _username = username;
            hasCachedData = true;
          }
          if (avatar != null) {
            _userAvatar = avatar;
            hasCachedData = true;
          }
          if (department != null) {
            _userDepartment = department;
            hasCachedData = true;
          }
          if (hasCachedData) _isLoading = false;
        });
      }

      // 从服务器同步最新用户信息
      final initSuccess = await _userService.initUserInfo();
      if (initSuccess && mounted) {
        final newUsername = await _userService.getUsername();
        final newAvatar = await _userService.getUserAvatar();
        final newDepartment = await _userService.getUserDepartment();
        setState(() {
          if (newUsername != null && newUsername.isNotEmpty) {
            _username = newUsername;
          }
          if (newAvatar != null && newAvatar.isNotEmpty) {
            _userAvatar = newAvatar;
          }
          if (newDepartment != null && newDepartment.isNotEmpty) {
            _userDepartment = newDepartment;
          }
          _isLoading = false;
          _hasError = false;
        });
      } else if (mounted && !hasCachedData) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = '初始化用户信息失败，请检查网络连接或登录状态';
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载用户信息失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // 判断是否有基本用户信息，如果有则不显示错误页面
          final hasBasicInfo = _username.isNotEmpty || _userAvatar.isNotEmpty;
          _hasError = !hasBasicInfo;
          _errorMessage = hasBasicInfo ? null : e.toString();
        });
      }
    }
  }

  /// 刷新用户信息（供外部调用）
  void refresh() {
    _loadUserInfo();
  }

  /// 打开个人资料页面（兼职用户），返回后刷新头像/昵称
  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserProfilePage()),
    );
    if (mounted) _loadUserInfo();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 显示错误状态和重试按钮
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '加载失败',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadUserInfo,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF366CDF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // 固定的头部区域
          _buildHeader(),
          // 固定的 TabBar
          Container(
            color: const Color(0xFFF4F7FF),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF709BF7),
              unselectedLabelColor: const Color(0xFF3D3D3D),
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
              ),
              indicatorColor: const Color(0xFF709BF7),
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: '我的作品'),
                Tab(text: '我的兼职'),
              ],
            ),
          ),
          // 可滚动的 TabBarView
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [MyWorksTab(hideCollect: true), MyParttimeTab()],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建头部区域
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/center-bg.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        children: [
          _buildUserCard(),
          // 兼职用户展示「我的钱包」入口
          if (_isPartTime && !_isGuestMode) _buildWalletEntry(),
        ],
      ),
    );
  }

  /// 构建兼职「我的钱包」入口（复用考勤入口的白卡样式）
  Widget _buildWalletEntry() {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(
              Icons.account_balance_wallet,
              color: Color(0xFF366CDF),
            ),
            title: const Text(
              '我的钱包',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WalletPage()),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建用户信息卡片
  Widget _buildUserCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 60, 24, 21),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：头像和用户信息（兼职用户可点击进入个人资料）
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (_isPartTime && !_isGuestMode) ? _openProfile : null,
              child: Row(
                children: [
                  // 头像
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 游客模式显示默认头像
                      _isGuestMode || _userAvatar.isEmpty
                          ? Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[300],
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                            )
                          : ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: _userAvatar,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey[300],
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey[300],
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                memCacheWidth: 100,
                                maxWidthDiskCache: 100,
                                fadeInDuration: const Duration(
                                  milliseconds: 150,
                                ),
                              ),
                            ),
                      // 部门标签 - 游客模式不显示
                      if (!_isGuestMode && _userDepartment.isNotEmpty)
                        Positioned(
                          bottom: -8,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 16,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/images/group-bg.png'),
                                fit: BoxFit.fill,
                              ),
                            ),
                            child: Text(
                              _getDepartmentShort(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // 用户名和部门
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _isGuestMode
                                  ? '测试账号'
                                  : (_username.isNotEmpty ? _username : '用户'),
                              style: const TextStyle(
                                color: Color(0xFF1E1E1E),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Image.asset(
                              'assets/images/hello-icon.png',
                              width: 16,
                              height: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 游客模式不显示部门信息
                        if (!_isGuestMode && _userDepartment.isNotEmpty)
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/group1-icon.png',
                                width: 16,
                                height: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _userDepartment,
                                  style: const TextStyle(
                                    color: Color(0xFF707070),
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧：应用设置入口
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppSettingsPage(),
                ),
              );
            },
            child: const SizedBox(
              width: 52,
              height: 44,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.settings_outlined,
                  size: 26,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取部门简称
  String _getDepartmentShort() {
    if (_userDepartment.isEmpty) return '';
    // 兼容使用 "-" 或 "·" 作为分隔符的部门名称，优先取第一个片段作为简称
    final parts = _userDepartment.split(RegExp(r'[-·]'));
    return parts.isNotEmpty ? parts[0] : _userDepartment;
  }
}
