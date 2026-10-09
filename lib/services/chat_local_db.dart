import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:yatai_hub/models/chat_contact.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/models/chat_query.dart';
import 'package:yatai_hub/models/chat_target.dart';

/// 群聊离线消息库（sqlite）
///
/// 消息相关三张表（v3 起每张都按 `conv_type + task_id` 定位会话，1=任务群
/// 2=科室群 3=私聊；三种 ID 来自不同表会撞号，查询必须带 conv_type）：
/// - chat_message：消息体（主键 task_id+message_id，message_id 后端全局唯一）
/// - chat_conversation：最近会话列表缓存（主键 conv_type+task_id）
/// - chat_sync_meta：每个会话的同步游标（主键 conv_type+task_id）
///
/// v2 起新增「群聊内查询」三张缓存表（先本地秒显、再网络刷新）：
/// - chat_task_context：任务 → 客户/医院 id，决定菜单里查询入口是否出现
/// - chat_hospital_cache：医院信息快照（仅弹窗展示字段，不含商务敏感数据）
/// - chat_client_cache：客户资料聚合快照
///
/// v4 起新增通讯录缓存（私聊入口，仅 roleid≠275 可见）：
/// - chat_contact：兼职人员通讯录快照（主键 user_id，含已有私聊会话 conv_id；
///   v5 加 mobile 列供列表右侧拨号）
///
/// 退登时 [clearAll] 清空，避免换账号串数据。
class ChatLocalDb {
  static final ChatLocalDb _instance = ChatLocalDb._internal();
  factory ChatLocalDb() => _instance;
  ChatLocalDb._internal();

  static const String _dbName = 'suixinpai_chat.db';
  static const int _dbVersion = 6;

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;
    final completer = Completer<Database>();
    _opening = completer;
    try {
      final dir = await getDatabasesPath();
      final path = p.join(dir, _dbName);
      final db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _db = db;
      completer.complete(db);
    } catch (e) {
      completer.completeError(e);
      _opening = null;
      rethrow;
    }
    _opening = null;
    return completer.future;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chat_message (
        conv_type INTEGER NOT NULL DEFAULT 1,
        task_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        msg_type INTEGER NOT NULL DEFAULT 1,
        recalled INTEGER NOT NULL DEFAULT 0,
        content TEXT,
        images TEXT,
        media TEXT,
        user_id INTEGER NOT NULL DEFAULT 0,
        username TEXT,
        roleid INTEGER NOT NULL DEFAULT 0,
        avatar TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        quote_message_id INTEGER NOT NULL DEFAULT 0,
        quote TEXT,
        mention_all INTEGER NOT NULL DEFAULT 0,
        mention_user_ids TEXT,
        PRIMARY KEY (task_id, message_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chat_message_conv_created '
      'ON chat_message (conv_type, task_id, created_at)',
    );
    await _createConversationTable(db);
    await _createSyncMetaTable(db);
    await _createQueryTables(db);
    await _createContactTable(db);
  }

