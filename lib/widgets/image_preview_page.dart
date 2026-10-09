import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yatai_hub/utils/media_saver.dart';
import 'package:video_player/video_player.dart';

/// 通用网络图片预览组件。
///
/// 交互与打开动画对齐项目内 MaterialPreviewPage / 护照预览：
/// 双指缩放、双击放大/复位、垂直拖拽关闭（带透明度渐变），
/// **图片单击关闭预览**（缩放态下单击不关，先双击复位）、视频单击切换控制栏，
/// 打开使用缩放+淡入路由（[createImagePreviewRoute]）。
///
/// 通过 [showImagePreview] 打开，确保所有图片预览的打开动画一致。
Future<void> showImagePreview(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  String title = '图片预览',
  bool enableSaveShare = true,
}) {
  return Navigator.of(context).push(
    createImagePreviewRoute(
      ImagePreviewPage(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        title: title,
        enableSaveShare: enableSaveShare,
      ),
    ),
  );
}

/// 缩放+淡入打开路由，与项目内其它图片预览的打开动画保持一致。
Route<T> createImagePreviewRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const curve = Curves.fastOutSlowIn;
      final scaleTween =
          Tween(begin: 0.85, end: 1.0).chain(CurveTween(curve: curve));
      final fadeTween =
          Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
      return FadeTransition(
        opacity: animation.drive(fadeTween),
        child: ScaleTransition(
          scale: animation.drive(scaleTween),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
  );
}

class ImagePreviewPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String title;

  /// 长按是否弹出「保存到相册 / 分享」菜单
  final bool enableSaveShare;

  const ImagePreviewPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.title = '图片预览',
    this.enableSaveShare = true,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late PageController _pageController;
  late int _currentPage;
  bool _isZoomed = false;
  bool _isInteracting = false;
  bool _isDraggingImage = false;
  bool _isClosingViaDrag = false;
  int _currentPointerCount = 0;
  bool _showControls = true;

  // 视频播放（仅当前页为视频时持有）
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;
  Timer? _hideControlsTimer;

  /// 顶栏 / 页码 / 指示器是否可见：视频页跟随控制栏开关，图片页常显
  /// （图片单击是关闭预览而非切换控件，若跟随 `_showControls` 将无法再显示回来）
  bool get _controlsVisible => _isVideoAt(_currentPage) ? _showControls : true;

  bool _isVideoAt(int index) =>
      index >= 0 &&
      index < widget.imageUrls.length &&
      MediaSaver.isVideo(widget.imageUrls[index]);

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex.clamp(
      0,
      widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1,
    );
    _pageController = PageController(initialPage: _currentPage);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    if (_isVideoAt(_currentPage)) {
      _initVideo(widget.imageUrls[_currentPage]);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _videoController?.dispose();
    _pageController.dispose();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
  }

  Future<void> _initVideo(String url) async {
    _videoController?.dispose();
    setState(() {
      _isVideoLoading = true;
      _showControls = true;
    });
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(Uri.encodeFull(url)));
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _isVideoLoading = false);
      controller.play();
      controller.addListener(_videoListener);
      _startHideControlsTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVideoLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('视频加载失败')));
    }
  }

  void _videoListener() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int index) {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
    setState(() => _currentPage = index);
    if (_isVideoAt(index)) {
      _initVideo(widget.imageUrls[index]);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _togglePlayPause() {
    final c = _videoController;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
        _startHideControlsTimer();
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _videoController != null &&
          _videoController!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$m:$s';
  }

  void _closePage({bool fromDrag = false}) {
    if (fromDrag) {
      setState(() => _isClosingViaDrag = true);
    }
    Navigator.pop(context);
  }

  Widget _buildVideoItem(String url, int index) {
    final isCurrent = index == _currentPage;
    final c = _videoController;
    final ready = isCurrent && c != null && c.value.isInitialized;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? _toggleControls : null,
      onLongPress: widget.enableSaveShare
          ? () => MediaSaver.showActionSheet(context, url)
          : null,
      child: Container(
        color: Colors.black,
        child: ready
            ? Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                  if (_showControls)
                    Positioned.fill(child: _buildVideoControls(c)),
                ],
              )
            : Center(
                child: _isVideoLoading && isCurrent
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.play_circle_outline,
                        color: Colors.white70, size: 64),
              ),
      ),
    );
  }

  Widget _buildVideoControls(VideoPlayerController c) {
    final position = c.value.position;
    final duration = c.value.duration;
    final maxMs = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),
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
                c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 28,
          child: Row(
            children: [
              Text(_formatDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, maxMs),
                    max: maxMs,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white38,
                    onChanged: (v) =>
                        c.seekTo(Duration(milliseconds: v.toInt())),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_formatDuration(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isClosingViaDrag) {
      return Container(color: Colors.transparent);
    }

    if (widget.imageUrls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        ),
        body: const Center(
          child: Text('暂无图片',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => setState(() => _currentPointerCount++),
            onPointerUp: (_) => setState(() {
              _currentPointerCount--;
              if (_currentPointerCount < 0) _currentPointerCount = 0;
            }),
            onPointerCancel: (_) => setState(() {
              _currentPointerCount--;
              if (_currentPointerCount < 0) _currentPointerCount = 0;
            }),
            child: PageView.builder(
              physics: _isZoomed || _isInteracting || _currentPointerCount > 1
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final url = widget.imageUrls[index];
                if (MediaSaver.isVideo(url)) {
                  return _buildVideoItem(url, index);
                }
                return _ImageZoomView(
                  imageUrl: url,
                  // 单击关闭预览，与随心拍 MaterialPreviewPage 一致
                  onTap: _closePage,
                  onLongPress: widget.enableSaveShare
                      ? () => MediaSaver.showActionSheet(context, url)
                      : null,
                  onDraggingChanged: (v) =>
                      setState(() => _isDraggingImage = v),
                  onZoomChanged: (v) => setState(() => _isZoomed = v),
                  onInteractionChanged: (v) =>
                      setState(() => _isInteracting = v),
                  onDismiss: () => _closePage(fromDrag: true),
                );
              },
            ),
          ),
          if (_controlsVisible && !_isDraggingImage)
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _closePage,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                    // 仅多张时显示页码（如 1/2），不显示标题文字，更简洁
                    if (widget.imageUrls.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentPage + 1}/${widget.imageUrls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_controlsVisible &&
              !_isDraggingImage &&
              widget.imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.imageUrls.length,
                    (i) => Container(
                      width: _currentPage == i ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? Colors.white
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 单张图片视图 — 支持双指缩放、双击放大/复位、垂直拖拽关闭、单击关闭
class _ImageZoomView extends StatefulWidget {
  final String imageUrl;

  /// 单击（未缩放时）回调，用于关闭预览
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool> onDraggingChanged;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onInteractionChanged;
  final VoidCallback onDismiss;

  const _ImageZoomView({
    required this.imageUrl,
    required this.onTap,
    this.onLongPress,
    required this.onDraggingChanged,
    required this.onZoomChanged,
    required this.onInteractionChanged,
    required this.onDismiss,
  });

  @override
  State<_ImageZoomView> createState() => _ImageZoomViewState();
}

class _ImageZoomViewState extends State<_ImageZoomView>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  bool _isInteracting = false;
  DateTime? _tapDownTime;
  Offset? _tapDownPosition;

  double _verticalDragOffset = 0.0;
  bool _isDragging = false;
  late AnimationController _dismissAnimationController;
  late Animation<double> _dismissAnimation;

  int _pointerCount = 0;
  Timer? _tapTimer;
  double _initialScale = 1.0;

  late AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();

    _dismissAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _dismissAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _dismissAnimationController,
        curve: Curves.easeOut,
      ),
    )..addListener(() {
        setState(() {
          _verticalDragOffset = _dismissAnimation.value;
        });
      });

    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _transformationController.addListener(() {
      if (mounted) {
        final scale = _transformationController.value.getMaxScaleOnAxis();
        widget.onZoomChanged(scale > 1.01);
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

  void _handleDoubleTap(Offset localPosition) {
    final Matrix4 startMatrix = _transformationController.value.clone();
    final Matrix4 endMatrix;

    if (_transformationController.value != Matrix4.identity()) {
      endMatrix = Matrix4.identity();
    } else {
      const double scale = 2.0;
      final double dx = localPosition.dx * (1 - scale);
      final double dy = localPosition.dy * (1 - scale);
      endMatrix = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, dx)
        ..setEntry(1, 3, dy);
    }

    _zoomAnimation = Matrix4Tween(begin: startMatrix, end: endMatrix).animate(
      CurvedAnimation(
        parent: _zoomAnimationController,
        curve: Curves.easeInOut,
      ),
    )..addListener(() {
        _transformationController.value = _zoomAnimation!.value;
      });

    _zoomAnimationController.forward(from: 0);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 1.01) {
      setState(() => _isDragging = true);
      widget.onDraggingChanged(true);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 1.01 && _isDragging) {
      setState(() {
        _verticalDragOffset += details.delta.dy;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);

    final screenHeight = MediaQuery.of(context).size.height;
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = screenHeight * 0.15;

    if (_verticalDragOffset.abs() > dismissThreshold || velocity.abs() > 800) {
      final targetOffset =
          _verticalDragOffset > 0 ? screenHeight : -screenHeight;
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
      _dismissAnimation =
          Tween<double>(begin: _verticalDragOffset, end: 0.0).animate(
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
    final dragProgress =
        (_verticalDragOffset.abs() / screenHeight).clamp(0.0, 1.0);
    final backgroundOpacity = 1.0 - dragProgress;
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isScaled = scale > 1.01;

    return Container(
      color: Colors.black.withValues(alpha: backgroundOpacity),
      child: Listener(
        onPointerDown: (_) => setState(() => _pointerCount++),
        onPointerUp: (_) => setState(() {
          _pointerCount--;
          if (_pointerCount < 0) _pointerCount = 0;
        }),
        onPointerCancel: (_) => setState(() {
          _pointerCount--;
          if (_pointerCount < 0) _pointerCount = 0;
        }),
        child: Transform.translate(
          offset: Offset(0, _verticalDragOffset),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: isScaled,
                  scaleEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  onInteractionStart: (details) {
                    _isInteracting = true;
                    _initialScale =
                        _transformationController.value.getMaxScaleOnAxis();
                    widget.onInteractionChanged(true);
                  },
                  onInteractionEnd: (details) {
                    final currentScale =
                        _transformationController.value.getMaxScaleOnAxis();
                    if (_initialScale > 1.01 && currentScale <= 1.15) {
                      _transformationController.value = Matrix4.identity();
                    }
                    widget.onInteractionChanged(false);
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) _isInteracting = false;
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
                            final percentage =
                                (progress.progress! * 100).toInt();
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
                                  Text('$percentage%',
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white)),
                                ],
                              ),
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                          );
                        },
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[800],
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  color: Colors.white54, size: 64),
                              SizedBox(height: 12),
                              Text('图片加载失败',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_pointerCount <= 1)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPress: widget.onLongPress,
                    onTapDown: (details) {
                      _tapDownTime = DateTime.now();
                      _tapDownPosition = details.globalPosition;
                    },
                    onTapUp: (details) {
                      if (_tapDownTime != null &&
                          _tapDownPosition != null &&
                          !_isDragging &&
                          !_isInteracting) {
                        final duration =
                            DateTime.now().difference(_tapDownTime!);
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
                                // 缩放态下单击不触发关闭（避免看大图时误关）
                                final currentScale = _transformationController
                                    .value
                                    .getMaxScaleOnAxis();
                                if (currentScale <= 1.01) widget.onTap();
                              },
                            );
                          }
                        }
                      }
                      _tapDownTime = null;
                      _tapDownPosition = null;
                    },
                    onVerticalDragStart:
                        !isScaled ? _onVerticalDragStart : null,
                    onVerticalDragUpdate:
                        _isDragging && !isScaled ? _onVerticalDragUpdate : null,
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
