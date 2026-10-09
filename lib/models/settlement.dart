import 'dart:ui';

import 'package:yatai_hub/models/parttime_record.dart';

/// 兼职钱包/结算相关数据模型
///
/// 对应后端 /v1/settlement 一组接口（钱包总览、收入流水、可结算明细、
/// 结算/提现历史、结算单明细、发起提现）。金额字段统一用 [_asDouble] 解析，
/// 展示时按需 `toStringAsFixed`。

/// 钱包总览（GET /v1/settlement/wallet_summary）
class WalletSummary {
  /// 可提现金额 / 天数（已审核未结算）
  final double withdrawableAmount;
  final int withdrawableDays;

  /// 结算中金额（申请中的结算单合计）
  final double settlingAmount;

  /// 累计已到账金额
  final double paidTotal;

  /// 当前月份 YYYY-MM / 本月已审核收入
  final String month;
  final double monthIncome;

  /// 是否持打工证 1/0
  final bool hasWorkcard;

  /// 能否 App 提现（有打工证=false，走后台月结）
  final bool canWithdraw;

  /// 不可提现时的提示文案
  final String withdrawTip;

  WalletSummary({
    required this.withdrawableAmount,
    required this.withdrawableDays,
    required this.settlingAmount,
    required this.paidTotal,
    required this.month,
    required this.monthIncome,
    required this.hasWorkcard,
    required this.canWithdraw,
    required this.withdrawTip,
  });

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
    withdrawableAmount: _asDouble(json['withdrawable_amount']),
    withdrawableDays: _asInt(json['withdrawable_days']),
    settlingAmount: _asDouble(json['settling_amount']),
    paidTotal: _asDouble(json['paid_total']),
    month: json['month']?.toString() ?? '',
    monthIncome: _asDouble(json['month_income']),
    hasWorkcard: _asBool(json['has_workcard']),
    canWithdraw: _asBool(json['can_withdraw']),
    withdrawTip: json['withdraw_tip']?.toString() ?? '',
  );

  /// 用于本地缓存（键与后端字段保持一致，便于 fromJson 回读）
  Map<String, dynamic> toJson() => {
    'withdrawable_amount': withdrawableAmount,
    'withdrawable_days': withdrawableDays,
    'settling_amount': settlingAmount,
    'paid_total': paidTotal,
    'month': month,
    'month_income': monthIncome,
    'has_workcard': hasWorkcard,
    'can_withdraw': canWithdraw,
    'withdraw_tip': withdrawTip,
  };
}

/// 收款账号信息（GET/POST /v1/settlement/payment_info）
///
/// 兼职提现打款用的支付宝账号 + 实名姓名。[isSet] 由后端判定（账号与姓名
/// 都非空才为 true），App 据此决定是否引导用户填写。
class PaymentInfo {
  /// 收款支付宝账号（手机/邮箱）；未设置为空串
  final String alipayAccount;

  /// 收款人真实姓名；未设置为空串
  final String alipayName;

  /// 是否已设置（账号与姓名都非空）
  final bool isSet;

  const PaymentInfo({
    required this.alipayAccount,
    required this.alipayName,
    required this.isSet,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) => PaymentInfo(
    alipayAccount: json['alipay_account']?.toString() ?? '',
    alipayName: json['alipay_name']?.toString() ?? '',
    isSet: _asBool(json['is_set']),
  );

  /// 用于本地缓存
  Map<String, dynamic> toJson() => {
    'alipay_account': alipayAccount,
    'alipay_name': alipayName,
    'is_set': isSet,
  };

  static const empty = PaymentInfo(
    alipayAccount: '',
    alipayName: '',
    isSet: false,
  );
}

/// 收入流水项（GET /v1/settlement/income_flow，以每天打卡为主线）
class IncomeFlowItem {
  final int clockId;
  final String workDate;
  final String workStartStr;
  final String workEndStr;
  final double workHours;
  final double hourlyRate;
  final double bonusTotal;
  final double settlementAmount;

  /// 当日交通费（₩，后端 expense_amount；未下发或无交通费为 0）
  final int expenseAmount;

  /// 关联结算单 id（未结算时可能为 0）
  final int settlementId;

