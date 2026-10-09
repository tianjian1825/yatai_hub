import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yatai_hub/models/user_register_info.dart';
import 'package:yatai_hub/pages/login_page.dart';
import 'package:yatai_hub/pages/main_page.dart';
import 'package:yatai_hub/pages/register_page.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/jpush_service.dart';
import 'package:yatai_hub/services/user_register_info_service.dart';
import 'package:yatai_hub/services/user_service.dart';

/// 兼职用户（roleid==275）账号状态拦截页（待审核 / 已驳回 / 已停用共用）
///
/// 门禁（`isPartTimePendingReview()` = roleid==275 && disabled==1）拦截到此页后，
/// 页面调用 `GET /v1/user/register_info` 拉取 `parttime_audit_status` + `disabled`
/// 精确区分状态（disabled==1 不再唯一等于「待审核」）：
/// - audit=0 待审核 → 展示「资料审核中」（刷新 + 退出登录）
/// - audit=2 已驳回 → 展示驳回原因 + 「修改并重新提交」（复用 [RegisterPage] 编辑模式）
/// - audit=1 且 disabled=1（已通过后被停用）→ 展示停用原因（刷新账号状态 + 退出登录）
/// - audit=1 且 disabled=0（正常）→ 自动进入主 App（[MainPage]）
///
/// 仅兼职非正常用户会进入本页，故 register_info 接口只对兼职登录调用。
class PartTimePendingPage extends StatefulWidget {
  const PartTimePendingPage({super.key});

  /// 当前是否有拦截页实例在栈中。main.dart 前台恢复检测据此避免重复 push
  /// （页面自身会在 resume 时刷新状态，由它接管即可）。
  static bool isActive = false;

  @override
  State<PartTimePendingPage> createState() => _PartTimePendingPageState();
}

