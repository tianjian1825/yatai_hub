import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yatai_hub/models/upload_history.dart';
import 'package:yatai_hub/utils/grid_utils.dart';
import 'package:yatai_hub/models/material_item.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/services/department_service.dart';
import 'package:yatai_hub/services/event_bus_service.dart';
import 'package:yatai_hub/services/route_settings_service.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';
import 'package:yatai_hub/services/list_cache_service.dart';
import 'package:yatai_hub/pages/material_preview_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

/// 我的作品Tab
class MyWorksTab extends StatefulWidget {
  /// 是否隐藏列表项右上角的收藏按钮（兼职角色下传 true）
  final bool hideCollect;

  const MyWorksTab({super.key, this.hideCollect = false});

  @override
  State<MyWorksTab> createState() => _MyWorksTabState();
}

class _MyWorksTabState extends State<MyWorksTab>
    with AutomaticKeepAliveClientMixin {
  final UserService _userService = UserService();
  final DepartmentService _departmentService = DepartmentService();
  final ListCacheService _cacheService = ListCacheService();
  final ScrollController _scrollController = ScrollController();
  final EventBusService _eventBus = EventBusService();

  final List<UploadHistoryDateGroup> _historyGroups = [];
  int _currentPage = 1;
  final int _pageSize = 10;
  bool _isLoading = false;
  bool _hasMore = true;

  StreamSubscription<void>? _materialUploadedSubscription;
  StreamSubscription<void>? _routeChangedSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistoryData();

    // 监听素材上传成功事件，自动刷新列表
    _materialUploadedSubscription = _eventBus.onMaterialUploaded.listen((_) {
      _loadHistoryData(refresh: true);
    });

    // 监听线路变更事件，刷新第一页数据
    _routeChangedSubscription = _eventBus.onRouteChanged.listen((_) {
      _loadHistoryData(refresh: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _materialUploadedSubscription?.cancel();
    _routeChangedSubscription?.cancel();
    super.dispose();
  }

  /// 滚动监听
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  /// 加载历史数据
  Future<void> _loadHistoryData({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _historyGroups.clear();
        _hasMore = true;
      }
    });

    // 列表为空时（首次加载或网络失败后），先从缓存读取并立即显示
    bool loadedFromCache = false;
    if (_currentPage == 1 && !refresh && _historyGroups.isEmpty) {
      try {
        final cachedData = await _cacheService.getCache('my_works_list');
        if (cachedData != null && cachedData is List) {
          final cachedGroups = cachedData
              .map((item) => UploadHistoryDateGroup.fromJson(item))
              .toList();

          if (mounted && cachedGroups.isNotEmpty) {
            setState(() {
              _historyGroups.clear();
              _historyGroups.addAll(cachedGroups);
              _isLoading = false; // 显示缓存数据，但继续后台加载
            });
            loadedFromCache = true;
          }
        }
      } catch (e) {
        debugPrint('[我的作品] 读取缓存失败: $e');
      }
    }

    try {
      // 获取浏览线路设置
      final RouteSettingsService routeSettings = RouteSettingsService();
      final browseRoute = await routeSettings.getBrowseRoute();

      final groups = await _userService.getUploadHistory(
        page: _currentPage,
        pageSize: _pageSize,
        isDomestic: browseRoute,
      );

      if (mounted) {
        setState(() {
          // 如果是第一页，直接替换（网络错误会进入 catch 块，不会执行到这里）
          if (_currentPage == 1 || refresh) {
            _historyGroups.clear();
            _historyGroups.addAll(groups);
          } else {
            // 加载更多时才合并同日期的数据
            if (_historyGroups.isNotEmpty && groups.isNotEmpty) {
              final lastGroup = _historyGroups.last;
              final firstNewGroup = groups.first;

              if (lastGroup.date == firstNewGroup.date) {
                // 合并同一天的数据
                lastGroup.items.addAll(firstNewGroup.items);
                _historyGroups.addAll(groups.skip(1));
              } else {
                _historyGroups.addAll(groups);
              }
            } else {
              _historyGroups.addAll(groups);
            }
          }

          // 计算本次返回的记录总数
          final newItemsCount = groups.fold<int>(
            0,
            (sum, group) => sum + group.items.length,
          );

          // 如果返回的数据少于 pageSize,说明没有更多数据了
          _hasMore = newItemsCount >= _pageSize;
          _isLoading = false;
        });

        // 只缓存第一页数据
        if (_currentPage == 1 && groups.isNotEmpty) {
          await _cacheService.saveCache(
            'my_works_list',
            groups.map((group) => group.toJson()).toList(),
          );
        }
      }
    } catch (e) {
      debugPrint('加载历史数据失败: $e');
      // API 失败时，如果已从缓存加载则保持，否则尝试使用缓存
      if (mounted && !loadedFromCache) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 加载更多
  Future<void> _loadMore() async {
    _currentPage++;
    await _loadHistoryData();
  }

  /// 刷新
  Future<void> _onRefresh() async {
    await _loadHistoryData(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 初始加载时显示加载动画
    if (_isLoading && _historyGroups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 分组内素材列表可能全为空（渲染时被过滤成空白），也视为无作品展示空态
    final hasWorks = _historyGroups
        .any((group) => group.items.any((item) => item.list.isNotEmpty));

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: !hasWorks
          ? _buildEmptyState()
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                left: 14,
                top: 14,
                right: 14,
                bottom: 80,
              ),
              itemCount: _historyGroups.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _historyGroups.length) {
                  return _buildLoadingIndicator();
                }
                return _buildHistoryGroup(_historyGroups[index]);
              },
            ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    // 包装在ListView中以支持下拉刷新
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const EmptyStateWidget(
            icon: Icons.inbox_outlined,
            message: '还没有上传作品',
          ),
        ),
      ],
    );
  }

  /// 构建加载指示器
  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '没有更多了',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
    );
  }

  /// 构建历史分组
  Widget _buildHistoryGroup(UploadHistoryDateGroup group) {
    // 过滤掉没有材料的记录
    final validItems = group.items
        .where((item) => item.list.isNotEmpty)
        .toList();

    if (validItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期标题
          Row(
            children: [
              Image.asset(
                'assets/images/my_center_date.png',
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 4),
              Text(
                group.date,
                style: const TextStyle(fontSize: 14, color: Color(0xFF757575)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 记录列表
          ...validItems.map((record) => _buildHistoryRecord(record, group)),
        ],
      ),
    );
  }

  /// 构建单个历史记录
  Widget _buildHistoryRecord(
    UploadHistoryRecord record,
    UploadHistoryDateGroup group,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 描述文本
          if (record.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableText(
                record.text,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              ),
            ),
          // 活动时间（仅价格表）
          if (record.materialCategory == 9 &&
              record.activityStartTime != null &&
              record.activityEndTime != null)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '活动时间：${_formatTimestamp(record.activityStartTime!)} - ${record.isLongTerm == 1 ? "长期" : _formatTimestamp(record.activityEndTime!)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
            ),
          // 材料网格
          _buildMaterialGrid(record.list),
          const SizedBox(height: 4),
          // 可见范围（单独一行）
          if (record.visableDepartment != null &&
              record.visableDepartment!.isNotEmpty)
            FutureBuilder<String>(
              future: _getVisibilityText(record),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      snapshot.data!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          // 医院信息和操作按钮（同一行）
          _buildRecordFooter(record, group),
        ],
      ),
    );
  }

  /// 构建材料网格
  Widget _buildMaterialGrid(List<UploadHistoryMaterialItem> materials) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 10),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: responsiveMaterialGridDelegate(
        crossAxisSpacing: 6,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: materials.length,
      itemBuilder: (context, index) {
        return _buildMaterialItem(materials[index]);
      },
    );
  }

  /// 构建单个材料项
  Widget _buildMaterialItem(UploadHistoryMaterialItem material) {
    final bool isVideo = _isVideo(material.url);
    final bool isAudio =
        material.fileClassification == 'audio' || _isAudio(material.url);
    final bool isDocument =
        material.fileClassification == 'document' && !isAudio;

    // 优先使用接口返回的thumbnail字段，如果不存在或为空则使用url拼接参数
    String? videoThumbnailUrl;
    String? imageThumbnailUrl;
    if (material.thumbnail != null && material.thumbnail!.isNotEmpty) {
      videoThumbnailUrl = material.thumbnail!;
      imageThumbnailUrl = material.thumbnail!;
    } else {
      videoThumbnailUrl =
          '${material.url}?x-oss-process=video/snapshot,t_1000,ar_auto,f_jpg,h_200';
      imageThumbnailUrl = '${material.url}?x-oss-process=image/resize,w_120';
    }

    return GestureDetector(
      onTap: () => _openPreview(material),
      child: Stack(
        children: [
          // 图片/视频/音频/文档
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: isAudio
                  ? _buildAudioPreview(material)
                  : isDocument
                  ? _buildDocumentPreview(material)
                  : (isVideo
                        ? CachedNetworkImage(
                            imageUrl: videoThumbnailUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            memCacheWidth: 300,
                            memCacheHeight: 300,
                            maxWidthDiskCache: 300,
                            maxHeightDiskCache: 300,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return const Icon(Icons.videocam, size: 40);
                            },
                          )
                        : CachedNetworkImage(
                            imageUrl: imageThumbnailUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            memCacheWidth: 300,
                            memCacheHeight: 300,
                            maxWidthDiskCache: 300,
                            maxHeightDiskCache: 300,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return const Icon(Icons.image, size: 40);
                            },
                          )),
            ),
          ),
          // 视频播放按钮
          if (isVideo)
            const Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 40,
              ),
            ),
          // 下载次数（仅图片和视频）
          if (!isDocument && !isAudio)
            Positioned(
              right: 6,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/downCount.png',
                      width: 11,
                      height: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${material.downloadCount}次',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          // 收藏图标（兼职角色下隐藏）
          if (!widget.hideCollect)
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: () => _toggleCollect(material),
                child: Image.asset(
                  material.isCollected
                      ? 'assets/images/m_yes_collect.png'
                      : 'assets/images/m_no_collect.png',
                  width: 22,
                  height: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建文档预览
  Widget _buildDocumentPreview(UploadHistoryMaterialItem material) {
    final extension = material.url
        .split('.')
        .last
        .toLowerCase()
        .split('?')
        .first
        .toUpperCase();
    String iconPath;
    LinearGradient gradient;

    switch (extension) {
      case 'PDF':
        iconPath = 'assets/images/pdf_icon.png';
        gradient = const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFDFD), Color(0xFFFFE5E5)],
        );
        break;
      case 'DOC':
      case 'DOCX':
        iconPath = 'assets/images/word_icon.png';
        gradient = const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFDFEFF), Color(0xFFE5EFFF)],
        );
        break;
      case 'XLS':
      case 'XLSX':
        iconPath = 'assets/images/excel_icon.png';
        gradient = const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFE5FFFC)],
        );
        break;
      case 'PPT':
      case 'PPTX':
        iconPath = 'assets/images/ppt_icon.png';
        gradient = const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFE9E7FF)],
        );
        break;
      default:
        iconPath = 'assets/images/emptyFile.png';
        gradient = const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFDFEFF), Color(0xFFE5EFFF)],
        );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            iconPath,
            width: 30,
            height: 30,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.insert_drive_file,
                size: 30,
                color: Colors.grey,
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            material.fileName ?? '',
            style: const TextStyle(fontSize: 10, color: Color(0xFF333333)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 构建音频预览
  Widget _buildAudioPreview(UploadHistoryMaterialItem material) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(0.309, -0.951),
          end: Alignment(-0.309, 0.951),
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFDFF), Color(0xFFF3E5F5)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.audiotrack, size: 30, color: Color(0xFF9C27B0)),
          const SizedBox(height: 6),
          Text(
            material.fileName ?? '',
            style: const TextStyle(fontSize: 10, color: Color(0xFF333333)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 切换收藏状态
  Future<void> _toggleCollect(UploadHistoryMaterialItem material) async {
    final success = await _userService.toggleCollect(material.id);

    if (success && mounted) {
      setState(() {
        material.isCollected = !material.isCollected;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(material.isCollected ? '收藏成功' : '已取消收藏')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  /// 判断素材是否为音频（按 classification 或 URL 后缀）
  bool _isAudioMaterial(UploadHistoryMaterialItem material) {
    return material.fileClassification == 'audio' || _isAudio(material.url);
  }

  /// 打开预览页面
  Future<void> _openPreview(UploadHistoryMaterialItem material) async {
    // 文档通过外部应用打开；音频改为应用内预览播放
    if (material.fileClassification == 'document' &&
        !_isAudioMaterial(material)) {
      await _openFileExternal(material);
      return;
    }

    // 找到当前素材所属的记录组
    UploadHistoryRecord? targetRecord;
    for (var group in _historyGroups) {
      for (var record in group.items) {
        if (record.list.any((item) => item.id == material.id)) {
          targetRecord = record;
          break;
        }
      }
      if (targetRecord != null) break;
    }

    // 如果没有找到记录组，则返回
    if (targetRecord == null) return;

    // 只收集当前记录中的所有媒体文件（图片、视频和音频）
    final allMaterials = targetRecord.list
        .where(
          (item) =>
              item.fileClassification == 'image' ||
              item.fileClassification == 'video' ||
              _isAudioMaterial(item),
        )
        .toList();

    // 找到当前素材在列表中的索引
    final currentIndex = allMaterials.indexWhere(
      (item) => item.id == material.id,
    );

    // 转换为MaterialFile列表
    final files = allMaterials.map((item) {
      return MaterialFile.fromJson(item.toMaterialFile());
    }).toList();

    if (!mounted) return;

    // 打开预览页面 - 使用自定义放大动画
    final result = await Navigator.push(
      context,
      _createZoomRoute(
        MaterialPreviewPage(
          files: files,
          initialIndex: currentIndex >= 0 ? currentIndex : 0,
          hospitalName: '',
        ),
      ),
    );

    // 如果预览页面返回了更新的文件列表，同步收藏状态
    if (result != null && result is List<MaterialFile> && mounted) {
      setState(() {
        for (var updatedFile in result) {
          // 在所有记录组中查找并更新
          for (var group in _historyGroups) {
            for (var record in group.items) {
              final itemIndex = record.list.indexWhere(
                (item) => item.id == updatedFile.id,
              );
              if (itemIndex >= 0) {
                record.list[itemIndex].isCollected = updatedFile.isCollected;
              }
            }
          }
        }
      });
    }
  }

  /// 通过外部应用打开文件
  Future<void> _openFileExternal(UploadHistoryMaterialItem material) async {
    try {
      final uri = Uri.parse(material.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开该文件')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开文件失败: $e')));
      }
    }
  }

  /// 构建记录底部（医院信息和操作按钮）
  Widget _buildRecordFooter(
    UploadHistoryRecord record,
    UploadHistoryDateGroup group,
  ) {
    return Row(
      children: [
        // 医院信息
        if (record.hospitalName != null && record.hospitalName!.isNotEmpty)
          Expanded(
            child: Row(
              children: [
                Image.asset(
                  'assets/images/icon-search.png',
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    record.hospitalName!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else
          const Spacer(),
        // 删除按钮
        InkWell(
          onTap: () => _showDeleteConfirmDialog(record, group),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE1E9FE),
              border: Border.all(color: const Color(0xFF4C88F6), width: 0.5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/delete-icon.png',
                  width: 12,
                  height: 14,
                ),
                const SizedBox(width: 2),
                const Text(
                  '删除',
                  style: TextStyle(fontSize: 14, color: Color(0xFF4C88F6)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 编辑按钮
        InkWell(
          onTap: () => _navigateToEdit(record),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEEFDF6),
              border: Border.all(color: const Color(0xFF3FB87E), width: 0.5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.edit, size: 14, color: Color(0xFF3FB87E)),
                SizedBox(width: 2),
                Text(
                  '编辑',
                  style: TextStyle(fontSize: 14, color: Color(0xFF3FB87E)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 获取可见范围文本（异步）
  Future<String> _getVisibilityText(UploadHistoryRecord record) async {
    // 部门内可见，需要显示具体的部门名称
    if (record.visableDepartment != null &&
        record.visableDepartment!.isNotEmpty) {
      final deptNames = await _departmentService.getDepartmentNames(
        record.visableDepartment,
      );
      if (deptNames.isNotEmpty) {
        return '仅${deptNames.join('、')}可见';
      }
    }
    return '';
  }

  /// 显示删除确认对话框
  Future<void> _showDeleteConfirmDialog(
    UploadHistoryRecord record,
    UploadHistoryDateGroup group,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('是否永久删除该记录及对应的素材？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteRecord(record, group);
    }
  }

  /// 删除记录
  Future<void> _deleteRecord(
    UploadHistoryRecord record,
    UploadHistoryDateGroup group,
  ) async {
    final success = await _userService.deleteUploadRecord(record.id);
    if (success && mounted) {
      setState(() {
        group.items.remove(record);
        if (group.items.isEmpty) {
          _historyGroups.remove(group);
        }
      });

      // 删除成功后更新缓存（只在第一页时更新）
      if (_currentPage == 1) {
        await _cacheService.saveCache(
          'my_works_list',
          _historyGroups.map((group) => group.toJson()).toList(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除成功')));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  /// 判断是否为视频
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
      'wmv',
      'mpeg',
      'mpg',
    ];
    final extension = url.split('.').last.toLowerCase().split('?').first;
    return videoExtensions.contains(extension);
  }

  /// 判断是否为音频
  bool _isAudio(String url) {
    final audioExtensions = [
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
    final extension = url.split('.').last.toLowerCase().split('?').first;
    return audioExtensions.contains(extension);
  }

  /// 跳转到编辑页面
  Future<void> _navigateToEdit(UploadHistoryRecord record) async {
    if (!mounted) return;

    // 跳转到材料上传页面并传递记录ID
    final result = await Navigator.pushNamed(
      context,
      '/material-upload',
      arguments: {'editId': record.id},
    );

    // 只有提交成功后才刷新列表并更新缓存
    if (mounted && result == true) {
      await _loadHistoryData(refresh: true);

      // 编辑成功后更新缓存（只在第一页时更新）
      if (_currentPage == 1 && _historyGroups.isNotEmpty) {
        await _cacheService.saveCache(
          'my_works_list',
          _historyGroups.map((group) => group.toJson()).toList(),
        );
      }
    }
  }

  /// 格式化时间戳
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy.MM.dd').format(date);
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
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
    );
  }
}
