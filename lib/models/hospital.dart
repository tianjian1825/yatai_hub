/// 医院/机构模型
class Hospital {
  final int? hospitalId; // 医院ID
  final int? kfHospitalId; // 客服医院ID
  final int? hospitalType; // 医院类型
  final String name; // 医院名称
  final String? hospitalEnName; // 英文名称
  final String? hospitalKrName; // 韩文名称
  final String? hospitalJpName; // 日文名称
  final String? pinyin; // 拼音
  final dynamic areaType; // 区域类型

  Hospital({
    this.hospitalId,
    this.kfHospitalId,
    this.hospitalType,
    required this.name,
    this.hospitalEnName,
    this.hospitalKrName,
    this.hospitalJpName,
    this.pinyin,
    this.areaType,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      hospitalId: json['hospital_id'] as int?,
      kfHospitalId: json['kf_hospital_id'] as int?,
      hospitalType: json['hospital_type'] as int?,
      name: json['name'] as String? ?? '',
      hospitalEnName: json['hospital_en_name'] as String?,
      hospitalKrName: json['hospital_kr_name'] as String?,
      hospitalJpName: json['hospital_jp_name'] as String?,
      pinyin: json['pinyin'] as String?,
      areaType: json['area_type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hospital_id': hospitalId,
      'kf_hospital_id': kfHospitalId,
      'hospital_type': hospitalType,
      'name': name,
      'hospital_en_name': hospitalEnName,
      'hospital_kr_name': hospitalKrName,
      'hospital_jp_name': hospitalJpName,
      'pinyin': pinyin,
      'area_type': areaType,
    };
  }
}
