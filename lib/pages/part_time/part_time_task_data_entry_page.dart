import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yatai_hub/models/order_entry_meta.dart';
import 'package:yatai_hub/models/part_time_task.dart';
import 'package:yatai_hub/models/upload_file.dart';
import 'package:yatai_hub/services/material_api.dart';
import 'package:yatai_hub/services/nas_chunked_upload_service.dart';
import 'package:yatai_hub/services/nas_upload_service.dart';
import 'package:yatai_hub/services/order_entry_meta_service.dart';
import 'package:yatai_hub/services/oss_api.dart';
import 'package:yatai_hub/services/part_time_task_service.dart';
import 'package:yatai_hub/utils/media_cache_cleaner.dart';
import 'package:yatai_hub/widgets/image_preview_page.dart';
import 'package:yatai_hub/widgets/passport_capture_guide.dart';

/// 录入兼职任务数据页
///
/// 在任务「已接单」阶段进入，用于完成任务前录入：
/// 1. 一个或多个客人的护照识别 + 精简录单草稿（韩国录单，币种固定韩币）
/// 2. 整个任务共享的一份随心拍素材（图片/视频）+ 描述
///
/// 提交时先调随心拍保存接口（绑定 parttime_task_id），再逐个客人提交录单草稿。
class PartTimeTaskDataEntryPage extends StatefulWidget {
  final PartTimeTaskDetail detail;

  /// 只读查看模式（任务已完成后进入），禁用所有编辑与提交
  final bool readOnly;

  const PartTimeTaskDataEntryPage({
    super.key,
    required this.detail,
    this.readOnly = false,
  });

  @override
  State<PartTimeTaskDataEntryPage> createState() =>
      _PartTimeTaskDataEntryPageState();
}

class _PartTimeTaskDataEntryPageState extends State<PartTimeTaskDataEntryPage> {
  static const Color _primary = Color(0xFF1F6FF4);
  static const Color _danger = Color(0xFFFF4D4F);
  static const int _maxFileCount = 50;
  /// 提交任务资料时随心拍素材的最少数量。
  /// 单任务只要求 ≥1 张；「一天累计 ≥10 张」由后端在「完成任务」时校验，
  /// 不足则后端返回提示，前端直接展示（见 _onCompleteTask）。
  static const int _minFileCount = 1;

  /// 本页独立的 NAS 上传服务（不走全局上传队列，无通知/持久化/恢复）
  final NasChunkedUploadService _nasService = NasChunkedUploadService();

  OrderEntryMeta? _meta;
  bool _loadingMeta = true;
  bool _submitting = false;

  final List<_ClientEntry> _clients = [];

  /// 本页内已物理删除过录单草稿：即使不保存直接返回，详情页也需刷新
  bool _draftDeleted = false;

  /// 当前任务主客户 ID（客人一），新增客人通过 main_client_id 回退到它
  int _mainClientId = 0;

  // ── 随心拍素材（整个任务共享一份）──
  /// 已上传并绑定的历史文件（回显，可删除；编辑提交时回传保留项）
  final List<PartTimeMaterialFile> _existingFiles = [];
  final List<_MediaUpload> _media = [];
  final TextEditingController _descController = TextEditingController();
  bool _descManuallyEdited = false;

  bool get _readOnly => widget.readOnly;

  /// 不关联日程的兼职任务（schedule_id 为 0）：无需填写客人 / 录单信息，
  /// 仅需提交随心拍素材记录。
  bool get _noScheduleTask => _detail.scheduleId <= 0;

  /// 当前绑定的随心拍主表 ID（>0 表示编辑已有素材）
  int get _casuallyId =>
      _detail.casuallyId > 0
          ? _detail.casuallyId
          : (_detail.materialDetail?.casuallyId ?? 0);

  // ── 表单校验错误状态 ──
  /// 素材区/描述的校验错误文案（null 表示无错误）
  String? _mediaError;
  String? _descError;
  /// 素材区/描述的滚动定位 Key
  final GlobalKey _mediaKey = GlobalKey();
  final GlobalKey _descKey = GlobalKey();

  PartTimeTaskDetail get _detail => widget.detail;

  @override
  void initState() {
    super.initState();
    _mainClientId = _detail.schedule?.clientId ?? 0;
    if (_mainClientId <= 0) {
      _mainClientId = _detail.appoint?.clientId ?? 0;
    }
    _initClients();
    _initMaterialDesc();
    _loadMeta();
  }

  @override
  void dispose() {
    // 取消本页正在进行的上传，避免离开页面后后台继续传
    for (final m in _media) {
      if (m.status == _MediaStatus.uploading) {
        m.cancelToken?.cancel('页面关闭');
      }
    }
    _descController.dispose();
    for (final c in _clients) {
      c.dispose();
    }
    // 释放图片缓存，降低内存占用
    _clearImageCache();
    // 离开页面时清理本页已选媒体的 image_picker 临时副本
    // （在此清理而非上传完成时，避免影响上传/编辑期间的本地缩略图预览）
    // ignore: discarded_futures
    MediaCacheCleaner.cleanPickedFiles(
      _media.map((m) => m.file.localPath).toList(),
    );
    super.dispose();
  }

  void _clearImageCache() {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (_) {}
  }

  // ───────────────────── 初始化 ─────────────────────

  void _initClients() {
    // 不关联日程的任务无需客人 / 录单信息，保持客人列表为空
    if (_noScheduleTask) return;
    final appoint = _detail.appoint;
    // 回显已有草稿：只读查看展示全部草稿；编辑态仅展示未写入正式录单的，避免重复创建
    final drafts = _detail.orderDrafts
        .where((d) => d.draftId > 0 && (_readOnly || !d.isWritten))
        .toList();

    if (drafts.isNotEmpty) {
      for (final d in drafts) {
        final entry = _ClientEntry.fromDraft(d);
        // 按 guest_id 关联档案成员，用于选择器回显与去重
        for (final m in _members) {
          if (m.guestId > 0 && m.guestId == entry.guestId) {
            entry.member = m;
            break;
          }
        }
        _clients.add(entry);
      }
      return;
    }

    final primary = _ClientEntry(clientId: _mainClientId);
    if (_members.isNotEmpty) {
      // 客人一默认选中「本人」（is_main=1），用户可点击切换
      primary.applyMember(
        _members.firstWhere((m) => m.isMain, orElse: () => _members.first),
      );
    } else if (appoint != null) {
      // 无档案成员时回退旧逻辑：以预约信息预填
      primary.nameController.text = appoint.clientName;
      primary.passportController.text = appoint.passportNumber;
      primary.birthTime = _tryParseDate(appoint.birthTime);
    } else if ((_detail.schedule?.name ?? '').isNotEmpty) {
      primary.nameController.text = _detail.schedule!.name;
    }
    if (appoint != null) primary.pendingProjectId = appoint.projectId;
    _clients.add(primary);
  }

