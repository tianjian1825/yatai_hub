import 'dart:convert';

import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/utils/media_saver.dart';

/// 兼职任务「群聊会话」相关模型
///
/// 接口契约见 PARTTIME_CHAT_API.md（/v1/parttime_task/chat/*）。
/// 旧留言板（PartTimeComment，主楼/回复树）已下线，本文件为群聊扁平消息流模型。

/// 消息里的一张图 / 一个视频（原件 + 缩略图）
///
/// NAS 缩略图/截帧的文件名是独立时间戳，**无法由原图 URL 推导**（OSS 那套
/// `?x-oss-process=` 参数对 NAS 静态服务无效），所以必须随消息一起下发。
///
/// 后端 `media` 与 `images` 同序等长：`images` 是纯 URL 数组（旧版 App 与客服
/// 后台留言板模板都按 string[] 读，形状不能变），`media` 额外带 thumb。
/// 老消息 / 后台发的图没有缩略图，此时 [thumb] 为空，取 [displayUrl] 自动回退原件。
class ChatMedia {
  /// 原图 / 原视频 URL（预览、保存到相册都用它）
  final String url;

  /// 缩略图 URL：图片为 200×200 缩略图，视频为第 1 秒截帧；可能为空
  final String thumb;

  final bool isVideo;

  const ChatMedia({required this.url, this.thumb = '', this.isVideo = false});

  /// 列表格子里该加载的地址：有缩略图用缩略图，否则回退原件
  String get displayUrl => thumb.isNotEmpty ? thumb : url;

  /// 只有原图 URL 时的兜底构造（旧后端不返回 media / 老消息）
  factory ChatMedia.fromUrl(String url) =>
      ChatMedia(url: url, isVideo: MediaSaver.isVideo(url));

  factory ChatMedia.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    final type = json['type']?.toString() ?? '';
    return ChatMedia(
      url: url,
      thumb: json['thumb']?.toString() ?? '',
      // type 缺失时按扩展名兜底判断（与后端 _guess_media_type 同口径）
      isVideo: type.isNotEmpty ? type == 'video' : MediaSaver.isVideo(url),
    );
  }

  Map<String, Object?> toMap() => {
    'url': url,
    'thumb': thumb,
    'type': isVideo ? 'video' : 'image',
  };

  /// 由 media（可能缺失/为空）+ images 得到最终列表
  ///
  /// 两个方向都要能降级：新 App 连旧后端（无 media 字段）、以及历史消息
  /// （media 列为空）都靠 images 兜底；长度不一致时同样以 images 为准，
  /// 避免两个字段错位导致点开预览串图。
  static List<ChatMedia> resolve(dynamic rawMedia, List<String> images) {
    if (rawMedia is List) {
      final parsed = rawMedia
          .whereType<Map>()
          .map((e) => ChatMedia.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.url.isNotEmpty)
          .toList();
      if (parsed.length == images.length) return parsed;
    }
    return images.map(ChatMedia.fromUrl).toList();
  }
}

/// 单条群聊消息
class ChatMessage {
  final int messageId;
  final int taskId;

  /// 1=普通消息；2=系统灰条（拉人/移除/退群等，user_id=0，居中灰字展示）
  final int msgType;

  /// 是否已撤回；为 true 时 content/images/quote 已清空，按「X 撤回了一条消息」灰条展示
  final bool recalled;

  final String content;

  /// 原件 URL 列表（预览 / 保存到相册用）；与 [media] 同序等长
  final List<String> images;

  /// 富媒体列表（原件 + 缩略图）；列表格子渲染走它的 displayUrl
  final List<ChatMedia> media;

  final int userId;
  final String username;
  final int roleid;

  /// 发送人头像（后端已拼成完整可访问 URL，客户端无需再拼）；系统消息为空串
  final String avatar;

  /// 发送时间戳（Unix 秒）
  final int createdAt;

  /// 被引用消息 ID；0=未引用
  final int quoteMessageId;

  /// 被引用消息快照；引用消息不存在/被撤回时为 null
  final ChatMessageQuote? quote;

