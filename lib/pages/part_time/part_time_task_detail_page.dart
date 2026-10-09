import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/models/part_time_task.dart';
import 'package:yatai_hub/pages/part_time/part_time_task_data_entry_page.dart';
import 'package:yatai_hub/pages/chat/chat_page.dart';
import 'package:yatai_hub/services/part_time_task_service.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/utils/map_launcher.dart';

/// 兼职任务详情页
///
/// 来源：兼职 Tab 的"接单列表"点击进入。
/// 根据 status + 当前用户身份动态渲染底部操作按钮。
class PartTimeTaskDetailPage extends StatefulWidget {
  final int taskId;

  const PartTimeTaskDetailPage({super.key, required this.taskId});

  @override
  State<PartTimeTaskDetailPage> createState() => _PartTimeTaskDetailPageState();
}

class _PartTimeTaskDetailPageState extends State<PartTimeTaskDetailPage> {
  static const Color _primary = Color(0xFF1F6FF4);
  static const Color _danger = Color(0xFFFF4D4F);
  static const Color _success = Color(0xFF52C41A);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  PartTimeTaskDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;
  int? _currentUserId;

  /// 是否兼职用户（roleid=275）。群聊跨角色，非兼职从群聊进入详情时只读——
  /// 可查看任务信息，但不显示接单/完成/录入等任何操作入口。
  bool _canOperate = false;

  /// 群聊未读数，用于吸附按钮红点
  int _unreadCount = 0;

