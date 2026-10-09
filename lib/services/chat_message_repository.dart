import 'package:yatai_hub/models/chat_contact.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/chat_local_db.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';

/// 群聊「先本地后网络」编排层
///
/// ChatPage / 会话列表只依赖本类，不直接碰网络 service 或 sqlite。
/// - 进页面：先 [localRecent] 秒显，再 [fetchInitial] 网络对齐并写库。
/// - 上拉历史：[loadOlder] 本地优先，本地不足一屏再打网。
/// - 增量拉新：[fetchNew]（after_id）写库。
/// - 引用定位：[locateMessage]（本地 around 优先，缺失走网络 around_id）。
/// - 通讯录：[localContacts] 秒显 + [fetchContacts] 网络对齐（私聊入口）。
///
/// 消息类方法都以 [ChatTarget]（conv_type + task_id）定位会话——任务群 / 科室群 /
/// 私聊的 ID 会撞号，不能只用 taskId。
class ChatMessageRepository {
  static final ChatMessageRepository _instance =
      ChatMessageRepository._internal();
  factory ChatMessageRepository() => _instance;
  ChatMessageRepository._internal();

  final ParttimeChatService _service = ParttimeChatService();
  final ChatLocalDb _db = ChatLocalDb();

  // ——————————————————— 消息 ———————————————————

  /// 本地最近 N 条（秒显）
  Future<List<ChatMessage>> localRecent(ChatTarget target, {int limit = 30}) =>
      _db.recentMessages(target, limit: limit);

  Future<({int oldestSyncedId, bool hasMoreOld, int lastReadId})?>
  localSyncMeta(ChatTarget target) => _db.getSyncMeta(target);

  /// 首屏网络对齐（before_id=0，推进已读），写库 + 更新同步游标。
  Future<ChatMessagesResult> fetchInitial(
    ChatTarget target, {
    int limit = 20,
  }) async {
    final r = await _service.getMessages(
      target: target,
      beforeId: 0,
      limit: limit,
    );
    if (r.errorMessage == null) {
      await _db.upsertMessages(target, r.list);
      await _db.setSyncMeta(
        target,
        oldestSyncedId: r.oldestId,
        hasMoreOld: r.hasMoreOld,
        lastReadId: r.lastReadId,
      );
    }
    return r;
  }

  /// 上拉历史：本地有一整屏更早消息则直接用（离线流畅）；否则网络拉。
  Future<ChatMessagesResult> loadOlder(
    ChatTarget target,
    int beforeId, {
    int limit = 20,
  }) async {
    final local = await _db.messagesOlderThan(target, beforeId, limit: limit);
    if (local.length >= limit) {
      return ChatMessagesResult.local(local, hasMoreOld: true);
    }
    final r = await _service.getMessages(
      target: target,
      beforeId: beforeId,
      limit: limit,
    );
    if (r.errorMessage == null) {
      await _db.upsertMessages(target, r.list);
      await _db.setSyncMeta(
        target,
        oldestSyncedId: r.oldestId,
        hasMoreOld: r.hasMoreOld,
      );
      return r;
    }
    // 网络失败但本地仍有部分：用本地兜底
    if (local.isNotEmpty) {
      return ChatMessagesResult.local(local, hasMoreOld: false);
    }
    return r;
  }

  /// 增量拉新（after_id，推进已读），写库。调用方据 hasMoreNew 循环续拉。
  Future<ChatMessagesResult> fetchNew(
    ChatTarget target,
    int afterId, {
    int limit = 20,
  }) async {
    final r = await _service.getMessages(
      target: target,
      afterId: afterId,
      limit: limit,
    );
    if (r.errorMessage == null) {
      await _db.upsertMessages(target, r.list);
    }
    return r;
  }

