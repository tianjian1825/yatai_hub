import 'package:yatai_hub/models/pay_list_item.dart';

/// 群聊内「医院信息查询 / 客户资料查询」用到的轻量模型。
///
/// 这些结构只保留弹窗展示需要的字段，并全部可 JSON 化——它们会作为快照写入
/// sqlite（[ChatLocalDb] 的 chat_task_context / chat_hospital_cache /
/// chat_client_cache 三张表），支持「先本地秒显、再网络刷新」。
///
/// 刻意**只依赖接口原始 JSON**（不复用客服 / 商务模块的模型），这样同一份代码
/// 能直接搬到已剥离客服模块的姊妹项目 yatai-hub。

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _asStr(dynamic v) => v?.toString().trim() ?? '';

/// 文本字段清洗：把后端"空占位"当作没有该字段。
///
/// 医院/客户老数据里，未填写的名称、地址、URL 常被存成 `0`（如
/// `branch_address: 0`、`kr_address: 0`、`url: 0`），日期则是 `0000-00-00`。
/// 这些值直接展示会变成一行「中文地址：0」，所以统一归零，由调用方跳过空行。
///
/// 仅用于文本/日期字段——金额等 `0` 有实际含义的字段不要走这里。
String cleanQueryText(dynamic v) {
  final s = _asStr(v);
  if (s.isEmpty) return '';
  if (s == '0' || s == '0.0' || s == '00' || s.toLowerCase() == 'null') {
    return '';
  }
  if (s.startsWith('0000-00-00') || s.startsWith('1970-01-01')) return '';
  return s;
}

// ─────────────────────────── 任务上下文 ───────────────────────────

/// 群聊所属兼职任务的关联对象，决定菜单里两个查询入口是否出现
class ChatTaskContext {
  final int taskId;
  final int clientId;
  final int hospitalId;
  final String hospitalName;

  const ChatTaskContext({
    required this.taskId,
    this.clientId = 0,
    this.hospitalId = 0,
    this.hospitalName = '',
  });

  bool get hasClient => clientId > 0;
  bool get hasHospital => hospitalId > 0;
  bool get isEmpty => !hasClient && !hasHospital;

  Map<String, Object?> toDbMap() => {
    'task_id': taskId,
    'client_id': clientId,
    'hospital_id': hospitalId,
    'hospital_name': hospitalName,
  };

  factory ChatTaskContext.fromDbMap(Map<String, Object?> row) =>
      ChatTaskContext(
        taskId: _asInt(row['task_id']),
        clientId: _asInt(row['client_id']),
        hospitalId: _asInt(row['hospital_id']),
        hospitalName: _asStr(row['hospital_name']),
      );
}

// ─────────────────────────── 医院信息 ───────────────────────────

/// 医院信息弹窗展示所需字段（`/v1/kr_hospital/detail` 的 basic_info 子集）。
///
/// 商务敏感节点（privacy_info 返点/财务、CRM 账密、收款码、联系人电话）**不**
/// 进入这个结构，避免随缓存落到兼职用户设备上。
class KrHospitalBrief {
  final int hospitalId;
  final String nameCn;
  final String nameKr;
  final String nameEn;
  final String alias;
  final String addressCn;
  final String addressKr;
  final String url;
  final String statusLabel;

  const KrHospitalBrief({
    required this.hospitalId,
    this.nameCn = '',
    this.nameKr = '',
    this.nameEn = '',
    this.alias = '',
    this.addressCn = '',
    this.addressKr = '',
    this.url = '',
    this.statusLabel = '',
  });

  /// 解析 `/v1/kr_hospital/detail` 的 data —— **只读 basic_info 节点**，
  /// business/privacy/appointment/resource 等节点连解析都不做。
  factory KrHospitalBrief.fromDetailJson(Map<String, dynamic> data) {
    final basic = data['basic_info'] is Map
        ? Map<String, dynamic>.from(data['basic_info'] as Map)
        : const <String, dynamic>{};
    return KrHospitalBrief(
      hospitalId: _asInt(basic['hospital_id']),
      nameCn: cleanQueryText(basic['companyname']),
      nameKr: cleanQueryText(basic['kr_companyname']),
      nameEn: cleanQueryText(basic['us_companyname']),
      alias: cleanQueryText(basic['other_companyname']),
      addressCn: cleanQueryText(basic['branch_address']),
      addressKr: cleanQueryText(basic['kr_address']),
      url: cleanQueryText(basic['url']),
      statusLabel: _hospitalStatusLabel(basic['is_suspend']),
    );
  }

