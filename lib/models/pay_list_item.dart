/// 录单列表项模型 — 解析 /v1/schedule/paylist 返回的数据
class PayListItem {
  final int id;
  final String clientName;
  final double operationAmount;
  final double actualAmount;
  final String operationTime;
  final String depositTime;
  final int payType;
  final String payTypeName;
  final int actualStatus;
  final String currency;
  final double rebatePercent;
  final double channelDeduction;
  final String channelName;
  final String operationType;
  final String operationProject;
  final String operationProjectName;
  final String operationDirector;
  final String operationRoomDirector;
  final String customerManager;
  final int chargingType;
  final String chargingTypeName;
  final int operationStatus;
  final int domesticStatus; // 国内审核状态: 0=未审核, 1=已审核
  final int overseasStatus; // 海外审核状态: 0=未审核, 1=已审核
  final double deductionFee;
  final String deductionReason;
  final String remark;
  final String createdAt;
  final String referrer;
  final int hospitalId;
  final String hospitalName;
  final double discountAmount;
  final List<Map<String, dynamic>> projectInfo;

  PayListItem({
    required this.id,
    required this.clientName,
    required this.operationAmount,
    required this.actualAmount,
    required this.operationTime,
    required this.depositTime,
    required this.payType,
    required this.payTypeName,
    required this.actualStatus,
    required this.currency,
    required this.rebatePercent,
    required this.channelDeduction,
    required this.channelName,
    required this.operationType,
    required this.operationProject,
    required this.operationProjectName,
    required this.operationDirector,
    required this.operationRoomDirector,
    required this.customerManager,
    required this.chargingType,
    required this.chargingTypeName,
    required this.operationStatus,
    required this.domesticStatus,
    required this.overseasStatus,
    required this.deductionFee,
    required this.deductionReason,
    required this.remark,
    required this.createdAt,
    required this.referrer,
    required this.hospitalId,
    required this.hospitalName,
    required this.discountAmount,
    required this.projectInfo,
  });

  factory PayListItem.fromJson(Map<String, dynamic> json) {
    return PayListItem(
      id: _parseInt(json['id'], 0),
      clientName:
          json['ClientName']?.toString() ??
          json['client_name']?.toString() ??
          '',
      operationAmount: _parseDouble(json['number'] ?? json['operation_amount']),
      actualAmount: _parseDouble(json['true_number'] ?? json['actual_amount']),
      operationTime:
          json['time']?.toString() ?? json['operation_time']?.toString() ?? '',
      depositTime:
          json['yp_close_time']?.toString() ??
          json['deposit_time']?.toString() ??
          '',
      payType: _parseInt(json['pay_type'], 0),
      payTypeName: json['pay_type_name']?.toString() ?? '',
      actualStatus: _parseInt(json['true_type'] ?? json['actual_status'], 0),
      currency:
          json['currency']?.toString() ??
          json['currency_type']?.toString() ??
          '',
      rebatePercent: _parseDouble(json['rebates'] ?? json['rebate_percent']),
      channelDeduction: _parseDouble(
        json['qudao_percent'] ?? json['channel_deduction'],
      ),
      channelName:
          json['qudao_name']?.toString() ??
          json['channel_name']?.toString() ??
          '',
      operationType:
          json['op_type']?.toString() ??
          json['operation_type']?.toString() ??
          '',
      operationProject:
          json['verym_project']?.toString() ??
          json['operation_project']?.toString() ??
          '',
      operationProjectName: json['item']?.toString() ?? '',
      operationDirector:
          json['ss_dean']?.toString() ??
          json['doctor']?.toString() ??
          json['operation_director']?.toString() ??
          '',
      operationRoomDirector:
          json['ss_notify']?.toString() ??
          json['operation_room_director']?.toString() ??
          '',
      customerManager: json['customer_manager']?.toString() ?? '',
      chargingType: _parseInt(json['charging_type'], 0),
      chargingTypeName: json['charging_type_name']?.toString() ?? '',
      operationStatus: _parseInt(
        json['kr_status'] ?? json['operation_status'],
        0,
      ),
      domesticStatus: _parseInt(json['status'], 0),
      overseasStatus: _parseInt(json['kr_check_status'], 0),
      deductionFee: _parseDouble(json['cutnumber'] ?? json['deduction_fee']),
      deductionReason:
          json['cutwhy']?.toString() ??
          json['description']?.toString() ??
          json['deduction_reason']?.toString() ??
          '',
      remark: json['addnote']?.toString() ?? json['remark']?.toString() ?? '',
      createdAt:
          json['addtime']?.toString() ?? json['created_at']?.toString() ?? '',
      referrer: json['ss_referrer']?.toString() ?? '',
      hospitalId: _parseInt(
        json['transaction_hospital_id'] ?? json['hospital_id'],
        0,
      ),
      hospitalName: json['hospital']?.toString() ?? '',
      discountAmount: _parseDouble(json['discount_amount']),
      projectInfo: _parseProjectInfo(json['project_info']),
    );
  }

  String get actualStatusText => actualStatus == 1 ? '全款' : '定金';
  String get operationStatusText => operationStatus == 1 ? '已手术' : '未手术';
  String get domesticStatusText => domesticStatus == 1 ? '国内已审核' : '国内未审核';
  String get overseasStatusText => overseasStatus == 1 ? '海外已审核' : '海外未审核';
  bool get isDomesticAudited => domesticStatus == 1;
  bool get isOverseasAudited => overseasStatus == 1;

  /// 国内审核或海外审核任一通过即视为已审核（不可编辑/删除）
  bool get isAudited => domesticStatus == 1 || overseasStatus == 1;

  static List<Map<String, dynamic>> _parseProjectInfo(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  static int _parseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