  /// 流水状态：settleable 可提现 / settling 结算中 / paid 已到账
  final String flowStatus;
  final String flowStatusLabel;

  /// 该打卡关联的独立报销单（最新一条，无则 null）。报销单审核已通过时
  /// 金额计入 [settlementAmount]（=工时×时薪+奖金+交通费+已通过报销），
  /// 待审核/已驳回则不计入、仅随流水单独展示。
  final ParttimeExpense? expense;

  IncomeFlowItem({
    required this.clockId,
    required this.workDate,
    required this.workStartStr,
    required this.workEndStr,
    required this.workHours,
    required this.hourlyRate,
    required this.bonusTotal,
    required this.settlementAmount,
    this.expenseAmount = 0,
    required this.settlementId,
    required this.flowStatus,
    required this.flowStatusLabel,
    this.expense,
  });

  factory IncomeFlowItem.fromJson(Map<String, dynamic> json) => IncomeFlowItem(
    clockId: _asInt(json['clock_id']),
    workDate: json['work_date']?.toString() ?? '',
    workStartStr: json['work_start_str']?.toString() ?? '',
    workEndStr: json['work_end_str']?.toString() ?? '',
    workHours: _asDouble(json['work_hours']),
    hourlyRate: _asDouble(json['hourly_rate']),
    bonusTotal: _asDouble(json['bonus_total']),
    settlementAmount: _asDouble(json['settlement_amount']),
    expenseAmount: _asInt(json['expense_amount']),
    settlementId: _asInt(json['settlement_id']),
    flowStatus: json['flow_status']?.toString() ?? '',
    flowStatusLabel: json['flow_status_label']?.toString() ?? '',
    expense: json['expense'] is Map
        ? ParttimeExpense.fromJson(Map<String, dynamic>.from(json['expense']))
        : null,
  );
}

/// 可结算/结算单逐日明细项
/// （GET /v1/settlement/income_summary.list[] 与 detail.items[] 共用结构）
class IncomeSummaryDay {
  final int clockId;
  final String workDate;
  final String workStartStr;
  final String workEndStr;
  final double workHours;
  final double hourlyRate;
  final double bonusTotal;
  final double settlementAmount;

  /// 当日交通费（₩，后端 expense_amount；未下发或无交通费为 0）
  final int expenseAmount;

  /// 该打卡关联的独立报销单（结算单明细 detail.items[] 随条下发；
  /// income_summary 未下发时为 null）
  final ParttimeExpense? expense;

  IncomeSummaryDay({
    required this.clockId,
    required this.workDate,
    required this.workStartStr,
    required this.workEndStr,
    required this.workHours,
    required this.hourlyRate,
    required this.bonusTotal,
    required this.settlementAmount,
    this.expenseAmount = 0,
    this.expense,
  });

  factory IncomeSummaryDay.fromJson(Map<String, dynamic> json) =>
      IncomeSummaryDay(
        clockId: _asInt(json['clock_id']),
        workDate: json['work_date']?.toString() ?? '',
        workStartStr: json['work_start_str']?.toString() ?? '',
        workEndStr: json['work_end_str']?.toString() ?? '',
        workHours: _asDouble(json['work_hours']),
        hourlyRate: _asDouble(json['hourly_rate']),
        bonusTotal: _asDouble(json['bonus_total']),
        settlementAmount: _asDouble(json['settlement_amount']),
        expenseAmount: _asInt(json['expense_amount']),
        expense: json['expense'] is Map
            ? ParttimeExpense.fromJson(
                Map<String, dynamic>.from(json['expense']))
            : null,
      );
}

/// 结算/提现单（GET /v1/settlement/history.list[] 与 detail.settle 共用）
class SettlementRecord {
  /// 结算单 ID（查明细用）
  final int id;

  /// 1=即时提现 2=月结
  final int settleType;
  final String settleTypeLabel;

  /// 月结期间 YYYY-MM；提现为空
  final String period;

  final double amount;

  /// 结算币种（如 KRW）；为空时按韩元展示
  final String currency;

  /// 结算汇率（如 228，表示 1 元人民币兑多少结算币种）；0 表示无
  final double exchangeRate;

