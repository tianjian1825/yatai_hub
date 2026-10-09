import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/upload_file.dart';
import '../models/persisted_task.dart';
import 'nas_upload_service.dart';
import 'nas_chunked_upload_service.dart';
import 'task_persistence_repository.dart';
import 'network_service.dart';
import 'upload_notification_service.dart';
import 'api_client.dart';

/// 上传任务
class UploadTask {
  /// 任务ID
  final String id;

  /// 要上传的文件
  final UploadFile file;

  /// 存储类型：'nas' 或 'oss'
  final String storageType;

  /// 医院名称（NAS 模式用于确定存储路径）
  final String? hospitalName;

  /// 上传基础目录（NAS 模式，如 'follow' 表示跟进模块）
  final String? baseDir;

  /// 任务状态
  UploadTaskStatus status;

  /// 上传进度 (0-100)
  double progress;

  /// 错误信息
  String? errorMessage;

  /// 上传结果（NAS 模式）
  NasUploadedFileInfo? nasResult;

  /// 取消令牌
  CancelToken? cancelToken;

  /// 重试次数
  int retryCount;

  /// 最大重试次数
  final int maxRetries;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  DateTime? completedAt;

  /// 最后更新时间
  DateTime lastUpdatedAt;

  UploadTask({
    required this.id,
    required this.file,
    this.storageType = 'nas',
    this.hospitalName,
    this.baseDir,
    this.status = UploadTaskStatus.queued,
    this.progress = 0,
    this.errorMessage,
    this.nasResult,
    this.retryCount = 0,
    this.maxRetries = 3,
    DateTime? createdAt,
    this.completedAt,
    DateTime? lastUpdatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  /// 复制任务并修改属性
  UploadTask copyWith({
    UploadTaskStatus? status,
    double? progress,
    String? errorMessage,
    NasUploadedFileInfo? nasResult,
    CancelToken? cancelToken,
    int? retryCount,
  }) {
    return UploadTask(
      id: id,
      file: file,
      storageType: storageType,
      hospitalName: hospitalName,
      baseDir: baseDir,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      nasResult: nasResult ?? this.nasResult,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries,
      createdAt: createdAt,
      completedAt: completedAt,
      lastUpdatedAt: DateTime.now(),
    )..cancelToken = cancelToken ?? this.cancelToken;
  }

  /// 获取文件 URL
  String? get fileUrl => nasResult?.fileUrl;

  /// 获取文件路径
  String? get filePath => nasResult?.filePath;

  /// 获取缩略图 URL（用于回显）
  /// 图片使用 thumbnail.fileUrl，视频使用 videoFrame.fileUrl
  String? get thumbnailUrl {
    if (nasResult != null) {
      if (nasResult!.thumbnail != null) {
        return nasResult!.thumbnail!.fileUrl;
      }
      if (nasResult!.videoFrame != null) {
        return nasResult!.videoFrame!.fileUrl;
      }
    }
    return null;
  }

  /// 获取缩略图路径（用于提交给后端）
  /// 图片使用 thumbnail.filePath，视频使用 videoFrame.filePath
  String? get thumbnailPath {
    if (nasResult != null) {
      if (nasResult!.thumbnail != null) {
        return nasResult!.thumbnail!.filePath;
      }
      if (nasResult!.videoFrame != null) {
        return nasResult!.videoFrame!.filePath;
      }
    }
    return null;
  }

  /// 转换为可持久化的任务
  PersistedTask toPersistedTask() {
    return PersistedTask(
      taskId: id,
      fileName: file.fileName,
      fileSize: file.fileSize,
      localPath: file.localPath,
      backendTaskId: file.backendTaskId,
      backendUploadId: file.backendUploadId,
      completedChunks: file.completedChunks,
      storageType: storageType,
      hospitalName: hospitalName,
      status: status,
      progress: progress,
      errorMessage: errorMessage,
      retryCount: retryCount,
      resultFileUrl: fileUrl,
      resultOssPath: filePath,
      uploadingOssPath: file.ossFilePath,
      thumbnailUrl: thumbnailUrl,
      thumbnailPath: thumbnailPath,
      createdAt: createdAt,
      completedAt: completedAt,
      lastUpdatedAt: lastUpdatedAt,
    );
  }
}

/// 上传任务状态
enum UploadTaskStatus {
  queued, // 排队中
  uploading, // 上传中
  completed, // 已完成
  failed, // 失败
  canceled, // 已取消
  paused, // 已暂停
}

/// 上传队列管理器
class UploadQueueManager {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  /// NAS 上传服务
  final NasUploadService _nasUploadService = NasUploadService();

  /// NAS 分片上传服务
  final NasChunkedUploadService _nasChunkedUploadService =
      NasChunkedUploadService();

  /// 任务队列
  final Queue<UploadTask> _taskQueue = Queue<UploadTask>();

  /// 正在执行的任务
  final Map<String, UploadTask> _activeTasks = {};

  /// 所有任务（包括已完成的）
  final Map<String, UploadTask> _allTasks = {};

  /// 最大并发数
  int maxConcurrentUploads = 3;

  /// 持久化仓库
  final TaskPersistenceRepository _repository = TaskPersistenceRepository();

  /// 网络服务
  final NetworkService _networkService = NetworkService();

  /// 通知服务
  final UploadNotificationService _notificationService =
      UploadNotificationService();

  /// 灵动岛服务
  final LiveActivityService _liveActivityService = LiveActivityService();

  /// 网络状态订阅
  StreamSubscription<NetworkInfo>? _networkSubscription;

  /// 网络是否可用
  bool _isNetworkAvailable = true;

  /// 因网络断开而暂停的任务ID列表
  final Set<String> _networkPausedTasks = {};

  /// 当前批次开始时的任务ID集合（用于跟踪一批上传）
  final Set<String> _currentBatchTaskIds = {};

  /// 当前批次的编辑记录ID（用于通知跳转）
  int? _currentBatchEditId;

  /// 是否启用通知
  bool _notificationsEnabled = true;

  /// 灵动岛更新节流时间戳（iOS性能优化）
  DateTime? _lastLiveActivityUpdate;

  /// 是否正在批量添加任务（用于避免重复刷新灵动岛）
  bool _batchAddingInProgress = false;

  /// 自动保存定时器
  Timer? _autoSaveTimer;

  /// 任务是否已从存储恢复
  bool _tasksRestored = false;

  /// 队列状态流
  final StreamController<Map<String, UploadTask>> _queueController =
      StreamController<Map<String, UploadTask>>.broadcast();

  /// 任务更新流
  final StreamController<UploadTask> _taskController =
      StreamController<UploadTask>.broadcast();

  /// 获取队列状态流
  Stream<Map<String, UploadTask>> get queueStream => _queueController.stream;

  /// 获取任务更新流
  Stream<UploadTask> get taskStream => _taskController.stream;

  /// 获取网络状态流
  Stream<NetworkInfo> get networkStream => _networkService.networkStream;

  /// 获取当前网络状态
  bool get isNetworkAvailable => _isNetworkAvailable;

  /// 获取网络状态描述
  String get networkStatusDescription => _networkService.getStatusDescription();

  /// 获取通知服务（用于设置点击回调）
  UploadNotificationService get notificationService => _notificationService;

  /// 设置 App 前后台状态
  void setAppInForeground(bool inForeground) {
    _notificationService.setAppInForeground(inForeground);
  }

  /// 是否存在进行中的上传任务（上传中 / 排队 / 暂停）
  bool get hasActiveUploadTasks => _allTasks.values.any((t) =>
      t.status == UploadTaskStatus.uploading ||
      t.status == UploadTaskStatus.queued ||
      t.status == UploadTaskStatus.paused);

  /// 回到前台时对账灵动岛状态（兜底）
  ///
  /// 若当前没有任何进行中的任务，则结束所有残留的灵动岛活动。
  /// 覆盖两类卡住场景：
  /// 1. endUploadActivity 的 3 秒延迟期间 App 被切后台/挂起，结束调用未执行完；
  /// 2. 其它原因遗留、与当前任务状态不一致的灵动岛。
  Future<void> reconcileLiveActivity() async {
    if (!_liveActivityService.isSupported) return;
    if (!hasActiveUploadTasks) {
      await _liveActivityService.endAllActivities();
      _currentBatchTaskIds.clear();
    }
  }

  /// 启用/禁用通知
  void setNotificationsEnabled(bool enabled) {
    _notificationsEnabled = enabled;
  }

  /// 是否正在运行
  bool _isRunning = false;

  /// 添加 NAS 上传任务
  ///
  /// [file] 要上传的文件
  /// [hospitalName] 医院名称（可选，用于确定存储路径）
  /// [editId] 编辑记录ID，如果是从编辑页面上传则传入，用于通知跳转
  /// 返回任务ID
  String addNasTask(UploadFile file, {String? hospitalName, String? baseDir, int? editId}) {
    final task = UploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${file.fileName}',
      file: file,
      storageType: 'nas',
      hospitalName: hospitalName,
      baseDir: baseDir,
      // 如果网络不可用，直接设为暂停状态
      status: _isNetworkAvailable
          ? UploadTaskStatus.queued
          : UploadTaskStatus.paused,
      errorMessage: _isNetworkAvailable ? null : '网络未连接',
    );

    return _addTaskToQueue(task, editId: editId);
  }

  /// 内部方法：将任务添加到队列
  String _addTaskToQueue(UploadTask task, {int? editId}) {
    // 只有网络可用时才加入队列
    if (_isNetworkAvailable) {
      _taskQueue.add(task);
    } else {
      // 网络不可用时，记录到 _networkPausedTasks
      _networkPausedTasks.add(task.id);
    }

    _allTasks[task.id] = task;

    // 记录到当前批次
    _currentBatchTaskIds.add(task.id);

    // 如果提供了 editId，更新当前批次的 editId
    if (editId != null) {
      _currentBatchEditId = editId;
    }

    if (kDebugMode) {
      print('添加上传任务: ${task.id}${_isNetworkAvailable ? "" : "（网络不可用，已暂停）"}');
    }

    // 只有不在批量添加过程中时才刷新灵动岛状态
    // 批量添加时由 addTasks 在最后统一刷新
    if (!_batchAddingInProgress) {
      _refreshLiveActivityState();
    }

    _notifyQueueUpdate();

    // 只有网络可用时才处理队列
    if (_isNetworkAvailable) {
      _processQueue();
    }

    // 持久化任务
    _persistTasks();

    return task.id;
  }

  /// 批量添加 NAS 上传任务
  ///
  /// [files] 要上传的文件列表
  /// [hospitalName] 医院名称（可选）
  /// [editId] 编辑记录ID
  List<String> addNasTasks(
    List<UploadFile> files, {
    String? hospitalName,
    String? baseDir,
    int? editId,
  }) {
    final taskIds = <String>[];

    // 开始新批次
    _currentBatchTaskIds.clear();
    _currentBatchEditId = editId;

    _batchAddingInProgress = true;
    try {
      for (var file in files) {
        taskIds.add(addNasTask(file, hospitalName: hospitalName, baseDir: baseDir));
      }
    } finally {
      _batchAddingInProgress = false;
    }

    _refreshLiveActivityState();

    return taskIds;
  }

  /// 取消任务
  void cancelTask(String taskId) {
    final task = _allTasks[taskId];
    if (task == null) return;

    if (task.status == UploadTaskStatus.uploading) {
      // 取消正在上传的任务
      task.cancelToken?.cancel('用户取消');
      _activeTasks.remove(taskId);
    } else if (task.status == UploadTaskStatus.queued) {
      // 从队列中移除
      _taskQueue.removeWhere((t) => t.id == taskId);
    }

    final updatedTask = task.copyWith(
      status: UploadTaskStatus.canceled,
      errorMessage: '用户取消',
    );
    updatedTask.completedAt = DateTime.now();
    updatedTask.lastUpdatedAt = DateTime.now();
    _allTasks[taskId] = updatedTask;

    _notifyTaskUpdate(updatedTask);
    _notifyQueueUpdate();
    _processQueue();

    // 持久化任务
    _persistTasks();
  }

  /// 暂停任务
  void pauseTask(String taskId) {
    final task = _allTasks[taskId];
    if (task == null || task.status != UploadTaskStatus.uploading) return;

    // 标记为暂停操作，保留后端任务用于断点续传
    task.file.isPaused = true;
    task.cancelToken?.cancel('用户暂停');
    _activeTasks.remove(taskId);

    final updatedTask = task.copyWith(status: UploadTaskStatus.paused);
    updatedTask.lastUpdatedAt = DateTime.now();
    _allTasks[taskId] = updatedTask;

    _notifyTaskUpdate(updatedTask);
    _notifyQueueUpdate();

    // 持久化任务
    _persistTasks();
  }

  /// 恢复任务
  void resumeTask(String taskId) {
    final task = _allTasks[taskId];
    if (task == null || task.status != UploadTaskStatus.paused) return;

    // 清除暂停标志
    task.file.isPaused = false;

    final updatedTask = task.copyWith(status: UploadTaskStatus.queued);
    updatedTask.lastUpdatedAt = DateTime.now();
    _allTasks[taskId] = updatedTask;
    _taskQueue.add(updatedTask);

    _notifyTaskUpdate(updatedTask);
    _notifyQueueUpdate();
    _processQueue();

    // 持久化任务
    _persistTasks();
  }

  /// 重试失败的任务
  void retryTask(String taskId) {
    final task = _allTasks[taskId];
    if (task == null || task.status != UploadTaskStatus.failed) return;

    final updatedTask = task.copyWith(
      status: UploadTaskStatus.queued,
      progress: 0,
      errorMessage: null,
      retryCount: task.retryCount + 1,
    );
    updatedTask.completedAt = null; // 重置完成时间
    updatedTask.lastUpdatedAt = DateTime.now();
    _allTasks[taskId] = updatedTask;
    _taskQueue.add(updatedTask);

    _notifyTaskUpdate(updatedTask);
    _notifyQueueUpdate();
    _processQueue();

    // 持久化任务
    _persistTasks();
  }

  /// 删除任务
  Future<void> removeTask(String taskId) async {
    // 先取消上传任务（同步操作，立即生效，避免异步清理期间上传继续运行）
    cancelTask(taskId);

    // 移除该任务的上传通知
    _notificationService.removeProgressNotification(taskId);

    final task = _allTasks[taskId];
    _allTasks.remove(taskId);
    _notifyQueueUpdate();

    // 更新灵动岛
    _refreshLiveActivityState();

    // 异步清理本地文件（不影响取消和移除的即时性）
    if (task != null) {
      await _cleanupTaskFile(task);
    }

    // 持久化任务
    await _persistTasks();
  }

  /// 清空已完成和失败的任务
  Future<void> clearCompletedTasks() async {
    // 先清理本地文件
    final tasksToRemove = _allTasks.values
        .where(
          (task) =>
              task.status == UploadTaskStatus.completed ||
              task.status == UploadTaskStatus.failed ||
              task.status == UploadTaskStatus.canceled,
        )
        .toList();

    for (final task in tasksToRemove) {
      await _cleanupTaskFile(task);
    }

    // 然后从内存中移除任务
    _allTasks.removeWhere(
      (key, task) =>
          task.status == UploadTaskStatus.completed ||
          task.status == UploadTaskStatus.failed ||
          task.status == UploadTaskStatus.canceled,
    );
    _notifyQueueUpdate();

    // 持久化任务
    await _persistTasks();
  }

  /// 获取所有任务
  List<UploadTask> getAllTasks() {
    return _allTasks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取指定状态的任务
  List<UploadTask> getTasksByStatus(UploadTaskStatus status) {
    return _allTasks.values.where((task) => task.status == status).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取任务
  UploadTask? getTask(String taskId) {
    return _allTasks[taskId];
  }

  /// 处理上传队列
  Future<void> _processQueue() async {
    if (_isRunning) return;

    // 如果网络不可用，不处理队列
    if (!_isNetworkAvailable) {
      if (kDebugMode) {
        print('[上传队列] 网络不可用，暂停队列处理');
      }
      return;
    }

    _isRunning = true;

    while (_taskQueue.isNotEmpty &&
        _activeTasks.length < maxConcurrentUploads) {
      final task = _taskQueue.removeFirst();

      // 跳过已取消或暂停的任务
      if (task.status == UploadTaskStatus.canceled ||
          task.status == UploadTaskStatus.paused) {
        continue;
      }

      _activeTasks[task.id] = task;
      _uploadTask(task);
    }

    _isRunning = false;
  }

  /// 执行上传任务
  Future<void> _uploadTask(UploadTask task) async {
    // 保留原进度（如果任务是恢复的）
    final initialProgress = task.progress;

    if (kDebugMode) {
      print('[上传队列] 开始执行任务: ${task.id}');
      print('[上传队列] 存储类型: ${task.storageType}');
      print('[上传队列] 文件名: ${task.file.fileName}');
      print('[上传队列] 文件大小: ${task.file.fileSize} bytes');
    }

    // 更新状态为上传中
    final uploadingTask = task.copyWith(
      status: UploadTaskStatus.uploading,
      // 保留原进度，不强制重置为0
      progress: initialProgress,
    )..cancelToken = CancelToken();

    _allTasks[task.id] = uploadingTask;
    _notifyTaskUpdate(uploadingTask);

    // 显示进度通知（使用保留的进度，转换为int）
    // 编辑模式下不显示通知
    if (_notificationsEnabled && _currentBatchEditId == null) {
      _notificationService.showProgressNotification(
        taskId: task.id,
        fileName: task.file.fileName,
        progress: initialProgress.toInt(), // 转换为int类型
      );
    }

    try {
      // 进度回调
      void handleProgress(double progress) {
        // 任务已被移除（用户删除），跳过更新
        if (!_allTasks.containsKey(task.id)) return;

        final progressTask = uploadingTask.copyWith(progress: progress);
        _allTasks[task.id] = progressTask;
        _notifyTaskUpdate(progressTask);

        if (_notificationsEnabled && _currentBatchEditId == null) {
          _notificationService.showProgressNotification(
            taskId: task.id,
            fileName: task.file.fileName,
            progress: progress.toInt(),
          );
        }

        final now = DateTime.now();
        if (_lastLiveActivityUpdate == null ||
            now.difference(_lastLiveActivityUpdate!) >
                const Duration(seconds: 1)) {
          _updateLiveActivity();
          _lastLiveActivityUpdate = now;
        }
      }

      // NAS 上传
      final useChunkedUpload = _nasChunkedUploadService.shouldUseChunkedUpload(
        task.file,
      );

      if (kDebugMode) {
        print('[上传队列] NAS上传模式');
        print('[上传队列] 使用分片上传: $useChunkedUpload');
        print('[上传队列] 医院名称: ${task.hospitalName}');
      }

      NasUploadedFileInfo nasResult;

      if (useChunkedUpload) {
        nasResult = await _nasChunkedUploadService.uploadFile(
          file: task.file,
          hospitalName: task.hospitalName,
          baseDir: task.baseDir,
          onProgress: handleProgress,
          onChunkComplete: (chunkIndex, totalChunks) {
            _persistTasks();
          },
          cancelToken: uploadingTask.cancelToken,
        );
      } else {
        nasResult = await _nasUploadService.uploadFile(
          file: task.file,
          hospitalName: task.hospitalName,
          baseDir: task.baseDir,
          generateThumbnail: true,
          onProgress: handleProgress,
          cancelToken: uploadingTask.cancelToken,
        );
      }

      // 上传成功
      // 从 nasResult 提取缩略图/视频截帧 URL 和路径
      String? thumbnailUrl;
      String? thumbnailPath;
      if (nasResult.thumbnail != null) {
        thumbnailUrl = nasResult.thumbnail!.fileUrl;
        thumbnailPath = nasResult.thumbnail!.filePath;
      } else if (nasResult.videoFrame != null) {
        thumbnailUrl = nasResult.videoFrame!.fileUrl;
        thumbnailPath = nasResult.videoFrame!.filePath;
      }

      // HEIC/DNG 可能被后端转码，提交时需使用转码后的 file_name
      final originalExtension = task.file.fileName
          .split('.')
          .last
          .toLowerCase();
      final isTranscodedImage = ['heic', 'dng'].contains(originalExtension);
      final resolvedFileName =
          (isTranscodedImage && nasResult.fileName.isNotEmpty)
          ? nasResult.fileName
          : task.file.fileName;
      final resolvedOriginalName =
          (isTranscodedImage && nasResult.fileName.isNotEmpty)
          ? nasResult.fileName
          : task.file.originalName;

      final updatedFile = task.file.copyWith(
        fileName: resolvedFileName,
        originalName: resolvedOriginalName,
        remoteUrl: nasResult.fileUrl,
        ossFilePath: nasResult.filePath,
        status: UploadFileStatus.success,
        progress: 100,
        thumbnailUrl: thumbnailUrl,
        thumbnailPath: thumbnailPath,
      );

      final completedTask = UploadTask(
        id: task.id,
        file: updatedFile,
        storageType: 'nas',
        hospitalName: task.hospitalName,
        baseDir: task.baseDir,
        status: UploadTaskStatus.completed,
        progress: 100,
        nasResult: nasResult,
        retryCount: uploadingTask.retryCount,
        maxRetries: uploadingTask.maxRetries,
        createdAt: uploadingTask.createdAt,
        completedAt: DateTime.now(),
        lastUpdatedAt: DateTime.now(),
      )..cancelToken = uploadingTask.cancelToken;

      // 任务已被移除（用户删除），跳过更新
      if (!_allTasks.containsKey(task.id)) return;
      _allTasks[task.id] = completedTask;
      _notifyTaskUpdate(completedTask);

      // 移除进度通知
      if (_notificationsEnabled) {
        _notificationService.removeProgressNotification(task.id);
      }

      // 清理本地缓存文件（上传成功后立即清理）
      unawaited(_cleanupTaskFile(_allTasks[task.id]!));

      // 持久化任务
      _persistTasks();

      // 检查批次是否完成
      _checkBatchCompletion();
    } catch (e) {
      // 上传失败
      if (kDebugMode) {
        print('[上传队列] 任务上传失败: ${task.file.fileName}');
        print('[上传队列] 错误类型: ${e.runtimeType}');
        print('[上传队列] 错误信息: $e');
        if (e is Exception) {
          print('[上传队列] Exception.toString(): ${e.toString()}');
        }
      }

      // 移除进度通知
      if (_notificationsEnabled) {
        _notificationService.removeProgressNotification(task.id);
      }

      // 检查是否是用户取消
      final isCanceled =
          e.toString().contains('cancel') ||
          e.toString().contains('取消') ||
          e.toString().contains('暂停') ||
          e.toString().contains('网络断开');

      if (isCanceled) {
        return;
      }

      // 任务已被移除（用户删除），跳过重试和状态更新
      if (!_allTasks.containsKey(task.id)) {
        return;
      }

      // 获取友好的错误消息
      String userFriendlyMessage;
      bool canRetry = true;

      // 如果遇到认证异常，放弃所有重试，并清空当前所有的 NAS 任务（因为登录过期了都要重传）
      if (e is AuthException) {
        userFriendlyMessage = e.toString();
        canRetry = false; // 取消重试
        // 实际上可以遍历队列把等待中的任务也直接设为失败，这就很彻底
        for (var t in _taskQueue) {
          final canceledTask = t.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '未登录或登录已过期',
          );
          _allTasks[t.id] = canceledTask;
          _notifyTaskUpdate(canceledTask);
        }
        _taskQueue.clear();
      } else if (e is NasUploadException) {
        userFriendlyMessage = e.userFriendlyMessage;
        canRetry = e.canRetry;
      } else if (e is DioException) {
        userFriendlyMessage = _getDioErrorMessage(e);
        canRetry = _isDioErrorRetryable(e);
      } else {
        // 提取异常中的有用信息，便于从用户截图排查问题
        String errDetail;
        if (e is Exception) {
          errDetail = e.toString().replaceFirst('Exception: ', '');
        } else {
          errDetail = e.toString();
        }
        // 限制长度避免 UI 溢出
        if (errDetail.length > 18) {
          errDetail = '${errDetail.substring(0, 18)}..';
        }
        userFriendlyMessage = '上传失败($errDetail)';
        canRetry = true;
      }

      // 确定分片大小
      final chunkSizeForCalc = _nasChunkedUploadService.chunkSize;

      // 检查是否需要重试
      if (canRetry && task.retryCount < task.maxRetries) {
        final retryTask = uploadingTask.copyWith(
          status: UploadTaskStatus.queued,
          progress: task.file.completedChunks.isNotEmpty
              ? (task.file.completedChunks.length /
                    ((task.file.fileSize / chunkSizeForCalc).ceil()) *
                    100)
              : 0,
          retryCount: task.retryCount + 1,
          errorMessage: userFriendlyMessage,
        );
        _allTasks[task.id] = retryTask;
        _notifyTaskUpdate(retryTask);

        // 指数退避延迟重试: 2s → 4s → 8s，避免立即重试加重服务器负担
        final delaySeconds = 2 << task.retryCount;
        if (kDebugMode) {
          print(
            '[上传队列] $delaySeconds秒后重试第${task.retryCount + 1}次: ${task.file.fileName}',
          );
        }
        Future.delayed(Duration(seconds: delaySeconds), () {
          // 延迟期间如果任务被取消则不再入队
          if (_allTasks[task.id]?.status == UploadTaskStatus.queued) {
            _taskQueue.add(retryTask);
            _processQueue();
          }
        });
      } else {
        final failedTask = uploadingTask.copyWith(
          status: UploadTaskStatus.failed,
          errorMessage: userFriendlyMessage,
        );
        failedTask.completedAt = DateTime.now();
        failedTask.lastUpdatedAt = DateTime.now();
        _allTasks[task.id] = failedTask;
        _notifyTaskUpdate(failedTask);

        _persistTasks();
        _checkBatchCompletion();
      }
    } finally {
      _activeTasks.remove(task.id);
      _notifyQueueUpdate();
      _processQueue();
    }
  }

  /// 检查当前批次是否完成
  void _checkBatchCompletion() {
    if (_currentBatchTaskIds.isEmpty) return;

    // 统计当前批次的任务状态
    int completedCount = 0;
    int failedCount = 0;
    int pendingCount = 0;

    for (final taskId in _currentBatchTaskIds) {
      final task = _allTasks[taskId];
      if (task == null) continue;

      switch (task.status) {
        case UploadTaskStatus.completed:
          completedCount++;
          break;
        case UploadTaskStatus.failed:
          failedCount++;
          break;
        case UploadTaskStatus.canceled:
          // 取消的任务不计入统计
          break;
        default:
          pendingCount++;
      }
    }

    // 如果还有等待中的任务，不发送完成通知
    if (pendingCount > 0) return;

    // 批次完成

    // 结束灵动岛活动（iOS 16.1+）
    if (_liveActivityService.isSupported) {
      _liveActivityService.endUploadActivity(
        successCount: completedCount,
        failedCount: failedCount,
      );
    }

    // 显示完成通知（iOS 上总是显示）
    // 编辑模式下不显示通知
    if (_notificationsEnabled &&
        _currentBatchEditId == null &&
        (completedCount > 0 || failedCount > 0)) {
      _notificationService.showCompletionNotification(
        successCount: completedCount,
        failedCount: failedCount,
        editId: null, // 非编辑模式不传递 editId
      );
    }

    // 清空批次
    _currentBatchTaskIds.clear();
  }

  /// 更新灵动岛进度
  void _updateLiveActivity() {
    if (!_liveActivityService.isSupported) return;
    if (_currentBatchTaskIds.isEmpty) return;

    // 统计当前批次的进度
    int completedFiles = 0;
    double totalProgress = 0;
    String? currentFileName;

    for (final taskId in _currentBatchTaskIds) {
      final task = _allTasks[taskId];
      if (task == null) continue;

      if (task.status == UploadTaskStatus.completed) {
        completedFiles++;
        totalProgress += 100;
      } else if (task.status == UploadTaskStatus.uploading) {
        totalProgress += task.progress;
        currentFileName ??= task.file.fileName;
      } else if (task.status == UploadTaskStatus.queued) {
        // 等待中
      }
    }

    final averageProgress = _currentBatchTaskIds.isNotEmpty
        ? (totalProgress / _currentBatchTaskIds.length).toInt()
        : 0;

    _liveActivityService.updateProgress(
      fileName: currentFileName ?? '上传中',
      progress: averageProgress,
      completedFiles: completedFiles,
      totalFiles: _currentBatchTaskIds.length,
    );
  }

  /// 通知任务更新
  void _notifyTaskUpdate(UploadTask task) {
    if (!_taskController.isClosed) {
      _taskController.add(task);
    }
  }

  /// 通知队列更新
  void _notifyQueueUpdate() {
    if (!_queueController.isClosed) {
      _queueController.add(Map<String, UploadTask>.from(_allTasks));
    }
  }

  /// 初始化上传队列管理器
  ///
  /// 从存储中恢复任务并启动自动保存
  Future<void> initialize() async {
    if (_tasksRestored) {
      return;
    }

    // 初始化网络服务
    await _initializeNetworkService();

    // 初始化通知服务
    await _initializeNotificationService();

    await _restoreTasksFromStorage();

    // 启动时清理已完成任务的缓存文件
    await cleanupTemporaryCache();

    _startAutoSaveTimer();
    _tasksRestored = true;
  }

  /// 初始化网络服务
  Future<void> _initializeNetworkService() async {
    try {
      await _networkService.initialize();

      // 获取初始网络状态
      _isNetworkAvailable = _networkService.isConnected;

      // 监听网络状态变化
      _networkSubscription = _networkService.networkStream.listen(
        _handleNetworkChange,
        onError: (error) {},
      );
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 初始化网络服务失败: $e');
      }
      // 默认假设网络可用
      _isNetworkAvailable = true;
    }
  }

  /// 初始化通知服务
  Future<void> _initializeNotificationService() async {
    try {
      await _notificationService.initialize();
      await _liveActivityService.initialize();
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 初始化通知服务失败: $e');
      }
    }
  }

