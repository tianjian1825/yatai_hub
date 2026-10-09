import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:async';
import '../models/material_item.dart';
import '../services/material_api.dart';
import '../services/user_service.dart';

/// 图片/视频预览页面
class MaterialPreviewPage extends StatefulWidget {
  final List<MaterialFile> files; // 当前组的所有文件
  final int initialIndex; // 初始显示的文件索引
  final String hospitalName; // 医院名称
  final bool enableViewCount; // 是否启用浏览量统计（默认为true）

  const MaterialPreviewPage({
    super.key,
    required this.files,
    required this.initialIndex,
    this.hospitalName = '',
    this.enableViewCount = true, // 默认启用
  });

  @override
  State<MaterialPreviewPage> createState() => _MaterialPreviewPageState();
}

class _MaterialPreviewPageState extends State<MaterialPreviewPage> {
  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false; // 视频初始化加载状态
  bool _isSaving = false; // 保存文件时的加载状态
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isDraggingImage = false; // 图片是否正在拖拽（用于隐藏UI）
  bool _isZoomed = false; // 是否处于放大状态
  bool _isInteractingWithImage = false; // 是否正在与图片交互（缩放/拖拽）
  bool _isClosingViaDrag = false; // Flag to suppress content during drag-close
  int _currentPointerCount = 0; // 当前屏幕上的手指数量

  // 本地浏览量状态（用于实时更新显示）
  late Map<int, int> _localShowCounts;
  // 本地下载量状态（用于实时更新显示）
  late Map<int, int> _localDownloadCounts;

  // 是否允许pop
  bool _canPop = false;

