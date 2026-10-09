import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/services/api_client.dart';

/// 兼职用户「每日打卡」服务
///
/// 业务：兼职用户每天在兼职 Tab 底部点「开始兼职」调 [clockIn] 上班打卡
/// （上班时间以服务器实时时间为准），下班时点「结束兼职」弹表单（上下班时间
/// 可修改、上班日期锁定当天，选午休 / 交通费 / 报销单）调 [clockOut] 下班打卡；
/// 当天被驳回时「修改重交」走 [submitClock] 修正（可编辑时间）。一人一天一条记录。
///
/// 本地状态（仅用于网络返回前的按钮秒开渲染，权威状态以服务端 today 为准）：
/// - [_keyStartedAt]：上班时间 unix 秒；clock_in 成功后写入，下班/完成后清除
/// - [_keySubmittedDate]：提交日期 yyyy-MM-dd；当天有值即代表已完成，按钮隐藏
class ParttimeClockService {
  static final ParttimeClockService _instance =
      ParttimeClockService._internal();
  factory ParttimeClockService() => _instance;
  ParttimeClockService._internal();

  static const String _keyStartedAt = 'parttime_clock_started_at';
  static const String _keySubmittedDate = 'parttime_clock_submitted_date';

  /// 状态变更广播：开始 / 结束 / 提交后通知 UI 刷新
  final _changedController = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changedController.stream;

