import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/upload_file.dart';
import 'api_client.dart';

/// NAS 上传服务
/// 用于将文件上传到后端 NAS 存储，替代原有的 OSS 直传方式
class NasUploadService {
  final Dio _dio;

  /// 上传接口基础 URL，与 ApiClient 保持一致
  static String get _baseUrl => ApiConfig.baseUrl;

  /// 上传接口路径
  static const String _uploadPath = '/v1/nas_upload/upload_image';

  NasUploadService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 120),
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  /// 上传单个文件到 NAS
  ///
  /// [file] 要上传的文件
  /// [hospitalName] 医院名称（可选，用于确定存储路径）
  /// [generateThumbnail] 是否生成缩略图（图片类型默认true）
  /// [onProgress] 进度回调
  /// [cancelToken] 取消令牌
  ///
  /// 返回上传成功后的文件信息
  Future<NasUploadedFileInfo> uploadFile({
    required UploadFile file,
    String? hospitalName,
    String? baseDir,
    bool generateThumbnail = true,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      // 准备上传数据
      final multipartFile = await MultipartFile.fromFile(
        file.localPath,
        filename: file.fileName,
      );

      // 构建表单数据
      final formData = FormData.fromMap({
        'file': multipartFile,
        if (hospitalName != null && hospitalName.isNotEmpty)
          'hospital_name': hospitalName,
        'generate_thumbnail': generateThumbnail ? 1 : 0,
        if (baseDir != null && baseDir.isNotEmpty) 'base_dir': baseDir,
      });

      // 获取 access_token
      final apiClient = ApiClient();
      final accessToken = await apiClient.getAccessToken();

      if (kDebugMode) {
        print('[NAS上传] ===== 请求参数 =====');
        print('[NAS上传] URL: $_baseUrl$_uploadPath');
        print('[NAS上传] file: ${file.fileName} (${file.fileSize} bytes)');
        print('[NAS上传] hospital_name: $hospitalName');
        print('[NAS上传] generate_thumbnail: ${generateThumbnail ? 1 : 0}');
        print('[NAS上传] base_dir: $baseDir');
        print('[NAS上传] Authorization: ${accessToken != null && accessToken.isNotEmpty ? 'Bearer ***' : '(无)'}');
        print('[NAS上传] ===================');
      }

      // 发送上传请求
      final response = await _dio.post(
        '$_baseUrl$_uploadPath',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            final progress = (sent / total * 100);
            onProgress(progress);
          }
        },
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'frontend': 'frontend',
            if (accessToken != null && accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
          validateStatus: (status) {
            return status != null && status >= 200 && status < 300;
          },
        ),
      );

      // 检查上传结果
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data;

        if (kDebugMode) {
          print('[NAS上传] 响应状态码: ${response.statusCode}');
          print('[NAS上传] 响应数据: $responseData');
          print(
            '[NAS上传] code: ${responseData['code']}, msg: ${responseData['msg']}',
          );
        }

        // 检查业务状态码
        // NAS 接口返回 code=0 表示成功
        if (responseData['code'] == 0 && responseData['data'] != null) {
          final data = responseData['data'] as Map<String, dynamic>;

          // 解析缩略图（兼容 Map 和 String 两种格式）
          ThumbnailInfo? thumbnail;
          final thumbnailRaw = data['thumbnail'];
          if (thumbnailRaw is Map) {
            thumbnail = ThumbnailInfo.fromJson(
              Map<String, dynamic>.from(thumbnailRaw),
            );
          } else if (thumbnailRaw is String && thumbnailRaw.isNotEmpty) {
            thumbnail = ThumbnailInfo(
              fileName: '',
              filePath: '',
              fileUrl: thumbnailRaw,
              fileSize: 0,
            );
          }

          // 解析视频截帧（兼容 Map 和 String 两种格式）
          VideoFrameInfo? videoFrame;
          final videoFrameRaw = data['video_frame'];
          if (videoFrameRaw is Map) {
            videoFrame = VideoFrameInfo.fromJson(
              Map<String, dynamic>.from(videoFrameRaw),
            );
          } else if (videoFrameRaw is String && videoFrameRaw.isNotEmpty) {
            videoFrame = VideoFrameInfo(
              fileName: '',
              filePath: '',
              fileUrl: videoFrameRaw,
              fileSize: 0,
            );
          }

          if (kDebugMode) {
            print('[NAS上传] thumbnail: $thumbnail (raw=$thumbnailRaw)');
            print('[NAS上传] videoFrame: $videoFrame (raw=$videoFrameRaw)');
          }

          return NasUploadedFileInfo(
            fileName: data['file_name'] as String? ?? file.fileName,
            originalName: data['original_name'] as String? ?? file.fileName,
            filePath: data['file_path'] as String? ?? '',
            fileUrl: data['file_url'] as String? ?? '',
            fileSize: _parseIntSafe(data['file_size']) ?? file.fileSize,
            fileType: file.fileType,
            storageType: 'nas',
            thumbnail: thumbnail,
            videoFrame: videoFrame,
          );
        } else {
          final code = responseData['code'];
          final msg = responseData['msg'] ?? '未知错误';
          if (kDebugMode) {
            print(
              '[NAS上传] 业务失败 - code: $code, msg: $msg, data: ${responseData['data']}',
            );
          }
          throw Exception('服务端$code:$msg');
        }
      } else {
        throw Exception('HTTP${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // 注册期（未登录态）调用上传：避免误触全局踢人逻辑导致注册页被 pop
        final hasToken = await ApiClient().getAccessToken();
        if (hasToken == null || hasToken.isEmpty) {
          rethrow;
        }
        ApiClient().handleAuthExpired();
        throw AuthException();
      }
      // 直接抛出 DioException，让上层 UploadQueueManager 根据类型做精确处理
      rethrow;
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('上传失败: $e');
    }
  }

  /// 批量上传文件
  ///
  /// [files] 要上传的文件列表
  /// [hospitalName] 医院名称（可选）
  /// [onProgress] 总体进度回调 (当前索引, 总数, 当前文件进度)
  /// [onFileComplete] 单个文件完成回调
  /// [cancelToken] 取消令牌
  ///
  /// 返回所有上传成功的文件信息
  Future<List<NasUploadedFileInfo>> uploadFiles({
    required List<UploadFile> files,
    String? hospitalName,
    void Function(int currentIndex, int total, double fileProgress)? onProgress,
    void Function(int index, NasUploadedFileInfo fileInfo)? onFileComplete,
    CancelToken? cancelToken,
  }) async {
    final List<NasUploadedFileInfo> uploadedFiles = [];
    final total = files.length;

    for (var i = 0; i < total; i++) {
      try {
        final fileInfo = await uploadFile(
          file: files[i],
          hospitalName: hospitalName,
          onProgress: (progress) {
            onProgress?.call(i, total, progress);
          },
          cancelToken: cancelToken,
        );

        uploadedFiles.add(fileInfo);
        onFileComplete?.call(i, fileInfo);
      } catch (e) {
        // 继续上传其他文件，但记录错误
        rethrow;
      }
    }

    return uploadedFiles;
  }
}

