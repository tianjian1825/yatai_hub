import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yatai_hub/services/oss_api.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';

/// 结束兼职提交载荷
class ParttimeClockOutPayload {
  final int workStartTime; // unix 秒
  final int workEndTime;
  final bool hasLunchBreak; // 是否午休
  final bool hasExpense;
  final int? expenseAmount; // 3000 / 5000 / 8000（韩币），hasExpense=false 时为 null
  final bool hasReimburse; // 是否随卡提交独立报销单（与交通费无关）
  final int? reimburseAmount; // 报销金额（韩币，100 的倍数），hasReimburse=false 时为 null
  final List<String>? voucherUrls; // 报销凭证图片 URL（≤9 张，选填）
  final String? reimburseRemark; // 报销备注（≤500 字，选填）

  ParttimeClockOutPayload({
    required this.workStartTime,
    required this.workEndTime,
    required this.hasLunchBreak,
    required this.hasExpense,
    this.expenseAmount,
    this.hasReimburse = false,
    this.reimburseAmount,
    this.voucherUrls,
    this.reimburseRemark,
  });
}

/// 弹出「结束兼职 / 修改重交」底部表单。
///
/// 默认上班时间 = [defaultStartAt]，下班时间 = [defaultEndAt]（缺省为 now）；
/// 用户可点行编辑。午休默认按 [initialHasLunchBreak] 预填（编辑时回填原值），
/// 未传则未选，必填。交通费默认按 [initialHasExpense] / [initialExpenseAmount]
/// 预填（编辑被驳回打卡时回填原值），未传则「否」；选「是」后强制选 3000 / 5000 / 8000。
/// [title] / [submitText] 供编辑场景覆盖文案。
/// [lockDate]=true 时（重新编辑打卡）上、下班日期均固定为原打卡日，仅可调整时分。
/// [lockStartDate]=true 时（正常结束兼职）仅锁定「上班时间」日期（打卡当天，
/// 不显示提示文字），仅可调整其时分；下班时间仍可自由选择日期与时分。
/// [enableReimburse]=true 时展示「报销单」块（默认关闭）：与交通费互相独立，
/// 可随卡提交金额（100 的倍数）+ 凭证图片（≤9 张，选填）+ 备注（≤500 字，选填）；
/// 仅正常下班打卡场景开启，驳回修改重交不带报销（后端不动已有报销单）。
Future<ParttimeClockOutPayload?> showParttimeClockOutSheet(
  BuildContext context, {
  required DateTime defaultStartAt,
  DateTime? defaultEndAt,
  bool? initialHasLunchBreak,
  bool? initialHasExpense,
  int? initialExpenseAmount,
  String title = '结束兼职',
  String submitText = '确认提交',
  bool lockDate = false,
  bool lockStartDate = false,
  bool enableReimburse = false,
}) {
  return showModalBottomSheet<ParttimeClockOutPayload>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (_) => _ParttimeClockOutSheet(
      defaultStartAt: defaultStartAt,
      defaultEndAt: defaultEndAt,
      initialHasLunchBreak: initialHasLunchBreak,
      initialHasExpense: initialHasExpense,
      initialExpenseAmount: initialExpenseAmount,
      title: title,
      submitText: submitText,
      lockDate: lockDate,
      lockStartDate: lockStartDate,
      enableReimburse: enableReimburse,
    ),
  );
}

class _ParttimeClockOutSheet extends StatefulWidget {
  final DateTime defaultStartAt;
  final DateTime? defaultEndAt;
  final bool? initialHasLunchBreak;
  final bool? initialHasExpense;
  final int? initialExpenseAmount;
  final String title;
  final String submitText;
  final bool lockDate;
  final bool lockStartDate;
  final bool enableReimburse;
  const _ParttimeClockOutSheet({
    required this.defaultStartAt,
    this.defaultEndAt,
    this.initialHasLunchBreak,
    this.initialHasExpense,
    this.initialExpenseAmount,
    required this.title,
    required this.submitText,
    this.lockDate = false,
    this.lockStartDate = false,
    this.enableReimburse = false,
  });