  /// 已开始打卡的时间戳；null 表示未开始
  Future<int?> getStartedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_keyStartedAt);
    return (v == null || v <= 0) ? null : v;
  }

  /// 当天是否已提交过（按本地日期 yyyy-MM-dd 判定）
  Future<bool> isSubmittedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySubmittedDate);
    if (raw == null || raw.isEmpty) return false;
    return raw == _todayDateString();
  }

  /// 上班打卡：调后端接口，上班时间以服务器实时时间为准
  ///
  /// 成功后把返回记录的 work_start_time 写入本地「进行中」缓存并广播刷新；
  /// 当天「被驳回」记录再次上班打卡会被后端重置为进行中并成功返回。
  ///
  /// ```
  /// POST /v1/parttime_clock/clock_in
  /// Authorization: Bearer <token>
  /// ```
  Future<({bool success, String? message, ParttimeRecord? record})>
      clockIn() async {
    try {
      final response = await ApiClient().post(
        '/v1/parttime_clock/clock_in',
        data: const <String, dynamic>{},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        ParttimeRecord? record;
        if (data['data'] is Map) {
          record = ParttimeRecord.fromJson(
            Map<String, dynamic>.from(data['data']),
          );
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _keyStartedAt,
          (record != null && record.workStartTime > 0)
              ? record.workStartTime
              : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        _changedController.add(null);
        return (success: true, message: null, record: record);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '上班打卡失败',
        record: null,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 上班打卡请求异常: $e');
      return (success: false, message: _extractMessage(e) ?? '网络异常', record: null);
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 上班打卡异常: $e');
      return (success: false, message: '上班打卡失败', record: null);
    }
  }

  /// 下班打卡：调后端接口，上下班时间由表单收集（上班默认 clock_in 时刻、
  /// 日期锁定当天仅可改时分，下班默认当前时间、可自由修改）
  ///
  /// 前置条件为当天已 [clockIn]（进行中）。成功后写入当天已完成标记并广播。
  ///
  /// 报销单块与交通费完全独立：`has_reimburse=true` 时联动写 un_parttime_expense
  /// 独立报销单（自带凭证/备注/审核状态）；false/缺省时后端不动已有报销单。
  ///
  /// ```
  /// POST /v1/parttime_clock/clock_out
  /// Authorization: Bearer <token>
  ///
  /// {
  ///   "work_start_time": 1753600000,
  ///   "work_end_time": 1753632000,
  ///   "has_lunch_break": true,
  ///   "has_expense": true,
  ///   "expense_amount": 3000,           // has_expense=false 时不传
  ///   "has_reimburse": true,            // 报销单，缺省 false
  ///   "reimburse_amount": 48000,        // has_reimburse=true 时必填 >0
  ///   "voucher_urls": ["https://..."],  // 凭证 ≤9 张，选填
  ///   "reimburse_remark": "客户接待餐费" // ≤500 字，选填
  /// }
  /// ```
  Future<({bool success, String? message})> clockOut({
    required int workStartTime,
    required int workEndTime,
    required bool hasLunchBreak,
    required bool hasExpense,
    int? expenseAmount,
    bool hasReimburse = false,
    int? reimburseAmount,
    List<String>? voucherUrls,
    String? reimburseRemark,
  }) async {
    try {
      final body = <String, dynamic>{
        'work_start_time': workStartTime,
        'work_end_time': workEndTime,
        'has_lunch_break': hasLunchBreak,
        'has_expense': hasExpense,
      };
      if (hasExpense && expenseAmount != null) {
        body['expense_amount'] = expenseAmount;
      }
      if (hasReimburse) {
        body['has_reimburse'] = true;
        body['reimburse_amount'] = reimburseAmount;
        if (voucherUrls != null && voucherUrls.isNotEmpty) {
          body['voucher_urls'] = voucherUrls;
        }
        if (reimburseRemark != null && reimburseRemark.isNotEmpty) {
          body['reimburse_remark'] = reimburseRemark;
        }
      }
      final response = await ApiClient().post(
        '/v1/parttime_clock/clock_out',
        data: body,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        // 已提交标记按上班时间推导日期（与 submitClock 一致），非提交时刻
        await _markSubmitted(workStartTime);
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '下班打卡失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 下班打卡请求异常: $e');
      return (success: false, message: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 下班打卡异常: $e');
      return (success: false, message: '下班打卡失败');
    }
  }

  /// 主动清除开始状态（取消打卡场景，目前未暴露入口）
  Future<void> clearStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStartedAt);
    _changedController.add(null);
  }

  /// 清除全部本地打卡缓存（开始时间 + 当天已提交标记）。
  /// 退出登录 / 切换账号时调用，避免上个账号的状态残留到下个账号。
  Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStartedAt);
    await prefs.remove(_keySubmittedDate);
    _changedController.add(null);
  }

  /// 提交 / 修改打卡：调后端接口，成功后清空开始状态、写入提交日期
  ///
  /// 新增与编辑共用同一接口、同一组入参（无需传 id）：后端按
  /// `(当前用户, work_date)` 定位记录，work_date 由 [workStartTime] 推导。
  /// 当天那条「已驳回」记录会被自动命中、更新并重置为待审核；返回 `is_update`
  /// 标识本次是修改驳回记录（true）还是新增（false）。
  ///
  /// ```
  /// POST /v1/parttime_clock/submit
  /// Authorization: Bearer <token>
  ///
  /// {
  ///   "work_start_time": 1779000000,
  ///   "work_end_time":   1779036000,
  ///   "has_lunch_break": true,     // 是否午休，必填
  ///   "has_expense": true,
  ///   "expense_amount": 20         // has_expense=false 时不传
  /// }
  /// ```
  Future<({bool success, String? message, bool isUpdate})> submitClock({
    required int workStartTime,
    required int workEndTime,
    required bool hasLunchBreak,
    required bool hasExpense,
    int? expenseAmount,
  }) async {
    try {
      final body = <String, dynamic>{
        'work_start_time': workStartTime,
        'work_end_time': workEndTime,
        'has_lunch_break': hasLunchBreak,
        'has_expense': hasExpense,
      };
      if (hasExpense && expenseAmount != null) {
        body['expense_amount'] = expenseAmount;
      }
      final response = await ApiClient().post(
        '/v1/parttime_clock/submit',
        data: body,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        final inner = data['data'];
        final isUpdate = inner is Map && inner['is_update'] == true;
        await _markSubmitted(workStartTime);
        return (success: true, message: null, isUpdate: isUpdate);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '提交失败',
        isUpdate: false,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 提交请求异常: $e');
      return (
        success: false,
        message: _extractMessage(e) ?? '网络异常',
        isUpdate: false,
      );
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 提交异常: $e');
      return (success: false, message: '提交失败', isUpdate: false);
    }
  }

  /// 查询当前登录兼职用户「当天是否已打卡」（权威状态）
  ///
  /// 本地 [_keySubmittedDate] 在卸载重装 / 切换账号后会失真，底部按钮显隐
  /// 应以本接口为准。拉取成功后顺带把服务端结果回写本地缓存，保证后续离线
  /// 判定一致；拉取失败则返回带 errorMessage 的对象，调用方回退本地缓存。
  ///
  /// ```
  /// GET /v1/parttime_clock/today
  /// Authorization: Bearer <token>
  /// ```
  Future<ParttimeTodayStatus> fetchTodayStatus() async {
    // 无 token 时（如退出登录清理本地缓存触发 onChanged 时）直接短路，
    // 不发起请求，避免 401 触发"登录已失效"提示。
    final token = await ApiClient().getAccessToken();
    if (token == null || token.isEmpty) {
      return ParttimeTodayStatus.error('未登录');
    }
    try {
      final response = await ApiClient().get('/v1/parttime_clock/today');
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final status = ParttimeTodayStatus.fromJson(
          Map<String, dynamic>.from(data['data']),
        );
        // 以服务端为准校正本地缓存
        await _syncSubmittedFromServer(status);
        return status;
      }
      return ParttimeTodayStatus.error(
        (data is Map ? data['msg']?.toString() : null) ?? '查询打卡状态失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询当天状态请求异常: $e');
      return ParttimeTodayStatus.error(_extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询当天状态失败: $e');
      return ParttimeTodayStatus.error('查询打卡状态失败');
    }
  }

  /// 用服务端当天状态校正本地缓存：
  /// - 已完成且不可再提交：写入当天已提交标记并清掉「进行中」开始时间
  /// - 进行中（clocked_in）：用服务端上班时间校正本地开始时间
  /// - 其余（无记录 / 被驳回）：清掉可能残留的脏标记（卸载重装 / 切号场景）
  Future<void> _syncSubmittedFromServer(ParttimeTodayStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayDateString();
    if (status.hasClock && !status.canSubmit) {
      await prefs.setString(_keySubmittedDate, today);
      await prefs.remove(_keyStartedAt);
    } else {
      if (prefs.getString(_keySubmittedDate) == today) {
        await prefs.remove(_keySubmittedDate);
      }
      final serverStart = status.record?.workStartTime ?? 0;
      if (status.isClockedIn && serverStart > 0) {
        await prefs.setInt(_keyStartedAt, serverStart);
      } else if (!status.isClockedIn) {
        // 服务端非进行中（无记录/被驳回），本地「进行中」缓存已失真
        await prefs.remove(_keyStartedAt);
      }
    }
  }

  /// 查询某年某月的兼职打卡记录列表
  ///
  /// 接口示例（后端待定，前端按此格式发）：
  ///
  /// ```
  /// GET /v1/parttime_clock/records?month=2026-11
  /// Authorization: Bearer <token>
  /// ```
  ///
  /// 成功响应：
  /// ```
  /// {
  ///   "code": 0, "msg": "success",
  ///   "data": {
  ///     "month": "2026-11",
  ///     "list": [
  ///       {
  ///         "id": 123,
  ///         "work_date": "2026-11-15",
  ///         "work_start_time": 1779000000,
  ///         "work_end_time":   1779036000,
  ///         "has_expense": true,
  ///         "expense_amount": 20,
  ///         "add_time": 1779036100
  ///       }
  ///     ]
  ///   }
  /// }
  /// ```
  Future<ParttimeRecordPage> fetchMyRecords({
    required int year,
    required int month,
  }) async {
    // 无 token 时（如退出登录清理本地缓存触发 onChanged 重载列表时）直接短路，
    // 不发起请求，避免 401 触发"登录已失效"提示。静默返回空列表（不带
    // errorMessage），避免登出瞬间在即将销毁的页面上误弹 toast。
    final token = await ApiClient().getAccessToken();
    if (token == null || token.isEmpty) {
      return ParttimeRecordPage(list: const [], total: 0);
    }
    try {
      // 接口要求单个 month 参数，格式 YYYY-MM
      final monthStr = '$year-${month.toString().padLeft(2, '0')}';
      final response = await ApiClient().get(
        '/v1/parttime_clock/records',
        queryParameters: {'month': monthStr},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => ParttimeRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        // 接口按月全量返回，无分页 total，直接用列表长度
        return ParttimeRecordPage(list: list, total: list.length);
      }
      return ParttimeRecordPage(
        list: const [],
        total: 0,
        errorMessage:
            (data is Map ? data['msg']?.toString() : null) ?? '查询记录失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询记录请求异常: $e');
      return ParttimeRecordPage(
        list: const [],
        total: 0,
        errorMessage: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询记录失败: $e');
      return ParttimeRecordPage(
        list: const [],
        total: 0,
        errorMessage: '查询记录失败',
      );
    }
  }

  /// 查询某条打卡记录详情，并返回该打卡日期当天已完成的兼职任务
  ///
  /// ```
  /// GET /v1/parttime_clock/detail?id=123
  /// Authorization: Bearer <token>
  /// ```
  ///
  /// [fallback] 为列表已携带的记录，用于接口失败时降级渲染头部信息。
  Future<ParttimeClockDetail> fetchClockDetail({
    required int id,
    required ParttimeRecord fallback,
  }) async {
    try {
      final response = await ApiClient().get(
        '/v1/parttime_clock/detail',
        queryParameters: {'id': id},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        return ParttimeClockDetail.fromJson(
          Map<String, dynamic>.from(data['data']),
        );
      }
      return ParttimeClockDetail.error(
        fallback,
        (data is Map ? data['msg']?.toString() : null) ?? '查询详情失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询详情请求异常: $e');
      return ParttimeClockDetail.error(fallback, _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[ParttimeClock] 查询详情失败: $e');
      return ParttimeClockDetail.error(fallback, '查询详情失败');
    }
  }

  /// 标记某次提交对应的工作日期（由 work_start_time 推导）。
  /// 编辑历史驳回记录时不会误标今天，今日按钮显隐仍以服务端 today 为准。
  Future<void> _markSubmitted(int workStartTime) async {
    final prefs = await SharedPreferences.getInstance();
    final d = DateTime.fromMillisecondsSinceEpoch(workStartTime * 1000);
    String pad(int v) => v.toString().padLeft(2, '0');
    final dateStr = '${d.year}-${pad(d.month)}-${pad(d.day)}';
    await prefs.setString(_keySubmittedDate, dateStr);
    await prefs.remove(_keyStartedAt);
    _changedController.add(null);
  }

  String _todayDateString() {
    final d = DateTime.now();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)}';
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
}