/// NAS 上传成功后的文件信息
class NasUploadedFileInfo {
  /// 服务器上的文件名
  final String fileName;

  /// 原始文件名
  final String originalName;

  /// 文件路径（相对路径，用于提交）
  final String filePath;

  /// 文件访问 URL（完整 URL，用于回显）
  final String fileUrl;

  /// 文件大小（字节）
  final int fileSize;

  /// 文件类型
  final UploadFileType fileType;

  /// 存储类型（固定为 'nas'）
  final String storageType;

  /// 缩略图信息（图片类型才有）
  final ThumbnailInfo? thumbnail;

  /// 视频截帧信息（视频类型才有）
  final VideoFrameInfo? videoFrame;

  NasUploadedFileInfo({
    required this.fileName,
    required this.originalName,
    required this.filePath,
    required this.fileUrl,
    required this.fileSize,
    required this.fileType,
    required this.storageType,
    this.thumbnail,
    this.videoFrame,
  });

  /// 转换为提交 API 所需的格式
  Map<String, dynamic> toSubmitJson() {
    // 图片使用 thumbnail.filePath，视频使用 videoFrame.filePath
    String? thumbnailPath;
    if (thumbnail != null) {
      thumbnailPath = thumbnail!.filePath;
    } else if (videoFrame != null) {
      thumbnailPath = videoFrame!.filePath;
    }

    return {
      'original_name': originalName,
      'file_name': fileName,
      'file_path': filePath,
      'file_size': fileSize,
      'url': fileUrl,
      'storage_type': storageType,
      'thumbnail': ?thumbnailPath,
    };
  }

  /// 获取预览用的缩略图 URL
  /// 优先使用缩略图，视频使用截帧，否则使用原图
  String get previewUrl {
    if (thumbnail != null && thumbnail!.fileUrl.isNotEmpty) {
      return thumbnail!.fileUrl;
    }
    if (videoFrame != null && videoFrame!.fileUrl.isNotEmpty) {
      return videoFrame!.fileUrl;
    }
    return fileUrl;
  }
}

/// 缩略图信息
class ThumbnailInfo {
  final String fileName;
  final String filePath;
  final String fileUrl;
  final int fileSize;
  final int? width;
  final int? height;

  ThumbnailInfo({
    required this.fileName,
    required this.filePath,
    required this.fileUrl,
    required this.fileSize,
    this.width,
    this.height,
  });

  factory ThumbnailInfo.fromJson(Map<String, dynamic> json) {
    return ThumbnailInfo(
      fileName: json['file_name'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      fileUrl: json['file_url'] as String? ?? '',
      fileSize: _parseIntSafe(json['file_size']) ?? 0,
      width: _parseIntSafe(json['width']),
      height: _parseIntSafe(json['height']),
    );
  }
}

/// 视频截帧信息
class VideoFrameInfo {
  final String fileName;
  final String filePath;
  final String fileUrl;
  final int fileSize;
  final int? frameTime;
  final int? width;
  final int? height;

  VideoFrameInfo({
    required this.fileName,
    required this.filePath,
    required this.fileUrl,
    required this.fileSize,
    this.frameTime,
    this.width,
    this.height,
  });

  factory VideoFrameInfo.fromJson(Map<String, dynamic> json) {
    return VideoFrameInfo(
      fileName: json['file_name'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      fileUrl: json['file_url'] as String? ?? '',
      fileSize: _parseIntSafe(json['file_size']) ?? 0,
      frameTime: _parseIntSafe(json['frame_time']),
      width: _parseIntSafe(json['width']),
      height: _parseIntSafe(json['height']),
    );
  }
}

/// 安全解析整数，支持 int 和 String 类型
int? _parseIntSafe(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
