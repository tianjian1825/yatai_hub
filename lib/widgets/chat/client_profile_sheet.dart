import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_query.dart';
import 'package:yatai_hub/services/chat_context_service.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/query_sheet_widgets.dart';

/// 群聊「客户资料查询」底部弹窗
///
/// 只读聚合，五个区块与客服系统详情页（kf_service `CustomerDetailPage`）同源：
/// 客户资料 `/v1/kefu/client/detail` + 派单医院 `/v1/kefu/order/list`
/// + 档案情况 `/v1/archives/list` + 预约情况 `/v1/appoint/list`
/// + 成交（消费）`/v1/schedule/paylist`（client_id + archives_id=0）。
///
/// 按需求不展示任何联系方式（手机号 / WhatsApp / LINE / 微信等），也不放
/// 「录成交 / 查看详情」这类操作入口。
Future<void> showClientProfileSheet(
  BuildContext context, {
  required int clientId,
}) {
  return showChatBottomSheet<void>(
    context: context,
    builder: (_) => _ClientProfileSheet(clientId: clientId),
  );
}

class _ClientProfileSheet extends StatefulWidget {
  final int clientId;

  const _ClientProfileSheet({required this.clientId});

  @override
  State<_ClientProfileSheet> createState() => _ClientProfileSheetState();
}

class _ClientProfileSheetState extends State<_ClientProfileSheet> {
  final ChatContextService _service = ChatContextService();

