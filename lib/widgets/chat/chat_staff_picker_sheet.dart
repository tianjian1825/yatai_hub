import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yatai_hub/models/chat_message.dart';
import 'package:yatai_hub/services/parttime_chat_service.dart';
import 'package:yatai_hub/widgets/chat/chat_bottom_sheet.dart';

/// 选人：分页搜索在职员工，多选返回 user_ids。
/// 已在群的成员置灰不可选（传入 [existingMemberIds]）。
Future<List<int>?> showChatStaffPicker(
  BuildContext context, {
  Set<int> existingMemberIds = const {},
}) {
  return showChatBottomSheet<List<int>>(
    context: context,
    builder: (_) => ChatStaffPickerSheet(existingMemberIds: existingMemberIds),
  );
}

class ChatStaffPickerSheet extends StatefulWidget {
  final Set<int> existingMemberIds;
  const ChatStaffPickerSheet({super.key, this.existingMemberIds = const {}});

  @override
  State<ChatStaffPickerSheet> createState() => _ChatStaffPickerSheetState();
}

class _ChatStaffPickerSheetState extends State<ChatStaffPickerSheet> {
  static const Color _primary = Color(0xFF1F6FF4);

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<StaffSearchItem> _list = [];
  final Set<int> _selected = {};

  Timer? _debounce;
  String _keyword = '';
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  bool get _hasMore => _list.length < _total;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        !_loading &&
        _hasMore) {
      _load();
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _keyword = v.trim();
      _load(refresh: true);
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final r = await ParttimeChatService().searchStaff(
      keyword: _keyword,
      page: refresh ? 1 : _page + 1,
    );
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _list
          ..clear()
          ..addAll(r.list);
        _loading = false;
        _error = r.message;
      } else {
        _list.addAll(r.list);
        _page += 1;
        _loadingMore = false;
      }
      _total = r.total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // 面板内容是「贴底 + 键盘高度 padding」向上排布的。把状态栏高度和一段
    // 余量直接算进高度上限，保证键盘弹出时面板顶部始终留在状态栏下方一截，
    // 顶部「选择成员 / 确定」不会被状态栏（通知栏）遮住。
    // 顶部安全区用 SafeArea(top:false) 关闭，避免与这里的扣减重复计算。
    const topGap = 48.0;
    final maxHeight = mq.size.height - keyboard - mq.viewPadding.top - topGap;
    final sheetHeight = (mq.size.height * 0.7).clamp(0.0, maxHeight);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: sheetHeight,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const ChatSheetHandle(),
              _buildHeader(),
              _buildSearch(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          const Text(
            '选择成员',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: Text(
              '确定${_selected.isEmpty ? '' : '(${_selected.length})'}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: '搜索姓名 / 用户名',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF5F6F8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xFF999999))),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text('未找到员工', style: TextStyle(color: Color(0xFF999999))),
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      itemCount: _list.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= _list.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final s = _list[i];
        final already = widget.existingMemberIds.contains(s.userId);
        final checked = _selected.contains(s.userId);
        return ListTile(
          dense: true,
          enabled: !already,
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE8F0FE),
            child: Text(
              s.username.isEmpty ? '?' : s.username.characters.first,
              style: const TextStyle(color: _primary),
            ),
          ),
          title: Text(s.username.isEmpty ? '用户${s.userId}' : s.username),
          subtitle: already ? const Text('已在群') : null,
          trailing: already
              ? const Icon(Icons.check, color: Color(0xFFBBBBBB))
              : Checkbox(
                  value: checked,
                  activeColor: _primary,
                  onChanged: (_) => setState(() {
                    if (checked) {
                      _selected.remove(s.userId);
                    } else {
                      _selected.add(s.userId);
                    }
                  }),
                ),
          onTap: already
              ? null
              : () => setState(() {
                  if (checked) {
                    _selected.remove(s.userId);
                  } else {
                    _selected.add(s.userId);
                  }
                }),
        );
      },
    );
  }
}
