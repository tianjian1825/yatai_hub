import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode, listEquals;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/material_category.dart';
import '../models/hospital.dart';
import '../utils/grid_utils.dart';
import '../models/department.dart';
import '../models/visibility_option.dart';
import '../models/upload_file.dart';
import '../services/material_api.dart';
import '../services/upload_queue_manager.dart';
import '../services/event_bus_service.dart';
import '../services/route_settings_service.dart';
import '../services/department_service.dart';
import '../services/guest_mode_service.dart';
import '../services/user_service.dart';
import '../services/share_intent_service.dart';
import '../models/material_item.dart';
import 'upload_manager_page.dart';
import 'material_preview_page.dart';

/// 素材上传页面
class MaterialUploadPage extends StatefulWidget {
  final int? editId; // 编辑记录ID,如果为null则为新建模式

  const MaterialUploadPage({super.key, this.editId});

  @override
  State<MaterialUploadPage> createState() => MaterialUploadPageState();
}

class MaterialUploadPageState extends State<MaterialUploadPage> {
  /// 常驻上传 Tab（editId == null）的活实例，供 ShareIntentService 注入分享文件。
  /// 编辑模式（从我的作品进入）不注册，避免分享文件误入编辑页。
  static MaterialUploadPageState? activeInstance;
  // 素材归属标签
  final List<Map<String, String>> tagList = [
    {'id': '1', 'name': '韩国'},
    {'id': '11', 'name': '釜山'},
    {'id': '3', 'name': '医美'},
    {'id': '5', 'name': '日本'},
    {'id': '2', 'name': '口腔'},
    {'id': '6', 'name': '新加坡'},
    {'id': '4', 'name': '眼科'},
    {'id': '10', 'name': '泰国'},
    {'id': '9', 'name': '马来西亚'},
    {'id': '8', 'name': '印尼'},
  ];

  // 当前选中的归属类型
  String? currentType;

  // 素材分类相关
  MaterialCategory? selectedCategory;
  final List<MaterialCategory> categoryList =
      MaterialCategory.getAllCategories();

  // 内容描述
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();

  // 医院搜索相关
  final TextEditingController _hospitalController = TextEditingController();
  final FocusNode _hospitalFocusNode = FocusNode();
  Hospital? selectedHospital;
  List<Hospital> hospitalSearchResults = [];
  bool isSearchingHospital = false;
  bool showHospitalSearchResults = false;
  Timer? _searchDebounceTimer;

  /// 当前在途搜索请求的取消令牌，发起新搜索前取消上一个，避免并发与乱序返回
  CancelToken? _searchCancelToken;

  // 客户ID（有音频文件时显示，选填）
  final TextEditingController _clientIdController = TextEditingController();
  final FocusNode _clientIdFocusNode = FocusNode();

  // 可见范围相关
  int selectedVisibilityId = 1; // 默认全部可见
  final List<VisibilityOption> visibilityOptions = VisibilityOption.getAll();
  List<Department> departmentList = [];
  List<int> selectedDepartmentIds = [];
  bool isLoadingDepartments = false;

  // 上传线路选项
  String uploadRegion = 'overseas'; // domestic/overseas
  final List<Map<String, String>> uploadRegionList = [
    {'value': 'domestic', 'name': '国内', 'desc': '适合中国大陆地区使用'},
    {'value': 'overseas', 'name': '海外', 'desc': '适合海外地区使用'},
  ];

  bool showRegionPicker = false;

  // 提交状态
  bool isSubmitting = false;

  // 游客模式服务
  final GuestModeService _guestModeService = GuestModeService();
  bool _isGuestMode = false;

  // 兼职用户（roleid==275）：机构必填、可见范围强制全部且隐藏选择
  bool _isPartTime = false;

  // 文件处理状态（选择文件后添加到队列的过程）
  bool _isProcessingFiles = false;

  // 上传文件列表（用于显示，与任务ID关联）
  final Map<String, UploadFile> uploadFiles = {};

  // 任务ID列表（保持顺序）
  final List<String> taskIds = [];

  // 最大文件数量
  static const int maxFileCount = 30;

  // 上传队列管理器
  final UploadQueueManager _uploadQueueManager = UploadQueueManager();
  StreamSubscription<UploadTask>? _taskSubscription;
  StreamSubscription<Map<String, UploadTask>>? _queueSubscription;
  StreamSubscription<void>? _routeChangedSubscription;

  // 缓存保存防抖定时器
  Timer? _saveDebounceTimer;

  // EventBus 用于监听线路变更
  final EventBusService _eventBus = EventBusService();

  // 编辑模式下的原始数据（用于检测是否有修改）
  String? _originalContent;
  String? _originalType; // 素材归属
  int? _originalCategoryId;
  int? _originalHospitalId;
  String? _originalHospitalName;
  int _originalVisibilityId = 1;
  List<int> _originalDepartmentIds = [];
  final List<String> _originalFileUrls = []; // 使用URL作为文件标识

