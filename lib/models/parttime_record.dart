/// 兼职日打卡历史记录
///
/// 由 /v1/parttime_clock/my_records 接口返回的列表项，也作为详情数据源。
class ParttimeRecord {
  final int id;

  /// 本地约定的工作日期 yyyy-MM-dd（便于列表分组与展示）
  final String workDate;

  /// 上班 / 下班时间 unix 秒
  final int workStartTime;
  final int workEndTime;

  /// 上班 / 下班时间 HH:mm（records 下发，已按打卡时区换算；缺省为空，
  /// 展示方可回退用本机时区格式化 unix 秒）
  final String workStartStr;
  final String workEndStr;

  /// 是否午休（后端 has_lunch_break，打卡提交必填）
  final bool hasLunchBreak;

  /// 是否产生交通费 + 金额
  final bool hasExpense;
  final int expenseAmount;

  /// 提交时间 unix 秒（创建时间）
  final int addTime;

  /// 审核状态：0=待审核 1=已通过 2=已驳回
  final int auditStatus;

  /// 审核驳回原因（后端 reject_reason，auditStatus==rejected 时有值）
  final String rejectReason;

  /// 是否允许重新编辑重交（后端 can_edit，仅 auditStatus==rejected 时为 true）。
  /// 重交沿用同一个 /v1/parttime_clock/submit 接口，后端按 work_date 命中并更新。
  final bool canEdit;

  /// 后端核算的计薪工时（小时，work_hours）。审核前为 0，审核通过后下发权威值，
  /// 口径可能与本地按上下班时间差估算的 [netWorkHours] 不一致，应优先采用本字段。
  final double settledWorkHours;

  /// 时薪（₩/小时，hourly_rate）。审核前为 0，审核通过后下发。
  final double hourlyRate;

  /// 奖金合计（₩，bonus_total）。审核前为 0，审核通过后下发。
  final double bonusTotal;

  /// 结算金额（₩，settlement_amount）= 时薪 × 计薪工时 + 奖金 + 交通费
  /// + 报销（仅报销单审核已通过时计入，见 [expense]）。审核通过后下发。
  final double settlementAmount;

  /// 关联的独立报销单（records 列表随条下发最新一条，无则 null）。
  /// 与交通费 [expenseAmount] 互相独立，报销金额在 expense.amount。
  final ParttimeExpense? expense;

  ParttimeRecord({
    required this.id,
    required this.workDate,
    required this.workStartTime,
    required this.workEndTime,
    this.workStartStr = '',
    this.workEndStr = '',
    this.hasLunchBreak = false,
    required this.hasExpense,
    required this.expenseAmount,
    required this.addTime,
    required this.auditStatus,
    this.rejectReason = '',
    this.canEdit = false,
    this.settledWorkHours = 0,
    this.hourlyRate = 0,
    this.bonusTotal = 0,
    this.settlementAmount = 0,
    this.expense,
  });

  factory ParttimeRecord.fromJson(Map<String, dynamic> json) => ParttimeRecord(
        id: _asInt(json['id']),
        workDate: json['work_date']?.toString() ?? '',
        workStartTime: _asInt(json['work_start_time']),
        workEndTime: _asInt(json['work_end_time']),
        workStartStr: json['work_start_str']?.toString() ?? '',
        workEndStr: json['work_end_str']?.toString() ?? '',
        hasLunchBreak: _asBool(json['has_lunch_break']),
        hasExpense: _asBool(json['has_expense']),
        expenseAmount: _asInt(json['expense_amount']),
        addTime: _asInt(json['add_time']),
        auditStatus: _asInt(json['audit_status']),
        rejectReason: json['reject_reason']?.toString() ?? '',
        canEdit: _asBool(json['can_edit']),
        settledWorkHours: _asDouble(json['work_hours']),
        hourlyRate: _asDouble(json['hourly_rate']),
        bonusTotal: _asDouble(json['bonus_total']),
        settlementAmount: _asDouble(json['settlement_amount']),
        expense: json['expense'] is Map
            ? ParttimeExpense.fromJson(
                Map<String, dynamic>.from(json['expense']))
            : null,
      );

  /// 仅携带打卡 id 的占位记录，用于推送跳转等场景：进入详情页后再凭
  /// [id] 调 /v1/parttime_clock/detail 拉取完整信息回填头部。
  factory ParttimeRecord.placeholder(int id) => ParttimeRecord(
        id: id,
        workDate: '',
        workStartTime: 0,
        workEndTime: 0,
        hasExpense: false,
        expenseAmount: 0,
        addTime: 0,
        auditStatus: ParttimeAuditStatus.pending,
      );

  /// 午休扣减工时（小时）。后端最终核算口径：有午休则在工时上扣 1 小时。
  static const double lunchDeductHours = 1.0;

  /// 打卡工时（小时数，保留 1 位小数）：纯按上下班时间差计算，不扣午休。
  double get workHours {
    if (workEndTime <= workStartTime) return 0;
    return (workEndTime - workStartTime) / 3600.0;
  }

