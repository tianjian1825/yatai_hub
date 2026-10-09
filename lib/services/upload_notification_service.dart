import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:live_activities/live_activities.dart';

/// 上传通知服务
/// 负责显示上传进度通知和完成通知
class UploadNotificationService {
  static final UploadNotificationService _instance =
      UploadNotificationService._internal();
  factory UploadNotificationService() => _instance;
  UploadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// 是否已初始化
  bool _initialized = false;

  /// 当前活跃的上传通知ID映射 (taskId -> notificationId)
  final Map<String, int> _activeNotifications = {};

  /// 通知ID计数器
  int _notificationIdCounter = 1000;

  /// 完成通知ID（固定）
  static const int _completionNotificationId = 9999;

  /// 上传进度通知渠道
  static const String _progressChannelId = 'upload_progress_v2';
  static const String _progressChannelName = '上传进度';
  static const String _progressChannelDescription = '显示文件上传进度';

  /// 完成通知渠道
  static const String _completionChannelId = 'upload_completion_v2';
  static const String _completionChannelName = '上传完成';
  static const String _completionChannelDescription = '上传完成后的通知';

  /// 通知点击回调
  Function(String? payload)? onNotificationTap;

  /// 初始化通知服务
  Future<void> initialize() async {
    if (_initialized) return;

    // Android 初始化设置
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS 初始化设置
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true, // 完成通知需要声音
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 创建通知渠道 (Android 8.0+)
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // 请求通知权限 (iOS & Android 13+)
    await _requestPermissions();

    _initialized = true;
  }

  /// 创建 Android 通知渠道
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) return;

    // 进度通知渠道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _progressChannelId,
        _progressChannelName,
        description: _progressChannelDescription,
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      ),
    );

    // 完成通知渠道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _completionChannelId,
        _completionChannelName,
        description: _completionChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  /// 请求通知权限
  Future<bool> _requestPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (kDebugMode) {
        print('[通知服务] iOS 通知权限请求结果: $granted');
      }

      return granted ?? false;
    } else if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();

      if (kDebugMode) {
        print('[通知服务] Android 通知权限请求结果: $granted');
      }

      return granted ?? false;
    }
    return false;
  }

  /// 处理通知点击
  void _onNotificationTap(NotificationResponse response) {
    onNotificationTap?.call(response.payload);
  }

  /// 设置 App 前后台状态
  /// 注意: 此方法保留用于兼容性,但当前未使用该状态
  void setAppInForeground(bool inForeground) {
    // 方法保留以保持接口兼容性
    // 如果将来需要根据前后台状态调整通知行为,可以在这里实现
  }

  /// 是否已打印过 iOS 跳过进度通知的日志
  bool _iosSkipLogPrinted = false;

  /// 显示上传进度通知
  ///
  /// [taskId] 任务ID
  /// [fileName] 文件名
  /// [progress] 进度 (0-100)
  Future<void> showProgressNotification({
    required String taskId,
    required String fileName,
    required int progress,
  }) async {
    // iOS 平台不显示进度通知，使用灵动岛代替
    if (Platform.isIOS) {
      if (kDebugMode && !_iosSkipLogPrinted) {
        // ignore: avoid_print
        _iosSkipLogPrinted = true;
      }
      return;
    }

    if (!_initialized) await initialize();

    // 获取或创建通知ID
    int notificationId;
    if (_activeNotifications.containsKey(taskId)) {
      notificationId = _activeNotifications[taskId]!;
    } else {
      notificationId = _notificationIdCounter++;
      _activeNotifications[taskId] = notificationId;
    }

    // 截断文件名（通知栏空间有限）
    final displayName = fileName.length > 30
        ? '${fileName.substring(0, 27)}...'
        : fileName;

    // Android 进度通知详情
    final androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: _progressChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true, // 持续通知，不可滑动移除
      autoCancel: false,
      onlyAlertOnce: true, // 只在第一次提醒
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.service, // 标记为服务类通知
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      // 添加大文本样式，明确告知用户后台运行
      styleInformation: const BigTextStyleInformation(
        '正在后台上传，请保持网络连接。退出APP不会中断上传。',
        contentTitle: '后台上传中',
        htmlFormatContentTitle: true,
        htmlFormatContent: true,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      // iOS 不需要设置，因为已经在上面返回了
    );

    await _notifications.show(
      id: notificationId,
      title: '正在上传',
      body: '$displayName ($progress%)',
      notificationDetails: details,
      payload: 'progress:$taskId',
    );
  }

  /// 移除上传进度通知
  ///
  /// [taskId] 任务ID
  Future<void> removeProgressNotification(String taskId) async {
    final notificationId = _activeNotifications.remove(taskId);
    if (notificationId != null) {
      await _notifications.cancel(id: notificationId);
    }
  }

  /// 移除所有进度通知
  Future<void> removeAllProgressNotifications() async {
    for (final notificationId in _activeNotifications.values) {
      await _notifications.cancel(id: notificationId);
    }
    _activeNotifications.clear();
  }

  /// 显示上传完成通知
  ///
  /// [successCount] 成功数量
  /// [failedCount] 失败数量
  /// [forceShow] 强制显示（iOS上灵动岛可用时也显示）
  /// [editId] 编辑记录ID，如果有则跳转到编辑页面
  Future<void> showCompletionNotification({
    required int successCount,
    required int failedCount,
    bool forceShow = false,
    int? editId,
  }) async {
    if (!_initialized) await initialize();

    // 先移除所有进度通知
    await removeAllProgressNotifications();

    String title;
    String body;

    if (failedCount == 0) {
      title = '素材上传已完成';
      body = '共 $successCount 个文件上传成功，点击前往提交';
    } else {
      title = '素材上传已完成';
      body = '$successCount 个成功，$failedCount 个失败，点击查看详情';
    }

    // Android 通知详情 - 确保弹出显示
    const androidDetails = AndroidNotificationDetails(
      _completionChannelId,
      _completionChannelName,
      channelDescription: _completionChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      playSound: true, // 使用默认声音
      enableVibration: true,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      // 添加大图标
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    // iOS 通知详情 - 允许在前台和后台弹出提醒
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true, // 弹出提醒
      presentBadge: true, // 显示角标
      presentSound: true, // 播放声音
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive, // 时效性通知，即时显示
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      // 构建 payload: completion:upload 或 completion:upload:editId={id}
      String payload = 'completion:upload';
      if (editId != null) {
        payload = 'completion:upload:editId=$editId';
      }

      await _notifications.show(
        id: _completionNotificationId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[通知服务] 显示完成通知失败: $e');
      }
    }
  }

  /// 取消完成通知
  Future<void> cancelCompletionNotification() async {
    await _notifications.cancel(id: _completionNotificationId);
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    _activeNotifications.clear();
  }
}

