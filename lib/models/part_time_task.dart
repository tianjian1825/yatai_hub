/// 兼职任务相关模型
///
/// 接口契约见 /v1/parttime_task。
class PartTimeTask {
  final int id;
  final int scheduleType; // 2=术前 3=手术 4=术后
  final int scheduleDate; // Unix 秒
  final int appointTime; // Unix 秒

  /// 服务端格式化好的时间（Y-m-d H:i），已处理时区；空串=未设置。
  /// 展示优先用 *Text，排序/比较仍用上面的整数时间戳。
  final String scheduleDateText;
  final String appointTimeText;

  final int hospitalId;
  final String hospitalName;
  final double price;
  final double bonus;
  final String requireDesc;
  final int addTime;

  PartTimeTask({
    required this.id,
    required this.scheduleType,
    required this.scheduleDate,
    required this.appointTime,
    this.scheduleDateText = '',
    this.appointTimeText = '',
    required this.hospitalId,
    required this.hospitalName,
    required this.price,
    required this.bonus,
    required this.requireDesc,
    required this.addTime,
  });

  factory PartTimeTask.fromJson(Map<String, dynamic> json) => PartTimeTask(
    id: _asInt(json['id']),
    scheduleType: _asInt(json['schedule_type']),
    scheduleDate: _asInt(json['schedule_date']),
    appointTime: _asInt(json['appoint_time']),
    scheduleDateText: json['schedule_date_text']?.toString() ?? '',
    appointTimeText: json['appoint_time_text']?.toString() ?? '',
    hospitalId: _asInt(json['hospital_id']),
    hospitalName: json['hospital_name']?.toString() ?? '',
    price: _asDouble(json['price']),
    bonus: _asDouble(json['bonus']),
    requireDesc: json['require_desc']?.toString() ?? '',
    addTime: _asInt(json['add_time']),
  );
}

/// 任务详情
class PartTimeTaskDetail {
  final int id;
  final int scheduleId;
  final int archivesId;

  /// 关联客户 ID（后端可能以字符串 "0" 下发）；0=无关联客户
  final int clientId;

  final int hospitalId;
  final String hospitalName;

  /// 医院韩文名称（来源 un_kr_hospital_details.kr_companyname）
  final String hospitalKrName;

  /// 韩国地址（来源 un_kr_hospital_details.kr_address）
  final String hospitalKrAddress;

  final int appointId;
  final double price;
  final double bonus;
  final int scheduleType;
  final int scheduleDate;
  final int appointTime;

  /// 服务端格式化好的时间（Y-m-d H:i），已处理时区；空串=未设置。
  /// 展示优先用 *Text，排序/比较仍用上面的整数时间戳。
  final String scheduleDateText;
  final String appointTimeText;
  final String workStartTimeText;
  final String workEndTimeText;

  final int assignType; // 1=指定接单 2=开放抢单
  final int parttimeUserId;
  final int createUserId;
  final int status; // 1=待接单 2=已接单 3=进行中 4=已完成 5=已取消
  final String requireDesc;
  final String remark;
  final int addTime;
  final int acceptTime;
  final int finishTime;
  final int cancelTime;
  final String cancelReason;

  /// 审核状态：0=待审核 1=审核通过 2=审核驳回（仅任务已完成时有意义）
  final int auditStatus;

  /// 审核驳回理由（audit_status==2 时有值）
  final String auditRejectReason;

  /// 当前绑定的随心拍主表 ID，0 表示未上传
  final int casuallyId;

  /// 录单草稿列表（按 draft_id DESC）
  final List<PartTimeOrderDraft> orderDrafts;

  /// 有效录单草稿数量（status IN (1,2,4)）
  final int orderDraftCount;

  /// 是否已有有效录单草稿
  final bool hasOrderDraft;

  /// 是否已上传并绑定随心拍
  final bool hasMaterial;

  /// 是否允许完成任务（hasOrderDraft && hasMaterial）
  final bool canComplete;

  /// 关联日程信息（无关联时为 null）
  final PartTimeTaskSchedule? schedule;

  /// 关联预约信息（无关联时为 null）
  final PartTimeTaskAppoint? appoint;

  /// 当前任务绑定的随心拍详情（无则为 null）
  final PartTimeMaterialDetail? materialDetail;

  /// 档案成员列表（含本人，按 is_main 降序），录单选客户用；无档案时为空
  final List<PartTimeArchiveMember> archivesCompanions;