  @override
  void initState() {
    super.initState();

    // 设置状态栏样式：透明背景，白色文本
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 状态栏背景透明
        statusBarIconBrightness: Brightness.light, // Android 状态栏图标亮色（白色）
        statusBarBrightness: Brightness.dark, // iOS 状态栏文本亮色（白色）
      ),
    );

    _currentIndex = widget.files.length * 1000 + widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // 初始化本地浏览量和下载量状态
    _localShowCounts = {};
    _localDownloadCounts = {};
    for (var file in widget.files) {
      _localShowCounts[file.id] = file.showCount;
      _localDownloadCounts[file.id] = file.downloadCount;
    }

    // 初始化当前页面（如果是视频）
    _initCurrentPage();

    // 增加浏览次数（仅在启用时）
    if (widget.enableViewCount) {
      _increaseViewCount();
    }
  }

  @override
  void dispose() {
    // 恢复默认状态栏样式
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android 恢复深色图标
        statusBarBrightness: Brightness.light, // iOS 恢复深色文本
      ),
    );

    _pageController.dispose();
    _videoController?.dispose();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  // 获取当前实际文件索引
  int get _currentFileIndex => _currentIndex % widget.files.length;

  // 获取更新后的文件列表
  List<MaterialFile> _getUpdatedFiles() {
    return widget.files.map((file) {
      final updatedShowCount = _localShowCounts[file.id] ?? file.showCount;
      final updatedDownloadCount =
          _localDownloadCounts[file.id] ?? file.downloadCount;
      return file.copyWith(
        showCount: updatedShowCount,
        downloadCount: updatedDownloadCount,
      );
    }).toList();
  }

  // 初始化当前页面
  void _initCurrentPage() {
    final currentFile = widget.files[_currentFileIndex];
    if (currentFile.fileClassification == 'video' ||
        _isVideo(currentFile.url)) {
      _initPlayer(currentFile.url, isAudio: false);
    } else if (_isAudioFile(currentFile)) {
      // 音频复用 video_player（AVPlayer/ExoPlayer 支持音频流播放）
      _initPlayer(currentFile.url, isAudio: true);
    }
  }

  // 初始化视频/音频播放器
  Future<void> _initPlayer(String url, {required bool isAudio}) async {
    final label = isAudio ? '音频' : '视频';
    _videoController?.dispose();

    setState(() {
      _isVideoLoading = true;
      _showControls = true;
    });

    if (kDebugMode) print('[$label预览] 初始化 url=$url');

    // Uri.parse 不会对路径中的中文/特殊字符编码，需要手动处理
    final encodedUri = _encodeVideoUrl(url);
    if (kDebugMode) print('[$label预览] 编码后 uri=$encodedUri');

    _videoController = VideoPlayerController.networkUrl(encodedUri);

    try {
      await _videoController!.initialize();
      setState(() {
        _isVideoLoading = false;
      });
      _videoController!.play();
      _startHideControlsTimer();
      // 监听播放完成
      _videoController!.addListener(_videoListener);
    } catch (e) {
      if (kDebugMode) print('[$label预览] 加载失败 url=$url error=$e');
      setState(() {
        _isVideoLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isAudio ? '音频加载失败，可长按通过分享导出后播放' : '视频加载失败')));
      }
    }
  }

  /// 将含非 ASCII 字符（如中文目录名）的 URL 转换为合法 URI
  Uri _encodeVideoUrl(String url) {
    // Uri.encodeFull 只编码非法字符（中文等），保留 :// / ? # 等结构字符
    return Uri.parse(Uri.encodeFull(url));
  }

  // 视频状态监听
  void _videoListener() {
    if (_videoController != null && mounted) {
      setState(() {});
    }
  }

  // 开始隐藏控制栏计时器（音频没有画面，控制栏保持常显不自动隐藏）
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isCurrentFileAudio()) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _videoController != null &&
          _videoController!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  // 切换控制栏显示
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  // 切换播放/暂停
  void _togglePlayPause() {
    if (_videoController == null) return;

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
        _startHideControlsTimer();
      }
    });
  }

  // 判断当前文件是否是视频
  bool _isCurrentFileVideo() {
    final currentFile = widget.files[_currentFileIndex];
    return currentFile.fileClassification == 'video' ||
        currentFile.fileClassification == '2' ||
        _isVideo(currentFile.url);
  }

  // 判断是否是视频
  bool _isVideo(String url) {
    final videoExtensions = [
      'mp4',
      'avi',
      'mov',
      'mkv',
      'flv',
      'webm',
      'm4v',
      '3gp',
      '3g2',
      'wmv',
      'mpeg',
      'mpg',
    ];

    final cleanUrl = url.split('?')[0].trim();
    final lastDotIndex = cleanUrl.lastIndexOf('.');

    if (lastDotIndex == -1) return false;

    final ext = cleanUrl.substring(lastDotIndex + 1).toLowerCase();
    return videoExtensions.contains(ext);
  }

  // 判断当前文件是否是音频
  bool _isCurrentFileAudio() {
    return _isAudioFile(widget.files[_currentFileIndex]);
  }

  bool _isAudioFile(MaterialFile file) {
    return file.fileClassification == 'audio' || _isAudio(file.url);
  }

  // 判断是否是音频（按 URL 后缀）
  bool _isAudio(String url) {
    const audioExtensions = [
      'mp3',
      'wav',
      'aac',
      'flac',
      'ogg',
      'wma',
      'm4a',
      'aiff',
      'aif',
      'ape',
      'opus',
      'amr',
    ];

    final cleanUrl = url.split('?')[0].trim();
    final lastDotIndex = cleanUrl.lastIndexOf('.');

    if (lastDotIndex == -1) return false;

    final ext = cleanUrl.substring(lastDotIndex + 1).toLowerCase();
    return audioExtensions.contains(ext);
  }

  // 页面切换
  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // 停止之前的视频
    _videoController?.dispose();
    _videoController = null;

    // 初始化新页面
    _initCurrentPage();

    // 增加浏览次数（仅在启用时）
    if (widget.enableViewCount) {
      _increaseViewCount();
    }
  }

  // 增加浏览次数
  Future<void> _increaseViewCount() async {
    final currentFile = widget.files[_currentFileIndex];
    final success = await MaterialApi.increaseViewCount(currentFile.id);

    // 如果增加成功，更新本地显示的浏览量
    if (success && mounted) {
      setState(() {
        _localShowCounts[currentFile.id] =
            (_localShowCounts[currentFile.id] ?? currentFile.showCount) + 1;
      });
    }
  }

  // 增加下载次数（仅在启用浏览量统计时才调用接口）
  Future<void> _increaseDownloadCount() async {
    final currentFile = widget.files[_currentFileIndex];
    if (widget.enableViewCount) {
      await UserService().updateDownloadCount(currentFile.id);
    }
    if (mounted) {
      setState(() {
        _localDownloadCounts[currentFile.id] =
            (_localDownloadCounts[currentFile.id] ??
                currentFile.downloadCount) +
            1;
      });
    }
  }

  // 显示权限设置对话框
  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要相册权限'),
        content: const Text('保存图片和视频需要相册权限，请在设置中开启"添加照片"权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  // 长按菜单
  void _showSaveMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('保存到本地'),
                onTap: () {
                  Navigator.pop(context);
                  _saveToLocal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () {
                  Navigator.pop(context);
                  _shareMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
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

  // 保存到本地
  Future<void> _saveToLocal() async {
    // 使用 gal 包的权限检查和请求方法（比 permission_handler 更可靠）
    if (Platform.isIOS) {
      // 首先检查是否有访问权限
      final hasAccess = await Gal.hasAccess(toAlbum: true);

      if (!hasAccess) {
        // 请求权限
        final granted = await Gal.requestAccess(toAlbum: true);

        if (!granted) {
          // 权限被拒绝，显示对话框引导用户去设置
          if (mounted) {
            _showPermissionSettingsDialog();
          }
          return;
        }
      }
    }
    // Android: gal 包会自动处理权限请求

    final currentFile = widget.files[_currentFileIndex];

    // 音频无法保存到系统相册（gal 仅支持图片/视频），改走系统分享面板导出
    // （iOS 面板内可「存储到文件」，Android 可选文件管理等目标）
    if (_isAudioFile(currentFile)) {
      await _shareMedia();
      return;
    }

    final isVideo =
        currentFile.fileClassification == 'video' ||
        currentFile.fileClassification == '2' ||
        _isVideo(currentFile.url);

    // 只有视频才显示加载状态（视频下载时间较长）
    if (isVideo) {
      setState(() {
        _isSaving = true;
      });
    }

    // 显示开始下载提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isVideo ? '正在下载视频...' : '正在保存图片...'),
          duration: Duration(seconds: isVideo ? 2 : 1),
        ),
      );
    }

    try {
      final url = Uri.encodeFull(currentFile.url.split('?')[0]); // 编码中文路径，移除OSS参数

      // 下载文件到临时目录
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final fileName = currentFile.fileName.isNotEmpty
          ? currentFile.fileName
          : 'download_${DateTime.now().millisecondsSinceEpoch}${_getFileExtension(url)}';
      final filePath = '${tempDir.path}/$fileName';

      await dio.download(url, filePath);

      // 根据文件类型保存到相册
      if (isVideo) {
        await Gal.putVideo(filePath, album: '亚太HUB');
      } else {
        await Gal.putImage(filePath, album: '亚太HUB');
      }

      // 删除临时文件
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 增加下载次数
      await _increaseDownloadCount();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(isVideo ? '视频保存成功' : '图片保存成功')));
      }
    } on GalException catch (e) {
      // 捕获 Gal 包的特定异常
      String errorMessage;
      switch (e.type) {
        case GalExceptionType.accessDenied:
          errorMessage = '相册权限被拒绝，请在设置中开启';
          break;
        case GalExceptionType.notEnoughSpace:
          errorMessage = '存储空间不足';
          break;
        case GalExceptionType.notSupportedFormat:
          errorMessage = '不支持的文件格式';
          break;
        case GalExceptionType.unexpected:
          errorMessage = '保存失败: ${e.type.message}';
          break;
      }
      if (kDebugMode) {
        print('[保存文件] GalException: type=${e.type}, message=${e.type.message}');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      // 捕获其他异常（如网络错误等）
      if (kDebugMode) {
        print('[保存文件] 其他异常: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      // 只有视频才需要重置加载状态
      if (isVideo && mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // 获取文件扩展名
  String _getFileExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1) {
      return path.substring(lastDot);
    }
    return '.jpg'; // 默认扩展名
  }

  // 分享图片/视频/音频到其他应用
  Future<void> _shareMedia() async {
    final currentFile = widget.files[_currentFileIndex];
    final isVideo =
        currentFile.fileClassification == 'video' ||
        currentFile.fileClassification == '2' ||
        _isVideo(currentFile.url);
    final isAudio = _isAudioFile(currentFile);
    final label = isVideo
        ? '视频'
        : isAudio
            ? '音频'
            : '图片';

    // 显示加载状态（视频/音频需下载，耗时较长）
    if (isVideo || isAudio) {
      setState(() {
        _isSaving = true;
      });
    }

    // 显示开始准备提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在准备分享$label...'),
          duration: Duration(seconds: isVideo || isAudio ? 2 : 1),
        ),
      );
    }

    try {
      final url = Uri.encodeFull(currentFile.url.split('?')[0]); // 编码中文路径，移除OSS参数

      // 下载文件到临时目录
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final fileName = currentFile.fileName.isNotEmpty
          ? currentFile.fileName
          : 'share_${DateTime.now().millisecondsSinceEpoch}${_getFileExtension(url)}';
      final filePath = '${tempDir.path}/$fileName';

      await dio.download(url, filePath);

      // 使用 share_plus 分享文件
      final xFile = XFile(filePath);
      final params = ShareParams(files: [xFile], text: '分享');
      await SharePlus.instance.share(params);

      // 增加下载次数（分享也算一次下载）
      await _increaseDownloadCount();

      // 延迟删除临时文件，确保分享完成后再删除
      Future.delayed(const Duration(seconds: 5), () async {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('[分享文件] 异常: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    } finally {
      if ((isVideo || isAudio) && mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // 关闭页面
  void _closePage({bool fromDrag = false}) {
    if (fromDrag) {
      setState(() {
        _isClosingViaDrag = true;
      });
    }
    setState(() {
      _canPop = true;
    });
    // 确保在下一帧执行pop，让canPop生效
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pop(context, _getUpdatedFiles());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isClosingViaDrag) {
      return Container(color: Colors.transparent);
    }
    return PopScope(
      canPop: _canPop, // 由状态控制是否允许pop
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // 如果已经pop过了,不再处理
        if (didPop) {
          return;
        }

        // 拦截手动返回(如安卓返回键),调用统一的关闭方法
        _closePage();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent, // 状态栏背景透明
          statusBarIconBrightness: Brightness.light, // Android 状态栏图标白色
          statusBarBrightness: Brightness.dark, // iOS 状态栏文本白色
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 图片/视频内容 - 外层监听手指数量
              Listener(
                onPointerDown: (event) {
                  setState(() {
                    _currentPointerCount++;
                  });
                },
                onPointerUp: (event) {
                  setState(() {
                    _currentPointerCount--;
                    if (_currentPointerCount < 0) _currentPointerCount = 0;
                  });
                },
                onPointerCancel: (event) {
                  setState(() {
                    _currentPointerCount--;
                    if (_currentPointerCount < 0) _currentPointerCount = 0;
                  });
                },
                child: GestureDetector(
                  onLongPress: _showSaveMenu,
                  child: PageView.builder(
                    physics:
                        _isZoomed ||
                            _isInteractingWithImage ||
                            _currentPointerCount > 1
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    // itemCount: widget.files.length, // 移除itemCount以支持无限滚动
                    itemBuilder: (context, index) {
                      final fileIndex = index % widget.files.length;
                      final file = widget.files[fileIndex];
                      return _buildMediaItem(file, index);
                    },
                  ),
                ),
              ),

              // 顶部信息栏（拖拽时隐藏）
              if (!_isDraggingImage)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    child: Row(
                      children: [
                        // 关闭按钮 - 扩大触摸区域
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _closePage,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0), // 扩大触摸区域
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // 医院名称
                        if (widget.hospitalName.isNotEmpty)
                          Expanded(
                            child: Text(
                              widget.hospitalName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        const Spacer(),

                        // 当前页码
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202020),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_currentFileIndex + 1}/${widget.files.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 底部浏览量显示（视频播放且控制栏显示时隐藏，避免与进度条重叠；拖拽时也隐藏）
              // 仅在启用浏览量统计时显示
              if (widget.enableViewCount &&
                  !_isDraggingImage &&
                  (!(_isCurrentFileVideo() || _isCurrentFileAudio()) ||
                      !_showControls))
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202020),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                '浏览量：',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${_localShowCounts[widget.files[_currentFileIndex].id] ?? widget.files[_currentFileIndex].showCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 加载指示器（视频加载或保存文件时显示）
              if (_isVideoLoading || _isSaving)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建媒体项
  Widget _buildMediaItem(MaterialFile file, int index) {
    final isVideo =
        file.fileClassification == 'video' ||
        file.fileClassification == '2' ||
        _isVideo(file.url);

    if (isVideo && index == _currentIndex && _videoController != null) {
      // 视频预览：整个区域点击切换控制栏
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Container(
          color: Colors.black, // 确保视频背景为黑色，不受Scaffold透明影响
          child: Stack(
            children: [
              // 视频播放器层
              Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              ),

              // 视频控制栏（覆盖整个屏幕，但只在底部显示内容）
              if (_showControls) Positioned.fill(child: _buildVideoControls()),
            ],
          ),
        ),
      );
    }

    if (_isAudioFile(file)) {
      // 音频预览：无画面，居中展示音符图标 + 文件名，控制栏复用视频的
      final ready = index == _currentIndex && _videoController != null;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.audiotrack,
                        size: 48,
                        color: Color(0xFF709BF7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        file.originalName?.isNotEmpty == true
                            ? file.originalName!
                            : file.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (ready && _showControls)
                Positioned.fill(child: _buildVideoControls()),
            ],
          ),
        ),
      );
    }

    // 图片预览：使用 InteractiveViewer 占满全屏，支持双指缩放和单击关闭
    final originalUrl = file.url.split('?')[0];

    return _ImagePreviewWidget(
      imageUrl: originalUrl,
      onTap: _closePage,
      onDraggingChanged: (isDragging) {
        setState(() {
          _isDraggingImage = isDragging;
        });
      },
      onZoomChanged: (isZoomed) {
        setState(() {
          _isZoomed = isZoomed;
        });
      },
      onInteractionChanged: (isInteracting) {
        setState(() {
          _isInteractingWithImage = isInteracting;
        });
      },
      onDismiss: () => _closePage(fromDrag: true),
    );
  }

  // 构建视频控制栏
  Widget _buildVideoControls() {
    final controller = _videoController!;
    final position = controller.value.position;
    final duration = controller.value.duration;

    return Stack(
      children: [
        // 背景渐变
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ),

        // 播放/暂停按钮（绝对居中）- 视频加载时不显示
        if (!_isVideoLoading)
          Center(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),

        // 底部进度条和时间
        Positioned(
          left: 16,
          right: 16,
          bottom: 60,
          child: Row(
            children: [
              // 当前时间
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),

              // 进度条
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: position.inMilliseconds.toDouble().clamp(
                      0.0,
                      duration.inMilliseconds.toDouble(),
                    ),
                    min: 0.0,
                    max: duration.inMilliseconds.toDouble(),
                    activeColor: const Color(0xFF709BF7),
                    inactiveColor: Colors.white.withValues(alpha: 0.3),
                    onChanged: (value) {
                      controller.seekTo(Duration(milliseconds: value.toInt()));
                    },
                    onChangeEnd: (value) {
                      _startHideControlsTimer();
                    },
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 总时长
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 格式化时长
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

/// 图片预览组件 - 支持全屏缩放、单击关闭和垂直滑动关闭
class _ImagePreviewWidget extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onTap;
  final ValueChanged<bool> onDraggingChanged; // 拖拽状态变化回调
  final ValueChanged<bool> onZoomChanged; // 缩放状态变化回调
  final ValueChanged<bool> onInteractionChanged; // 交互状态变化回调（立即触发）
  final VoidCallback onDismiss; // 关闭回调

  const _ImagePreviewWidget({
    required this.imageUrl,
    required this.onTap,
    required this.onDraggingChanged,
    required this.onZoomChanged,
    required this.onInteractionChanged,
    required this.onDismiss,
  });

  @override
  State<_ImagePreviewWidget> createState() => _ImagePreviewWidgetState();
}

class _ImagePreviewWidgetState extends State<_ImagePreviewWidget>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  bool _isInteracting = false;
  DateTime? _tapDownTime;
  Offset? _tapDownPosition;

  // 垂直拖拽相关
  double _verticalDragOffset = 0.0; // 垂直拖拽偏移量
  bool _isDragging = false; // 是否正在拖拽
  late AnimationController _dismissAnimationController; // 关闭/回弹动画控制器
  late Animation<double> _dismissAnimation;

  // 手势优化相关
  int _pointerCount = 0; // 当前按下的手指数量
  Timer? _tapTimer; // 单击延时计时器
  double _initialScale = 1.0; // 记录双指缩放开始时的scale值

  // 双击缩放动画相关
  late AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化关闭/回弹动画控制器
    _dismissAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _dismissAnimation =
        Tween<double>(begin: 0, end: 0).animate(
          CurvedAnimation(
            parent: _dismissAnimationController,
            curve: Curves.easeOut,
          ),
        )..addListener(() {
          setState(() {
            _verticalDragOffset = _dismissAnimation.value;
          });
        });

    // 初始化双击缩放动画控制器
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // 监听缩放状态变化
    _transformationController.addListener(() {
      if (mounted) {
        final matrix = _transformationController.value;
        // 计算当前缩放比例（从matrix中提取scale）
        final scale = matrix.getMaxScaleOnAxis();
        final isScaled = scale > 1.01; // 考虑浮点误差，大于1.01才认为是缩放状态
        widget.onZoomChanged(isScaled);
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _dismissAnimationController.dispose();
    _zoomAnimationController.dispose();
    _tapTimer?.cancel();
    super.dispose();
  }

  // 双击缩放（带平滑动画）
  void _handleDoubleTap(Offset localPosition) {
    final Matrix4 startMatrix = _transformationController.value.clone();
    final Matrix4 endMatrix;

    if (_transformationController.value != Matrix4.identity()) {
      // 已经缩放，恢复原始大小
      endMatrix = Matrix4.identity();
    } else {
      // 放大到2倍，以点击位置为中心
      final double scale = 2.0;
      // 计算缩放后需要平移的距离，使点击位置保持在屏幕相同位置
      final double dx = localPosition.dx * (1 - scale);
      final double dy = localPosition.dy * (1 - scale);

      // 使用新的 Matrix4 API（非 deprecated）
      // 先创建缩放矩阵，再应用平移
      endMatrix = Matrix4.identity()
        ..setEntry(0, 0, scale) // x 轴缩放
        ..setEntry(1, 1, scale) // y 轴缩放
        ..setEntry(0, 3, dx) // x 轴平移
        ..setEntry(1, 3, dy); // y 轴平移
    }

    // 创建平滑的缩放动画
    _zoomAnimation =
        Matrix4Tween(begin: startMatrix, end: endMatrix).animate(
          CurvedAnimation(
            parent: _zoomAnimationController,
            curve: Curves.easeInOut,
          ),
        )..addListener(() {
          _transformationController.value = _zoomAnimation!.value;
        });

    // 执行动画
    _zoomAnimationController.forward(from: 0);
  }

  // 开始垂直拖拽
  void _onVerticalDragStart(DragStartDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    // 只有在图片未缩放时才允许垂直拖拽
    if (scale <= 1.01) {
      setState(() {
        _isDragging = true;
      });
      widget.onDraggingChanged(true);
    }
  }

  // 垂直拖拽更新
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // 只有在图片未缩放且已经开始拖拽时才允许垂直拖拽
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 1.01 && _isDragging) {
      setState(() {
        _verticalDragOffset += details.delta.dy;
      });
    }
  }

  // 垂直拖拽结束
  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;

    setState(() {
      _isDragging = false;
    });

    final screenHeight = MediaQuery.of(context).size.height;
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = screenHeight * 0.15; // 15%阈值

    // 判断是否应该关闭：1. 拖拽距离超过阈值 或 2. 快速滑动（速度>800）
    if (_verticalDragOffset.abs() > dismissThreshold || velocity.abs() > 800) {
      // 执行滑出动画
      final targetOffset = _verticalDragOffset > 0
          ? screenHeight
          : -screenHeight;
      _dismissAnimation =
          Tween<double>(begin: _verticalDragOffset, end: targetOffset).animate(
            CurvedAnimation(
              parent: _dismissAnimationController,
              curve: Curves.easeOut,
            ),
          );

      _dismissAnimationController.forward(from: 0).then((_) {
        widget.onDismiss();
      });
    } else {
      // 回弹到原位
      _dismissAnimation = Tween<double>(begin: _verticalDragOffset, end: 0.0)
          .animate(
            CurvedAnimation(
              parent: _dismissAnimationController,
              curve: Curves.easeOut,
            ),
          );
      _dismissAnimationController.forward(from: 0).then((_) {
        widget.onDraggingChanged(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dragProgress = (_verticalDragOffset.abs() / screenHeight).clamp(
      0.0,
      1.0,
    );
    final backgroundOpacity = 1.0 - dragProgress;
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isScaled = scale > 1.01;

    return Container(
      color: Colors.black.withValues(alpha: backgroundOpacity),
      child: Listener(
        // 最外层监听手指数量
        onPointerDown: (event) {
          setState(() => _pointerCount++);
        },
        onPointerUp: (event) {
          setState(() {
            _pointerCount--;
            if (_pointerCount < 0) _pointerCount = 0;
          });
        },
        onPointerCancel: (event) {
          setState(() {
            _pointerCount--;
            if (_pointerCount < 0) _pointerCount = 0;
          });
        },
        child: Transform.translate(
          offset: Offset(0, _verticalDragOffset),
          child: Stack(
            children: [
              // 底层：InteractiveViewer 处理缩放和平移
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: isScaled,
                  scaleEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  onInteractionStart: (details) {
                    _isInteracting = true;
                    _initialScale = _transformationController.value
                        .getMaxScaleOnAxis();
                    // 立即通知父组件禁用 PageView 滑动
                    widget.onInteractionChanged(true);
                  },
                  onInteractionEnd: (details) {
                    final currentScale = _transformationController.value
                        .getMaxScaleOnAxis();
                    if (_initialScale > 1.01 && currentScale <= 1.15) {
                      _transformationController.value = Matrix4.identity();
                    }
                    // 立即通知父组件可以恢复 PageView 滑动
                    widget.onInteractionChanged(false);
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) {
                        _isInteracting = false;
                      }
                    });
                  },
                  child: SizedBox.expand(
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        progressIndicatorBuilder: (context, url, progress) {
                          if (progress.progress != null &&
                              progress.progress! > 0.05) {
                            final percentage = (progress.progress! * 100)
                                .toInt();
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress.progress,
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '$percentage%',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          );
                        },
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.error,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 顶层：GestureDetector 处理单指手势（点击和拖拽）
              // 只在单指时参与手势竞争，双指时所有回调为null
              if (_pointerCount <= 1)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) {
                      _tapDownTime = DateTime.now();
                      _tapDownPosition = details.globalPosition;
                    },
                    onTapUp: (details) {
                      if (_tapDownTime != null &&
                          _tapDownPosition != null &&
                          !_isDragging &&
                          !_isInteracting) {
                        final duration = DateTime.now().difference(
                          _tapDownTime!,
                        );
                        final distance =
                            (details.globalPosition - _tapDownPosition!)
                                .distance;

                        if (duration.inMilliseconds < 500 && distance < 30) {
                          if (_tapTimer != null && _tapTimer!.isActive) {
                            _tapTimer!.cancel();
                            _handleDoubleTap(details.localPosition);
                          } else {
                            _tapTimer = Timer(
                              const Duration(milliseconds: 250),
                              () {
                                final currentScale = _transformationController
                                    .value
                                    .getMaxScaleOnAxis();
                                if (currentScale <= 1.01) {
                                  widget.onTap();
                                }
                              },
                            );
                          }
                        }
                      }
                      _tapDownTime = null;
                      _tapDownPosition = null;
                    },
                    onVerticalDragStart: !isScaled
                        ? _onVerticalDragStart
                        : null,
                    onVerticalDragUpdate: _isDragging && !isScaled
                        ? _onVerticalDragUpdate
                        : null,
                    onVerticalDragEnd: _isDragging ? _onVerticalDragEnd : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