  /// 引用定位：本地 around 命中直接用（可双向继续加载）；否则网络 around_id。
  /// 网络 around_id 锚点不存在时返回带 errorMessage 的结果。
  Future<ChatMessagesResult> locateMessage(
    ChatTarget target,
    int anchorId, {
    int limit = 20,
  }) async {
    final half = (limit / 2).floor();
    final localAround = await _db.aroundLocal(target, anchorId, half: half);
    if (localAround.found && localAround.list.isNotEmpty) {
      final list = localAround.list;
      return ChatMessagesResult(
        list: list,
        hasMoreOld: true,
        hasMoreNew: true,
        oldestId: list.first.messageId,
        newestId: list.last.messageId,
      );
    }
    final r = await _service.getMessages(
      target: target,
      aroundId: anchorId,
      limit: limit,
    );
    if (r.errorMessage == null) {
      await _db.upsertMessages(target, r.list);
    }
    return r;
  }

  /// 写库（发送确认 / 收到新消息后）
  Future<void> persist(ChatTarget target, List<ChatMessage> messages) =>
      _db.upsertMessages(target, messages);

  Future<void> markRecalledLocal(ChatTarget target, int messageId) =>
      _db.markRecalled(target, messageId);

  // ——————————————————— 会话列表 ———————————————————

  Future<List<ChatConversation>> localConversations() => _db.allConversations();

  /// 群聊页内消息落地后维护会话摘要：写 sqlite + 广播补丁给会话列表。
  ///
  /// 以前群聊页只往 `chat_message` 写消息，`chat_conversation` 那行一直是进群前的
  /// 旧摘要，所以返回列表会看到「旧内容旧时间 → 网络回来跳到最新并上移」的闪动。
  /// 现在本地先自行维护，网络刷新照旧跑，只是回来的值与本地一致所以看不出变化。
  ///
  /// [clearUnread] 仅在已读确实推进时传 true（人在底部看着）；停在历史位置时
  /// 未读该留着，交给网络刷新给准数。
  Future<void> touchConversationSummary(
    ChatTarget target,
    ChatMessage latest, {
    bool clearUnread = false,
  }) async {
    if (latest.messageId <= 0) return; // 乐观消息还没拿到真实 id，等确认后再来
    await _db.touchConversationSummary(
      target: target,
      lastMessageId: latest.messageId,
      lastMessage: latest.conversationPreview,
      lastMessageTime: latest.createdAt,
      clearUnread: clearUnread,
    );
    _service.publishConversationSummary((
      target: target,
      lastMessageId: latest.messageId,
      lastMessage: latest.conversationPreview,
      lastMessageTime: latest.createdAt,
      readCleared: clearUnread,
    ));
  }

  Future<bool> hasAnyConversation() => _db.hasAnyConversation();

  /// 会话列表：任务群 + 科室群 + 私聊混排（不传 conv_type），每条自带 convType
  Future<({List<ChatConversation> list, int total, String? message})>
  fetchConversations({int page = 1, int pageSize = 20}) async {
    final r = await _service.getConversations(page: page, pageSize: pageSize);
    if (r.message == null) {
      await _db.upsertConversations(r.list);
    }
    return r;
  }

  // ——————————————————— 通讯录 ———————————————————

  /// 本地通讯录（进页面秒显 / 网络失败兜底）。有关键词时本地模糊匹配。
  Future<List<ChatContact>> localContacts({String keyword = ''}) =>
      keyword.trim().isEmpty ? _db.allContacts() : _db.searchContacts(keyword);

  /// 本地单个联系人（群聊点头像弹名片：拿手机号与已有私聊会话 ID）
  Future<ChatContact?> localContact(int userId) => _db.contactById(userId);

  /// 网络通讯录。只有「无关键词第 1 页」才落库——搜索结果 / 后续分页是残缺子集，
  /// 写进去会让离线看到的联系人少一截。
  Future<({List<ChatContact> list, int total, String? message})> fetchContacts({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _service.getContacts(
      keyword: keyword,
      page: page,
      pageSize: pageSize,
    );
    if (r.message == null && keyword.trim().isEmpty && page == 1) {
      await _db.replaceContacts(r.list);
    }
    return r;
  }

  /// private/open 成功后把会话 ID 写回通讯录缓存，下次点该人直接进会话
  Future<void> cacheContactConvId(int userId, int convId) =>
      _db.setContactConvId(userId, convId);
}
