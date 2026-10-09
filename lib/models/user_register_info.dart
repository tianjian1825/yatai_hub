/// 兼职用户个人资料（注册信息）
///
/// 由 /v1/user/register_info 接口返回，展示用户注册时提交的内容，
/// 以及打工证（韩国劳动许可证）相关状态。
class UserRegisterInfo {
  final int userid;

  /// 姓名（真实姓名）
  final String username;

  /// 昵称（库中 realname，可通过 /v1/user/profile 自助修改）
  final String realname;
  final String email;

  /// 中国电话
  final String mobile;

  /// 微信号
  final String wechat;

  /// 性别
  final String gender;

  /// 生日 YYYY-MM-DD
  final String birthday;

  /// 韩国地址
  final String krAddress;

  /// 韩语等级（TOPIK 1~6）；0 表示历史数据未填
  final int krLanguageLevel;

  /// 韩语等级展示文案，如 "TOPIK 6级"；未填时为空字符串
  final String krLanguageLevelLabel;

  /// 注册上传资料，每项 {name, url}
  final List<KrParttimeFile> krParttimeFiles;

  /// 审核状态：1=待审核/禁用，0=已通过
  final int disabled;

  /// 兼职审核状态：0=待审核 / 1=已通过 / 2=已驳回
  final int parttimeAuditStatus;

  /// 兼职审核状态中文：待审核 / 已通过 / 已驳回
  final String parttimeAuditStatusLabel;

  /// 驳回原因，仅 parttimeAuditStatus=2 有值，否则为空字符串
  final String parttimeRejectReason;

  /// 停用原因，仅「已通过(parttimeAuditStatus=1) + 已停用(disabled=1)」时有值，否则为空字符串
  final String parttimeDisableReason;

  /// 打工证图片 URL，未上传为空
  final String krWorkcard;

  /// 打工证有效期，未填或 0000-00-00 为空
  final String krWorkcardExpiry;

  /// 打工证是否有效
  final bool isValid;

  /// 打工证状态码：none / no_expiry / expired / expiring / valid
  final String workcardStatus;

  /// 打工证状态中文
  final String workcardStatusLabel;

  UserRegisterInfo({
    required this.userid,
    required this.username,
    required this.realname,
    required this.email,
    required this.mobile,
    required this.wechat,
    required this.gender,
    required this.birthday,
    required this.krAddress,
    required this.krLanguageLevel,
    required this.krLanguageLevelLabel,
    required this.krParttimeFiles,
    required this.disabled,
    required this.parttimeAuditStatus,
    required this.parttimeAuditStatusLabel,
    required this.parttimeRejectReason,
    required this.parttimeDisableReason,
    required this.krWorkcard,
    required this.krWorkcardExpiry,
    required this.isValid,
    required this.workcardStatus,
    required this.workcardStatusLabel,
  });

  factory UserRegisterInfo.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['kr_parttime_files'];
    final files = filesRaw is List
        ? filesRaw
              .whereType<Map>()
              .map((e) => KrParttimeFile.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <KrParttimeFile>[];
    // 向后兼容旧缓存：无 parttime_audit_status 字段时，由 disabled 推导
    // （disabled=0 视为已通过=1，否则视为待审核=0）
    final int auditStatus = json.containsKey('parttime_audit_status')
        ? _asInt(json['parttime_audit_status'])
        : (_asInt(json['disabled']) == 0 ? 1 : 0);
    return UserRegisterInfo(
      userid: _asInt(json['userid']),
      username: json['username']?.toString() ?? '',
      realname: json['realname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      wechat: json['wechat']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      birthday: json['birthday']?.toString() ?? '',
      krAddress: json['kr_address']?.toString() ?? '',
      krLanguageLevel: _asInt(json['kr_language_level']),
      krLanguageLevelLabel: json['kr_language_level_label']?.toString() ?? '',
      krParttimeFiles: files,
      disabled: _asInt(json['disabled']),
      parttimeAuditStatus: auditStatus,
      parttimeAuditStatusLabel:
          json['parttime_audit_status_label']?.toString() ?? '',
      parttimeRejectReason: json['parttime_reject_reason']?.toString() ?? '',
      parttimeDisableReason: json['parttime_disable_reason']?.toString() ?? '',
      krWorkcard: json['kr_workcard']?.toString() ?? '',
      krWorkcardExpiry: json['kr_workcard_expiry']?.toString() ?? '',
      isValid: _asBool(json['is_valid']),
      workcardStatus: json['workcard_status']?.toString() ?? '',
      workcardStatusLabel: json['workcard_status_label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'userid': userid,
    'username': username,
    'realname': realname,
    'email': email,
    'mobile': mobile,
    'wechat': wechat,
    'gender': gender,
    'birthday': birthday,
    'kr_address': krAddress,
    'kr_language_level': krLanguageLevel,
    'kr_language_level_label': krLanguageLevelLabel,
    'kr_parttime_files': krParttimeFiles.map((e) => e.toJson()).toList(),
    'disabled': disabled,
    'parttime_audit_status': parttimeAuditStatus,
    'parttime_audit_status_label': parttimeAuditStatusLabel,
    'parttime_reject_reason': parttimeRejectReason,
    'parttime_disable_reason': parttimeDisableReason,
    'kr_workcard': krWorkcard,
    'kr_workcard_expiry': krWorkcardExpiry,
    'is_valid': isValid,
    'workcard_status': workcardStatus,
    'workcard_status_label': workcardStatusLabel,
  };

  /// 是否已上传打工证（决定是否展示打工证相关区域）
  bool get hasWorkcard => krWorkcard.isNotEmpty && workcardStatus != 'none';

  /// 是否已通过审核（优先看兼职审核状态）
  bool get isApproved => parttimeAuditStatus == 1;

  /// 是否待审核
  bool get isPending => parttimeAuditStatus == 0;

  /// 是否已驳回
  bool get isRejected => parttimeAuditStatus == 2;

  /// 是否「已通过后被管理员停用」（parttimeAuditStatus=1 且 disabled=1）。
  /// 注意：disabled=1 不再唯一等于「待审核」，必须结合审核状态判断。
  bool get isDisabledAfterApproval => parttimeAuditStatus == 1 && disabled == 1;

  /// 是否可进入主 App（审核通过且未被停用）
  bool get canEnterMainApp => parttimeAuditStatus == 1 && disabled == 0;

  /// 审核状态展示文案（后端 label 优先，缺失时本地兜底）
  String get auditStatusText {
    if (parttimeAuditStatusLabel.isNotEmpty) return parttimeAuditStatusLabel;
    switch (parttimeAuditStatus) {
      case 1:
        return '已通过';
      case 2:
        return '已驳回';
      default:
        return '待审核';
    }
  }
}

/// 注册上传资料项
class KrParttimeFile {
  final String name;
  final String url;

  KrParttimeFile({required this.name, required this.url});

  factory KrParttimeFile.fromJson(Map<String, dynamic> json) => KrParttimeFile(
    name: json['name']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
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
