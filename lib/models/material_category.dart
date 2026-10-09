/// 素材分类模型
class MaterialCategory {
  final int id;
  final String name;
  final String key;

  MaterialCategory({required this.id, required this.name, required this.key});

  factory MaterialCategory.fromJson(Map<String, dynamic> json) {
    return MaterialCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      key: json['key'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'key': key};
  }

  /// 获取所有素材分类
  static List<MaterialCategory> getAllCategories() {
    return [
      MaterialCategory(id: 1, name: '美食', key: 'food'),
      MaterialCategory(id: 2, name: '风景', key: 'scenery'),
      MaterialCategory(id: 3, name: '街拍', key: 'street'),
      MaterialCategory(id: 4, name: '医院环境', key: 'hospital_env'),
      MaterialCategory(id: 5, name: '施术过程', key: 'surgery'),
      MaterialCategory(id: 6, name: '日常分享', key: 'daily'),
      MaterialCategory(id: 7, name: '对比案例', key: 'comparison'),
      MaterialCategory(id: 9, name: '价格表', key: 'price_table'),
      MaterialCategory(id: 10, name: '注意事项', key: 'notice'),
      MaterialCategory(id: 11, name: '医生资料', key: 'doctor_info'),
      MaterialCategory(id: 13, name: '话术', key: 'script'),
    ];
  }
}