  Map<String, dynamic> toJson() => {
    'hospital_id': hospitalId,
    'name_cn': nameCn,
    'name_kr': nameKr,
    'name_en': nameEn,
    'alias': alias,
    'address_cn': addressCn,
    'address_kr': addressKr,
    'url': url,
    'status_label': statusLabel,
  };

  factory KrHospitalBrief.fromJson(Map<String, dynamic> json) =>
      KrHospitalBrief(
        // 旧缓存里可能已经存进了 "0" 之类的占位，读回时一并清洗
        hospitalId: _asInt(json['hospital_id']),
        nameCn: cleanQueryText(json['name_cn']),
        nameKr: cleanQueryText(json['name_kr']),
        nameEn: cleanQueryText(json['name_en']),
        alias: cleanQueryText(json['alias']),
        addressCn: cleanQueryText(json['address_cn']),
        addressKr: cleanQueryText(json['address_kr']),
        url: cleanQueryText(json['url']),
        statusLabel: cleanQueryText(json['status_label']),
      );
}

/// 合作状态：un_kr_hospital.is_suspend（与商务模块 KrHospitalStatus 同口径）；
/// 未知/缺失返回空串，由 UI 跳过该行（不默认成「合作中」造成误导）
String _hospitalStatusLabel(dynamic raw) {
  switch (raw?.toString()) {
    case '0':
      return '合作中';
    case '2':
      return '倒闭';
    case '3':
      return '不合作可派单';
    default:
      return '';
  }
}

// ─────────────────────────── 客户资料 ───────────────────────────

/// 客户基本资料（`/v1/kefu/client/detail?client_id=`，单对象返回）。
///
/// 字段口径与客服系统详情页（kf_service `CustomerDetailPage`）一致。
/// 接口同时返回手机号/微信/WhatsApp/LINE 等联系方式，按需求**一律不解析**。
class ClientBasicInfo {
  final int clientId;
  final String name;
  final String kefuName;
  final String fromTypeName;
  final String fromTypeValue;

  /// 「编辑」——detail 的 `edit_user_name`
  final String editName;

  final String registerTimeText;

  const ClientBasicInfo({
    required this.clientId,
    this.name = '',
    this.kefuName = '',
    this.fromTypeName = '',
    this.fromTypeValue = '',
    this.editName = '',
    this.registerTimeText = '',
  });

  /// 解析 `/v1/kefu/client/detail` 的 data（字段名已确认，无需多候选猜测）。
  /// `register_time` 后端已格式化为字符串；仍兼容早期的秒级时间戳。
  factory ClientBasicInfo.fromApi(Map<String, dynamic> json) {
    final rawRegister = json['register_time'];
    final registerText = rawRegister is num
        ? _formatUnix(rawRegister)
        : cleanQueryText(rawRegister);
    return ClientBasicInfo(
      clientId: _asInt(json['client_id']),
      name: cleanQueryText(json['client_name']),
      kefuName: cleanQueryText(json['kf_name']),
      fromTypeName: cleanQueryText(json['from_type_name']),
      fromTypeValue: cleanQueryText(json['from_type_value']),
      editName: cleanQueryText(json['edit_user_name']),
      registerTimeText: registerText,
    );
  }

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'name': name,
    'kefu_name': kefuName,
    'from_type_name': fromTypeName,
    'from_type_value': fromTypeValue,
    'edit_name': editName,
    'register_time_text': registerTimeText,
  };

  factory ClientBasicInfo.fromJson(Map<String, dynamic> json) =>
      ClientBasicInfo(
        clientId: _asInt(json['client_id']),
        name: cleanQueryText(json['name']),
        kefuName: cleanQueryText(json['kefu_name']),
        fromTypeName: cleanQueryText(json['from_type_name']),
        fromTypeValue: cleanQueryText(json['from_type_value']),
        editName: cleanQueryText(json['edit_name']),
        registerTimeText: cleanQueryText(json['register_time_text']),
      );
}

/// 派单医院（`/v1/kefu/order/list?client_id=`）
class ClientDispatchItem {
  final int orderId;
  final int hospitalId;
  final String hospitalName;
  final String sendOrderTimeText;

  const ClientDispatchItem({
    this.orderId = 0,
    this.hospitalId = 0,
    this.hospitalName = '',
    this.sendOrderTimeText = '',
  });

