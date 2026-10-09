import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:io';
import '../services/upload_queue_manager.dart';
import '../models/upload_file.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';

/// 上传管理页面 - 显示所有上传任务的状态
class UploadManagerPage extends StatefulWidget {
  const UploadManagerPage({super.key});

  @override
  State<UploadManagerPage> createState() => _UploadManagerPageState();
}

class _UploadManagerPageState extends State<UploadManagerPage> {
  final UploadQueueManager _queueManager = UploadQueueManager();
  List<UploadTask> _tasks = [];
  StreamSubscription<Map<String, UploadTask>>? _queueSubscription;
  StreamSubscription<UploadTask>? _taskSubscription;

  // 过滤器
  UploadTaskStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _subscribeToQueue();
    _subscribeToTaskUpdates();
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _taskSubscription?.cancel();
    super.dispose();
  }

  /// 加载任务列表
  void _loadTasks() {
    setState(() {
      if (_filterStatus == null) {
        _tasks = _queueManager.getAllTasks();
      } else {
        _tasks = _queueManager.getTasksByStatus(_filterStatus!);
      }
    });
  }

  /// 订阅队列更新
  void _subscribeToQueue() {
    _queueSubscription = _queueManager.queueStream.listen((tasks) {
      _loadTasks();
    });
  }

  /// 订阅任务更新（用于实时进度更新）
  void _subscribeToTaskUpdates() {
    _taskSubscription = _queueManager.taskStream.listen((task) {
      if (mounted) {
        setState(() {
          // 更新任务列表中对应的任务
          final index = _tasks.indexWhere((t) => t.id == task.id);
          if (index >= 0) {
            _tasks[index] = task;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 状态栏背景透明
        statusBarIconBrightness: Brightness.dark, // Android 深色图标
        statusBarBrightness: Brightness.light, // iOS 深色图标
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text('上传管理'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF333333),
          elevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          actions: [
            // 清理已完成任务
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _showClearDialog,
              tooltip: '清理已完成',
            ),
          ],
        ),
        body: Column(
          children: [
            // 状态筛选栏
            _buildFilterBar(),
            // 任务统计
            _buildStatistics(),
            // 任务列表
            Expanded(
              child: _tasks.isEmpty ? _buildEmptyView() : _buildTaskList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('全部', null),
            const SizedBox(width: 8),
            _buildFilterChip('队列中', UploadTaskStatus.queued),
            const SizedBox(width: 8),
            _buildFilterChip('上传中', UploadTaskStatus.uploading),
            const SizedBox(width: 8),
            _buildFilterChip('已完成', UploadTaskStatus.completed),
            const SizedBox(width: 8),
            _buildFilterChip('失败', UploadTaskStatus.failed),
            const SizedBox(width: 8),
            _buildFilterChip('已暂停', UploadTaskStatus.paused),
          ],
        ),
      ),
    );
  }

  /// 构建筛选标签
  Widget _buildFilterChip(String label, UploadTaskStatus? status) {
    final isActive = _filterStatus == status;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterStatus = status;
          _loadTasks();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF366CDF) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isActive ? Colors.white : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  /// 构建统计信息
  Widget _buildStatistics() {
    final queuedCount = _queueManager
        .getTasksByStatus(UploadTaskStatus.queued)
        .length;
    final uploadingCount = _queueManager
        .getTasksByStatus(UploadTaskStatus.uploading)
        .length;
    final completedCount = _queueManager
        .getTasksByStatus(UploadTaskStatus.completed)
        .length;
    final failedCount = _queueManager
        .getTasksByStatus(UploadTaskStatus.failed)
        .length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('队列中', queuedCount, const Color(0xFF2196F3)),
          _buildStatItem('上传中', uploadingCount, const Color(0xFFFF9800)),
          _buildStatItem('已完成', completedCount, const Color(0xFF4CAF50)),
          _buildStatItem('失败', failedCount, const Color(0xFFF44336)),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
      ],
    );
  }

  /// 构建任务列表
  Widget _buildTaskList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        return _buildTaskItem(_tasks[index]);
      },
    );
  }

  /// 构建任务项
  Widget _buildTaskItem(UploadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件信息行
          Row(
            children: [
              _buildFileThumbnail(task),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.file.fileName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          task.file.formattedSize,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(task.status),
                      ],
                    ),
                  ],
                ),
              ),
              _buildActionButtons(task),
            ],
          ),
          // 进度条（上传中或暂停状态显示）
          if (task.status == UploadTaskStatus.uploading ||
              task.status == UploadTaskStatus.paused) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: task.progress / 100,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      task.status == UploadTaskStatus.paused
                          ? Colors.grey
                          : const Color(0xFF366CDF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${task.progress.toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          // 错误信息
          if (task.status == UploadTaskStatus.failed &&
              task.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              task.errorMessage!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// 构建文件缩略图（支持本地图片/视频预览）
  /// 同步 material_upload_page.dart 的缩略图逻辑
  Widget _buildFileThumbnail(UploadTask task) {
    final file = task.file;

    // 图片文件：优先显示缩略图
    if (file.fileType == UploadFileType.image) {
      // 如果上传成功且有远程URL，显示远程缩略图
      if (task.status == UploadTaskStatus.completed && file.remoteUrl != null) {
        // 优先使用后端返回的缩略图 URL（NAS 模式）
        // 如果没有，则使用 OSS 图片处理参数
        final thumbnailUrl =
            file.thumbnailUrl ?? _getImageThumbnailUrl(file.remoteUrl!);
        return _buildNetworkThumbnail(thumbnailUrl, UploadFileType.image);
      }

      // 否则尝试显示本地缩略图
      if (file.localPath.isNotEmpty) {
        final localFile = File(file.localPath);
        if (localFile.existsSync()) {
          return _buildLocalThumbnail(file.localPath, UploadFileType.image);
        }
      }
    }

    // 视频文件：如果上传成功，显示截帧缩略图
    if (file.fileType == UploadFileType.video) {
      if (task.status == UploadTaskStatus.completed && file.remoteUrl != null) {
        // 优先使用后端返回的视频截帧 URL（NAS 模式）
        // 如果没有，则使用 OSS 视频截帧参数
        final snapshotUrl =
            file.thumbnailUrl ?? _getVideoSnapshotUrl(file.remoteUrl!);
        return _buildNetworkThumbnail(snapshotUrl, UploadFileType.video);
      }
    }

    // 其他情况：显示文件图标
    return _buildFileIcon(file.fileType);
  }

  /// 获取图片缩略图 URL
  /// 优先使用接口返回的 thumbnail 字段，如果不存在则使用 url 拼接参数
  String _getImageThumbnailUrl(String originalUrl) {
    final separator = originalUrl.contains('?') ? '&' : '?';
    return '$originalUrl${separator}x-oss-process=image/resize,w_120';
  }

  /// 获取视频截帧 URL
  /// 优先使用接口返回的 thumbnail 字段，如果不存在则使用 url 拼接参数
  String _getVideoSnapshotUrl(String originalUrl) {
    final separator = originalUrl.contains('?') ? '&' : '?';
    return '$originalUrl${separator}x-oss-process=video/snapshot,t_1000,ar_auto,f_jpg,h_200';
  }

  /// 构建本地缩略图
  Widget _buildLocalThumbnail(String localPath, UploadFileType fileType) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(localPath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // 加载失败时显示图标
            return _buildFileIcon(fileType);
          },
        ),
      ),
    );
  }

  /// 构建网络缩略图
  /// thumbnailUrl 已经是处理好的缩略图地址（包含 OSS 参数或 NAS 缩略图 URL）
  Widget _buildNetworkThumbnail(String thumbnailUrl, UploadFileType fileType) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: thumbnailUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          memCacheWidth: 96,
          maxWidthDiskCache: 96,
          placeholder: (context, url) => Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => _buildFileIcon(fileType),
        ),
      ),
    );
  }

  /// 构建文件图标（后备方案）
  Widget _buildFileIcon(UploadFileType type) {
    IconData icon;
    Color color;

    switch (type) {
      case UploadFileType.image:
        icon = Icons.image;
        color = const Color(0xFF4CAF50);
        break;
      case UploadFileType.video:
        icon = Icons.videocam;
        color = const Color(0xFFFF9800);
        break;
      case UploadFileType.audio:
        icon = Icons.audiotrack;
        color = const Color(0xFF9C27B0);
        break;
      case UploadFileType.document:
        icon = Icons.insert_drive_file;
        color = const Color(0xFF2196F3);
        break;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  /// 构建状态标签
  Widget _buildStatusBadge(UploadTaskStatus status) {
    String text;
    Color color;

    switch (status) {
      case UploadTaskStatus.queued:
        text = '队列中';
        color = const Color(0xFF2196F3);
        break;
      case UploadTaskStatus.uploading:
        text = '上传中';
        color = const Color(0xFFFF9800);
        break;
      case UploadTaskStatus.completed:
        text = '已完成';
        color = const Color(0xFF4CAF50);
        break;
      case UploadTaskStatus.failed:
        text = '失败';
        color = const Color(0xFFF44336);
        break;
      case UploadTaskStatus.canceled:
        text = '已取消';
        color = const Color(0xFF9E9E9E);
        break;
      case UploadTaskStatus.paused:
        text = '已暂停';
        color = const Color(0xFF9E9E9E);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(UploadTask task) {
    switch (task.status) {
      case UploadTaskStatus.queued:
        return IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => _queueManager.cancelTask(task.id),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      case UploadTaskStatus.uploading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.pause, size: 20),
              onPressed: () => _queueManager.pauseTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => _queueManager.cancelTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        );
      case UploadTaskStatus.completed:
        return const Icon(
          Icons.check_circle,
          color: Color(0xFF4CAF50),
          size: 24,
        );
      case UploadTaskStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _queueManager.retryTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _queueManager.removeTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        );
      case UploadTaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: () => _queueManager.resumeTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _queueManager.removeTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        );
      case UploadTaskStatus.canceled:
        return IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _queueManager.removeTask(task.id),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
    }
  }

  /// 构建空视图
  Widget _buildEmptyView() {
    return EmptyStateWidget(
      icon: Icons.cloud_upload_outlined,
      message: _filterStatus == null
          ? '暂无上传任务'
          : '暂无${_getFilterStatusText()}任务',
    );
  }

  /// 获取筛选状态文本
  String _getFilterStatusText() {
    switch (_filterStatus) {
      case UploadTaskStatus.queued:
        return '队列中';
      case UploadTaskStatus.uploading:
        return '上传中';
      case UploadTaskStatus.completed:
        return '已完成';
      case UploadTaskStatus.failed:
        return '失败';
      case UploadTaskStatus.paused:
        return '已暂停';
      case UploadTaskStatus.canceled:
        return '已取消';
      case null:
        return '';
    }
  }

  /// 显示清理对话框
  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理已完成任务'),
        content: const Text('确定要清理所有已完成、失败和已取消的任务吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              _queueManager.clearCompletedTasks();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已清理完成'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