  @override
  void initState() {
    super.initState();

    // 配置 Android Photo Picker（适用于 Android 12 及以下版本）
    final ImagePickerPlatform imagePickerImplementation =
        ImagePickerPlatform.instance;
    if (imagePickerImplementation is ImagePickerAndroid) {
      imagePickerImplementation.useAndroidPhotoPicker = true;
    }

    _checkGuestMode();
    // 设置状态栏样式为深色图标（适配白色背景）
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 状态栏背景透明
        statusBarIconBrightness: Brightness.dark, // Android 深色图标
        statusBarBrightness: Brightness.light, // iOS 深色图标
      ),
    );

    // 如果是编辑模式,加载记录详情
    if (widget.editId != null) {
      _loadRecordDetail();
    }

    _subscribeToTaskUpdates(); // 订阅任务更新
    _subscribeToRouteChanged(); // 订阅线路变更事件

    // 注册为常驻上传 Tab 的活实例（编辑模式不注册，避免分享文件误入编辑页）
    if (widget.editId == null) {
      activeInstance = this;
    }

    // 异步初始化,避免竞态条件
    _asyncInitialize();
  }

  /// 异步初始化方法,确保缓存加载和任务恢复按顺序执行,避免竞态条件
  Future<void> _asyncInitialize() async {
    try {
      // 编辑模式下不加载缓存，因为会从服务器获取文件
      if (widget.editId == null) {
        // 1. 先加载缓存数据(uploadFiles)
        await _loadCachedData();
      }

      if (!mounted) return;

      // 2. NAS 模式不需要预加载 OSS 配置

      // 3. 最后初始化上传管理器(恢复任务)
      // 编辑模式下从我的作品进入时不恢复任务
      if (widget.editId == null) {
        // 此时 uploadFiles 已经从缓存恢复,可以正确判断是否存在
        await _initializeUploadManager();
      }
    } catch (e) {
      if (kDebugMode) print('[素材上传] 异步初始化失败: $e');
    }

    // 缓存/任务恢复完成后，消费冷启动期间到达的系统分享，避免与缓存加载竞态
    if (widget.editId == null && mounted) {
      ShareIntentService().consumePending();
    }
  }

  /// 接收系统分享进来的文件并加入上传队列。
  /// 由 [ShareIntentService] 调用（已确保登录态、非游客）。
  /// 复用与 [_pickFiles] 一致的入队逻辑（NAS 上传 + maxFileCount 上限）。
  Future<void> ingestSharedFiles(List<String> paths) async {
    if (paths.isEmpty) return;

    final remainingSlots = maxFileCount - uploadFiles.length;
    if (remainingSlots <= 0) {
      if (mounted) _showSnackBar('最多只能上传 $maxFileCount 个文件');
      return;
    }

    final pathsToAdd = paths.take(remainingSlots).toList();
    final limited = pathsToAdd.length < paths.length;

    var added = 0;
    for (final rawPath in pathsToAdd) {
      // 兜底：分享进来的路径可能带 file:// 前缀或百分号编码（如中文/空格文件名），
      // 原始路径找不到时尝试解码后再试，避免误报「无法读取」。
      final filePath = _resolveSharedPath(rawPath);
      final file = File(filePath);
      if (!file.existsSync()) continue;

      final fileName = filePath.split(Platform.pathSeparator).last;
      final fileSize = file.lengthSync();
      final uploadFile = UploadFile.fromPath(
        filePath,
        customFileName: fileName,
        fileSize: fileSize,
      );

      final taskId = _uploadQueueManager.addNasTask(
        uploadFile,
        hospitalName: selectedHospital?.name,
      );

      if (mounted) {
        setState(() {
          taskIds.add(taskId);
          uploadFiles[taskId] = uploadFile;
        });
      } else {
        taskIds.add(taskId);
        uploadFiles[taskId] = uploadFile;
      }
      added++;
    }

    _saveCachedData();

    if (!mounted) return;
    if (added == 0) {
      _showSnackBar('分享的文件无法读取');
    } else if (limited) {
      _showSnackBar('已添加 $added 个文件，超出 $maxFileCount 上限部分已忽略');
    } else {
      _showSnackBar('已从分享添加 $added 个文件到上传队列');
    }
  }

  /// 规整分享进来的文件路径：去掉 file:// 前缀并按需百分号解码。
  /// 优先返回真实存在的形态；都不存在时返回去前缀后的解码值，交由调用方判断。
  String _resolveSharedPath(String raw) {
    final candidates = <String>[];
    void add(String p) {
      if (p.isNotEmpty && !candidates.contains(p)) candidates.add(p);
    }

    add(raw);
    final noScheme =
        raw.startsWith('file://') ? raw.replaceFirst('file://', '') : raw;
    add(noScheme);
    String decoded = noScheme;
    try {
      decoded = Uri.decodeComponent(noScheme);
    } catch (_) {
      // 非法百分号序列，保持原值
    }
    add(decoded);

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return decoded;
  }

  /// 检查游客模式
  Future<void> _checkGuestMode() async {
    final isGuest = await _guestModeService.isGuestMode();
    final isPartTime = !isGuest && await UserService().isPartTimeUser();
    if (mounted) {
      setState(() {
        _isGuestMode = isGuest;
        _isPartTime = isPartTime;
        // 兼职用户强制可见范围为「全部可见」
        if (_isPartTime) selectedVisibilityId = 1;
      });
    }
  }

  /// 订阅线路变更事件
  void _subscribeToRouteChanged() {
    _routeChangedSubscription = _eventBus.onRouteChanged.listen((_) {
      if (mounted) {
        // 线路变更时重新加载上传线路
        _reloadUploadRoute();
      }
    });
  }

  /// 重新加载上传线路
  Future<void> _reloadUploadRoute() async {
    try {
      final routeSettings = RouteSettingsService();
      final uploadRoute = await routeSettings.getUploadRoute();

      // 将整数格式转换为字符串格式
      final routeString = uploadRoute == RouteSettingsService.routeDomestic
          ? 'domestic'
          : 'overseas';

      // 只有当线路发生变化时才更新状态
      if (uploadRegion != routeString) {
        if (mounted) {
          setState(() {
            uploadRegion = routeString;
          });
        }
        // NAS 模式不需要重新加载配置
      }
    } catch (e) {
      if (kDebugMode) print('[素材上传] 重新加载上传线路失败: $e');
    }
  }

  @override
  void dispose() {
    if (identical(activeInstance, this)) {
      activeInstance = null;
    }
    _contentController.dispose();
    _contentFocusNode.dispose();
    _hospitalController.dispose();
    _hospitalFocusNode.dispose();
    _clientIdController.dispose();
    _clientIdFocusNode.dispose();
    _searchDebounceTimer?.cancel();
    _searchCancelToken?.cancel(); // 取消在途的医院搜索请求
    _saveDebounceTimer?.cancel(); // 取消缓存保存防抖定时器
    _taskSubscription?.cancel();
    _queueSubscription?.cancel();
    _routeChangedSubscription?.cancel(); // 取消线路变更事件订阅

    // 清理图片缓存，降低内存占用
    _clearImageCache();

    super.dispose();
  }

  /// 显示 SnackBar（自动替换旧通知，避免排队）
  void _showSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars(); // 清除旧通知
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 1),
      ),
    );
  }

  /// 检测已上传文件中是否有音频文件
  bool _hasAudioFile() {
    return uploadFiles.values.any(
      (file) => file.fileType == UploadFileType.audio,
    );
  }

  /// 检测编辑模式下内容是否有修改
  bool _hasContentChanged() {
    if (widget.editId == null) return false;

    // 检测内容描述
    final currentContent = _contentController.text;
    if (currentContent != (_originalContent ?? '')) {
      return true;
    }

    // 检测素材归属
    if (currentType != _originalType) {
      return true;
    }

    // 检测素材分类
    final currentCategoryId = selectedCategory?.id;
    if (currentCategoryId != _originalCategoryId) {
      return true;
    }

    // 检测医院信息
    final currentHospitalId = selectedHospital?.hospitalId;
    final currentHospitalName = selectedHospital?.name;
    if (currentHospitalId != _originalHospitalId ||
        currentHospitalName != _originalHospitalName) {
      return true;
    }

    // 检测可见范围
    if (selectedVisibilityId != _originalVisibilityId) {
      return true;
    }

    // 检测部门选择
    if (selectedVisibilityId == 2) {
      final sortedCurrent = List.from(selectedDepartmentIds)..sort();
      final sortedOriginal = List.from(_originalDepartmentIds)..sort();
      if (!listEquals(sortedCurrent, sortedOriginal)) {
        return true;
      }
    }

    // 检测文件列表
    final currentFileUrls =
        uploadFiles.values
            .where(
              (file) => file.remoteUrl != null && file.remoteUrl!.isNotEmpty,
            )
            .map((file) => file.remoteUrl!)
            .toList()
          ..sort();
    final originalFileUrls = List.from(_originalFileUrls)..sort();
    if (currentFileUrls.length != originalFileUrls.length) {
      return true;
    }
    for (int i = 0; i < currentFileUrls.length; i++) {
      if (currentFileUrls[i] != originalFileUrls[i]) {
        return true;
      }
    }

    return false;
  }

  /// 显示退出确认对话框
  /// 返回 true 表示用户确认退出，false 表示取消
  Future<bool> _showExitConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('退出将不会保存所作更改'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定退出'),
          ),
        ],
      ),
    );

    return result == true;
  }

  /// 加载记录详情(编辑模式)
  Future<void> _loadRecordDetail() async {
    if (widget.editId == null) return;

    try {
      // 调用API获取编辑详情
      final result = await MaterialApi.getEditMaterialDetail(widget.editId!);

      if (result == null) {
        if (mounted) {
          _showSnackBar('加载素材详情失败');
        }
        return;
      }

      final casually = result['casually'] as Map<String, dynamic>?;
      final casuallyList = result['casually_list'] as List<dynamic>?;

      if (casually == null) {
        debugPrint('casually为null，无法继续加载');
        return;
      }

      if (mounted) {
        setState(() {
          // 回显内容描述
          if (casually['text'] != null) {
            _contentController.text = casually['text'].toString();
            _originalContent = casually['text'].toString();
          } else {
            _originalContent = '';
          }

          // 回显素材归属
          if (casually['country_type'] != null) {
            final countryType = casually['country_type'].toString();
            currentType = countryType;
            _originalType = countryType;
          } else {
            // 如果没有 country_type，使用默认值（韩国，id为'1'）
            currentType = '1';
            _originalType = '1';
          }

          // 回显素材分类
          if (casually['material_category'] != null) {
            final categoryId = int.tryParse(
              casually['material_category'].toString(),
            );
            if (categoryId != null) {
              final category = categoryList.firstWhere(
                (c) => c.id == categoryId,
                orElse: () => categoryList.first,
              );
              selectedCategory = category;
              _originalCategoryId = categoryId;
            } else {
              _originalCategoryId = null;
            }
          } else {
            _originalCategoryId = null;
          }

          // 回显医院信息
          if (casually['hospital_name'] != null &&
              casually['hospital_name'].toString().isNotEmpty) {
            _hospitalController.text = casually['hospital_name'].toString();
            final hospitalId = int.tryParse(
              casually['hospital_id']?.toString() ?? '',
            );
            selectedHospital = Hospital(
              hospitalId: hospitalId,
              kfHospitalId: int.tryParse(
                casually['kf_hospital_id']?.toString() ?? '',
              ),
              name: casually['hospital_name'].toString(),
              areaType: casually['area_type']?.toString() ?? '',
            );
            _originalHospitalId = hospitalId;
            _originalHospitalName = casually['hospital_name'].toString();
          } else {
            _originalHospitalId = null;
            _originalHospitalName = null;
          }

          // 回显可见范围
          if (casually['visable_department'] != null) {
            final visableDept = casually['visable_department']
                .toString()
                .trim();
            if (visableDept.isNotEmpty) {
              selectedVisibilityId = 2; // 部分可见
              // 解析部门ID列表
              selectedDepartmentIds = visableDept
                  .split(',')
                  .map((id) => int.tryParse(id.trim()))
                  .where((id) => id != null)
                  .cast<int>()
                  .toList();
              _originalVisibilityId = 2;
              _originalDepartmentIds = List.from(selectedDepartmentIds);
            } else {
              selectedVisibilityId = 1; // 全部可见
              selectedDepartmentIds = [];
              _originalVisibilityId = 1;
              _originalDepartmentIds = [];
            }
          } else {
            // visable_department 为空时默认全部可见
            selectedVisibilityId = 1;
            selectedDepartmentIds = [];
            _originalVisibilityId = 1;
            _originalDepartmentIds = [];
          }
        });

        // 回显文件列表
        _originalFileUrls.clear();
        if (casuallyList != null && casuallyList.isNotEmpty) {
          // 清空当前文件列表
          uploadFiles.clear();
          taskIds.clear();

          for (var file in casuallyList) {
            final fileMap = file as Map<String, dynamic>;
            final fileUrl = fileMap['url']?.toString() ?? '';

            // 保存原始文件URL
            if (fileUrl.isNotEmpty) {
              _originalFileUrls.add(fileUrl);
            }

            // 根据file_classification判断文件类型
            String fileType = 'file';
            final classification =
                fileMap['file_classification']?.toString() ?? '';
            final suffix =
                fileMap['file_suffix']?.toString().toLowerCase() ?? '';

            if (classification == 'image') {
              if (['jpg', 'jpeg'].contains(suffix)) {
                fileType = 'image/jpeg';
              } else if (suffix == 'png') {
                fileType = 'image/png';
              } else if (suffix == 'gif') {
                fileType = 'image/gif';
              } else if (suffix == 'webp') {
                fileType = 'image/webp';
              } else if (suffix == 'heic') {
                fileType = 'image/heic';
              } else if (suffix == 'heif') {
                fileType = 'image/heif';
              } else if (suffix == 'dng') {
                fileType = 'image/x-adobe-dng';
              } else {
                fileType = 'image/jpeg';
              }
            } else if (classification == 'video') {
              if (['mov', 'quicktime'].contains(suffix)) {
                fileType = 'video/quicktime';
              } else {
                fileType = 'video/mp4';
              }
            } else if (classification == 'audio') {
              if (suffix == 'mp3') {
                fileType = 'audio/mpeg';
              } else if (suffix == 'wav') {
                fileType = 'audio/wav';
              } else if (suffix == 'flac') {
                fileType = 'audio/flac';
              } else if (suffix == 'aac') {
                fileType = 'audio/aac';
              } else if (suffix == 'm4a') {
                fileType = 'audio/m4a';
              } else if (suffix == 'ogg') {
                fileType = 'audio/ogg';
              } else {
                fileType = 'audio/mpeg';
              }
            } else {
              // 如果后端没有正确标记classification，根据文件后缀再判断一次
              final detectedType = UploadFile.getFileType(
                fileMap['file_name']?.toString() ?? suffix,
              );
              if (detectedType == UploadFileType.audio) {
                fileType = 'audio/mpeg';
              }
            }

            // 获取缩略图 URL（NAS 模式下后端会返回 thumbnail 字段，可能是对象或字符串）
            // 对于视频，可能返回 video_frame 字段
            String? thumbnailUrl;
            String? thumbnailPath;
            final thumbnailData = fileMap['thumbnail'];
            if (thumbnailData is Map) {
              thumbnailUrl = thumbnailData['file_url']?.toString();
              thumbnailPath = thumbnailData['file_path']?.toString();
            } else if (thumbnailData is String && thumbnailData.isNotEmpty) {
              thumbnailUrl = thumbnailData;
            }

            final videoFrameData = fileMap['video_frame'];
            if ((thumbnailUrl == null || thumbnailUrl.isEmpty) &&
                videoFrameData != null) {
              if (videoFrameData is Map) {
                thumbnailUrl = videoFrameData['file_url']?.toString();
                if (thumbnailPath == null || thumbnailPath.isEmpty) {
                  thumbnailPath = videoFrameData['file_path']?.toString();
                }
              } else if (videoFrameData is String &&
                  videoFrameData.isNotEmpty) {
                thumbnailUrl = videoFrameData.toString();
              }
            }

            // 如果对象格式没有提供 path，尝试读取独立的 thumbnail_path 字段（向后兼容）
            if (thumbnailPath == null || thumbnailPath.isEmpty) {
              thumbnailPath = fileMap['thumbnail_path']?.toString();
            }

            // 创建文件对象（编辑模式下文件已经上传，使用URL作为标识）
            final uploadFile = UploadFile(
              id: 'edit_$fileUrl',
              localPath: '', // 编辑模式下不需要本地路径
              fileName: fileMap['file_name']?.toString() ?? '',
              originalName:
                  fileMap['original_name']?.toString() ??
                  fileMap['file_name']?.toString(), // 设置原始文件名
              fileSize: int.tryParse(fileMap['size']?.toString() ?? '0') ?? 0,
              fileType: _getFileTypeFromString(fileType),
              status: UploadFileStatus.success,
              remoteUrl: fileUrl,
              ossFilePath: fileMap['file_path']?.toString() ?? '', // 添加OSS文件路径
              thumbnailUrl: (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  ? thumbnailUrl
                  : null,
              thumbnailPath: (thumbnailPath != null && thumbnailPath.isNotEmpty)
                  ? thumbnailPath
                  : null,
              serverFileId: fileMap['id']?.toString(), // 保存后端文件记录ID，提交时需要回传
            );

            // 使用URL作为唯一标识
            final taskId = 'edit_$fileUrl';
            setState(() {
              uploadFiles[taskId] = uploadFile;
              taskIds.add(taskId);
            });
          }
        }

        // 如果选择了部分可见且有部门ID，加载部门列表
        if (selectedVisibilityId == 2 && selectedDepartmentIds.isNotEmpty) {
          _loadDepartments();
        }
      }
    } catch (e) {
      debugPrint('加载编辑详情失败: $e');
      if (mounted) {
        _showSnackBar('加载素材详情失败');
      }
    }
  }

  /// 将字符串文件类型转换为 UploadFileType 枚举
  UploadFileType _getFileTypeFromString(String typeString) {
    if (typeString.startsWith('image/')) {
      return UploadFileType.image;
    } else if (typeString.startsWith('video/')) {
      return UploadFileType.video;
    } else if (typeString.startsWith('audio/')) {
      return UploadFileType.audio;
    } else {
      return UploadFileType.document;
    }
  }

  /// 加载缓存数据
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载素材归属
    final cachedType = prefs.getString('cached_current_type');
    if (cachedType != null && mounted) {
      setState(() {
        currentType = cachedType;
      });
    }

    // 加载素材分类
    final cachedCategoryId = prefs.getInt('cached_category_id');
    if (cachedCategoryId != null && mounted) {
      final category = categoryList.firstWhere(
        (c) => c.id == cachedCategoryId,
        orElse: () => categoryList.first,
      );
      setState(() {
        selectedCategory = category;
      });
    }

    // 加载可见范围
    final cachedVisibility = prefs.getInt('cached_visibility_id') ?? 1;
    if (mounted) {
      setState(() {
        selectedVisibilityId = cachedVisibility;
      });
    }

    // 加载上传线路（从 RouteSettingsService 读取）
    try {
      final routeSettings = RouteSettingsService();
      final uploadRoute = await routeSettings.getUploadRoute();

      // 将整数格式转换为字符串格式（保持兼容性）
      final routeString = uploadRoute == RouteSettingsService.routeDomestic
          ? 'domestic'
          : 'overseas';

      if (mounted) {
        setState(() {
          uploadRegion = routeString;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[素材上传] 加载上传线路失败: $e');
      // 失败时使用默认值
      if (mounted) {
        setState(() {
          uploadRegion = 'overseas';
        });
      }
    }

    // 加载内容描述
    final cachedContent = prefs.getString('cached_content_description');
    if (cachedContent != null) {
      _contentController.text = cachedContent;
    }

    // 加载机构名称
    final cachedHospitalJson = prefs.getString('cached_hospital');
    if (cachedHospitalJson != null) {
      try {
        final hospitalMap =
            jsonDecode(cachedHospitalJson) as Map<String, dynamic>;
        final hospital = Hospital.fromJson(hospitalMap);
        if (mounted) {
          setState(() {
            selectedHospital = hospital;
            _hospitalController.text = hospital.name;
          });
        }
      } catch (e) {
        // 解析失败，忽略
        debugPrint('加载缓存的医院信息失败: $e');
      }
    }

    // 加载部门列表
    final cachedDepartmentsJson = prefs.getString('cached_departments');
    if (cachedDepartmentsJson != null) {
      try {
        final departmentsList =
            jsonDecode(cachedDepartmentsJson) as List<dynamic>;
        final departments = departmentsList
            .map((json) => Department.fromJson(json as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            departmentList = departments;
          });
        }
      } catch (e) {
        // 解析失败，忽略
        debugPrint('加载缓存的部门列表失败: $e');
      }
    }

    // 加载选择的部门 IDs
    final cachedDepartmentIds = prefs.getString('cached_department_ids');
    if (cachedDepartmentIds != null) {
      try {
        final idsList = jsonDecode(cachedDepartmentIds) as List<dynamic>;
        if (mounted) {
          setState(() {
            selectedDepartmentIds = idsList.map((id) => id as int).toList();
          });
        }
      } catch (e) {
        // 解析失败，忽略
        debugPrint('加载缓存的部门ID列表失败: $e');
      }
    }

    // 加载已上传的文件列表
    final cachedFilesJson = prefs.getString('cached_upload_files');
    if (cachedFilesJson != null) {
      try {
        final filesMap = jsonDecode(cachedFilesJson) as Map<String, dynamic>;
        final Map<String, UploadFile> cachedFiles = {};
        final List<String> cachedTaskIds = [];

        filesMap.forEach((taskId, fileJson) {
          try {
            var file = UploadFile.fromJson(fileJson as Map<String, dynamic>);

            // 如果文件状态是"上传中"，重置为"暂停"
            // 保留原有的进度和已完成的分片信息，以支持断点续传
            if (file.status == UploadFileStatus.uploading) {
              file = file.copyWith(
                status: UploadFileStatus.paused,
                // 保留进度，不重置为0，以便用户看到之前的上传进度
              );
            }

            cachedFiles[taskId] = file;
            cachedTaskIds.add(taskId);
          } catch (e) {
            // 解析单个文件失败，跳过
            debugPrint('加载缓存文件失败 ($taskId): $e');
          }
        });

        if (cachedFiles.isNotEmpty && mounted) {
          setState(() {
            uploadFiles.addAll(cachedFiles);
            taskIds.addAll(cachedTaskIds);
          });
        }
      } catch (e) {
        // 解析失败，忽略
        debugPrint('加载缓存的文件列表失败: $e');
      }
    }
  }

  /// 保存缓存数据
  Future<void> _saveCachedData() async {
    // 编辑模式下不保存缓存
    if (widget.editId != null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 保存素材归属
    if (currentType != null) {
      await prefs.setString('cached_current_type', currentType!);
    }

    // 保存素材分类
    if (selectedCategory != null) {
      await prefs.setInt('cached_category_id', selectedCategory!.id);
    }

    // 保存可见范围
    await prefs.setInt('cached_visibility_id', selectedVisibilityId);

    // 保存上传线路（统一使用整数格式，避免类型冲突）
    final routeValue = uploadRegion == 'domestic'
        ? RouteSettingsService.routeDomestic
        : RouteSettingsService.routeOverseas;
    await prefs.setInt('cached_upload_region', routeValue);

    // 同步到 RouteSettingsService（仅在线路变化时）
    try {
      final routeSettings = RouteSettingsService();

      // 先读取当前值，避免频繁同步
      final currentRoute = await routeSettings.getUploadRoute();

      // 只有当线路发生变化时才同步
      if (currentRoute != routeValue) {
        await routeSettings.setUploadRoute(routeValue);
      }
    } catch (e) {
      if (kDebugMode) print('[素材上传] 同步上传线路失败: $e');
    }

    // 保存内容描述
    await prefs.setString(
      'cached_content_description',
      _contentController.text,
    );

    // 保存机构名称
    if (selectedHospital != null) {
      final hospitalJson = jsonEncode(selectedHospital!.toJson());
      await prefs.setString('cached_hospital', hospitalJson);
    } else {
      await prefs.remove('cached_hospital');
    }

    // 保存部门列表
    if (departmentList.isNotEmpty) {
      final departmentsJson = jsonEncode(
        departmentList.map((dept) => dept.toJson()).toList(),
      );
      await prefs.setString('cached_departments', departmentsJson);
    }

    // 保存选择的部门 IDs
    if (selectedDepartmentIds.isNotEmpty) {
      final departmentIdsJson = jsonEncode(selectedDepartmentIds);
      await prefs.setString('cached_department_ids', departmentIdsJson);
    } else {
      await prefs.remove('cached_department_ids');
    }

    // 保存已上传的文件列表
    if (uploadFiles.isNotEmpty) {
      final filesMap = <String, dynamic>{};
      uploadFiles.forEach((taskId, file) {
        filesMap[taskId] = file.toJson();
      });
      final filesJson = jsonEncode(filesMap);
      await prefs.setString('cached_upload_files', filesJson);
    } else {
      await prefs.remove('cached_upload_files');
    }
  }

  /// 订阅任务更新
  void _subscribeToTaskUpdates() {
    _taskSubscription = _uploadQueueManager.taskStream.listen((task) {
      if (mounted && uploadFiles.containsKey(task.id)) {
        setState(() {
          // 根据任务状态更新文件状态
          uploadFiles[task.id] = task.file.copyWith(
            status: _mapTaskStatusToFileStatus(task.status),
            progress: task.progress,
            errorMessage: task.errorMessage,
            // 使用兼容 OSS 和 NAS 的 getter
            remoteUrl: task.fileUrl,
            ossFilePath: task.filePath,
            // 缩略图信息（NAS 模式）
            thumbnailUrl: task.thumbnailUrl,
            thumbnailPath: task.thumbnailPath,
          );
        });

        // 防抖保存：1秒内只保存一次，降低I/O频率
        _saveDebounceTimer?.cancel();
        _saveDebounceTimer = Timer(const Duration(seconds: 1), () {
          _saveCachedData();
        });
      }
    });

    // 同时订阅队列更新，以便在任务被删除时同步更新
    // 注意：stream 事件中的 allTasks 是快照，可能是旧数据，
    // 必须直接查询队列管理器的当前状态，避免因旧快照误删刚添加的任务
    _queueSubscription = _uploadQueueManager.queueStream.listen((_) {
      if (mounted) {
        // 直接查询队列管理器的当前状态，而非使用 stream 传递的旧快照
        final taskIdsToRemove = <String>[];
        for (final taskId in uploadFiles.keys) {
          final file = uploadFiles[taskId];
          if (file == null) continue;
          // 只删除未完成且不在队列中的文件
          // 成功上传的文件应该保留，即使不在队列管理器中
          if (file.status != UploadFileStatus.success &&
              _uploadQueueManager.getTask(taskId) == null) {
            taskIdsToRemove.add(taskId);
          }
        }

        if (taskIdsToRemove.isNotEmpty) {
          setState(() {
            for (final taskId in taskIdsToRemove) {
              uploadFiles.remove(taskId);
              taskIds.remove(taskId);
            }
          });
          _saveCachedData();
        }
      }
    });
  }

  /// 将任务状态映射到文件状态
  UploadFileStatus _mapTaskStatusToFileStatus(UploadTaskStatus taskStatus) {
    switch (taskStatus) {
      case UploadTaskStatus.queued:
        return UploadFileStatus.pending;
      case UploadTaskStatus.paused:
        return UploadFileStatus.paused;
      case UploadTaskStatus.uploading:
        return UploadFileStatus.uploading;
      case UploadTaskStatus.completed:
        return UploadFileStatus.success;
      case UploadTaskStatus.failed:
        return UploadFileStatus.failed;
      case UploadTaskStatus.canceled:
        return UploadFileStatus.canceled;
    }
  }

  /// 初始化上传管理器（恢复之前的上传任务）
  Future<void> _initializeUploadManager() async {
    await _uploadQueueManager.initialize();

    if (!mounted) return;

    // 获取恢复的任务
    final restoredTasks = _uploadQueueManager.getAllTasks();

    if (restoredTasks.isEmpty && uploadFiles.isEmpty) {
      // 如果没有需要恢复的任务，且 uploadFiles 也为空，直接返回
      return;
    }

    // 构建恢复任务的 taskId 集合
    final restoredTaskIds = restoredTasks.map((task) => task.id).toSet();

    // 清理 uploadFiles 中存在但 UploadQueueManager 中不存在的任务（避免重复）
    final taskIdsToRemove = <String>[];
    for (final taskId in uploadFiles.keys) {
      final file = uploadFiles[taskId];
      if (file == null) continue;
      // 只清理未完成的任务（成功上传的文件应该保留）
      if (file.status != UploadFileStatus.success &&
          !restoredTaskIds.contains(taskId)) {
        taskIdsToRemove.add(taskId);
      }
    }

    if (taskIdsToRemove.isNotEmpty && mounted) {
      setState(() {
        for (final taskId in taskIdsToRemove) {
          uploadFiles.remove(taskId);
          taskIds.remove(taskId);
        }
      });
    }

    if (restoredTasks.isNotEmpty && mounted) {
      int recoveredCount = 0; // 真正恢复的任务数量
      int completedCount = 0; // 已完成任务数量
      setState(() {
        // 同步恢复的任务到 UI
        for (final task in restoredTasks) {
          // 如果UI中已经有这个任务，更新其状态
          if (uploadFiles.containsKey(task.id)) {
            uploadFiles[task.id] = task.file.copyWith(
              status: _mapTaskStatusToFileStatus(task.status),
              progress: task.progress,
              errorMessage: task.errorMessage,
              // 使用兼容 OSS 和 NAS 的 getter
              remoteUrl: task.fileUrl,
              ossFilePath: task.filePath,
              // 缩略图信息（NAS 模式）
              thumbnailUrl: task.thumbnailUrl,
              thumbnailPath: task.thumbnailPath,
            );
          } else {
            // 如果UI中没有这个任务，需要恢复到UI
            // ⚠️ 重要：已完成的任务也需要恢复，因为用户可能还没提交表单
            uploadFiles[task.id] = task.file.copyWith(
              status: _mapTaskStatusToFileStatus(task.status),
              progress: task.progress,
              errorMessage: task.errorMessage,
              // 使用兼容 OSS 和 NAS 的 getter
              remoteUrl: task.fileUrl,
              ossFilePath: task.filePath,
              // 缩略图信息（NAS 模式）
              thumbnailUrl: task.thumbnailUrl,
              thumbnailPath: task.thumbnailPath,
            );
            taskIds.add(task.id);

            // 统计恢复的任务类型
            if (task.status == UploadTaskStatus.completed) {
              completedCount++;
            } else if (task.status != UploadTaskStatus.canceled) {
              recoveredCount++; // 未完成且未取消的任务
            }
          }
        }
      });

      // 显示恢复提示
      if (mounted) {
        if (recoveredCount > 0 && completedCount > 0) {
          _showSnackBar(
            '恢复了 $recoveredCount 个上传任务和 $completedCount 个已完成文件',
            duration: const Duration(seconds: 2),
          );
        } else if (recoveredCount > 0) {
          _showSnackBar(
            '恢复了 $recoveredCount 个上传任务',
            duration: const Duration(seconds: 2),
          );
        } else if (completedCount > 0) {
          _showSnackBar(
            '恢复了 $completedCount 个已完成文件',
            duration: const Duration(seconds: 2),
          );
        }
      }

      // 保存同步后的状态
      _saveCachedData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 只在编辑模式下才拦截返回
    final isEditMode = widget.editId != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 状态栏背景透明
        statusBarIconBrightness: Brightness.dark, // Android 深色图标
        statusBarBrightness: Brightness.light, // iOS 深色图标
      ),
      child: isEditMode
          ? PopScope(
              // 如果没有修改，允许直接返回（包括侧滑返回）
              // 如果有修改，拦截返回并显示确认对话框
              canPop: !_hasContentChanged(),
              onPopInvokedWithResult: (didPop, result) async {
                // 如果已经返回了（没有修改的情况），不再处理
                if (didPop) return;
                // 如果有修改，显示确认对话框
                if (_hasContentChanged()) {
                  // 在异步操作前获取 context 引用
                  if (!mounted) return;
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  final shouldPop = await _showExitConfirmDialog();
                  if (shouldPop) {
                    // 确保在 mounted 状态下使用
                    if (!mounted) return;
                    messenger.clearSnackBars();
                    // 使用 SchedulerBinding 确保在下一帧执行，避免导航冲突
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && navigator.canPop()) {
                        navigator.pop();
                      }
                    });
                  }
                }
              },
              child: _buildScaffold(),
            )
          : _buildScaffold(),
    );
  }

  /// 构建 Scaffold 内容
  Widget _buildScaffold() {
    return GestureDetector(
      onTap: () {
        // 点击空白区域时，取消所有输入框的焦点
        FocusScope.of(context).unfocus();
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // 自定义导航栏
            _buildCustomNavbar(),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    _buildBelongSection(),
                    _buildDivider(),
                    _buildCategorySection(),
                    _buildDivider(),
                    _buildContentSection(),
                    _buildDivider(),
                    _buildUploadSection(),
                    _buildDivider(),
                    _buildHospitalSearchSection(),
                    if (!_isPartTime) ...[
                      _buildDivider(),
                      _buildVisibilitySection(),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // 提交按钮
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  /// 构建分隔线
  Widget _buildDivider() {
    return Container(height: 8, color: const Color(0xFFF5F5F5));
  }

  /// 构建自定义导航栏
  Widget _buildCustomNavbar() {
    // 获取标题 - 顶部始终显示"素材上传"或"编辑素材"
    String title = '素材上传';
    if (widget.editId != null) {
      title = '编辑素材';
    }

    // 是否显示返回按钮
    final showBackButton = widget.editId != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  // 编辑模式或任务模式显示返回按钮
                  if (showBackButton)
                    GestureDetector(
                      onTap: () {
                        // 编辑模式下检查是否有修改
                        if (widget.editId != null && _hasContentChanged()) {
                          _showExitConfirmDialog();
                        } else {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.arrow_back,
                          color: Color(0xFF333333),
                          size: 24,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                // _buildNavbarAction(
                //   icon: Icons.map_outlined,
                //   text: '线路: ${_getUploadRegionText()}',
                //   onTap: () {
                //     setState(() {
                //       showRegionPicker = true;
                //     });
                //     _showRegionPickerDialog();
                //   },
                // ),
                const SizedBox(width: 16),
                _buildNavbarAction(
                  icon: Icons.grid_view_outlined,
                  text: '上传管理',
                  onTap: () {
                    // 清除当前页面的 SnackBar，避免跨页面流转
                    ScaffoldMessenger.of(context).clearSnackBars();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UploadManagerPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建导航栏操作按钮
  Widget _buildNavbarAction({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // 确保整个区域可点击
      onTap: () {
        // 先取消任何输入框的焦点，避免第一次点击被用于关闭键盘
        FocusScope.of(context).unfocus();
        onTap();
      },
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF366CDF), size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 14, color: Color(0xFF366CDF)),
          ),
        ],
      ),
    );
  }

  /// 构建素材归属选择区域
  Widget _buildBelongSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/material-icon.png',
                width: 20,
                height: 20,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.category,
                    size: 20,
                    color: Color(0xFF709BF7),
                  );
                },
              ),
              const SizedBox(width: 10),
              const Text(
                '素材归属',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
              const Text(
                '*',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tagList.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final tag = tagList[index];
                final isActive = currentType == tag['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      currentType = tag['id'];
                    });
                    _saveCachedData();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF709BF7)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        tag['name']!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF3D3D3D),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建素材分类选择区域
  Widget _buildCategorySection() {
    // 分两行展示：第一行放前 6 个常规分类，第二行以「话术」领头（其余依次排在后面）。
    // 每行内部横向滚动，保证「话术」恒为第二行第一个。
    final ordered = List<MaterialCategory>.from(categoryList);
    final scriptIndex = ordered.indexWhere((c) => c.key == 'script');
    final MaterialCategory? script = scriptIndex >= 0
        ? ordered.removeAt(scriptIndex)
        : null;
    final firstRow = ordered.take(6).toList();
    final secondRow = <MaterialCategory>[
      ?script,
      ...ordered.skip(6),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.category, size: 20, color: Color(0xFF709BF7)),
              const SizedBox(width: 10),
              const Text(
                '素材分类',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
              const Text(
                '*',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 两行整体横向滑动：外层统一滚动，内部两行同步平移
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoryRow(firstRow),
                const SizedBox(height: 12),
                _buildCategoryRow(secondRow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 单行素材分类（不单独滚动，随外层整体横向滑动）
  Widget _buildCategoryRow(List<MaterialCategory> items) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _buildCategoryChip(items[i]),
          ],
        ],
      ),
    );
  }

  /// 单个素材分类 chip
  Widget _buildCategoryChip(MaterialCategory category) {
    final isActive = selectedCategory?.id == category.id;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCategory = category;
        });
        _saveCachedData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF709BF7) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            category.name,
            style: TextStyle(
              fontSize: 13,
              color: isActive ? Colors.white : const Color(0xFF3D3D3D),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建内容描述输入区域
  Widget _buildContentSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 20, color: Color(0xFF709BF7)),
              const SizedBox(width: 10),
              const Text(
                '内容描述',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: TextField(
              controller: _contentController,
              focusNode: _contentFocusNode,
              maxLines: 6,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText:
                    '请输入素材描述内容...\n\n推荐格式：\n1. 素材主题\n2. 拍摄地点/项目名称\n3. 其他说明',
                hintStyle: TextStyle(color: Color(0xFF999999), fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (value) {
                // 保存缓存（异步，不阻塞 UI）
                _saveCachedData();
              },
              onEditingComplete: () {
                // 点击键盘上的"完成"按钮时，取消焦点
                _contentFocusNode.unfocus();
              },
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              _showExampleDialog();
            },
            child: Row(
              children: [
                const Icon(
                  Icons.visibility,
                  size: 18,
                  color: Color(0xFF5681DC),
                ),
                const SizedBox(width: 6),
                const Text(
                  '查看示例',
                  style: TextStyle(fontSize: 14, color: Color(0xFF5681DC)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建上传区域
  Widget _buildUploadSection() {
    final fileCount = uploadFiles.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload,
                size: 20,
                color: Color(0xFF709BF7),
              ),
              const SizedBox(width: 10),
              const Text(
                '上传素材',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
              const Text(
                '*',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
              const Spacer(),
              Text(
                '$fileCount/$maxFileCount',
                style: TextStyle(
                  fontSize: 14,
                  color: fileCount >= maxFileCount
                      ? Colors.red
                      : const Color(0xFF666666),
                  fontWeight: fileCount >= maxFileCount
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 文件选择按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (fileCount >= maxFileCount || _isProcessingFiles)
                      ? null
                      : _showMediaPickerOptions,
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('选择图片/视频', style: TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF709BF7),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (fileCount >= maxFileCount || _isProcessingFiles)
                      ? null
                      : _pickFiles,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择文件', style: TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF709BF7),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ),
          // 文件列表
          if (uploadFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildFileList(),
          ],
        ],
      ),
    );
  }

  /// 构建医院搜索区域
  Widget _buildHospitalSearchSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_hospital,
                size: 20,
                color: Color(0xFF709BF7),
              ),
              const SizedBox(width: 10),
              const Text(
                '机构名称',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
              if (selectedCategory?.id == 9 || _isPartTime) // 价格表 / 兼职用户必填
                const Text(
                  '*',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _hospitalController,
            focusNode: _hospitalFocusNode,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: (selectedCategory?.id == 9 || _isPartTime)
                  ? '请输入机构名称（必填）'
                  : '请输入机构名称',
              hintStyle: const TextStyle(
                color: Color(0xFFB2B2B2),
                fontSize: 14,
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF366CDF)),
              ),
              suffixIcon: const Icon(Icons.search, color: Color(0xFFB2B2B2)),
            ),
            onChanged: (value) {
              _searchHospitalWithDebounce(value);
            },
            onTap: () {
              setState(() {
                showHospitalSearchResults = true;
              });
            },
            onEditingComplete: () {
              // 点击键盘上的"完成"按钮时，取消焦点
              _hospitalFocusNode.unfocus();
            },
          ),
          if (isSearchingHospital)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (hospitalSearchResults.isNotEmpty &&
              showHospitalSearchResults &&
              !isSearchingHospital)
            Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E5E5)),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: hospitalSearchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final hospital = hospitalSearchResults[index];

                  // 构建副标题，优先显示有内容的多语言名称
                  String? subtitle;
                  final List<String> names = [];

                  if (hospital.hospitalEnName != null &&
                      hospital.hospitalEnName!.isNotEmpty) {
                    names.add(hospital.hospitalEnName!);
                  }
                  if (hospital.hospitalKrName != null &&
                      hospital.hospitalKrName!.isNotEmpty) {
                    names.add(hospital.hospitalKrName!);
                  }
                  if (hospital.hospitalJpName != null &&
                      hospital.hospitalJpName!.isNotEmpty) {
                    names.add(hospital.hospitalJpName!);
                  }

                  if (names.isNotEmpty) {
                    subtitle = names.join(' / ');
                  }

                  return ListTile(
                    title: Text(hospital.name),
                    subtitle: subtitle != null
                        ? Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF666666),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () {
                      _hospitalFocusNode.unfocus();
                      setState(() {
                        selectedHospital = hospital;
                        _hospitalController.text = hospital.name;
                        showHospitalSearchResults = false;
                      });
                      // 保存缓存
                      _saveCachedData();
                    },
                  );
                },
              ),
            ),
          if (selectedHospital != null && !showHospitalSearchResults)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF366CDF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已选择：${selectedHospital!.name}',
                      style: const TextStyle(color: Color(0xFF366CDF)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedHospital = null;
                        _hospitalController.clear();
                      });
                      // 保存缓存
                      _saveCachedData();
                    },
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF366CDF),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          // 客户ID输入框（当有音频文件时显示）
          if (_hasAudioFile()) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: Color(0xFF709BF7),
                ),
                const SizedBox(width: 10),
                const Text(
                  '客户ID',
                  style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _clientIdController,
              focusNode: _clientIdFocusNode,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: '请输入客户ID',
                hintStyle: const TextStyle(
                  color: Color(0xFFB2B2B2),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF366CDF)),
                ),
              ),
              onEditingComplete: () {
                _clientIdFocusNode.unfocus();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 构建可见范围选择区域
  Widget _buildVisibilitySection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, size: 20, color: Color(0xFF709BF7)),
              const SizedBox(width: 10),
              const Text(
                '可见范围',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
              ),
              const Text(
                '*',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: visibilityOptions.map((option) {
              final isActive = selectedVisibilityId == option.id;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedVisibilityId = option.id;
                    selectedDepartmentIds.clear();
                  });
                  _saveCachedData();
                  if (option.id == 2 && departmentList.isEmpty) {
                    _loadDepartments();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF709BF7)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    option.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: isActive ? Colors.white : const Color(0xFF3D3D3D),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (selectedVisibilityId == 2) ...[
            const SizedBox(height: 14),
            if (isLoadingDepartments)
              const Center(child: CircularProgressIndicator())
            else if (departmentList.isEmpty)
              const Text('暂无部门数据', style: TextStyle(color: Color(0xFF999999)))
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '请选择可见的部门：',
                      style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: departmentList.map((dept) {
                        final isSelected = selectedDepartmentIds.contains(
                          dept.id,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selectedDepartmentIds.remove(dept.id);
                              } else {
                                selectedDepartmentIds.add(dept.id);
                              }
                            });
                            // 保存缓存
                            _saveCachedData();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF709BF7)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF709BF7)
                                    : const Color(0xFFE5E5E5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF999999),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  dept.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF3D3D3D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 构建提交按钮
  Widget _buildSubmitButton() {
    // 获取底部安全区域高度（Android 导航栏高度）
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + bottomPadding, // 16px内边距 + 系统底部安全区域
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed: isSubmitting ? null : _validateAndSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF709BF7),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: isSubmitting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  widget.editId != null ? '确认编辑' : '确认提交',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  /// 获取上传线路文本
  // String _getUploadRegionText() {
  //   final region = uploadRegionList.firstWhere(
  //     (item) => item['value'] == uploadRegion,
  //     orElse: () => {'name': '未知'},
  //   );
  //   return region['name']!;
  // }

  /// 显示上传线路选择对话框
  // void _showRegionPickerDialog() {
  //   showDialog(
  //     context: context,
  //     builder: (context) => Dialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  //       child: Container(
  //         width: MediaQuery.of(context).size.width * 0.85,
  //         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             const Text(
  //               '选择上传线路',
  //               style: TextStyle(
  //                 fontSize: 18,
  //                 fontWeight: FontWeight.bold,
  //                 color: Color(0xFF1A1A1A),
  //               ),
  //             ),
  //             const SizedBox(height: 22),
  //             ...uploadRegionList.map((item) {
  //               final isActive = uploadRegion == item['value'];
  //               return GestureDetector(
  //                 onTap: () {
  //                   setState(() {
  //                     uploadRegion = item['value']!;
  //                   });
  //                   _saveCachedData();
  //                   Navigator.pop(context);
  //                   // NAS 模式不需要重新加载配置
  //                 },
  //                 child: Container(
  //                   margin: const EdgeInsets.only(bottom: 12),
  //                   padding: const EdgeInsets.all(16),
  //                   decoration: BoxDecoration(
  //                     color: isActive
  //                         ? const Color(0xFFE8F0FF)
  //                         : const Color(0xFFF9FAFB),
  //                     borderRadius: BorderRadius.circular(16),
  //                     border: isActive
  //                         ? Border.all(color: const Color(0xFF366CDF), width: 2)
  //                         : null,
  //                   ),
  //                   child: Row(
  //                     children: [
  //                       Expanded(
  //                         child: Column(
  //                           crossAxisAlignment: CrossAxisAlignment.start,
  //                           children: [
  //                             Text(
  //                               item['name']!,
  //                               style: const TextStyle(
  //                                 fontSize: 15,
  //                                 fontWeight: FontWeight.w500,
  //                                 color: Color(0xFF1A1A1A),
  //                               ),
  //                             ),
  //                             const SizedBox(height: 2),
  //                             Text(
  //                               item['desc']!,
  //                               style: const TextStyle(
  //                                 fontSize: 14,
  //                                 color: Color(0xFF999999),
  //                               ),
  //                             ),
  //                           ],
  //                         ),
  //                       ),
  //                       if (isActive)
  //                         const Icon(
  //                           Icons.check_circle,
  //                           color: Color(0xFF366CDF),
  //                           size: 24,
  //                         ),
  //                     ],
  //                   ),
  //                 ),
  //               );
  //             }),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  /// 显示示例对话框
  void _showExampleDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '描述示例',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '示例 1：\n首尔江南站区域街景\n拍摄于明洞购物街\n晴天，人流密集\n\n示例 2：\nXX医院鼻整形案例\n患者术后3个月恢复照\n效果自然，满意度高',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示文件处理进度对话框
  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭
      barrierColor: Colors.black54,
      builder: (context) => PopScope(
        canPop: false, // 禁止返回键关闭
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 加载动画
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF709BF7),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '正在处理...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请稍候，正在处理选中的文件',
                  style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示媒体选择选项
  Future<void> _showMediaPickerOptions() async {
    // 先取消输入框焦点，避免选择完成后键盘自动弹出
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera,
                  color: Color(0xFF709BF7),
                ),
                title: const Text('拍摄照片'),
                onTap: () {
                  Navigator.pop(context);
                  _capturePhoto();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Color(0xFF709BF7)),
                title: const Text('拍摄视频'),
                onTap: () {
                  Navigator.pop(context);
                  _captureVideo();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF709BF7),
                ),
                title: const Text('从相册选择'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.grey),
                title: const Text('取消'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 拍摄照片
  Future<void> _capturePhoto() async {
    final ImagePicker picker = ImagePicker();

    // 检查剩余可选数量
    final remainingSlots = maxFileCount - uploadFiles.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('最多只能上传 $maxFileCount 个文件')));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessingFiles = true;
      });
      _showProcessingDialog();
    }

    try {
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) return;

      await _addMediaFiles([photo]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍摄照片失败: $e')));
    } finally {
      if (_isProcessingFiles && mounted) {
        try {
          Navigator.of(context).pop();
        } catch (e) {
          // 对话框可能已经关闭
        }
        setState(() {
          _isProcessingFiles = false;
        });
      }
    }
  }

  /// 拍摄视频
  Future<void> _captureVideo() async {
    final ImagePicker picker = ImagePicker();

    // 检查剩余可选数量
    final remainingSlots = maxFileCount - uploadFiles.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('最多只能上传 $maxFileCount 个文件')));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessingFiles = true;
      });
      _showProcessingDialog();
    }

    try {
      final XFile? video = await picker.pickVideo(source: ImageSource.camera);

      if (video == null) return;

      await _addMediaFiles([video]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍摄视频失败: $e')));
    } finally {
      if (_isProcessingFiles && mounted) {
        try {
          Navigator.of(context).pop();
        } catch (e) {
          // 对话框可能已经关闭
        }
        setState(() {
          _isProcessingFiles = false;
        });
      }
    }
  }

  /// 选择图片或视频（从相册）
  Future<void> _pickMedia() async {
    final ImagePicker picker = ImagePicker();

    // 检查剩余可选数量
    final remainingSlots = maxFileCount - uploadFiles.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('最多只能上传 $maxFileCount 个文件')));
      }
      return;
    }

    // 在调用 picker 之前就显示处理对话框
    // 因为 image_picker 的图片压缩是在返回之前进行的
    if (mounted) {
      setState(() {
        _isProcessingFiles = true;
      });
      _showProcessingDialog();
    }

    try {
      // image_picker 的 limit 参数最小值为2，如果只剩1个位置，特殊处理
      List<XFile> media;
      if (remainingSlots == 1) {
        // 只剩1个位置时，使用单选模式
        final XFile? singleFile = await picker.pickMedia(imageQuality: 85);
        if (singleFile == null) return;
        media = [singleFile];
      } else {
        // 多选模式，直接调起系统相册
        media = await picker.pickMultipleMedia(
          imageQuality: 85, // 图片压缩质量
          limit: remainingSlots, // 限制为剩余可选数量
        );
      }

      if (media.isEmpty) return;

      await _addMediaFiles(media);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择媒体文件失败: $e')));
    } finally {
      // 确保关闭对话框
      if (_isProcessingFiles && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        setState(() {
          _isProcessingFiles = false;
        });
      }
    }
  }

  /// 添加媒体文件到上传队列
  Future<void> _addMediaFiles(List<XFile> media) async {
    // 检查文件数量限制
    final remainingSlots = maxFileCount - uploadFiles.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        _showSnackBar('最多只能上传 $maxFileCount 个文件');
      }
      return;
    }

    // 限制选择的文件数量
    final filesToAdd = media.take(remainingSlots).toList();
    if (filesToAdd.length < media.length) {
      if (mounted) {
        _showSnackBar('只能再添加 $remainingSlots 个文件，已自动限制选择数量');
      }
    }

    // NAS 模式无需检查上传配置

    for (var i = 0; i < filesToAdd.length; i++) {
      final file = filesToAdd[i];
      // 使用 XFile 的 name 属性获取正确的文件名
      final fileName = file.name;
      // 获取文件大小
      final fileSize = await file.length();
      final uploadFile = UploadFile.fromPath(
        file.path,
        customFileName: fileName,
        fileSize: fileSize,
      );

      // 添加到队列管理器（使用 NAS 上传）
      final taskId = _uploadQueueManager.addNasTask(
        uploadFile,
        hospitalName: selectedHospital?.name,
        editId: widget.editId,
      );

      // 保存到本地映射
      if (mounted) {
        setState(() {
          taskIds.add(taskId);
          uploadFiles[taskId] = uploadFile;
        });
      }
    }

    // 保存缓存
    _saveCachedData();

    if (!mounted) return;

    _showSnackBar('已添加 ${filesToAdd.length} 个文件到上传队列');
  }

  /// 选择文件
  Future<void> _pickFiles() async {
    // 先取消输入框焦点，避免选择完成后键盘自动弹出
    FocusScope.of(context).unfocus();

    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      // 检查文件数量限制
      final remainingSlots = maxFileCount - uploadFiles.length;
      if (remainingSlots <= 0) {
        if (mounted) {
          _showSnackBar('最多只能上传 $maxFileCount 个文件');
        }
        return;
      }

      // 限制选择的文件数量
      final filesToAdd = result.files.take(remainingSlots).toList();
      if (filesToAdd.length < result.files.length) {
        if (mounted) {
          _showSnackBar('只能再添加 $remainingSlots 个文件，已自动限制选择数量');
        }
      }

      // NAS 模式无需检查上传配置

      // 如果文件数量较多，显示处理进度对话框
      final showProgress = filesToAdd.length > 2;
      if (showProgress && mounted) {
        setState(() {
          _isProcessingFiles = true;
        });
        _showProcessingDialog();
      }

      try {
        for (var i = 0; i < filesToAdd.length; i++) {
          final file = filesToAdd[i];
          if (file.path != null) {
            // 使用 PlatformFile 的 name 属性获取正确的文件名
            final fileName = file.name;
            final filePath = file.path!;
            final fileSize = file.size; // 获取文件大小
            final uploadFile = UploadFile.fromPath(
              filePath,
              customFileName: fileName,
              fileSize: fileSize,
            );

            // 添加到队列管理器（使用 NAS 上传）
            final taskId = _uploadQueueManager.addNasTask(
              uploadFile,
              hospitalName: selectedHospital?.name,
            );

            // 保存到本地映射
            if (mounted) {
              setState(() {
                taskIds.add(taskId);
                uploadFiles[taskId] = uploadFile;
              });
            }
          }
        }
      } finally {
        // 关闭处理进度对话框
        if (showProgress && mounted && _isProcessingFiles) {
          Navigator.of(context, rootNavigator: true).pop();
          setState(() {
            _isProcessingFiles = false;
          });
        }
      }

      // 保存缓存
      _saveCachedData();

      if (!mounted) return;

      _showSnackBar('已添加 ${filesToAdd.length} 个文件到上传队列');
    } catch (e) {
      // 确保异常时也关闭对话框
      if (_isProcessingFiles && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        setState(() {
          _isProcessingFiles = false;
        });
      }
      if (!mounted) return;
      _showSnackBar('选择文件失败: $e');
    }
  }

  /// 搜索医院（带防抖）
  void _searchHospitalWithDebounce(String keyword) {
    // 取消之前的定时器
    _searchDebounceTimer?.cancel();
    // 取消上一个在途请求，避免并发与乱序返回
    _searchCancelToken?.cancel();
    _searchCancelToken = null;

    // 如果输入为空，清空结果
    if (keyword.trim().isEmpty) {
      setState(() {
        hospitalSearchResults.clear();
        isSearchingHospital = false;
        showHospitalSearchResults = false;
      });
      return;
    }

    // 设置新的定时器（500ms 后执行搜索）
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchHospital(keyword);
    });
  }

  /// 搜索医院
  Future<void> _searchHospital(String keyword) async {
    if (keyword.trim().isEmpty) {
      setState(() {
        hospitalSearchResults.clear();
        isSearchingHospital = false;
      });
      return;
    }

    // 为本次搜索创建取消令牌
    final cancelToken = CancelToken();
    _searchCancelToken = cancelToken;

    setState(() {
      isSearchingHospital = true;
      showHospitalSearchResults = true;
    });

    try {
      List<Hospital> results;
      // 价格表分类使用专用搜索接口
      if (selectedCategory?.id == 9) {
        results = await MaterialApi.searchPriceHospital(
          keyword,
          cancelToken: cancelToken,
        );
      } else {
        results = await MaterialApi.searchHospital(
          keyword,
          cancelToken: cancelToken,
        );
      }

      // 仅当本次请求仍是最新请求、且输入框内容未变时才更新结果，
      // 避免旧关键词的响应覆盖新结果（乱序返回竞态）
      if (!mounted ||
          cancelToken != _searchCancelToken ||
          _hospitalController.text.trim() != keyword.trim()) {
        return;
      }

      setState(() {
        hospitalSearchResults = results;
        isSearchingHospital = false;
      });
    } catch (e) {
      // 请求被取消属于正常流程，静默忽略
      if (e is DioException && CancelToken.isCancel(e)) {
        return;
      }
      // 已被更新的请求不再处理 loading 与提示
      if (!mounted || cancelToken != _searchCancelToken) {
        return;
      }
      setState(() {
        isSearchingHospital = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('机构搜索失败，请稍后重试')));
    }
  }

  /// 加载部门列表
  Future<void> _loadDepartments() async {
    if (departmentList.isNotEmpty) return;

    setState(() {
      isLoadingDepartments = true;
    });

    try {
      // 使用 DepartmentService 的缓存机制，避免重复请求
      final departmentService = DepartmentService();
      final departments = await departmentService.getDepartments();
      if (mounted) {
        setState(() {
          departmentList = departments;
          isLoadingDepartments = false;
        });
        // 保存部门列表到缓存
        _saveCachedData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingDepartments = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载部门列表失败: $e')));
      }
    }
  }

  /// 表单验证和提交
  Future<void> _validateAndSubmit() async {
    // 取消所有输入框焦点，避免键盘在验证失败后重新弹出
    FocusScope.of(context).unfocus();

    // 检查游客模式
    if (_isGuestMode) {
      _showErrorMessage('测试账户不可提交');
      return;
    }

    // 验证素材归属
    if (currentType == null) {
      _showErrorMessage('请选择素材归属');
      return;
    }

    // 验证素材分类
    if (selectedCategory == null) {
      _showErrorMessage('请选择素材分类');
      return;
    }

    // 验证价格表分类的医院必填
    if (selectedCategory?.id == 9 && selectedHospital == null) {
      _showErrorMessage('价格表分类必须选择医院');
      return;
    }

    // 兼职用户医院必填
    if (_isPartTime && selectedHospital == null) {
      _showErrorMessage('请选择机构名称');
      return;
    }

    // 验证可见范围
    if (selectedVisibilityId == 2 && selectedDepartmentIds.isEmpty) {
      _showErrorMessage('请选择可见的部门');
      return;
    }

    // 验证文件是否已选择
    if (uploadFiles.isEmpty) {
      _showErrorMessage('请选择要上传的文件');
      return;
    }

    // 检查是否有文件正在上传
    final uploadingFiles = uploadFiles.values
        .where((f) => f.status == UploadFileStatus.uploading)
        .toList();

    // 获取上传成功的文件
    final successFiles = uploadFiles.values
        .where((f) => f.status == UploadFileStatus.success)
        .toList();

    // 检查是否有上传失败的文件
    final failedFiles = uploadFiles.values
        .where((f) => f.status == UploadFileStatus.failed)
        .toList();

    // 如果有正在上传的文件，询问用户是否继续
    if (uploadingFiles.isNotEmpty) {
      final shouldContinue =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('提示'),
              content: Text(
                '当前有 ${uploadingFiles.length} 个文件正在上传中，是否仍要提交？\n'
                '\n已完成上传：${successFiles.length} 个'
                '${failedFiles.isNotEmpty ? '\n上传失败：${failedFiles.length} 个' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('等待上传完成'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF709BF7),
                  ),
                  child: const Text('仍要提交'),
                ),
              ],
            ),
          ) ??
          false;

      if (!shouldContinue) return;
    }

    // 检查是否有成功上传的文件
    if (successFiles.isEmpty) {
      if (mounted) {
        _showErrorMessage('没有上传成功的文件，请等待上传完成或重新选择文件');
      }
      return;
    }

    // 如果有上传失败的文件，再次确认
    if (failedFiles.isNotEmpty && uploadingFiles.isEmpty) {
      if (!mounted) return;

      final shouldContinue =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('提示'),
              content: Text(
                '有 ${failedFiles.length} 个文件上传失败，是否仅提交已成功上传的 ${successFiles.length} 个文件？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF709BF7),
                  ),
                  child: const Text('继续提交'),
                ),
              ],
            ),
          ) ??
          false;

      if (!shouldContinue) return;
    }

    // 显示确认对话框
    if (!mounted) return;
    final confirmed = await _showConfirmDialog(successFiles.length);
    if (!confirmed) return;

    // 对话框关闭后再次确保焦点已取消，防止键盘自动弹出
    if (mounted) FocusScope.of(context).unfocus();

    // 开始提交
    setState(() {
      isSubmitting = true;
    });

    try {
      // 构建上传文件信息列表（NAS 模式添加 storage_type）
      final uploadedFilesList = successFiles.map((file) {
        final fileData = <String, dynamic>{
          'original_name': file.originalName ?? file.fileName,
          'file_name': file.fileName,
          'file_path': file.ossFilePath ?? '',
          'file_size': file.fileSize,
          'url': file.remoteUrl ?? '',
          'storage_type': 'nas', // NAS 存储类型
        };
        // 编辑模式下需要回传文件记录ID
        if (file.serverFileId != null && file.serverFileId!.isNotEmpty) {
          fileData['id'] = file.serverFileId!;
        }
        // 添加缩略图/视频截帧路径（图片用 thumbnail，视频用 video_frame）
        if (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) {
          fileData['thumbnail'] = file.thumbnailPath!;
        }
        return fileData;
      }).toList();

      // 提交素材信息到服务器
      final submitData = {
        'text': _contentController.text,
        'hospital_id': selectedHospital?.hospitalId ?? '',
        'hospital_name': selectedHospital?.name ?? '',
        'kf_hospital_id': selectedHospital?.kfHospitalId ?? '',
        'area_type': selectedHospital?.areaType ?? '',
        'file': uploadedFilesList,
        'material_category': selectedCategory!.id,
        'source': 'App',
        'country_type': int.tryParse(currentType!) ?? 1,
        'department_id': selectedVisibilityId == 1
            ? ''
            : selectedDepartmentIds.join(','),
        if (_hasAudioFile()) 'client_id': _clientIdController.text.trim(),
      };

      // 根据是否为编辑模式调用不同的API
      final result = widget.editId != null
          ? await MaterialApi.editMaterial({
              ...submitData,
              'id': widget.editId!,
            })
          : await MaterialApi.submitMaterial(submitData);

      if (result != null && result['code'] == 0) {
        if (mounted) {
          setState(() {
            isSubmitting = false;
          });

          _showSnackBar(widget.editId != null ? '修改成功！' : '提交成功！');

          // 通知我的作品页面刷新数据
          EventBusService().notifyMaterialUploaded();

          // 清空表单
          _resetForm();
          // 保存缓存
          await _saveCachedData();

          // 如果是编辑模式，返回上一页并传递成功标志
          if (widget.editId != null && mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            Navigator.of(context).pop(true);
          }
        }
      } else {
        throw Exception(
          result?['msg'] ?? (widget.editId != null ? '修改失败' : '提交失败'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
        _showErrorMessage('提交失败: $e');
      }
    }
  }

  /// 显示错误消息
  void _showErrorMessage(String message) {
    _showSnackBar(message);
  }

  /// 显示确认对话框
  Future<bool> _showConfirmDialog(int fileCount) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认提交'),
            content: Text(
              '素材归属：${tagList.firstWhere((t) => t['id'] == currentType)['name']}\n'
              '素材分类：${selectedCategory?.name}\n'
              '医院：${selectedHospital?.name ?? '未选择'}\n'
              '可见范围：${visibilityOptions.firstWhere((v) => v.id == selectedVisibilityId).name}\n'
              '文件数量：$fileCount 个\n\n'
              '确认提交吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 重置表单
  void _resetForm() {
    // 先失焦所有输入框，避免清空后自动聚焦
    _contentFocusNode.unfocus();
    _hospitalFocusNode.unfocus();
    _clientIdFocusNode.unfocus();

    setState(() {
      _contentController.clear();
      selectedHospital = null;
      _hospitalController.clear();
      _clientIdController.clear();
      hospitalSearchResults.clear();
      taskIds.clear();
      uploadFiles.clear(); // 清空上传文件映射
    });

    // 清除临时缓存数据（不包括可见范围和部门选择）
    _clearTemporaryCache();

    // 清除图片缓存，释放内存
    _clearImageCache();

    // 清除上传队列中的已完成任务（防止任务堆积）
    _uploadQueueManager.clearCompletedTasks();
  }

  /// 清除临时缓存数据（提交成功后）
  /// 注意：不清除可见范围和部门选择，这些需要保留
  Future<void> _clearTemporaryCache() async {
    final prefs = await SharedPreferences.getInstance();

    // 清除内容描述
    await prefs.remove('cached_content_description');

    // 清除医院选择
    await prefs.remove('cached_hospital');

    // 清除文件列表
    await prefs.remove('cached_upload_files');
  }

  /// 清理图片缓存（释放内存）
  void _clearImageCache() {
    try {
      // 清理 Flutter 的图片缓存
      final imageCache = PaintingBinding.instance.imageCache;

      // 清空所有缓存
      imageCache.clear();

      // 清空实时缓存
      imageCache.clearLiveImages();
    } catch (e) {
      if (kDebugMode) {
        print('[素材上传] 清理图片缓存失败: $e');
      }
    }
  }

  /// 构建文件列表（网格布局）
  Widget _buildFileList() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero, // 消除 GridView 默认内边距
      gridDelegate: responsiveMaterialGridDelegate(
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1, // 调整比例，使网格更紧凑
      ),
      // 性能优化：禁用自动保活，启用 RepaintBoundary
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      scrollCacheExtent: const ScrollCacheExtent.pixels(0), // 禁用预加载缓存，降低内存压力
      itemCount: taskIds.length,
      itemBuilder: (context, index) {
        final taskId = taskIds[index];
        final file = uploadFiles[taskId];
        if (file == null) {
          // taskIds 与 uploadFiles 不同步时的安全保护
          return const SizedBox.shrink();
        }
        return _buildFileItem(file, taskId);
      },
    );
  }

  /// 构建单个文件项
  Widget _buildFileItem(UploadFile file, String taskId) {
    // 判断是否可以点击预览（上传成功且是图片/视频/音频）
    final canPreview =
        file.status == UploadFileStatus.success &&
        file.remoteUrl != null &&
        (file.fileType == UploadFileType.image ||
            file.fileType == UploadFileType.video ||
            file.fileType == UploadFileType.audio);

    return Column(
      children: [
        // 预览区域（带状态指示）
        Expanded(
          child: GestureDetector(
            onTap: canPreview ? () => _openPreview(file, taskId) : null,
            child: Stack(
              children: [
                // 预览内容
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildFilePreview(file),
                  ),
                ),
                // 上传进度遮罩
                if (file.status == UploadFileStatus.uploading)
                  Positioned.fill(
                    child: _buildUploadProgressMask(file, taskId),
                  ),
                // 队列中状态遮罩
                if (file.status == UploadFileStatus.pending)
                  Positioned.fill(child: _buildPendingMask(file, taskId)),
                // 暂停状态遮罩
                if (file.status == UploadFileStatus.paused)
                  Positioned.fill(child: _buildPausedMask(file, taskId)),
                // 失败状态遮罩
                if (file.status == UploadFileStatus.failed)
                  Positioned.fill(child: _buildFailedMask(file, taskId)),
                // 删除按钮 - 扩大触摸区域
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _removeFile(taskId),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0), // 扩大触摸区域
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                // 上传状态指示
                if (file.status == UploadFileStatus.success)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2EB678),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                if (file.status == UploadFileStatus.failed)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF56C6C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 打开预览页面
  void _openPreview(UploadFile file, String taskId) {
    // 获取所有上传成功的图片、视频和音频文件
    final successFiles = taskIds
        .map((id) => uploadFiles[id])
        .where(
          (f) =>
              f != null &&
              f.status == UploadFileStatus.success &&
              f.remoteUrl != null &&
              (f.fileType == UploadFileType.image ||
                  f.fileType == UploadFileType.video ||
                  f.fileType == UploadFileType.audio),
        )
        .cast<UploadFile>()
        .toList();

    // 找到当前文件在列表中的索引
    final currentIndex = successFiles.indexWhere((f) => f.id == file.id);
    if (currentIndex == -1) return;

    // 转换为 MaterialFile 列表
    final materialFiles = successFiles
        .map((f) => _convertToMaterialFile(f))
        .toList();

    // 打开预览页面
    Navigator.push(
      context,
      _createZoomRoute(
        MaterialPreviewPage(
          files: materialFiles,
          initialIndex: currentIndex,
          hospitalName: selectedHospital?.name ?? '',
          enableViewCount: false,
        ),
      ),
    );
  }

  /// 将 UploadFile 转换为 MaterialFile（用于预览）
  MaterialFile _convertToMaterialFile(UploadFile file) {
    // 根据文件类型确定 fileClassification
    String fileClassification;
    switch (file.fileType) {
      case UploadFileType.image:
        fileClassification = 'image';
        break;
      case UploadFileType.video:
        fileClassification = 'video';
        break;
      case UploadFileType.audio:
        fileClassification = 'audio';
        break;
      case UploadFileType.document:
        fileClassification = 'document';
        break;
    }

    return MaterialFile(
      id: file.id.hashCode, // 使用 id 的 hashCode 作为临时 ID
      url: file.remoteUrl ?? '',
      fileName: file.fileName,
      filePath: file.ossFilePath ?? '',
      fileClassification: fileClassification,
      downloadCount: 0,
      showCount: 0,
      isCollected: false,
      originalName: file.originalName ?? file.fileName,
      size: file.fileSize.toString(),
      fileSuffix: file.fileName.split('.').last,
    );
  }

  /// 构建文件预览
  Widget _buildFilePreview(UploadFile file) {
    // 如果文件已上传成功且有远程URL，优先使用远程URL显示
    if (file.status == UploadFileStatus.success && file.remoteUrl != null) {
      if (file.fileType == UploadFileType.image) {
        // 优先使用后端返回的缩略图 URL（NAS 模式）
        // 如果没有，则使用 OSS 图片处理参数
        final thumbnailUrl =
            file.thumbnailUrl ?? _getImageThumbnailUrl(file.remoteUrl!);
        return CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: 120,
          maxWidthDiskCache: 240,
          placeholder: (context, url) =>
              Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (context, url, error) => _buildFileIcon(file),
        );
      } else if (file.fileType == UploadFileType.video) {
        // 优先使用后端返回的视频截帧 URL（NAS 模式）
        // 如果没有，则使用 OSS 视频截帧参数
        final snapshotUrl =
            file.thumbnailUrl ?? _getVideoSnapshotUrl(file.remoteUrl!);
        return CachedNetworkImage(
          imageUrl: snapshotUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: 120,
          maxWidthDiskCache: 240,
          placeholder: (context, url) =>
              Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (context, url, error) => _buildFileIcon(file),
        );
      }
      // 文档文件显示图标
      return _buildFileIcon(file);
    }

    // 图片和视频显示预览
    if (file.fileType == UploadFileType.image) {
      // 检查文件是否存在
      final fileExists = File(file.localPath).existsSync();
      if (!fileExists) {
        // 文件不存在，显示提示
        return _buildFileIcon(file);
      }

      return Image.file(
        File(file.localPath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 120, // 限制解码后的图片宽度，降低内存占用
        errorBuilder: (context, error, stackTrace) {
          return _buildFileIcon(file);
        },
      );
    }

    // 其他情况显示文件图标和文件名
    return _buildFileIcon(file);
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

  /// 构建文件图标（当无法显示缩略图时使用）
  /// 所有类型都显示文件名，因为此时无法通过缩略图识别文件
  Widget _buildFileIcon(UploadFile file) {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFileIcon(file.fileType),
              size: 40,
              color: const Color(0xFF709BF7),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                file.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF666666),
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取文件类型图标
  IconData _getFileIcon(UploadFileType type) {
    switch (type) {
      case UploadFileType.image:
        return Icons.image;
      case UploadFileType.video:
        return Icons.videocam;
      case UploadFileType.audio:
        return Icons.audiotrack;
      case UploadFileType.document:
        return Icons.insert_drive_file;
    }
  }

  /// 构建队列中状态遮罩
  Widget _buildPendingMask(UploadFile file, String taskId) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '队列中',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建上传进度遮罩
  Widget _buildUploadProgressMask(UploadFile file, String taskId) {
    return GestureDetector(
      onTap: () {
        // 点击暂停上传
        _uploadQueueManager.pauseTask(taskId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: file.progress / 100,
                  strokeWidth: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF366CDF),
                  ),
                ),
                Text(
                  '${file.progress.toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建暂停状态遮罩
  Widget _buildPausedMask(UploadFile file, String taskId) {
    return GestureDetector(
      onTap: () {
        // 点击继续上传
        _resumeOrRecreateTask(file, taskId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(height: 4),
              const Text(
                '点击继续',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (file.progress > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${file.progress.toInt()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建失败状态遮罩
  Widget _buildFailedMask(UploadFile file, String taskId) {
    return GestureDetector(
      onTap: () {
        // 点击重试上传
        _retryOrRecreateTask(file, taskId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh, color: Colors.white, size: 40),
              const SizedBox(height: 4),
              const Text(
                '点击重试',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (file.errorMessage != null &&
                  file.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    file.errorMessage!,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 继续上传任务（如果任务不存在则重新创建）
  Future<void> _resumeOrRecreateTask(UploadFile file, String taskId) async {
    // 检查任务是否存在于队列管理器中
    final existingTask = _uploadQueueManager.getTask(taskId);

    if (existingTask != null) {
      // 任务存在，直接恢复
      _uploadQueueManager.resumeTask(taskId);
    } else {
      // 任务不存在，需要重新创建
      debugPrint('[素材上传] 任务 $taskId 不存在于队列中，尝试重新创建...');

      // 检查本地文件是否存在
      if (file.localPath.isNotEmpty) {
        final localFile = File(file.localPath);
        if (!await localFile.exists()) {
          if (mounted) {
            _showSnackBar('文件已被删除，无法继续上传');
          }
          // 从列表中移除
          _removeFile(taskId);
          return;
        }
      }

      // 重新创建任务（使用 NAS 上传，无需 OSS 配置）
      final newTaskId = _uploadQueueManager.addNasTask(
        file,
        hospitalName: selectedHospital?.name,
        editId: widget.editId,
      );

      // 更新本地映射
      setState(() {
        // 移除旧的 taskId
        taskIds.remove(taskId);
        uploadFiles.remove(taskId);
        // 添加新的 taskId
        taskIds.add(newTaskId);
        uploadFiles[newTaskId] = file.copyWith(
          status: UploadFileStatus.pending,
        );
      });

      // 保存缓存
      _saveCachedData();

      if (mounted) {
        _showSnackBar('已重新添加到上传队列', duration: const Duration(seconds: 1));
      }
    }
  }

  /// 重试上传任务（如果任务不存在则重新创建）
  /// NAS 模式下无需刷新配置，直接重试
  Future<void> _retryOrRecreateTask(UploadFile file, String taskId) async {
    // 检查任务是否存在于队列管理器中
    final existingTask = _uploadQueueManager.getTask(taskId);

    if (existingTask != null) {
      // 任务存在，直接重试（NAS 模式无需刷新配置）
      debugPrint('[素材上传] 准备重试任务 $taskId');
      _uploadQueueManager.retryTask(taskId);
    } else {
      // 任务不存在，使用与继续上传相同的逻辑重新创建
      await _resumeOrRecreateTask(file, taskId);
    }
  }

  /// 删除文件
  void _removeFile(String taskId) {
    // 从队列管理器中完全移除任务（会自动触发 queueStream 更新，同步到其他页面）
    _uploadQueueManager.removeTask(taskId);

    // 从本地映射中删除（会通过 queueStream 监听自动删除，但为了立即更新UI，这里也手动删除）
    setState(() {
      taskIds.remove(taskId);
      uploadFiles.remove(taskId);
    });

    // 保存缓存
    _saveCachedData();
  }

  /// 创建放大动画路由（与首页保持一致）
  Route _createZoomRoute(Widget page) {
    return PageRouteBuilder(
      opaque: false, // 设置为透明路由
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // 使用非线性曲线，让动画更自然
        const curve = Curves.fastOutSlowIn;

        // 缩放从 0.85 开始，而不是从 0，让动画更柔和
        var scaleTween = Tween(
          begin: 0.85,
          end: 1.0,
        ).chain(CurveTween(curve: curve));

        // 淡入效果也使用相同的曲线
        var fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: curve));

        return FadeTransition(
          opacity: animation.drive(fadeTween),
          child: ScaleTransition(
            scale: animation.drive(scaleTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 350), // 稍微延长动画时间
      reverseTransitionDuration: const Duration(milliseconds: 300), // 返回动画更快
    );
  }
}