  /// 是否 @所有人
  final bool mentionAll;

  /// 被 @的成员 userid 列表
  final List<int> mentionUserIds;

  // —— 本地态（不来自后端，不入库）——
  /// 乐观发送中（尚未拿到服务端 message_id）
  final bool pending;

  /// 发送失败（可重发）
  final bool failed;

  /// 客户端消息 ID（幂等去重 + 乐观占位本地 key）
  final String? clientMsgId;

  /// [media] 省略时按 [images] 兜底合成（thumb 空、回退原件），
  /// 保证任何构造路径都不会出现「有图但 media 为空」导致格子不渲染。
  ChatMessage({
    required this.messageId,
    required this.taskId,
    this.msgType = 1,
    this.recalled = false,
    this.content = '',
    this.images = const [],
    List<ChatMedia>? media,
    this.userId = 0,
    this.username = '',
    this.roleid = 0,
    this.avatar = '',
    this.createdAt = 0,
    this.quoteMessageId = 0,
    this.quote,
    this.mentionAll = false,
    this.mentionUserIds = const [],
    this.pending = false,
    this.failed = false,
    this.clientMsgId,
  }) : media = media ?? images.map(ChatMedia.fromUrl).toList();

  /// 系统灰条（含撤回）—— 不显示气泡，居中灰字
  bool get isSystem => msgType == 2 || recalled;

  /// 会话列表里「最后一条消息」的预览文案。
  ///
  /// 群聊页收发消息后要就地更新本地会话摘要（返回列表不闪动），本地算出的文案
  /// 必须和后端 `_conv_preview` / `_message_summary` **逐字一致**，否则网络刷新
  /// 回来值不同，那一行的文字还是会跳一下。后端规则（parttime_task.php:3382 /
  /// :2621）：撤回 → `[消息已撤回]`；系统消息 → 原文；无文字无图 → 空串；
  /// 否则连续空白压成单空格并 trim，超 80 字截断加 `...`，有附件按类型追加
  /// `[N张图片]` / `[N个视频]`（都有则图片在前、空格分隔），仍为空则 `[新消息]`。
  ///
  /// 80 的口径是 PHP `mb_strlen`（按 code point），所以这里用 runes 而不是
  /// `String.length`（UTF-16 code unit，emoji 会算成 2）。
  String get conversationPreview {
    if (recalled) return '[消息已撤回]';
    if (msgType == 2) return content;
    if (content.isEmpty && images.isEmpty) return '';
    var text = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final runes = text.runes.toList();
    if (runes.length > 80) {
      text = '${String.fromCharCodes(runes.take(80))}...';
    }
    if (images.isNotEmpty) {
      // 图片与视频分别计数：视频也存在 images 里，一律说成「张图片」是错的。
      // 与后端 _count_media_kinds 同构——总量以 images 为准（media 可能缺失或
      // 错位），类型优先取 media[i]，对不齐时按 URL 后缀猜。
      final aligned = media.length == images.length;
      final videoCount = aligned
          ? media.where((m) => m.isVideo).length
          : images.where(MediaSaver.isVideo).length;
      final imageCount = images.length - videoCount;
      final suffix = [
        if (imageCount > 0) '[$imageCount张图片]',
        if (videoCount > 0) '[$videoCount个视频]',
      ].join(' ');
      if (suffix.isNotEmpty) {
        text = text.isNotEmpty ? '$text $suffix' : suffix;
      }
    }
    return text.isNotEmpty ? text : '[新消息]';
  }

  bool isMine(int? currentUserId) =>
      currentUserId != null && currentUserId > 0 && userId == currentUserId;

  /// 是否本人可撤回（本人 + 普通消息 + 未撤回 + 2 分钟内）
  bool canRecall(int? currentUserId, int nowSeconds) =>
      isMine(currentUserId) &&
      msgType == 1 &&
      !recalled &&
      !pending &&
      (nowSeconds - createdAt) < 120;