  /// 当前用户在该任务留言板下的未读留言数（含回复）；列表接口 my_tasks 返回
  final int unreadCommentCount;

  PartTimeTaskDetail({
    required this.id,
    required this.scheduleId,
    required this.archivesId,
    this.clientId = 0,
    required this.hospitalId,
    required this.hospitalName,
    this.hospitalKrName = '',
    this.hospitalKrAddress = '',
    required this.appointId,
    required this.price,
    required this.bonus,
    required this.scheduleType,
    required this.scheduleDate,
    required this.appointTime,
    this.scheduleDateText = '',
    this.appointTimeText = '',
    this.workStartTimeText = '',
    this.workEndTimeText = '',
    required this.assignType,
    required this.parttimeUserId,
    required this.createUserId,
    required this.status,
    required this.requireDesc,
    required this.remark,
    required this.addTime,
    required this.acceptTime,
    required this.finishTime,
    required this.cancelTime,
    required this.cancelReason,
    this.auditStatus = 0,
    this.auditRejectReason = '',
    this.casuallyId = 0,
    this.orderDrafts = const [],
    this.orderDraftCount = 0,
    this.hasOrderDraft = false,
    this.hasMaterial = false,
    this.canComplete = false,
    this.schedule,
    this.appoint,
    this.materialDetail,
    this.archivesCompanions = const [],
    this.unreadCommentCount = 0,
  });

