import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yatai_hub/models/user_register_info.dart';
import 'package:yatai_hub/services/oss_api.dart';
import 'package:yatai_hub/services/user_register_info_service.dart';
import 'package:yatai_hub/services/user_service.dart';
import 'package:yatai_hub/widgets/image_preview_page.dart';

/// 个人资料页面（兼职用户）
///
/// 展示用户注册时提交的基本信息、韩国联系方式、上传资料，
/// 以及打工证状态（未上传打工证时不展示打工证区域）。
/// 支持自助修改头像和昵称（POST /v1/user/profile，昵称即库中 realname）。
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final UserRegisterInfoService _service = UserRegisterInfoService();

  UserRegisterInfo? _info;
  bool _loading = true;
  String? _error;

  /// 当前头像 URL（来自 UserService 缓存，register_info 不含头像）
  String _avatar = '';
  bool _avatarUploading = false;
  // image_picker 全局只允许一个实例同时活跃，防止重复点击并发触发
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final avatar = await UserService().getUserAvatar();
    if (avatar != null && avatar.isNotEmpty && mounted) {
      setState(() => _avatar = avatar);
    }
    // 先展示本地缓存，避免白屏
    final cached = await _service.getCached();
    if (cached != null && mounted) {
      setState(() {
        _info = cached;
        _loading = false;
      });
    }
    await _refresh(silent: cached != null);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = _info == null;
        _error = null;
      });
    }
    final info = await _service.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (info != null) {
        _info = info;
        _error = null;
      } else if (_info == null) {
        _error = '加载失败，请下拉重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('个人资料'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0.5,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_info == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _error ?? '暂无数据',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final info = _info!;
    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildHeaderCard(info),
          const SizedBox(height: 12),
          _buildInfoCard('基本信息', [
            // 姓名取 username；旧缓存无该字段时回退 realname，刷新后自动纠正
            _Field(
              '姓名',
              info.username.isNotEmpty ? info.username : info.realname,
            ),
            _Field('性别', info.gender),
            _Field('生日', info.birthday),
            _Field('手机号', info.mobile),
            _Field('微信号', info.wechat),
            _Field('邮箱', info.email),
            _Field('韩语等级', _krLanguageLevelText(info)),
            _Field('韩国地址', info.krAddress),
          ]),
          if (info.krParttimeFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildFilesCard(info.krParttimeFiles),
          ],
          if (info.hasWorkcard) ...[
            const SizedBox(height: 12),
            _buildWorkcardCard(info),
          ],
        ],
      ),
    );
  }

  /// 顶部卡片：姓名 + 审核状态
  Widget _buildHeaderCard(UserRegisterInfo info) {
    final (Color, Color) badgeColors;
    if (info.isApproved) {
      badgeColors = const (Color(0xFF52C41A), Color(0xFFE6FFEE));
    } else if (info.isRejected) {
      badgeColors = const (Color(0xFFF5222D), Color(0xFFFFECEC));
    } else {
      badgeColors = const (Color(0xFFFA8C16), Color(0xFFFFF7E6));
    }
    return _cardContainer(
      child: Row(
        children: [
          _buildEditableAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        info.realname.isNotEmpty ? info.realname : '未设置昵称',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _editNickname,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Color(0xFF709BF7),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${info.userid}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          _badge(info.auditStatusText, badgeColors),
        ],
      ),
    );
  }

  /// 可编辑头像：点击更换，右下角相机角标，上传中显示遮罩进度
  Widget _buildEditableAvatar() {
    final Widget avatarImage = _avatar.isEmpty
        ? Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEAF0FF),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.person, color: Color(0xFF709BF7)),
          )
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: _avatar,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              maxWidthDiskCache: 96,
              placeholder: (_, _) => Container(
                width: 48,
                height: 48,
                color: const Color(0xFFEAF0FF),
                child: const Icon(Icons.person, color: Color(0xFF709BF7)),
              ),
              errorWidget: (_, _, _) => Container(
                width: 48,
                height: 48,
                color: const Color(0xFFEAF0FF),
                child: const Icon(Icons.person, color: Color(0xFF709BF7)),
              ),
            ),
          );

    return GestureDetector(
      onTap: _changeAvatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarImage,
          if (_avatarUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF709BF7),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.photo_camera,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 修改昵称：弹窗输入（1~30 字符），成功后刷新资料
  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _info?.realname ?? '');
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '请输入昵称（1~30 个字符）',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (input == null) return;

    final nickname = input.trim();
    if (nickname.isEmpty) {
      _toast('昵称不能为空');
      return;
    }
    if (nickname == _info?.realname) return;

    final (ok, msg) = await UserService().updateProfile(nickname: nickname);
    if (!mounted) return;
    _toast(msg);
    if (ok) {
      // 昵称即库中 realname，重新拉取 register_info 同步展示
      _refresh(silent: true);
    }
  }

  /// 更换头像：选图 → OSS 直传 → 提交 /v1/user/profile
  Future<void> _changeAvatar() async {
    if (_avatarUploading || _isPicking) return;
    _isPicking = true;

    try {
      final source = await _chooseImageSource();
      if (source == null) return;

      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      final ext = picked.name.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        _toast('头像仅支持 jpg / jpeg / png 格式');
        return;
      }
      if (await picked.length() > 10 * 1024 * 1024) {
        _toast('头像不能超过 10MB');
        return;
      }

      if (!mounted) return;
      setState(() => _avatarUploading = true);
      try {
        final signData = await OssApi.getDirectUploadSign(picked.name);
        if (signData == null) throw Exception('获取上传签名失败');
        final url = await OssApi.uploadToOss(
          file: File(picked.path),
          signData: signData,
        );
        if (url == null || url.isEmpty) throw Exception('上传到 OSS 失败');

        final (ok, msg) = await UserService().updateProfile(avatar: url);
        if (!mounted) return;
        _toast(msg);
        if (ok) setState(() => _avatar = url);
      } catch (e) {
        if (mounted) _toast('头像上传失败：$e');
      } finally {
        if (mounted) setState(() => _avatarUploading = false);
      }
    } finally {
      _isPicking = false;
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
              leading: const Icon(Icons.photo_camera, color: Color(0xFF709BF7)),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFF709BF7),
              ),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  Widget _buildInfoCard(String title, List<_Field> fields) {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(title),
          const SizedBox(height: 12),
          ...fields.map(_fieldRow),
        ],
      ),
    );
  }

  Widget _buildFilesCard(List<KrParttimeFile> files) {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('资料'),
          const SizedBox(height: 12),
          ...files.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _thumbnail(f.url, title: f.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.name.isNotEmpty ? f.name : '资料',
                      style: const TextStyle(
                        fontSize: 14,
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

  Widget _buildWorkcardCard(UserRegisterInfo info) {
    final (fg, bg) = _workcardColor(info.workcardStatus);
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardTitle('打工证'),
              const SizedBox(width: 8),
              if (info.workcardStatusLabel.isNotEmpty)
                _badge(info.workcardStatusLabel, (fg, bg)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbnail(info.krWorkcard, title: '打工证', size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldRow(
                      _Field(
                        '有效期',
                        info.krWorkcardExpiry.isNotEmpty
                            ? info.krWorkcardExpiry
                            : '未填写',
                      ),
                    ),
                    _fieldRow(_Field('状态', info.workcardStatusLabel)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============ 复用小组件 ============

  Widget _cardContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _cardTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _fieldRow(_Field field) {
    final value = field.value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              field.label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '—',
              style: TextStyle(
                fontSize: 13,
                color: value.isNotEmpty
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFBBBBBB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, (Color, Color) colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.$1,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _thumbnail(String url, {required String title, double size = 56}) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: Color(0xFFBBBBBB),
        ),
      );
    }
    return GestureDetector(
      onTap: () => showImagePreview(context, imageUrls: [url], title: title),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: const Color(0xFFF0F2F5),
            child: const Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: Color(0xFFBBBBBB),
            ),
          ),
        ),
      ),
    );
  }

  /// 韩语等级展示文案：优先用后端 label，历史未填（0/空）展示"未填"
  String _krLanguageLevelText(UserRegisterInfo info) {
    if (info.krLanguageLevelLabel.isNotEmpty) return info.krLanguageLevelLabel;
    if (info.krLanguageLevel >= 1 && info.krLanguageLevel <= 6) {
      return 'TOPIK ${info.krLanguageLevel}级';
    }
    return '未填';
  }

  /// 打工证状态码 -> (前景色, 背景色)
  (Color, Color) _workcardColor(String status) {
    switch (status) {
      case 'valid':
        return (const Color(0xFF52C41A), const Color(0xFFE6FFEE));
      case 'expiring':
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
      case 'expired':
        return (const Color(0xFFF5222D), const Color(0xFFFFECEC));
      case 'no_expiry':
        return (const Color(0xFFFA8C16), const Color(0xFFFFF7E6));
      default:
        return (const Color(0xFF999999), const Color(0xFFF5F5F5));
    }
  }
}

class _Field {
  final String label;
  final String value;
  _Field(this.label, this.value);
}
