import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/hospital.dart';
import '../models/department.dart';
import 'api_client.dart';

/// 素材上传相关 API
class MaterialApi {
  static final ApiClient _client = ApiClient();

  /// 搜索医院（普通搜索）
  ///
  /// [keyword] 搜索关键词
  /// [cancelToken] 用于取消在途请求，避免快速输入时的并发与乱序返回
  ///
  /// 失败时向上抛出异常（包含取消异常），由调用方区分处理。
  static Future<List<Hospital>> searchHospital(
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get(
      '/v1/hospital_info/searchHospitalByName',
      queryParameters: {'hospital_name': keyword},
      cancelToken: cancelToken,
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );

    if (response.data['code'] == 0 && response.data['data'] != null) {
      // 从 data.new_name_list 获取医院列表
      final data = response.data['data'];
      if (data is Map && data['new_name_list'] != null) {
        final List<dynamic> list = data['new_name_list'] as List<dynamic>;
        return list
            .map((item) => Hospital.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// 搜索机构（跟进模块专用）
  ///
  /// GET /v1/kefu/bd/hospital/list
  static Future<List<Hospital>> searchBdHospital(String keyword) async {
    try {
      final response = await _client.get(
        '/v1/kefu/bd/hospital/list',
        queryParameters: {'hospital_name': keyword},
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        final data = response.data['data'];
        List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map && data['list'] != null) {
          list = data['list'] as List<dynamic>;
        } else {
          return [];
        }
        return list.map((item) {
          final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
          // 接口返回 hospital_name，映射到 Hospital 模型的 name 字段
          map['name'] = map['hospital_name'] ?? map['name'] ?? '';
          return Hospital.fromJson(map);
        }).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('搜索机构失败(BD): $e');
      }
      return [];
    }
  }

  /// 搜索医院（价格表专用）
  ///
  /// [keyword] 搜索关键词
  /// [cancelToken] 用于取消在途请求，避免快速输入时的并发与乱序返回
  ///
  /// 失败时向上抛出异常（包含取消异常），由调用方区分处理。
  static Future<List<Hospital>> searchPriceHospital(
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get(
      '/v1/hospital_info/searchPriceHospitalByName',
      queryParameters: {'hospital_name': keyword},
      cancelToken: cancelToken,
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );

    if (response.data['code'] == 0 && response.data['data'] != null) {
      // 从 data.new_name_list 获取医院列表
      final data = response.data['data'];
      if (data is Map && data['new_name_list'] != null) {
        final List<dynamic> list = data['new_name_list'] as List<dynamic>;
        return list
            .map((item) => Hospital.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// 获取部门可见范围列表
  static Future<List<Department>> getDepartments() async {
    try {
      final response = await _client.post('/v1/casually/get_departs');

      if (response.data['code'] == 0 && response.data['data'] != null) {
        final List<dynamic> list = response.data['data'] as List<dynamic>;
        return list
            .map((item) => Department.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('获取部门列表失败: $e');
      }
      return [];
    }
  }

  /// 提交素材
  ///
  /// [data] 素材数据
  static Future<Map<String, dynamic>?> submitMaterial(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client.post(
        '/v1/casually/upload_new',
        data: data,
      );

      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('提交素材失败: $e');
      }
      return null;
    }
  }

  /// 获取跟进列表
  ///
  /// GET /v1/customer_service/bd/hospital/followup/list
  static Future<Map<String, dynamic>?> getFollowUpList({
    String? hospitalName,
    int? startTime,
    int? endTime,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _client.get(
        '/v1/kefu/bd/hospital/followup/list',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          if (hospitalName != null && hospitalName.isNotEmpty)
            'hospital_name': hospitalName,
          'start_time': ?startTime,
          'end_time': ?endTime,
        },
      );
      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('获取跟进列表失败: $e');
      return null;
    }
  }

  /// 提交跟进记录
  ///
  /// POST /v1/kefu/bd/hospital/followup
  static Future<Map<String, dynamic>?> submitFollowUp(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client.post(
        '/v1/kefu/bd/hospital/followup',
        data: data,
      );

      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('提交跟进失败: $e');
      }
      return null;
    }
  }

  /// 获取上传历史
  ///
  /// [data] 分页和筛选参数
  static Future<Map<String, dynamic>?> getUploadHistory(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client.post(
        '/v1/casually/upload_history_new',
        data: data,
      );

      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('获取上传历史失败: $e');
      }
      return null;
    }
  }

  /// 删除上传记录
  ///
  /// [id] 记录ID
  static Future<bool> deleteUploadHistory(int id) async {
    try {
      final response = await _client.post(
        '/v1/casually/delete_upload_one',
        data: {'id': id},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) {
        print('删除上传记录失败: $e');
      }
      return false;
    }
  }

  /// 获取用户信息
  static Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final response = await _client.post('/v1/casually/getUserInfo');

      if (response.data['code'] == 0) {
        return response.data['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('获取用户信息失败: $e');
      }
      return null;
    }
  }

