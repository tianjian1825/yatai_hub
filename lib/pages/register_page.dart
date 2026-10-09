import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yatai_hub/models/user_register_info.dart';
import 'package:yatai_hub/services/auth_service.dart';
import 'package:yatai_hub/services/oss_api.dart';
import 'package:yatai_hub/services/user_register_info_service.dart';
import 'package:yatai_hub/widgets/passport_capture_guide.dart';

/// 注册页面
///
/// 两种模式：
/// - 新注册（[editInfo] 为 null）：POST /v1/register，需填邮箱 / 密码。
/// - 修改重新提交（[editInfo] 非 null）：用于兼职审核被驳回 / 待审核时重新提交，
///   POST /v1/user/register_info_update，回填整套资料，邮箱 / 密码不可改、不展示。
class RegisterPage extends StatefulWidget {
  final UserRegisterInfo? editInfo;

  const RegisterPage({super.key, this.editInfo});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _realnameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _krAddressController = TextEditingController();
  final TextEditingController _wechatController = TextEditingController();

  String? _gender; // '男' / '女'
  DateTime? _birthday;
  int? _krLanguageLevel; // 韩语 TOPIK 等级 1~6
  bool _isPasswordVisible = false;
  bool _isSubmitting = false;
  // 性别 / 出生日期 / 手机号码 / 韩国住址 / 微信 ID 均为选填，不参与提交校验
  bool _krLanguageLevelError = false;

  // 资料上传：护照首页（登陆证）/ 存折首页 / 韩语等级证书 / 合同 / 收款码
  // 其中护照首页、存折首页为选填，其余仍必填
  _RegisterFileSlot _passportSlot = _RegisterFileSlot();
  _RegisterFileSlot _bookSlot = _RegisterFileSlot();
  _RegisterFileSlot _krCertSlot = _RegisterFileSlot();
  _RegisterFileSlot _contractSlot = _RegisterFileSlot();
  // 收款码拆分为支付宝 / 微信两项，二选一即可（也可同时上传）
  _RegisterFileSlot _alipaySlot = _RegisterFileSlot();
  _RegisterFileSlot _wechatPaySlot = _RegisterFileSlot();
  bool _krCertError = false;
  bool _contractError = false;
  bool _paymentError = false; // 收款码组合校验：支付宝、微信至少上传一项

  // image_picker 全局只允许一个实例同时活跃，用此锁防止多个上传按钮并发触发
  bool _isPicking = false;

  // 护照上传成功后调用 OCR 识别期间为 true，用于卡片展示「识别中」态
  bool _passportRecognizing = false;

  static const _primary = Color(0xFF1F6FF4);
  static const String _passportFileName = '护照首页（登陆证）';
  static const String _bookFileName = '存折首页';
  static const String _krCertFileName = '韩语等级证书';
  static const String _contractFileName = '合同';
  static const String _alipayFileName = '支付宝收款码';
  static const String _wechatPayFileName = '微信收款码';
  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10MB
  static const Set<String> _allowedExt = {'jpg', 'jpeg', 'png', 'pdf'};

  /// 是否为「修改重新提交」模式
  bool get _isEdit => widget.editInfo != null;

  @override
  void initState() {
    super.initState();
    if (widget.editInfo != null) {
      _prefillFromInfo(widget.editInfo!);
    }
  }

  /// 修改重新提交模式：用已有注册资料回填表单（邮箱 / 密码不可改）。
  void _prefillFromInfo(UserRegisterInfo info) {
    // 姓名取 username（realname 已改为承载昵称），旧数据无 username 时回退
    _realnameController.text = info.username.isNotEmpty
        ? info.username
        : info.realname;
    _mobileController.text = info.mobile;
    _wechatController.text = info.wechat;
    _krAddressController.text = info.krAddress;
    if (info.gender == '男' || info.gender == '女') {
      _gender = info.gender;
    }
    _birthday = DateTime.tryParse(info.birthday);
    if (info.krLanguageLevel >= 1 && info.krLanguageLevel <= 6) {
      _krLanguageLevel = info.krLanguageLevel;
    }
    // 按资料名称回填各上传槽（已上传 → 仅有远端 URL，预览走 Image.network）
    for (final f in info.krParttimeFiles) {
      if (f.url.isEmpty) continue;
      final slot = _RegisterFileSlot(remoteUrl: f.url);
      final name = f.name;
      if (name.contains('护照')) {
        _passportSlot = slot;
      } else if (name.contains('存折')) {
        _bookSlot = slot;
      } else if (name.contains('韩语') ||
          name.contains('语言') ||
          name.toUpperCase().contains('TOPIK')) {
        _krCertSlot = slot;
      } else if (name.contains('合同')) {
        _contractSlot = slot;
      } else if (name.contains('支付宝')) {
        _alipaySlot = slot;
      } else if (name.contains('微信')) {
        _wechatPaySlot = slot;
      }
    }
  }