  /// 折合人民币金额；>0 时展示
  final double rmbAmount;

  /// 津贴（结算单级额外补贴，已计入 amount，仅展示用）
  final double allowance;

  final int daysCount;

  /// 1 申请中 2 已完成 3 已驳回
  final int status;
  final String statusLabel;

  /// 驳回原因
  final String rejectReason;

  /// 申请 / 处理时间
  final int applyTime;
  final String applyTimeStr;
  final String handleTimeStr;

  SettlementRecord({
    required this.id,
    required this.settleType,
    required this.settleTypeLabel,
    required this.period,
    required this.amount,
    this.currency = '',
    this.exchangeRate = 0,
    this.rmbAmount = 0,
    this.allowance = 0,
    required this.daysCount,
    required this.status,
    required this.statusLabel,
    required this.rejectReason,
    required this.applyTime,
    required this.applyTimeStr,
    required this.handleTimeStr,
  });

  factory SettlementRecord.fromJson(Map<String, dynamic> json) =>
      SettlementRecord(
        id: _asInt(json['id']),
        settleType: _asInt(json['settle_type']),
        settleTypeLabel: json['settle_type_label']?.toString() ?? '',
        period: json['period']?.toString() ?? '',
        amount: _asDouble(json['amount']),
        currency: json['currency']?.toString() ?? '',
        exchangeRate: _asDouble(json['exchange_rate']),
        rmbAmount: _asDouble(json['rmb_amount']),
        allowance: _asDouble(json['allowance']),
        daysCount: _asInt(json['days_count']),
        status: _asInt(json['status']),
        statusLabel: json['status_label']?.toString() ?? '',
        rejectReason: json['reject_reason']?.toString() ?? '',
        applyTime: _asInt(json['apply_time']),
        applyTimeStr: json['apply_time_str']?.toString() ?? '',
        handleTimeStr: json['handle_time_str']?.toString() ?? '',
      );
}

/// 结算单明细（GET /v1/settlement/detail）
class SettlementDetail {
  final SettlementRecord settle;
  final List<IncomeSummaryDay> items;

  SettlementDetail({required this.settle, required this.items});

  factory SettlementDetail.fromJson(Map<String, dynamic> json) {
    final rawSettle = json['settle'];
    final rawItems = json['items'];
    return SettlementDetail(
      settle: rawSettle is Map
          ? SettlementRecord.fromJson(Map<String, dynamic>.from(rawSettle))
          : SettlementRecord.fromJson(const {}),
      items: (rawItems is List ? rawItems : const [])
          .whereType<Map>()
          .map((e) => IncomeSummaryDay.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 收入流水分页结果
class IncomeFlowPage {
  final List<IncomeFlowItem> list;
  final int total;
  final int page;
  final int pageSize;

  /// 业务错误 / 网络错误信息；非空表示本次请求失败
  final String? errorMessage;

  IncomeFlowPage({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    this.errorMessage,
  });
}

/// 结算/提现历史分页结果
class SettlementHistoryResult {
  final List<SettlementRecord> list;
  final int total;
  final int page;
  final int pageSize;
  final String? errorMessage;

  SettlementHistoryResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    this.errorMessage,
  });
}

/// 结算单状态展示工具（颜色沿用项目既有映射）
class SettlementStatus {
  static const int applying = 1;
  static const int completed = 2;
  static const int rejected = 3;

  /// 返回 (前景色, 背景色)
  static (Color, Color) color(int status) {
    switch (status) {
      case completed:
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case rejected:
        return (const Color(0xFFFF4D4F), const Color(0xFFFFEBEC));
      case applying:
      default:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
    }
  }
}

/// 收入流水状态展示工具（按 flow_status key 映射颜色，文案用后端 label）
class IncomeFlowStatus {
  static const String settleable = 'settleable';
  static const String settling = 'settling';
  static const String paid = 'paid';

  /// 返回 (前景色, 背景色)
  static (Color, Color) color(String status) {
    switch (status) {
      case paid:
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case settling:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
      case settleable:
      default:
        return (const Color(0xFF366CDF), const Color(0xFFE6F0FF));
    }
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}