  factory ClientDispatchItem.fromApi(Map<String, dynamic> json) =>
      ClientDispatchItem(
        orderId: _asInt(json['order_id']),
        hospitalId: _asInt(json['hospital_id']),
        hospitalName: cleanQueryText(json['companyname']),
        sendOrderTimeText: cleanQueryText(json['send_order_time_str']),
      );

  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'hospital_id': hospitalId,
    'hospital_name': hospitalName,
    'send_order_time_text': sendOrderTimeText,
  };

  factory ClientDispatchItem.fromJson(Map<String, dynamic> json) =>
      ClientDispatchItem(
        orderId: _asInt(json['order_id']),
        hospitalId: _asInt(json['hospital_id']),
        hospitalName: cleanQueryText(json['hospital_name']),
        sendOrderTimeText: cleanQueryText(json['send_order_time_text']),
      );
}

/// 档案情况（`/v1/archives/list`）
class ClientArchiveItem {
  final int archivesId;
  final String name;
  final String genderText;
  final String goTime;
  final String identity;
  final String birthTime;
  final String nationalityText;

  const ClientArchiveItem({
    this.archivesId = 0,
    this.name = '',
    this.genderText = '',
    this.goTime = '',
    this.identity = '',
    this.birthTime = '',
    this.nationalityText = '',
  });

  /// 解析 `/v1/archives/list` 的 data.list_data 单项
  factory ClientArchiveItem.fromApi(Map<String, dynamic> json) =>
      ClientArchiveItem(
        archivesId: _asInt(json['archives_id']),
        name: cleanQueryText(json['archives_name']),
        genderText: cleanQueryText(json['gender_str']),
        goTime: cleanQueryText(json['go_time']),
        identity: _archiveIdentityLabel(json['identity']),
        birthTime: cleanQueryText(json['birth_time']),
        nationalityText: cleanQueryText(json['nationality_str']),
      );

  Map<String, dynamic> toJson() => {
    'archives_id': archivesId,
    'name': name,
    'gender_text': genderText,
    'go_time': goTime,
    'identity': identity,
    'birth_time': birthTime,
    'nationality_text': nationalityText,
  };

  factory ClientArchiveItem.fromJson(Map<String, dynamic> json) =>
      ClientArchiveItem(
        archivesId: _asInt(json['archives_id']),
        name: cleanQueryText(json['name']),
        genderText: cleanQueryText(json['gender_text']),
        goTime: cleanQueryText(json['go_time']),
        // 旧缓存里可能存的还是 code，读回时再映射一次（对已是文案的值幂等）
        identity: _archiveIdentityLabel(json['identity']),
        birthTime: cleanQueryText(json['birth_time']),
        nationalityText: cleanQueryText(json['nationality_text']),
      );
}

/// 档案身份：后端下发 code，口径与建档表单（`customer_archive_form_page` 的
/// 身份选项）及客服系统 `ArchiveTab` 一致；未知 code 原样展示。
String _archiveIdentityLabel(dynamic raw) {
  final code = cleanQueryText(raw);
  switch (code) {
    case '1':
      return '爱美身份';
    case '2':
      return '医院身份';
    case '3':
      return '翻译身份';
    case '4':
      return '电话卡身份';
    default:
      return code;
  }
}

/// 预约情况（`/v1/appoint/list?client_id=`）
class ClientAppointmentItem {
  final int appointId;
  final int status;
  final String statusText;
  final int hospitalId;
  final String hospitalName;
  final String appointTimeText;

  /// 客服确认到院：0=未确认
  final int arriveStatus;

  const ClientAppointmentItem({
    this.appointId = 0,
    this.status = 0,
    this.statusText = '',
    this.hospitalId = 0,
    this.hospitalName = '',
    this.appointTimeText = '',
    this.arriveStatus = 0,
  });

  /// 解析 `/v1/appoint/list` 的 data.list 单项。
  /// `appoint_time` 只到日期时补 `appoint_hour`（后端分两个字段下发）。
  factory ClientAppointmentItem.fromApi(Map<String, dynamic> json) {
    final time = cleanQueryText(json['appoint_time']);
    final hour = cleanQueryText(json['appoint_hour']);
    return ClientAppointmentItem(
      appointId: _asInt(json['appoint_id']),
      status: _asInt(json['status']),
      statusText: cleanQueryText(json['status_cn']),
      hospitalId: _asInt(json['hospital_id']),
      hospitalName: cleanQueryText(json['hospital_name']),
      appointTimeText: hour.isNotEmpty && !time.contains(':')
          ? '$time $hour'.trim()
          : time,
      arriveStatus: _asInt(json['arrive_status']),
    );
  }

  String get arriveText => arriveStatus > 0 ? '已确认' : '未确认';

  Map<String, dynamic> toJson() => {
    'appoint_id': appointId,
    'status': status,
    'status_text': statusText,
    'hospital_id': hospitalId,
    'hospital_name': hospitalName,
    'appoint_time_text': appointTimeText,
    'arrive_status': arriveStatus,
  };

