import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yatai_hub/services/oss_api.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';

/// 报销单编辑提交载荷
class ParttimeExpenseEditPayload {
  final int amount; // 报销金额（韩币，100 的倍数）
  final List<String> voucherUrls; // 凭证图片 URL（1~9 张，save 接口必填）
  final String? remark; // 备注（≤500 字，选填）

  ParttimeExpenseEditPayload({
    required this.amount,
    required this.voucherUrls,
    this.remark,
  });
}

/// 弹出「编辑 / 修改重提报销单」底部表单（打卡详情页报销单卡片入口）。
///
/// 预填已有报销单的金额 / 凭证（网络图）/ 备注；凭证可删除、可继续
/// 拍照或相册多选补充（OSS 直传），与下班打卡弹窗的报销块交互一致。
/// 差异：save 接口凭证必填（至少 1 张）。返回载荷由调用方提交
/// /v1/parttime_expense/save。
Future<ParttimeExpenseEditPayload?> showParttimeExpenseEditSheet(
  BuildContext context, {
  required int initialAmount,
  List<String> initialVoucherUrls = const [],
  String initialRemark = '',
  String title = '编辑报销单',
  String submitText = '确认提交',
}) {
  return showModalBottomSheet<ParttimeExpenseEditPayload>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (_) => _ParttimeExpenseEditSheet(
      initialAmount: initialAmount,
      initialVoucherUrls: initialVoucherUrls,
      initialRemark: initialRemark,
      title: title,
      submitText: submitText,
    ),
  );
}

class _ParttimeExpenseEditSheet extends StatefulWidget {
  final int initialAmount;
  final List<String> initialVoucherUrls;
  final String initialRemark;
  final String title;
  final String submitText;
  const _ParttimeExpenseEditSheet({
    required this.initialAmount,
    required this.initialVoucherUrls,
    required this.initialRemark,
    required this.title,
    required this.submitText,
  });

  @override
  State<_ParttimeExpenseEditSheet> createState() =>
      _ParttimeExpenseEditSheetState();
}

class _ParttimeExpenseEditSheetState extends State<_ParttimeExpenseEditSheet> {
  static const Color _primary = Color(0xFF709BF7);
  static const Color _danger = Color(0xFFFF4D4F);
  static const Color _border = Color(0xFFE5E5E5);
  static const int _maxVouchers = 9;

  late final TextEditingController _amountCtrl = TextEditingController(
    text: widget.initialAmount > 0 ? '${widget.initialAmount}' : '',
  );
  late final TextEditingController _remarkCtrl = TextEditingController(
    text: widget.initialRemark,
  );
  late final List<_VoucherItem> _vouchers = [
    for (final url in widget.initialVoucherUrls) _VoucherItem.remote(url),
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    showOverlayToast(context, msg, icon: Icons.info_outline);
  }

  void _submit() {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _toast('请输入报销金额');
      return;
    }
    if (amount % 100 != 0) {
      _toast('报销金额须为 100 的倍数');
      return;
    }
    if (_vouchers.any((v) => v.uploading)) {
      _toast('凭证上传中，请稍候');
      return;
    }
    final voucherUrls = _vouchers
        .map((v) => v.url)
        .whereType<String>()
        .toList(growable: false);
    if (voucherUrls.isEmpty) {
      _toast('请上传报销凭证');
      return;
    }
    final remark = _remarkCtrl.text.trim();
    Navigator.of(context).pop(
      ParttimeExpenseEditPayload(
        amount: amount,
        voucherUrls: voucherUrls,
        remark: remark.isNotEmpty ? remark : null,
      ),
    );
  }

  // ───────────────────── 凭证选择 / 上传 ─────────────────────

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
    final item = _VoucherItem.local(File(picked.path));
    setState(() => _vouchers.add(item));
    try {
      final signData = await OssApi.getDirectUploadSign(picked.name);
      final url = signData == null
          ? null
          : await OssApi.uploadToOss(file: item.file!, signData: signData);
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
                    _sectionTitle('报销金额', required: true),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                      ),
                      decoration: InputDecoration(
                        prefixText: '₩ ',
                        hintText: '请输入报销金额（100 的倍数）',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB0B0B0),
                        ),
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
                    _sectionTitle('报销凭证（最多$_maxVouchers张）', required: true),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final v in _vouchers) _voucherThumb(v),
                        if (_vouchers.length < _maxVouchers)
                          _addVoucherButton(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('报销备注（选填）'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarkCtrl,
                      maxLength: 500,
                      maxLines: 3,
                      minLines: 2,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                      ),
                      decoration: InputDecoration(
                        hintText: '请填写报销说明',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB0B0B0),
                        ),
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

  Widget _buildHeader() => SizedBox(
    height: 48,
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

  Widget _voucherThumb(_VoucherItem item) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.file != null
                ? Image.file(
                    item.file!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  )
                : CachedNetworkImage(
                    imageUrl: item.url ?? '',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFFF0F1F3),
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFFF0F1F3),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: Color(0xFFB0B0B0),
                      ),
                    ),
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

/// 报销凭证：已有凭证为网络 URL（remote），新增为本地文件 + OSS 上传态
class _VoucherItem {
  final File? file;
  String? url;
  bool uploading;

  _VoucherItem.remote(String this.url) : file = null, uploading = false;

  _VoucherItem.local(File this.file) : uploading = true;
}
