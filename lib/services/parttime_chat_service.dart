import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yatai_hub/models/chat_contact.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/api_client.dart';
import 'package:yatai_hub/services/jpush_service.dart';

/// 会话摘要补丁：群聊页内消息落地后，把「最后一条消息」对齐到会话列表那一行。
///
/// [readCleared] 为 true 时连未读/提及一起清零（人就在群里看着，已读已推进）。
typedef ChatConvSummary = ({
  ChatTarget target,
  int lastMessageId,
  String lastMessage,
  int lastMessageTime,
  bool readCleared,
});

/// 「群聊会话」接口（纯网络）+ 前台推送编排
///
/// Base: /v1/parttime_task/chat。群聊跨角色——发起人/执行人(兼职)/责任客服/管理员
/// 均可能在群，所有登录用户都可对接（成员校验由后端 can_manage / 4003 处理）。
///
/// 会话类型走 `conv_type`：1=任务群（task_id=任务 ID，不传即此）、2=科室群
/// （task_id=科室 ID）、3=私聊（task_id=私聊会话 ID）。三种 ID 会撞号，所以广播
/// 与活跃会话集合一律用 [ChatTarget] 而非裸 taskId。
///
/// 私聊（conv_type=3）复用全部收发/已读/撤回接口，另有两个专属入口：
/// [getContacts]（通讯录，仅 roleid≠275 可访问）、[openPrivateChat]
/// （get-or-create 会话，仅 roleid≠275 可发起）。成员管理三接口
/// （invite/remove/leave）对私聊一律被后端拒绝，前端不给入口。
class ParttimeChatService {
  static final ParttimeChatService _instance = ParttimeChatService._internal();
  factory ParttimeChatService() => _instance;
  ParttimeChatService._internal();

  final ApiClient _client = ApiClient();

  // ——————————————————— 广播 ———————————————————

  /// 某会话已读被推进（首屏 before_id=0 / 增量 after_id / markRead 成功后）。
  /// 列表红点据此清零。
  final StreamController<ChatTarget> _readController =
      StreamController<ChatTarget>.broadcast();
  Stream<ChatTarget> get onTaskRead => _readController.stream;

  /// 前台收到「当前正停留的会话」的新消息 → 页面据此 after_id 增量刷新。
  final StreamController<ChatTarget> _foregroundNewMessageController =
      StreamController<ChatTarget>.broadcast();
  Stream<ChatTarget> get onForegroundNewMessage =>
      _foregroundNewMessageController.stream;

  /// 前台收到「非当前会话」的新消息 → 列表/会话红点 +1（携带会话标识）。
  final StreamController<ChatTarget> _unreadChangedController =
      StreamController<ChatTarget>.broadcast();
  Stream<ChatTarget> get onUnreadChanged => _unreadChangedController.stream;

  /// 会话列表需要刷新（被拉入新群 / 收到新消息）。
  final StreamController<void> _conversationsChangedController =
      StreamController<void>.broadcast();
  Stream<void> get onConversationsChanged =>
      _conversationsChangedController.stream;

  /// 群聊页内消息落地（发送成功 / 增量拉到 / 撤回）后的会话摘要补丁。
  ///
  /// 会话列表订阅它就地改内存那一行，用户还停在群聊页时列表就已经对齐了，返回时
  /// 不会先亮旧摘要再被网络结果顶掉。**只是补丁不是整行**：群聊页手里没有
  /// member_count / title 等字段，整行覆盖会把它们抹平。
  final StreamController<ChatConvSummary> _convSummaryController =
      StreamController<ChatConvSummary>.broadcast();
  Stream<ChatConvSummary> get onConversationSummaryUpdated =>
      _convSummaryController.stream;

  void publishConversationSummary(ChatConvSummary summary) =>
      _convSummaryController.add(summary);

  // ——————————————————— 当前活跃会话感知 ———————————————————

  /// 当前正打开的群聊页集合（支持同会话多层重入）。
  /// ChatPage initState/dispose 调 [enterChat]/[leaveChat] 注册。
  final Set<ChatTarget> _activeTargets = {};

  void enterChat(ChatTarget target) => _activeTargets.add(target);
  void leaveChat(ChatTarget target) => _activeTargets.remove(target);
  bool isActiveChat(ChatTarget target) => _activeTargets.contains(target);

  // ——————————————————— 前台推送编排 ———————————————————

