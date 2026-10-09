import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/upload_file.dart';
import 'material_api.dart';
import 'nas_upload_service.dart';

/// NAS 分片上传服务
/// 用于大文件分片上传到 NAS 存储
class NasChunkedUploadService {
  /// 分片大小（默认15MB）
  final int chunkSize;

  /// 最小分片文件大小（默认30MB）
  /// 小于此大小的文件不使用分片上传
  final int minChunkFileSize;

  /// 单个分片最大重试次数
  final int maxChunkRetries;

  /// 分片重试延迟（毫秒）
  final int chunkRetryDelay;

  /// 普通上传服务（用于小文件）
  final NasUploadService _nasUploadService;

  NasChunkedUploadService({
    Dio? dio,
    this.chunkSize = 15 * 1024 * 1024, // 15MB
    this.minChunkFileSize = 30 * 1024 * 1024, // 30MB
    this.maxChunkRetries = 3,
    this.chunkRetryDelay = 1000,
  }) : _nasUploadService = NasUploadService(dio: dio);

  /// 判断文件是否需要分片上传
  bool shouldUseChunkedUpload(UploadFile file) {
    return file.fileSize >= minChunkFileSize;
  }

  /// 分片上传文件到 NAS
  /// 支持断点续传：如果 file 中包含 backendTaskId 和 backendUploadId，则跳过已完成分片
  ///
  /// [file] 要上传的文件
  /// [hospitalName] 医院名称（可选，用于确定存储路径）
  /// [onProgress] 进度回调
  /// [onChunkComplete] 分片完成回调
  /// [cancelToken] 取消令牌
  Future<NasUploadedFileInfo> uploadFile({
    required UploadFile file,
    String? hospitalName,
    String? baseDir,
    void Function(double progress)? onProgress,
    void Function(int chunkIndex, int totalChunks)? onChunkComplete,
    CancelToken? cancelToken,
  }) async {
    if (kDebugMode) {
      print('[NAS分片上传] ===== 请求参数 =====');
      print('[NAS分片上传] file: ${file.fileName} (${file.fileSize} bytes)');
      print('[NAS分片上传] hospital_name: $hospitalName');
      print('[NAS分片上传] base_dir: $baseDir');
      print('[NAS分片上传] 分片阈值: $minChunkFileSize bytes');
      print('[NAS分片上传] 分片大小: $chunkSize bytes');
      print('[NAS分片上传] ===================');
    }

    // 如果文件不需要分片，使用普通上传
    if (!shouldUseChunkedUpload(file)) {
      if (kDebugMode) {
        print('[NAS分片上传] 文件小于阈值，使用普通上传');
      }
      return _nasUploadService.uploadFile(
        file: file,
        hospitalName: hospitalName,
        baseDir: baseDir,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // 生成或使用已保存的文件名和路径
    String fileName;
    String? filePath;

    // 断点续传时使用保存的路径
    if (file.ossFilePath != null && file.ossFilePath!.isNotEmpty) {
      filePath = file.ossFilePath!;
      fileName = filePath.split('/').last;
    } else {
      // 首次上传，原文件名追加时间戳后缀（仅在扩展名前插入，不改动主体名）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dotIndex = file.fileName.lastIndexOf('.');
      fileName = dotIndex > 0
          ? '${file.fileName.substring(0, dotIndex)}_$timestamp'
              '${file.fileName.substring(dotIndex)}'
          : '${file.fileName}_$timestamp';
      // filePath 可以不传，让后端自动生成
    }

    // 实际使用的分片大小和总分片数，初始化后从后端响应获取
    int effectiveChunkSize = chunkSize;
    int effectiveTotalChunks = 0;

    String uploadId;
    String backendTaskId;

    // 检查是否有断点续传信息
    if (file.backendTaskId != null &&
        file.backendUploadId != null &&
        file.completedChunks.isNotEmpty) {
      // 使用已有的任务信息进行续传
      backendTaskId = file.backendTaskId!;
      uploadId = file.backendUploadId!;

      // 尝试从后端恢复上传状态
      try {
        final resumeResult = await MaterialApi.nasResumeUpload(
          taskId: backendTaskId,
        );

        if (resumeResult != null) {
          // 更新已完成的分片列表
          final uploadedChunks =
              resumeResult['uploaded_chunks'] as List<dynamic>?;
          if (uploadedChunks != null) {
            file.completedChunks.clear();
            file.completedChunks.addAll(uploadedChunks.cast<int>());
          }
          // 获取文件路径
          filePath = resumeResult['file_path'] as String?;
          // 从 resume 响应获取分片信息（如果后端返回）
          if (resumeResult['chunk_size'] != null) {
            effectiveChunkSize = resumeResult['chunk_size'] as int;
          }
          if (resumeResult['total_chunks'] != null) {
            effectiveTotalChunks = resumeResult['total_chunks'] as int;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[NAS分片上传] 恢复上传状态失败，重新初始化: $e');
        }
        // 恢复失败，重新初始化
        file.backendTaskId = null;
        file.backendUploadId = null;
        file.completedChunks.clear();
      }
    }

    // 如果没有断点续传信息或恢复失败，初始化新的上传任务
    if (file.backendTaskId == null || file.backendUploadId == null) {
      if (kDebugMode) {
        print('[NAS分片上传] 初始化请求参数:');
        print('  - file_name: $fileName');
        print('  - file_size: ${file.fileSize}');
        print('  - file_path: $filePath');
        print('  - base_dir: $baseDir');
        print('  - generate_thumbnail: 1');
      }
      final initResult = await MaterialApi.nasInitMultipartUpload(
        fileName: fileName,
        fileSize: file.fileSize,
        filePath: filePath,
        baseDir: baseDir,
        generateThumbnail: true,
      );

      if (initResult == null) {
        throw NasUploadException('初始化分片上传失败', NasUploadErrorType.initFailed);
      }

      uploadId = initResult['upload_id'] as String;
      backendTaskId = initResult['task_id'] as String;
      filePath = initResult['file_path'] as String?;

      // 使用后端返回的分片大小和总分片数
      effectiveChunkSize = (initResult['chunk_size'] as int?) ?? chunkSize;
      effectiveTotalChunks =
          (initResult['total_chunks'] as int?) ??
          (file.fileSize / effectiveChunkSize).ceil();

      // 保存后端ID到文件对象（用于断点续传）
      file.backendTaskId = backendTaskId;
      file.backendUploadId = uploadId;
      if (filePath != null) {
        file.ossFilePath = filePath;
      }

      if (kDebugMode) {
        print('[NAS分片上传] 初始化成功:');
        print('  - upload_id: $uploadId');
        print('  - task_id: $backendTaskId');
        print('  - chunk_size: $effectiveChunkSize bytes');
        print('  - total_chunks: $effectiveTotalChunks');
      }
    } else {
      backendTaskId = file.backendTaskId!;
      uploadId = file.backendUploadId!;
    }

    // 若 resume 响应未返回分片信息，本地兜底计算
    if (effectiveTotalChunks == 0) {
      effectiveTotalChunks = (file.fileSize / effectiveChunkSize).ceil();
    }

    // 打开文件用于分片读取
    final fileObj = File(file.localPath);
    if (!await fileObj.exists()) {
      throw NasUploadException(
        '文件不存在: ${file.localPath}',
        NasUploadErrorType.fileNotFound,
      );
    }
    final raf = await fileObj.open(mode: FileMode.read);

    try {
      // 获取已完成的分片集合
      final completedChunksSet = Set<int>.from(file.completedChunks);
      int completedCount = completedChunksSet.length;

      // 如果有已完成的分片，先报告初始进度
      if (completedCount > 0) {
        final initialProgress = (completedCount / effectiveTotalChunks * 100);
        onProgress?.call(initialProgress);
      }

      // 上传所有分片
      for (int i = 0; i < effectiveTotalChunks; i++) {
        // 检查是否取消或暂停
        if (cancelToken?.isCancelled ?? false) {
          if (file.isPaused) {
            throw NasUploadException('上传已暂停', NasUploadErrorType.paused);
          } else {
            throw NasUploadException('上传已取消', NasUploadErrorType.cancelled);
          }
        }

        final partNumber = i + 1;

        // 跳过已完成的分片
        if (completedChunksSet.contains(partNumber)) {
          continue;
        }

        final start = i * effectiveChunkSize;
        final end = (start + effectiveChunkSize < file.fileSize)
            ? start + effectiveChunkSize
            : file.fileSize;

        // 读取分片数据
        await raf.setPosition(start);
        final chunkData = await raf.read(end - start);

        // 带重试的分片上传
        await _uploadChunkWithRetry(
          file: file,
          taskId: backendTaskId,
          uploadId: uploadId,
          partNumber: partNumber,
          chunkData: chunkData,
          cancelToken: cancelToken,
        );

        // 记录已完成的分片
        if (!file.completedChunks.contains(partNumber)) {
          file.completedChunks.add(partNumber);
        }
        completedCount++;

        // 回调分片完成
        onChunkComplete?.call(partNumber, effectiveTotalChunks);

        // 更新总进度
        final progress = (completedCount / effectiveTotalChunks * 100);
        onProgress?.call(progress);
      }

      // 完成分片上传
      final completeResult = await MaterialApi.nasCompleteMultipartUpload(
        taskId: backendTaskId,
        uploadId: uploadId,
        filePath: filePath ?? file.ossFilePath ?? '',
        generateFrame: file.fileType == UploadFileType.video,
      );

      if (completeResult == null) {
        throw NasUploadException('完成分片上传失败', NasUploadErrorType.completeFailed);
      }

      // 解析返回结果
      final fileUrl = completeResult['file_url'] as String? ?? '';
      final resultFilePath =
          completeResult['file_path'] as String? ?? filePath ?? '';
      final resultFileName = completeResult['file_name'] as String? ?? fileName;

      // 解析缩略图信息（图片类型，兼容 Map 和 String 两种格式）
      ThumbnailInfo? thumbnail;
      final thumbnailRaw = completeResult['thumbnail'];
      if (thumbnailRaw is Map) {
        thumbnail = ThumbnailInfo.fromJson(Map<String, dynamic>.from(thumbnailRaw));
      } else if (thumbnailRaw is String && thumbnailRaw.isNotEmpty) {
        thumbnail = ThumbnailInfo(fileName: '', filePath: '', fileUrl: thumbnailRaw, fileSize: 0);
      }

      // 解析视频截帧信息（视频类型，兼容 Map 和 String 两种格式）
      VideoFrameInfo? videoFrame;
      final videoFrameRaw = completeResult['video_frame'];
      if (videoFrameRaw is Map) {
        videoFrame = VideoFrameInfo.fromJson(Map<String, dynamic>.from(videoFrameRaw));
      } else if (videoFrameRaw is String && videoFrameRaw.isNotEmpty) {
        videoFrame = VideoFrameInfo(fileName: '', filePath: '', fileUrl: videoFrameRaw, fileSize: 0);
      }

      if (kDebugMode) {
        print('[NAS分片上传] thumbnail: $thumbnail (raw=$thumbnailRaw)');
        print('[NAS分片上传] videoFrame: $videoFrame (raw=$videoFrameRaw)');
      }

      return NasUploadedFileInfo(
        fileName: resultFileName,
        originalName: file.fileName,
        filePath: resultFilePath,
        fileUrl: fileUrl,
        fileSize: file.fileSize,
        fileType: file.fileType,
        storageType: 'nas',
        thumbnail: thumbnail,
        videoFrame: videoFrame,
      );
    } on NasUploadException catch (e) {
      // 只有真正的取消操作才通知后端清理资源
      if (e.type == NasUploadErrorType.cancelled && backendTaskId.isNotEmpty) {
        try {
          await MaterialApi.nasCancelUpload(taskId: backendTaskId);
        } catch (cancelError) {
          if (kDebugMode) {
            print('[NAS分片上传] 通知后端取消失败: $cancelError');
          }
        }
      }
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// 带重试的分片上传
  Future<void> _uploadChunkWithRetry({
    required UploadFile file,
    required String taskId,
    required String uploadId,
    required int partNumber,
    required Uint8List chunkData,
    CancelToken? cancelToken,
  }) async {
    int retryCount = 0;
    Exception? lastError;

    while (retryCount < maxChunkRetries) {
      try {
        // 检查是否取消或暂停
        if (cancelToken?.isCancelled ?? false) {
          if (file.isPaused) {
            throw NasUploadException('上传已暂停', NasUploadErrorType.paused);
          } else {
            throw NasUploadException('上传已取消', NasUploadErrorType.cancelled);
          }
        }

        // 上传分片到 NAS
        final result = await MaterialApi.nasUploadChunk(
          taskId: taskId,
          uploadId: uploadId,
          partNumber: partNumber,
          chunkData: chunkData,
        );

        if (result == null) {
          throw Exception('分片上传返回空结果');
        }

        return; // 上传成功
      } on NasUploadException {
        rethrow; // 不重试取消/暂停操作
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        retryCount++;

        if (retryCount < maxChunkRetries) {
          if (kDebugMode) {
            print(
              '[NAS分片上传] 分片 $partNumber 上传失败，${chunkRetryDelay}ms 后重试 ($retryCount/$maxChunkRetries): $e',
            );
          }
          await Future.delayed(Duration(milliseconds: chunkRetryDelay));
        }
      }
    }

    throw NasUploadException(
      '分片 $partNumber 上传失败，已重试 $maxChunkRetries 次: ${lastError?.toString()}',
      NasUploadErrorType.chunkUploadFailed,
    );
  }

  /// 获取分片信息
  ChunkInfo getChunkInfo(int fileSize) {
    final totalChunks = (fileSize / chunkSize).ceil();
    return ChunkInfo(
      totalChunks: totalChunks,
      chunkSize: chunkSize,
      lastChunkSize: fileSize - (totalChunks - 1) * chunkSize,
    );
  }
}

/// 分片信息
class ChunkInfo {
  final int totalChunks;
  final int chunkSize;
  final int lastChunkSize;

  ChunkInfo({
    required this.totalChunks,
    required this.chunkSize,
    required this.lastChunkSize,
  });
}

/// NAS 上传错误类型
enum NasUploadErrorType {
  networkError,
  initFailed,
  chunkUploadFailed,
  completeFailed,
  fileReadError,
  fileNotFound,
  cancelled,
  paused,
  timeout,
  unknown,
}

/// NAS 上传异常
class NasUploadException implements Exception {
  final String message;
  final NasUploadErrorType type;
  final dynamic originalError;

  NasUploadException(this.message, this.type, [this.originalError]);

  /// 获取用户友好的错误提示（含简短标识便于排查）
  String get userFriendlyMessage {
    switch (type) {
      case NasUploadErrorType.networkError:
        return '上传失败(网络异常)';
      case NasUploadErrorType.initFailed:
        return '上传失败(初始化失败)';
      case NasUploadErrorType.chunkUploadFailed:
        return '上传失败(分片写入失败)';
      case NasUploadErrorType.completeFailed:
        return '上传失败(文件合并失败)';
      case NasUploadErrorType.fileReadError:
        return '上传失败(文件读取失败)';
      case NasUploadErrorType.fileNotFound:
        return '上传失败(文件不存在)';
      case NasUploadErrorType.cancelled:
        return '上传已取消';
      case NasUploadErrorType.paused:
        return '上传已暂停';
      case NasUploadErrorType.timeout:
        return '上传失败(服务器超时)';
      case NasUploadErrorType.unknown:
        return '上传失败(未知错误)';
    }
  }

  /// 是否可以重试
  bool get canRetry {
    switch (type) {
      case NasUploadErrorType.networkError:
      case NasUploadErrorType.initFailed:
      case NasUploadErrorType.chunkUploadFailed:
      case NasUploadErrorType.timeout:
      case NasUploadErrorType.completeFailed:
        return true;
      case NasUploadErrorType.fileReadError:
      case NasUploadErrorType.fileNotFound:
      case NasUploadErrorType.cancelled:
      case NasUploadErrorType.paused:
      case NasUploadErrorType.unknown:
        return false;
    }
  }

  @override
  String toString() => 'NasUploadException: $message (type: $type)';
}