  /// 计薪工时（小时数）：有午休时在 [workHours] 上扣减 [lunchDeductHours]，
  /// 下限 0，仅作审核前的本地估算用，最终以后端 [settledWorkHours] 为准。
  double get netWorkHours {
    final net = workHours - (hasLunchBreak ? lunchDeductHours : 0);
    return net < 0 ? 0 : net;
  }

  /// 是否已核算：审核通过后后端才下发时薪 / 奖金 / 结算金额等结算字段。
  bool get isSettled => auditStatus == ParttimeAuditStatus.approved;

  /// 展示用工时：已核算优先采用后端权威 [settledWorkHours]，否则用本地估算
  /// [netWorkHours]（审核前后端 work_hours 为 0）。
  double get displayWorkHours =>
      settledWorkHours > 0 ? settledWorkHours : netWorkHours;
}

/// 审核状态展示工具
class ParttimeAuditStatus {
  static const int pending = 0;
  static const int approved = 1;
  static const int rejected = 2;

  static String label(int v) {
    switch (v) {
      case approved:
        return '已通过';
      case rejected:
        return '已驳回';
      case pending:
      default:
        return '待审核';
    }
  }
}

/// 兼职打卡详情中「当天已完成任务」摘要项
///
/// 由 /v1/parttime_clock/detail 接口的 data.completed_tasks[] 返回；点击后凭
/// [id] 跳转到 PartTimeTaskDetailPage 加载完整任务详情。
class ParttimeCompletedTask {
  final int id;
  final String hospitalName;

  /// 任务类型文案（术前 / 手术 / 术后）
  final String scheduleTypeLabel;

  /// 任务状态文案
  final String statusLabel;

  /// 预约 / 完成时间 unix 秒及其格式化串
  final int appointTime;
  final String appointTimeStr;
  final int finishTime;
  final String finishTimeStr;

  /// 时薪 / 价格 + 奖金
  final double price;
  final double bonus;

  /// 任务要求
  final String requireDesc;

  /// 客户姓名（取自关联日程 schedule.name）
  final String clientName;

  /// 任务审核状态及文案 / 驳回原因（completed_tasks 内，后端新增）
  final int auditStatus;
  final String auditStatusLabel;
  final String auditRejectReason;

  ParttimeCompletedTask({
    required this.id,
    required this.hospitalName,
    required this.scheduleTypeLabel,
    required this.statusLabel,
    required this.appointTime,
    required this.appointTimeStr,
    required this.finishTime,
    required this.finishTimeStr,
    required this.price,
    required this.bonus,
    required this.requireDesc,
    required this.clientName,
    this.auditStatus = 0,
    this.auditStatusLabel = '',
    this.auditRejectReason = '',
  });

  factory ParttimeCompletedTask.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'];
    return ParttimeCompletedTask(
      id: _asInt(json['id']),
      hospitalName: json['hospital_name']?.toString() ?? '',
      scheduleTypeLabel: json['schedule_type_label']?.toString() ?? '',
      statusLabel: json['status_label']?.toString() ?? '',
      appointTime: _asInt(json['appoint_time']),
      appointTimeStr: json['appoint_time_str']?.toString() ?? '',
      finishTime: _asInt(json['finish_time']),
      finishTimeStr: json['finish_time_str']?.toString() ?? '',
      price: _asDouble(json['price']),
      bonus: _asDouble(json['bonus']),
      requireDesc: json['require_desc']?.toString() ?? '',
      clientName: schedule is Map ? (schedule['name']?.toString() ?? '') : '',
      auditStatus: _asInt(json['audit_status']),
      auditStatusLabel: json['audit_status_label']?.toString() ?? '',
      auditRejectReason: json['audit_reject_reason']?.toString() ?? '',
    );
  }
}

/// 打卡关联的独立报销单（/v1/parttime_clock/detail 的 data.expense，无则 null）
///
/// 报销金额在 [amount]，与打卡交通费（clock.expense_amount）互相独立。
/// 审核状态沿用 [ParttimeAuditStatus] 三态；编辑 / 取消（can_edit / can_cancel）
/// 走独立 /v1/parttime_expense 接口，已由 ParttimeExpenseService 接入。
class ParttimeExpense {
  final int id;

  /// 报销金额（₩）
  final int amount;

  /// 报销凭证图片 URL（≤9 张）
  final List<String> voucherUrls;

  /// 报销备注
  final String remark;

  /// 报销单状态（后端 status，1=有效 2=已取消）
  final int status;

  /// 审核状态：0=待审核 1=已通过 2=已驳回
  final int auditStatus;

  /// 审核状态文案（后端 audit_status_label，缺省时用本地兜底）
  final String auditStatusLabel;

  /// 驳回原因（契约未列，防御性解析，驳回且非空时展示）
  final String rejectReason;

  final bool canEdit;
  final bool canCancel;