  factory ClientAppointmentItem.fromJson(Map<String, dynamic> json) =>
      ClientAppointmentItem(
        appointId: _asInt(json['appoint_id']),
        status: _asInt(json['status']),
        statusText: cleanQueryText(json['status_text']),
        hospitalId: _asInt(json['hospital_id']),
        hospitalName: cleanQueryText(json['hospital_name']),
        appointTimeText: cleanQueryText(json['appoint_time_text']),
        arriveStatus: _asInt(json['arrive_status']),
      );
}

/// 成交（消费）情况——`/v1/schedule/paylist?client_id=&archives_id=0`
///
/// 客服系统详情页的「消费」Tab 用的是同一接口同一口径（kf_service
/// `fetchPayList`），这里只取展示需要的字段。金额单位韩元。
class ClientDealItem {
  final int id;
  final String hospitalName;
  final String operationTime;
  final String clientName;
  final double amount;
  final double receivedAmount;

  /// 手术项目名（paylist 的 `item`）
  final String projectName;

  /// 备注（paylist 的 `addnote`，已由 [PayListItem.remark] 解析）
  final String remark;

  const ClientDealItem({
    this.id = 0,
    this.hospitalName = '',
    this.operationTime = '',
    this.clientName = '',
    this.amount = 0,
    this.receivedAmount = 0,
    this.projectName = '',
    this.remark = '',
  });

  factory ClientDealItem.fromPayListItem(PayListItem p) => ClientDealItem(
    id: p.id,
    hospitalName: cleanQueryText(p.hospitalName),
    operationTime: cleanQueryText(p.operationTime),
    clientName: cleanQueryText(p.clientName),
    amount: p.operationAmount,
    receivedAmount: p.actualAmount,
    projectName: cleanQueryText(p.operationProjectName),
    remark: cleanQueryText(p.remark),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'hospital_name': hospitalName,
    'operation_time': operationTime,
    'client_name': clientName,
    'amount': amount,
    'received_amount': receivedAmount,
    'project_name': projectName,
    'remark': remark,
  };

  factory ClientDealItem.fromJson(Map<String, dynamic> json) => ClientDealItem(
    id: _asInt(json['id']),
    hospitalName: cleanQueryText(json['hospital_name']),
    operationTime: cleanQueryText(json['operation_time']),
    clientName: cleanQueryText(json['client_name']),
    amount: _asDouble(json['amount']),
    receivedAmount: _asDouble(json['received_amount']),
    projectName: cleanQueryText(json['project_name']),
    remark: cleanQueryText(json['remark']),
  );
}

/// 客户资料弹窗的聚合结果（多个客服接口拼装）
class ClientProfile {
  final int clientId;
  final ClientBasicInfo? basic;
  final List<ClientDispatchItem> dispatches;
  final List<ClientArchiveItem> archives;
  final List<ClientAppointmentItem> appointments;
  final List<ClientDealItem> deals;

  const ClientProfile({
    required this.clientId,
    this.basic,
    this.dispatches = const [],
    this.archives = const [],
    this.appointments = const [],
    this.deals = const [],
  });

  bool get isEmpty =>
      basic == null &&
      dispatches.isEmpty &&
      archives.isEmpty &&
      appointments.isEmpty &&
      deals.isEmpty;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'basic': basic?.toJson(),
    'dispatches': dispatches.map((e) => e.toJson()).toList(),
    'archives': archives.map((e) => e.toJson()).toList(),
    'appointments': appointments.map((e) => e.toJson()).toList(),
    'deals': deals.map((e) => e.toJson()).toList(),
  };

  factory ClientProfile.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) build) =>
        (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => build(Map<String, dynamic>.from(e)))
            .toList();

    return ClientProfile(
      clientId: _asInt(json['client_id']),
      basic: json['basic'] is Map
          ? ClientBasicInfo.fromJson(Map<String, dynamic>.from(json['basic']))
          : null,
      dispatches: parseList(json['dispatches'], ClientDispatchItem.fromJson),
      archives: parseList(json['archives'], ClientArchiveItem.fromJson),
      appointments: parseList(
        json['appointments'],
        ClientAppointmentItem.fromJson,
      ),
      deals: parseList(json['deals'], ClientDealItem.fromJson),
    );
  }
}

/// 秒级时间戳 → `Y-m-d H:i`（与客户列表页 registerTimeStr 口径一致）
String _formatUnix(dynamic raw) {
  final ts = _asInt(raw);
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
