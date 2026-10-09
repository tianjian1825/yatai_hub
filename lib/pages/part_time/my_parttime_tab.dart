import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/pages/part_time/parttime_record_detail_page.dart';
import 'package:yatai_hub/services/parttime_clock_service.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';

/// 「我的兼职」Tab —— 按年月筛选历史打卡记录
class MyParttimeTab extends StatefulWidget {
  const MyParttimeTab({super.key});

  @override
  State<MyParttimeTab> createState() => _MyParttimeTabState();
}

class _MyParttimeTabState extends State<MyParttimeTab>
    with AutomaticKeepAliveClientMixin {
  late int _year;
  late int _month;
  bool _loading = false;
  List<ParttimeRecord> _records = [];

  /// 打卡变更广播订阅：详情页「重新编辑打卡」重交成功后同步刷新当前列表状态
  StreamSubscription<void>? _clockSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _clockSub = ParttimeClockService().onChanged.listen((_) {
      if (mounted) _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _clockSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final page = await ParttimeClockService().fetchMyRecords(
      year: _year,
      month: _month,
    );
    if (!mounted) return;
    setState(() {
      _records = page.list;
      _loading = false;
    });
    // 接口错误（如 404 / 网络异常等后端 raw 文案）改用 toast 提示，
    // 空态文案永远保持中文「该月暂无兼职记录」
    if (page.errorMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(page.errorMessage!)));
    }
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    final now = DateTime.now();
    if (y > now.year || (y == now.year && m > now.month)) return; // 不能未来
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final initial = DateTime(_year, _month);
    var current = initial;
    DateTime? result;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () {
                      result = current;
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.monthYear,
                initialDateTime: initial,
                maximumDate: DateTime(now.year, now.month, 1, 23, 59),
                onDateTimeChanged: (dt) => current = dt,
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result!.year == _year && result!.month == _month) return;
    setState(() {
      _year = result!.year;
      _month = result!.month;
    });
    _load();
  }

  /// 审核状态徽章配色：(前景, 背景)
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

  // ───────────────────── Build ─────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildMonthBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildMonthBar() {
    final now = DateTime.now();
    final canNext = !(_year == now.year && _month == now.month);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _shiftMonth(-1),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_left,
                size: 22,
                color: Color(0xFF666666),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickMonth,
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Text(
                  '$_year 年 ${_month.toString().padLeft(2, '0')} 月',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: canNext ? () => _shiftMonth(1) : null,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_right,
                size: 22,
                color: canNext
                    ? const Color(0xFF666666)
                    : const Color(0xFFCCCCCC),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              // 与「我的作品」空态对齐：固定占 0.6 屏高后居中，整体略偏上
              height: MediaQuery.of(context).size.height * 0.6,
              child: const EmptyStateWidget(
                icon: Icons.work_history_outlined,
                message: '该月暂无兼职记录',
              ),
            ),
          ],
        ),
      );
    }

    // 本页在 MainPage 的 extendBody:true 下，body 会延伸到底栏后面，
    // 列表底部需额外留出「底栏高度(65) + 设备底部安全区」才不会被底栏盖住。
    const tabBarHeight = 65.0;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + tabBarHeight + bottomInset),
        itemCount: _records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, idx) => _buildCard(_records[idx]),
      ),
    );
  }

  Widget _buildCard(ParttimeRecord r) {
    final (auditColor, auditBg) = _auditColor(r.auditStatus);
    // 有效报销单才展示（已取消不显示）
    final hasReimburse = r.expense != null && r.expense!.isValid;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        // 详情页内可能操作报销单（重提/取消）等，返回后静默重拉当月列表对齐
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParttimeRecordDetailPage(record: r),
          ),
        );
        if (mounted) _load();
      },
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
                  child: Text.rich(
                    TextSpan(
                      text: r.workDate.isEmpty ? '—' : r.workDate,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                      children: [
                        TextSpan(
                          text:
                              ' · ${r.displayWorkHours.toStringAsFixed(1)} 小时',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: auditBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ParttimeAuditStatus.label(r.auditStatus),
                    style: TextStyle(
                      fontSize: 12,
                      color: auditColor,
                      fontWeight: FontWeight.w500,
                    ),
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
            // 费用行：交通费 / 报销灰字弱化（费用是明细不是状态），
            // 仅报销「已驳回」时状态词标红提醒；无费用则整行不显示
            if (r.hasExpense || hasReimburse) ...[
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                  children: [
                    if (r.hasExpense)
                      TextSpan(
                        text:
                            '交通费 ₩${_fmtWon(r.expenseAmount.toDouble())}',
                      ),
                    if (r.hasExpense && hasReimburse)
                      const TextSpan(text: ' · '),
                    // 报销默认只展示金额（避免与右上角打卡审核徽章的
                    // 「已通过」重复），仅被驳回时红字标注提醒处理
                    if (hasReimburse) ...[
                      TextSpan(
                        text: '报销 ₩${_fmtWon(r.expense!.amount.toDouble())}',
                      ),
                      if (r.expense!.auditStatus ==
                          ParttimeAuditStatus.rejected) ...[
                        const TextSpan(text: '（'),
                        const TextSpan(
                          text: '已驳回',
                          style: TextStyle(color: Color(0xFFFF4D4F)),
                        ),
                        const TextSpan(text: '）'),
                      ],
                    ],
                  ],
                ),
              ),
            ],
            // 结算金额：深色加粗右对齐，作为卡片唯一的金额强调
            if (r.isSettled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '结算 ₩${_fmtWon(r.settlementAmount)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
            if (r.auditStatus == ParttimeAuditStatus.rejected &&
                r.rejectReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '驳回原因：${r.rejectReason}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCF1322),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