  @override
  State<_ParttimeClockOutSheet> createState() => _ParttimeClockOutSheetState();
}

class _ParttimeClockOutSheetState extends State<_ParttimeClockOutSheet> {
  static const Color _primary = Color(0xFF709BF7);
  static const Color _danger = Color(0xFFFF4D4F);
  static const Color _border = Color(0xFFE5E5E5);
  static const List<int> _expenseOptions = [3000, 5000, 8000];

  static const int _maxVouchers = 9;

  late DateTime _startAt;
  late DateTime _endAt;
  bool? _hasLunchBreak; // null=未选
  bool? _hasExpense; // null=未选
  int? _expenseAmount;
  // ── 报销单块（仅 enableReimburse 时展示，非必选默认「否」）──
  bool _hasReimburse = false;
  final TextEditingController _reimburseAmountCtrl = TextEditingController();
  final TextEditingController _reimburseRemarkCtrl = TextEditingController();
  final List<_VoucherItem> _vouchers = [];

  @override
  void initState() {
    super.initState();
    _startAt = widget.defaultStartAt;
    _endAt = widget.defaultEndAt ?? DateTime.now();
    _hasLunchBreak = widget.initialHasLunchBreak;
    _hasExpense = widget.initialHasExpense;
    _expenseAmount = widget.initialHasExpense == true
        ? widget.initialExpenseAmount
        : null;
  }

  @override
  void dispose() {
    _reimburseAmountCtrl.dispose();
    _reimburseRemarkCtrl.dispose();
    super.dispose();
  }

  // ───────────────────── 时间选择 ─────────────────────

