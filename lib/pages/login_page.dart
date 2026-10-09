import 'package:flutter/material.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/services/guest_mode_service.dart';
import 'package:yatai_hub/pages/main_page.dart';
import 'package:yatai_hub/pages/part_time/part_time_pending_page.dart';
import 'package:yatai_hub/pages/register_page.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final GuestModeService _guestModeService = GuestModeService();

  bool _isGuestEntering = false;
  bool _isAccountLoggingIn = false;

  // 账号密码登录相关
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _showAccountLoginForm = false; // 控制是否显示账号密码登录表单

  // 访客模式预留入口（不走真实接口）
  static const String _guestAccount = 'appTest';
  static const String _guestPassword = '123456test';

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 处理账号密码登录
  Future<void> _handleAccountLogin() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text.trim();

    if (account.isEmpty || password.isEmpty) {
      _showErrorDialog('请输入账号和密码');
      return;
    }

    // 访客通道：保留原硬编码账号走 guestMode，不调真实接口
    if (account == _guestAccount && password == _guestPassword) {
      setState(() => _isGuestEntering = true);
      try {
        final success = await _guestModeService.loginAsGuest();
        if (success && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainPage()),
          );
        } else if (mounted) {
          _showErrorDialog('登录失败，请重试');
        }
      } catch (e) {
        debugPrint('访客登录错误: $e');
        if (mounted) _showErrorDialog('登录出错: $e');
      } finally {
        if (mounted) setState(() => _isGuestEntering = false);
      }
      return;
    }

    if (password.length < 6) {
      _showErrorDialog('密码不能少于 6 位');
      return;
    }

    setState(() => _isAccountLoggingIn = true);

    try {
      // 退出可能残留的游客状态
      await _guestModeService.exitGuestMode();

      final result = await _authService.loginWithAccount(
        username: account,
        password: password,
      );

      if (result.success) {
        final userService = UserService();
        await userService.initUserInfo();
        if (mounted) {
          final pending = await userService.isPartTimePendingReview();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  pending ? const PartTimePendingPage() : const MainPage(),
            ),
          );
        }
      } else if (mounted) {
        _showErrorDialog(result.errorMessage ?? '登录失败，请重试');
      }
    } catch (e) {
      debugPrint('账号密码登录错误: $e');
      if (mounted) _showErrorDialog('登录出错: $e');
    } finally {
      if (mounted) setState(() => _isAccountLoggingIn = false);
    }
  }

  /// 跳转到注册页
  Future<void> _goToRegister() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const RegisterPage()),
    );
    // 注册成功返回带回邮箱：自动填入登录名并展开账号登录表单
    if (!mounted) return;
    if (email != null && email.isNotEmpty) {
      setState(() {
        _accountController.text = email;
        _showAccountLoginForm = true;
      });
    }
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 构建账号密码登录表单
  Widget _buildAccountLoginForm() {
    final bool isAnyAuthorizing = _isGuestEntering || _isAccountLoggingIn;

    return Container(
      key: const ValueKey('accountLoginForm'),
      color: Colors.white,
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () {
                      // 先收起键盘，避免回退动画期间 body 高度突变
                      // 导致表单瞬间溢出 flex 区域出现像素溢出提示
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _showAccountLoginForm = false;
                        _accountController.clear();
                        _passwordController.clear();
                      });
                    },
                    color: const Color(0xFF666666),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '账号密码登录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 账号输入框
              TextField(
                controller: _accountController,
                decoration: InputDecoration(
                  hintText: '姓名 / 手机号 / 邮箱',
                  hintStyle: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: Color(0xFF999999),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF1F6FF4),
                      width: 1.5,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 密码输入框
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  hintText: '请输入密码',
                  hintStyle: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: Color(0xFF999999),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: const Color(0xFF999999),
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF1F6FF4),
                      width: 1.5,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 登录按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isAnyAuthorizing ? null : _handleAccountLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FF4),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFB0B0B0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: (_isGuestEntering || _isAccountLoggingIn)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // 注册入口
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '还没有账号？',
                    style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                  ),
                  GestureDetector(
                    onTap: isAnyAuthorizing ? null : _goToRegister,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '立即注册',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1F6FF4),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建登录入口区域（仅账号密码登录）
  Widget _buildLoginButtons() {
    final bool isAnyAuthorizing = _isGuestEntering || _isAccountLoggingIn;

    return Container(
      key: const ValueKey('loginButtons'),
      color: Colors.white,
      child: Column(
        children: [
          // 账号密码登录按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isAnyAuthorizing
                  ? null
                  : () {
                      setState(() {
                        _showAccountLoginForm = true;
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FF4),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB0B0B0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                '账号密码登录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 注册入口
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '还没有账号？',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
              GestureDetector(
                onTap: isAnyAuthorizing ? null : _goToRegister,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '立即注册',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1F6FF4),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      children: [
                        Expanded(
                          // logo 区与登录区按 1:1 分配，避免登录区在加入
                          // 「立即注册」入口后高度逼近边界、过渡动画期间像素溢出
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Logo区域
                              Image.asset(
                                'assets/images/app_logo_mark.png',
                                width: 90,
                                height: 90,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                '亚太HUB',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E1E1E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ClipRect(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 350),
                                  curve: const Cubic(
                                    0.42,
                                    0.0,
                                    0.58,
                                    1.0,
                                  ), // iOS 标准缓动曲线
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 350),
                                    transitionBuilder:
                                        (
                                          Widget child,
                                          Animation<double> animation,
                                        ) {
                                          // 判断当前子组件类型
                                          final isAccountForm =
                                              child.key ==
                                              const ValueKey(
                                                'accountLoginForm',
                                              );

                                          final offsetTween = Tween<Offset>(
                                            begin: isAccountForm
                                                ? const Offset(1.0, 0.0)
                                                : const Offset(-1.0, 0.0),
                                            end: Offset.zero,
                                          );

                                          return SlideTransition(
                                            position: offsetTween.animate(
                                              CurvedAnimation(
                                                parent: animation,
                                                curve: const Cubic(
                                                  0.42,
                                                  0.0,
                                                  0.58,
                                                  1.0,
                                                ), // iOS 标准缓动曲线
                                              ),
                                            ),
                                            child: FadeTransition(
                                              opacity:
                                                  Tween<double>(
                                                    begin: 0.0,
                                                    end: 1.0,
                                                  ).animate(
                                                    CurvedAnimation(
                                                      parent: animation,
                                                      curve: const Cubic(
                                                        0.42,
                                                        0.0,
                                                        0.58,
                                                        1.0,
                                                      ),
                                                    ),
                                                  ),
                                              child: child,
                                            ),
                                          );
                                        },
                                    layoutBuilder:
                                        (
                                          Widget? currentChild,
                                          List<Widget> previousChildren,
                                        ) {
                                          return Stack(
                                            alignment: Alignment.bottomCenter,
                                            children: <Widget>[
                                              ...previousChildren,
                                              ?currentChild,
                                            ],
                                          );
                                        },
                                    child: _showAccountLoginForm
                                        ? _buildAccountLoginForm()
                                        : _buildLoginButtons(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