  ChatMessage copyWith({
    int? messageId,
    int? msgType,
    bool? recalled,
    String? content,
    List<String>? images,
    List<ChatMedia>? media,
    int? createdAt,
    int? quoteMessageId,
    ChatMessageQuote? quote,
    bool clearQuote = false,
    bool? mentionAll,
    List<int>? mentionUserIds,
    bool? pending,
    bool? failed,
    String? clientMsgId,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      taskId: taskId,
      msgType: msgType ?? this.msgType,
      recalled: recalled ?? this.recalled,
      content: content ?? this.content,
      images: images ?? this.images,
      // 只改 images 不给 media 时（如撤回清空）交给构造函数按新 images 重算，
      // 避免两个列表错位
      media: media ?? (images == null ? this.media : null),
      userId: userId,
      username: username,
      roleid: roleid,
      avatar: avatar,
      createdAt: createdAt ?? this.createdAt,
      quoteMessageId: quoteMessageId ?? this.quoteMessageId,
      quote: clearQuote ? null : (quote ?? this.quote),
      mentionAll: mentionAll ?? this.mentionAll,
      mentionUserIds: mentionUserIds ?? this.mentionUserIds,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      clientMsgId: clientMsgId ?? this.clientMsgId,
    );
  }

  /// 发送确认：用服务端返回的 message_id/created_at 替换乐观占位
  ChatMessage confirmed(int newMessageId, int newCreatedAt) => copyWith(
    messageId: newMessageId,
    createdAt: newCreatedAt > 0 ? newCreatedAt : createdAt,
    pending: false,
    failed: false,
  );

  ChatMessage markFailed() => copyWith(pending: false, failed: true);

  /// 撤回：清空内容/图片/引用
  ChatMessage markRecalled() =>
      copyWith(recalled: true, content: '', images: const [], clearQuote: true);