  factory PartTimeTaskDetail.fromJson(Map<String, dynamic> json) {
    final rawDrafts = json['order_drafts'];
    final drafts = (rawDrafts is List ? rawDrafts : const [])
        .whereType<Map>()
        .map((e) => PartTimeOrderDraft.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rawMembers = json['archives_companions'];
    final members = (rawMembers is List ? rawMembers : const [])
        .whereType<Map>()
        .map(
          (e) => PartTimeArchiveMember.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
    return PartTimeTaskDetail(
      id: _asInt(json['id']),
      scheduleId: _asInt(json['schedule_id']),
      archivesId: _asInt(json['archives_id']),
      clientId: _asInt(json['client_id']),
      hospitalId: _asInt(json['hospital_id']),
      hospitalName: json['hospital_name']?.toString() ?? '',
      hospitalKrName: json['hospital_kr_name']?.toString() ?? '',
      hospitalKrAddress: json['hospital_kr_address']?.toString() ?? '',
      appointId: _asInt(json['appoint_id']),
      price: _asDouble(json['price']),
      bonus: _asDouble(json['bonus']),
      scheduleType: _asInt(json['schedule_type']),
      scheduleDate: _asInt(json['schedule_date']),
      appointTime: _asInt(json['appoint_time']),
      scheduleDateText: json['schedule_date_text']?.toString() ?? '',
      appointTimeText: json['appoint_time_text']?.toString() ?? '',
      workStartTimeText: json['work_start_time_text']?.toString() ?? '',
      workEndTimeText: json['work_end_time_text']?.toString() ?? '',
      assignType: _asInt(json['assign_type']),
      parttimeUserId: _asInt(json['parttime_userid']),
      createUserId: _asInt(json['create_userid']),
      status: _asInt(json['status']),
      requireDesc: json['require_desc']?.toString() ?? '',
      remark: json['remark']?.toString() ?? '',
      addTime: _asInt(json['add_time']),
      acceptTime: _asInt(json['accept_time']),
      finishTime: _asInt(json['finish_time']),
      cancelTime: _asInt(json['cancel_time']),
      cancelReason: json['cancel_reason']?.toString() ?? '',
      auditStatus: _asInt(json['audit_status']),
      auditRejectReason: json['audit_reject_reason']?.toString() ?? '',
      casuallyId: _asInt(json['casually_id']),
      orderDrafts: drafts,
      orderDraftCount: _asInt(json['order_draft_count']),
      hasOrderDraft: _asBool(json['has_order_draft']),
      hasMaterial: _asBool(json['has_material']),
      canComplete: _asBool(json['can_complete']),
      schedule: json['schedule'] is Map
          ? PartTimeTaskSchedule.fromJson(
              Map<String, dynamic>.from(json['schedule']),
            )
          : null,
      appoint: json['appoint'] is Map
          ? PartTimeTaskAppoint.fromJson(
              Map<String, dynamic>.from(json['appoint']),
            )
          : null,
      materialDetail: json['material_detail'] is Map
          ? PartTimeMaterialDetail.fromJson(
              Map<String, dynamic>.from(json['material_detail']),
            )
          : null,
      archivesCompanions: members,
      unreadCommentCount: _asInt(json['unread_comment_count']),
    );
  }

  /// 当前任务是否「待抢单」
  bool get isHallOpen => status == 1 && assignType == 2;

  /// 是否需要展示审核相关信息（仅任务已完成后才进入审核流程）
  bool get showAudit => status == PartTimeTaskStatus.completed;

  /// 是否审核驳回（已完成 + audit_status==2）
  bool get isAuditRejected =>
      showAudit && auditStatus == PartTimeAuditStatus.rejected;

  /// 是否本用户的接单
  bool isAcceptedByMe(int? currentUserId) {
    if (currentUserId == null) return false;
    return parttimeUserId == currentUserId && parttimeUserId > 0;
  }

  /// 是否本用户创建
  bool isCreatedByMe(int? currentUserId) {
    if (currentUserId == null) return false;
    return createUserId == currentUserId && createUserId > 0;
  }
}

/// 任务关联的日程信息
class PartTimeTaskSchedule {
  final int jobtype;
  final String jobtypeLabel;
  final int scheduleDate;
  final int appointTime;
  final String name; // 患者姓名
  final int status;
  final String require;
  final String hotelName;
  final String hotelAddress;
  final int archivesId;
  final int customId; // 日程客户 ID，来自 un_schedule.custom_id
  final int clientId; // 客户 ID，当前等同 custom_id
  final String clientIds; // 日程关联客户 ID 列表，逗号分隔

  PartTimeTaskSchedule({
    required this.jobtype,
    required this.jobtypeLabel,
    required this.scheduleDate,
    required this.appointTime,
    required this.name,
    required this.status,
    required this.require,
    required this.hotelName,
    required this.hotelAddress,
    this.archivesId = 0,
    this.customId = 0,
    this.clientId = 0,
    this.clientIds = '',
  });

  factory PartTimeTaskSchedule.fromJson(Map<String, dynamic> json) =>
      PartTimeTaskSchedule(
        jobtype: _asInt(json['jobtype']),
        jobtypeLabel: json['jobtype_label']?.toString() ?? '',
        scheduleDate: _asInt(json['schedule_date']),
        appointTime: _asInt(json['appoint_time']),
        name: json['name']?.toString() ?? '',
        status: _asInt(json['status']),
        require: json['require']?.toString() ?? '',
        hotelName: json['hotel_name']?.toString() ?? '',
        hotelAddress: json['hotel_address']?.toString() ?? '',
        archivesId: _asInt(json['archives_id']),
        customId: _asInt(json['custom_id']),
        clientId: _asInt(json['client_id']),
        clientIds: json['client_ids']?.toString() ?? '',
      );
}

/// 任务关联的预约信息
class PartTimeTaskAppoint {
  final int appointId;
  final int clientId;
  final String clientName;
  final int appointTime;
  final String passportNumber;
  final String projectId;
  final String birthTime;
  final String mobile;
  final int sex; // 1=男 2=女
  final List<PartTimeTaskCompanion> companions;

  PartTimeTaskAppoint({
    this.appointId = 0,
    this.clientId = 0,
    required this.clientName,
    required this.appointTime,
    required this.passportNumber,
    this.projectId = '',
    required this.birthTime,
    required this.mobile,
    required this.sex,
    required this.companions,
  });

  factory PartTimeTaskAppoint.fromJson(Map<String, dynamic> json) {
    final raw = json['companions'];
    final companions = (raw is List ? raw : const [])
        .whereType<Map>()
        .map(
          (e) => PartTimeTaskCompanion.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
    return PartTimeTaskAppoint(
      appointId: _asInt(json['appoint_id']),
      clientId: _asInt(json['client_id']),
      clientName: json['client_name']?.toString() ?? '',
      appointTime: _asInt(json['appoint_time']),
      passportNumber: json['passport_number']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      birthTime: json['birth_time']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      sex: _asInt(json['sex']),
      companions: companions,
    );
  }
}

/// 预约同行人
class PartTimeTaskCompanion {
  final int id; // 同行人 ID（guest_id）
  final String companionName;
  final String birthTime;
  final String passportNumber;
  final String projectId;
  final String mobile;
  final int sex;

  PartTimeTaskCompanion({
    this.id = 0,
    required this.companionName,
    required this.birthTime,
    required this.passportNumber,
    this.projectId = '',
    required this.mobile,
    required this.sex,
  });

  factory PartTimeTaskCompanion.fromJson(Map<String, dynamic> json) =>
      PartTimeTaskCompanion(
        id: _asInt(json['id']),
        companionName: json['companion_name']?.toString() ?? '',
        birthTime: json['birth_time']?.toString() ?? '',
        passportNumber: json['passport_number']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        mobile: json['mobile']?.toString() ?? '',
        sex: _asInt(json['sex']),
      );
}

/// 档案成员（含本人与同行人），任务详情 archives_companions 项
///
/// 录单草稿提交时使用 guest_id / client_id / archives_id。
class PartTimeArchiveMember {
  final int guestId; // 录单 order_draft 使用的同行人 ID
  final int archivesId;
  final int clientId;
  final String userName;
  final int relation; // 1本人 2配偶 3子女 4父子 5母子 6亲戚 7兄弟姐妹 8朋友 9其他
  final String relationStr;
  final int gender; // 1男 2女 0未知
  final String genderStr;
  final String birthTime; // YYYY-MM-DD
  final String passportNo;
  final String mobile;
  final bool isMain; // 是否主联系人（本人）

  PartTimeArchiveMember({
    required this.guestId,
    required this.archivesId,
    required this.clientId,
    required this.userName,
    required this.relation,
    required this.relationStr,
    required this.gender,
    required this.genderStr,
    required this.birthTime,
    required this.passportNo,
    required this.mobile,
    required this.isMain,
  });

  factory PartTimeArchiveMember.fromJson(Map<String, dynamic> json) =>
      PartTimeArchiveMember(
        guestId: _asInt(json['guest_id']),
        archivesId: _asInt(json['archives_id']),
        clientId: _asInt(json['client_id']),
        userName:
            (json['user_name'] ?? json['archives_name'])?.toString() ?? '',
        relation: _asInt(json['relation']),
        relationStr: json['relation_str']?.toString() ?? '',
        gender: _asInt(json['gender']),
        genderStr: json['gender_str']?.toString() ?? '',
        birthTime: json['birth_time']?.toString() ?? '',
        passportNo: json['passport_no']?.toString() ?? '',
        mobile: json['mobile']?.toString() ?? '',
        isMain: _asBool(json['is_main']),
      );
}

/// 兼职录单草稿
class PartTimeOrderDraft {
  final int draftId;
  final int taskId;
  final int status; // 1=待审核 2=审核通过 3=驳回 4=已写入正式录单
  final int paylistId; // 正式录单 ID；未写入时为 0
  final String rejectReason;
  final int clientId;
  final int archivesId;
  final int guestId;
  final int hospitalId;
  final double amount;
  final int currencyType;
  final String addTime;

  /// 完整录单草稿内容，用于编辑回显
  final Map<String, dynamic> draftPayload;

  PartTimeOrderDraft({
    required this.draftId,
    required this.taskId,
    required this.status,
    required this.paylistId,
    required this.rejectReason,
    required this.clientId,
    required this.archivesId,
    required this.guestId,
    required this.hospitalId,
    required this.amount,
    required this.currencyType,
    required this.addTime,
    required this.draftPayload,
  });

  /// 是否已写入正式录单（不可再编辑草稿）
  bool get isWritten => status == 4;

  /// 是否计入有效录单（status IN (1,2,4)）
  bool get isValid => status == 1 || status == 2 || status == 4;

  factory PartTimeOrderDraft.fromJson(Map<String, dynamic> json) =>
      PartTimeOrderDraft(
        draftId: _asInt(json['draft_id']),
        taskId: _asInt(json['task_id']),
        status: _asInt(json['status']),
        paylistId: _asInt(json['paylist_id']),
        rejectReason: json['reject_reason']?.toString() ?? '',
        clientId: _asInt(json['client_id']),
        archivesId: _asInt(json['archives_id']),
        guestId: _asInt(json['guest_id']),
        hospitalId: _asInt(json['hospital_id']),
        amount: _asDouble(json['amount']),
        currencyType: _asInt(json['currency_type']),
        addTime: json['add_time']?.toString() ?? '',
        draftPayload: json['draft_payload'] is Map
            ? Map<String, dynamic>.from(json['draft_payload'])
            : <String, dynamic>{},
      );
}

/// 兼职任务绑定的随心拍详情
class PartTimeMaterialDetail {
  final int taskId;
  final int casuallyId;
  final bool hasMaterial;
  final String text; // 素材描述
  final List<PartTimeMaterialFile> files; // 已上传文件列表（回显 + 编辑回传）

  PartTimeMaterialDetail({
    required this.taskId,
    required this.casuallyId,
    required this.hasMaterial,
    required this.text,
    required this.files,
  });

  /// 文件 URL 列表（兼容旧用法，如数量统计）
  List<String> get fileUrls =>
      files.map((f) => f.url).where((u) => u.isNotEmpty).toList();

  factory PartTimeMaterialDetail.fromJson(Map<String, dynamic> json) {
    final casually = json['casually'];
    final text = casually is Map ? (casually['text']?.toString() ?? '') : '';
    final rawList = json['casually_list'];
    final files = (rawList is List ? rawList : const [])
        .whereType<Map>()
        .map((e) => PartTimeMaterialFile.fromJson(Map<String, dynamic>.from(e)))
        .where((f) => f.url.isNotEmpty)
        .toList();
    return PartTimeMaterialDetail(
      taskId: _asInt(json['task_id']),
      casuallyId: _asInt(json['casually_id']),
      hasMaterial: _asBool(json['has_material']),
      text: text,
      files: files,
    );
  }
}

/// 随心拍已上传文件（来自 casually_list），用于回显与编辑回传
class PartTimeMaterialFile {
  final int id; // 文件记录 ID，编辑回传时携带以保留该文件
  final String originalName;
  final String fileName;
  final String filePath;
  final int size;
  final String url;
  final String storageType;
  final String thumbnail; // 缩略图相对路径
  final String fileClassification; // image / video

  PartTimeMaterialFile({
    required this.id,
    required this.originalName,
    required this.fileName,
    required this.filePath,
    required this.size,
    required this.url,
    required this.storageType,
    required this.thumbnail,
    required this.fileClassification,
  });

  bool get isVideo => fileClassification == 'video';

  factory PartTimeMaterialFile.fromJson(Map<String, dynamic> json) =>
      PartTimeMaterialFile(
        id: _asInt(json['id']),
        originalName: json['original_name']?.toString() ?? '',
        fileName: json['file_name']?.toString() ?? '',
        filePath: json['file_path']?.toString() ?? '',
        size: _asInt(json['size']),
        url: json['url']?.toString() ?? '',
        storageType: json['storage_type']?.toString() ?? 'nas',
        thumbnail: json['thumbnail']?.toString() ?? '',
        fileClassification: json['file_classification']?.toString() ?? '',
      );
}

String sexLabel(int sex) {
  switch (sex) {
    case 1:
      return '男';
    case 2:
      return '女';
    default:
      return '—';
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}

/// 状态枚举辅助
class PartTimeTaskStatus {
  static const int waiting = 1; // 待接单
  static const int accepted = 2; // 已接单
  // 状态 3（已到院）已下线：接单后直接进入录入/完成，不再有中间态。
  static const int completed = 4; // 已完成
  static const int canceled = 5; // 已取消

  static String label(int status) {
    switch (status) {
      case waiting:
        return '待接单';
      case accepted:
        return '已接单';
      case completed:
        return '已完成';
      case canceled:
        return '已取消';
      default:
        return '未知';
    }
  }
}

/// 兼职任务数据审核状态（任务已完成后进入审核流程）
class PartTimeAuditStatus {
  static const int pending = 0; // 待审核
  static const int approved = 1; // 审核通过
  static const int rejected = 2; // 审核驳回

  static String label(int status) {
    switch (status) {
      case approved:
        return '审核通过';
      case rejected:
        return '审核驳回';
      case pending:
      default:
        return '待审核';
    }
  }
}

class PartTimeScheduleType {
  static const int preOp = 2;
  static const int operation = 3;
  static const int postOp = 4;

  static String label(int type) {
    switch (type) {
      case preOp:
        return '术前';
      case operation:
        return '手术';
      case postOp:
        return '术后';
      default:
        return '其他';
    }
  }
}

/// 兼职大厅分页结果
class PartTimeTaskHallResult {
  final List<PartTimeTask> list;
  final int total;
  final int page;
  final int pageSize;

  /// 业务错误 / 网络错误信息；非空表示本次请求失败
  final String? errorMessage;

  PartTimeTaskHallResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    this.errorMessage,
  });
}

/// 我的任务分页结果（复用 PartTimeTaskDetail 作为列表项，字段更全）
class PartTimeMyTasksResult {
  final List<PartTimeTaskDetail> list;
  final int total;
  final int page;
  final int pageSize;

  /// 业务错误 / 网络错误信息；非空表示本次请求失败
  final String? errorMessage;

  PartTimeMyTasksResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    this.errorMessage,
  });
}