  /// v1 → v2：新增群聊内查询三张缓存表
  /// v2 → v3：接入科室群（conv_type）
  /// v3 → v4：接入私聊（通讯录表 + 会话表加对方 userid/头像两列）
  /// v4 → v5：通讯录加 mobile 列（列表右侧拨号按钮）
  /// v5 → v6：消息加 media 列（缩略图 / 视频截帧）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createQueryTables(db);
    if (oldVersion < 3) await _upgradeToV3(db);
    if (oldVersion < 4) await _upgradeToV4(db);
    if (oldVersion < 5) await _upgradeToV5(db);
    if (oldVersion < 6) await _upgradeToV6(db);
  }

  /// v3：会话类型（1=任务群 2=科室群）进入定位键。
  ///
  /// - chat_message 只加列 + 建新索引：message_id 后端全局唯一，主键
  ///   (task_id, message_id) 不会跨类型冲突，历史消息全部保留（离线可读）
  /// - chat_conversation / chat_sync_meta 主键要从 task_id 改成
  ///   (conv_type, task_id)，sqlite 不支持改主键 → 直接重建。两张表都是纯缓存：
  ///   会话列表进「消息」Tab 就会重拉，同步游标里的 last_read_id 首屏
  ///   fetchInitial 会用服务端值写回，重建无实际损失。
  Future<void> _upgradeToV3(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE chat_message ADD COLUMN conv_type INTEGER NOT NULL DEFAULT 1',
      );
    } catch (e) {
      // 列已存在（重复升级）时忽略
      if (kDebugMode) print('[ChatLocalDb] v3 加列跳过: $e');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_message_conv_created '
      'ON chat_message (conv_type, task_id, created_at)',
    );
    await db.execute('DROP TABLE IF EXISTS chat_conversation');
    await db.execute('DROP TABLE IF EXISTS chat_sync_meta');
    await _createConversationTable(db);
    await _createSyncMetaTable(db);
  }

  /// v4：接入私聊（conv_type=3）。
  ///
  /// - 新建 chat_contact（通讯录快照，只有 roleid≠275 的账号会往里写）
  /// - chat_conversation 只加 peer_user_id / avatar 两列（私聊行要展示对方姓名
  ///   头像）。主键不变 → 纯 ALTER，不重建，已有会话缓存全保留。
  ///   v2→v4 时 [_upgradeToV3] 已按新结构重建过该表，这里加列会失败，忽略即可。
  Future<void> _upgradeToV4(Database db) async {
    for (final column in const [
      'peer_user_id INTEGER NOT NULL DEFAULT 0',
      "avatar TEXT NOT NULL DEFAULT ''",
    ]) {
      try {
        await db.execute('ALTER TABLE chat_conversation ADD COLUMN $column');
      } catch (e) {
        // 列已存在（v2→v4 走过 v3 重建 / 重复升级）时忽略
        if (kDebugMode) print('[ChatLocalDb] v4 加列跳过($column): $e');
      }
    }
    await _createContactTable(db);
  }

  Future<void> _createConversationTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_conversation (
        conv_type INTEGER NOT NULL DEFAULT 1,
        task_id INTEGER NOT NULL,
        last_message_id INTEGER NOT NULL DEFAULT 0,
        last_message TEXT,
        last_message_time INTEGER NOT NULL DEFAULT 0,
        unread_count INTEGER NOT NULL DEFAULT 0,
        has_mention INTEGER NOT NULL DEFAULT 0,
        member_count INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        peer_user_id INTEGER NOT NULL DEFAULT 0,
        avatar TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (conv_type, task_id)
      )
    ''');
  }

  /// v5：通讯录加 mobile（列表右侧拨号按钮）。
  ///
  /// 纯 ALTER 而不是重建：v4 已在测试机上建过库，需就地升级。表由
  /// [_upgradeToV4]（oldVersion<4）或 v4 本身保证存在；新装机走
  /// [_createContactTable] 已带该列，此时加列失败忽略即可。
  Future<void> _upgradeToV5(Database db) async {
    try {
      await db.execute(
        "ALTER TABLE chat_contact ADD COLUMN mobile TEXT NOT NULL DEFAULT ''",
      );
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] v5 加列跳过: $e');
    }
  }

  /// v6：消息加 media（图片缩略图 / 视频截帧地址）。
  ///
  /// 纯 ALTER 不重建：历史消息要留着离线可读。老行 media 为 NULL，
  /// [ChatMedia.resolve] 会按 images 兜底（无缩略图，行为与升级前一致）。
  Future<void> _upgradeToV6(Database db) async {
    try {
      await db.execute('ALTER TABLE chat_message ADD COLUMN media TEXT');
    } catch (e) {
      // 列已存在（重复升级）时忽略
      if (kDebugMode) print('[ChatLocalDb] v6 加列跳过: $e');
    }
  }

  /// 通讯录快照表（私聊入口）。sort_index 保留接口返回顺序，本地读取按它排。
  Future<void> _createContactTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_contact (
        user_id INTEGER PRIMARY KEY,
        username TEXT,
        avatar TEXT,
        roleid INTEGER NOT NULL DEFAULT 0,
        mobile TEXT NOT NULL DEFAULT '',
        conv_id INTEGER NOT NULL DEFAULT 0,
        sort_index INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createSyncMetaTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sync_meta (
        conv_type INTEGER NOT NULL DEFAULT 1,
        task_id INTEGER NOT NULL,
        oldest_synced_id INTEGER NOT NULL DEFAULT 0,
        has_more_old INTEGER NOT NULL DEFAULT 1,
        last_read_id INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (conv_type, task_id)
      )
    ''');
  }

  /// 群聊内查询（医院信息 / 客户资料）的三张缓存表
  Future<void> _createQueryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_task_context (
        task_id INTEGER PRIMARY KEY,
        client_id INTEGER NOT NULL DEFAULT 0,
        hospital_id INTEGER NOT NULL DEFAULT 0,
        hospital_name TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_hospital_cache (
        hospital_id INTEGER PRIMARY KEY,
        payload TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_client_cache (
        client_id INTEGER PRIMARY KEY,
        payload TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ——————————————————— 消息 ———————————————————

  /// 批量 upsert（仅持久化已确认消息，跳过 message_id<=0 的乐观占位）
  Future<void> upsertMessages(
    ChatTarget target,
    List<ChatMessage> messages,
  ) async {
    final list = messages.where((m) => m.messageId > 0).toList();
    if (list.isEmpty) return;
    try {
      final db = await _database;
      final batch = db.batch();
      for (final m in list) {
        batch.insert('chat_message', {
          ...m.toDbMap(),
          'conv_type': target.convType,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] upsertMessages 失败: $e');
    }
  }

  /// 最近 N 条（返回正序：旧→新）
  Future<List<ChatMessage>> recentMessages(
    ChatTarget target, {
    int limit = 30,
  }) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_message',
        where: 'conv_type = ? AND task_id = ?',
        whereArgs: [target.convType, target.taskId],
        orderBy: 'message_id DESC',
        limit: limit,
      );
      return rows.map(ChatMessage.fromDbMap).toList().reversed.toList();
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] recentMessages 失败: $e');
      return const [];
    }
  }

  /// 比 beforeId 更早的 N 条（返回正序：旧→新），用于上拉历史本地优先
  Future<List<ChatMessage>> messagesOlderThan(
    ChatTarget target,
    int beforeId, {
    int limit = 20,
  }) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_message',
        where: 'conv_type = ? AND task_id = ? AND message_id < ?',
        whereArgs: [target.convType, target.taskId, beforeId],
        orderBy: 'message_id DESC',
        limit: limit,
      );
      return rows.map(ChatMessage.fromDbMap).toList().reversed.toList();
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] messagesOlderThan 失败: $e');
      return const [];
    }
  }

  /// 本地 around：锚点前 half 条 + 锚点 + 后 half 条（正序）。
  /// 返回 (list, found)：found=锚点是否在本地。
  Future<({List<ChatMessage> list, bool found})> aroundLocal(
    ChatTarget target,
    int anchorId, {
    int half = 10,
  }) async {
    try {
      final db = await _database;
      final olderRows = await db.query(
        'chat_message',
        where: 'conv_type = ? AND task_id = ? AND message_id <= ?',
        whereArgs: [target.convType, target.taskId, anchorId],
        orderBy: 'message_id DESC',
        limit: half + 1,
      );
      final newerRows = await db.query(
        'chat_message',
        where: 'conv_type = ? AND task_id = ? AND message_id > ?',
        whereArgs: [target.convType, target.taskId, anchorId],
        orderBy: 'message_id ASC',
        limit: half,
      );
      final older = olderRows.map(ChatMessage.fromDbMap).toList();
      final found = older.any((m) => m.messageId == anchorId);
      final newer = newerRows.map(ChatMessage.fromDbMap).toList();
      final list = [...older.reversed, ...newer];
      return (list: list, found: found);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] aroundLocal 失败: $e');
      return (list: <ChatMessage>[], found: false);
    }
  }

  Future<ChatMessage?> getMessage(ChatTarget target, int messageId) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_message',
        where: 'conv_type = ? AND task_id = ? AND message_id = ?',
        whereArgs: [target.convType, target.taskId, messageId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return ChatMessage.fromDbMap(rows.first);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] getMessage 失败: $e');
      return null;
    }
  }

  Future<void> markRecalled(ChatTarget target, int messageId) async {
    try {
      final db = await _database;
      await db.update(
        'chat_message',
        {
          'recalled': 1,
          'content': '',
          'images': '[]',
          'media': '[]',
          'quote': null,
        },
        where: 'conv_type = ? AND task_id = ? AND message_id = ?',
        whereArgs: [target.convType, target.taskId, messageId],
      );
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] markRecalled 失败: $e');
    }
  }

  // ——————————————————— 同步游标 ———————————————————

  Future<({int oldestSyncedId, bool hasMoreOld, int lastReadId})?> getSyncMeta(
    ChatTarget target,
  ) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_sync_meta',
        where: 'conv_type = ? AND task_id = ?',
        whereArgs: [target.convType, target.taskId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      return (
        oldestSyncedId: (r['oldest_synced_id'] as int?) ?? 0,
        hasMoreOld: ((r['has_more_old'] as int?) ?? 1) != 0,
        lastReadId: (r['last_read_id'] as int?) ?? 0,
      );
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] getSyncMeta 失败: $e');
      return null;
    }
  }

  Future<void> setSyncMeta(
    ChatTarget target, {
    int? oldestSyncedId,
    bool? hasMoreOld,
    int? lastReadId,
  }) async {
    try {
      final db = await _database;
      final existing = await getSyncMeta(target);
      await db.insert('chat_sync_meta', {
        'conv_type': target.convType,
        'task_id': target.taskId,
        'oldest_synced_id': oldestSyncedId ?? existing?.oldestSyncedId ?? 0,
        'has_more_old': (hasMoreOld ?? existing?.hasMoreOld ?? true) ? 1 : 0,
        'last_read_id': lastReadId ?? existing?.lastReadId ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] setSyncMeta 失败: $e');
    }
  }

  // ——————————————————— 会话列表 ———————————————————

  Future<void> upsertConversations(List<ChatConversation> list) async {
    if (list.isEmpty) return;
    try {
      final db = await _database;
      final batch = db.batch();
      for (final c in list) {
        batch.insert(
          'chat_conversation',
          c.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] upsertConversations 失败: $e');
    }
  }

  /// 会话摘要就地更新（**只 UPDATE，不 INSERT**）。
  ///
  /// 群聊页收发消息后立刻把本地会话行的最后一条消息/时间对齐，这样返回列表时读到
  /// 的已经是最新值，不会先显示进群前的旧摘要、等网络回来再跳一下（视觉闪动）。
  ///
  /// 行不存在（新会话还没在列表里出现过）时什么也不做，交给网络刷新补齐 —— 这里
  /// 没有 title / member_count，插半行会让列表冒出无标题、0 人的行。
  ///
  /// `last_message_id <= ?` 是防乱序：撤回旧消息、慢到的增量都不该把更新的摘要
  /// 盖回去。
  Future<void> touchConversationSummary({
    required ChatTarget target,
    required int lastMessageId,
    required String lastMessage,
    required int lastMessageTime,
    bool clearUnread = false,
  }) async {
    if (lastMessageId <= 0) return;
    try {
      final db = await _database;
      final values = <String, Object?>{
        'last_message_id': lastMessageId,
        'last_message': lastMessage,
        'last_message_time': lastMessageTime,
      };
      if (clearUnread) {
        values['unread_count'] = 0;
        values['has_mention'] = 0;
      }
      await db.update(
        'chat_conversation',
        values,
        where: 'conv_type = ? AND task_id = ? AND last_message_id <= ?',
        whereArgs: [target.convType, target.taskId, lastMessageId],
      );
    } catch (e) {
      if (kDebugMode) {
        print('[ChatLocalDb] touchConversationSummary 失败: $e');
      }
    }
  }

  Future<List<ChatConversation>> allConversations() async {
    try {
      final db = await _database;
      // 排序口径对齐后端 chat_conversations：科室群整体置顶，其余按最后消息时间
      // 倒序、同一时间戳按 last_message_id 倒序。本地与网络顺序不一致的话，
      // 秒显那一屏会在网络返回后整体跳一次。
      final rows = await db.query(
        'chat_conversation',
        orderBy:
            'CASE conv_type WHEN 2 THEN 0 ELSE 1 END, '
            'last_message_time DESC, last_message_id DESC',
      );
      return rows.map(ChatConversation.fromDbMap).toList();
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] allConversations 失败: $e');
      return const [];
    }
  }

  Future<bool> hasAnyConversation() async {
    try {
      final db = await _database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chat_conversation'),
      );
      return (count ?? 0) > 0;
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] hasAnyConversation 失败: $e');
      return false;
    }
  }

  // ——————————————————— 通讯录 ———————————————————

  /// 整表替换（清空 + 批量写）。
  ///
  /// 只在「无关键词第 1 页」拉取成功时调用，保证本地始终是一份完整快照——搜索
  /// 结果或第 N 页若也落库，会把本地缩成一个残缺子集，离线时看不到全部联系人。
  Future<void> replaceContacts(List<ChatContact> list) async {
    if (list.isEmpty) return;
    try {
      final db = await _database;
      final now = _nowSeconds();
      final batch = db.batch();
      batch.delete('chat_contact');
      for (var i = 0; i < list.length; i++) {
        batch.insert('chat_contact', {
          ...list[i].toDbMap(sortIndex: i),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] replaceContacts 失败: $e');
    }
  }

  Future<List<ChatContact>> allContacts() async {
    try {
      final db = await _database;
      final rows = await db.query('chat_contact', orderBy: 'sort_index ASC');
      return rows.map(ChatContact.fromDbMap).toList();
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] allContacts 失败: $e');
      return const [];
    }
  }

  /// 本地按姓名模糊匹配（网络失败 / 离线时的搜索兜底）
  Future<List<ChatContact>> searchContacts(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return allContacts();
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_contact',
        where: 'username LIKE ?',
        whereArgs: ['%$kw%'],
        orderBy: 'sort_index ASC',
      );
      return rows.map(ChatContact.fromDbMap).toList();
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] searchContacts 失败: $e');
      return const [];
    }
  }

  /// 按 userid 取单个联系人（群聊里点头像弹名片时查手机号 / 已有会话 ID）。
  /// 未拉过通讯录（或该人不是兼职）时返回 null。
  Future<ChatContact?> contactById(int userId) async {
    if (userId <= 0) return null;
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_contact',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return ChatContact.fromDbMap(rows.first);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] contactById 失败: $e');
      return null;
    }
  }

  /// private/open 拿到会话 ID 后写回，下次进通讯录可直接进会话、跳过 open
  Future<void> setContactConvId(int userId, int convId) async {
    if (userId <= 0 || convId <= 0) return;
    try {
      final db = await _database;
      await db.update(
        'chat_contact',
        {'conv_id': convId},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] setContactConvId 失败: $e');
    }
  }

  // ——————————————————— 群聊内查询缓存 ———————————————————

  /// 任务上下文（客户 / 医院 id）
  Future<ChatTaskContext?> getTaskContext(int taskId) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'chat_task_context',
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return ChatTaskContext.fromDbMap(rows.first);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] getTaskContext 失败: $e');
      return null;
    }
  }

  Future<void> upsertTaskContext(ChatTaskContext ctx) async {
    try {
      final db = await _database;
      await db.insert('chat_task_context', {
        ...ctx.toDbMap(),
        'updated_at': _nowSeconds(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] upsertTaskContext 失败: $e');
    }
  }

  /// 医院信息快照
  Future<KrHospitalBrief?> getHospitalBrief(int hospitalId) async {
    final payload = await _getPayload(
      'chat_hospital_cache',
      'hospital_id',
      hospitalId,
    );
    if (payload == null) return null;
    try {
      return KrHospitalBrief.fromJson(payload);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] 医院快照解析失败: $e');
      return null;
    }
  }

  Future<void> upsertHospitalBrief(KrHospitalBrief brief) => _upsertPayload(
    'chat_hospital_cache',
    'hospital_id',
    brief.hospitalId,
    brief.toJson(),
  );

  /// 客户资料聚合快照
  Future<ClientProfile?> getClientProfile(int clientId) async {
    final payload = await _getPayload(
      'chat_client_cache',
      'client_id',
      clientId,
    );
    if (payload == null) return null;
    try {
      return ClientProfile.fromJson(payload);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] 客户快照解析失败: $e');
      return null;
    }
  }

  Future<void> upsertClientProfile(ClientProfile profile) => _upsertPayload(
    'chat_client_cache',
    'client_id',
    profile.clientId,
    profile.toJson(),
  );

  Future<Map<String, dynamic>?> _getPayload(
    String table,
    String idColumn,
    int id,
  ) async {
    try {
      final db = await _database;
      final rows = await db.query(
        table,
        where: '$idColumn = ?',
        whereArgs: [id],
        limit: 1,
      );
      final raw = rows.isEmpty ? null : rows.first['payload']?.toString();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] 读取 $table 失败: $e');
      return null;
    }
  }

  Future<void> _upsertPayload(
    String table,
    String idColumn,
    int id,
    Map<String, dynamic> payload,
  ) async {
    if (id <= 0) return;
    try {
      final db = await _database;
      await db.insert(table, {
        idColumn: id,
        'payload': jsonEncode(payload),
        'updated_at': _nowSeconds(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] 写入 $table 失败: $e');
    }
  }

  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ——————————————————— 退登清库 ———————————————————

  Future<void> clearAll() async {
    try {
      final db = await _database;
      final batch = db.batch();
      batch.delete('chat_message');
      batch.delete('chat_conversation');
      batch.delete('chat_sync_meta');
      batch.delete('chat_contact');
      batch.delete('chat_task_context');
      batch.delete('chat_hospital_cache');
      batch.delete('chat_client_cache');
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) print('[ChatLocalDb] clearAll 失败: $e');
    }
  }
}
