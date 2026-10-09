import 'package:flutter/foundation.dart';
import 'package:yatai_hub/models/chat_query.dart';
import 'package:yatai_hub/services/api_client.dart';
import 'package:yatai_hub/services/chat_local_db.dart';
import 'package:yatai_hub/services/part_time_task_service.dart';
import 'package:yatai_hub/services/schedule_api.dart';

/// 群聊内「医院信息查询 / 客户资料查询」的数据编排层
///
/// 统一「先本地秒显、再网络刷新」：本地快照存在就先回调一次，网络成功后再回调
/// 一次并写库；网络失败时保留本地值，只在完全没有缓存时对外报错。
///
/// 快照落 [ChatLocalDb] 的 chat_task_context / chat_hospital_cache /
/// chat_client_cache 三张表，退登随 `clearAll()` 一起清掉。
///
/// 除 [PartTimeTaskService] / [ScheduleApi] 外只直接用 [ApiClient] 打接口，
/// **不依赖客服 / 商务模块的 service**，便于整份搬到姊妹项目 yatai-hub。
class ChatContextService {
  static final ChatContextService _instance = ChatContextService._internal();
  factory ChatContextService() => _instance;
  ChatContextService._internal();

  final ChatLocalDb _db = ChatLocalDb();

  // ——————————————————— 任务上下文 ———————————————————

  /// 本地任务上下文（进群聊时先用它决定菜单，不等网络）
  Future<ChatTaskContext?> localContext(int taskId) =>
      _db.getTaskContext(taskId);

  /// 拉一次 `/v1/parttime_task/detail` 刷新任务上下文并写库。
  ///
  /// 失败（无权限 / 网络异常）时返回本地值，没有本地值则返回 null。
  Future<ChatTaskContext?> refreshContext(int taskId) async {
    final r = await PartTimeTaskService.getDetail(taskId);
    final d = r.detail;
    if (d == null) {
      if (kDebugMode) print('[ChatContext] 任务 $taskId 详情拉取失败: ${r.message}');
      return _db.getTaskContext(taskId);
    }
    final ctx = ChatTaskContext(
      taskId: taskId,
      clientId: d.clientId,
      hospitalId: d.hospitalId,
      // 老数据里医院名可能是 "0" 之类的占位，清洗后才好当标题兜底
      hospitalName: cleanQueryText(d.hospitalName),
    );
    await _db.upsertTaskContext(ctx);
    return ctx;
  }

  // ——————————————————— 医院信息 ———————————————————

  Future<KrHospitalBrief?> localHospital(int hospitalId) =>
      _db.getHospitalBrief(hospitalId);

  /// 拉医院详情，只取 basic_info 的展示字段写入缓存
  /// （返点/财务、CRM 账密、收款码、联系人电话等节点不解析也不落地）
  Future<KrHospitalBrief?> refreshHospital(int hospitalId) async {
    try {
      final resp = await ApiClient().dio.get(
        '/v1/kr_hospital/detail',
        queryParameters: {'hospital_id': hospitalId},
      );
      final data = resp.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final brief = KrHospitalBrief.fromDetailJson(
          Map<String, dynamic>.from(data['data'] as Map),
        );
        // 详情接口没回 hospital_id 时用入参兜底，保证缓存主键正确
        final fixed = brief.hospitalId > 0
            ? brief
            : KrHospitalBrief(
                hospitalId: hospitalId,
                nameCn: brief.nameCn,
                nameKr: brief.nameKr,
                nameEn: brief.nameEn,
                alias: brief.alias,
                addressCn: brief.addressCn,
                addressKr: brief.addressKr,
                url: brief.url,
                statusLabel: brief.statusLabel,
              );
        await _db.upsertHospitalBrief(fixed);
        return fixed;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 医院详情拉取失败: $e');
      return null;
    }
  }

  // ——————————————————— 客户资料 ———————————————————

  Future<ClientProfile?> localClient(int clientId) =>
      _db.getClientProfile(clientId);