  /// 乐观发送占位（messageId=0，pending）
  factory ChatMessage.optimistic({
    required int taskId,
    required int userId,
    required String username,
    required int roleid,
    required String avatar,
    required int createdAt,
    required String clientMsgId,
    String content = '',
    List<String> images = const [],
    List<ChatMedia>? media,
    int quoteMessageId = 0,
    ChatMessageQuote? quote,
    bool mentionAll = false,
    List<int> mentionUserIds = const [],
  }) {
    return ChatMessage(
      messageId: 0,
      taskId: taskId,
      msgType: 1,
      content: content,
      images: images,
      media: media,
      userId: userId,
      username: username,
      roleid: roleid,
      avatar: avatar,
      createdAt: createdAt,
      quoteMessageId: quoteMessageId,
      quote: quote,
      mentionAll: mentionAll,
      mentionUserIds: mentionUserIds,
      pending: true,
      clientMsgId: clientMsgId,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final images = (rawImages is List ? rawImages : const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final rawMentions = json['mention_user_ids'];
    final mentions = (rawMentions is List ? rawMentions : const [])
        .map(_asInt)
        .where((e) => e > 0)
        .toList();
    final rawQuote = json['quote'];
    return ChatMessage(
      messageId: _asInt(json['message_id']),
      taskId: _asInt(json['task_id']),
      msgType: json['msg_type'] == null ? 1 : _asInt(json['msg_type']),
      recalled: _asBool(json['recalled']),
      content: json['content']?.toString() ?? '',
      images: images,
      // 旧后端不返回 media 字段 → resolve 内部按 images 兜底
      media: ChatMedia.resolve(json['media'], images),
      userId: _asInt(json['user_id']),
      username: json['username']?.toString() ?? '',
      roleid: _asInt(json['roleid']),
      avatar: json['avatar']?.toString() ?? '',
      createdAt: _asInt(json['created_at']),
      quoteMessageId: _asInt(json['quote_message_id']),
      quote: rawQuote is Map
          ? ChatMessageQuote.fromJson(Map<String, dynamic>.from(rawQuote))
          : null,
      mentionAll: _asBool(json['mention_all']),
      mentionUserIds: mentions,
    );
  }

  /// 转 sqlite 行（仅持久化已确认消息；本地态 pending/failed/clientMsgId 不入库）
  Map<String, Object?> toDbMap() => {
    'task_id': taskId,
    'message_id': messageId,
    'msg_type': msgType,
    'recalled': recalled ? 1 : 0,
    'content': content,
    'images': jsonEncode(images),
    'media': jsonEncode(media.map((e) => e.toMap()).toList()),
    'user_id': userId,
    'username': username,
    'roleid': roleid,
    'avatar': avatar,
    'created_at': createdAt,
    'quote_message_id': quoteMessageId,
    'quote': quote == null ? null : jsonEncode(quote!.toMap()),
    'mention_all': mentionAll ? 1 : 0,
    'mention_user_ids': jsonEncode(mentionUserIds),
  };

  factory ChatMessage.fromDbMap(Map<String, Object?> row) {
    final rawImages = _decodeJson(row['images']);
    final images = (rawImages is List ? rawImages : const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final rawMentions = _decodeJson(row['mention_user_ids']);
    final mentions = (rawMentions is List ? rawMentions : const [])
        .map(_asInt)
        .where((e) => e > 0)
        .toList();
    final rawQuote = _decodeJson(row['quote']);
    return ChatMessage(
      messageId: _asInt(row['message_id']),
      taskId: _asInt(row['task_id']),
      msgType: row['msg_type'] == null ? 1 : _asInt(row['msg_type']),
      recalled: _asBool(row['recalled']),
      content: row['content']?.toString() ?? '',
      images: images,
      // v6 之前入库的行没有 media 列值 → resolve 内部按 images 兜底
      media: ChatMedia.resolve(_decodeJson(row['media']), images),
      userId: _asInt(row['user_id']),
      username: row['username']?.toString() ?? '',
      roleid: _asInt(row['roleid']),
      avatar: row['avatar']?.toString() ?? '',
      createdAt: _asInt(row['created_at']),
      quoteMessageId: _asInt(row['quote_message_id']),
      quote: rawQuote is Map
          ? ChatMessageQuote.fromJson(Map<String, dynamic>.from(rawQuote))
          : null,
      mentionAll: _asBool(row['mention_all']),
      mentionUserIds: mentions,
    );
  }
}

/// 被引用消息快照
class ChatMessageQuote {
  final int messageId;
  final int userId;
  final String username;
  final String content; // 截断 50 字
  final String image; // 首图原件，可能空

  /// 首图缩略图，可能空（老消息 / 旧后端不返回）；渲染取 [thumbOrImage]
  final String imageThumb;

  /// 首个附件类型（后端 `image_type`：`image` / `video`）。
  /// 旧后端与老本地缓存没有这个字段，为空串时由 [isVideo] 按 URL 后缀兜底。
  final String imageType;

  const ChatMessageQuote({
    required this.messageId,
    required this.userId,
    required this.username,
    required this.content,
    required this.image,
    this.imageThumb = '',
    this.imageType = '',
  });

  /// 引用条里该加载的地址：有缩略图用缩略图，否则回退原件
  String get thumbOrImage => imageThumb.isNotEmpty ? imageThumb : image;

  /// 被引用的附件是不是视频（引用条要显示「[视频]」而不是「[图片]」）。
  ///
  /// 不能拿 [thumbOrImage] 判断：视频的缩略图是截帧 jpg，会被当成图片。
  bool get isVideo =>
      imageType.isEmpty ? MediaSaver.isVideo(image) : imageType == 'video';

  factory ChatMessageQuote.fromJson(Map<String, dynamic> json) =>
      ChatMessageQuote(
        messageId: _asInt(json['message_id']),
        userId: _asInt(json['user_id']),
        username: json['username']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
        imageThumb: json['image_thumb']?.toString() ?? '',
        imageType: json['image_type']?.toString() ?? '',
      );

  Map<String, Object?> toMap() => {
    'message_id': messageId,
    'user_id': userId,
    'username': username,
    'content': content,
    'image': image,
    'image_thumb': imageThumb,
    'image_type': imageType,
  };
}

/// 群成员
class ChatMember {
  final int userId;
  final String username;

  /// 头像 URL，可能为空（空时 UI 回退首字文字头像）
  final String avatar;
  final int roleid;

  /// 1=发起人/群主，2=普通成员
  final int memberRole;

  /// 1=自动入群（三方），2=被邀请
  final int source;
  final int joinedAt;

  const ChatMember({
    required this.userId,
    required this.username,
    this.avatar = '',
    required this.roleid,
    required this.memberRole,
    required this.source,
    required this.joinedAt,
  });

  bool get isOwner => memberRole == 1;

  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
    userId: _asInt(json['user_id']),
    username: json['username']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    roleid: _asInt(json['roleid']),
    memberRole: json['member_role'] == null ? 2 : _asInt(json['member_role']),
    source: _asInt(json['source']),
    joinedAt: _asInt(json['joined_at']),
  );
}

/// 选人：在职员工
class StaffSearchItem {
  final int userId;
  final String username;
  final int roleid;

  const StaffSearchItem({
    required this.userId,
    required this.username,
    required this.roleid,
  });

  factory StaffSearchItem.fromJson(Map<String, dynamic> json) =>
      StaffSearchItem(
        userId: _asInt(json['user_id']),
        username: json['username']?.toString() ?? '',
        roleid: _asInt(json['roleid']),
      );
}

/// 最近会话（IM 首页一行）
///
/// conversations 接口返回任务群 + 科室群 + 私聊**混排**，靠 [convType] 区分；
/// 进入会话后所有接口都要带上它（`task_id` 在科室群里是科室 ID，私聊里是会话 ID）。
class ChatConversation {
  /// 1=任务群 2=科室群 3=私聊（后端缺省视为任务群）
  final int convType;

  final int taskId;
  final int lastMessageId;
  // 预览（附件为 [N张图片] / [N个视频]，系统消息为其文本，撤回为 [消息已撤回]）
  final String lastMessage;
  final int lastMessageTime;
  final int unreadCount;
  final bool hasMention;
  final int memberCount;

  /// 群标题（任务/医院名）；私聊为对方姓名。后端未返回时本地补
  final String title;

  /// 私聊特有：对方 userid（群聊为 0）
  final int peerUserId;

  /// 私聊特有：对方头像 URL（群聊为空串，列表用方形图标）
  final String avatar;

  const ChatConversation({
    this.convType = 1,
    required this.taskId,
    required this.lastMessageId,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.hasMention,
    required this.memberCount,
    this.title = '',
    this.peerUserId = 0,
    this.avatar = '',
  });

  bool get isDepartment => convType == 2;
  bool get isPrivate => convType == 3;

  /// 会话定位键（进会话后所有接口都用它）
  ChatTarget get target => ChatTarget(convType: convType, taskId: taskId);

  ChatConversation copyWith({
    String? title,
    int? unreadCount,
    bool? hasMention,
    int? lastMessageId,
    String? lastMessage,
    int? lastMessageTime,
  }) => ChatConversation(
    convType: convType,
    taskId: taskId,
    lastMessageId: lastMessageId ?? this.lastMessageId,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    unreadCount: unreadCount ?? this.unreadCount,
    hasMention: hasMention ?? this.hasMention,
    memberCount: memberCount,
    title: title ?? this.title,
    peerUserId: peerUserId,
    avatar: avatar,
  );

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        convType: _convType(json['conv_type']),
        taskId: _asInt(json['task_id']),
        lastMessageId: _asInt(json['last_message_id']),
        lastMessage: json['last_message']?.toString() ?? '',
        lastMessageTime: _asInt(json['last_message_time']),
        unreadCount: _asInt(json['unread_count']),
        hasMention: _asBool(json['has_mention']),
        memberCount: _asInt(json['member_count']),
        // 群名称：后端 group_name（任务群=客户名·医院名·日期，科室群=科室名，
        // 私聊=对方姓名），跨角色可用
        title: (json['group_name'] ?? json['title'])?.toString() ?? '',
        peerUserId: _asInt(json['peer_user_id']),
        avatar: json['avatar']?.toString() ?? '',
      );

  Map<String, Object?> toDbMap() => {
    'conv_type': convType,
    'task_id': taskId,
    'last_message_id': lastMessageId,
    'last_message': lastMessage,
    'last_message_time': lastMessageTime,
    'unread_count': unreadCount,
    'has_mention': hasMention ? 1 : 0,
    'member_count': memberCount,
    'title': title,
    'peer_user_id': peerUserId,
    'avatar': avatar,
  };

  factory ChatConversation.fromDbMap(Map<String, Object?> row) =>
      ChatConversation(
        convType: _convType(row['conv_type']),
        taskId: _asInt(row['task_id']),
        lastMessageId: _asInt(row['last_message_id']),
        lastMessage: row['last_message']?.toString() ?? '',
        lastMessageTime: _asInt(row['last_message_time']),
        unreadCount: _asInt(row['unread_count']),
        hasMention: _asBool(row['has_mention']),
        memberCount: _asInt(row['member_count']),
        title: row['title']?.toString() ?? '',
        peerUserId: _asInt(row['peer_user_id']),
        avatar: row['avatar']?.toString() ?? '',
      );
}

/// 会话类型白名单：2=科室群 3=私聊，其余（含缺省/非法）一律按任务群
int _convType(Object? v) {
  final n = _asInt(v);
  return (n == 2 || n == 3) ? n : 1;
}

/// 消息列表结果（before_id / after_id / around_id 共用）
class ChatMessagesResult {
  /// 后端按时间正序（旧→新）
  final List<ChatMessage> list;

