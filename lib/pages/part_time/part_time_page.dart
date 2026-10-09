import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yatai_hub/models/part_time_task.dart';
import 'package:yatai_hub/models/parttime_record.dart';
import 'package:yatai_hub/pages/part_time/part_time_task_detail_page.dart';
import 'package:yatai_hub/pages/part_time/parttime_clock_out_sheet.dart';
import 'package:yatai_hub/pages/chat/chat_page.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/models/chat_target.dart';
import 'package:yatai_hub/services/part_time_task_service.dart';
import 'package:yatai_hub/services/parttime_clock_service.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';

/// 兼职用户主页 —— 两个 Tab：我已接单 / 接单列表
class PartTimePage extends StatefulWidget {
  const PartTimePage({super.key});

  @override
  State<PartTimePage> createState() => PartTimePageState();
}

class PartTimePageState extends State<PartTimePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_HallTabState> _hallKey = GlobalKey<_HallTabState>();
  final GlobalKey<_MyTasksTabState> _myKey = GlobalKey<_MyTasksTabState>();

  // 每日打卡状态
  int? _clockStartedAt;
  bool _clockSubmittedToday = true; // 默认 true，避免加载前按钮闪现
  bool _clockBusy = false;
  StreamSubscription<void>? _clockSub;

  // 当天打卡被驳回（can_edit=true）时进入「修改重交」态：保留原记录用于预填，
  // 并展示驳回原因。此态优先于「开始/结束兼职」。
  ParttimeRecord? _rejectedToday;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadClockState();
    _clockSub = ParttimeClockService().onChanged.listen(
      (_) => _loadClockState(),
    );
  }

  Future<void> _loadClockState() async {
    // 1) 先用本地缓存即时渲染，避免等待网络期间按钮闪烁
    final startedAt = await ParttimeClockService().getStartedAt();
    final submitted = await ParttimeClockService().isSubmittedToday();
    if (!mounted) return;
    setState(() {
      _clockStartedAt = startedAt;
      _clockSubmittedToday = submitted;
    });

    // 2) 拉服务端当天状态校正按钮显隐：本地缓存在卸载重装 / 切号后会失真，
    //    以 clock_status / can_submit 为权威依据。拉取失败则保留本地缓存。
    final today = await ParttimeClockService().fetchTodayStatus();
    if (!mounted || today.errorMessage != null) return;
    // can_edit 仅在「已驳回」时为 true：此时 can_submit 也为 true，需展示「修改重交」
    final rejected = today.record?.canEdit == true ? today.record : null;
    setState(() {
      // 不可再提交（已完成且非驳回）即视为今日已完成，隐藏按钮
      _clockSubmittedToday = !today.canSubmit;
      if (today.isClockedIn && (today.record?.workStartTime ?? 0) > 0) {
        // 服务端「进行中」→ 以服务端上班时间为准展示「结束兼职」
        _clockStartedAt = today.record!.workStartTime;
      } else if (today.hasClock) {
        // 已完成 / 被驳回 → 清掉本地「进行中」开始状态
        _clockStartedAt = null;
      }
      _rejectedToday = rejected;
    });
  }

  /// 开始兼职：调 clock_in 上班打卡（上班时间以服务器时间为准，
  /// 独立于任务状态，直接开始无需确认）。
  Future<void> _onStartClock() async {
    if (_clockBusy || _clockStartedAt != null) return;
    setState(() => _clockBusy = true);
    final r = await ParttimeClockService().clockIn();
    if (!mounted) return;
    setState(() => _clockBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.success ? '上班打卡成功，已开始今日兼职' : (r.message ?? '上班打卡失败')),
      ),
    );
    // clockIn 成功会经 onChanged 触发 _loadClockState 刷新按钮态
  }

  /// 结束兼职：弹表单收集上下班时间/午休/交通费/报销单后调 clock_out 下班打卡
  /// （上班默认 clock_in 时刻、日期锁定当天，下班默认当前时间，均可修改）。
  Future<void> _onEndClock() async {
    if (_clockBusy || _clockStartedAt == null) return;
    final defaultStartAt = DateTime.fromMillisecondsSinceEpoch(
      _clockStartedAt! * 1000,
    );
    final payload = await showParttimeClockOutSheet(
      context,
      defaultStartAt: defaultStartAt,
      lockStartDate: true,
      enableReimburse: true,
    );
    if (payload == null || !mounted) return;
    setState(() => _clockBusy = true);
    final r = await ParttimeClockService().clockOut(
      workStartTime: payload.workStartTime,
      workEndTime: payload.workEndTime,
      hasLunchBreak: payload.hasLunchBreak,
      hasExpense: payload.hasExpense,
      expenseAmount: payload.expenseAmount,
      hasReimburse: payload.hasReimburse,
      reimburseAmount: payload.reimburseAmount,
      voucherUrls: payload.voucherUrls,
      reimburseRemark: payload.reimburseRemark,
    );
    if (!mounted) return;
    setState(() => _clockBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.success ? '下班打卡成功，今日兼职已提交' : (r.message ?? '下班打卡失败')),
      ),
    );
  }

  /// 修改重交：打卡被驳回后，预填原记录重新提交（沿用同一 submit 接口，
  /// 后端按 work_date 命中并重置为待审核）。
  Future<void> _onEditRejectedClock() async {
    final rec = _rejectedToday;
    if (_clockBusy || rec == null) return;
    final payload = await showParttimeClockOutSheet(
      context,
      defaultStartAt: DateTime.fromMillisecondsSinceEpoch(
        rec.workStartTime * 1000,
      ),
      defaultEndAt: DateTime.fromMillisecondsSinceEpoch(rec.workEndTime * 1000),
      initialHasLunchBreak: rec.hasLunchBreak,
      initialHasExpense: rec.hasExpense,
      initialExpenseAmount: rec.hasExpense ? rec.expenseAmount : null,
      title: '修改重交',
      lockDate: true,
    );
    if (payload == null || !mounted) return;
    setState(() => _clockBusy = true);
    final r = await ParttimeClockService().submitClock(
      workStartTime: payload.workStartTime,
      workEndTime: payload.workEndTime,
      hasLunchBreak: payload.hasLunchBreak,
      hasExpense: payload.hasExpense,
      expenseAmount: payload.expenseAmount,
    );
    if (!mounted) return;
    setState(() => _clockBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.success ? '已重新提交，等待审核' : (r.message ?? '提交失败'))),
    );
    // submitClock 成功会经 onChanged 触发 _loadClockState 刷新按钮态
  }

  @override
  void dispose() {
    _tabController.dispose();
    _clockSub?.cancel();
    super.dispose();
  }

  /// 外部点击底栏同 Tab 时滚顶 + 刷新当前 Tab
  void refreshToTop() {
    if (_tabController.index == 0) {
      _myKey.currentState?.refreshToTop();
    } else {
      _hallKey.currentState?.refreshToTop();
    }
  }

  /// 切到指定子 Tab（0=我已接单 / 1=接单列表）
  ///
  /// 推送跳转复用，重复切到当前 Tab 也会触发刷新到顶。
  void switchToTab(int index) {
    if (index < 0 || index >= _tabController.length) return;
    if (_tabController.index == index) {
      refreshToTop();
      return;
    }
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 40,
        title: const Text(
          '兼职',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: SizedBox(
            height: 38,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF709BF7),
              unselectedLabelColor: const Color(0xFF666666),
              indicatorColor: const Color(0xFF709BF7),
              indicatorWeight: 2,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: '我已接单'),
                Tab(text: '接单大厅'),
              ],
            ),
          ),
        ),
      ),
      // 参考素材上传页：Column + Expanded 滚动区 + 贴底操作条。
      // MainPage 启用 extendBody=true，body 传入的 MediaQuery.padding.bottom
      // 已包含 BottomTabbar 高度，按钮容器据此留底部内边距即可紧贴底栏上方。
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MyTasksTab(key: _myKey),
                _HallTab(
                  key: _hallKey,
                  onAccepted: () => _myKey.currentState?.refreshList(),
                ),
              ],
            ),
          ),
          // 上班打卡独立于任务状态：未开始时显示「开始兼职」，手动点击记录
          // 上班时间；已开始显示「结束兼职」，被驳回显示「修改重交」。
          // 当日已提交则整体隐藏（一天最多一次）。
          if (!_clockSubmittedToday)
            _buildClockButton()
          else
            // 打卡条隐藏时补底栏等高占位：MainPage extendBody=true 下 body 会延伸到
            // BottomTabbar 之后，否则列表末尾会被常驻底栏压住、滑不出来。
            SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  /// 底部打卡按钮三态：被驳回=「修改重交」(红，含驳回原因)，已开始兼职=「结束兼职」(橙)，
  /// 未开始=「开始兼职」(蓝)。显隐条件见 build()（当日已提交则整体隐藏）。
  Widget _buildClockButton() {
    final rejected = _rejectedToday;
    // extendBody=true 下 padding.bottom 已含 BottomTabbar 高度，
    // 据此留底部内边距，让操作条正好贴在底栏上方（同素材上传提交按钮）
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final Color bgColor;
    final String label;
    final VoidCallback onTap;
    if (rejected != null) {
      bgColor = const Color(0xFFFF4D4F);
      label = '修改重交';
      onTap = _onEditRejectedClock;
    } else if (_clockStartedAt != null) {
      bgColor = const Color(0xFFFA8C16);
      label = '结束兼职';
      onTap = _onEndClock;
    } else {
      bgColor = const Color(0xFF709BF7);
      label = '开始兼职';
      onTap = _onStartClock;
    }

    // 规格与素材上传「确认提交」按钮保持一致：上下 16 内边距、按钮高 40、
    // 圆角 24、字号 16/w500、loading 24×24、禁用态浅灰
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + bottomPadding,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rejected != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCCC7)),
              ),
              child: Text(
                rejected.rejectReason.isEmpty
                    ? '打卡已被驳回，请修改后重新提交。'
                    : '打卡已被驳回：${rejected.rejectReason}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCF1322),
                  height: 1.4,
                ),
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _clockBusy ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: bgColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: _clockBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 我已接单 Tab —— 接 /v1/parttime_task/my_tasks
class _MyTasksTab extends StatefulWidget {
  const _MyTasksTab({super.key});

