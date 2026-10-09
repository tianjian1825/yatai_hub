import 'package:flutter/material.dart';
import 'package:yatai_hub/models/settlement.dart';
import 'package:yatai_hub/pages/part_time/settlement_detail_page.dart';
import 'package:yatai_hub/services/settlement_service.dart';
import 'package:yatai_hub/widgets/empty_state_widget.dart';

/// 兼职结算/提现历史列表页
///
/// 展示即时提现（settle_type=1）与月结（settle_type=2）记录，分页无限滚动。
/// 点击进入结算单明细页。
class SettlementHistoryPage extends StatefulWidget {
  const SettlementHistoryPage({super.key});

  @override
  State<SettlementHistoryPage> createState() => _SettlementHistoryPageState();
}

class _SettlementHistoryPageState extends State<SettlementHistoryPage> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();

  final List<SettlementRecord> _list = [];
  int _page = 1;
  bool _loading = false;
  bool _firstLoad = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
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
    final result = await SettlementService().fetchHistory(
      page: loadPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _list
          ..clear()
          ..addAll(result.list);
      } else {
        _list.addAll(result.list);
      }
      _page = loadPage + 1;
      _hasMore = _list.length < result.total;
      _loading = false;
      _firstLoad = false;
    });
    if (result.errorMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    }
  }

  Future<void> _refresh() => _load(refresh: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '结算记录',
          style: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_firstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 360,
              child: EmptyStateWidget(
                icon: Icons.receipt_long,
                message: '暂无结算记录',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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

  Widget _buildCard(SettlementRecord r) {
    final (fg, bg) = SettlementStatus.color(r.status);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettlementDetailPage(id: r.id)),
        );
      },
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
                    r.settleTypeLabel.isEmpty
                        ? (r.settleType == 2 ? '月结' : '即时提现')
                        : r.settleTypeLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    r.statusLabel,
                    style: TextStyle(fontSize: 12, color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₩${_money(r.amount)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${r.daysCount} 天'
                    '${r.period.isNotEmpty ? ' · ${r.period}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ),
              ],
            ),
            if (r.allowance > 0) ...[
              const SizedBox(height: 4),
              Text(
                '含津贴 ₩${_money(r.allowance)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFA8C16)),
              ),
            ],
            if (r.applyTimeStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '申请时间：${r.applyTimeStr}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
            ],
            if (r.status == SettlementStatus.rejected &&
                r.rejectReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFCCC7)),
                ),
                child: Text(
                  '驳回原因：${r.rejectReason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFCF1322),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _money(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}
