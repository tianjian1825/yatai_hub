/// 录单元数据 - 通用选项模型（pay_type、charging_type、operators）
class MetaOption {
  final dynamic value;
  final String label;

  MetaOption({required this.value, required this.label});

  factory MetaOption.fromJson(Map<String, dynamic> json) {
    return MetaOption(
      value: json['value'],
      label: json['label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// 录单元数据 - 键值选项模型（channel_name、verym_project）
class MetaKeyOption {
  final String key;
  final String label;

  MetaKeyOption({required this.key, required this.label});

  factory MetaKeyOption.fromJson(Map<String, dynamic> json) {
    return MetaKeyOption(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'key': key, 'label': label};
}

/// 录单元数据顶层容器
class OrderEntryMeta {
  final List<MetaOption> payType;
  final List<MetaOption> chargingType;
  final List<MetaOption> operators;
  final List<MetaOption> surgeryType;
  final List<MetaKeyOption> channelName;
  final List<MetaKeyOption> verymProject;

  OrderEntryMeta({
    required this.payType,
    required this.chargingType,
    required this.operators,
    required this.surgeryType,
    required this.channelName,
    required this.verymProject,
  });

  factory OrderEntryMeta.fromJson(Map<String, dynamic> json) {
    return OrderEntryMeta(
      payType: _parseOptionList(json['pay_type']),
      chargingType: _parseOptionList(json['charging_type']),
      operators: _parseOptionList(json['operators']),
      surgeryType: _parseOptionList(json['surgery_type']),
      channelName: _parseKeyOptionList(json['channel_name']),
      verymProject: _parseKeyOptionList(json['verym_project']),
    );
  }

  Map<String, dynamic> toJson() => {
    'pay_type': payType.map((e) => e.toJson()).toList(),
    'charging_type': chargingType.map((e) => e.toJson()).toList(),
    'operators': operators.map((e) => e.toJson()).toList(),
    'surgery_type': surgeryType.map((e) => e.toJson()).toList(),
    'channel_name': channelName.map((e) => e.toJson()).toList(),
    'verym_project': verymProject.map((e) => e.toJson()).toList(),
  };

  static List<MetaOption> _parseOptionList(dynamic value) {
    if (value == null || value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((item) => MetaOption.fromJson(item))
        .toList();
  }

  static List<MetaKeyOption> _parseKeyOptionList(dynamic value) {
    if (value == null || value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((item) => MetaKeyOption.fromJson(item))
        .toList();
  }
}
