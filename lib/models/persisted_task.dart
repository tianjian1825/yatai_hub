import '../services/upload_queue_manager.dart';

/// 持久化任务模型
/// 专门用于序列化/反序列化，不包含运行时对象（如 CancelToken）
class PersistedTask {
  /// 任务ID
  final String taskId;

  /// 文件名
  final String fileName;

  /// 文件大小（字节）
  final int fileSize;

  /// 本地文件路径
  final String localPath;

  /// 后端任务ID（分片上传用）
  final String? backendTaskId;

  /// 后端上传ID（分片上传用）
  final String? backendUploadId;

  /// 已完成的分片编号列表
  final List<int> completedChunks;

  /// 存储类型：'nas'
  final String storageType;

  /// 医院名称（NAS 模式使用）
  final String? hospitalName;

  /// 任务状态
  final UploadTaskStatus status;

  /// 上传进度（0-100）
  final double progress;

  /// 错误信息
  final String? errorMessage;

  /// 重试次数
  final int retryCount;

  /// 上传结果：文件URL
  final String? resultFileUrl;

  /// 上传结果：OSS路径
  final String? resultOssPath;

  /// 分片上传过程中使用的OSS文件路径（用于断点续传）
  final String? uploadingOssPath;

  /// 缩略图/视频截帧 URL（用于回显）
  final String? thumbnailUrl;

  /// 缩略图/视频截帧路径（用于提交）
  final String? thumbnailPath;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  final DateTime? completedAt;

  /// 最后更新时间
  final DateTime lastUpdatedAt;

  PersistedTask({
    required this.taskId,
    required this.fileName,
    required this.fileSize,
    required this.localPath,
    this.backendTaskId,
    this.backendUploadId,
    required this.completedChunks,
    this.storageType = 'nas',
    this.hospitalName,
    required this.status,
    required this.progress,
    this.errorMessage,
    required this.retryCount,
    this.resultFileUrl,
    this.resultOssPath,
    this.uploadingOssPath,
    this.thumbnailUrl,
    this.thumbnailPath,
    required this.createdAt,
    this.completedAt,
    required this.lastUpdatedAt,
  });

  /// 判断任务是否可恢复（用于继续上传）
  bool isResumable() {
    // 本地路径为空不可恢复
    if (localPath.isEmpty) {
      return false;
    }

    // 已完成或已取消的任务不需要恢复上传
    if (status == UploadTaskStatus.completed ||
        status == UploadTaskStatus.canceled) {
      return false;
    }

    // 超过5天的失败任务不恢复
    final age = DateTime.now().difference(createdAt).inDays;
    if (age >= 5 && status == UploadTaskStatus.failed) {
      return false;
    }

    return true;
  }

  /// 判断任务是否应该在列表中显示（包括已完成的任务）
  bool shouldDisplay() {
    // 已完成的任务始终显示（用户可能需要后续提交）
    if (status == UploadTaskStatus.completed) {
      return true;
    }

    // 非完成状态的任务超过5天不显示
    final age = DateTime.now().difference(createdAt).inDays;
    if (age >= 5) {
      return false;
    }

    return true;
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'fileName': fileName,
      'fileSize': fileSize,
      'localPath': localPath,
      'backendTaskId': backendTaskId,
      'backendUploadId': backendUploadId,
      'completedChunks': completedChunks,
      'storageType': storageType,
      'hospitalName': hospitalName,
      'status': status.index,
      'progress': progress,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
      'resultFileUrl': resultFileUrl,
      'resultOssPath': resultOssPath,
      'uploadingOssPath': uploadingOssPath,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
    };
  }

  /// 从JSON反序列化
  factory PersistedTask.fromJson(Map<String, dynamic> json) {
    return PersistedTask(
      taskId: json['taskId'] as String,
      fileName: json['fileName'] as String,
      fileSize: json['fileSize'] as int,
      localPath: json['localPath'] as String,
      backendTaskId: json['backendTaskId'] as String?,
      backendUploadId: json['backendUploadId'] as String?,
      completedChunks:
          (json['completedChunks'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      storageType: json['storageType'] as String? ?? 'nas',
      hospitalName: json['hospitalName'] as String?,
      status: UploadTaskStatus.values[json['status'] as int],
      progress: (json['progress'] as num).toDouble(),
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int,
      resultFileUrl: json['resultFileUrl'] as String?,
      resultOssPath: json['resultOssPath'] as String?,
      uploadingOssPath: json['uploadingOssPath'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      lastUpdatedAt: DateTime.parse(json['lastUpdatedAt'] as String),
    );
  }
}
