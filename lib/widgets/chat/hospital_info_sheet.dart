import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_query.dart';
import 'package:yatai_hub/services/chat_context_service.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';
import 'package:yatai_hub/widgets/chat/query_sheet_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// 群聊「医院信息查询」底部弹窗
///
/// 数据源 `/v1/kr_hospital/detail`，只展示中文/韩文/英文名称、别名、中文地址、
/// 韩文地址、合作状态（商务敏感节点——返点、财务结算、联系人电话、CRM 账密、
/// 收款码——不取不存不显示）。
///
/// 先本地快照秒显，再网络刷新；无缓存且网络失败时给重试。
Future<void> showHospitalInfoSheet(
  BuildContext context, {
  required int hospitalId,
  String fallbackName = '',
}) {
  return showChatBottomSheet<void>(
    context: context,
    builder: (_) =>
        _HospitalInfoSheet(hospitalId: hospitalId, fallbackName: fallbackName),
  );
}

class _HospitalInfoSheet extends StatefulWidget {
  final int hospitalId;
  final String fallbackName;

  const _HospitalInfoSheet({
    required this.hospitalId,
    required this.fallbackName,
  });

  @override
  State<_HospitalInfoSheet> createState() => _HospitalInfoSheetState();
}

class _HospitalInfoSheetState extends State<_HospitalInfoSheet> {
  final ChatContextService _service = ChatContextService();

  KrHospitalBrief? _brief;
  bool _loading = true;
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
    // 本地快照先显示，避免弹窗空转
    final cached = await _service.localHospital(widget.hospitalId);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _brief = cached;
        _loading = false;
      });
    }
    final fresh = await _service.refreshHospital(widget.hospitalId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (fresh != null) {
        _brief = fresh;
      } else if (_brief == null) {
        _error = '医院信息获取失败，请检查网络后重试';
      }
    });
  }

  Future<void> _openUrl(String url) async {
    var target = url.trim();
    if (target.isEmpty) return;
    if (!target.startsWith('http')) target = 'https://$target';
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        showOverlayToast(context, '无法打开链接', icon: Icons.error_outline);
      }
    }
  }

  String get _title {
    final name = _brief?.nameCn ?? '';
    if (name.isNotEmpty) return name;
    return widget.fallbackName.trim().isEmpty
        ? '医院信息'
        : widget.fallbackName.trim();
  }

  @override
  Widget build(BuildContext context) {
    final url = _brief?.url ?? '';
    // 内容通常只有 6 行，用自适应高度避免大片空白；超长时封顶到 70% 屏高
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChatSheetHandle(),
            QuerySheetHeader(
              title: _title,
              trailing: url.isEmpty
                  ? null
                  : TextButton.icon(
                      onPressed: () => _openUrl(url),
                      icon: const Icon(Icons.language, size: 16),
                      label: const Text('官网'),
                    ),
            ),
            const Divider(height: 1),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_brief == null && _loading) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_brief == null) {
      return SizedBox(
        height: 180,
        child: QuerySheetError(message: _error ?? '暂无医院信息', onRetry: _load),
      );
    }
    final h = _brief!;
    final rows = <Widget>[
      if (h.nameCn.isNotEmpty) QueryInfoRow(label: '中文名称', value: h.nameCn),
      if (h.nameKr.isNotEmpty) QueryInfoRow(label: '韩文名称', value: h.nameKr),
      if (h.nameEn.isNotEmpty) QueryInfoRow(label: '英文名称', value: h.nameEn),
      if (h.alias.isNotEmpty) QueryInfoRow(label: '别名', value: h.alias),
      if (h.addressCn.isNotEmpty)
        QueryInfoRow(label: '中文地址', value: h.addressCn, isAddress: true),
      if (h.addressKr.isNotEmpty)
        QueryInfoRow(label: '韩文地址', value: h.addressKr, isAddress: true),
      // 合作状态是枚举值，复制没意义
      if (h.statusLabel.isNotEmpty)
        QueryInfoRow(label: '合作状态', value: h.statusLabel, copyable: false),
    ];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        QuerySection(
          title: '基本信息',
          copyPayload: _copyPayload(h),
          children: rows.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '该医院暂无可展示的信息',
                      style: TextStyle(fontSize: 13, color: kQuerySheetLabel),
                    ),
                  ),
                ]
              : rows,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 4),
          child: Text(
            '点击地址可直接导航，点复制图标或长按可复制',
            style: TextStyle(fontSize: 11, color: kQuerySheetLabel),
          ),
        ),
      ],
    );
  }

  String _copyPayload(KrHospitalBrief h) {
    final lines = <String>[
      if (h.nameCn.isNotEmpty) '中文名称：${h.nameCn}',
      if (h.nameKr.isNotEmpty) '韩文名称：${h.nameKr}',
      if (h.nameEn.isNotEmpty) '英文名称：${h.nameEn}',
      if (h.alias.isNotEmpty) '别名：${h.alias}',
      if (h.addressCn.isNotEmpty) '中文地址：${h.addressCn}',
      if (h.addressKr.isNotEmpty) '韩文地址：${h.addressKr}',
      if (h.statusLabel.isNotEmpty) '合作状态：${h.statusLabel}',
    ];
    return lines.join('\n');
  }
}
