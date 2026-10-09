import 'dart:async';

/// 全局事件总线服务
/// 用于在不同页面之间传递事件通知
class EventBusService {
  // 单例模式
  static final EventBusService _instance = EventBusService._internal();
  factory EventBusService() => _instance;
  EventBusService._internal();

  // 素材上传成功事件控制器
  final _materialUploadedController = StreamController<void>.broadcast();

  // 线路变更事件控制器
  final _routeChangedController = StreamController<void>.broadcast();

  /// 素材上传成功事件流
  Stream<void> get onMaterialUploaded => _materialUploadedController.stream;

  /// 线路变更事件流
  Stream<void> get onRouteChanged => _routeChangedController.stream;

  /// 发送素材上传成功事件
  void notifyMaterialUploaded() {
    _materialUploadedController.add(null);
  }

  /// 发送线路变更事件
  void notifyRouteChanged() {
    _routeChangedController.add(null);
  }

  /// 释放资源
  void dispose() {
    _materialUploadedController.close();
    _routeChangedController.close();
  }
}
