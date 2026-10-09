import 'package:flutter/material.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/models/settlement.dart';
import 'package:yatai_hub/pages/part_time/parttime_record_detail_page.dart';
import 'package:yatai_hub/services/settlement_service.dart';

/// 兼职结算单明细页
///
/// 顶部展示结算单信息（类型 / 状态 / 金额 / 天数 / 期间 / 申请·处理时间 /
/// 驳回原因），下方为纳入的逐日打卡明细。结算单不存在（4004）显示错误重试。
class SettlementDetailPage extends StatefulWidget {
  final int id;

  const SettlementDetailPage({super.key, required this.id});

  @override
  State<SettlementDetailPage> createState() => _SettlementDetailPageState();
}

class _SettlementDetailPageState extends State<SettlementDetailPage> {
  static const Color _primary = Color(0xFF366CDF);

  bool _loading = true;
  String? _error;
  SettlementDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await SettlementService().fetchDetail(id: widget.id);
    if (!mounted) return;
    setState(() {
      _detail = r.data;
      _error = r.error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '结算单详情',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_detail == null) {
      return _buildErrorRetry(_error ?? '结算单不存在');
    }
    final detail = _detail!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSettleCard(detail.settle),
        const SizedBox(height: 12),
        _buildItemsCard(detail.items),
      ],
    );
  }

  Widget _buildSettleCard(SettlementRecord s) {
    final (fg, bg) = SettlementStatus.color(s.status);
    final rows = <_Row>[
      _Row(
        '结算类型',
        s.settleTypeLabel.isEmpty
            ? (s.settleType == 2 ? '月结' : '即时提现')
            : s.settleTypeLabel,
      ),
      _Row('结算金额', '₩ ${_money(s.amount)}'),
      if (s.allowance > 0) _Row('其中津贴', '₩ ${_money(s.allowance)}'),
      if (s.rmbAmount > 0) _Row('折合人民币', '¥ ${_money(s.rmbAmount)}'),
      if (s.exchangeRate > 0) _Row('结算汇率', '¥1 = ₩${_trim(s.exchangeRate)}'),
      _Row('结算天数', '${s.daysCount} 天'),
      if (s.period.isNotEmpty) _Row('结算期间', s.period),
      if (s.applyTimeStr.isNotEmpty) _Row('申请时间', s.applyTimeStr),
      if (s.handleTimeStr.isNotEmpty) _Row('处理时间', s.handleTimeStr),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '结算单信息',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  s.statusLabel,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map(_buildRow),
          if (s.status == SettlementStatus.rejected &&
              s.rejectReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCCC7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '驳回原因',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCF1322)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.rejectReason,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(List<IncomeSummaryDay> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '纳入打卡明细（${items.length}）',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '无打卡明细',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            )
          else
            ...items.map(_buildDayRow),
        ],
      ),
    );
  }

  Widget _buildDayRow(IncomeSummaryDay d) {
    final expense = d.expense;
    final hasReimburse = expense != null && expense.isValid;
    // 已通过的报销并入结算明细行；待审核/已驳回仍单独一行按审核态着色提示
    final reimburseApproved =
        hasReimburse && expense.auditStatus == ParttimeAuditStatus.approved;
    return InkWell(
      onTap: d.clockId > 0 ? () => _openRecordDetail(d.clockId) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.workDate,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_trim(d.workHours)} 小时 × ₩${_trim(d.hourlyRate)}'
                    '${d.bonusTotal > 0 ? ' + 奖金 ₩${_trim(d.bonusTotal)}' : ''}'
                    '${d.expenseAmount > 0 ? ' + 交通费 ₩${_money(d.expenseAmount.toDouble())}' : ''}'
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₩${_money(d.settlementAmount)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: Color(0xFFB0B0B0),
            ),
          ],
        ),
      ),
    );
  }

  /// 点逐日明细进打卡记录详情；详情页内可能编辑/取消报销单，
  /// 返回后静默重拉结算单明细对齐（不闪整页加载态）
  Future<void> _openRecordDetail(int clockId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ParttimeRecordDetailPage.fromClockId(clockId: clockId),
      ),
    );
    if (!mounted) return;
    final r = await SettlementService().fetchDetail(id: widget.id);
    if (!mounted) return;
    if (r.data != null) setState(() => _detail = r.data);
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

  Widget _buildRow(_Row r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              r.label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
          ),
          Expanded(
            child: Text(
              r.value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
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
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
          ),
        ],
      ),
    );
  }

  static String _money(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

class _Row {
  final String label;
  final String value;

  _Row(this.label, this.value);
}
