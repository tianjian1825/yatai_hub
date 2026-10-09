import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/pages/part_time/part_time_task_detail_page.dart';
import 'package:yatai_hub/pages/part_time/parttime_clock_out_sheet.dart';
import 'package:yatai_hub/pages/part_time/parttime_expense_edit_sheet.dart';
import 'package:yatai_hub/services/parttime_clock_service.dart';
import 'package:yatai_hub/services/parttime_expense_service.dart';
import 'package:yatai_hub/widgets/image_preview_page.dart';

/// 兼职打卡记录详情页
///
/// 两种入口：
/// - 列表入口携带完整 [record]，头部信息可即时渲染；
/// - 推送入口（打卡审核通知）只携带 [clockId]，先用占位记录渲染，
///   待 /v1/parttime_clock/detail 返回后用 data.clock 回填头部。
///
/// 进入后调用 /v1/parttime_clock/detail 拉取该打卡日期当天「已完成任务」
/// 列表，点击任务卡片可跳转到 [PartTimeTaskDetailPage] 查看完整任务详情。
class ParttimeRecordDetailPage extends StatefulWidget {
  /// 列表入口携带的完整记录；推送入口为 null（仅有 [clockId]）
  final ParttimeRecord? record;

  /// 推送入口携带的打卡 id；列表入口为 null
  final int? clockId;

  const ParttimeRecordDetailPage({
    super.key,
    required ParttimeRecord this.record,
  }) : clockId = null;

  /// 推送跳转入口：仅凭打卡 id 进入，详情由接口拉取
  const ParttimeRecordDetailPage.fromClockId({
    super.key,
    required int this.clockId,
  }) : record = null;

  @override
  State<ParttimeRecordDetailPage> createState() =>
      _ParttimeRecordDetailPageState();
}

class _ParttimeRecordDetailPageState extends State<ParttimeRecordDetailPage> {
  static const Color _primary = Color(0xFF709BF7);

  static const Color _danger = Color(0xFFFF4D4F);

  bool _loading = true;
  bool _submitting = false;
  List<ParttimeCompletedTask> _tasks = const [];

  /// 该打卡关联的独立报销单（data.expense），无则 null 不展示卡片
  ParttimeExpense? _expense;

  /// 报销单编辑 / 取消操作进行中（与打卡重交的 [_submitting] 互不干扰）
  bool _expenseBusy = false;

  /// 头部渲染依据：列表入口为已携带记录，推送入口先用占位记录，
  /// 接口返回后统一回填为服务端 data.clock。
  late ParttimeRecord _record =
      widget.record ?? ParttimeRecord.placeholder(widget.clockId!);