  /// 处理网络状态变化
  void _handleNetworkChange(NetworkInfo info) {
    final wasConnected = _isNetworkAvailable;
    _isNetworkAvailable = info.isConnected;

    if (!wasConnected && info.isConnected) {
      // 网络恢复：自动恢复失败的任务和暂停的任务
      _resumeNetworkPausedTasks();
      // 同时自动重试所有因网络问题失败的任务
      _retryNetworkFailedTasks();
    } else if (wasConnected && !info.isConnected) {
      // 网络断开：记录当前正在上传和排队的任务
      // 这样网络恢复后可以自动恢复它们
      _pauseTasksForNetworkDisconnection();

      // 网络断开，立即更新灵动岛（显示暂停或保持进度但停止转圈，这里主要是保持显示）
      _refreshLiveActivityState();
    }
  }

  /// 网络恢复后自动恢复任务
  void _resumeNetworkPausedTasks() {
    if (_networkPausedTasks.isEmpty) {
      return;
    }

    for (final taskId in _networkPausedTasks.toList()) {
      final task = _allTasks[taskId];
      if (task != null && task.status == UploadTaskStatus.paused) {
        // 恢复任务
        final resumedTask = task.copyWith(
          status: UploadTaskStatus.queued,
          errorMessage: null,
        );
        resumedTask.lastUpdatedAt = DateTime.now();
        _allTasks[taskId] = resumedTask;
        _taskQueue.add(resumedTask);

        _notifyTaskUpdate(resumedTask);
      }
    }

    // 清空网络暂停列表
    _networkPausedTasks.clear();

    _notifyQueueUpdate();
    _processQueue();
    _persistTasks();
  }

