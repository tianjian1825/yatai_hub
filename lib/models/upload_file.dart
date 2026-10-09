import 'dart:io';
import 'package:path/path.dart' as path;

/// 上传文件状态枚举
enum UploadFileStatus {
  pending, // 待上传
  uploading, // 上传中
  success, // 上传成功
  failed, // 上传失败
  canceled, // 已取消
  paused, // 已暂停
}

/// 上传文件模型
class UploadFile {
  /// 文件本地路径
  final String localPath;

  /// 文件名
  final String fileName;

  /// 原始文件名（用于提交时的original_name字段）
  String? originalName;

  /// 文件大小（字节）
  final int fileSize;

  /// 文件类型（从文件扩展名判断）
  final UploadFileType fileType;

  /// 上传状态
  UploadFileStatus status;

  /// 上传进度（0-100）
  double progress;

  /// 远程URL（上传成功后）
  String? remoteUrl;

  /// OSS文件路径（上传成功后）
  String? ossFilePath;

  /// 错误信息（上传失败时）
  String? errorMessage;

  /// 缩略图路径（图片的thumbnail.file_path 或 视频的video_frame.file_path，用于提交）
  String? thumbnailPath;

  /// 缩略图URL（图片的thumbnail.file_url 或 视频的video_frame.file_url，用于回显）
  String? thumbnailUrl;

  /// 唯一ID（用于标识文件）
  final String id;

  /// 服务器文件记录ID（编辑模式下从 casually_list 获取，提交时需要回传）
  final String? serverFileId;

  /// 后端任务ID（分片上传用）
  String? backendTaskId;

  /// 后端上传ID（分片上传用）
  String? backendUploadId;

  /// 已完成的分片编号列表
  List<int> completedChunks;

  /// 是否为暂停操作（用于区分暂停和取消）
  bool isPaused;

  /// 创建时间（用于清理）
  final DateTime createdAt;

  UploadFile({
    required this.localPath,
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.id,
    this.serverFileId,
    this.originalName,
    this.status = UploadFileStatus.pending,
    this.progress = 0.0,
    this.remoteUrl,
    this.ossFilePath,
    this.errorMessage,
    this.thumbnailPath,
    this.thumbnailUrl,
    this.backendTaskId,
    this.backendUploadId,
    List<int>? completedChunks,
    this.isPaused = false,
    DateTime? createdAt,
  }) : completedChunks = completedChunks ?? [],
       createdAt = createdAt ?? DateTime.now();

  /// 根据文件路径创建上传文件
  factory UploadFile.fromPath(
    String filePath, {
    String? customId,
    String? customFileName,
    int? fileSize,
  }) {
    // 使用自定义文件名或从路径中提取
    final fileName = customFileName ?? path.basename(filePath);
    final id = customId ?? DateTime.now().millisecondsSinceEpoch.toString();

    // 获取文件大小
    int actualFileSize = fileSize ?? 0;

    // 如果未提供文件大小，则尝试从文件路径读取
    if (actualFileSize == 0) {
      try {
        final file = File(filePath);
        actualFileSize = file.lengthSync();
      } catch (e) {
        // 文件访问失败时，大小为 0
        actualFileSize = 0;
      }
    }

    final fileType = getFileType(fileName);

    return UploadFile(
      localPath: filePath,
      fileName: fileName,
      fileSize: actualFileSize,
      fileType: fileType,
      id: id,
    );
  }

  /// 判断文件类型
  static UploadFileType getFileType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;

    if ([
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'heic',
      'heif',
      'dng',
      'tiff',
      'tif',
    ].contains(extension)) {
      return UploadFileType.image;
    } else if ([
      // 常见视频格式
      'mp4', 'mov', 'avi', 'wmv', 'flv', 'mkv',
      // Web 视频格式
      'webm', 'ogv',
      // 移动端常见格式
      'm4v', '3gp', '3g2',
      // 其他格式
      'mpeg', 'mpg', 'mpe', 'mpv', 'm2v',
      'ts', 'mts', 'm2ts',
      'vob', 'divx', 'xvid',
      'rm', 'rmvb',
      'asf', 'f4v',
    ].contains(extension)) {
      return UploadFileType.video;
    } else if ([
      // 常见音频格式
      'mp3', 'wav', 'aac', 'flac', 'ogg', 'wma',
      'm4a', 'aiff', 'aif', 'ape', 'opus',
      'amr', 'mid', 'midi', 'ra', 'ram',
    ].contains(extension)) {
      return UploadFileType.audio;
    } else {
      return UploadFileType.document;
    }
  }

  /// 获取文件扩展名
  String get fileExtension {
    return fileName.split('.').last.toUpperCase();
  }

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(2)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 是否是图片或视频（可以显示缩略图）
  bool get canShowThumbnail {
    return fileType == UploadFileType.image || fileType == UploadFileType.video;
  }

  /// 复制并更新状态
  UploadFile copyWith({
    String? fileName,
    UploadFileStatus? status,
    double? progress,
    String? remoteUrl,
    String? ossFilePath,
    String? errorMessage,
    String? thumbnailPath,
    String? thumbnailUrl,
    String? backendTaskId,
    String? backendUploadId,
    List<int>? completedChunks,
    String? originalName,
    bool? isPaused,
    String? serverFileId,
  }) {
    return UploadFile(
      localPath: localPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize,
      fileType: fileType,
      id: id,
      serverFileId: serverFileId ?? this.serverFileId,
      originalName: originalName ?? this.originalName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      ossFilePath: ossFilePath ?? this.ossFilePath,
      errorMessage: errorMessage ?? this.errorMessage,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      backendTaskId: backendTaskId ?? this.backendTaskId,
      backendUploadId: backendUploadId ?? this.backendUploadId,
      completedChunks: completedChunks ?? this.completedChunks,
      isPaused: isPaused ?? this.isPaused,
      createdAt: createdAt,
    );
  }

  /// 序列化为 JSON（用于缓存）
  Map<String, dynamic> toJson() {
    return {
      'localPath': localPath,
      'fileName': fileName,
      'originalName': originalName,
      'fileSize': fileSize,
      'fileType': fileType.index,
      'id': id,
      'serverFileId': serverFileId,
      'status': status.index,
      'progress': progress,
      'remoteUrl': remoteUrl,
      'ossFilePath': ossFilePath,
      'errorMessage': errorMessage,
      'thumbnailPath': thumbnailPath,
      'thumbnailUrl': thumbnailUrl,
      'backendTaskId': backendTaskId,
      'backendUploadId': backendUploadId,
      'completedChunks': completedChunks,
      'isPaused': isPaused,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化
  factory UploadFile.fromJson(Map<String, dynamic> json) {
    return UploadFile(
      localPath: json['localPath'] as String,
      fileName: json['fileName'] as String,
      originalName: json['originalName'] as String?,
      fileSize: json['fileSize'] as int,
      fileType: UploadFileType.values[json['fileType'] as int],
      id: json['id'] as String,
      serverFileId: json['serverFileId'] as String?,
      status: UploadFileStatus.values[json['status'] as int],
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      remoteUrl: json['remoteUrl'] as String?,
      ossFilePath: json['ossFilePath'] as String?,
      errorMessage: json['errorMessage'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      backendTaskId: json['backendTaskId'] as String?,
      backendUploadId: json['backendUploadId'] as String?,
      completedChunks:
          (json['completedChunks'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      isPaused: json['isPaused'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// 文件类型枚举
enum UploadFileType {
  image, // 图片
  video, // 视频
  audio, // 音频
  document, // 文档
}