  /// 离开时回传是否做过修改（让上一页决定是否刷新列表）
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final uid = await UserService().getBackendUserId();
    _currentUserId = int.tryParse(uid ?? '');
    _canOperate = await UserService().isPartTimeUser();
    if (mounted) setState(() {});
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final result = await PartTimeTaskService.getDetail(widget.taskId);
    if (!mounted) return;
    setState(() {
      _detail = result.detail;
      _errorMessage = result.detail == null ? result.message : null;
      _loading = false;
    });
    if (result.detail != null && _showChatEntry(result.detail!)) {
      _refreshUnread();
    }
  }

  /// 是否显示群聊入口。
  /// - 兼职用户：只有任务已归属自己（接单人=我）才是群成员，未接单（接单列表进来看详情）不显示；
  /// - 非兼职用户（发起人/责任客服/管理员，跨角色只读进入）：本身即群成员，始终显示。
  bool _showChatEntry(PartTimeTaskDetail d) =>
      !_canOperate || d.isAcceptedByMe(_currentUserId);

  Future<void> _refreshUnread() async {
    final n = await ParttimeChatService().getTaskUnread(
      ChatTarget.task(widget.taskId),
    );
    if (!mounted) return;
    setState(() => _unreadCount = n);
  }

  Future<void> _openMessageBoard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          taskId: widget.taskId,
          title: _detail?.hospitalName.isEmpty ?? true
              ? '任务群聊'
              : _detail!.hospitalName,
        ),
      ),
    );
    if (mounted) _refreshUnread();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────────────── 操作 ─────────────────────

  Future<void> _doAccept() async {
    final confirm = await _confirmDialog(
      title: '确认接单',
      content: '接单后，任务将归属到你的名下并进入「已接单」状态，是否确认？',
      confirmText: '确认接单',
      confirmColor: _primary,
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final r = await PartTimeTaskService.accept(widget.taskId);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.success ? '接单成功' : (r.message ?? '接单失败'));
    if (r.success) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _doUpdateStatus(
    int targetStatus, {
    String? confirmText,
    String? confirmContent,
    String? successText,
  }) async {
    final confirm = await _confirmDialog(
      title: '确认操作',
      content: confirmContent ?? '是否确认变更任务状态？',
      confirmText: confirmText ?? '确认',
      confirmColor: _primary,
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final r = await PartTimeTaskService.updateStatus(
      taskId: widget.taskId,
      status: targetStatus,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.success ? (successText ?? '操作成功') : (r.message ?? '操作失败'));
    if (r.success) {
      _changed = true;
      await _load();
    }
  }

  // ignore: unused_element
  Future<void> _doCancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('取消任务'),
          content: TextField(
            controller: controller,
            maxLength: 255,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '请输入取消原因（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('确认取消任务'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    setState(() => _busy = true);
    final r = await PartTimeTaskService.updateStatus(
      taskId: widget.taskId,
      status: PartTimeTaskStatus.canceled,
      cancelReason: reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.success ? '任务已取消' : (r.message ?? '取消失败'));
    if (r.success) {
      _changed = true;
      await _load();
    }
  }

  /// 进入「录入/编辑/查看任务数据」页（护照识别 + 录单草稿 + 随心拍素材）
  Future<void> _openDataEntry(
    PartTimeTaskDetail d, {
    bool readOnly = false,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PartTimeTaskDataEntryPage(detail: d, readOnly: readOnly),
      ),
    );
    if (result == true) {
      _changed = true;
      await _load();
    }
  }

  /// 完成任务前校验是否已录入任务数据并上传素材
  void _onCompleteTask(PartTimeTaskDetail d) {
    if (!d.canComplete) {
      final needOrder = !d.hasOrderDraft;
      final needMaterial = !d.hasMaterial;
      String msg;
      if (needOrder && needMaterial) {
        msg = '请先录入任务数据并上传素材';
      } else if (needOrder) {
        msg = '请先录入任务数据';
      } else {
        msg = '请先上传任务素材';
      }
      _toast(msg);
      return;
    }
    _doUpdateStatus(
      PartTimeTaskStatus.completed,
      confirmText: '确认完成',
      confirmContent: '任务将会标记为已完成，不可撤销，是否确认？',
      successText: '任务已完成',
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String content,
    required String confirmText,
    Color confirmColor = _primary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  // ───────────────────── 时间格式化 ─────────────────────

  /// 优先用服务端格式化好的时间文本（已处理时区）；老接口无该字段时回退本地转换。
  String _displayDateTime(String text, int seconds) {
    if (text.isNotEmpty) return text;
    return _fmtDateTime(seconds);
  }

  String _fmtDateTime(int seconds) {
    if (seconds <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  // ───────────────────── Build ─────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 仅在做过修改时才拦截 pop，以便把 _changed 回传给上一页触发刷新；
      // 未修改时保持 canPop=true，确保 iOS 侧滑返回手势可用。
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            '任务详情',
            style: TextStyle(
              color: Color(0xFF1E1E1E),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading || _busy ? null : _load,
              icon: const Icon(Icons.refresh, color: Color(0xFF1E1E1E)),
            ),
          ],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: Stack(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _detail == null
                ? _buildError()
                : _buildContent(_detail!),
            if (_detail != null && _showChatEntry(_detail!)) _buildCommentFab(),
          ],
        ),
        bottomNavigationBar: _detail == null
            ? null
            : _buildBottomActions(_detail!),
      ),
    );
  }

  /// 右侧中部吸附的群聊入口（带未读红点）
  Widget _buildCommentFab() {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.38,
      child: GestureDetector(
        onTap: _openMessageBoard,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x331F6FF4),
                blurRadius: 8,
                offset: Offset(-2, 2),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(Icons.forum_outlined, color: Colors.white, size: 22),
              if (_unreadCount > 0)
                Positioned(
                  right: 2,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D4F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Color(0xFFB2B2B2)),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? '加载失败',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
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

  Widget _buildContent(PartTimeTaskDetail d) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(d),
        // 任务已完成后进入审核流程，展示审核状态（驳回时含原因与编辑提示）。
        if (d.showAudit) ...[const SizedBox(height: 12), _buildAuditCard(d)],
        // 提示卡片（合一）：待接单/已接单未录入时提示提前到达；已接单未录入时
        // 再叠加「及时录入」一行。录入任务数据后整卡消失。
        if (_showTaskTip(d)) ...[
          const SizedBox(height: 12),
          _buildTaskTipCard(d),
        ],
        if (d.requireDesc.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTextBlockCard(title: '任务要求', content: d.requireDesc),
        ],
        if (d.remark.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTextBlockCard(title: '备注', content: d.remark),
        ],
        if (d.appoint != null) ...[
          const SizedBox(height: 12),
          _buildAppointCard(d.appoint!),
        ],
        const SizedBox(height: 12),
        _buildInfoCard(
          title: '任务记录',
          rows: [
            _Row('创建时间', _fmtDateTime(d.addTime)),
            if (d.acceptTime > 0) _Row('接单时间', _fmtDateTime(d.acceptTime)),
            if (d.finishTime > 0) _Row('完成时间', _fmtDateTime(d.finishTime)),
            if (d.cancelTime > 0) _Row('取消时间', _fmtDateTime(d.cancelTime)),
            if (d.cancelReason.isNotEmpty) _Row('取消原因', d.cancelReason),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ───────────────────── 提示 / 预约卡片 ─────────────────────

  /// 是否展示任务提示卡片：
  /// - 待接单：仅提示提前到达；
  /// - 已接单且未录入任务数据：提示提前到达 + 及时录入；
  /// - 已录入 / 已完成 / 已取消：不再展示。
  bool _showTaskTip(PartTimeTaskDetail d) {
    if (d.status == PartTimeTaskStatus.waiting) return true;
    if (d.status == PartTimeTaskStatus.accepted) {
      return !d.hasOrderDraft && !d.hasMaterial;
    }
    return false;
  }

  /// 任务提示卡片：两条提示合并到同一张卡片内，避免出现两个独立提示框。
  Widget _buildTaskTipCard(PartTimeTaskDetail d) {
    // 已接单未录入时追加「及时录入」提示；待接单阶段仅提示提前到达。
    final showEntryTip = d.status == PartTimeTaskStatus.accepted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE0A6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTipLine(Icons.access_time_rounded, '请提前 30 分钟到达任务地点'),
          if (showEntryTip) ...[
            const SizedBox(height: 8),
            _buildTipLine(Icons.edit_note_rounded, '到院后请及时录入任务数据'),
          ],
        ],
      ),
    );
  }

  /// 提示卡片内的单行：小图标 + 文案。
  Widget _buildTipLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFFA8C16)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFD46B08),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppointCard(PartTimeTaskAppoint a) {
    final rows = <_Row>[
      if (a.clientName.isNotEmpty) _Row('客户姓名', a.clientName),
      if (a.sex > 0) _Row('性别', sexLabel(a.sex)),
      if (a.birthTime.isNotEmpty) _Row('出生日期', a.birthTime),
      if (a.mobile.isNotEmpty) _Row('手机号', a.mobile),
      if (a.passportNumber.isNotEmpty) _Row('护照号', a.passportNumber),
      if (a.appointTime > 0) _Row('预约时间', _fmtDateTime(a.appointTime)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '预约信息',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      r.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (a.companions.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 12),
            Text(
              '同行人 (${a.companions.length})',
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < a.companions.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == a.companions.length - 1 ? 0 : 10,
                ),
                child: _buildCompanionTile(i + 1, a.companions[i]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompanionTile(int idx, PartTimeTaskCompanion c) {
    final fields = <_Row>[
      if (c.sex > 0) _Row('性别', sexLabel(c.sex)),
      if (c.birthTime.isNotEmpty) _Row('出生日期', c.birthTime),
      if (c.mobile.isNotEmpty) _Row('手机号', c.mobile),
      if (c.passportNumber.isNotEmpty) _Row('护照号', c.passportNumber),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        border: Border.all(color: const Color(0xFFEDEFF2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '同行人 $idx',
                  style: const TextStyle(fontSize: 11, color: _primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.companionName.isEmpty ? '—' : c.companionName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...fields.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        r.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF999999),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 任务地点（医院地址）行，点击打开导航/地图应用
  Widget _buildAddressRow(String address) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMap(address),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.location_on_outlined, size: 16, color: _primary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              address,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: _primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.navigation_outlined, size: 16, color: _primary),
        ],
      ),
    );
  }

  /// 调用系统地图/导航应用打开指定地址（实现见 utils/map_launcher.dart，
  /// 与群聊「医院信息查询」弹窗共用一套 scheme 回退逻辑）
  Future<void> _openMap(String address) => openAddressInMap(context, address);

  Widget _buildHeaderCard(PartTimeTaskDetail d) {
    final statusLabel = PartTimeTaskStatus.label(d.status);
    final (badgeColor, badgeBg) = _statusColor(d.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.hospitalName.isEmpty ? '医院信息缺失' : d.hospitalName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    if (d.hospitalKrName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        d.hospitalKrName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF999999),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (d.hospitalKrAddress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildAddressRow(d.hospitalKrAddress),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [_chip(PartTimeScheduleType.label(d.scheduleType))],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₩${d.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                '/ 小时',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
              if (d.bonus > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '奖金 ₩${d.bonus.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFA8C16),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '任务时间',
            style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.event, size: 16, color: Color(0xFF999999)),
              const SizedBox(width: 4),
              Text(
                _displayDateTime(d.appointTimeText, d.appointTime),
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
            ],
          ),
          if ((d.schedule?.name ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '客户姓名',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 4),
            Text(
              d.schedule!.name,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: _primary)),
    );
  }

  Widget _buildInfoCard({required String title, required List<_Row> rows}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      r.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlockCard({required String title, required String content}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF333333),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _statusColor(int status) {
    switch (status) {
      case PartTimeTaskStatus.waiting:
        return (_primary, const Color(0xFFE6F0FF));
      case PartTimeTaskStatus.accepted:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
      case PartTimeTaskStatus.completed:
        return (_success, const Color(0xFFE6FFEE));
      case PartTimeTaskStatus.canceled:
        return (const Color(0xFF999999), const Color(0xFFF5F5F5));
      default:
        return (const Color(0xFF666666), const Color(0xFFF5F5F5));
    }
  }

  (Color, Color) _auditColor(int auditStatus) {
    switch (auditStatus) {
      case PartTimeAuditStatus.approved:
        return (_success, const Color(0xFFE6FFEE));
      case PartTimeAuditStatus.rejected:
        return (_danger, const Color(0xFFFFECEC));
      case PartTimeAuditStatus.pending:
      default:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
    }
  }

  /// 审核状态卡片（任务已完成后展示，驳回时含原因与重新编辑提示）
  Widget _buildAuditCard(PartTimeTaskDetail d) {
    final (color, bg) = _auditColor(d.auditStatus);
    final rejected = d.auditStatus == PartTimeAuditStatus.rejected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '审核状态',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  PartTimeAuditStatus.label(d.auditStatus),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (rejected) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCCC7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '驳回原因',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCF1322)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.auditRejectReason.isEmpty ? '—' : d.auditRejectReason,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '审核被驳回，请重新编辑任务数据后再次提交。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────── 底部操作按钮 ─────────────────────

  Widget? _buildBottomActions(PartTimeTaskDetail d) {
    // 非兼职用户（群聊跨角色进入）只读：不显示任何操作 / 录入入口
    if (!_canOperate) return null;
    final isAccepter = d.isAcceptedByMe(_currentUserId);
    // ignore: unused_local_variable
    final isCreator = d.isCreatedByMe(_currentUserId); // 取消任务屏蔽期间暂未使用
    // 已完成：进入审核流程。
    // - 审核驳回时，接单人可重新编辑任务数据并再次提交（提交后后端将审核状态由驳回改回待审核）。
    // - 其余审核状态（待审核 / 通过）仅提供只读查看入口。
    if (d.status == PartTimeTaskStatus.completed) {
      if (isAccepter && d.isAuditRejected) {
        return _buildActionBar([
          _primaryButton(text: '编辑任务数据', onTap: () => _openDataEntry(d)),
        ]);
      }
      if (isAccepter && (d.hasOrderDraft || d.hasMaterial)) {
        return _buildActionBar([
          _outlinedButton(
            text: '查看任务数据',
            onTap: () => _openDataEntry(d, readOnly: true),
            color: _primary,
          ),
        ]);
      }
      return null;
    }
    if (d.status == PartTimeTaskStatus.canceled) return null;

    final buttons = <Widget>[];

    // 主操作
    if (d.isHallOpen) {
      buttons.add(_primaryButton(text: '立即接单', onTap: _doAccept));
    } else if (d.status == PartTimeTaskStatus.accepted && isAccepter) {
      // 已到院状态已下线：接单后直接录入任务数据 + 完成任务。
      // 已录入过数据则改为「编辑任务数据」
      final hasData = d.hasOrderDraft || d.hasMaterial;
      buttons.add(
        _outlinedButton(
          text: hasData ? '编辑任务数据' : '录入任务数据',
          onTap: () => _openDataEntry(d),
          color: _primary,
        ),
      );
      buttons.add(
        _primaryButton(
          text: '完成任务',
          onTap: () => _onCompleteTask(d),
          color: _success,
        ),
      );
    }

    // 取消任务功能暂时屏蔽（暂不需要），保留 _doCancel 实现待后续恢复。
    // if ((isAccepter || isCreator) &&
    //     (d.status == PartTimeTaskStatus.waiting ||
    //         d.status == PartTimeTaskStatus.accepted)) {
    //   buttons.add(
    //     _outlinedButton(text: '取消任务', onTap: _doCancel, color: _danger),
    //   );
    // }

    if (buttons.isEmpty) return null;
    return _buildActionBar(buttons);
  }

  Widget _buildActionBar(List<Widget> buttons) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        color: Colors.white,
        child: Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String text,
    required VoidCallback onTap,
    Color color = _primary,
    bool enabled = true,
    String? disabledHint,
  }) {
    // 禁用时按钮置灰，点击仅弹出提示而不触发真实操作
    final effectiveOnTap = enabled
        ? onTap
        : () {
            if (disabledHint != null) _toast(disabledHint);
          };
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: _busy ? null : effectiveOnTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color : const Color(0xFFB0B0B0),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB0B0B0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _outlinedButton({
    required String text,
    required VoidCallback onTap,
    required Color color,
  }) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  _Row(this.label, this.value);
}
