import 'package:flutter/material.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/models/settlement.dart';
import 'package:yatai_hub/pages/part_time/parttime_record_detail_page.dart';
import 'package:yatai_hub/pages/part_time/settlement_history_page.dart';
import 'package:yatai_hub/services/settlement_service.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';

/// 兼职「我的钱包」页
///
/// 顶部钱包总览卡（可提现 / 结算中 / 累计到账 / 本月收入），下方收入流水分页
/// 列表，底部按是否持打工证展示「发起提现」按钮或月结提示文案。
/// - 无打工证（can_withdraw=1）：可在 App 手动提现（即时提现）。
/// - 有打工证（can_withdraw=0）：仅展示 withdraw_tip，工资走后台月结。
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const Color _primary = Color(0xFF366CDF);
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();

  WalletSummary? _summary;
  bool _summaryLoading = true;
  String? _summaryError;

  /// 收款账号信息（null=尚未取到 / 取失败）
  PaymentInfo? _paymentInfo;

  /// 本次进入是否已就「未设置收款账号」自动弹窗，避免下拉刷新重复弹
  bool _paymentPrompted = false;

  final List<IncomeFlowItem> _flow = [];
  int _page = 1;
  bool _flowLoading = false;
  bool _flowFirstLoad = true;
  bool _hasMore = true;

  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restoreCache();
    _loadAll();
  }

  /// 冷启动先用本地缓存秒显钱包首页内容（总览卡 + 收款账号），再走网络对齐。
  /// 仅在网络数据尚未到达（字段为 null）时填充，避免覆盖更新鲜的数据。
  Future<void> _restoreCache() async {
    final cachedSummary = await SettlementService().cachedWalletSummary();
    final cachedPayment = await SettlementService().cachedPaymentInfo();
    if (!mounted) return;
    setState(() {
      if (cachedSummary != null && _summary == null) {
        _summary = cachedSummary;
        _summaryLoading = false;
      }
      if (cachedPayment != null && _paymentInfo == null) {
        _paymentInfo = cachedPayment;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_flowLoading && _hasMore) _loadFlow();
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSummary(), _loadPaymentInfo()]);
    await _loadFlow(refresh: true);
    _maybePromptPayment();
  }

  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    final r = await SettlementService().fetchWalletSummary();
    if (!mounted) return;
    setState(() {
      // 网络失败时保留缓存中的总览，避免已显示内容被清空
      if (r.data != null) _summary = r.data;
      _summaryError = r.error;
      _summaryLoading = false;
    });
  }

  Future<void> _loadPaymentInfo() async {
    final r = await SettlementService().fetchPaymentInfo();
    if (!mounted) return;
    // 网络失败时保留缓存中的收款账号
    if (r.data != null) setState(() => _paymentInfo = r.data);
  }

  /// 首次取到「未设置收款账号」时自动弹出填写（每次进入仅弹一次）
  void _maybePromptPayment() {
    if (!mounted || _paymentPrompted) return;
    final p = _paymentInfo;
    if (p != null && !p.isSet) {
      _paymentPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPaymentSheet(notice: true);
      });
    }
  }

  /// 打开收款账号填写/修改 Sheet。返回 true 表示本次成功保存。
  Future<bool> _openPaymentSheet({bool notice = false}) async {
    final saved = await showModalBottomSheet<PaymentInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) =>
          _PaymentAccountSheet(initial: _paymentInfo, notice: notice),
    );
    if (saved != null && mounted) {
      setState(() => _paymentInfo = saved);
      return true;
    }
    return false;
  }

  Future<void> _loadFlow({bool refresh = false}) async {
    if (_flowLoading) return;
    final loadPage = refresh ? 1 : _page;
    setState(() {
      _flowLoading = true;
      if (refresh) _hasMore = true;
    });
    final result = await SettlementService().fetchIncomeFlow(
      page: loadPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _flow
          ..clear()
          ..addAll(result.list);
      } else {
        _flow.addAll(result.list);
      }
      _page = loadPage + 1;
      _hasMore = _flow.length < result.total;
      _flowLoading = false;
      _flowFirstLoad = false;
    });
    if (result.errorMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    }
  }

  Future<void> _refresh() => _loadAll();

  // ───────────────────── 发起提现 ─────────────────────

  Future<void> _onWithdraw() async {
    final summary = _summary;
    if (summary == null || _withdrawing) return;

    // 提现前确保已设置收款账号；未设置则引导填写后再继续
    var payment = _paymentInfo;
    if (payment == null || !payment.isSet) {
      final ok = await _openPaymentSheet(notice: true);
      if (!ok || !mounted) return;
      payment = _paymentInfo;
      if (payment == null || !payment.isSet) return;
    }

    final confirmed = await _showWithdrawSheet(summary, payment);
    if (confirmed != true || !mounted) return;

    setState(() => _withdrawing = true);
    final r = await SettlementService().applyWithdrawal();
    if (!mounted) return;
    setState(() => _withdrawing = false);

    // 4005 未设置收款账号：引导去设置，不弹默认错误
    if (!r.success && r.code == 4005) {
      await _openPaymentSheet(notice: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.success ? '提现申请已提交' : (r.message ?? '提现申请失败'))),
    );
    // 成功 / 金额已变动（2002）都刷新总览与流水，让用户看到最新状态
    if (r.success || (r.message?.contains('变动') ?? false)) {
      _loadAll();
    }
  }

  /// 提现确认 Sheet：汇总金额 + 天数 + 收款账号，提供「查看可结算明细」按需展开。
  /// 返回 true 表示用户确认提现。
  Future<bool?> _showWithdrawSheet(WalletSummary summary, PaymentInfo payment) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _WithdrawSheet(summary: summary, payment: payment),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '我的钱包',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    // 首屏总览加载失败且无任何数据时，整页错误重试
    if (_summaryError != null && _summary == null && _flow.isEmpty) {
      return _buildErrorRetry(_summaryError!);
    }

    final emptyFlow = !_flowFirstLoad && _flow.isEmpty;
    // 头部（总览卡 + 结算记录入口 + 流水标题）固定为第 0 项
    final itemCount = 1 + (emptyFlow ? 1 : _flow.length + 1);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: itemCount,
        itemBuilder: (_, idx) {
          if (idx == 0) return _buildHeader();

          if (emptyFlow) {
            return const Padding(
              padding: EdgeInsets.only(top: 60),
              child: EmptyStateWidget(
                icon: Icons.account_balance_wallet_outlined,
                message: '暂无收入流水',
              ),
            );
          }

          final flowIdx = idx - 1;
          if (flowIdx < _flow.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildFlowCard(_flow[flowIdx]),
            );
          }
          // 底部指示器
          return _buildFooter();
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 12),
        _buildPaymentEntry(),
        const SizedBox(height: 12),
        _buildHistoryEntry(),
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 2, left: 2),
          child: Text(
            '收入流水',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final s = _summary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A86F7), Color(0xFF366CDF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _summaryLoading && s == null
          ? const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '可提现金额（₩）',
                  style: TextStyle(fontSize: 13, color: Color(0xCCFFFFFF)),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      '₩',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _money(s?.withdrawableAmount ?? 0),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _summaryStat('结算中', s?.settlingAmount ?? 0),
                    _summaryStat('累计到账', s?.paidTotal ?? 0),
                    _summaryStat(
                      '本月收入${s?.month.isNotEmpty == true ? '·${s!.month}' : ''}',
                      s?.monthIncome ?? 0,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _summaryStat(String label, double amount) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₩${_money(amount)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentEntry() {
    final p = _paymentInfo;
    final isSet = p?.isSet ?? false;
    final subtitle = isSet
        ? '${_maskAccount(p!.alipayAccount)}  ·  ${p.alipayName}'
        : '未设置，点击填写收款支付宝账号';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(
          Icons.account_balance_wallet_outlined,
          color: _primary,
        ),
        title: const Text(
          '收款账号',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isSet ? const Color(0xFF666666) : const Color(0xFFFA8C16),
            ),
          ),
        ),
        trailing: Text(
          isSet ? '修改' : '去设置',
          style: const TextStyle(fontSize: 13, color: _primary),
        ),
        onTap: () => _openPaymentSheet(notice: !isSet),
      ),
    );
  }

  /// 账号脱敏：手机号保留前 3 后 4，邮箱保留首字符与域名，其余以 *** 代替
  static String _maskAccount(String account) {
    if (account.isEmpty) return '';
    if (account.contains('@')) {
      final parts = account.split('@');
      final name = parts.first;
      final domain = parts.length > 1 ? parts[1] : '';
      final head = name.isNotEmpty ? name[0] : '';
      return '$head***@$domain';
    }
    if (account.length >= 7) {
      return '${account.substring(0, 3)}****${account.substring(account.length - 4)}';
    }
    return account;
  }

  Widget _buildHistoryEntry() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.receipt_long, color: _primary),
        title: const Text(
          '结算记录',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettlementHistoryPage()),
          );
        },
      ),
    );
  }

  Widget _buildFlowCard(IncomeFlowItem item) {
    final (fg, bg) = IncomeFlowStatus.color(item.flowStatus);
    final expense = item.expense;
    final hasReimburse = expense != null && expense.isValid;
    // 已通过的报销并入结算明细行；待审核/已驳回仍单独一行按审核态着色提示
    final reimburseApproved =
        hasReimburse && expense.auditStatus == ParttimeAuditStatus.approved;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.clockId > 0 ? () => _openRecordDetail(item.clockId) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.workDate.isEmpty ? '—' : item.workDate,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.flowStatusLabel,
                    style: TextStyle(fontSize: 12, color: fg),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFFB0B0B0),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 结算明细独占整行，避免韩币长金额挤一行溢出
            Text(
              '${_trim(item.workHours)} 小时 × ₩${_trim(item.hourlyRate)}'
              '${item.bonusTotal > 0 ? ' + 奖金 ₩${_trim(item.bonusTotal)}' : ''}'
              '${item.expenseAmount > 0 ? ' + 交通费 ₩${_money(item.expenseAmount.toDouble())}' : ''}'
              '${reimburseApproved ? ' + 报销 ₩${_money(expense.amount.toDouble())}' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
              ),
            ),
            // 未通过审核（待审核/已驳回）的报销单独展示，按审核态着色
            if (hasReimburse && !reimburseApproved) ...[
              const SizedBox(height: 2),
              Text(
                '报销 ₩${_money(expense.amount.toDouble())}'
                ' · ${expense.displayAuditLabel}',
                style: TextStyle(
                  fontSize: 12,
                  color: _expenseAuditColor(expense.auditStatus),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '₩${_money(item.settlementAmount)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点流水卡进打卡记录详情；详情页内可能编辑/取消报销单，返回后静默重拉对齐
  Future<void> _openRecordDetail(int clockId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ParttimeRecordDetailPage.fromClockId(clockId: clockId),
      ),
    );
    if (mounted) _loadAll();
  }

  /// 报销单审核状态着色：通过绿 / 驳回红 / 待审核橙
  Color _expenseAuditColor(int auditStatus) {
    switch (auditStatus) {
      case ParttimeAuditStatus.approved:
        return const Color(0xFF52C41A);
      case ParttimeAuditStatus.rejected:
        return const Color(0xFFFF4D4F);
      default:
        return const Color(0xFFFA8C16);
    }
  }

  Widget _buildFooter() {
    if (_flowLoading && _flow.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore && _flow.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('到底了~', style: TextStyle(color: Color(0xFF999999))),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildErrorRetry(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            '加载失败',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar() {
    final s = _summary;
    if (s == null) return null;

    // 有打工证：不可在 App 提现，仅展示提示文案
    if (!s.canWithdraw) {
      final tip = s.withdrawTip.isNotEmpty
          ? s.withdrawTip
          : '您持有打工证，工资将按月由后台统一结算';
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEDEFF2))),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: Color(0xFF999999),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tip,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF999999),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 无打工证：可发起提现，金额为 0 时置灰
    final canTap = s.withdrawableAmount > 0 && !_withdrawing;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEDEFF2))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: canTap ? _onWithdraw : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB0B0B0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _withdrawing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    s.withdrawableAmount > 0
                        ? '发起提现（₩${_money(s.withdrawableAmount)}）'
                        : '暂无可提现金额',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 金额展示：整数去掉小数尾巴，否则保留 2 位
  static String _money(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  /// 工时/时薪去尾：整数不显示小数
  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// 提现确认底部 Sheet：汇总金额 + 天数 + 收款账号，可点击展开可结算逐日明细。
class _WithdrawSheet extends StatefulWidget {
  final WalletSummary summary;
  final PaymentInfo payment;

  const _WithdrawSheet({required this.summary, required this.payment});

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  static const Color _primary = Color(0xFF366CDF);

  bool _detailExpanded = false;
  bool _detailLoading = false;
  bool _detailLoaded = false;
  List<IncomeSummaryDay> _days = const [];
  String? _detailError;

  Future<void> _toggleDetail() async {
    if (_detailExpanded) {
      setState(() => _detailExpanded = false);
      return;
    }
    setState(() => _detailExpanded = true);
    if (_detailLoaded || _detailLoading) return;
    setState(() => _detailLoading = true);
    final r = await SettlementService().fetchIncomeSummary();
    if (!mounted) return;
    setState(() {
      _days = r.list;
      _detailError = r.error;
      _detailLoading = false;
      _detailLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                '确认提现',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '₩${_WalletPageState._money(s.withdrawableAmount)}',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '共 ${s.withdrawableDays} 天可结算',
                style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                    color: _primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '提现至',
                    style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.payment.alipayName}  ${widget.payment.alipayAccount}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _toggleDetail,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      '查看可结算明细',
                      style: TextStyle(fontSize: 14, color: _primary),
                    ),
                    Icon(
                      _detailExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.chevron_right,
                      size: 18,
                      color: _primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_detailExpanded) _buildDetail(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '确认提现',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail() {
    if (_detailLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_detailError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _detailError!,
          style: const TextStyle(fontSize: 13, color: Color(0xFFFF4D4F)),
        ),
      );
    }
    if (_days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '暂无可结算明细',
          style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: SingleChildScrollView(
        child: Column(
          children: _days
              .map(
                (d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.workDate,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      Text(
                        '₩${_WalletPageState._money(d.settlementAmount)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// 收款账号填写 / 修改底部 Sheet
///
/// [initial] 为当前已设置的账号（可空），[notice] 为 true 时顶部展示
/// 「请先设置收款账号」引导文案（未绑定自动弹出或提现拦截时）。保存成功后
/// pop 返回最新 [PaymentInfo]。
class _PaymentAccountSheet extends StatefulWidget {
  final PaymentInfo? initial;
  final bool notice;

  const _PaymentAccountSheet({this.initial, this.notice = false});

  @override
  State<_PaymentAccountSheet> createState() => _PaymentAccountSheetState();
}

class _PaymentAccountSheetState extends State<_PaymentAccountSheet> {
  static const Color _primary = Color(0xFF366CDF);

  late final TextEditingController _accountCtrl;
  late final TextEditingController _nameCtrl;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountCtrl = TextEditingController(
      text: widget.initial?.alipayAccount ?? '',
    );
    _nameCtrl = TextEditingController(text: widget.initial?.alipayName ?? '');
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final account = _accountCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (account.isEmpty) {
      setState(() => _error = '请填写收款支付宝账号');
      return;
    }
    if (account.length > 100) {
      setState(() => _error = '支付宝账号过长（≤100 字）');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = '请填写收款人真实姓名');
      return;
    }
    if (name.length > 50) {
      setState(() => _error = '收款人姓名过长（≤50 字）');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await SettlementService().savePaymentInfo(
      alipayAccount: account,
      alipayName: name,
    );
    if (!mounted) return;
    if (r.data != null) {
      Navigator.of(context).pop(r.data);
    } else {
      setState(() {
        _saving = false;
        _error = r.error ?? '保存失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial?.isSet ?? false;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                isEdit ? '修改收款账号' : '设置收款账号',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.notice)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '请先设置收款支付宝账号，用于接收提现打款。请确保账号与实名姓名一致，否则可能打款失败。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB7791F),
                    height: 1.5,
                  ),
                ),
              ),
            _buildField(
              label: '支付宝账号',
              controller: _accountCtrl,
              hint: '手机号或邮箱',
              keyboardType: TextInputType.emailAddress,
              maxLength: 100,
            ),
            const SizedBox(height: 14),
            _buildField(
              label: '收款人姓名',
              controller: _nameCtrl,
              hint: '支付宝实名认证姓名',
              keyboardType: TextInputType.text,
              maxLength: 50,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB0B0B0),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        '保存',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    required int maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFBBBBBB)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            filled: true,
            fillColor: const Color(0xFFF7F8FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
          ),
        ),
      ],
    );
  }
}