  @override
  State<_MyTasksTab> createState() => _MyTasksTabState();
}

class _MyTasksTabState extends State<_MyTasksTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _primary = Color(0xFF709BF7);
  static const int _pageSize = 20;

  /// 状态筛选：null=全部
  static const List<({int? value, String label})> _filters = [
    (value: null, label: '全部'),
    (value: PartTimeTaskStatus.accepted, label: '已接单'),
    (value: PartTimeTaskStatus.completed, label: '已完成'),
    // 已取消单子暂不在列表筛选中展示
  ];

  final ScrollController _scrollController = ScrollController();

  int? _statusFilter;
  List<PartTimeTaskDetail> _list = [];
  int _page = 1;
  bool _loading = false;
  bool _firstLoad = true;
  bool _hasMore = true;

  /// 各任务群聊未读数 {taskId: unreadCount}。
  /// 数据源为列表接口每条任务返回的 unread_comment_count；任意入口查看群聊后
  /// 经 [ParttimeChatService.onTaskRead] 清零，下次列表刷新再与服务端对齐。
  final Map<int, int> _unreadMap = {};

  /// 群聊已读广播订阅：覆盖列表入口 / 任务详情 / 会话列表等所有查看入口
  StreamSubscription<ChatTarget>? _readSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _readSub = ParttimeChatService().onTaskRead.listen((target) {
      if (!mounted) return;
      // 只认任务群：科室群的 task_id 是科室 ID、私聊是会话 ID，都可能与某任务
      // 撞号，不加这层判断会把同号任务的未读红点误清
      if (!target.isTask) return;
      if ((_unreadMap[target.taskId] ?? 0) != 0) {
        setState(() => _unreadMap[target.taskId] = 0);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _readSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && _hasMore) _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    final loadPage = refresh ? 1 : _page;
    setState(() {
      _loading = true;
      if (refresh) _hasMore = true;
    });
    final result = await PartTimeTaskService.getMyTasks(
      page: loadPage,
      pageSize: _pageSize,
      status: _statusFilter,
    );
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _list = result.list;
        _unreadMap.clear();
      } else {
        _list = [..._list, ...result.list];
      }
      // 未读数直接取列表接口返回的 unread_comment_count，省去单独的未读查询
      for (final t in result.list) {
        _unreadMap[t.id] = t.unreadCommentCount;
      }
      _page = loadPage + 1;
      _hasMore = _list.length < result.total;
      _loading = false;
      _firstLoad = false;
    });
    // 退出登录期间在途请求返回的 401（Not authenticated）不再弹提示
    if (result.errorMessage != null && !AuthService().isLoggingOut) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    }
  }

  Future<void> _refresh() => _load(refresh: true);

  /// 供父级在大厅接单成功后调用：原地静默重载列表（不滚动到顶）。
  void refreshList() => _load(refresh: true);

  void refreshToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _load(refresh: true);
  }

  void _onFilterTap(int? value) {
    if (_statusFilter == value) return;
    setState(() {
      _statusFilter = value;
      _firstLoad = true;
      _list = [];
    });
    _load(refresh: true);
  }

  void _openDetail(PartTimeTaskDetail task) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartTimeTaskDetailPage(taskId: task.id),
      ),
    );
    if (changed == true) {
      _load(refresh: true);
    }
  }

  void _openMessageBoard(PartTimeTaskDetail task) {
    // 红点清零由 ParttimeChatService.onTaskRead 统一处理（群聊首屏拉取即触发）
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          taskId: task.id,
          title: task.hospitalName.isEmpty ? '任务群聊' : task.hospitalName,
        ),
      ),
    );
  }

  /// 优先用服务端格式化好的时间文本（已处理时区）；老接口无该字段时回退本地转换。
  String _displayDate(String text, int seconds) {
    if (text.isNotEmpty) return text;
    return _fmtDate(seconds);
  }

  String _fmtDate(int seconds) {
    if (seconds <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  (Color, Color) _statusColor(int status) {
    switch (status) {
      case PartTimeTaskStatus.waiting:
        return (_primary, const Color(0xFFE6F0FF));
      case PartTimeTaskStatus.accepted:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
      case PartTimeTaskStatus.completed:
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case PartTimeTaskStatus.canceled:
        return (const Color(0xFF999999), const Color(0xFFF5F5F5));
      default:
        return (const Color(0xFF666666), const Color(0xFFF5F5F5));
    }
  }

  (Color, Color) _auditColor(int auditStatus) {
    switch (auditStatus) {
      case PartTimeAuditStatus.approved:
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case PartTimeAuditStatus.rejected:
        return (const Color(0xFFFF4D4F), const Color(0xFFFFECEC));
      case PartTimeAuditStatus.pending:
      default:
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  /// 状态筛选行：几个筛选项总宽远小于屏宽，居中排布与上方均分的 TabBar 呼应，
  /// 不在右侧留大片空白。ConstrainedBox(minWidth) 保证项目变多撑满后仍能横滑，
  /// 那时自然退化成从左排起。
  Widget _buildFilterBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 24),
                  _buildFilterChip(_filters[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(({int? value, String label}) f) {
    final selected = _statusFilter == f.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onFilterTap(f.value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _primary : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          f.label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF666666),
            fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_firstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const EmptyStateWidget(
                icon: Icons.assignment_turned_in_outlined,
                message: '暂无相关任务',
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        // 顶部不留白：首张卡片直接接在筛选行下方，否则多出一截空白
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        itemCount: _list.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, idx) {
          if (idx == _list.length) {
            if (_loading && _list.isNotEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!_hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '到底了~',
                    style: TextStyle(color: Color(0xFF999999)),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          return _buildCard(_list[idx]);
        },
      ),
    );
  }

  Widget _buildCard(PartTimeTaskDetail task) {
    final (badgeColor, badgeBg) = _statusColor(task.status);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(task),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.hospitalName.isEmpty ? '医院信息缺失' : task.hospitalName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    PartTimeTaskStatus.label(task.status),
                    style: TextStyle(
                      fontSize: 12,
                      color: badgeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // 任务已完成后展示审核状态徽章
                if (task.showAudit) ...[
                  const SizedBox(width: 6),
                  _buildAuditBadge(task.auditStatus),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    PartTimeScheduleType.label(task.scheduleType),
                    style: const TextStyle(fontSize: 12, color: _primary),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.event, size: 14, color: Color(0xFF999999)),
                const SizedBox(width: 4),
                Text(
                  _displayDate(task.appointTimeText, task.appointTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
            if (task.requireDesc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.requireDesc,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  '报酬',
                  style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
                const SizedBox(width: 4),
                Text(
                  '₩${task.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 2),
                const Text(
                  '/ 小时',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
                if (task.bonus > 0) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '奖金 ₩${task.bonus.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFA8C16),
                        ),
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 10),
            _buildCommentEntry(task),
          ],
        ),
      ),
    );
  }

  /// 审核状态徽章（任务已完成后展示）
  Widget _buildAuditBadge(int auditStatus) {
    final (color, bg) = _auditColor(auditStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        PartTimeAuditStatus.label(auditStatus),
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 卡片内的群聊入口按钮（带未读红点）
  Widget _buildCommentEntry(PartTimeTaskDetail task) {
    final unread = _unreadMap[task.id] ?? 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openMessageBoard(task),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 15, color: _primary),
              const SizedBox(width: 5),
              const Text('群聊', style: TextStyle(fontSize: 12, color: _primary)),
              if (unread > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D4F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 接单列表 Tab —— 接 /v1/parttime_task/hall
class _HallTab extends StatefulWidget {
  const _HallTab({super.key, this.onAccepted});

  /// 接单成功后回调，用于通知父级刷新「我已接单」Tab
  final VoidCallback? onAccepted;

  @override
  State<_HallTab> createState() => _HallTabState();
}

class _HallTabState extends State<_HallTab> with AutomaticKeepAliveClientMixin {
  static const Color _primary = Color(0xFF709BF7);
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();

  List<PartTimeTask> _list = [];
  int _page = 1;
  bool _loading = false;
  bool _firstLoad = true;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && _hasMore) _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    final loadPage = refresh ? 1 : _page;
    setState(() {
      _loading = true;
      if (refresh) _hasMore = true;
    });

    final result = await PartTimeTaskService.getHall(
      page: loadPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _list = result.list;
      } else {
        _list = [..._list, ...result.list];
      }
      _page = loadPage + 1;
      _hasMore = _list.length < result.total;
      _loading = false;
      _firstLoad = false;
    });
    // 退出登录期间在途请求返回的 401（Not authenticated）不再弹提示
    if (result.errorMessage != null && !AuthService().isLoggingOut) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    }
  }

  Future<void> _refresh() => _load(refresh: true);

  void refreshToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _load(refresh: true);
  }

  void _openDetail(PartTimeTask task) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartTimeTaskDetailPage(taskId: task.id),
      ),
    );
    if (changed == true) {
      _load(refresh: true);
      // 大厅里的单子接单后会进入「我已接单」，同步刷新该 Tab，
      // 否则因 keepAlive 缓存，切过去看不到刚接的单。
      widget.onAccepted?.call();
    }
  }

  /// 优先用服务端格式化好的时间文本（已处理时区）；老接口无该字段时回退本地转换。
  String _displayDate(String text, int seconds) {
    if (text.isNotEmpty) return text;
    return _fmtDate(seconds);
  }

  String _fmtDate(int seconds) {
    if (seconds <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_firstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const EmptyStateWidget(
                icon: Icons.inbox_outlined,
                message: '暂无可接的任务',
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        // 接单大厅没有筛选行，列表直接接在 TabBar 下方，顶部要留白（我已接单那边
        // 有筛选行垫着，才把顶部留白去掉）
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _list.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, idx) {
          if (idx == _list.length) return _buildFooter();
          return _buildCard(_list[idx]);
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loading && _list.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('到底了~', style: TextStyle(color: Color(0xFF999999))),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCard(PartTimeTask task) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(task),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.hospitalName.isEmpty ? '医院信息缺失' : task.hospitalName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    PartTimeScheduleType.label(task.scheduleType),
                    style: const TextStyle(fontSize: 12, color: _primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event, size: 14, color: Color(0xFF999999)),
                const SizedBox(width: 4),
                Text(
                  _displayDate(task.appointTimeText, task.appointTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
            if (task.requireDesc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.requireDesc,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  '报酬',
                  style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
                const SizedBox(width: 4),
                Text(
                  '₩${task.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 2),
                const Text(
                  '/ 小时',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
                if (task.bonus > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '奖金 ₩${task.bonus.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFA8C16),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                const Text(
                  '查看详情 ',
                  style: TextStyle(fontSize: 12, color: _primary),
                ),
                const Icon(Icons.chevron_right, size: 16, color: _primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
