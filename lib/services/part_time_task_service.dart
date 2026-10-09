import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yatai_hub/models/part_time_task.dart';
import 'package:yatai_hub/services/api_client.dart';

/// 兼职任务接口
///
/// Base: /v1/parttime_task。多数接口仅 roleid==275 可调用（否则后端返回 code=1）。
/// 例外：[getDetail]（/detail）已放开为「兼职角色 或 该任务群成员」可只读，
/// 用于群聊跨角色查看任务详情；非成员非兼职仍返回无权限。
class PartTimeTaskService {
  static final ApiClient _client = ApiClient();

  /// 任务大厅列表（status=1 && assign_type=2）
  static Future<PartTimeTaskHallResult> getHall({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/hall',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => PartTimeTask.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return PartTimeTaskHallResult(
          list: list,
          total: (inner['total'] is int)
              ? inner['total']
              : int.tryParse(inner['total']?.toString() ?? '') ?? 0,
          page: (inner['page'] is int)
              ? inner['page']
              : int.tryParse(inner['page']?.toString() ?? '') ?? page,
          pageSize: (inner['page_size'] is int)
              ? inner['page_size']
              : int.tryParse(inner['page_size']?.toString() ?? '') ?? pageSize,
        );
      }
      // 业务错误（code != 0）
      final msg = (data is Map ? data['msg']?.toString() : null) ?? '获取任务大厅失败';
      return PartTimeTaskHallResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: msg,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('获取兼职大厅请求异常: $e');
      return PartTimeTaskHallResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('获取兼职大厅失败: $e');
      return PartTimeTaskHallResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: '获取任务大厅失败',
      );
    }
  }

  /// 我的任务列表（按 add_time 倒序，可按 status 筛选）
  static Future<PartTimeMyTasksResult> getMyTasks({
    int page = 1,
    int pageSize = 20,
    int? status,
  }) async {
    try {
      final query = <String, dynamic>{'page': page, 'page_size': pageSize};
      if (status != null) query['status'] = status;
      final response = await _client.get(
        '/v1/parttime_task/my_tasks',
        queryParameters: query,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map(
              (e) => PartTimeTaskDetail.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();
        return PartTimeMyTasksResult(
          list: list,
          total: (inner['total'] is int)
              ? inner['total']
              : int.tryParse(inner['total']?.toString() ?? '') ?? 0,
          page: (inner['page'] is int)
              ? inner['page']
              : int.tryParse(inner['page']?.toString() ?? '') ?? page,
          pageSize: (inner['page_size'] is int)
              ? inner['page_size']
              : int.tryParse(inner['page_size']?.toString() ?? '') ?? pageSize,
        );
      }
      // 业务错误（code != 0）
      final msg = (data is Map ? data['msg']?.toString() : null) ?? '获取我的任务失败';
      return PartTimeMyTasksResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: msg,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('获取我的兼职任务请求异常: $e');
      return PartTimeMyTasksResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('获取我的兼职任务失败: $e');
      return PartTimeMyTasksResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: '获取我的任务失败',
      );
    }
  }

  /// 任务详情
  ///
  /// 返回 (detail, message)；detail 为空时 message 携带错误原因。
  static Future<({PartTimeTaskDetail? detail, String? message})> getDetail(
    int taskId,
  ) async {
    try {
      final response = await _client.get(
        '/v1/parttime_task/detail',
        queryParameters: {'task_id': taskId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        return (detail: PartTimeTaskDetail.fromJson(inner), message: null);
      }
      return (
        detail: null,
        message: (data is Map ? data['msg']?.toString() : null) ?? '获取任务详情失败',
      );
    } on DioException catch (e) {
      return (detail: null, message: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('获取任务详情失败: $e');
      return (detail: null, message: '获取任务详情失败');
    }
  }

  /// 抢单
  ///
  /// 返回 (success, message)；success=true 时 message 始终为 null，
  /// 由前端自行决定成功文案（后端 msg 通常只是 "success"）。
  static Future<({bool success, String? message})> accept(int taskId) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/accept',
        data: {'task_id': taskId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '接单失败',
      );
    } on DioException catch (e) {
      return (success: false, message: _extractMessage(e) ?? '接单失败');
    } catch (e) {
      if (kDebugMode) print('接单失败: $e');
      return (success: false, message: '接单失败');
    }
  }

  /// 更新任务状态
  ///
  /// status: 4=已结束 5=已取消（3=已到院 已下线，接单后直接完成）
  /// cancelReason 仅 status==5 时传入。
  /// success=true 时 message 为 null，由前端自定义成功文案。
  static Future<({bool success, String? message})> updateStatus({
    required int taskId,
    required int status,
    String? cancelReason,
  }) async {
    try {
      final body = <String, dynamic>{'task_id': taskId, 'status': status};
      if (status == PartTimeTaskStatus.canceled && cancelReason != null) {
        body['cancel_reason'] = cancelReason;
      }
      final response = await _client.post(
        '/v1/parttime_task/update_status',
        data: body,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '操作失败',
      );
    } on DioException catch (e) {
      return (success: false, message: _extractMessage(e) ?? '操作失败');
    } catch (e) {
      if (kDebugMode) print('更新任务状态失败: $e');
      return (success: false, message: '操作失败');
    }
  }

  /// 提交 / 编辑兼职录单草稿
  ///
  /// [payload] 录单草稿内容，至少含 task_id / client_id(或 main_client_id) /
  /// hospital / verym_project / currency_type / number / pay_type / add_time。
  /// 不传 draft_id 或 draft_id=0 为新增；draft_id>0 为编辑。
  /// 返回 (success, draftId, message)。
  static Future<({bool success, int? draftId, String? message})>
  submitOrderDraft(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        '/v1/parttime_task/order_draft',
        data: payload,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        final inner = data['data'];
        final draftId = inner is Map ? _asIntStatic(inner['draft_id']) : null;
        return (success: true, draftId: draftId, message: null);
      }
      return (
        success: false,
        draftId: null,
        message: (data is Map ? data['msg']?.toString() : null) ?? '提交录单失败',
      );
    } on DioException catch (e) {
      return (
        success: false,
        draftId: null,
        message: _extractMessage(e) ?? '提交录单失败',
      );
    } catch (e) {
      if (kDebugMode) print('提交兼职录单草稿失败: $e');
      return (success: false, draftId: null, message: '提交录单失败');
    }
  }

  /// 删除录单草稿（物理删除，不可恢复）
  ///
  /// 仅未写入正式录单的草稿可删；已写入时后端返回
  /// 「消费记录已写入正式录单，不能删除」。
  static Future<({bool success, String? message})> deleteOrderDraft(
    int draftId,
  ) async {
    try {
      final response = await _client.delete(
        '/v1/parttime_task/order_draft',
        queryParameters: {'draft_id': draftId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '删除失败',
      );
    } on DioException catch (e) {
      return (success: false, message: _extractMessage(e) ?? '删除失败');
    } catch (e) {
      if (kDebugMode) print('删除兼职录单草稿失败: $e');
      return (success: false, message: '删除失败');
    }
  }

  static int? _asIntStatic(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// 提取 DioException 中 detail.msg / msg 错误信息
  static String? _extractMessage(DioException e) {
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
}