  void _initMaterialDesc() {
    final md = _detail.materialDetail;
    if (md != null && md.hasMaterial) {
      if (md.text.isNotEmpty) {
        _descController.text = md.text;
        _descManuallyEdited = true; // 已有素材描述，不自动覆盖
      }
      // 回显已上传的素材文件
      _existingFiles.addAll(md.files);
    }
  }

  Future<void> _loadMeta() async {
    final meta = await OrderEntryMetaService().getMeta();
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _loadingMeta = false;
    });
    if (meta != null) {
      // 元数据就绪后，应用预约带入的项目预选
      var changed = false;
      for (final c in _clients) {
        if (c.pendingProjectId != null && c.pendingProjectId!.isNotEmpty) {
          final p = meta.verymProject
              .where((e) => e.key == c.pendingProjectId)
              .toList();
          if (p.isNotEmpty &&
              !c.projects.any((x) => x.project.key == p.first.key)) {
            c.projects.add(_ProjectWithPrice(project: p.first));
            changed = true;
          }
          c.pendingProjectId = null;
        }
        // 草稿回显的项目 key → 还原为 MetaKeyOption
        c.resolvePendingDraftProjects(meta);
      }
      if (changed) setState(() {});
      _regenerateDescIfNeeded();
    }
  }

  // ───────────────────── 描述自动带入 ─────────────────────

  void _regenerateDescIfNeeded() {
    if (_descManuallyEdited) return;
    final labels = <String>[];
    for (final c in _clients) {
      for (final p in c.projects) {
        if (!labels.contains(p.project.label)) labels.add(p.project.label);
      }
    }
    final hospital = _detail.hospitalName;
    // 未选项目时留空，避免出现「医院的兼职任务」这类兜底文案；
    // 选好项目后自动带入「{医院}的{项目…}」。
    final text = labels.isEmpty ? '' : '$hospital的${labels.join('、')}';
    _descController.text = text;
  }

  // ───────────────────── 客人操作 ─────────────────────

  /// 档案成员列表（含本人，按 is_main 降序）；空表示任务无档案数据
  List<PartTimeArchiveMember> get _members => _detail.archivesCompanions;

  /// 是否还有未被选走的档案成员可新增（无档案成员时保留自由新增）
  bool get _hasSelectableMember {
    if (_members.isEmpty) return true;
    final taken = _clients.map((e) => e.guestId).where((id) => id > 0).toSet();
    return _members.any((m) => !taken.contains(m.guestId));
  }

  Future<void> _addClient() async {
    // 无档案成员时回退旧逻辑：直接新增空白客人
    if (_members.isEmpty) {
      setState(() => _clients.add(_ClientEntry()));
      return;
    }
    final m = await _showMemberSheet();
    if (m == null || !mounted) return;
    setState(() {
      _clients.add(_ClientEntry()..applyMember(m));
    });
  }

  /// 点击客人卡片上的客户选择器（切换 / 补选）
  Future<void> _selectMemberFor(_ClientEntry c) async {
    final m = await _showMemberSheet(current: c);
    if (m == null || !mounted) return;
    setState(() => c.applyMember(m));
  }

  /// 底部弹窗选择档案成员；其他客人已选的置灰不可选。
  /// [current] 为正在切换的客人（其当前选择展示对勾且可重选）。
  Future<PartTimeArchiveMember?> _showMemberSheet({_ClientEntry? current}) {
    final takenGuestIds = _clients
        .where((e) => !identical(e, current) && e.guestId > 0)
        .map((e) => e.guestId)
        .toSet();
    return showModalBottomSheet<PartTimeArchiveMember>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '选择客户',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _members.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                itemBuilder: (_, i) {
                  final m = _members[i];
                  final taken = takenGuestIds.contains(m.guestId);
                  final isCurrent = current != null &&
                      current.member != null &&
                      current.guestId == m.guestId;
                  final subtitle = [
                    if (m.genderStr.isNotEmpty) m.genderStr,
                    if (m.birthTime.isNotEmpty) m.birthTime,
                  ].join(' · ');
                  return ListTile(
                    enabled: !taken,
                    onTap: taken ? null : () => Navigator.pop(ctx, m),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.userName.isEmpty ? '未命名' : m.userName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: taken
                                  ? const Color(0xFFBBBBBB)
                                  : const Color(0xFF1E1E1E),
                            ),
                          ),
                        ),
                        if (m.relationStr.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: taken
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.relationStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: taken
                                    ? const Color(0xFFBBBBBB)
                                    : _primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: subtitle.isEmpty
                        ? null
                        : Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF999999))),
                    trailing: taken
                        ? const Text('已选',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFFBBBBBB)))
                        : (isCurrent
                            ? const Icon(Icons.check,
                                size: 20, color: _primary)
                            : null),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _removeClient(int index) async {
    final c = _clients[index];
    // 已保存的草稿需调接口物理删除（不可恢复），确认后再移除卡片
    if (c.draftId > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除消费记录'),
          content: const Text('该客人的消费记录已保存，删除后不可恢复，确定删除吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: _danger)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _showLoadingDialog('正在删除...');
      final r = await PartTimeTaskService.deleteOrderDraft(c.draftId);
      _dismissDialog();
      if (!mounted) return;
      if (!r.success) {
        // 已写入正式录单的草稿后端会拒绝删除，直接透出服务端文案
        _toast(r.message ?? '删除失败');
        return;
      }
      _draftDeleted = true;
    }
    setState(() {
      c.dispose();
      _clients.remove(c);
    });
    _regenerateDescIfNeeded();
  }

  // ───────────────────── 护照识别 ─────────────────────

  Future<void> _pickPassport(_ClientEntry entry) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _primary),
              title: const Text('拍摄护照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _primary),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    _showLoadingDialog('正在上传护照...');
    try {
      final signData = await OssApi.getDirectUploadSign(picked.name);
      if (signData == null) {
        _dismissDialog();
        _toast('获取上传签名失败');
        return;
      }
      final imageUrl = await OssApi.uploadToOss(
        file: File(picked.path),
        signData: signData,
      );
      if (imageUrl == null) {
        _dismissDialog();
        _toast('护照图片上传失败');
        return;
      }
      entry.passportImageUrl = imageUrl;
      entry.errors.remove('passportImage');
      _updateLoadingDialog('正在识别护照信息...');
      final data = await OssApi.recognizePassport(imageUrl);
      _dismissDialog();
      if (!mounted) return;

      final name = data?['nameEn']?.toString() ?? '';
      final passport = data?['passportNumber']?.toString() ?? '';
      final birth = data?['birth_time']?.toString() ?? '';
      if (name.isEmpty && passport.isEmpty && birth.isEmpty) {
        _toast('未能识别护照信息，请手动填写');
        return;
      }
      setState(() {
        // 识别成功后，姓名一律用识别结果覆盖（无论原姓名是否已有值）
        entry.nameController.text = name;
        if (passport.isNotEmpty) entry.passportController.text = passport;
        final parsed = _tryParseDate(birth);
        if (parsed != null) entry.birthTime = parsed;
      });
      _toast('护照识别完成');
    } catch (e) {
      _dismissDialog();
      _toast('护照识别失败: $e');
    }
  }

  // ───────────────────── 素材选择/上传 ─────────────────────

  Future<void> _showMediaPicker() async {
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _primary),
              title: const Text('拍摄照片'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: _primary),
              title: const Text('拍摄视频'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _primary),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    final picker = ImagePicker();
    final remaining = _maxFileCount - _media.length;
    if (remaining <= 0) {
      _toast('最多只能上传 $_maxFileCount 个文件');
      return;
    }
    try {
      final List<XFile> media = [];
      if (action == 'photo') {
        final f = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (f != null) media.add(f);
      } else if (action == 'video') {
        final f = await picker.pickVideo(source: ImageSource.camera);
        if (f != null) media.add(f);
      } else {
        if (remaining == 1) {
          final f = await picker.pickMedia(imageQuality: 85);
          if (f != null) media.add(f);
        } else {
          media.addAll(
            await picker.pickMultipleMedia(imageQuality: 85, limit: remaining),
          );
        }
      }
      if (media.isEmpty) return;
      await _addMediaFiles(media);
    } catch (e) {
      _toast('选择媒体文件失败: $e');
    }
  }

  Future<void> _addMediaFiles(List<XFile> media) async {
    final remaining = _maxFileCount - _media.length;
    final filesToAdd = media.take(remaining).toList();
    for (final file in filesToAdd) {
      final fileSize = await file.length();
      final uploadFile = UploadFile.fromPath(
        file.path,
        customFileName: file.name,
        fileSize: fileSize,
      );
      final item = _MediaUpload(
        id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
        file: uploadFile,
      );
      if (!mounted) return;
      setState(() {
        _media.add(item);
        _mediaError = null;
      });
      _uploadMedia(item);
    }
  }

  /// 直接调 NAS 上传服务（不走全局队列），进度只在本页维护
  Future<void> _uploadMedia(_MediaUpload item) async {
    item.cancelToken = CancelToken();
    try {
      final result = await _nasService.uploadFile(
        file: item.file,
        hospitalName: _detail.hospitalName,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => item.progress = p);
        },
        cancelToken: item.cancelToken,
      );
      if (!mounted) return;
      setState(() {
        item.result = result;
        item.progress = 100;
        item.status = _MediaStatus.completed;
      });
      _regenerateDescIfNeeded();
    } catch (e) {
      // 用户移除/离开页面导致的取消，不算失败
      if (item.cancelToken?.isCancelled ?? false) return;
      if (!mounted) return;
      setState(() => item.status = _MediaStatus.failed);
    }
  }

  void _retryMedia(_MediaUpload item) {
    setState(() {
      item.status = _MediaStatus.uploading;
      item.progress = 0;
    });
    _uploadMedia(item);
  }

  void _removeMedia(_MediaUpload item) {
    if (item.status == _MediaStatus.uploading) {
      item.cancelToken?.cancel('用户移除');
    }
    setState(() => _media.remove(item));
  }

  // ───────────────────── 提交 ─────────────────────

  Future<void> _submit() async {
    if (_meta == null) {
      _toast('录单元数据加载中，请稍后重试');
      return;
    }

    // 1. 校验每个客人 + 素材：收集所有错误并标红，定位到第一个错误项
    // 先清空旧的错误状态
    for (final c in _clients) {
      c.errors.clear();
      for (final p in c.projects) {
        p.priceError = null;
      }
    }
    _mediaError = null;
    _descError = null;

    GlobalKey? firstErrorKey;
    void mark(_ClientEntry c, String field, String msg) {
      c.errors[field] = msg;
      firstErrorKey ??= c.fieldKey(field);
    }

    for (final c in _clients) {
      // 未选客户时其余字段尚未展示，只提示选择客户
      if (_members.isNotEmpty && !c.memberChosen) {
        mark(c, 'member', '请选择客户');
        continue;
      }
      if (c.nameController.text.trim().isEmpty) mark(c, 'name', '请填写姓名');
      if (c.birthTime == null) mark(c, 'birth', '请选择出生日期');
      if (c.passportImageUrl.isEmpty) mark(c, 'passportImage', '请上传护照照片');
      if (c.passportController.text.trim().isEmpty) {
        mark(c, 'passport', '请填写护照号');
      }
      if (c.projects.isEmpty) {
        mark(c, 'projects', '请选择手术项目');
      } else {
        var priceErr = false;
        for (final p in c.projects) {
          final price = double.tryParse(p.priceController.text) ?? 0;
          if (price <= 0) {
            p.priceError = '请填写金额';
            priceErr = true;
          }
        }
        if (priceErr) firstErrorKey ??= c.fieldKey('projects');
      }
      if (c.payType == null) mark(c, 'payType', '请选择付款方式');
      if (c.operationTime == null) mark(c, 'operationTime', '请选择手术时间');
      if (c.directorController.text.trim().isEmpty) {
        mark(c, 'director', '请填写手术院长');
      }
    }

    // 素材校验：已上传历史文件 + 本次新上传文件，总数需 ≥ _minFileCount
    final completed =
        _media.where((m) => m.status == _MediaStatus.completed).toList();
    final uploading =
        _media.where((m) => m.status == _MediaStatus.uploading).toList();
    final totalFiles = _existingFiles.length + completed.length;
    if (uploading.isNotEmpty) {
      _mediaError = '素材正在上传中，请等待上传完成';
      firstErrorKey ??= _mediaKey;
    } else if (totalFiles < _minFileCount) {
      _mediaError = '请至少上传 $_minFileCount 个图片/视频';
      firstErrorKey ??= _mediaKey;
    }
    if (_descController.text.trim().isEmpty) {
      _descError = '请填写素材描述';
      firstErrorKey ??= _descKey;
    }

    if (firstErrorKey != null) {
      setState(() {});
      _scrollToError(firstErrorKey!);
      return;
    }

    setState(() => _submitting = true);

    // 3. 保存随心拍素材：合并「保留的历史文件 + 新上传文件」一并提交。
    // 已绑定素材（_casuallyId>0）走编辑接口，否则走新建接口。
    {
      final fileList = <Map<String, dynamic>>[];
      // 保留的历史文件（携带 id，后端据此保留；被删除的不在列表中即删除）
      for (final f in _existingFiles) {
        final m = <String, dynamic>{
          'id': f.id,
          'original_name': f.originalName,
          'file_name': f.fileName,
          'file_path': f.filePath,
          'file_size': f.size,
          'url': f.url,
          'storage_type': f.storageType,
        };
        if (f.thumbnail.isNotEmpty) m['thumbnail'] = f.thumbnail;
        fileList.add(m);
      }
      // 本次新上传文件（无 id）
      for (final item in completed) {
        final r = item.result!;
        final thumbPath =
            r.thumbnail?.filePath ?? r.videoFrame?.filePath ?? '';
        final m = <String, dynamic>{
          'original_name': r.originalName,
          'file_name': r.fileName,
          'file_path': r.filePath,
          'file_size': r.fileSize,
          'url': r.fileUrl,
          'storage_type': r.storageType,
        };
        if (thumbPath.isNotEmpty) m['thumbnail'] = thumbPath;
        fileList.add(m);
      }

      final casuallyData = <String, dynamic>{
        'parttime_task_id': _detail.id,
        'type': 1, // casually 记录 type（按兼职 upload_new 接口文档固定）
        'material_type': 5, // 按兼职 upload_new 接口文档固定
        'material_category': 5, // 素材类别=施术过程（material_category.dart）
        'text': _descController.text.trim(),
        'hospital_id': _detail.hospitalId,
        'hospital_name': _detail.hospitalName,
        'country_type': 1, // 素材归属=韩国
        'source': 'App',
        'file': fileList,
      };
      final editing = _casuallyId > 0;
      final result = editing
          ? await MaterialApi.editMaterial({
              ...casuallyData,
              'id': _casuallyId,
            })
          : await MaterialApi.submitMaterial(casuallyData);
      if (result == null || result['code'] != 0) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _toast(result?['msg']?.toString() ?? '随心拍素材保存失败');
        return;
      }
    }

    // 4. 逐个客人提交录单草稿
    for (var i = 0; i < _clients.length; i++) {
      final c = _clients[i];
      final payload = _buildDraftPayload(c);
      final r = await PartTimeTaskService.submitOrderDraft(payload);
      if (!r.success) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _toast('客人${_cnNum(i + 1)}录单提交失败：${r.message ?? ''}');
        return;
      }
      // 回写 draft_id，避免再次提交时重复创建
      if (r.draftId != null) c.draftId = r.draftId!;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    _toast('任务数据已保存');
    Navigator.of(context).pop(true);
  }

  Map<String, dynamic> _buildDraftPayload(_ClientEntry c) {
    String fmt(DateTime? dt) {
      if (dt == null) return '';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    final discount = double.tryParse(c.discountController.text) ?? 0;
    final payload = <String, dynamic>{
      'task_id': _detail.id,
      'client_id': c.clientId,
      'main_client_id': _mainClientId,
      'hospital': _detail.hospitalId,
      'verym_project': c.projects.map((p) => p.project.key).toList(),
      'currency_type': 1, // 韩国录单固定韩币
      'number': c.surgeryAmount,
      'true_number': double.tryParse(c.actualAmountController.text) ?? 0,
      'true_type': c.actualStatus,
      'pay_type': c.payType ?? 0,
      'op_type': c.opType ?? 0,
      'kr_status': c.krStatus,
      'add_time': fmt(c.operationTime),
      'yp_close_time': fmt(c.depositTime),
      'ss_dean': c.directorController.text.trim(),
      'addnote': c.remarkController.text.trim(),
      'ClientName': c.nameController.text.trim(),
      'birth_time': fmt(c.birthTime),
      'passport_number': c.passportController.text.trim(),
      'passport_url': c.passportImageUrl,
      'discount_amount': discount,
      'archives_id': c.archivesId > 0 ? c.archivesId : _detail.archivesId,
      'guest_id': c.guestId,
      'project_info': c.projects
          .map((p) => {
                'name': p.project.label,
                'project_id': p.project.key,
                'price': double.tryParse(p.priceController.text) ?? 0,
              })
          .toList(),
    };
    if (c.draftId > 0) payload['draft_id'] = c.draftId;
    return payload;
  }

  // ───────────────────── 工具 ─────────────────────

  /// 清除某客人指定字段的校验错误（用户重新编辑时调用）
  void _clearError(_ClientEntry c, String field) {
    if (c.errors[field] != null) {
      setState(() => c.errors.remove(field));
    }
  }

  /// 滚动到第一个校验错误项并使其可见
  Future<void> _scrollToError(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  DateTime? _tryParseDate(String s) {
    if (s.isEmpty) return null;
    final normalized = s.replaceAll('/', '-');
    return DateTime.tryParse(normalized);
  }

  String _cnNum(int n) {
    const cn = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    return n >= 1 && n <= cn.length ? cn[n - 1] : '$n';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showLoadingDialog(String msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _primary),
                  const SizedBox(height: 16),
                  Text(msg, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateLoadingDialog(String msg) {
    _dismissDialog();
    _showLoadingDialog(msg);
  }

  void _dismissDialog() {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  // ───────────────────── Build ─────────────────────

  @override
  Widget build(BuildContext context) {
    // 删除草稿是即时物理删除：未保存直接返回时也要回传 true 让详情页刷新
    return PopScope(
      canPop: !_draftDeleted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _readOnly ? '查看任务数据' : '录入任务数据',
          style: const TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator())
          : _meta == null
              ? _buildMetaError()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_noScheduleTask) _buildNoScheduleHint(),
                    for (var i = 0; i < _clients.length; i++)
                      _buildClientCard(i, _clients[i]),
                    // 档案成员全部选完后不再展示新增入口
                    if (!_readOnly && !_noScheduleTask && _hasSelectableMember)
                      _buildAddClientButton(),
                    const SizedBox(height: 12),
                    _buildMaterialCard(),
                    const SizedBox(height: 80),
                  ],
                ),
      bottomNavigationBar:
          (_loadingMeta || _meta == null || _readOnly) ? null : _buildSubmitBar(),
    );
  }

  /// 无日程任务提示：仅需提交随心拍素材
  Widget _buildNoScheduleHint() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: _primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '该任务无需填写客人相关信息，仅需上传素材。',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF4A6FA5),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Color(0xFFB2B2B2)),
            const SizedBox(height: 12),
            const Text('任务数据加载失败',
                style: TextStyle(color: Color(0xFF666666), fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _loadingMeta = true);
                _loadMeta();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        color: Colors.white,
        child: SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB0B0B0),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '提交任务数据',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
      ),
    );
  }

  // ── 客人卡片 ──

  Widget _buildClientCard(int index, _ClientEntry c) {
    return Container(
      key: ValueKey('client_${c.uid}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '客人${_cnNum(index + 1)}',
                  style: const TextStyle(fontSize: 13, color: _primary),
                ),
              ),
              const Spacer(),
              if (_clients.length > 1 && !_readOnly)
                TextButton.icon(
                  onPressed: () => _removeClient(index),
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: _danger),
                  label: const Text('移除',
                      style: TextStyle(color: _danger, fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          // 先选客户（档案成员），再填写其余信息
          if (!_readOnly && _members.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildMemberSelector(c),
          ],
          if (_readOnly || _members.isEmpty || c.memberChosen) ...[
          const SizedBox(height: 8),
          // 护照识别
          Column(
            key: c.fieldKey('passportImage'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildFieldLabel('护照照片', required: true),
                  if (!_readOnly) ...[
                    const Spacer(),
                    const PassportCaptureGuideHint(compact: true),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (!_readOnly)
                    OutlinedButton.icon(
                    onPressed: () => _pickPassport(c),
                    icon:
                        const Icon(Icons.document_scanner_outlined, size: 18),
                    label: Text(
                        c.passportImageUrl.isEmpty ? '上传护照识别' : '重新上传护照'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(
                          color: c.errors['passportImage'] != null
                              ? _danger
                              : _primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (c.passportImageUrl.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => showImagePreview(
                        context,
                        imageUrls: [c.passportImageUrl],
                        title: '护照预览',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          c.passportImageUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, s) => const Icon(
                              Icons.image_not_supported_outlined,
                              size: 24,
                              color: Color(0xFFBBBBBB)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (c.errors['passportImage'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(c.errors['passportImage']!,
                      style: const TextStyle(fontSize: 12, color: _danger)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField('姓名', c.nameController,
              required: true,
              hint: '上传护照自动识别或手动填写',
              fieldKey: c.fieldKey('name'),
              errorText: c.errors['name'],
              enabled: !_readOnly,
              onChanged: (_) => _clearError(c, 'name')),
          _buildDateField('出生日期', c.birthTime, required: true,
              fieldKey: c.fieldKey('birth'),
              errorText: c.errors['birth'],
              enabled: !_readOnly, (picked) {
            setState(() {
              c.birthTime = picked;
              c.errors.remove('birth');
            });
          }),
          _buildTextField('护照号', c.passportController,
              required: true,
              fieldKey: c.fieldKey('passport'),
              errorText: c.errors['passport'],
              enabled: !_readOnly,
              onChanged: (_) => _clearError(c, 'passport')),
          const Divider(height: 24),
          KeyedSubtree(
            key: c.fieldKey('projects'),
            child: _buildProjectSection(c),
          ),
          _buildDropdown<int>(
            '付款方式',
            c.payType,
            _meta!.payType
                .map((o) => DropdownMenuItem<int>(
                      value: _toInt(o.value),
                      child: Text(o.label),
                    ))
                .toList(),
            (v) => setState(() {
              c.payType = v;
              c.errors.remove('payType');
            }),
            required: true,
            fieldKey: c.fieldKey('payType'),
            errorText: c.errors['payType'],
            enabled: !_readOnly,
          ),
          _buildDropdown<int>(
            '手术类型',
            c.opType,
            _meta!.surgeryType
                .map((o) => DropdownMenuItem<int>(
                      value: _toInt(o.value),
                      child: Text(o.label),
                    ))
                .toList(),
            (v) => setState(() => c.opType = v),
            enabled: !_readOnly,
          ),
          _buildDateField('手术时间', c.operationTime, required: true,
              fieldKey: c.fieldKey('operationTime'),
              errorText: c.errors['operationTime'],
              enabled: !_readOnly, (picked) {
            setState(() {
              c.operationTime = picked;
              c.errors.remove('operationTime');
            });
          }),
          _buildDateField('定金时间', c.depositTime, enabled: !_readOnly, (picked) {
            setState(() => c.depositTime = picked);
          }),
          _buildNumberField('实收金额', c.actualAmountController,
              enabled: !_readOnly),
          _buildSegment('实收情况', c.actualStatus, const {1: '全款', 2: '定金'},
              (v) => setState(() => c.actualStatus = v),
              enabled: !_readOnly),
          _buildSegment('手术情况', c.krStatus, const {0: '暂未手术', 1: '已经手术'},
              (v) => setState(() => c.krStatus = v),
              enabled: !_readOnly),
          _buildTextField('手术院长', c.directorController,
              required: true,
              fieldKey: c.fieldKey('director'),
              errorText: c.errors['director'],
              enabled: !_readOnly,
              onChanged: (_) => _clearError(c, 'director')),
          _buildReadonlyField('手术币种', '韩币'),
          _buildTextField('备注', c.remarkController,
              maxLines: 2, enabled: !_readOnly),
          ],
        ],
      ),
    );
  }

  /// 客户选择器（必选）：展示已选档案成员，点击弹出底部成员列表
  Widget _buildMemberSelector(_ClientEntry c) {
    final m = c.member;
    final name = m != null
        ? (m.userName.isEmpty ? '未命名' : m.userName)
        : c.nameController.text.trim();
    return Column(
      key: c.fieldKey('member'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('客户', required: true),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _selectMemberFor(c),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                  color: c.errors['member'] != null
                      ? _danger
                      : const Color(0xFFDDDDDD)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: !c.memberChosen || name.isEmpty
                      ? const Text('请选择客户',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFFBBBBBB)))
                      : Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, color: Color(0xFF1E1E1E)),
                              ),
                            ),
                            if (m != null && m.relationStr.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F4FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(m.relationStr,
                                    style: const TextStyle(
                                        fontSize: 11, color: _primary)),
                              ),
                            ],
                          ],
                        ),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    size: 20, color: Color(0xFF999999)),
              ],
            ),
          ),
        ),
        if (c.errors['member'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(c.errors['member']!,
                style: const TextStyle(fontSize: 12, color: _danger)),
          ),
      ],
    );
  }

  Widget _buildAddClientButton() {
    return OutlinedButton.icon(
      onPressed: _addClient,
      icon: const Icon(Icons.person_add_alt_1, size: 18),
      label: const Text('新增客人'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: _primary),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── 项目多选 ──

  Widget _buildProjectSection(_ClientEntry c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('手术项目', required: true),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _readOnly ? null : () => _showProjectSelector(c),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                  color: c.errors['projects'] != null
                      ? _danger
                      : const Color(0xFFDDDDDD)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: c.projects.isEmpty
                ? const Text('请选择手术项目',
                    style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB)))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: c.projects
                        .map((pwp) => Chip(
                              label: Text(pwp.project.label,
                                  style: const TextStyle(
                                      fontSize: 12, color: _primary)),
                              backgroundColor: const Color(0xFFEEF1FA),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
          ),
        ),
        if (c.errors['projects'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(c.errors['projects']!,
                style: const TextStyle(fontSize: 12, color: _danger)),
          ),
        if (c.projects.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...c.projects.map(
            (pwp) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(pwp.project.label,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF666666)),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _buildAmountStepper(pwp.priceController, '金额',
                        errorText: pwp.priceError,
                        enabled: !_readOnly, onChanged: () {
                      if (pwp.priceError != null) {
                        setState(() => pwp.priceError = null);
                      }
                    }),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text('优惠金额',
                      style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _buildAmountStepper(c.discountController, '优惠金额',
                      enabled: !_readOnly),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDDDDD)),
            ),
            child: Row(
              children: [
                const Text('手术金额',
                    style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
                const Spacer(),
                Text('₩ ${_formatWon(c.surgeryAmount)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _primary)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text('手术金额 = 项目金额总和 - 优惠金额',
              style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  void _showProjectSelector(_ClientEntry c) {
    if (_meta == null) return;
    FocusScope.of(context).unfocus();
    final allProjects = _meta!.verymProject;
    final initialKeys = c.projects.map((p) => p.project.key).toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ProjectSelectorSheet(
        allProjects: allProjects,
        initialSelectedKeys: initialKeys,
        onConfirm: (selectedKeys) {
          setState(() {
            final toRemove = c.projects
                .where((p) => !selectedKeys.contains(p.project.key))
                .toList();
            for (final r in toRemove) {
              r.dispose();
              c.projects.remove(r);
            }
            final existing = c.projects.map((p) => p.project.key).toSet();
            for (final key in selectedKeys) {
              if (!existing.contains(key)) {
                final project = allProjects.firstWhere((p) => p.key == key);
                c.projects.add(_ProjectWithPrice(project: project));
              }
            }
            if (c.projects.isNotEmpty) c.errors.remove('projects');
          });
          _regenerateDescIfNeeded();
        },
      ),
    );
  }

  // ── 素材卡片 ──

  Widget _buildMaterialCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('任务素材',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text(
              _readOnly
                  ? '该任务的图片/视频素材'
                  : '上传该任务的图片/视频，比如项目的施术过程等等（至少 $_minFileCount 项，一天累计需满 10 项才能完成任务）',
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          const SizedBox(height: 12),
          KeyedSubtree(key: _mediaKey, child: _buildMediaGrid()),
          if (_mediaError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Text(_mediaError!,
                  style: const TextStyle(fontSize: 12, color: _danger)),
            ),
          const SizedBox(height: 12),
          _buildFieldLabel('素材描述', required: true),
          const SizedBox(height: 6),
          TextField(
            key: _descKey,
            controller: _descController,
            maxLines: 3,
            enabled: !_readOnly,
            onChanged: (_) {
              _descManuallyEdited = true;
              if (_descError != null) setState(() => _descError = null);
            },
            decoration: _inputDecoration('请输入素材描述',
                errorText: _descError),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    const crossAxisCount = 4;
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 按可用宽度均分，铺满整行，避免固定尺寸在右侧留白
        final size =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ..._existingFiles.map((f) => _buildExistingThumb(f, size)),
            ..._media.map((m) => _buildMediaThumb(m, size)),
            if (!_readOnly) _buildAddMediaTile(size),
          ],
        );
      },
    );
  }

  /// 已上传历史文件缩略图（可预览，非只读时可删除）
  Widget _buildExistingThumb(PartTimeMaterialFile f, double size) {
    Widget content;
    if (f.isVideo) {
      content =
          const Icon(Icons.movie, size: 32, color: Color(0xFFBBBBBB));
    } else {
      content = CachedNetworkImage(
        imageUrl: f.url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, _, _) =>
            const Icon(Icons.image, size: 32, color: Color(0xFFBBBBBB)),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            // 通用预览组件已支持视频播放，图片/视频均可点开预览
            onTap: () => showImagePreview(context,
                imageUrls: [f.url], title: '素材预览'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: const Color(0xFFF0F0F0),
                alignment: Alignment.center,
                child: content,
              ),
            ),
          ),
          if (!_readOnly)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => setState(() => _existingFiles.remove(f)),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaThumb(_MediaUpload item, double size) {
    final thumbUrl =
        item.result?.thumbnail?.fileUrl ?? item.result?.videoFrame?.fileUrl;

    Widget content;
    if (item.isImage && File(item.file.localPath).existsSync()) {
      // 本地图片直接预览（上传中/完成均可显示）
      content = Image.file(File(item.file.localPath),
          width: size, height: size, fit: BoxFit.cover);
    } else if (thumbUrl != null && thumbUrl.isNotEmpty) {
      content = CachedNetworkImage(
        imageUrl: thumbUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, _, _) =>
            const Icon(Icons.movie, size: 32, color: Color(0xFFBBBBBB)),
      );
    } else {
      content = Icon(item.isImage ? Icons.image : Icons.movie,
          size: 32, color: const Color(0xFFBBBBBB));
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: const Color(0xFFF0F0F0),
              alignment: Alignment.center,
              child: content,
            ),
          ),
          if (item.status == _MediaStatus.uploading)
            Container(
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text('${item.progress.toInt()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          if (item.status == _MediaStatus.failed)
            GestureDetector(
              onTap: () => _retryMedia(item),
              child: Container(
                decoration: BoxDecoration(
                  color: _danger.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 20),
                    Text('重试',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => _removeMedia(item),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMediaTile(double size) {
    return GestureDetector(
      onTap: _showMediaPicker,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 26, color: Color(0xFF999999)),
            SizedBox(height: 2),
            Text('添加', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
          ],
        ),
      ),
    );
  }

  // ───────────────────── 通用字段控件 ─────────────────────

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        if (required)
          const Text('*', style: TextStyle(color: _danger, fontSize: 14)),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF666666),
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {String? errorText}) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      errorText: errorText,
      errorStyle: const TextStyle(fontSize: 12, color: _danger),
      border: border(const Color(0xFFDDDDDD)),
      enabledBorder: border(const Color(0xFFDDDDDD)),
      focusedBorder: border(_primary),
      errorBorder: border(_danger),
      focusedErrorBorder: border(_danger),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool required = false,
      String? hint,
      int maxLines = 1,
      String? errorText,
      Key? fieldKey,
      bool enabled = true,
      ValueChanged<String>? onChanged}) {
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label, required: required),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            enabled: enabled,
            onChanged: onChanged,
            decoration: _inputDecoration(hint ?? '请输入$label', errorText: errorText),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildReadonlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDDDDD)),
            ),
            child: Text(value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller,
      {bool required = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label, required: required),
          const SizedBox(height: 6),
          _buildAmountStepper(controller, label, enabled: enabled),
        ],
      ),
    );
  }

  /// 韩币金额步进输入：「− ₩金额 +」，整数、步进 100。
  Widget _buildAmountStepper(TextEditingController controller, String hint,
      {String? errorText, VoidCallback? onChanged, bool enabled = true}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepButton(Icons.remove, enabled
            ? () {
                _stepAmount(controller, -100);
                onChanged?.call();
              }
            : null),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            enabled: enabled,
            onChanged: (_) {
              setState(() {});
              onChanged?.call();
            },
            decoration: _inputDecoration(hint, errorText: errorText).copyWith(
              prefixText: '₩ ',
              prefixStyle:
                  const TextStyle(fontSize: 14, color: Color(0xFF333333)),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(width: 6),
        _stepButton(Icons.add, enabled
            ? () {
                _stepAmount(controller, 100);
                onChanged?.call();
              }
            : null),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 34,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18, color: _primary),
      ),
    );
  }

  void _stepAmount(TextEditingController c, int delta) {
    var next = (int.tryParse(c.text) ?? 0) + delta;
    if (next < 0) next = 0;
    c.text = next.toString();
    setState(() {});
  }

  /// 韩币金额展示：千分位整数，如 1,000,000
  String _formatWon(num v) {
    final n = v.round();
    final digits = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }

  Widget _buildDateField(
      String label, DateTime? value, ValueChanged<DateTime> onPicked,
      {bool required = false,
      String? errorText,
      Key? fieldKey,
      bool enabled = true}) {
    final hasError = errorText != null;
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label, required: required),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: enabled
                ? () async {
                    FocusScope.of(context).unfocus();
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: value ?? now,
                      firstDate: DateTime(now.year - 100),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) onPicked(picked);
                  }
                : null,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(
                    color: hasError ? _danger : const Color(0xFFDDDDDD)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value == null
                    ? '请选择$label'
                    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 14,
                  color: value == null
                      ? const Color(0xFFBBBBBB)
                      : const Color(0xFF333333),
                ),
              ),
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(errorText,
                  style: const TextStyle(fontSize: 12, color: _danger)),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(String label, T? value,
      List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged,
      {bool required = false,
      String? errorText,
      Key? fieldKey,
      bool enabled = true}) {
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label, required: required),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            items: items,
            onChanged: enabled ? onChanged : null,
            decoration: _inputDecoration('请选择$label', errorText: errorText),
            style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(String label, int value, Map<int, String> options,
      ValueChanged<int> onChanged,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(label),
          const SizedBox(height: 6),
          Row(
            children: options.entries.map((e) {
              final selected = e.key == value;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: enabled ? (_) => onChanged(e.key) : null,
                  selectedColor: const Color(0xFFEEF1FA),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected ? _primary : const Color(0xFF666666),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// 客人录入项
// ══════════════════════════════════════════════════════════════

class _ClientEntry {
  static int _seq = 0;

  /// 页面内稳定唯一标识，用于给客人卡片设置 Key，避免下拉框状态错位
  final int uid = _seq++;

  int clientId;
  int guestId;
  int archivesId;
  int draftId; // 0=新增

  /// 关联的档案成员（从任务详情 archives_companions 中选择）
  PartTimeArchiveMember? member;

  /// 是否已选定客户：选过档案成员，或草稿回显（旧数据可能匹配不到成员）
  bool get memberChosen => member != null || draftId > 0;

  final TextEditingController nameController;
  final TextEditingController passportController;
  DateTime? birthTime;

  /// 护照识别时上传到 OSS 的图片 URL（随录单草稿提交给后端）
  String passportImageUrl = '';

  final List<_ProjectWithPrice> projects;
  final TextEditingController discountController;
  int? payType;
  int? opType;
  DateTime? operationTime; // add_time（手术时间）
  DateTime? depositTime; // yp_close_time（定金时间）
  final TextEditingController actualAmountController; // true_number
  int actualStatus; // true_type：1=全款 2=定金
  int krStatus; // 0=暂未手术 1=已经手术
  final TextEditingController directorController; // ss_dean
  final TextEditingController remarkController; // addnote

  /// 预约带入的项目 key，待 meta 加载后解析
  String? pendingProjectId;

  /// 草稿回显的项目（key→price），待 meta 加载后解析
  List<MapEntry<String, String>>? _pendingDraftProjects;

  /// 各字段的校验错误文案，按字段名索引（null/缺省=无错误）
  final Map<String, String?> errors = {};

  /// 各字段的滚动定位 Key（稳定复用，避免重建时丢失）
  final Map<String, GlobalKey> _fieldKeys = {};
  GlobalKey fieldKey(String field) =>
      _fieldKeys.putIfAbsent(field, () => GlobalKey());

  _ClientEntry({
    this.clientId = 0,
    this.guestId = 0,
    this.archivesId = 0,
    this.draftId = 0,
  })  : nameController = TextEditingController(),
        passportController = TextEditingController(),
        projects = [],
        discountController = TextEditingController(),
        actualAmountController = TextEditingController(),
        directorController = TextEditingController(),
        remarkController = TextEditingController(),
        actualStatus = 1,
        krStatus = 0;

  /// 由已有录单草稿回显
  factory _ClientEntry.fromDraft(PartTimeOrderDraft d) {
    final p = d.draftPayload;
    final entry = _ClientEntry(
      clientId: d.clientId,
      guestId: d.guestId != 0 ? d.guestId : _i(p['guest_id']),
      archivesId: d.archivesId != 0 ? d.archivesId : _i(p['archives_id']),
      draftId: d.draftId,
    );
    entry.nameController.text = p['ClientName']?.toString() ?? '';
    entry.passportController.text = p['passport_number']?.toString() ?? '';
    entry.passportImageUrl = p['passport_url']?.toString() ?? '';
    entry.birthTime = _parse(p['birth_time']?.toString() ?? '');
    entry.discountController.text = _numStr(p['discount_amount']);
    entry.payType = _i(p['pay_type']) == 0 ? null : _i(p['pay_type']);
    entry.opType = _i(p['op_type']) == 0 ? null : _i(p['op_type']);
    entry.operationTime = _parse(p['add_time']?.toString() ?? '');
    entry.depositTime = _parse(p['yp_close_time']?.toString() ?? '');
    entry.actualAmountController.text = _numStr(p['true_number']);
    entry.actualStatus = _i(p['true_type']) == 0 ? 1 : _i(p['true_type']);
    entry.krStatus = _i(p['kr_status']);
    entry.directorController.text = p['ss_dean']?.toString() ?? '';
    entry.remarkController.text = p['addnote']?.toString() ?? '';

    // project_info: [{name, project_id, price}]
    final info = p['project_info'];
    if (info is List) {
      entry._pendingDraftProjects = info
          .whereType<Map>()
          .map((e) => MapEntry(
              e['project_id']?.toString() ?? '', _numStr(e['price'])))
          .where((e) => e.key.isNotEmpty)
          .toList();
    }
    return entry;
  }

  /// 选定档案成员：带入身份 ID 并预填姓名/出生日期/护照号（仍可编辑）。
  /// 换人时清空已上传的护照照片（属于上一位客人）。
  void applyMember(PartTimeArchiveMember m) {
    final switched = guestId > 0 && guestId != m.guestId;
    member = m;
    guestId = m.guestId;
    clientId = m.clientId;
    archivesId = m.archivesId;
    nameController.text = m.userName;
    birthTime = _parse(m.birthTime);
    passportController.text = m.passportNo;
    if (switched) passportImageUrl = '';
    errors.remove('member');
    if (m.userName.isNotEmpty) errors.remove('name');
    if (birthTime != null) errors.remove('birth');
    if (m.passportNo.isNotEmpty) errors.remove('passport');
  }

  /// meta 加载完成后还原草稿回显的项目
  void resolvePendingDraftProjects(OrderEntryMeta meta) {
    final pending = _pendingDraftProjects;
    if (pending == null) return;
    for (final e in pending) {
      final match = meta.verymProject.where((p) => p.key == e.key).toList();
      if (match.isNotEmpty &&
          !projects.any((x) => x.project.key == e.key)) {
        projects.add(
            _ProjectWithPrice(project: match.first, initialPrice: e.value));
      }
    }
    _pendingDraftProjects = null;
  }

  double get surgeryAmount {
    var sum = 0.0;
    for (final p in projects) {
      sum += double.tryParse(p.priceController.text) ?? 0;
    }
    final discount = double.tryParse(discountController.text) ?? 0;
    final result = sum - discount;
    return result < 0 ? 0 : result;
  }

  void dispose() {
    nameController.dispose();
    passportController.dispose();
    discountController.dispose();
    actualAmountController.dispose();
    directorController.dispose();
    remarkController.dispose();
    for (final p in projects) {
      p.dispose();
    }
  }

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _numStr(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      if (v == 0) return '';
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    final s = v.toString();
    return s == '0' ? '' : s;
  }

  static DateTime? _parse(String s) {
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceAll('/', '-'));
  }
}

class _ProjectWithPrice {
  final MetaKeyOption project;
  final TextEditingController priceController;

  /// 金额校验错误文案（null=无错误）
  String? priceError;

  _ProjectWithPrice({required this.project, String? initialPrice})
      : priceController = TextEditingController(text: initialPrice ?? '');

  void dispose() => priceController.dispose();
}

// ══════════════════════════════════════════════════════════════
// 任务素材上传项（本页独立维护，不走全局上传队列）
// ══════════════════════════════════════════════════════════════

enum _MediaStatus { uploading, completed, failed }

class _MediaUpload {
  final String id;
  final UploadFile file;
  double progress;
  _MediaStatus status;
  NasUploadedFileInfo? result;
  CancelToken? cancelToken;

  _MediaUpload({required this.id, required this.file})
      : progress = 0,
        status = _MediaStatus.uploading;

  bool get isImage => file.fileType == UploadFileType.image;
}

// ══════════════════════════════════════════════════════════════
// 手术项目多选弹窗
// ══════════════════════════════════════════════════════════════

class _ProjectSelectorSheet extends StatefulWidget {
  final List<MetaKeyOption> allProjects;
  final Set<String> initialSelectedKeys;
  final ValueChanged<Set<String>> onConfirm;

  const _ProjectSelectorSheet({
    required this.allProjects,
    required this.initialSelectedKeys,
    required this.onConfirm,
  });

  @override
  State<_ProjectSelectorSheet> createState() => _ProjectSelectorSheetState();
}

class _ProjectSelectorSheetState extends State<_ProjectSelectorSheet> {
  final _searchController = TextEditingController();
  late Set<String> _selectedKeys;
  List<MetaKeyOption> _filtered = [];

  @override
  void initState() {
    super.initState();
    _selectedKeys = Set.from(widget.initialSelectedKeys);
    _filtered = widget.allProjects;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text;
    setState(() {
      _filtered = q.isEmpty
          ? widget.allProjects
          : widget.allProjects
              .where((p) => p.label.toLowerCase().contains(q.toLowerCase()))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 20, color: Color(0xFF1F6FF4)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('选择手术项目（多选）',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333))),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onConfirm(_selectedKeys);
                  },
                  child: const Text('确定',
                      style: TextStyle(
                          color: Color(0xFF1F6FF4),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              cursorColor: const Color(0xFF1F6FF4),
              decoration: InputDecoration(
                hintText: '搜索项目...',
                hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
                prefixIcon: const Icon(Icons.search,
                    size: 20, color: Color(0xFF1F6FF4)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF0F3FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1F6FF4)),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final project = _filtered[i];
                final isSelected = _selectedKeys.contains(project.key);
                return ListTile(
                  title:
                      Text(project.label, style: const TextStyle(fontSize: 14)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF1F6FF4), size: 20)
                      : const Icon(Icons.radio_button_off,
                          color: Color(0xFFDDDDDD), size: 20),
                  dense: true,
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selectedKeys.remove(project.key);
                    } else {
                      _selectedKeys.add(project.key);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