/// 灵动岛服务（iOS 16.1+）
/// 使用 live_activities 插件
class LiveActivityService {
  static final LiveActivityService _instance = LiveActivityService._internal();
  factory LiveActivityService() => _instance;
  LiveActivityService._internal();

  /// live_activities 插件实例
  final _liveActivitiesPlugin = LiveActivities();

  /// 是否支持灵动岛
  bool _isSupported = false;

  /// 当前活动ID
  String? _currentActivityId;

  /// 是否正在创建活动（防止并发创建多个实例）
  bool _isCreating = false;

  /// App Group ID（iOS 配置）
  static const String _appGroupId = 'group.com.amgroup.hub';

  /// 初始化
  Future<void> initialize() async {
    // 灵动岛仅 iOS 支持
    if (!Platform.isIOS) {
      _isSupported = false;
      return;
    }

    try {
      if (kDebugMode) {
        print('[灵动岛] 开始初始化，App Group: $_appGroupId');
      }

      // 初始化插件
      await _liveActivitiesPlugin.init(appGroupId: _appGroupId);

      // 先检查设备是否支持 Live Activities
      final isDeviceSupported = await _liveActivitiesPlugin
          .areActivitiesSupported();
      if (kDebugMode) {
        print('[灵动岛] 设备支持状态: $isDeviceSupported');
      }

      if (!isDeviceSupported) {
        _isSupported = false;
        if (kDebugMode) {
          print('[灵动岛] 设备不支持 Live Activities (需要 iPhone 14 Pro+ 且 iOS 16.1+)');
        }
        return;
      }

      // 检查用户是否启用了 Live Activities
      _isSupported = await _liveActivitiesPlugin.areActivitiesEnabled();

      if (kDebugMode) {
        print('[灵动岛] 用户启用状态: $_isSupported');
        if (!_isSupported) {
          print('[灵动岛] 请在 设置 > 面容ID与密码 > Live Activities 中开启');
        }
      }

      // 冷启动清理上一次会话残留的孤儿灵动岛。
      // 进程被强杀（上划）或系统因内存压力回收时，
      // removeWhenAppIsKilled 依赖的原生 applicationWillTerminate 回调不会触发，
      // 导致灵动岛冻结在最后一次上报的进度上（用户感知为「卡住」）。
      // 此刻 _currentActivityId 已随进程重置为 null，任何仍存活的活动都属于上一次会话，直接清掉。
      if (_isSupported) {
        await endAllActivities();
      }
    } catch (e, stack) {
      if (kDebugMode) {
        print('[灵动岛] 初始化失败: $e');
        print('[灵动岛] 堆栈: $stack');
      }
      _isSupported = false;
    }
  }