  Future<void> _pickDateTime({required bool isStart}) async {
    // 下班时间的初始值不能早于上班时间，否则会与 minimumDate 冲突触发断言
    final initial = isStart
        ? _startAt
        : (_endAt.isBefore(_startAt) ? _startAt : _endAt);
    var current = initial;
    DateTime? result;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () {
                      result = current;
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoDatePicker(
                // 日期锁定时仅允许调整时分：
                // - lockDate：上、下班日期均锁定（重新编辑打卡）
                // - lockStartDate：仅上班时间日期锁定（正常结束兼职）
                mode: (widget.lockDate || (isStart && widget.lockStartDate))
                    ? CupertinoDatePickerMode.time
                    : CupertinoDatePickerMode.dateAndTime,
                initialDateTime: initial,
                // 下班时间不得早于上班时间（日期 + 时分），从选择器层面拦截
                minimumDate: isStart ? null : _startAt,
                use24hFormat: true,
                onDateTimeChanged: (dt) => current = dt,
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isStart) {
        _startAt = result!;
      } else {
        _endAt = result!;
      }
    });
  }

  String _fmt(DateTime dt) {
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  // ───────────────────── 提交 ─────────────────────

  void _toast(String msg) {
    if (!mounted) return;
    showOverlayToast(context, msg, icon: Icons.info_outline);
  }

  void _submit() {
    if (!_endAt.isAfter(_startAt)) {
      _toast('下班时间需晚于上班时间');
      return;
    }
    if (_hasLunchBreak == null) {
      _toast('请选择是否午休');
      return;
    }
    if (_hasExpense == null) {
      _toast('请选择是否产生交通费');
      return;
    }
    if (_hasExpense == true && _expenseAmount == null) {
      _toast('请选择交通费金额');
      return;
    }
    final hasReimburse = widget.enableReimburse && _hasReimburse;
    int? reimburseAmount;
    if (hasReimburse) {
      reimburseAmount = int.tryParse(_reimburseAmountCtrl.text.trim());
      if (reimburseAmount == null || reimburseAmount <= 0) {
        _toast('请输入报销金额');
        return;
      }
      if (reimburseAmount % 100 != 0) {
        _toast('报销金额须为 100 的倍数');
        return;
      }
      if (_vouchers.any((v) => v.uploading)) {
        _toast('凭证上传中，请稍候');
        return;
      }
    }
    final voucherUrls = hasReimburse
        ? _vouchers
              .map((v) => v.url)
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];
    final remark = _reimburseRemarkCtrl.text.trim();
    Navigator.of(context).pop(
      ParttimeClockOutPayload(
        workStartTime: _startAt.millisecondsSinceEpoch ~/ 1000,
        workEndTime: _endAt.millisecondsSinceEpoch ~/ 1000,
        hasLunchBreak: _hasLunchBreak!,
        hasExpense: _hasExpense!,
        expenseAmount: _hasExpense == true ? _expenseAmount : null,
        hasReimburse: hasReimburse,
        reimburseAmount: hasReimburse ? reimburseAmount : null,
        voucherUrls: hasReimburse && voucherUrls.isNotEmpty
            ? voucherUrls
            : null,
        reimburseRemark: hasReimburse && remark.isNotEmpty ? remark : null,
      ),
    );
  }

  // ───────────────────── 报销凭证 ─────────────────────

  Future<void> _addVoucher() async {
    final remaining = _maxVouchers - _vouchers.length;
    if (remaining <= 0) {
      _toast('凭证图片最多上传$_maxVouchers张');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // 拍照单张，相册多选（一次最多补满剩余额度）
    final picker = ImagePicker();
    List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot = await picker.pickImage(source: source, imageQuality: 85);
      picked = shot == null ? const [] : [shot];
    } else {
      picked = await picker.pickMultiImage(imageQuality: 85);
    }
    if (picked.isEmpty || !mounted) return;
    if (picked.length > remaining) {
      picked = picked.sublist(0, remaining);
      _toast('凭证图片最多上传$_maxVouchers张，超出部分已忽略');
    }
    for (final x in picked) {
      _uploadVoucher(x); // 各自并发上传、独立维护上传中状态
    }
  }

  Future<void> _uploadVoucher(XFile picked) async {
    final item = _VoucherItem(file: File(picked.path));
    setState(() => _vouchers.add(item));
    try {
      final signData = await OssApi.getDirectUploadSign(picked.name);
      final url = signData == null
          ? null
          : await OssApi.uploadToOss(file: item.file, signData: signData);
      if (!mounted) return;
      // 上传期间被删除则丢弃结果
      if (!_vouchers.contains(item)) return;
      setState(() {
        if (url == null) {
          _vouchers.remove(item);
        } else {
          item.url = url;
          item.uploading = false;
        }
      });
      if (url == null) _toast('凭证上传失败，请重试');
    } catch (_) {
      if (!mounted || !_vouchers.contains(item)) return;
      setState(() => _vouchers.remove(item));
      _toast('凭证上传失败，请重试');
    }
  }

  // ───────────────────── Build ─────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.86;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('工作时间', required: true),
                    if (widget.lockDate) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '打卡日期不可修改，仅可调整上下班时间',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF999999),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _timeRow(
                      '上班时间',
                      _fmt(_startAt),
                      onTap: () => _pickDateTime(isStart: true),
                    ),
                    const SizedBox(height: 10),
                    _timeRow(
                      '下班时间',
                      _fmt(_endAt),
                      onTap: () => _pickDateTime(isStart: false),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('是否午休', required: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _yesNoChip(
                          '是',
                          true,
                          groupValue: _hasLunchBreak,
                          onSelect: (v) => setState(() => _hasLunchBreak = v),
                        ),
                        const SizedBox(width: 10),
                        _yesNoChip(
                          '否',
                          false,
                          groupValue: _hasLunchBreak,
                          onSelect: (v) => setState(() => _hasLunchBreak = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('是否产生交通费', required: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _yesNoChip(
                          '是',
                          true,
                          groupValue: _hasExpense,
                          onSelect: (v) => setState(() {
                            _hasExpense = v;
                            if (!v) _expenseAmount = null;
                          }),
                        ),
                        const SizedBox(width: 10),
                        _yesNoChip(
                          '否',
                          false,
                          groupValue: _hasExpense,
                          onSelect: (v) => setState(() {
                            _hasExpense = v;
                            if (!v) _expenseAmount = null;
                          }),
                        ),
                      ],
                    ),
                    if (_hasExpense == true) ...[
                      const SizedBox(height: 16),
                      _sectionTitle('交通费金额', required: true),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var i = 0; i < _expenseOptions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            _amountChip(_expenseOptions[i]),
                          ],
                        ],
                      ),
                    ],
                    if (widget.enableReimburse) ..._buildReimburseSection(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// 报销单块：开关 + 金额（100 的倍数）+ 凭证（≤9 张，选填）+ 备注（选填）
  List<Widget> _buildReimburseSection() {
    return [
      const SizedBox(height: 20),
      _sectionTitle('是否提交报销单'),
      const SizedBox(height: 8),
      Row(
        children: [
          _yesNoChip(
            '是',
            true,
            groupValue: _hasReimburse,
            onSelect: (v) => setState(() => _hasReimburse = v),
          ),
          const SizedBox(width: 10),
          _yesNoChip(
            '否',
            false,
            groupValue: _hasReimburse,
            onSelect: (v) => setState(() => _hasReimburse = v),
          ),
        ],
      ),
      if (_hasReimburse) ...[
        const SizedBox(height: 16),
        _sectionTitle('报销金额', required: true),
        const SizedBox(height: 8),
        TextField(
          controller: _reimburseAmountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            prefixText: '₩ ',
            hintText: '请输入报销金额（100 的倍数）',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B0B0)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('报销凭证（最多$_maxVouchers张，选填）'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in _vouchers) _voucherThumb(v),
            if (_vouchers.length < _maxVouchers) _addVoucherButton(),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('报销备注（选填）'),
        const SizedBox(height: 8),
        TextField(
          controller: _reimburseRemarkCtrl,
          maxLength: 500,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            hintText: '请填写报销说明',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B0B0)),
            isDense: true,
            counterStyle: const TextStyle(
              fontSize: 11,
              color: Color(0xFF999999),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _voucherThumb(_VoucherItem item) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              item.file,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          if (item.uploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => setState(() => _vouchers.remove(item)),
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addVoucherButton() {
    return GestureDetector(
      onTap: _addVoucher,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.add, size: 24, color: Color(0xFFB0B0B0)),
      ),
    );
  }

  Widget _buildHeader() => SizedBox(
    height: 48,
    // 撑满整行，否则 Stack 收缩到标题文字宽度，关闭按钮会贴在文字右侧
    width: double.infinity,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        Positioned(
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF999999)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String text, {bool required = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (required)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Text('*', style: TextStyle(color: _danger, fontSize: 14)),
          ),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  /// [onTap] 为空时为只读展示（无箭头不可点）
  Widget _timeRow(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFB0B0B0),
              ),
          ],
        ),
      ),
    );
  }

  Widget _yesNoChip(
    String label,
    bool value, {
    required bool? groupValue,
    required ValueChanged<bool> onSelect,
  }) {
    final selected = groupValue == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.white,
          border: Border.all(color: selected ? _primary : _border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _amountChip(int amount) {
    final selected = _expenseAmount == amount;
    return GestureDetector(
      onTap: () => setState(() => _expenseAmount = amount),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.white,
          border: Border.all(color: selected ? _primary : _border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '₩ $amount',
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    side: const BorderSide(color: _border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('取消'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.submitText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 报销凭证：本地文件 + OSS 上传态。上传成功前 [url] 为空。
class _VoucherItem {
  final File file;
  String? url;
  bool uploading = true;

  _VoucherItem({required this.file});
}
