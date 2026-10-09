/// 上传历史中的材料项
class UploadHistoryMaterialItem {
  final int id;
  final String url;
  final String? fileName;
  final int downloadCount;
  final String? thumbnail; // 缩略图URL（优先使用）
  bool isCollected;

  UploadHistoryMaterialItem({
    required this.id,
    required this.url,
    this.fileName,
    required this.downloadCount,
    this.thumbnail,
    this.isCollected = false,
  });

  factory UploadHistoryMaterialItem.fromJson(Map<String, dynamic> json) {
    return UploadHistoryMaterialItem(
      id: _parseInt(json['id']) ?? 0,
      url: json['url']?.toString() ?? '',
      fileName: json['file_name']?.toString(),
      downloadCount: _parseInt(json['download_count']) ?? 0,
      thumbnail: json['thumbnail']?.toString(),
      isCollected:
          json['is_collected'] == 1 ||
          json['is_collected'] == true ||
          json['is_collected'] == '1',
    );
  }

  /// 安全解析int值（兼容字符串和int）
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'file_name': fileName,
      'download_count': downloadCount,
      'thumbnail': thumbnail,
      'is_collected': isCollected ? 1 : 0,
    };
  }

  /// 获取文件类型
  String get fileClassification {
    if (url.isEmpty) return 'image';

    final extension = url.split('.').last.toLowerCase().split('?').first;

    // 视频格式
    const videoExtensions = [
      'mp4',
      'avi',
      'mov',
      'mkv',
      'flv',
      'webm',
      'm4v',
      '3gp',
      'wmv',
      'mpeg',
      'mpg',
    ];
    if (videoExtensions.contains(extension)) {
      return 'video';
    }

    // 音频格式
    const audioExtensions = [
      'mp3',
      'wav',
      'aac',
      'flac',
      'ogg',
      'wma',
      'm4a',
      'aiff',
      'aif',
      'ape',
      'opus',
      'amr',
    ];
    if (audioExtensions.contains(extension)) {
      return 'audio';
    }

    // 图片格式
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];
    if (imageExtensions.contains(extension)) {
      return 'image';
    }

    // 默认为文档
    return 'document';
  }

  /// 转换为MaterialFile（用于预览）
  dynamic toMaterialFile() {
    return {
      'id': id,
      'url': url,
      'file_name': fileName ?? '',
      'file_path': '',
      'file_classification': fileClassification,
      'download_count': downloadCount,
      'show_count': 0, // 我的作品中没有浏览量
      'is_collected': isCollected ? 1 : 0,
      'original_name': fileName,
      'size': '0',
      'file_suffix': url.split('.').last.toLowerCase().split('?').first,
      'thumbnail': thumbnail,
    };
  }
}

/// 上传历史记录项（单次上传）
class UploadHistoryRecord {
  final int id; // casually_id
  final String text; // 描述
  final int materialCategory; // 素材分类
  final String? hospitalName; // 医院名称
  final int? flag; // 可见范围：1=公开，2=医院内可见，3=部门内可见
  final String? visableDepartment; // 可见部门ID列表（逗号分隔）
  final int? activityStartTime; // 活动开始时间（时间戳）
  final int? activityEndTime; // 活动结束时间（时间戳）
  final int? isLongTerm; // 是否长期有效（1=是）
  final int createdAt; // 创建时间（时间戳）
  final List<UploadHistoryMaterialItem> list; // 材料列表

  UploadHistoryRecord({
    required this.id,
    required this.text,
    required this.materialCategory,
    this.hospitalName,
    this.flag,
    this.visableDepartment,
    this.activityStartTime,
    this.activityEndTime,
    this.isLongTerm,
    required this.createdAt,
    required this.list,
  });

  factory UploadHistoryRecord.fromJson(Map<String, dynamic> json) {
    List<UploadHistoryMaterialItem> materialList = [];
    if (json['list'] != null && json['list'] is List) {
      materialList = (json['list'] as List)
          .map((item) => UploadHistoryMaterialItem.fromJson(item))
          .toList();
    }

    return UploadHistoryRecord(
      id: _parseInt(json['id']) ?? 0,
      text: json['text']?.toString() ?? '',
      materialCategory: _parseInt(json['material_category']) ?? 0,
      hospitalName: json['hospital_name']?.toString(),
      flag: _parseInt(json['flag']),
      visableDepartment: json['visable_department']?.toString(),
      activityStartTime: _parseInt(json['activity_start_time']),
      activityEndTime: _parseInt(json['activity_end_time']),
      isLongTerm: _parseInt(json['is_long_term']),
      createdAt: _parseInt(json['created_at']) ?? 0,
      list: materialList,
    );
  }

  /// 安全解析int值（兼容字符串和int）
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      return int.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'material_category': materialCategory,
      'hospital_name': hospitalName,
      'flag': flag,
      'visable_department': visableDepartment,
      'activity_start_time': activityStartTime,
      'activity_end_time': activityEndTime,
      'is_long_term': isLongTerm,
      'created_at': createdAt,
      'list': list.map((item) => item.toJson()).toList(),
    };
  }
}

/// 上传历史按日期分组
class UploadHistoryDateGroup {
  final String date; // YYYY-MM-DD格式
  final List<UploadHistoryRecord> items;

  UploadHistoryDateGroup({required this.date, required this.items});

  factory UploadHistoryDateGroup.fromJson(Map<String, dynamic> json) {
    List<UploadHistoryRecord> records = [];
    if (json['items'] != null && json['items'] is List) {
      records = (json['items'] as List)
          .map((item) => UploadHistoryRecord.fromJson(item))
          .toList();
    }

    return UploadHistoryDateGroup(date: json['date'] ?? '', items: records);
  }

  Map<String, dynamic> toJson() {
    return {'date': date, 'items': items.map((item) => item.toJson()).toList()};
  }
}
