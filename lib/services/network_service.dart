import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态
enum NetworkStatus {
  /// 有网络连接
  connected,

  /// 无网络连接
  disconnected,

  /// 未知状态
  unknown,
}

/// 网络连接类型
enum NetworkType {
  /// WiFi
  wifi,

  /// 移动数据
  mobile,

  /// 以太网
  ethernet,

  /// VPN
  vpn,

  /// 无连接
  none,

  /// 其他/未知
  other,
}

/// 网络状态信息
class NetworkInfo {
  final NetworkStatus status;
  final NetworkType type;
  final DateTime timestamp;

  NetworkInfo({required this.status, required this.type, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// 是否有网络连接
  bool get isConnected => status == NetworkStatus.connected;

  /// 是否是WiFi连接
  bool get isWifi => type == NetworkType.wifi;

  /// 是否是移动数据
  bool get isMobile => type == NetworkType.mobile;

  @override
  String toString() => 'NetworkInfo(status: $status, type: $type)';
}

/// 网络状态监听服务
/// 单例模式，提供全局网络状态监听
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();

  /// 网络状态流
  final StreamController<NetworkInfo> _networkStatusController =
      StreamController<NetworkInfo>.broadcast();

  /// 当前网络状态
  NetworkInfo? _currentNetworkInfo;

  /// 订阅
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// 是否已初始化
  bool _initialized = false;

  /// 获取网络状态流
  Stream<NetworkInfo> get networkStream => _networkStatusController.stream;

  /// 获取当前网络状态
  NetworkInfo? get currentNetworkInfo => _currentNetworkInfo;

  /// 当前是否有网络连接
  bool get isConnected => _currentNetworkInfo?.isConnected ?? true;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 获取初始状态
    try {
      final results = await _connectivity.checkConnectivity();
      _handleConnectivityChange(results);
    } catch (e) {
      if (kDebugMode) {
        print('[网络服务] 获取初始网络状态失败: $e');
      }
      // 默认假设有网络
      _updateNetworkInfo(
        NetworkInfo(status: NetworkStatus.unknown, type: NetworkType.other),
      );
    }

    // 监听网络变化
    _subscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (error) {
        if (kDebugMode) {
          print('[网络服务] 监听错误: $error');
        }
      },
    );

    if (kDebugMode) {
      print('[网络服务] 初始化完成');
    }
  }

  /// 处理网络状态变化
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      _updateNetworkInfo(
        NetworkInfo(status: NetworkStatus.disconnected, type: NetworkType.none),
      );
      return;
    }

    // 取第一个结果（通常是主要连接）
    final result = results.first;

    final type = _mapConnectivityResultToType(result);
    final status = type == NetworkType.none
        ? NetworkStatus.disconnected
        : NetworkStatus.connected;

    _updateNetworkInfo(NetworkInfo(status: status, type: type));
  }

  /// 转换连接类型
  NetworkType _mapConnectivityResultToType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return NetworkType.wifi;
      case ConnectivityResult.mobile:
        return NetworkType.mobile;
      case ConnectivityResult.ethernet:
        return NetworkType.ethernet;
      case ConnectivityResult.vpn:
        return NetworkType.vpn;
      case ConnectivityResult.none:
        return NetworkType.none;
      default:
        return NetworkType.other;
    }
  }

  /// 更新网络信息
  void _updateNetworkInfo(NetworkInfo info) {
    final previousStatus = _currentNetworkInfo?.status;
    _currentNetworkInfo = info;

    if (!_networkStatusController.isClosed) {
      _networkStatusController.add(info);
    }

    if (kDebugMode) {
      if (previousStatus != info.status) {
        print('[网络服务] 网络状态变化: $previousStatus -> ${info.status}');
      }
    }
  }

  /// 手动检查网络状态
  Future<NetworkInfo> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _handleConnectivityChange(results);
      return _currentNetworkInfo!;
    } catch (e) {
      if (kDebugMode) {
        print('[网络服务] 检查网络状态失败: $e');
      }
      return NetworkInfo(
        status: NetworkStatus.unknown,
        type: NetworkType.other,
      );
    }
  }

  /// 获取用户友好的网络状态描述
  String getStatusDescription() {
    if (_currentNetworkInfo == null) {
      return '正在检测网络...';
    }

    switch (_currentNetworkInfo!.status) {
      case NetworkStatus.connected:
        switch (_currentNetworkInfo!.type) {
          case NetworkType.wifi:
            return 'WiFi 已连接';
          case NetworkType.mobile:
            return '移动网络已连接';
          case NetworkType.ethernet:
            return '有线网络已连接';
          case NetworkType.vpn:
            return 'VPN 已连接';
          default:
            return '网络已连接';
        }
      case NetworkStatus.disconnected:
        return '网络已断开';
      case NetworkStatus.unknown:
        return '网络状态未知';
    }
  }

  /// 释放资源
  void dispose() {
    _subscription?.cancel();
    _networkStatusController.close();
    _initialized = false;
  }
}