  /// 网络断开时暂停正在上传和排队的任务
  void _pauseTasksForNetworkDisconnection() {
    // 记录所有正在上传和排队中的任务
    for (final task in _allTasks.values) {
      if (task.status == UploadTaskStatus.uploading ||
          task.status == UploadTaskStatus.queued) {
        _networkPausedTasks.add(task.id);

        // 如果任务正在上传，取消它并更新状态
        if (task.status == UploadTaskStatus.uploading) {
          task.cancelToken?.cancel('网络断开');
          _activeTasks.remove(task.id);

          // 更新任务状态为暂停
          final pausedTask = task.copyWith(
            status: UploadTaskStatus.paused,
            errorMessage: '网络已断开',
          );
          pausedTask.lastUpdatedAt = DateTime.now();
          _allTasks[task.id] = pausedTask;
          _notifyTaskUpdate(pausedTask);
        } else if (task.status == UploadTaskStatus.queued) {
          // 排队中的任务也标记为暂停
          final pausedTask = task.copyWith(
            status: UploadTaskStatus.paused,
            errorMessage: '网络已断开',
          );
          pausedTask.lastUpdatedAt = DateTime.now();
          _allTasks[task.id] = pausedTask;

          // 从队列中移除
          _taskQueue.removeWhere((t) => t.id == task.id);
          _notifyTaskUpdate(pausedTask);
        }
      }
    }

    // 通知队列更新
    _notifyQueueUpdate();

    // 持久化任务状态
    _persistTasks();
  }

