import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yatai_hub/services/api_client.dart';

/// 兼职独立报销单操作服务（/v1/parttime_expense，仅兼职 roleid=275）
///
/// 报销单随下班打卡首次提交（clock_out 的 has_reimburse 块），后续的
/// 编辑 / 驳回重提 / 取消走本服务。查询在打卡详情里（data.expense）。
class ParttimeExpenseService {
  static final ParttimeExpenseService _instance =
      ParttimeExpenseService._internal();
  factory ParttimeExpenseService() => _instance;
  ParttimeExpenseService._internal();

  /// 提交 / 编辑 / 驳回重提报销单（共用一个接口，按 expense_id 区分）
  ///
  /// [expenseId] 0=新增（此时 [clockId] 必填）；>0=编辑或驳回后重提，
  /// 重提会重置为待审核并清空驳回原因。仅有效（未取消）且未通过审核可改。
  ///
  /// ```
  /// POST /v1/parttime_expense/save
  /// { "expense_id": 88, "amount": 50000,
  ///   "voucher_urls": ["https://..."], "remark": "餐费" }
  /// ```
  /// 返回 data: { expense_id, action(create/edit) }
  Future<({bool success, String? message})> save({
    int expenseId = 0,
    int clockId = 0,
    required int amount,
    required List<String> voucherUrls,
    String? remark,
  }) async {
    try {
      final body = <String, dynamic>{
        'expense_id': expenseId,
        'amount': amount,
        'voucher_urls': voucherUrls,
      };
      if (expenseId <= 0) body['clock_id'] = clockId;
      if (remark != null && remark.isNotEmpty) body['remark'] = remark;
      final response = await ApiClient().post(
        '/v1/parttime_expense/save',
        data: body,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '报销单提交失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeExpense] 保存请求异常: $e');
      return (success: false, message: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[ParttimeExpense] 保存异常: $e');
      return (success: false, message: '报销单提交失败');
    }
  }

  /// 取消报销单（终态 status=2 不可恢复；仅待审核 / 已驳回可取消，
  /// 已通过审核不可取消）
  ///
  /// ```
  /// POST /v1/parttime_expense/cancel
  /// { "expense_id": 88 }
  /// ```
  Future<({bool success, String? message})> cancel({
    required int expenseId,
  }) async {
    try {
      final response = await ApiClient().post(
        '/v1/parttime_expense/cancel',
        data: {'expense_id': expenseId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: (data is Map ? data['msg']?.toString() : null) ?? '取消失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[ParttimeExpense] 取消请求异常: $e');
      return (success: false, message: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[ParttimeExpense] 取消异常: $e');
      return (success: false, message: '取消失败');
    }
  }

  /// 从 DioException 响应体中提取后端业务错误文案
  String? _extractMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['msg'] != null) return data['msg'].toString();
    return null;
  }
}