  /// 兼容字段：after_id 时=hasMoreNew，其余=hasMoreOld
  final bool hasMore;

  /// 比本屏最旧更早是否还有
  final bool hasMoreOld;

  /// 比本屏最新更新是否还有
  final bool hasMoreNew;

  /// 本屏最大消息 ID（增量续拉用作下次 after_id）
  final int newestId;

  /// 本屏最小消息 ID（翻历史用作下次 before_id）
  final int oldestId;

  /// 当前用户最后已读消息 ID（用于画新消息分隔线）
  final int lastReadId;

  /// 当前用户未读数
  final int unreadCount;

  /// 群名称（后端 group_name：客户名·医院名·日期；跨角色可用，作 AppBar 标题）
  final String groupName;

  /// 非空表示请求失败（msg 可直接展示）
  final String? errorMessage;

  const ChatMessagesResult({
    required this.list,
    this.hasMore = false,
    this.hasMoreOld = false,
    this.hasMoreNew = false,
    this.newestId = 0,
    this.oldestId = 0,
    this.lastReadId = 0,
    this.unreadCount = 0,
    this.groupName = '',
    this.errorMessage,
  });

  factory ChatMessagesResult.fromData(Map<String, dynamic> data) {
    final rawList = data['list'];
    final list = (rawList is List ? rawList : const [])
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return ChatMessagesResult(
      list: list,
      hasMore: _asBool(data['has_more']),
      hasMoreOld: _asBool(data['has_more_old']),
      hasMoreNew: _asBool(data['has_more_new']),
      newestId: _asInt(data['newest_id']),
      oldestId: _asInt(data['oldest_id']),
      lastReadId: _asInt(data['last_read_id']),
      unreadCount: _asInt(data['unread_count']),
      groupName: data['group_name']?.toString() ?? '',
    );
  }

  factory ChatMessagesResult.error(String message) =>
      ChatMessagesResult(list: const [], errorMessage: message);

  /// 仅本地数据构造（离线秒显用）
  factory ChatMessagesResult.local(
    List<ChatMessage> list, {
    bool hasMoreOld = false,
    int lastReadId = 0,
  }) {
    final newest = list.isEmpty ? 0 : list.last.messageId;
    final oldest = list.isEmpty ? 0 : list.first.messageId;
    return ChatMessagesResult(
      list: list,
      hasMore: hasMoreOld,
      hasMoreOld: hasMoreOld,
      hasMoreNew: false,
      newestId: newest,
      oldestId: oldest,
      lastReadId: lastReadId,
    );
  }
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
    return s == 'true' || s == '1';
  }
  return false;
}

dynamic _decodeJson(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
