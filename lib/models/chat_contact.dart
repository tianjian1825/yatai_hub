/// 通讯录联系人（`GET /v1/parttime_task/contacts` 的一行）
///
/// 后端只列**兼职人员**（roleid 固定 275），且仅 `roleid ≠ 275` 的账号可访问该接口
/// ——兼职之间不能互相发起私聊。
///
/// [convId] 是与当前登录人已存在的私聊会话 ID：
/// - `0`  尚未建过会话，点进去要先打 `chat/private/open`（get-or-create）
/// - `>0` 已有会话，直接当 `task_id` + `conv_type=3` 进 ChatPage，跳过 open
class ChatContact {
  final int userId;

  /// 姓名（后端已做 realname → username 回退）
  final String username;

  /// 头像（后端已补全 URL + 缩放参数，可能为空串 → UI 回退首字头像）
  final String avatar;

  /// 固定 275（兼职）
  final int roleid;

  /// 手机号，可能为空串（未登记）→ 列表不显示拨号按钮
  final String mobile;

  /// 已存在的私聊会话 ID；0=尚未建过
  final int convId;

  const ChatContact({
    required this.userId,
    this.username = '',
    this.avatar = '',
    this.roleid = 0,
    this.mobile = '',
    this.convId = 0,
  });

  /// 是否已有会话（点击时不再打 private/open，直接进会话）
  bool get hasConversation => convId > 0;

  /// 是否可拨号
  bool get hasMobile => mobile.trim().isNotEmpty;

  ChatContact copyWith({int? convId}) => ChatContact(
    userId: userId,
    username: username,
    avatar: avatar,
    roleid: roleid,
    mobile: mobile,
    convId: convId ?? this.convId,
  );

  factory ChatContact.fromJson(Map<String, dynamic> json) => ChatContact(
    userId: _asInt(json['user_id']),
    username: json['username']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    roleid: _asInt(json['roleid']),
    mobile: json['mobile']?.toString() ?? '',
    convId: _asInt(json['conv_id']),
  );

  /// 转 sqlite 行（[sortIndex] 保留接口返回顺序，本地读取时按它排）
  Map<String, Object?> toDbMap({int sortIndex = 0}) => {
    'user_id': userId,
    'username': username,
    'avatar': avatar,
    'roleid': roleid,
    'mobile': mobile,
    'conv_id': convId,
    'sort_index': sortIndex,
  };

  factory ChatContact.fromDbMap(Map<String, Object?> row) => ChatContact(
    userId: _asInt(row['user_id']),
    username: row['username']?.toString() ?? '',
    avatar: row['avatar']?.toString() ?? '',
    roleid: _asInt(row['roleid']),
    mobile: row['mobile']?.toString() ?? '',
    convId: _asInt(row['conv_id']),
  );
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