  /// 并发拉取客户资料 / 派单医院 / 档案 / 预约 / 成交，任一失败该区块降级为空，
  /// 其余照常展示；全空则返回 null（不覆盖已有缓存）。
  Future<ClientProfile?> refreshClient(int clientId) async {
    final results = await Future.wait([
      _fetchBasic(clientId),
      _fetchDispatches(clientId),
      _fetchArchives(clientId),
      _fetchAppointments(clientId),
      _fetchDeals(clientId),
    ]);

    final basic = results[0] as ClientBasicInfo?;
    final dispatches = results[1] as List<ClientDispatchItem>;
    final archives = results[2] as List<ClientArchiveItem>;
    final appointments = results[3] as List<ClientAppointmentItem>;
    final deals = results[4] as List<ClientDealItem>;

    final profile = ClientProfile(
      clientId: clientId,
      basic: basic,
      dispatches: dispatches,
      archives: archives,
      appointments: appointments,
      deals: deals,
    );
    if (profile.isEmpty) return null;
    await _db.upsertClientProfile(profile);
    return profile;
  }

  /// 客户资料：客服系统详情页同款专用接口（单对象返回，字段名已确认）
  Future<ClientBasicInfo?> _fetchBasic(int clientId) async {
    try {
      final resp = await ApiClient().dio.get(
        '/v1/kefu/client/detail',
        queryParameters: {'client_id': clientId},
      );
      final data = resp.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data'] as Map);
        final basic = ClientBasicInfo.fromApi(inner);
        // detail 未回 client_id 时用入参兜底，保证弹窗第一行有值
        return basic.clientId > 0
            ? basic
            : ClientBasicInfo(
                clientId: clientId,
                name: basic.name,
                kefuName: basic.kefuName,
                fromTypeName: basic.fromTypeName,
                fromTypeValue: basic.fromTypeValue,
                editName: basic.editName,
                registerTimeText: basic.registerTimeText,
              );
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 客户资料拉取失败: $e');
      return null;
    }
  }

  Future<List<ClientDispatchItem>> _fetchDispatches(int clientId) async {
    try {
      final resp = await ApiClient().dio.get(
        '/v1/kefu/order/list',
        queryParameters: {'client_id': clientId},
      );
      final data = resp.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final list = (data['data'] as Map)['list'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map(
                (e) => ClientDispatchItem.fromApi(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      }
      return const [];
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 派单列表拉取失败: $e');
      return const [];
    }
  }

  Future<List<ClientArchiveItem>> _fetchArchives(int clientId) async {
    try {
      final resp = await ApiClient().dio.post(
        '/v1/archives/list',
        data: {'client_id': clientId, 'archives_id': 0},
      );
      final data = resp.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final list = (data['data'] as Map)['list_data'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map(
                (e) => ClientArchiveItem.fromApi(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      }
      return const [];
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 档案列表拉取失败: $e');
      return const [];
    }
  }

  Future<List<ClientAppointmentItem>> _fetchAppointments(int clientId) async {
    try {
      final resp = await ApiClient().dio.get(
        '/v1/appoint/list',
        queryParameters: {'client_id': clientId, 'page': 1, 'page_size': 20},
      );
      final data = resp.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final list = (data['data'] as Map)['list'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map(
                (e) =>
                    ClientAppointmentItem.fromApi(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      }
      return const [];
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 预约列表拉取失败: $e');
      return const [];
    }
  }

  /// 成交（消费）：客户维度用 client_id + archives_id=0，与客服系统详情页一致
  Future<List<ClientDealItem>> _fetchDeals(int clientId) async {
    try {
      final list = await ScheduleApi.getPayList(
        clientId: '$clientId',
        archivesId: '0',
        guestId: '0',
      );
      return list.map(ClientDealItem.fromPayListItem).toList();
    } catch (e) {
      if (kDebugMode) print('[ChatContext] 消费记录拉取失败: $e');
      return const [];
    }
  }
}