  /// 网络恢复后重试所有因网络问题失败的任务
  void _retryNetworkFailedTasks() {
    final failedTasks = _allTasks.values.where((task) {
      // 只重试因网络问题失败的任务
      return task.status == UploadTaskStatus.failed &&
          task.errorMessage != null &&
          (task.errorMessage!.contains('网络') ||
              task.errorMessage!.contains('连接') ||
              task.errorMessage!.contains('超时') ||
              task.errorMessage!.contains('unreachable'));
    }).toList();

    if (failedTasks.isEmpty) {
      return;
    }

    for (final task in failedTasks) {
      // 重置任务状态
      final retriedTask = task.copyWith(
        status: UploadTaskStatus.queued,
        errorMessage: null,
      );
      retriedTask.completedAt = null;
      retriedTask.lastUpdatedAt = DateTime.now();
      _allTasks[task.id] = retriedTask;
      _taskQueue.add(retriedTask);

      _notifyTaskUpdate(retriedTask);
    }

    _notifyQueueUpdate();
    _processQueue();
    _persistTasks();
  }

  /// 从存储中恢复任务
  Future<void> _restoreTasksFromStorage() async {
    try {
      final persistedTasks = await _repository.loadTasks();

      if (persistedTasks.isEmpty) {
        return;
      }

      for (final pTask in persistedTasks) {
        try {
          // 跳过旧的 OSS 任务（已全面切换到 NAS）
          if (pTask.storageType != 'nas') {
            if (kDebugMode) {
              print('[上传队列] 跳过非NAS任务: ${pTask.taskId} (${pTask.storageType})');
            }
            continue;
          }

          // 判断任务是否需要继续上传（非已完成/已取消）
          final needsUpload = pTask.isResumable();

          // 1. 验证文件存在（仅对需要继续上传的任务）
          if (needsUpload && pTask.localPath.isNotEmpty) {
            final file = File(pTask.localPath);
            if (!await file.exists()) {
              if (kDebugMode) {
                print('[上传队列] 任务 ${pTask.taskId} 的文件不存在: ${pTask.localPath}');
              }
              continue;
            }
          }

          // 2. 重建 UploadFile
          final uploadFile = UploadFile(
            localPath: pTask.localPath,
            fileName: pTask.fileName,
            fileSize: pTask.fileSize,
            fileType: UploadFile.getFileType(pTask.fileName),
            id: pTask.taskId,
            status: UploadFileStatus.values[pTask.status.index],
            progress: pTask.progress,
            remoteUrl: pTask.resultFileUrl,
            ossFilePath: pTask.uploadingOssPath ?? pTask.resultOssPath,
            errorMessage: pTask.errorMessage,
            backendTaskId: pTask.backendTaskId,
            backendUploadId: pTask.backendUploadId,
            completedChunks: pTask.completedChunks,
            thumbnailUrl: pTask.thumbnailUrl,
            thumbnailPath: pTask.thumbnailPath,
            createdAt: pTask.createdAt,
          );

          // 3. 重建 UploadTask
          final task = UploadTask(
            id: pTask.taskId,
            file: uploadFile,
            storageType: pTask.storageType,
            hospitalName: pTask.hospitalName,
            status: pTask.status,
            progress: pTask.progress,
            errorMessage: pTask.errorMessage,
            retryCount: pTask.retryCount,
            createdAt: pTask.createdAt,
            completedAt: pTask.completedAt,
            lastUpdatedAt: pTask.lastUpdatedAt,
          );

          // 4. 恢复结果（如果已完成）
          if (pTask.resultFileUrl != null && pTask.resultOssPath != null) {
            // 根据文件类型恢复缩略图/视频截帧信息
            ThumbnailInfo? thumbnail;
            VideoFrameInfo? videoFrame;
            if (pTask.thumbnailUrl != null && pTask.thumbnailPath != null) {
              if (uploadFile.fileType == UploadFileType.image) {
                thumbnail = ThumbnailInfo(
                  fileName: '',
                  filePath: pTask.thumbnailPath!,
                  fileUrl: pTask.thumbnailUrl!,
                  fileSize: 0,
                );
              } else if (uploadFile.fileType == UploadFileType.video) {
                videoFrame = VideoFrameInfo(
                  fileName: '',
                  filePath: pTask.thumbnailPath!,
                  fileUrl: pTask.thumbnailUrl!,
                  fileSize: 0,
                );
              }
            }

            task.nasResult = NasUploadedFileInfo(
              fileName: pTask.fileName,
              originalName: pTask.fileName,
              filePath: pTask.resultOssPath!,
              fileUrl: pTask.resultFileUrl!,
              fileSize: pTask.fileSize,
              fileType: uploadFile.fileType,
              storageType: 'nas',
              thumbnail: thumbnail,
              videoFrame: videoFrame,
            );
          }

          // 5. 添加到任务列表
          _allTasks[task.id] = task;

          // 6. 只有需要继续上传的任务才加入队列
          if (needsUpload) {
            if (task.status == UploadTaskStatus.uploading) {
              final queuedTask = task.copyWith(status: UploadTaskStatus.queued);
              _allTasks[task.id] = queuedTask;
              _taskQueue.add(queuedTask);
            } else if (task.status == UploadTaskStatus.queued ||
                task.status == UploadTaskStatus.paused) {
              _taskQueue.add(task);
            }

            if (task.status != UploadTaskStatus.completed &&
                task.status != UploadTaskStatus.canceled &&
                task.status != UploadTaskStatus.failed) {
              _currentBatchTaskIds.add(task.id);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[上传队列] 恢复任务 ${pTask.taskId} 失败: $e');
          }
        }
      }

      // 通知UI更新
      _notifyQueueUpdate();

      // 尝试启动或更新灵动岛
      _refreshLiveActivityState();

      // 自动开始处理队列

      if (_taskQueue.isNotEmpty) {
        _processQueue();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 恢复任务失败: $e');
      }
    }
  }

  /// 手动保存任务（公共方法，用于外部触发保存）
  Future<void> saveTasks() async {
    await _persistTasks();
  }

  /// 持久化任务到存储
  Future<void> _persistTasks() async {
    try {
      final persistedTasks = _allTasks.values
          .map((task) => task.toPersistedTask())
          .toList();
      await _repository.saveTasks(persistedTasks);

      // if (kDebugMode) {
      //   print('[上传队列] 已保存 ${persistedTasks.length} 个任务');
      // }
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 保存任务失败: $e');
      }
    }
  }