  bool _coordinatorStarted = false;
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _notiSub;

  /// 「会话列表需刷新」广播去抖：推送常突发多条，合并成一次发射，
  /// 避免每个订阅方（消息 Tab、底栏红点）对每条推送各拉一次 conversations 造成刷屏。
  Timer? _convChangedDebounce;
  void _emitConversationsChanged() {
    _convChangedDebounce?.cancel();
    _convChangedDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _conversationsChangedController.add(null),
    );
  }

  /// 启动前台推送编排（幂等）。在 main 的服务初始化期调用。
  ///
  /// - 透传 onMessage：前台实时刷新主源（后端 ttl=60s，仅在线）。
  /// - 通知 onNotification：仅用于「在该会话页时清掉系统通知栏」。
  /// 两通道对同一条都可能触发，页面侧按 message_id 去重。
  void startForegroundCoordinator() {
    if (_coordinatorStarted) return;
    _coordinatorStarted = true;
    _msgSub = JPushService().onMessage.listen((m) => _onPush(m, false));
    _notiSub = JPushService().onNotification.listen((m) => _onPush(m, true));
  }

  void _onPush(Map<String, dynamic> message, bool fromNotification) {
    final extras = _extractExtras(message);
    if (extras == null) return;
    if (extras['action']?.toString() != 'open_part_time_comment') return;
    final taskId = _asInt(extras['task_id']);
    if (taskId <= 0) return;
    // 科室群播报（打卡等）带 conv_type=2、私聊带 3；缺省按任务群
    final target = ChatTarget.of(_asInt(extras['conv_type']), taskId);

    if (_activeTargets.contains(target)) {
      // 用户就在该群聊页：清通知栏（仅通知通道）+ 让页面增量刷新，不跳转
      if (fromNotification) {
        // ignore: discarded_futures
        JPushService().clearAllNotifications();
      }
      _foregroundNewMessageController.add(target);
    } else {
      _unreadChangedController.add(target); // 即时点亮红点（廉价，不拉网络）
      _emitConversationsChanged(); // 拉取去抖合并
    }
  }

  // ——————————————————— 消息 ———————————————————

  /// 拉取消息。三种模式互斥，优先级 around > after > before（后端处理）：
  /// - 首屏：before_id=0（默认）→ 最新一屏 + 推进已读
  /// - 翻历史：before_id=oldest_id → 不推进已读
  /// - 增量：after_id=newest_id → 正序追加 + 推进已读
  /// - 定位：around_id=锚点 → 前后各 ~limit/2 条，不推进已读
  Future<ChatMessagesResult> getMessages({
    required ChatTarget target,
    int beforeId = 0,
    int afterId = 0,
    int aroundId = 0,
    int limit = 20,
  }) async {
    try {
      final qp = <String, dynamic>{
        'task_id': target.taskId,
        'conv_type': target.convType,
        'limit': limit,
      };
      if (aroundId > 0) {
        qp['around_id'] = aroundId;
      } else if (afterId > 0) {
        qp['after_id'] = afterId;
      } else {
        qp['before_id'] = beforeId;
      }
      final response = await _client.get(
        '/v1/parttime_task/chat/messages',
        queryParameters: qp,
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        // 首屏(before=0) 与增量(after>0) 会推进已读；翻历史/定位不推进
        if (aroundId <= 0 && beforeId <= 0) {
          _readController.add(target);
        }
        return ChatMessagesResult.fromData(r.data!);
      }
      return ChatMessagesResult.error(r.msg ?? '获取消息失败');
    } on DioException catch (e) {
      if (kDebugMode) print('[Chat] getMessages 异常: $e');
      return ChatMessagesResult.error(_extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[Chat] getMessages 失败: $e');
      return ChatMessagesResult.error('获取消息失败');
    }
  }

  /// 发送消息（含引用 / @ / 幂等）
  Future<
    ({
      bool success,
      int messageId,
      int createdAt,
      bool duplicated,
      String? message,
    })
  >
  send({
    required ChatTarget target,
    String content = '',
    List<String> images = const [],
    List<ChatMedia> media = const [],
    int quoteMessageId = 0,
    String clientMsgId = '',
    List<int> mentionUserIds = const [],
    bool mentionAll = false,
  }) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/send',
        data: {
          'task_id': target.taskId,
          'conv_type': target.convType,
          'content': content,
          // images 为兼容字段（旧后端只认它）；media 带缩略图，新后端优先用
          // media 并由它反推 images
          'images': images,
          'media': media.map((e) => e.toMap()).toList(),
          'quote_message_id': quoteMessageId,
          'client_msg_id': clientMsgId,
          'mention_user_ids': mentionUserIds,
          'mention_all': mentionAll,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        _readController.add(target); // 发送者自身已读已推进
        return (
          success: true,
          messageId: _asInt(r.data!['message_id']),
          createdAt: _asInt(r.data!['created_at']),
          duplicated: _asBool(r.data!['duplicated']),
          message: null,
        );
      }
      return (
        success: false,
        messageId: 0,
        createdAt: 0,
        duplicated: false,
        message: r.msg ?? '发送失败',
      );
    } on DioException catch (e) {
      return (
        success: false,
        messageId: 0,
        createdAt: 0,
        duplicated: false,
        message: _extractMessage(e) ?? '发送失败',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] send 失败: $e');
      return (
        success: false,
        messageId: 0,
        createdAt: 0,
        duplicated: false,
        message: '发送失败',
      );
    }
  }

  /// 撤回本人消息（2 分钟内）
  Future<({bool success, String? message})> recall(int messageId) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/message/recall',
        data: {'message_id': messageId},
      );
      final r = _parse(response.data);
      if (r.ok) return (success: true, message: null);
      return (success: false, message: r.msg ?? '撤回失败');
    } on DioException catch (e) {
      return (success: false, message: _extractMessage(e) ?? '撤回失败');
    } catch (e) {
      if (kDebugMode) print('[Chat] recall 失败: $e');
      return (success: false, message: '撤回失败');
    }
  }

  /// 单会话未读数
  Future<int> getTaskUnread(ChatTarget target) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/chat/unread_count',
        queryParameters: {
          'task_id': target.taskId,
          'conv_type': target.convType,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) return _asInt(r.data!['total_unread']);
      return 0;
    } catch (e) {
      if (kDebugMode) print('[Chat] getTaskUnread 失败: $e');
      return 0;
    }
  }

  /// 未读汇总：总数 + 每个有未读的会话（{target: unread}）
  ///
  /// `task_id=0` 时后端反查我的**全部**会话（任务群走成员表、科室群实时算、私聊查
  /// 会话表）后汇总，不受 conversations 的分页限制 —— 所以「消息」Tab 红点用它，
  /// 而不是看会话列表第 1 页那 20 条（未读排在 20 名外就漏了）。
  ///
  /// 键必须是 [ChatTarget]：返回的 tasks 每项都带 conv_type，三类会话 ID 会撞号，
  /// 用裸 taskId 作键会让任务群 #5 / 科室群 #5 / 私聊 #5 互相覆盖。
  /// 只返回 unread > 0 的会话（后端跳过 0）。
  Future<({int total, Map<ChatTarget, int> byTarget})> getAllUnread() async {
    try {
      final response = await _client.get('/v1/parttime_task/chat/unread_count');
      final r = _parse(response.data);
      final byTarget = <ChatTarget, int>{};
      if (r.ok && r.data != null) {
        final rawTasks = r.data!['tasks'];
        if (rawTasks is List) {
          for (final item in rawTasks) {
            if (item is Map) {
              final tid = _asInt(item['task_id']);
              if (tid > 0) {
                final target = ChatTarget.of(_asInt(item['conv_type']), tid);
                byTarget[target] = _asInt(item['unread_count']);
              }
            }
          }
        }
        return (total: _asInt(r.data!['total_unread']), byTarget: byTarget);
      }
      return (total: 0, byTarget: byTarget);
    } catch (e) {
      if (kDebugMode) print('[Chat] getAllUnread 失败: $e');
      return (total: 0, byTarget: <ChatTarget, int>{});
    }
  }

  /// 推进已读
  Future<({bool success, int lastReadId, int unread})> markRead({
    required ChatTarget target,
    int upToId = 0,
  }) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/read',
        data: {
          'task_id': target.taskId,
          'conv_type': target.convType,
          'up_to_id': upToId,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        _readController.add(target);
        return (
          success: true,
          lastReadId: _asInt(r.data!['last_read_id']),
          unread: _asInt(r.data!['unread_count']),
        );
      }
      return (success: false, lastReadId: 0, unread: 0);
    } catch (e) {
      if (kDebugMode) print('[Chat] markRead 失败: $e');
      return (success: false, lastReadId: 0, unread: 0);
    }
  }

  /// 最近会话列表
  Future<({List<ChatConversation> list, int total, String? message})>
  getConversations({int page = 1, int pageSize = 20}) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/chat/conversations',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        final rawList = r.data!['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => ChatConversation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (list: list, total: _asInt(r.data!['total']), message: null);
      }
      return (list: <ChatConversation>[], total: 0, message: r.msg ?? '获取会话失败');
    } on DioException catch (e) {
      return (
        list: <ChatConversation>[],
        total: 0,
        message: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] getConversations 失败: $e');
      return (list: <ChatConversation>[], total: 0, message: '获取会话失败');
    }
  }

  // ——————————————————— 通讯录 / 私聊 ———————————————————

  /// 通讯录：列全部兼职人员（仅 roleid≠275 可访问，兼职调用返回「无权限」）。
  ///
  /// 行内 `conv_id>0` 表示与当前登录人已有私聊会话，可直接当 task_id +
  /// conv_type=3 进会话，跳过 [openPrivateChat]。
  Future<({List<ChatContact> list, int total, String? message})> getContacts({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/contacts',
        queryParameters: {
          'keyword': keyword,
          'page': page,
          'page_size': pageSize,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        final rawList = r.data!['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => ChatContact.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (list: list, total: _asInt(r.data!['total']), message: null);
      }
      return (list: <ChatContact>[], total: 0, message: r.msg ?? '获取通讯录失败');
    } on DioException catch (e) {
      return (
        list: <ChatContact>[],
        total: 0,
        message: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] getContacts 失败: $e');
      return (list: <ChatContact>[], total: 0, message: '获取通讯录失败');
    }
  }

  /// 发起 / 获取私聊会话（get-or-create，不发任何消息）。
  ///
  /// 仅 roleid≠275 可发起；失败 msg 由后端给（「兼职人员不能主动发起私聊」
  /// 「只能与兼职人员发起私聊」「对方不存在或已离职」「不能和自己私聊」），
  /// 原样透给 UI 展示。
  Future<
    ({
      bool success,
      int taskId,
      String peerName,
      String peerAvatar,
      String? message,
    })
  >
  openPrivateChat(int peerId) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/private/open',
        data: {'peer_id': peerId},
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        final rawPeer = r.data!['peer'];
        final peer = rawPeer is Map
            ? Map<String, dynamic>.from(rawPeer)
            : const <String, dynamic>{};
        return (
          success: true,
          taskId: _asInt(r.data!['task_id']),
          peerName: peer['username']?.toString() ?? '',
          peerAvatar: peer['avatar']?.toString() ?? '',
          message: null,
        );
      }
      return (
        success: false,
        taskId: 0,
        peerName: '',
        peerAvatar: '',
        message: r.msg ?? '发起私聊失败',
      );
    } on DioException catch (e) {
      return (
        success: false,
        taskId: 0,
        peerName: '',
        peerAvatar: '',
        message: _extractMessage(e) ?? '发起私聊失败',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] openPrivateChat 失败: $e');
      return (
        success: false,
        taskId: 0,
        peerName: '',
        peerAvatar: '',
        message: '发起私聊失败',
      );
    }
  }

  // ——————————————————— 成员 ———————————————————

  /// 群成员。科室群后端固定返回 `can_manage=false`（成员随科室自动同步），
  /// 前端据此隐藏邀请/移除入口。
  Future<({List<ChatMember> list, bool canManage, String? message})> getMembers(
    ChatTarget target,
  ) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/chat/members',
        queryParameters: {
          'task_id': target.taskId,
          'conv_type': target.convType,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        return (
          list: _members(r.data!['list']),
          canManage: _asBool(r.data!['can_manage']),
          message: null,
        );
      }
      return (
        list: <ChatMember>[],
        canManage: false,
        message: r.msg ?? '获取成员失败',
      );
    } on DioException catch (e) {
      return (
        list: <ChatMember>[],
        canManage: false,
        message: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] getMembers 失败: $e');
      return (list: <ChatMember>[], canManage: false, message: '获取成员失败');
    }
  }

  Future<
    ({bool success, List<ChatMember> list, List<int> added, String? message})
  >
  invite({required ChatTarget target, required List<int> userIds}) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/member/invite',
        data: {
          'task_id': target.taskId,
          'conv_type': target.convType,
          'user_ids': userIds,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        final rawAdded = r.data!['added'];
        final added = (rawAdded is List ? rawAdded : const [])
            .map(_asInt)
            .where((e) => e > 0)
            .toList();
        return (
          success: true,
          list: _members(r.data!['list']),
          added: added,
          message: null,
        );
      }
      return (
        success: false,
        list: <ChatMember>[],
        added: <int>[],
        message: r.msg ?? '邀请失败',
      );
    } on DioException catch (e) {
      return (
        success: false,
        list: <ChatMember>[],
        added: <int>[],
        message: _extractMessage(e) ?? '邀请失败',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] invite 失败: $e');
      return (
        success: false,
        list: <ChatMember>[],
        added: <int>[],
        message: '邀请失败',
      );
    }
  }

  Future<({bool success, List<ChatMember> list, String? message})>
  removeMember({required ChatTarget target, required int userId}) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/chat/member/remove',
        data: {
          'task_id': target.taskId,
          'conv_type': target.convType,
          'user_id': userId,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        return (success: true, list: _members(r.data!['list']), message: null);
      }
      return (success: false, list: <ChatMember>[], message: r.msg ?? '移除失败');
    } on DioException catch (e) {
      return (
        success: false,
        list: <ChatMember>[],
        message: _extractMessage(e) ?? '移除失败',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] removeMember 失败: $e');
      return (success: false, list: <ChatMember>[], message: '移除失败');
    }
  }

  Future<({List<StaffSearchItem> list, int total, String? message})>
  searchStaff({String keyword = '', int page = 1, int pageSize = 20}) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/staff/search',
        queryParameters: {
          'keyword': keyword,
          'page': page,
          'page_size': pageSize,
        },
      );
      final r = _parse(response.data);
      if (r.ok && r.data != null) {
        final rawList = r.data!['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => StaffSearchItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (list: list, total: _asInt(r.data!['total']), message: null);
      }
      return (list: <StaffSearchItem>[], total: 0, message: r.msg ?? '搜索失败');
    } on DioException catch (e) {
      return (
        list: <StaffSearchItem>[],
        total: 0,
        message: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Chat] searchStaff 失败: $e');
      return (list: <StaffSearchItem>[], total: 0, message: '搜索失败');
    }
  }

  // ——————————————————— 工具 ———————————————————

  List<ChatMember> _members(dynamic raw) => (raw is List ? raw : const [])
      .whereType<Map>()
      .map((e) => ChatMember.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  /// 拆包：返回 (ok, msg, data)。兼容 {code,msg,data} 与直接 {...}。
  ({bool ok, String? msg, Map<String, dynamic>? data}) _parse(dynamic data) {
    if (data is! Map) return (ok: false, msg: null, data: null);
    if (data.containsKey('code')) {
      final ok = _asInt(data['code']) == 0;
      final d = data['data'];
      return (
        ok: ok,
        msg: data['msg']?.toString(),
        data: d is Map ? Map<String, dynamic>.from(d) : null,
      );
    }
    return (ok: true, msg: null, data: Map<String, dynamic>.from(data));
  }

  Map<String, dynamic>? _extractExtras(Map<String, dynamic> message) {
    dynamic extras = message['extras'];
    // Android 极光把业务 extras 再包一层 cn.jpush.android.EXTRA，先解开
    if (extras is Map && extras['cn.jpush.android.EXTRA'] != null) {
      extras = extras['cn.jpush.android.EXTRA'];
    }
    if (extras is Map) {
      final m = Map<String, dynamic>.from(extras);
      if (m['action'] != null) return m;
    }
    if (extras is String && extras.isNotEmpty) {
      try {
        final decoded = jsonDecode(extras);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    // 顶层平铺（iOS / 部分平台）
    if (message['action'] != null) return Map<String, dynamic>.from(message);
    return null;
  }

  String? _extractMessage(DioException e) {
    try {
      dynamic data = e.response?.data;
      if (data is String) data = jsonDecode(data);
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) return detail['msg']?.toString();
        if (detail is String) return detail;
        if (data['msg'] is String) return data['msg'] as String;
      }
    } catch (_) {}
    return null;
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

  void dispose() {
    _msgSub?.cancel();
    _notiSub?.cancel();
    _convChangedDebounce?.cancel();
    _readController.close();
    _foregroundNewMessageController.close();
    _unreadChangedController.close();
    _conversationsChangedController.close();
    _convSummaryController.close();
  }
}
