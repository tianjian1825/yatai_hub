/// 素材库单个文件模型
class MaterialFile {
  final int id;
  final String url;
  final String fileName;
  final String filePath;
  final String fileClassification; // image, video, document
  final int downloadCount;
  final int showCount;
  final bool isCollected;
  final String? originalName;
  final String? size; // 文件大小（字节）
  final String? fileSuffix; // 文件后缀
  final String? thumbnail; // 缩略图URL（优先使用）

  MaterialFile({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.fileClassification,
    required this.downloadCount,
    required this.showCount,
    required this.isCollected,
    this.originalName,
    this.size,
    this.fileSuffix,
    this.thumbnail,
  });

  factory MaterialFile.fromJson(Map<String, dynamic> json) {
    return MaterialFile(
      id: json['id'] ?? 0,
      url: json['url'] ?? '',
      fileName: json['file_name'] ?? '',
      filePath: json['file_path'] ?? '',
      fileClassification: json['file_classification'] ?? 'image',
      downloadCount: _parseInt(json['download_count']),
      showCount: _parseInt(json['show_count']),
      isCollected: json['is_collected'] == 1 || json['is_collected'] == true,
      originalName: json['original_name'],
      size: json['size']?.toString(),
      fileSuffix: json['file_suffix'],
      thumbnail: json['thumbnail'],
    );
  }

  // 辅助方法：安全地将动态类型转换为 int
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'file_name': fileName,
      'file_path': filePath,
      'file_classification': fileClassification,
      'download_count': downloadCount,
      'show_count': showCount,
      'is_collected': isCollected ? 1 : 0,
      'original_name': originalName,
      'size': size,
      'file_suffix': fileSuffix,
      'thumbnail': thumbnail,
    };
  }

  MaterialFile copyWith({
    int? id,
    String? url,
    String? fileName,
    String? filePath,
    String? fileClassification,
    int? downloadCount,
    int? showCount,
    bool? isCollected,
    String? originalName,
    String? size,
    String? fileSuffix,
    String? thumbnail,
  }) {
    return MaterialFile(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileClassification: fileClassification ?? this.fileClassification,
      downloadCount: downloadCount ?? this.downloadCount,
      showCount: showCount ?? this.showCount,
      isCollected: isCollected ?? this.isCollected,
      originalName: originalName ?? this.originalName,
      size: size ?? this.size,
      fileSuffix: fileSuffix ?? this.fileSuffix,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }

  // 格式化文件大小
  String getFormattedSize() {
    if (size == null) return '未知大小';
    final bytes = int.tryParse(size!) ?? 0;
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}

/// 素材库单个素材组模型（一个发布包含多个文件）
class MaterialItem {
  final int id;
  final String text; // 素材描述
  final int userId;
  final String? userName;
  final String? depName;
  final String? avatar;
  final int hospitalId;
  final String? hospitalName;
  final int materialCategory; // 素材分类：1-美食、2-风景、3-街拍等
  final int createdAt;
  final int activityStartTime;
  final int activityEndTime;
  final int isLongTerm; // 是否长期活动
  final List<MaterialFile> list; // 文件列表

  MaterialItem({
    required this.id,
    required this.text,
    required this.userId,
    this.userName,
    this.depName,
    this.avatar,
    required this.hospitalId,
    this.hospitalName,
    required this.materialCategory,
    required this.createdAt,
    required this.activityStartTime,
    required this.activityEndTime,
    required this.isLongTerm,
    required this.list,
  });

  factory MaterialItem.fromJson(Map<String, dynamic> json) {
    List<MaterialFile> files = [];
    if (json['list'] != null && json['list'] is List) {
      files = (json['list'] as List)
          .map((item) => MaterialFile.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return MaterialItem(
      id: json['id'] ?? 0,
      text: json['text'] ?? '',
      userId: json['user_id'] ?? 0,
      userName: json['user_name'],
      depName: json['dep_name'],
      avatar: json['avatar'],
      hospitalId: json['hospital_id'] ?? 0,
      hospitalName: json['hospital_name'],
      materialCategory: json['material_category'] ?? 0,
      createdAt: _parseInt(json['created_at']),
      activityStartTime: _parseInt(json['activity_start_time']),
      activityEndTime: _parseInt(json['activity_end_time']),
      isLongTerm: json['is_long_term'] ?? 0,
      list: files,
    );
  }

  // 辅助方法：安全地将动态类型转换为 int
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'user_id': userId,
      'user_name': userName,
      'dep_name': depName,
      'avatar': avatar,
      'hospital_id': hospitalId,
      'hospital_name': hospitalName,
      'material_category': materialCategory,
      'created_at': createdAt,
      'activity_start_time': activityStartTime,
      'activity_end_time': activityEndTime,
      'is_long_term': isLongTerm,
      'list': list.map((file) => file.toJson()).toList(),
    };
  }
}

/// 素材库日期分组模型
class MaterialDateGroup {
  final String date; // 格式：YYYY-MM-DD
  final List<MaterialItem> items;

  MaterialDateGroup({required this.date, required this.items});

  factory MaterialDateGroup.fromJson(Map<String, dynamic> json) {
    List<MaterialItem> items = [];
    if (json['items'] != null && json['items'] is List) {
      items = (json['items'] as List)
          .map((item) => MaterialItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return MaterialDateGroup(date: json['date'] ?? '', items: items);
  }

  Map<String, dynamic> toJson() {
    return {'date': date, 'items': items.map((item) => item.toJson()).toList()};
  }
}