  /// 是否支持灵动岛
  bool get isSupported => _isSupported;

  /// 获取是否有活跃的 Live Activity
  bool get hasActiveActivity => _currentActivityId != null;

  /// 开始上传活动 (如果已存在则不重复创建，除非 forceNew = true)
  Future<void> startUploadActivity({
    required String fileName,
    required int totalFiles,
    bool forceNew = false,
  }) async {
    if (!_isSupported) {
      return;
    }

    // 防止并发创建多个灵动岛实例
    if (_isCreating) {
      return;
    }

    // 如果已经有活跃的 Activity 且不强制新建，则跳过
    if (_currentActivityId != null && !forceNew) {
      return;
    }

    _isCreating = true;
    try {
      // 生成唯一的 activity ID
      final activityId = 'upload_${DateTime.now().millisecondsSinceEpoch}';

      // 创建 Live Activity 数据
      final activityData = {
        'fileName': fileName,
        'completedFiles': 0,
        'totalFiles': totalFiles,
        'progress': 0,
        'isCompleted': false,
        'successCount': 0,
        'failedCount': 0,
      };

      // 创建 Live Activity
      // removeWhenAppIsKilled: true - 应用「正常」终止时移除灵动岛（注意：上划强杀/系统回收不触发此回调，
      //   孤儿活动靠冷启动 endAllActivities() + 回到前台对账兜底清理）
      // staleIn: 30秒 - 活动在30秒无更新后标记为过期变灰（iOS 16.2+），
      //   缩短时长让强杀后残留的灵动岛更快变灰，降低「冻结很久」的观感
      _currentActivityId = await _liveActivitiesPlugin.createActivity(
        activityId,
        activityData,
        removeWhenAppIsKilled: true,
        staleIn: const Duration(seconds: 30),
      );
    } catch (e, stack) {
      if (kDebugMode) {
        print('[灵动岛] 开始活动失败: $e');
        print('[灵动岛] 堆栈: $stack');
      }
    } finally {
      _isCreating = false;
    }
  }

  /// 更新上传进度
  Future<void> updateProgress({
    required String fileName,
    required int progress,
    required int completedFiles,
    required int totalFiles,
  }) async {
    if (!_isSupported) return;

    // 如果没有 ID，尝试启动一个新的（自动恢复）
    if (_currentActivityId == null) {
      await startUploadActivity(fileName: fileName, totalFiles: totalFiles);
      // start 可能会失败或延迟，如果仍然 null，则无法更新
      if (_currentActivityId == null) return;
    }

    try {
      // 更新数据
      final activityData = {
        'fileName': fileName,
        'completedFiles': completedFiles,
        'totalFiles': totalFiles,
        'progress': progress,
        'isCompleted': false,
        'successCount': 0,
        'failedCount': 0,
      };

      await _liveActivitiesPlugin.updateActivity(
        _currentActivityId!,
        activityData,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[灵动岛] 更新进度失败: $e');
      }
    }
  }

  /// 结束上传活动
  Future<void> endUploadActivity({
    required int successCount,
    required int failedCount,
  }) async {
    if (!_isSupported || _currentActivityId == null) return;

    try {
      // 先更新为完成状态
      final activityData = {
        'fileName': '',
        'completedFiles': successCount + failedCount,
        'totalFiles': successCount + failedCount,
        'progress': 100,
        'isCompleted': true,
        'successCount': successCount,
        'failedCount': failedCount,
      };

      await _liveActivitiesPlugin.updateActivity(
        _currentActivityId!,
        activityData,
      );

      // 延迟 3 秒后结束活动，让用户看到完成状态
      await Future.delayed(const Duration(seconds: 3));

      await _liveActivitiesPlugin.endActivity(_currentActivityId!);
    } catch (e) {
      if (kDebugMode) {
        print('[灵动岛] 结束活动失败: $e');
      }
    } finally {
      // 无论结束成功与否都重置 ID，避免异常后 _currentActivityId 残留导致后续上传无法再创建灵动岛
      _currentActivityId = null;
    }
  }

  /// 结束所有灵动岛活动（清理兜底）
  ///
  /// 用于冷启动清理孤儿活动、或回到前台时对账。
  /// 直接调用插件的 endAllActivities 结束系统中所有存活的活动。
  Future<void> endAllActivities() async {
    if (!_isSupported) return;
    try {
      await _liveActivitiesPlugin.endAllActivities();
    } catch (e) {
      if (kDebugMode) {
        print('[灵动岛] 清理所有活动失败: $e');
      }
    } finally {
      _currentActivityId = null;
    }
  }
}