  ClientProfile? _profile;
  bool _loading = true;
  bool _expandArchives = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await _service.localClient(widget.clientId);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _profile = cached;
        _loading = false;
      });
    }
    final fresh = await _service.refreshClient(widget.clientId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (fresh != null) {
        _profile = fresh;
      } else if (_profile == null) {
        _error = '客户资料获取失败，请检查网络后重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const ChatSheetHandle(),
            QuerySheetHeader(
              title: _headerTitle(),
              trailing: _loading && _profile != null
                  ? const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  String _headerTitle() {
    final name = _profile?.basic?.name ?? '';
    return name.isEmpty ? '客户资料查询' : '客户资料 · $name';
  }

  Widget _buildBody() {
    if (_profile == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _profile;
    if (p == null) {
      return QuerySheetError(message: _error ?? '暂无客户资料', onRetry: _load);
    }
    return Container(
      color: const Color(0xFFF7F8FA),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildBasicSection(p),
          if (p.dispatches.isNotEmpty) _buildDispatchSection(p),
          if (p.archives.isNotEmpty) _buildArchiveSection(p),
          if (p.appointments.isNotEmpty) _buildAppointmentSection(p),
          if (p.deals.isNotEmpty) _buildDealSection(p),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              '长按任意行或点复制图标可复制',
              style: TextStyle(fontSize: 11, color: kQuerySheetLabel),
            ),
          ),
        ],
      ),
    );
  }

  // ——————————————————— 客户资料 ———————————————————

  Widget _buildBasicSection(ClientProfile p) {
    final b = p.basic;
    if (b == null) {
      return QuerySection(
        title: '客户资料',
        children: [
          QueryInfoRow(label: '客户 ID', value: '${p.clientId}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '未取到客户基础资料（可能无查看权限）',
              style: TextStyle(fontSize: 13, color: kQuerySheetLabel),
            ),
          ),
        ],
      );
    }
    final rows = <({String label, String value})>[
      (label: '客户 ID', value: '${b.clientId > 0 ? b.clientId : p.clientId}'),
      (label: '客户姓名', value: b.name),
      (label: '客服', value: b.kefuName),
      (label: '来源类型', value: b.fromTypeName),
      (label: '来源详情', value: b.fromTypeValue),
      (label: '编辑', value: b.editName),
      (label: '注册时间', value: b.registerTimeText),
    ].where((e) => e.value.isNotEmpty).toList();
    return QuerySection(
      title: '客户资料',
      copyPayload: rows.map((e) => '${e.label}：${e.value}').join('\n'),
      children: [
        for (final r in rows) QueryInfoRow(label: r.label, value: r.value),
      ],
    );
  }

  // ——————————————————— 派单医院 ———————————————————

  Widget _buildDispatchSection(ClientProfile p) {
    return QuerySection(
      title: '派单医院 (${p.dispatches.length})',
      copyPayload: p.dispatches.map(_dispatchText).join('\n'),
      children: [
        for (final d in p.dispatches)
          QueryInfoRow(label: '医院', value: _dispatchText(d)),
      ],
    );
  }

  String _dispatchText(ClientDispatchItem d) {
    final name = d.hospitalName.isEmpty ? '医院${d.hospitalId}' : d.hospitalName;
    return d.hospitalId > 0 ? '$name (${d.hospitalId})' : name;
  }

  // ——————————————————— 档案情况 ———————————————————

  Widget _buildArchiveSection(ClientProfile p) {
    final all = p.archives;
    final shown = _expandArchives ? all : all.take(1).toList();
    return QuerySection(
      title: '档案情况 (${all.length})',
      copyPayload: all.map(_archiveText).join('\n\n'),
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 2 : 10, bottom: 2),
            child: Text(
              i == 0 ? '最新档案信息' : '档案 ${i + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E1E1E),
              ),
            ),
          ),
          ..._archiveRows(shown[i]),
        ],
        if (all.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expandArchives = !_expandArchives),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2, right: 8),
                child: Text(
                  _expandArchives ? '收起其余档案' : '展开其余 ${all.length - 1} 份档案',
                  style: const TextStyle(
                    fontSize: 12,
                    color: kQuerySheetPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _archiveRows(ClientArchiveItem a) {
    final rows = <({String label, String value})>[
      (label: '档案 ID', value: a.archivesId > 0 ? '${a.archivesId}' : ''),
      (label: '姓名', value: a.name),
      (label: '性别', value: a.genderText),
      (label: '赴韩时间', value: a.goTime),
      (label: '身份', value: a.identity),
      (label: '出生日期', value: a.birthTime),
      (label: '国籍', value: a.nationalityText),
    ].where((e) => e.value.isNotEmpty).toList();
    return [for (final r in rows) QueryInfoRow(label: r.label, value: r.value)];
  }

  String _archiveText(ClientArchiveItem a) {
    final lines = <String>[
      if (a.archivesId > 0) '档案 ID：${a.archivesId}',
      if (a.name.isNotEmpty) '姓名：${a.name}',
      if (a.genderText.isNotEmpty) '性别：${a.genderText}',
      if (a.goTime.isNotEmpty) '赴韩时间：${a.goTime}',
      if (a.identity.isNotEmpty) '身份：${a.identity}',
      if (a.birthTime.isNotEmpty) '出生日期：${a.birthTime}',
      if (a.nationalityText.isNotEmpty) '国籍：${a.nationalityText}',
    ];
    return lines.join('\n');
  }

  // ——————————————————— 预约情况 ———————————————————

  Widget _buildAppointmentSection(ClientProfile p) {
    return QuerySection(
      title: '预约情况 (${p.appointments.length})',
      copyPayload: p.appointments.map(_appointmentText).join('\n\n'),
      children: [
        for (var i = 0; i < p.appointments.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildAppointmentStatus(p.appointments[i]),
          ..._appointmentRows(p.appointments[i]),
        ],
      ],
    );
  }

  Widget _buildAppointmentStatus(ClientAppointmentItem a) {
    final text = a.statusText.isEmpty ? '预约' : a.statusText;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor(text),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E1E1E),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String statusText) {
    if (statusText.contains('取消') ||
        statusText.contains('失败') ||
        statusText.contains('无效')) {
      return const Color(0xFFFF4D4F);
    }
    if (statusText.contains('成功') || statusText.contains('到院')) {
      return const Color(0xFF34C759);
    }
    return const Color(0xFFFF9800);
  }

  /// 医院地址 / 韩文名称 / 韩文地址 `/v1/appoint/list` 不返回，且不为此额外
  /// 打医院详情接口——需要看地址走菜单里的「医院信息查询」。
  List<Widget> _appointmentRows(ClientAppointmentItem a) {
    final rows = <({String label, String value})>[
      (label: '医院', value: _appointHospitalText(a)),
      (label: '预约时间', value: a.appointTimeText),
      (label: '客服确认到院', value: a.arriveText),
    ].where((e) => e.value.isNotEmpty).toList();
    return [for (final r in rows) QueryInfoRow(label: r.label, value: r.value)];
  }

  String _appointHospitalText(ClientAppointmentItem a) {
    final name = a.hospitalName.isEmpty ? '医院${a.hospitalId}' : a.hospitalName;
    return a.hospitalId > 0 ? '$name (${a.hospitalId})' : name;
  }

  String _appointmentText(ClientAppointmentItem a) {
    final lines = <String>[
      if (a.statusText.isNotEmpty) a.statusText,
      '医院：${_appointHospitalText(a)}',
      if (a.appointTimeText.isNotEmpty) '预约时间：${a.appointTimeText}',
      '客服确认到院：${a.arriveText}',
    ];
    return lines.join('\n');
  }

  // ——————————————————— 成交（消费）情况 ———————————————————

  Widget _buildDealSection(ClientProfile p) {
    return QuerySection(
      title: '成交情况 (${p.deals.length})',
      copyPayload: p.deals.map(_dealText).join('\n\n'),
      children: [
        for (var i = 0; i < p.deals.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 2 : 10, bottom: 2),
            child: Text(
              '成交 ${i + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E1E1E),
              ),
            ),
          ),
          ..._dealRows(p.deals[i]),
        ],
      ],
    );
  }

  List<Widget> _dealRows(ClientDealItem d) {
    final rows = <({String label, String value})>[
      (label: '手术医院', value: d.hospitalName),
      (label: '手术时间', value: d.operationTime),
      (label: '客户名称', value: d.clientName),
      (label: '手术项目', value: d.projectName),
      (label: '手术金额', value: _money(d.amount)),
      (label: '实收金额', value: _money(d.receivedAmount)),
      (label: '备注', value: d.remark),
    ].where((e) => e.value.isNotEmpty).toList();
    return [for (final r in rows) QueryInfoRow(label: r.label, value: r.value)];
  }

  /// 金额（韩元）。0 也照实展示——录单确实可能为 0 或负数（退款）
  String _money(double v) => '${v.toStringAsFixed(2)} (韩币)';

  String _dealText(ClientDealItem d) {
    final lines = <String>[
      if (d.hospitalName.isNotEmpty) '手术医院：${d.hospitalName}',
      if (d.operationTime.isNotEmpty) '手术时间：${d.operationTime}',
      if (d.clientName.isNotEmpty) '客户名称：${d.clientName}',
      if (d.projectName.isNotEmpty) '手术项目：${d.projectName}',
      '手术金额：${_money(d.amount)}',
      '实收金额：${_money(d.receivedAmount)}',
      if (d.remark.isNotEmpty) '备注：${d.remark}',
    ];
    return lines.join('\n');
  }
}