  /// 获取编辑记录详情
  ///
  /// [id] 记录ID
  static Future<Map<String, dynamic>?> getEditMaterialDetail(int id) async {
    try {
      final response = await _client.get(
        '/v1/Casually/up_knowledge_casually',
        queryParameters: {'id': id},
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('获取编辑详情失败: $e');
      }
      return null;
    }
  }

  /// 编辑提交素材
  ///
  /// [data] 素材数据（包含id字段）
  static Future<Map<String, dynamic>?> editMaterial(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client.post(
        '/v1/Casually/up_knowledge_casually',
        data: data,
      );

      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('编辑素材失败: $e');
      }
      return null;
    }
  }

  // ==================== NAS 分片上传相关 API ====================

  /// NAS 初始化分片上传
  ///
  /// [fileName] 文件名
  /// [fileSize] 文件大小（字节）
  /// [filePath] 文件存储路径（可选，不传则由后端自动生成）
  static Future<Map<String, dynamic>?> nasInitMultipartUpload({
    required String fileName,
    required int fileSize,
    String? filePath,
    String? baseDir,
    bool generateThumbnail = true,
  }) async {
    try {
      final data = <String, dynamic>{
        'file_name': fileName,
        'file_size': fileSize,
        'generate_thumbnail': generateThumbnail ? 1 : 0,
      };
      if (filePath != null && filePath.isNotEmpty) {
        data['file_path'] = filePath;
      }
      if (baseDir != null && baseDir.isNotEmpty) {
        data['base_dir'] = baseDir;
      }

      final response = await _client.post(
        '/v1/nas_upload/init_multipart_upload',
        data: data,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      // NAS 接口返回 code=0 表示成功
      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 初始化分片上传失败: $e');
      }
      rethrow;
    }
  }

  /// NAS 上传分片
  ///
  /// 前端需要自己切分文件，每个分片通过此接口上传
  /// 进度记录已集成到此接口中，无需额外调用 recordChunkProgress
  ///
  /// [taskId] 任务ID（init接口返回）
  /// [uploadId] 上传ID（init接口返回）
  /// [partNumber] 分片序号（从1开始）
  /// [chunkData] 分片数据
  static Future<Map<String, dynamic>?> nasUploadChunk({
    required String taskId,
    required String uploadId,
    required int partNumber,
    required List<int> chunkData,
  }) async {
    try {
      final formData = FormData.fromMap({
        'task_id': taskId,
        'upload_id': uploadId,
        'part_number': partNumber,
        'chunk': MultipartFile.fromBytes(
          chunkData,
          filename: 'chunk_$partNumber',
        ),
      });

      final response = await _client.postFormData(
        '/v1/nas_upload/upload_chunk',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      // NAS 接口返回 code=0 表示成功
      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 上传分片失败: $e');
      }
      rethrow;
    }
  }

  /// NAS 完成分片上传
  ///
  /// [taskId] 任务ID
  /// [uploadId] 上传ID
  /// [filePath] 文件路径
  /// [generateFrame] 是否生成视频截帧（视频类型默认true）
  static Future<Map<String, dynamic>?> nasCompleteMultipartUpload({
    required String taskId,
    required String uploadId,
    required String filePath,
    bool generateFrame = true,
  }) async {
    try {
      final response = await _client.post(
        '/v1/nas_upload/complete_multipart_upload',
        data: {
          'task_id': taskId,
          'upload_id': uploadId,
          'file_path': filePath,
          'generate_frame': generateFrame ? 1 : 0,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 180),
        ),
      );

      // NAS 接口返回 code=0 表示成功
      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 完成分片上传失败: $e');
      }
      rethrow;
    }
  }

  /// NAS 暂停上传
  ///
  /// [taskId] 任务ID
  static Future<bool> nasPauseUpload({required String taskId}) async {
    try {
      final response = await _client.post(
        '/v1/nas_upload/pause_upload',
        data: {'task_id': taskId},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 暂停上传失败: $e');
      }
      return false;
    }
  }

  /// NAS 继续上传
  ///
  /// 返回已上传的分片号数组，客户端可以跳过已上传的分片继续上传
  ///
  /// [taskId] 任务ID
  static Future<Map<String, dynamic>?> nasResumeUpload({
    required String taskId,
  }) async {
    try {
      final response = await _client.post(
        '/v1/nas_upload/resume_upload',
        data: {'task_id': taskId},
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 继续上传失败: $e');
      }
      return null;
    }
  }

  /// NAS 取消上传
  ///
  /// [taskId] 任务ID
  static Future<bool> nasCancelUpload({required String taskId}) async {
    try {
      final response = await _client.post(
        '/v1/nas_upload/cancel_upload',
        data: {'task_id': taskId},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 取消上传失败: $e');
      }
      return false;
    }
  }

  /// NAS 获取上传任务列表
  ///
  /// [status] 状态筛选（waiting/uploading/paused/completed/failed）
  /// [page] 页码，默认1
  /// [pageSize] 每页数量，默认20
  static Future<Map<String, dynamic>?> nasGetUploadTasks({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final data = <String, dynamic>{
        'storage_type': 'nas',
        'page': page,
        'page_size': pageSize,
      };
      if (status != null && status.isNotEmpty) {
        data['status'] = status;
      }

      final response = await _client.post(
        '/v1/nas_upload/get_upload_tasks',
        data: data,
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NAS 获取上传任务列表失败: $e');
      }
      return null;
    }
  }

  // ==================== 素材库相关 API ====================

  /// 获取素材库列表（V2版本，支持分页和筛选）
  ///
  /// [pageSize] 每页数量
  /// [text] 搜索关键词
  /// [flag] 标志位，2表示查询素材库
  /// [materialCategory] 素材类型：0-全部，1-美食，2-风景等
  /// [activityStartTime] 活动开始时间（格式：YYYY-MM-DD）
  /// [activityEndTime] 活动结束时间（格式：YYYY-MM-DD）
  /// [id] 当前ID（用于分页）
  /// [type] 分页方向：dayu-向上加载，xiaoyu-向下加载
  /// [order] 排序：asc-升序，desc-降序
  /// [countryType] 素材归属数组，例如：["1", "2", "3"]
  /// [fileType] 文件类型：0-全部，1-仅视频，2-仅图片
  /// [filterHospitalId] 按医院ID筛选
  /// [filterUserId] 按用户ID筛选
  /// [isMyDep] 可见范围：0-全部，1-仅本部门
  /// [isDomestic] 是否国内：1-国内，0-国外
  static Future<Map<String, dynamic>?> getMaterialList({
    int pageSize = 10,
    String? text,
    int flag = 2,
    int materialCategory = 0,
    String? activityStartTime,
    String? activityEndTime,
    String? id,
    String type = '',
    String order = 'desc',
    List<String>? countryType,
    int fileType = 0,
    String? filterHospitalId,
    String? filterUserId,
    int isMyDep = 0,
    int isDomestic = 1,
  }) async {
    try {
      final data = {
        'page_size': pageSize,
        'flag': flag,
        'material_category': materialCategory,
        'order': order,
        'file_type': fileType,
        'is_my_dep': isMyDep,
        'is_domestic': isDomestic,
      };

      if (text != null && text.isNotEmpty) {
        data['text'] = text;
      }
      if (activityStartTime != null && activityStartTime.isNotEmpty) {
        data['activity_start_time'] = activityStartTime;
      }
      if (activityEndTime != null && activityEndTime.isNotEmpty) {
        data['activity_end_time'] = activityEndTime;
      }
      if (id != null && id.isNotEmpty) {
        data['id'] = id;
      }
      if (type.isNotEmpty) {
        data['type'] = type;
      }
      if (countryType != null && countryType.isNotEmpty) {
        data['country_type'] = countryType;
      }
      if (filterHospitalId != null && filterHospitalId.isNotEmpty) {
        data['filter_hospital_id'] = filterHospitalId;
      }
      if (filterUserId != null && filterUserId.isNotEmpty) {
        data['filter_user_id'] = filterUserId;
      }

      final response = await _client.post(
        '/v1/casually/upload_history_new',
        data: data,
      );

      if (response.data['code'] == 0) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('获取素材列表失败: $e');
      }
      // 网络错误时重新抛出异常，让调用方能够区分网络错误和正常空数据
      rethrow;
    }
  }

  /// 增加下载次数
  ///
  /// [id] 素材ID
  static Future<bool> increaseDownloadCount(int id) async {
    try {
      final response = await _client.post(
        '/v1/casually/down_load_history',
        data: {'id': id},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) {
        print('增加下载次数失败: $e');
      }
      return false;
    }
  }

  /// 增加浏览次数
  ///
  /// [id] 素材ID
  static Future<bool> increaseViewCount(int id) async {
    try {
      final response = await _client.post(
        '/v1/casually/update_show_count',
        data: {'id': id},
      );

      // 检查返回数据是否包含"更新成功"
      if (response.data['code'] == 0 && response.data['data'] != null) {
        return response.data['data'].toString().contains('更新成功');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('增加浏览次数失败: $e');
      }
      return false;
    }
  }

  /// 切换收藏状态
  ///
  /// [kclId] 素材ID
  static Future<bool> toggleCollect(int kclId) async {
    try {
      final response = await _client.post(
        '/v1/casually/toggle_collect',
        data: {'kcl_id': kclId},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) {
        print('切换收藏状态失败: $e');
      }
      return false;
    }
  }
}