  ParttimeRecord get record => _record;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    final detail = await ParttimeClockService().fetchClockDetail(
      id: _record.id,
      fallback: _record,
    );
    if (!mounted) return;
    setState(() {
      // 接口成功时用服务端记录回填头部（推送入口尤其依赖此回填）
      if (detail.errorMessage == null) {
        _record = detail.clock;
        _expense = detail.expense;
      }
      _tasks = detail.completedTasks;
      _loading = false;
    });
    if (detail.errorMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(detail.errorMessage!)));
    }
  }

  /// 重新编辑打卡：预填原记录重新提交（沿用同一 submit 接口，后端按 work_date
  /// 命中该条驳回记录并重置为待审核）。成功后重新拉取详情刷新审核态。
  Future<void> _onEditClock() async {
    if (_submitting) return;
    final payload = await showParttimeClockOutSheet(
      context,
      defaultStartAt:
          DateTime.fromMillisecondsSinceEpoch(_record.workStartTime * 1000),
      defaultEndAt:
          DateTime.fromMillisecondsSinceEpoch(_record.workEndTime * 1000),
      initialHasLunchBreak: _record.hasLunchBreak,
      initialHasExpense: _record.hasExpense,
      initialExpenseAmount: _record.hasExpense ? _record.expenseAmount : null,
      title: '重新编辑打卡',
      lockDate: true,
    );
    if (payload == null || !mounted) return;
    setState(() => _submitting = true);
    final r = await ParttimeClockService().submitClock(
      workStartTime: payload.workStartTime,
      workEndTime: payload.workEndTime,
      hasLunchBreak: payload.hasLunchBreak,
      hasExpense: payload.hasExpense,
      expenseAmount: payload.expenseAmount,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.success ? '已重新提交，等待审核' : (r.message ?? '提交失败'))),
    );
    if (r.success) _loadDetail();
  }

  /// 编辑 / 驳回重提报销单：预填原单弹编辑表单，提交走
  /// /v1/parttime_expense/save（expense_id>0），成功后重置为待审核并回刷详情。
  Future<void> _onEditExpense() async {
    final expense = _expense;
    if (_expenseBusy || expense == null) return;
    final rejected = expense.auditStatus == ParttimeAuditStatus.rejected;
    final payload = await showParttimeExpenseEditSheet(
      context,
      initialAmount: expense.amount,
      initialVoucherUrls: expense.voucherUrls,
      initialRemark: expense.remark,
      title: rejected ? '重新提交报销单' : '编辑报销单',
    );
    if (payload == null || !mounted) return;
    setState(() => _expenseBusy = true);
    final r = await ParttimeExpenseService().save(
      expenseId: expense.id,
      amount: payload.amount,
      voucherUrls: payload.voucherUrls,
      remark: payload.remark,
    );
    if (!mounted) return;
    setState(() => _expenseBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.success ? '报销单已重新提交，等待审核' : (r.message ?? '提交失败')),
      ),
    );
    if (r.success) _loadDetail();
  }

  /// 取消报销单：终态不可恢复，先弹确认；仅待审核 / 已驳回可取消。
  Future<void> _onCancelExpense() async {
    final expense = _expense;
    if (_expenseBusy || expense == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消报销单'),
        content: const Text('取消后不可恢复，确定取消该报销单吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想',
                style: TextStyle(color: Color(0xFF666666))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定取消', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _expenseBusy = true);
    final r = await ParttimeExpenseService().cancel(expenseId: expense.id);
    if (!mounted) return;
    setState(() => _expenseBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.success ? '报销单已取消' : (r.message ?? '取消失败'))),
    );
    if (r.success) _loadDetail();
  }

  String _fmtDateTime(int seconds) {
    if (seconds <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }

  String _fmtTime(int seconds) {
    if (seconds <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(d.hour)}:${pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '兼职记录详情',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 12),
          _buildInfoCard(
            title: '工时',
            rows: [
              _Row('上班时间', _fmtTime(record.workStartTime)),
              _Row('下班时间', _fmtTime(record.workEndTime)),
              _Row(
                '工作时长',
                '${record.netWorkHours.toStringAsFixed(1)} 小时',
                // 工作时长恒为按打卡时间的原始估算（含午休扣减），真实计薪
                // 口径看结算信息卡的「计薪工时」（审核通过后后端下发）。
                note: record.hasLunchBreak
                    ? '（打卡 ${record.workHours.toStringAsFixed(1)} 小时，'
                        '午休扣减 ${ParttimeRecord.lunchDeductHours.toStringAsFixed(0)} 小时；审核后以计薪工时为准）'
                    : '（审核通过后以计薪工时为准）',
              ),
              _Row('是否午休', record.hasLunchBreak ? '是' : '否'),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            title: '交通费',
            rows: record.hasExpense
                ? [
                    _Row('是否产生', '是'),
                    _Row('金额', '₩ ${_fmtWon(record.expenseAmount.toDouble())}'),
                  ]
                : [_Row('是否产生', '否')],
          ),
          const SizedBox(height: 12),
          // 独立报销单（与交通费无关），该打卡有关联报销单时才展示
          if (_expense != null) ...[
            _buildExpenseCard(_expense!),
            const SizedBox(height: 12),
          ],
          // 结算信息：审核通过后后端才下发时薪 / 奖金 / 结算金额
          if (record.isSettled) ...[
            _buildSettlementCard(),
            const SizedBox(height: 12),
          ],
          _buildInfoCard(
            title: '提交信息',
            rows: [
              _Row('审核状态', ParttimeAuditStatus.label(record.auditStatus)),
              if (record.addTime > 0)
                _Row('提交时间', _fmtDateTime(record.addTime)),
            ],
          ),
          if (record.auditStatus == ParttimeAuditStatus.rejected) ...[
            const SizedBox(height: 12),
            _buildRejectCard(),
          ],
          const SizedBox(height: 12),
          _buildTasksSection(),
        ],
      ),
      bottomNavigationBar: record.canEdit ? _buildEditBar() : null,
    );
  }

  /// 驳回原因卡片（审核驳回时展示）
  Widget _buildRejectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '驳回原因',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCCC7)),
            ),
            child: Text(
              record.rejectReason.isEmpty ? '—' : record.rejectReason,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF333333),
                height: 1.5,
              ),
            ),
          ),
          if (record.canEdit) ...[
            const SizedBox(height: 8),
            const Text(
              '审核被驳回，可重新编辑打卡后再次提交。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部「重新编辑打卡」操作条（仅 can_edit 时展示）
  Widget _buildEditBar() {
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
          height: 44,
          child: ElevatedButton(
            onPressed: _submitting ? null : _onEditClock,
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '重新编辑打卡',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final (auditColor, auditBg) = _auditColor(record.auditStatus);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F0FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.event_available, color: _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    record.workDate.isEmpty ? '—' : record.workDate,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: auditBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ParttimeAuditStatus.label(record.auditStatus),
                    style: TextStyle(
                      color: auditColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _auditColor(int status) {
    switch (status) {
      case ParttimeAuditStatus.approved:
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case ParttimeAuditStatus.rejected:
        return (const Color(0xFFFF4D4F), const Color(0xFFFFEBEC));
      case ParttimeAuditStatus.pending:
      default:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
    }
  }

  Widget _buildInfoCard({required String title, required List<_Row> rows}) {
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
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        r.label,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF999999)),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.value,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF1A1A1A)),
                          ),
                          if (r.note != null && r.note!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                r.note!,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF999999)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// 报销单卡片：金额 / 凭证（点击大图预览）/ 备注 + 独立审核状态徽章。
  /// 报销单与交通费互相独立、单独审核；编辑 / 重新提交 / 取消按 can_edit /
  /// can_cancel 出按钮，走 ParttimeExpenseService（/v1/parttime_expense）。
  Widget _buildExpenseCard(ParttimeExpense expense) {
    final (auditColor, auditBg) = _auditColor(expense.auditStatus);
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
                  '报销单',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: auditBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ParttimeAuditStatus.label(expense.auditStatus),
                  style: TextStyle(
                    color: auditColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _expenseRow('报销金额', '₩ ${_fmtWon(expense.amount.toDouble())}'),
          if (expense.remark.isNotEmpty) _expenseRow('备注', expense.remark),
          if (expense.voucherUrls.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              '报销凭证',
              style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < expense.voucherUrls.length; i++)
                  GestureDetector(
                    onTap: () => showImagePreview(
                      context,
                      imageUrls: expense.voucherUrls,
                      initialIndex: i,
                      title: '报销凭证',
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: expense.voucherUrls[i],
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 64,
                          height: 64,
                          color: const Color(0xFFF0F1F3),
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: const Color(0xFFF0F1F3),
                          child: const Icon(Icons.broken_image_outlined,
                              size: 20, color: Color(0xFFB0B0B0)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (expense.auditStatus == ParttimeAuditStatus.rejected &&
              expense.rejectReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '驳回原因：${expense.rejectReason}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCF1322),
                  height: 1.4,
                ),
              ),
            ),
          ],
          // 待审核 / 已驳回时可编辑或取消（后端 can_edit / can_cancel 驱动）
          if (expense.canEdit || expense.canCancel) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (expense.canCancel)
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: _expenseBusy ? null : _onCancelExpense,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF666666),
                        side: const BorderSide(color: Color(0xFFE5E5E5)),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child:
                          const Text('取消报销', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                if (expense.canCancel && expense.canEdit)
                  const SizedBox(width: 10),
                if (expense.canEdit)
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: _expenseBusy ? null : _onEditExpense,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primary,
                        side: const BorderSide(color: _primary),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        expense.auditStatus == ParttimeAuditStatus.rejected
                            ? '重新提交'
                            : '编辑',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expenseRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
  }

  /// 结算信息卡片（审核通过后展示）：计薪工时 / 时薪 / 奖金 / 交通费 /
  /// 已通过报销 / 结算金额，金额行高亮。
  Widget _buildSettlementCard() {
    final expense = _expense;
    // 仅审核已通过的有效报销并入结算信息；待审核/已驳回在报销单卡片单独呈现
    final reimburseApproved = expense != null &&
        expense.isValid &&
        expense.auditStatus == ParttimeAuditStatus.approved;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '结算信息',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          _settlementRow('计薪工时', '${record.settledWorkHours.toStringAsFixed(1)} 小时'),
          _settlementRow('时薪', '₩ ${_fmtWon(record.hourlyRate)} / 小时'),
          _settlementRow('奖金', '₩ ${_fmtWon(record.bonusTotal)}'),
          if (record.hasExpense)
            _settlementRow(
                '交通费', '₩ ${_fmtWon(record.expenseAmount.toDouble())}'),
          if (reimburseApproved)
            _settlementRow('报销', '₩ ${_fmtWon(expense.amount.toDouble())}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFEDEFF2)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '结算金额',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                '₩ ${_fmtWon(record.settlementAmount)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF52C41A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settlementRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
          ),
        ],
      ),
    );
  }

  /// 韩币金额千分位格式化（无小数）
  static String _fmtWon(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ───────────────────── 当天已完成任务 ─────────────────────

  Widget _buildTasksSection() {
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
              const Text(
                '当天已完成任务',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(width: 6),
              if (!_loading && _tasks.isNotEmpty)
                Text(
                  '(${_tasks.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF999999),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '当天暂无已完成任务',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            )
          else
            for (var i = 0; i < _tasks.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _tasks.length - 1 ? 0 : 10,
                ),
                child: _buildTaskCard(_tasks[i]),
              ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(ParttimeCompletedTask t) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        // 进任务详情可能处理驳回/编辑等，返回后回刷当天已完成任务状态
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PartTimeTaskDetailPage(taskId: t.id),
          ),
        );
        if (mounted) _loadDetail();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          border: Border.all(color: const Color(0xFFEDEFF2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.hospitalName.isEmpty ? '医院信息缺失' : t.hospitalName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                if (t.auditStatusLabel.isNotEmpty)
                  _auditBadge(t.auditStatus, t.auditStatusLabel)
                else if (t.statusLabel.isNotEmpty)
                  Text(
                    t.statusLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF52C41A),
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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (t.scheduleTypeLabel.isNotEmpty) _tag(t.scheduleTypeLabel),
                if (t.clientName.isNotEmpty) _tag('客户 ${t.clientName}'),
              ],
            ),
            const SizedBox(height: 8),
            _taskRow('任务时间',
                t.appointTimeStr.isNotEmpty ? t.appointTimeStr : '—'),
            _taskRow('完成时间',
                t.finishTimeStr.isNotEmpty ? t.finishTimeStr : '—'),
            _taskRow('时薪 / 奖金',
                '₩${t.price.toStringAsFixed(2)} / ₩${t.bonus.toStringAsFixed(2)}'),
            if (t.auditStatus == ParttimeAuditStatus.rejected &&
                t.auditRejectReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '驳回原因：${t.auditRejectReason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFCF1322),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 任务审核状态徽章：驳回红 / 通过绿 / 其余橙
  Widget _auditBadge(int status, String label) {
    final Color color;
    switch (status) {
      case ParttimeAuditStatus.rejected:
        color = const Color(0xFFFF4D4F);
        break;
      case ParttimeAuditStatus.approved:
        color = const Color(0xFF52C41A);
        break;
      default:
        color = const Color(0xFFFA8C16);
    }
    return Text(
      label,
      style: TextStyle(fontSize: 12, color: color),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: _primary)),
    );
  }

  Widget _taskRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;

  /// 值下方的浅色补充说明（如午休扣减口径），为空则不展示
  final String? note;
  _Row(this.label, this.value, {this.note});
}