  ParttimeExpense({
    required this.id,
    required this.amount,
    required this.voucherUrls,
    required this.remark,
    required this.status,
    required this.auditStatus,
    this.auditStatusLabel = '',
    this.rejectReason = '',
    this.canEdit = false,
    this.canCancel = false,
  });

  /// 是否有效（未取消）；已取消（status=2）的报销单不再展示
  bool get isValid => status == 1;

  /// 审核状态展示文案：优先后端 label，缺省本地兜底
  String get displayAuditLabel => auditStatusLabel.isNotEmpty
      ? auditStatusLabel
      : ParttimeAuditStatus.label(auditStatus);

  factory ParttimeExpense.fromJson(Map<String, dynamic> json) =>
      ParttimeExpense(
        id: _asInt(json['id']),
        amount: _asInt(json['amount']),
        voucherUrls: (json['voucher_urls'] is List
                ? json['voucher_urls'] as List
                : const [])
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
        remark: json['remark']?.toString() ?? '',
        status: _asInt(json['status']),
        auditStatus: _asInt(json['audit_status']),
        auditStatusLabel: json['audit_status_label']?.toString() ?? '',
        rejectReason: json['reject_reason']?.toString() ?? '',
        canEdit: _asBool(json['can_edit']),
        canCancel: _asBool(json['can_cancel']),
      );
}

/// 兼职打卡详情（/v1/parttime_clock/detail）
class ParttimeClockDetail {
  /// 打卡记录详情（复用 [ParttimeRecord] 解析 data.clock）
  final ParttimeRecord clock;

  /// 关联的独立报销单；该打卡没有报销单时为 null
  final ParttimeExpense? expense;

  /// 当天已完成的兼职任务列表
  final List<ParttimeCompletedTask> completedTasks;

  /// 请求失败时的提示文案；非空表示加载失败
  final String? errorMessage;

  ParttimeClockDetail({
    required this.clock,
    this.expense,
    required this.completedTasks,
    this.errorMessage,
  });

  factory ParttimeClockDetail.error(ParttimeRecord fallback, String message) =>
      ParttimeClockDetail(
        clock: fallback,
        completedTasks: const [],
        errorMessage: message,
      );

  factory ParttimeClockDetail.fromJson(Map<String, dynamic> json) {
    final rawClock = json['clock'];
    final rawExpense = json['expense'];
    final rawTasks = json['completed_tasks'];
    return ParttimeClockDetail(
      clock: rawClock is Map
          ? ParttimeRecord.fromJson(Map<String, dynamic>.from(rawClock))
          : ParttimeRecord.fromJson(const {}),
      expense: rawExpense is Map
          ? ParttimeExpense.fromJson(Map<String, dynamic>.from(rawExpense))
          : null,
      completedTasks: (rawTasks is List ? rawTasks : const [])
          .whereType<Map>()
          .map((e) =>
              ParttimeCompletedTask.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
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

/// 列表分页返回
class ParttimeRecordPage {
  final List<ParttimeRecord> list;
  final int total;
  final String? errorMessage;

  ParttimeRecordPage({
    required this.list,
    required this.total,
    this.errorMessage,
  });
}

/// 当天打卡状态（/v1/parttime_clock/today）
///
/// 作为底部打卡按钮显隐的权威依据：本地缓存在卸载重装 / 切换账号后会失真，
/// 以服务端 [canSubmit] / [hasClock] 为准校正。
class ParttimeTodayStatus {
  /// 查询日期 yyyy-MM-dd（服务端时区）
  final String workDate;

  /// 当天是否已打卡
  final bool hasClock;

  /// 当天打卡状态机：none 无记录 / clocked_in 进行中 / completed 已完成 /
  /// rejected 被驳回可重打
  final String clockStatus;

  /// 当前是否还可以提交打卡（none / rejected / clocked_in 时为 true）
  final bool canSubmit;

  /// 当天打卡记录；未打卡为 null
  final ParttimeRecord? record;

  /// 请求失败时的提示文案；非空表示拉取失败，调用方应回退本地缓存
  final String? errorMessage;

  ParttimeTodayStatus({
    required this.workDate,
    required this.hasClock,
    this.clockStatus = '',
    required this.canSubmit,
    this.record,
    this.errorMessage,
  });

  /// 是否「上班进行中」（已 clock_in 未 clock_out）
  bool get isClockedIn => clockStatus == 'clocked_in';

  factory ParttimeTodayStatus.error(String message) => ParttimeTodayStatus(
        workDate: '',
        hasClock: false,
        canSubmit: false,
        errorMessage: message,
      );

  factory ParttimeTodayStatus.fromJson(Map<String, dynamic> json) {
    final rawRecord = json['record'];
    return ParttimeTodayStatus(
      workDate: json['work_date']?.toString() ?? '',
      hasClock: _asBool(json['has_clock']),
      clockStatus: json['clock_status']?.toString() ?? '',
      canSubmit: _asBool(json['can_submit']),
      record: rawRecord is Map
          ? ParttimeRecord.fromJson(Map<String, dynamic>.from(rawRecord))
          : null,
    );
  }
}