class _PartTimePendingPageState extends State<PartTimePendingPage>
    with WidgetsBindingObserver {
  static const Color _primary = Color(0xFF1F6FF4);

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final UserRegisterInfoService _registerInfoService =
      UserRegisterInfoService();

  UserRegisterInfo? _info;
  bool _loading = true;
  bool _refreshing = false;
  bool _loggingOut = false;
  // 审核通过后会 pushReplacement 离开本页，置位防止并发刷新重复跳转
  bool _navigating = false;

  // 前台收到注册审核推送（onNotification 通知 / onMessage 透传）时自动刷新
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<Map<String, dynamic>>? _messageSub;

  @override
  void initState() {
    super.initState();
    PartTimePendingPage.isActive = true;
    WidgetsBinding.instance.addObserver(this);
    _init();
    // 停留本页时，后台审核（通过 / 驳回）推送到达 → 自动刷新状态，无需手动点击
    _notificationSub = JPushService().onNotification.listen(_onAuditPush);
    _messageSub = JPushService().onMessage.listen(_onAuditPush);
  }

  @override
  void dispose() {
    PartTimePendingPage.isActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 每次回到前台重新拉取状态：已恢复正常则自动进主 App，仍被拦截则刷新展示
    if (state == AppLifecycleState.resumed && !_navigating && mounted) {
      // ignore: discarded_futures
      _loadStatus(silent: true);
    }
  }

  /// 前台推送回调：是注册审核推送（或无法识别 action 的推送）时刷新审核状态。
  void _onAuditPush(Map<String, dynamic> message) {
    if (_navigating || !mounted) return;
    // 资料修改页等覆盖在本页之上时不抢跳转，等用户回到本页再说
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final action = _extractAction(message);
    if (action == null || action == 'open_part_time_register') {
      if (kDebugMode) print('[审核页] 收到推送，自动刷新审核状态: action=$action');
      // ignore: discarded_futures
      _loadStatus(silent: true);
    }
  }

  /// 从 JPush 前台消息中尽量解析出业务 action（兼容各平台 extras 格式）。
  String? _extractAction(Map<String, dynamic> message) {
    dynamic extras = message['extras'];
    if (extras is Map && extras['cn.jpush.android.EXTRA'] != null) {
      extras = extras['cn.jpush.android.EXTRA'];
    }
    if (extras is String && extras.isNotEmpty) {
      try {
        extras = jsonDecode(extras);
      } catch (_) {}
    }
    if (extras is Map && extras['action'] != null) {
      return extras['action'].toString();
    }
    if (message['action'] != null) return message['action'].toString();
    return null;
  }

  Future<void> _init() async {
    // 先用缓存秒显，再后台拉最新审核状态
    final cached = await _registerInfoService.getCached();
    if (cached != null && mounted) {
      setState(() {
        _info = cached;
        _loading = false;
      });
    }
    await _loadStatus(silent: cached != null);
  }

  /// 拉取最新审核状态：已通过则进入主 App，否则按状态展示。
  Future<void> _loadStatus({bool silent = false}) async {
    if (_navigating) return;
    final info = await _registerInfoService.fetch();
    if (!mounted || _navigating) return;
    if (info != null && info.canEnterMainApp) {
      // 审核通过且未被停用：同步 getUserInfo（刷新 disabled / 角色标志）后进入主 App
      _navigating = true;
      _userService.resetUserInfoInitState();
      await _userService.initUserInfo();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainPage()),
      );
      return;
    }
    setState(() {
      _loading = false;
      if (info != null) _info = info;
    });
  }

  Future<void> _refreshStatus() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _loadStatus(silent: true);
      if (!mounted) return;
      // 仍未恢复正常才会走到这里（正常会 pushReplacement 离开本页）
      if (_info != null && _info!.isDisabledAfterApproval) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('账号仍处于停用状态，请联系管理员')),
        );
      } else if (_info != null && _info!.isPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('资料仍在审核中，请耐心等待')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// 进入资料修改页（复用注册表单编辑模式），提交成功后回到待审核态。
  Future<void> _openResubmit() async {
    final info = _info;
    if (info == null) return;
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => RegisterPage(editInfo: info)),
    );
    if (result == true && mounted) {
      // 重新提交成功，状态回到待审核：刷新展示
      setState(() => _loading = true);
      await _loadStatus(silent: true);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loggingOut = true);
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: _loading && _info == null
              ? const Center(child: CircularProgressIndicator())
              : (_info?.isDisabledAfterApproval ?? false)
                  ? _buildDisabledBody(_info!)
                  : (_info?.isRejected ?? false)
                      ? _buildRejectedBody(_info!)
                      : _buildPendingBody(),
        ),
      ),
    );
  }

  /// 待审核：资料审核中
  Widget _buildPendingBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFE6F0FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: _primary,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '资料审核中',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '您的兼职资料已提交，正在等待管理员审核。\n审核通过后即可正常使用 App。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
              height: 1.6,
            ),
          ),
          const Spacer(flex: 3),
          _primaryButton(
            label: '刷新审核状态',
            loading: _refreshing,
            onPressed: _refreshStatus,
          ),
          const SizedBox(height: 12),
          _logoutButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 已通过后被停用：展示停用原因 + 刷新账号状态 / 退出登录
  Widget _buildDisabledBody(UserRegisterInfo info) {
    final reason = info.parttimeDisableReason.trim();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECEC),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    color: Color(0xFFF5222D),
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '账号已停用',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCCC7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '停用原因',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF5222D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reason.isNotEmpty
                          ? reason
                          : '您的账号已被管理员停用，如有疑问请联系管理员',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Color(0xFF8C1F1A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '账号停用期间无法使用 App，如已恢复请点击下方刷新账号状态。',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              _primaryButton(
                label: '刷新账号状态',
                loading: _refreshing,
                onPressed: _refreshStatus,
              ),
              const SizedBox(height: 12),
              _logoutButton(),
            ],
          ),
        ),
      ],
    );
  }

  /// 已驳回：展示原因 + 修改重新提交
  Widget _buildRejectedBody(UserRegisterInfo info) {
    final reason = info.parttimeRejectReason.trim();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECEC),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_gmailerrorred_rounded,
                    color: Color(0xFFF5222D),
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '审核未通过',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCCC7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '驳回原因',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF5222D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reason.isNotEmpty
                          ? reason
                          : '管理员未填写具体原因，请核对资料后重新提交',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Color(0xFF8C1F1A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '请根据上述原因修改资料后重新提交，提交后将重新进入审核。',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              _primaryButton(
                label: '修改资料',
                loading: false,
                onPressed: _openResubmit,
              ),
              const SizedBox(height: 12),
              _logoutButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB0B0B0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _loggingOut ? null : _logout,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF666666),
          side: const BorderSide(color: Color(0xFFDDDDDD)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('退出登录', style: TextStyle(fontSize: 15)),
      ),
    );
  }
}
