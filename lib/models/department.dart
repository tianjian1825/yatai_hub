/// 部门模型（用于可见范围选择）
class Department {
  final int id;
  final String department; // 部门名称
  final String? smallDep; // 小部门名称

  Department({required this.id, required this.department, this.smallDep});

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as int,
      department: json['department'] as String? ?? '',
      smallDep: json['small_dep'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'department': department, 'small_dep': smallDep};
  }

  /// 获取显示名称（优先显示小部门名称）
  String get displayName =>
      smallDep?.isNotEmpty == true ? smallDep! : department;
}
