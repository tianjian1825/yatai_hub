import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/models/settlement.dart';
import 'package:yatai_hub/services/api_client.dart';

/// 兼职「钱包 / 结算」服务（前缀 /v1/settlement，仅兼职人员 roleid=275）
///
/// 统一返回 `{ code, msg, data }`，code=0 成功。后端 msg 已是中文提示，
/// 自定义错误码（4003 非兼职 / 4001 有打工证不可提现 / 2001 无可结算 /
/// 2002 金额已变动 / 4004 结算单不存在）直接透传 msg 给 UI 展示。
class SettlementService {
  static final SettlementService _instance = SettlementService._internal();
  factory SettlementService() => _instance;
  SettlementService._internal();

  static const String _prefix = '/v1/settlement';

  // 钱包首页本地缓存（总览 + 收款账号），冷启动秒显、断网兜底
  static const String _cacheKeySummary = 'cached_wallet_summary';
  static const String _cacheKeyPayment = 'cached_payment_info';

  /// 读取缓存的钱包总览（无缓存或解析失败返回 null）
  Future<WalletSummary?> cachedWalletSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKeySummary);
      if (raw == null || raw.isEmpty) return null;
      return WalletSummary.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] 读取钱包总览缓存失败: $e');
      return null;
    }
  }

  /// 读取缓存的收款账号（无缓存或解析失败返回 null）
  Future<PaymentInfo?> cachedPaymentInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKeyPayment);
      if (raw == null || raw.isEmpty) return null;
      return PaymentInfo.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] 读取收款账号缓存失败: $e');
      return null;
    }
  }

  Future<void> _cacheSummary(WalletSummary s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeySummary, jsonEncode(s.toJson()));
    } catch (e) {
      if (kDebugMode) print('[Settlement] 写入钱包总览缓存失败: $e');
    }
  }

  Future<void> _cachePayment(PaymentInfo p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyPayment, jsonEncode(p.toJson()));
    } catch (e) {
      if (kDebugMode) print('[Settlement] 写入收款账号缓存失败: $e');
    }
  }

  /// 清除钱包本地缓存（退登时调用，避免跨账号串数据）
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKeySummary);
      await prefs.remove(_cacheKeyPayment);
    } catch (e) {
      if (kDebugMode) print('[Settlement] 清除钱包缓存失败: $e');
    }
  }

  /// 钱包总览 GET /wallet_summary
  Future<({WalletSummary? data, String? error})> fetchWalletSummary() async {
    try {
      final response = await ApiClient().get('$_prefix/wallet_summary');
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final summary = WalletSummary.fromJson(
          Map<String, dynamic>.from(data['data']),
        );
        await _cacheSummary(summary);
        return (data: summary, error: null);
      }
      return (
        data: null,
        error: (data is Map ? data['msg']?.toString() : null) ?? '获取钱包信息失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] wallet_summary 异常: $e');
      return (data: null, error: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[Settlement] wallet_summary 失败: $e');
      return (data: null, error: '获取钱包信息失败');
    }
  }

  /// 收入流水 GET /income_flow
  Future<IncomeFlowPage> fetchIncomeFlow({
    String? month,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final query = <String, dynamic>{'page': page, 'page_size': pageSize};
      if (month != null && month.isNotEmpty) query['month'] = month;
      final response = await ApiClient().get(
        '$_prefix/income_flow',
        queryParameters: query,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => IncomeFlowItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return IncomeFlowPage(
          list: list,
          total: _asInt(inner['total']) ?? 0,
          page: _asInt(inner['page']) ?? page,
          pageSize: _asInt(inner['page_size']) ?? pageSize,
        );
      }
      return IncomeFlowPage(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage:
            (data is Map ? data['msg']?.toString() : null) ?? '获取收入流水失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] income_flow 异常: $e');
      return IncomeFlowPage(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] income_flow 失败: $e');
      return IncomeFlowPage(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: '获取收入流水失败',
      );
    }
  }

  /// 可结算明细 GET /income_summary
  Future<
    ({
      double amount,
      int daysCount,
      bool canWithdraw,
      String withdrawTip,
      List<IncomeSummaryDay> list,
      String? error,
    })
  >
  fetchIncomeSummary({String? month}) async {
    try {
      final query = <String, dynamic>{};
      if (month != null && month.isNotEmpty) query['month'] = month;
      final response = await ApiClient().get(
        '$_prefix/income_summary',
        queryParameters: query,
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => IncomeSummaryDay.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (
          amount: _asDouble(inner['amount']),
          daysCount: _asInt(inner['days_count']) ?? 0,
          canWithdraw: _asBool(inner['can_withdraw']),
          withdrawTip: inner['withdraw_tip']?.toString() ?? '',
          list: list,
          error: null,
        );
      }
      return (
        amount: 0.0,
        daysCount: 0,
        canWithdraw: false,
        withdrawTip: '',
        list: const <IncomeSummaryDay>[],
        error: (data is Map ? data['msg']?.toString() : null) ?? '获取可结算明细失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] income_summary 异常: $e');
      return (
        amount: 0.0,
        daysCount: 0,
        canWithdraw: false,
        withdrawTip: '',
        list: const <IncomeSummaryDay>[],
        error: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] income_summary 失败: $e');
      return (
        amount: 0.0,
        daysCount: 0,
        canWithdraw: false,
        withdrawTip: '',
        list: const <IncomeSummaryDay>[],
        error: '获取可结算明细失败',
      );
    }
  }

  /// 结算/提现历史 GET /history
  Future<SettlementHistoryResult> fetchHistory({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await ApiClient().get(
        '$_prefix/history',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        final rawList = inner['list'];
        final list = (rawList is List ? rawList : const [])
            .whereType<Map>()
            .map((e) => SettlementRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return SettlementHistoryResult(
          list: list,
          total: _asInt(inner['total']) ?? 0,
          page: _asInt(inner['page']) ?? page,
          pageSize: _asInt(inner['page_size']) ?? pageSize,
        );
      }
      return SettlementHistoryResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage:
            (data is Map ? data['msg']?.toString() : null) ?? '获取结算记录失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] history 异常: $e');
      return SettlementHistoryResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: _extractMessage(e) ?? '网络异常',
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] history 失败: $e');
      return SettlementHistoryResult(
        list: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        errorMessage: '获取结算记录失败',
      );
    }
  }

  /// 结算单明细 GET /detail?id=（失败码 4004 结算单不存在）
  Future<({SettlementDetail? data, String? error})> fetchDetail({
    required int id,
  }) async {
    try {
      final response = await ApiClient().get(
        '$_prefix/detail',
        queryParameters: {'id': id},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        return (
          data: SettlementDetail.fromJson(
            Map<String, dynamic>.from(data['data']),
          ),
          error: null,
        );
      }
      return (
        data: null,
        error: (data is Map ? data['msg']?.toString() : null) ?? '结算单不存在',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] detail 异常: $e');
      return (data: null, error: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[Settlement] detail 失败: $e');
      return (data: null, error: '获取结算单详情失败');
    }
  }

  /// 查询收款账号 GET /payment_info
  Future<({PaymentInfo? data, String? error})> fetchPaymentInfo() async {
    try {
      final response = await ApiClient().get('$_prefix/payment_info');
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final info = PaymentInfo.fromJson(
          Map<String, dynamic>.from(data['data']),
        );
        await _cachePayment(info);
        return (data: info, error: null);
      }
      return (
        data: null,
        error: (data is Map ? data['msg']?.toString() : null) ?? '获取收款账号失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] payment_info GET 异常: $e');
      return (data: null, error: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[Settlement] payment_info GET 失败: $e');
      return (data: null, error: '获取收款账号失败');
    }
  }

  /// 设置收款账号 POST /payment_info（账号/姓名都必填，后端校验空值与超长）
  Future<({PaymentInfo? data, String? error})> savePaymentInfo({
    required String alipayAccount,
    required String alipayName,
  }) async {
    try {
      final response = await ApiClient().post(
        '$_prefix/payment_info',
        data: {'alipay_account': alipayAccount, 'alipay_name': alipayName},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final info = PaymentInfo.fromJson(
          Map<String, dynamic>.from(data['data']),
        );
        await _cachePayment(info);
        return (data: info, error: null);
      }
      return (
        data: null,
        error: (data is Map ? data['msg']?.toString() : null) ?? '保存收款账号失败',
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] payment_info POST 异常: $e');
      return (data: null, error: _extractMessage(e) ?? '网络异常');
    } catch (e) {
      if (kDebugMode) print('[Settlement] payment_info POST 失败: $e');
      return (data: null, error: '保存收款账号失败');
    }
  }

  /// 发起提现 POST /apply_withdrawal（无 body，金额由服务端汇总）
  ///
  /// 失败码：4001 有打工证 / 2001 无可结算 / 2002 金额已变动 /
  /// 4005 未设置收款账号。[code] 透出供 UI 区分（如 4005 引导去设置）。
  Future<
    ({
      bool success,
      int code,
      String? message,
      int? settlementId,
      double amount,
    })
  >
  applyWithdrawal() async {
    try {
      final response = await ApiClient().post('$_prefix/apply_withdrawal');
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final inner = Map<String, dynamic>.from(data['data']);
        return (
          success: true,
          code: 0,
          message: null,
          settlementId: _asInt(inner['settlement_id']),
          amount: _asDouble(inner['amount']),
        );
      }
      return (
        success: false,
        code: (data is Map ? _asInt(data['code']) : null) ?? -1,
        message: (data is Map ? data['msg']?.toString() : null) ?? '提现申请失败',
        settlementId: null,
        amount: 0.0,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('[Settlement] apply_withdrawal 异常: $e');
      return (
        success: false,
        code: -1,
        message: _extractMessage(e) ?? '网络异常',
        settlementId: null,
        amount: 0.0,
      );
    } catch (e) {
      if (kDebugMode) print('[Settlement] apply_withdrawal 失败: $e');
      return (
        success: false,
        code: -1,
        message: '提现申请失败',
        settlementId: null,
        amount: 0.0,
      );
    }
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

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
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
