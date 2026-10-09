import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'package:yatai_hub/models/order_entry_meta.dart';
import 'package:yatai_hub/models/pay_list_item.dart';

/// 日程API服务
class ScheduleApi {
  static final Dio _client = ApiClient().dio;

  /// 保存护照信息（关联到档案）
  static Future<bool> savePassport({
    required String contractUrl,
    required String contractName,
    required int archivesId,
  }) async {
    try {
      if (kDebugMode) {
        print(
          '[保存护照] 请求: contractUrl=$contractUrl, contractName=$contractName, archivesId=$archivesId',
        );
      }

      final response = await _client.post(
        '/v1/crm/save-passport',
        data: {
          'contract_url': contractUrl,
          'contract_name': contractName,
          'archives_id': archivesId,
        },
      );

      if (kDebugMode) {
        print('[保存护照] 响应: ${response.data}');
      }

      final resData = response.data;
      return resData['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('[保存护照] 失败: $e');
      return false;
    }
  }

  /// 删除录单（消费记录）
  static Future<bool> deleteOrder({required int id}) async {
    try {
      if (kDebugMode) print('[删除录单] 请求: id=$id');
      final response = await _client.post(
        '/v1/crm/delete-order',
        data: {'id': id},
      );
      if (kDebugMode) print('[删除录单] 响应: ${response.data}');
      final resData = response.data;
      return resData['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('[删除录单] 失败: $e');
      return false;
    }
  }

  /// 删除护照
  static Future<bool> deletePassport({required int hospitalContractId}) async {
    try {
      if (kDebugMode) {
        print('[删除护照] 请求: hospitalContractId=$hospitalContractId');
      }

      final response = await _client.post(
        '/v1/crm/delete-passport',
        data: {'hospital_contract_id': hospitalContractId},
      );

      if (kDebugMode) {
        print('[删除护照] 响应: ${response.data}');
      }

      final resData = response.data;
      return resData['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('[删除护照] 失败: $e');
      return false;
    }
  }

  /// 获取日程列表（新接口）
  /// [startDate] 开始日期（格式：2026-03-06）
  /// [endDate] 结束日期（格式：2026-03-06）
  static Future<Map<String, dynamic>?> getTodaySchedule({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final Map<String, dynamic> params = {};

      if (startDate != null && startDate.isNotEmpty) {
        params['start_date'] = startDate;
      }

      if (endDate != null && endDate.isNotEmpty) {
        params['end_date'] = endDate;
      }

      final response = await _client.get(
        '/v1/schedule/list',
        queryParameters: params,
      );

      if (kDebugMode) {
        print('[日程列表] 响应: ${response.data}');
      }

      if (response.data['code'] == 0) {
        return response.data;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[日程列表] 获取失败: $e');
      rethrow;
    }
  }

  /// 获取录单元数据
  static Future<OrderEntryMeta?> getOrderEntryMeta() async {
    try {
      final response = await _client.get('/v1/order-entry/meta');

      if (kDebugMode) {
        print('[录单元数据] 响应: ${response.data}');
      }

      final resData = response.data;
      if (resData['code'] == 0 && resData['data'] != null) {
        return OrderEntryMeta.fromJson(resData['data']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[录单元数据] 获取失败: $e');
      return null;
    }
  }

  /// 获取录单列表
  ///
  /// [clientId] 非空时按「客户维度」查该客户全部消费/成交记录
  /// （客服系统详情页口径：client_id + archives_id=0），默认按档案维度查。
  static Future<List<PayListItem>> getPayList({
    required String archivesId,
    required String guestId,
    String clientId = '',
  }) async {
    try {
      final response = await _client.get(
        '/v1/schedule/paylist',
        queryParameters: {
          'archives_id': archivesId,
          'guest_id': guestId,
          if (clientId.isNotEmpty && clientId != '0') 'client_id': clientId,
        },
      );

      if (kDebugMode) {
        print('[录单列表] 响应: ${response.data}');
      }

      final resData = response.data;
      if (resData['code'] == 0 && resData['data'] != null) {
        final data = resData['data'];
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map && data['list'] is List) {
          list = data['list'];
        } else {
          list = [];
        }
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => PayListItem.fromJson(item))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[录单列表] 获取失败: $e');
      return [];
    }
  }

  /// 获取客户关联医院列表
  static Future<List<Map<String, dynamic>>> getClientHospitals(
    int clientId,
  ) async {
    try {
      final response = await _client.get(
        '/v1/crm/client-hospitals',
        queryParameters: {'client_id': clientId},
      );

      if (kDebugMode) {
        print('[客户医院] 响应: ${response.data}');
      }

      final resData = response.data;
      if (resData['code'] == 0 && resData['data'] != null) {
        final List<dynamic> list = resData['data'] is List
            ? resData['data']
            : [];
        return list.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[客户医院] 获取失败: $e');
      return [];
    }
  }

  /// 获取编辑录单初始化数据
  static Future<Map<String, dynamic>?> getEditOrderInit(int id) async {
    try {
      if (kDebugMode) print('[编辑录单初始化] 请求: id=$id');
      final response = await _client.get(
        '/v1/crm/kr-edit-order-init',
        queryParameters: {'id': id},
      );
      if (kDebugMode) print('[编辑录单初始化] 响应: ${response.data}');
      final resData = response.data;
      if (resData['code'] == 0 && resData['data'] != null) {
        return resData['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[编辑录单初始化] 失败: $e');
      return null;
    }
  }

  /// 提交录单
  static Future<String?> submitOrderEntry(Map<String, dynamic> data) async {
    try {
      if (kDebugMode) {
        print('[提交录单] 请求: $data');
      }

      final response = await _client.post(
        '/v1/order-entry/kr-edit',
        data: data,
      );

      if (kDebugMode) {
        print('[提交录单] 响应: ${response.data}');
      }

      final resData = response.data;
      if (resData['code'] == 0) {
        return null;
      }
      return resData['msg'] ?? resData['message'] ?? '提交失败，请重试';
    } on DioException catch (e) {
      if (kDebugMode) print('[提交录单] API异常: $e');
      if (e.response?.data is Map) {
        final resData = e.response!.data as Map;
        return resData['msg'] ?? resData['message'] ?? '网络异常，请重试';
      }
      return '网络异常，请重试';
    } catch (e) {
      if (kDebugMode) print('[提交录单] 失败: $e');
      return '发生异常，请重试';
    }
  }

  /// 文本智能识别（录单内容）
  static Future<Map<String, dynamic>?> textRecognize(String text) async {
    try {
      if (kDebugMode) print('[文本识别] 请求: text=$text');
      final response = await _client.post(
        '/v1/crm/text-recognize',
        data: {'text': text},
      );
      if (kDebugMode) print('[文本识别] 响应: ${response.data}');
      final resData = response.data;
      if (resData['code'] == 0 && resData['data'] != null) {
        return resData['data']['message'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[文本识别] 失败: $e');
      return null;
    }
  }
}
