/// 可见范围选项模型
class VisibilityOption {
  final int id;
  final String name;

  VisibilityOption({required this.id, required this.name});

  /// 获取所有可见范围选项（移除"仅自己可见"）
  static List<VisibilityOption> getAll() {
    return [
      VisibilityOption(id: 1, name: '全部可见'),
      VisibilityOption(id: 2, name: '部分可见'),
    ];
  }
}