  /// 启动自动保存定时器
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _persistTasks();
    });
  }

  /// 清理任务的本地文件（仅清理 FilePicker 创建的临时副本）
  ///
  /// 注意：只清理临时缓存目录中的文件，不清理用户原始文件
  Future<void> _cleanupTaskFile(UploadTask task) async {
    // 如果没有本地路径，无需清理
    if (task.file.localPath.isEmpty) return;

    try {
      final file = File(task.file.localPath);

      // 检查文件是否存在
      if (!file.existsSync()) {
        return;
      }

      // 获取应用缓存目录
      final tempDir = await getTemporaryDirectory();
      final tempPath = tempDir.path;

      // Android 上还需要检查外部缓存目录
      List<String> cachePaths = [tempPath];
      if (Platform.isAndroid) {
        try {
          final externalCacheDirs = await getExternalCacheDirectories();
          if (externalCacheDirs != null) {
            cachePaths.addAll(externalCacheDirs.map((dir) => dir.path));
          }
        } catch (e) {
          // 忽略外部缓存目录获取失败
        }
      }

      // 判断文件是否在缓存目录中
      final filePath = file.path;
      bool isCacheFile = false;

      for (final cachePath in cachePaths) {
        if (filePath.startsWith(cachePath)) {
          isCacheFile = true;
          break;
        }
      }

      // 额外检查：文件路径包含 file_picker 或 image_picker 关键字
      if (!isCacheFile) {
        isCacheFile =
            filePath.contains('file_picker') ||
            filePath.contains('image_picker') ||
            filePath.contains('/cache/') ||
            filePath.contains('\\cache\\');
      }

      if (!isCacheFile) {
        // 不是缓存文件，可能是用户的原始文件，不删除
        return;
      }

      // 删除文件
      await file.delete();

      // 如果是 image_picker 压缩后的 scaled_ 文件，同时清理原始副本
      // image_picker 使用 imageQuality 参数时会创建两个文件：
      // 1. 原始图片的副本（可能在同目录或 image_picker 子目录）
      // 2. 压缩后的文件（例如 scaled_IMG_xxx.jpg）
      final fileName = task.file.fileName;
      if (fileName.startsWith('scaled_')) {
        final originalFileName = fileName.substring(7); // 去掉 'scaled_' 前缀
        final directory = file.parent;

        // 搜索可能的原始文件位置
        final possiblePaths = <String>[
          // 1. 同目录下
          '${directory.path}${Platform.pathSeparator}$originalFileName',
          // 2. image_picker 子目录
          '${directory.path}${Platform.pathSeparator}image_picker${Platform.pathSeparator}$originalFileName',
        ];

        // 同时搜索父目录及其子目录
        try {
          final cacheDir = directory;
          if (await cacheDir.exists()) {
            await for (final entity in cacheDir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entity is File) {
                final entityName = entity.path
                    .split(Platform.pathSeparator)
                    .last;
                // 匹配原始文件名（不带 scaled_ 前缀）
                if (entityName == originalFileName) {
                  possiblePaths.add(entity.path);
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[上传队列] 搜索原始文件时出错: $e');
          }
        }

        // 尝试删除所有找到的原始文件
        for (final path in possiblePaths.toSet()) {
          // 去重
          final originalFile = File(path);
          if (await originalFile.exists()) {
            try {
              await originalFile.delete();
            } catch (e) {
              if (kDebugMode) {
                print('[上传队列] 清理原始副本失败: $path - $e');
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 清理文件失败: ${task.file.fileName} - $e');
      }
    }
  }

  /// 刷新灵动岛状态（集中管理）
  ///
  /// 此方法根据当前 _currentBatchTaskIds 的状态来决定：
  /// 1. 启动活动（如果有任务且未开始）
  /// 2. 更新进度（如果有任务且已开始）
  /// 3. 结束活动（如果没有任务）
  Future<void> _refreshLiveActivityState() async {
    if (!_liveActivityService.isSupported) return;

    if (_currentBatchTaskIds.isEmpty) {
      // 检查是否有任何未完成的任务需要加入批次
      bool hasPendingTasks = false;
      for (final task in _allTasks.values) {
        if (task.status == UploadTaskStatus.queued ||
            task.status == UploadTaskStatus.uploading ||
            task.status == UploadTaskStatus.paused) {
          _currentBatchTaskIds.add(task.id);
          hasPendingTasks = true;
        }
      }

      // 如果仍然没有任务，尝试结束活动（兜底）
      if (!hasPendingTasks) {
        return;
      }
    }

    // 重新统计状态
    int completedFiles = 0;
    int failedFiles = 0;
    double totalProgress = 0;
    int totalFiles = _currentBatchTaskIds.length;
    String? currentFileName;

    // 检查是否所有任务都已完成/失败
    bool allFinished = true;

    for (final taskId in _currentBatchTaskIds) {
      final task = _allTasks[taskId];
      if (task == null) continue;

      if (task.status == UploadTaskStatus.completed) {
        completedFiles++;
        totalProgress += 100;
      } else if (task.status == UploadTaskStatus.failed) {
        failedFiles++;
        // 失败的任务不算进度，或者是0
      } else if (task.status == UploadTaskStatus.uploading) {
        totalProgress += task.progress;
        currentFileName ??= task.file.fileName; // 优先显示正在上传的文件名
        allFinished = false;
      } else if (task.status == UploadTaskStatus.queued ||
          task.status == UploadTaskStatus.paused) {
        // 排队或暂停的任务
        allFinished = false;
      } else if (task.status == UploadTaskStatus.canceled) {
        // 已取消的任务不计入总数，但如果它在 batch 里，会影响计数
        // 这里简单处理：不做特殊处理
      }
    }

    // 如果没有正在上传的文件，且有文件在队列，取第一个作为显示名称
    if (currentFileName == null && !allFinished) {
      // 查找第一个排队或暂停的任务
      for (final taskId in _currentBatchTaskIds) {
        final task = _allTasks[taskId];
        if (task != null &&
            (task.status == UploadTaskStatus.queued ||
                task.status == UploadTaskStatus.paused)) {
          currentFileName = task.file.fileName;
          break;
        }
      }
    }

    // 如果所有任务都完成了，结束活动
    if (allFinished && totalFiles > 0) {
      _liveActivityService.endUploadActivity(
        successCount: completedFiles,
        failedCount: failedFiles,
      );
      _currentBatchTaskIds.clear();
      return;
    }

    // 计算平均进度
    final averageProgress = totalFiles > 0
        ? (totalProgress / totalFiles).toInt()
        : 0;

    // 强制更新一次
    await _liveActivityService.updateProgress(
      fileName: currentFileName ?? '等待上传...',
      progress: averageProgress,
      completedFiles: completedFiles,
      totalFiles: totalFiles,
    );
  }

  /// 获取所有活跃（未完成）上传任务的本地文件路径
  ///
  /// 用于缓存清理时跳过这些文件，防止正在上传的文件被误删
  Set<String> getActiveUploadFilePaths() {
    final paths = <String>{};
    for (final task in _allTasks.values) {
      if (task.status != UploadTaskStatus.completed &&
          task.status != UploadTaskStatus.canceled &&
          task.file.localPath.isNotEmpty) {
        paths.add(task.file.localPath);
      }
    }
    return paths;
  }

  /// 移除本地文件已不存在的上传任务（从内存和持久化中移除）
  ///
  /// 当用户手动清理缓存后调用，清理掉无法继续上传的任务
  Future<void> removeTasksWithMissingFiles() async {
    final taskIdsToRemove = <String>[];

    for (final task in _allTasks.values) {
      // 已完成的任务不需要本地文件，保留
      if (task.status == UploadTaskStatus.completed) continue;
      // 已取消的任务也保留（用于历史记录）
      if (task.status == UploadTaskStatus.canceled) continue;

      // 检查本地文件是否存在
      if (task.file.localPath.isNotEmpty) {
        final file = File(task.file.localPath);
        if (!file.existsSync()) {
          taskIdsToRemove.add(task.id);
        }
      }
    }

    if (taskIdsToRemove.isEmpty) return;

    if (kDebugMode) {
      print('[上传队列] 清理 ${taskIdsToRemove.length} 个本地文件已丢失的任务');
    }

    for (final taskId in taskIdsToRemove) {
      final task = _allTasks[taskId];
      if (task != null) {
        // 取消正在上传的任务
        if (task.status == UploadTaskStatus.uploading) {
          task.cancelToken?.cancel('文件已被清理');
          _activeTasks.remove(taskId);
        }
        // 从队列中移除
        _taskQueue.removeWhere((t) => t.id == taskId);
        // 从批次中移除
        _currentBatchTaskIds.remove(taskId);
        _networkPausedTasks.remove(taskId);
      }
      _allTasks.remove(taskId);
    }

    _notifyQueueUpdate();
    await _persistTasks();
  }

  /// 清理所有临时缓存文件（应用启动时调用）
  Future<void> cleanupTemporaryCache() async {
    try {
      for (final task in _allTasks.values) {
        if (task.status == UploadTaskStatus.completed) {
          await _cleanupTaskFile(task);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[上传队列] 清理临时缓存失败: $e');
      }
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    // 停止自动保存定时器
    _autoSaveTimer?.cancel();

    // 取消网络监听
    _networkSubscription?.cancel();

    // 清理所有已完成和已取消任务的本地文件
    // 注意：未完成任务的本地文件需要保留，以便应用重启后继续上传
    for (var task in _allTasks.values) {
      if (task.status == UploadTaskStatus.completed ||
          task.status == UploadTaskStatus.canceled) {
        await _cleanupTaskFile(task);
      }
    }

    // 最后保存一次
    await _persistTasks();

    _queueController.close();
    _taskController.close();

    // 取消所有进行中的任务
    for (var task in _activeTasks.values) {
      task.cancelToken?.cancel('应用关闭');
    }

    _taskQueue.clear();
    _activeTasks.clear();
    _allTasks.clear();
    _networkPausedTasks.clear();
  }

  /// 获取 Dio 错误的友好消息（含简短错误标识，便于排查）
  String _getDioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '上传失败(连接超时)';
      case DioExceptionType.sendTimeout:
        return '上传失败(发送超时)';
      case DioExceptionType.receiveTimeout:
        return '上传失败(响应超时)';
      case DioExceptionType.transformTimeout:
        return '上传失败(响应解析超时)';
      case DioExceptionType.badCertificate:
        return '上传失败(证书错误)';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return '登录已过期，请重新登录';
        } else if (statusCode == 403) {
          return '没有上传权限';
        } else if (statusCode == 413) {
          return '文件太大，无法上传';
        } else if (statusCode != null && statusCode >= 500) {
          return '上传失败(服务器$statusCode)';
        }
        return '上传失败(HTTP$statusCode)';
      case DioExceptionType.cancel:
        return '上传已取消';
      case DioExceptionType.connectionError:
        return '上传失败(网络连接异常)';
      case DioExceptionType.unknown:
        if (e.error.toString().contains('SocketException') ||
            e.error.toString().contains('Network is unreachable')) {
          return '上传失败(网络不可用)';
        }
        return '上传失败(未知网络错误)';
    }
  }

  /// 判断 Dio 错误是否可以重试
  bool _isDioErrorRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        // 5xx 错误可以重试
        if (statusCode != null && statusCode >= 500 && statusCode < 600) {
          return true;
        }
        // 401/403 不重试
        if (statusCode == 401 || statusCode == 403 || statusCode == 413) {
          return false;
        }
        return true;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
      case DioExceptionType.unknown:
        return true;
    }
  }
}