  @override
  void dispose() {
    _realnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    _krAddressController.dispose();
    _wechatController.dispose();
    // 离开页面时释放本地预览图片占用的内存缓存（参考素材上传页做法）
    _clearImageCache();
    super.dispose();
  }

  /// 清理图片缓存（释放本地预览 Image.file 占用的内存）
  void _clearImageCache() {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      if (kDebugMode) {
        print('[注册] 清理图片缓存失败: $e');
      }
    }
  }

  // ───────────────────── 图片选择 + 上传 ─────────────────────

  Future<void> _pickPassport() => _pickAndUpload(
    targetSetter: (slot) => setState(() => _passportSlot = slot),
    targetGetter: () => _passportSlot,
    displayName: _passportFileName,
    onUploaded: _recognizePassport,
  );

  /// 护照上传成功后调用 OCR 识别，把姓名 / 性别 / 出生日期回填到表单。
  /// 识别失败不阻断注册流程（图片已上传成功），仅提示用户手动填写。
  Future<void> _recognizePassport(String imageUrl) async {
    if (!mounted) return;
    setState(() => _passportRecognizing = true);
    try {
      final data = await OssApi.recognizePassportForRegister(imageUrl) ?? {};
      if (!mounted) return;
      _applyPassportResult(data);
    } catch (e) {
      if (kDebugMode) print('[注册] 护照识别失败: $e');
      if (mounted) {
        _showError('护照识别失败，请手动填写姓名 / 性别 / 出生日期');
      }
    } finally {
      if (mounted) setState(() => _passportRecognizing = false);
    }
  }

  /// 把护照识别结果回填到注册表单（姓名 / 性别 / 出生日期）。
  void _applyPassportResult(Map<String, dynamic> data) {
    final name = data['nameEn']?.toString().trim() ?? '';
    final birthTime = data['birth_time']?.toString().trim() ?? '';
    final genderStr = data['gender_str']?.toString().trim() ?? '';

    setState(() {
      if (name.isNotEmpty) {
        _realnameController.text = name.length > 50
            ? name.substring(0, 50)
            : name;
      }
      final birthday = DateTime.tryParse(birthTime);
      if (birthday != null) {
        _birthday = birthday;
      }
      if (genderStr == '男' || genderStr == '女') {
        _gender = genderStr;
      }
    });
  }

  Future<void> _pickBook() => _pickAndUpload(
    targetSetter: (slot) => setState(() => _bookSlot = slot),
    targetGetter: () => _bookSlot,
    displayName: _bookFileName,
  );

  Future<void> _pickKrCert() => _pickAndUpload(
    targetSetter: (slot) => setState(() {
      _krCertSlot = slot;
      if (slot.isReady) _krCertError = false;
    }),
    targetGetter: () => _krCertSlot,
    displayName: _krCertFileName,
  );

  Future<void> _pickContract() => _pickAndUpload(
    targetSetter: (slot) => setState(() {
      _contractSlot = slot;
      if (slot.isReady) _contractError = false;
    }),
    targetGetter: () => _contractSlot,
    displayName: _contractFileName,
  );

  Future<void> _pickAlipay() => _pickAndUpload(
    targetSetter: (slot) => setState(() {
      _alipaySlot = slot;
      if (slot.isReady) _paymentError = false;
    }),
    targetGetter: () => _alipaySlot,
    displayName: _alipayFileName,
  );

  Future<void> _pickWechatPay() => _pickAndUpload(
    targetSetter: (slot) => setState(() {
      _wechatPaySlot = slot;
      if (slot.isReady) _paymentError = false;
    }),
    targetGetter: () => _wechatPaySlot,
    displayName: _wechatPayFileName,
  );

  void _clearPassport() {
    setState(() {
      _passportSlot = _RegisterFileSlot();
    });
  }

  void _clearBook() {
    setState(() {
      _bookSlot = _RegisterFileSlot();
    });
  }

  void _clearKrCert() {
    setState(() {
      _krCertSlot = _RegisterFileSlot();
    });
  }

  void _clearContract() {
    setState(() {
      _contractSlot = _RegisterFileSlot();
    });
  }

  void _clearAlipay() {
    setState(() {
      _alipaySlot = _RegisterFileSlot();
    });
  }

  void _clearWechatPay() {
    setState(() {
      _wechatPaySlot = _RegisterFileSlot();
    });
  }

  Future<void> _pickAndUpload({
    required void Function(_RegisterFileSlot) targetSetter,
    required _RegisterFileSlot Function() targetGetter,
    required String displayName,
    // 上传成功后回调（携带 OSS URL），用于护照触发 OCR 识别
    Future<void> Function(String imageUrl)? onUploaded,
  }) async {
    if (targetGetter().uploading) return;
    // 全局锁：image_picker 同一时刻只能有一个实例活跃，
    // 防止同时点击多个上传按钮触发 "image picker is already active"
    if (_isPicking) return;
    _isPicking = true;
    try {
      // 先让用户选择来源：拍照 / 从相册选择（与项目其他上传一致）
      final source = await _chooseImageSource();
      if (source == null) {
        _isPicking = false; // 用户取消来源选择，释放锁
        return;
      }

      final picker = ImagePicker();
      final XFile? picked;
      try {
        picked = await picker.pickImage(source: source, imageQuality: 85);
      } finally {
        // 选择完成（或取消）即释放锁，后续 OSS 上传不阻塞其他按钮
        _isPicking = false;
      }
      if (picked == null) return;

      // 文件后缀校验
      final ext = picked.name.split('.').last.toLowerCase();
      if (!_allowedExt.contains(ext)) {
        _showError('$displayName 仅支持 jpg / jpeg / png / pdf 格式');
        return;
      }

      // 文件大小校验
      final size = await picked.length();
      if (size > _maxUploadBytes) {
        _showError('$displayName 不能超过 10MB');
        return;
      }

      // 立即显示本地预览 + 标记上传中
      targetSetter(_RegisterFileSlot(localPath: picked.path, uploading: true));

      // 1) 拿匿名直传签名
      final signData = await OssApi.getRegisterUploadSign(picked.name);
      if (signData == null) {
        throw Exception('获取上传签名失败');
      }

      // 2) 直传 OSS
      final imageUrl = await OssApi.uploadToOss(
        file: File(picked.path),
        signData: signData,
      );
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('上传到 OSS 失败');
      }

      if (!mounted) return;
      targetSetter(
        _RegisterFileSlot(
          localPath: picked.path,
          remoteUrl: imageUrl,
          uploading: false,
        ),
      );

      if (onUploaded != null) {
        await onUploaded(imageUrl);
      }
    } catch (e) {
      if (mounted) {
        targetSetter(_RegisterFileSlot());
        _showError('$displayName 上传失败：$e');
      }
    }
  }

  /// 底部弹出选择图片来源：拍照 / 从相册选择
  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _primary),
              title: const Text('拍照'),
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
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 25, now.month, now.day);
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDate: initial,
      locale: const Locale('zh'),
    );
    if (result != null) {
      setState(() => _birthday = result);
    }
  }

  String _formatBirthday(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isValidEmail(String s) {
    return RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(s);
  }

  /// 通用手机号校验：允许数字及 + - 空格分隔符，纯数字位数在 6-20 之间即可
  /// （不限中国手机号，兼容海外号码）
  bool _isValidMobile(String s) {
    if (!RegExp(r'^[0-9+\-\s]+$').hasMatch(s)) return false;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 6 && digits.length <= 20;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // 同时校验文本字段与自定义字段（韩语等级、资料图片）
    // 性别 / 出生日期 / 手机号码 / 韩国住址 / 微信 ID 为选填，不校验
    // 资料图片中护照首页、存折首页为选填，同样不校验
    final textValid = _formKey.currentState?.validate() ?? false;
    setState(() {
      _krLanguageLevelError = _krLanguageLevel == null;
      _krCertError = !_krCertSlot.isReady;
      _contractError = !_contractSlot.isReady;
      // 收款码二选一：支付宝、微信至少有一个上传完成
      _paymentError = !_alipaySlot.isReady && !_wechatPaySlot.isReady;
    });

    if (_passportSlot.uploading ||
        _bookSlot.uploading ||
        _krCertSlot.uploading ||
        _contractSlot.uploading ||
        _alipaySlot.uploading ||
        _wechatPaySlot.uploading) {
      _showError('资料图片正在上传，请稍候');
      return;
    }
    if (!textValid ||
        _krLanguageLevelError ||
        _krCertError ||
        _contractError ||
        _paymentError) {
      return;
    }

    // 组装资料文件：护照 / 存折为选填，收款码按实际上传情况追加（支付宝 / 微信任一或同时）
    final krParttimeFiles = <Map<String, String>>[
      if (_passportSlot.isReady)
        {'name': _passportFileName, 'url': _passportSlot.remoteUrl!},
      if (_bookSlot.isReady)
        {'name': _bookFileName, 'url': _bookSlot.remoteUrl!},
      {'name': _krCertFileName, 'url': _krCertSlot.remoteUrl!},
      {'name': _contractFileName, 'url': _contractSlot.remoteUrl!},
    ];
    if (_alipaySlot.isReady) {
      krParttimeFiles.add({
        'name': _alipayFileName,
        'url': _alipaySlot.remoteUrl!,
      });
    }
    if (_wechatPaySlot.isReady) {
      krParttimeFiles.add({
        'name': _wechatPayFileName,
        'url': _wechatPaySlot.remoteUrl!,
      });
    }

    // 选填项留空时不下发对应字段（尤其 birthday，空串会被后端当格式错误）
    final birthday = _birthday == null ? null : _formatBirthday(_birthday!);
    final mobile = _mobileController.text.trim();
    final krAddress = _krAddressController.text.trim();
    final wechat = _wechatController.text.trim();

    setState(() => _isSubmitting = true);
    try {
      final ({bool success, String? message}) result = _isEdit
          ? await UserRegisterInfoService().submitUpdate(
              realname: _realnameController.text.trim(),
              mobile: mobile.isEmpty ? null : mobile,
              wechat: wechat.isEmpty ? null : wechat,
              krLanguageLevel: _krLanguageLevel!,
              krParttimeFiles: krParttimeFiles,
              gender: _gender,
              birthday: birthday,
              krAddress: krAddress.isEmpty ? null : krAddress,
            )
          : await _authService.register(
              realname: _realnameController.text.trim(),
              email: _emailController.text.trim(),
              password: _passwordController.text,
              mobile: mobile.isEmpty ? null : mobile,
              gender: _gender,
              birthday: birthday,
              krAddress: krAddress.isEmpty ? null : krAddress,
              wechat: wechat.isEmpty ? null : wechat,
              krLanguageLevel: _krLanguageLevel!,
              krParttimeFiles: krParttimeFiles,
            );

      if (!mounted) return;

      if (result.success) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(_isEdit ? '已提交' : '注册成功'),
            content: Text(
              result.message ?? (_isEdit ? '已提交，请等待管理员审核' : '注册成功，请等待管理员审核'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        // 编辑模式：pop(true) 通知审核状态页刷新；新注册：把邮箱带回登录页自动填入
        Navigator.of(
          context,
        ).pop(_isEdit ? true : _emailController.text.trim());
      } else {
        _showError(result.message ?? (_isEdit ? '提交失败，请重试' : '注册失败，请重试'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEdit ? '修改资料' : '注册',
          style: const TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E1E1E)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.disabled,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              _buildPassportCard(),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _realnameController,
                hint: '姓名',
                icon: Icons.person_outline,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return '请输入姓名';
                  if (s.length > 30) return '姓名不能超过 30 字';
                  return null;
                },
              ),
              // 邮箱 / 密码仅新注册时填写；修改重新提交模式下不可改、不展示
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emailController,
                  hint: '邮箱（同时作为登录用户名）',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '请输入邮箱';
                    if (!_isValidEmail(s)) return '邮箱格式不正确';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _passwordController,
                  hint: '密码（6-16 位）',
                  icon: Icons.lock_outline,
                  obscureText: !_isPasswordVisible,
                  inputFormatters: [LengthLimitingTextInputFormatter(16)],
                  suffix: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: const Color(0xFF999999),
                    ),
                    onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return '请输入密码';
                    if (s.length < 6 || s.length > 16) return '密码长度需 6-16 位';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              _buildTextField(
                controller: _mobileController,
                hint: '手机号码（选填）',
                icon: Icons.phone_iphone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                // 选填：留空放行，填了才校验格式
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  if (!_isValidMobile(s)) return '手机号码格式不正确';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildGenderSelector(),
              const SizedBox(height: 12),
              _buildBirthdaySelector(),
              const SizedBox(height: 12),
              _buildKrLanguageLevelSelector(),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _krAddressController,
                hint: '韩国住址（选填）',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _wechatController,
                hint: '微信 ID（选填）',
                icon: Icons.chat_outlined,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.length > 50) return '微信 ID 不能超过 50 字';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildImageSlot(
                title: '$_bookFileName（选填）',
                slot: _bookSlot,
                hasError: false,
                onPick: _pickBook,
                onClear: _clearBook,
              ),
              const SizedBox(height: 12),
              _buildImageSlot(
                title: _krCertFileName,
                slot: _krCertSlot,
                hasError: _krCertError,
                onPick: _pickKrCert,
                onClear: _clearKrCert,
              ),
              const SizedBox(height: 12),
              _buildImageSlot(
                title: _contractFileName,
                slot: _contractSlot,
                hasError: _contractError,
                onPick: _pickContract,
                onClear: _clearContract,
              ),
              const SizedBox(height: 12),
              // 收款码：支付宝 / 微信二选一即可（也可同时上传）
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '收款码（支付宝 / 微信至少上传一种）',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
              _buildImageSlot(
                title: _alipayFileName,
                slot: _alipaySlot,
                hasError: _paymentError,
                suppressErrorText: true,
                onPick: _pickAlipay,
                onClear: _clearAlipay,
              ),
              const SizedBox(height: 12),
              _buildImageSlot(
                title: _wechatPayFileName,
                slot: _wechatPaySlot,
                hasError: _paymentError,
                suppressErrorText: true,
                onPick: _pickWechatPay,
                onClear: _clearWechatPay,
              ),
              if (_paymentError)
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 6),
                  child: Text(
                    '请至少上传一种收款码（支付宝或微信）',
                    style: TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
                  ),
                ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFB0B0B0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _isEdit ? '提交' : '注 册',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isEdit ? '提交后状态将回到「待审核」，请等待管理员重新审核' : '注册后需等待管理员审核，审核通过后即可登录',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF999999)),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF4D4F)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF4D4F), width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.wc_outlined, color: Color(0xFF999999)),
          const SizedBox(width: 12),
          const Text(
            '性别（选填）',
            style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
          ),
          const Spacer(),
          _buildGenderChip('男'),
          const SizedBox(width: 8),
          _buildGenderChip('女'),
        ],
      ),
    );
  }

  Widget _buildGenderChip(String value) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _primary : const Color(0xFFDDDDDD),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdaySelector() {
    return GestureDetector(
      onTap: _pickBirthday,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined, color: Color(0xFF999999)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _birthday != null ? _formatBirthday(_birthday!) : '出生日期（选填）',
                style: TextStyle(
                  fontSize: 14,
                  color: _birthday != null
                      ? const Color(0xFF333333)
                      : const Color(0xFFCCCCCC),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }

  /// 韩语等级（TOPIK 1~6）选择器：点击弹出底部选择弹窗
  Widget _buildKrLanguageLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickKrLanguageLevel,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _krLanguageLevelError
                    ? const Color(0xFFFF4D4F)
                    : const Color(0xFFE5E5E5),
                width: _krLanguageLevelError ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.translate_outlined, color: Color(0xFF999999)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _krLanguageLevel != null
                        ? 'TOPIK $_krLanguageLevel级'
                        : '韩语等级（TOPIK）',
                    style: TextStyle(
                      fontSize: 14,
                      color: _krLanguageLevel != null
                          ? const Color(0xFF333333)
                          : const Color(0xFFCCCCCC),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF999999),
                ),
              ],
            ),
          ),
        ),
        if (_krLanguageLevelError)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 6),
            child: Text(
              '请选择韩语等级',
              style: TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
            ),
          ),
      ],
    );
  }

  /// 底部弹窗选择韩语等级（TOPIK 1~6）
  Future<void> _pickKrLanguageLevel() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<int>(
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
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '选择韩语等级（TOPIK）',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E1E1E),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            for (var level = 1; level <= 6; level++)
              ListTile(
                title: Text(
                  'TOPIK $level级',
                  style: TextStyle(
                    fontSize: 15,
                    color: _krLanguageLevel == level
                        ? _primary
                        : const Color(0xFF333333),
                    fontWeight: _krLanguageLevel == level
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                trailing: _krLanguageLevel == level
                    ? const Icon(Icons.check, color: _primary, size: 20)
                    : null,
                onTap: () => Navigator.pop(ctx, level),
              ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _krLanguageLevel = result;
        _krLanguageLevelError = false;
      });
    }
  }

  /// 护照识别卡片（置于表单最顶部）：大图上传区，上传后自动 OCR 回填。
  Widget _buildPassportCard() {
    final slot = _passportSlot;
    final busy = slot.uploading || _passportRecognizing;

    // 状态文案与配色
    final String statusText;
    final Color statusColor;
    if (slot.uploading) {
      statusText = '正在上传护照…';
      statusColor = const Color(0xFF999999);
    } else if (_passportRecognizing) {
      statusText = '正在识别护照信息…';
      statusColor = _primary;
    } else if (slot.isReady) {
      statusText = '识别完成，请核对下方姓名 / 性别 / 出生日期';
      statusColor = const Color(0xFF52C41A);
    } else {
      statusText = '上传护照后将自动识别并填写姓名 / 性别 / 出生日期';
      statusColor = const Color(0xFF999999);
    }

    Widget previewArea;
    if (slot.localPath != null || slot.isReady) {
      previewArea = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            _slotPreviewImage(slot, width: double.infinity, height: 180),
            if (busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            // 右上角操作：更换 / 删除（上传或识别中禁用）
            if (!busy)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _passportAction(label: '更换', onTap: _pickPassport),
                    const SizedBox(width: 8),
                    _passportAction(label: '删除', onTap: _clearPassport),
                  ],
                ),
              ),
          ],
        ),
      );
    } else {
      previewArea = GestureDetector(
        onTap: busy ? null : _pickPassport,
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC7D7FF)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF1FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: _primary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '点击上传护照',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E4FF)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: _primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                _passportFileName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '（选填）',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
          const SizedBox(height: 10),
          const PassportCaptureGuideHint(),
          const SizedBox(height: 12),
          previewArea,
        ],
      ),
    );
  }

  /// 上传槽的预览图：本地已选 → Image.file；仅有远端 URL（修改模式回填）→ Image.network。
  Widget _slotPreviewImage(
    _RegisterFileSlot slot, {
    required double width,
    required double height,
  }) {
    Widget broken = Container(
      width: width,
      height: height,
      color: const Color(0xFFF0F0F0),
      child: const Icon(Icons.broken_image, color: Color(0xFFCCCCCC)),
    );
    if (slot.localPath != null) {
      return Image.file(
        File(slot.localPath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => broken,
      );
    }
    return Image.network(
      slot.remoteUrl!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => broken,
    );
  }

  /// 护照预览右上角的小操作按钮（更换 / 删除）
  Widget _passportAction({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildImageSlot({
    required String title,
    required _RegisterFileSlot slot,
    required bool hasError,
    required Future<void> Function() onPick,
    required VoidCallback onClear,
    // true 时仅高亮红框、不显示"请上传xxx"文字（用于收款码组合校验，错误文案统一在外层展示）
    bool suppressErrorText = false,
  }) {
    final borderColor = hasError
        ? const Color(0xFFFF4D4F)
        : const Color(0xFFE5E5E5);
    final borderWidth = hasError ? 1.5 : 1.0;

    Widget body;
    if (slot.localPath != null || slot.isReady) {
      body = Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _slotPreviewImage(slot, width: 64, height: 64),
          ),
          if (slot.uploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      body = Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.add_a_photo_outlined,
          color: Color(0xFF999999),
          size: 24,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: slot.uploading ? null : onPick,
                child: body,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot.uploading
                          ? '上传中…'
                          : slot.isReady
                          ? '已上传'
                          : '点击选择图片',
                      style: TextStyle(
                        fontSize: 12,
                        color: slot.isReady
                            ? const Color(0xFF52C41A)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
              if ((slot.localPath != null || slot.isReady) && !slot.uploading)
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF999999),
                  ),
                  onPressed: onClear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                TextButton(
                  onPressed: slot.uploading ? null : onPick,
                  child: Text(
                    slot.isReady ? '更换' : '选择',
                    style: const TextStyle(color: _primary, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        if (hasError && !suppressErrorText)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Text(
              '请上传$title',
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
            ),
          ),
      ],
    );
  }
}

/// 单图上传槽的本地状态
class _RegisterFileSlot {
  /// 本地预览路径（选中后立即可见）
  String? localPath;

  /// 上传完成后的 NAS URL
  String? remoteUrl;

  /// 是否正在上传
  bool uploading;

  _RegisterFileSlot({this.localPath, this.remoteUrl, this.uploading = false});

  bool get isReady => remoteUrl != null && remoteUrl!.isNotEmpty;
}
