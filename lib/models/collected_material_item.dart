/// 收藏的材料项
class CollectedMaterialItem {
  final int id;
  final String url;
  final String originalName;
  final String fileClassification; // image, video, document
  final String? fileSuffix;
  final int size; // 文件大小（字节）
  final String? thumbnail; // 缩略图URL（优先使用）
  int downloadCount;
  int showCount;
  bool isCollected;

  CollectedMaterialItem({
    required this.id,
    required this.url,
    required this.originalName,
    required this.fileClassification,
    this.fileSuffix,
    required this.size,
    this.thumbnail,
    required this.downloadCount,
    required this.showCount,
    this.isCollected = true,
  });

  factory CollectedMaterialItem.fromJson(Map<String, dynamic> json) {
    return CollectedMaterialItem(
      id: _parseInt(json['id']) ?? 0,
      url: json['url']?.toString() ?? '',
      originalName:
          json['original_name']?.toString() ??
          json['file_name']?.toString() ??
          '',
      fileClassification:
          json['file_classification']?.toString() ??
          json['type']?.toString() ??
          'image',
      fileSuffix: json['file_suffix']?.toString(),
      size: _parseInt(json['size']) ?? 0,
      thumbnail: json['thumbnail']?.toString(),
      downloadCount: _parseInt(json['download_count']) ?? 0,
      showCount: _parseInt(json['show_count']) ?? 0,
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
    if (value is String) {
      if (value.isEmpty) return null;
      return int.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'original_name': originalName,
      'file_classification': fileClassification,
      'file_suffix': fileSuffix,
      'size': size,
      'thumbnail': thumbnail,
      'download_count': downloadCount,
      'show_count': showCount,
      'is_collected': isCollected ? 1 : 0,
    };
  }

  /// 获取文件显示类型
  String get displayType {
    if (fileClassification == 'image') return 'image';
    if (fileClassification == 'video') return 'video';
    if (fileClassification == 'audio') return 'audio';
    // 也根据文件后缀判断是否为音频
    if (_isAudioSuffix(fileSuffix)) return 'audio';
    return 'document';
  }

  /// 判断是否为音频文件后缀
  bool _isAudioSuffix(String? suffix) {
    if (suffix == null || suffix.isEmpty) return false;
    final audioExtensions = [
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
    return audioExtensions.contains(suffix.toLowerCase());
  }

  /// 获取文件格式（大写）
  String get fileFormat {
    if (fileSuffix != null && fileSuffix!.isNotEmpty) {
      return fileSuffix!.toUpperCase();
    }
    if (originalName.contains('.')) {
      return originalName.split('.').last.toUpperCase();
    }
    return '';
  }

  /// 转换为MaterialFile（用于预览）
  dynamic toMaterialFile() {
    // 返回一个Map，因为MaterialFile需要从JSON创建
    return {
      'id': id,
      'url': url,
      'file_name': originalName,
      'file_path': '',
      'file_classification': fileClassification,
      'download_count': downloadCount,
      'show_count': showCount,
      'is_collected': isCollected ? 1 : 0,
      'original_name': originalName,
      'size': size.toString(),
      'file_suffix': fileSuffix,
      'thumbnail': thumbnail,
    };
  }
}
