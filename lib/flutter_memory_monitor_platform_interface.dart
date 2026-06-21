import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_memory_monitor_method_channel.dart';
import 'src/memory_models.dart';

/// Flutter 内存监控的平台接口。
///
/// Android/iOS 的平台实现通过该接口向 Dart 层提供原生内存快照和系统内存压力事件。
abstract class FlutterMemoryMonitorPlatform extends PlatformInterface {
  /// 创建平台接口实例。
  FlutterMemoryMonitorPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMemoryMonitorPlatform _instance =
      MethodChannelFlutterMemoryMonitor();

  /// 当前默认平台实现。
  static FlutterMemoryMonitorPlatform get instance => _instance;

  /// 替换平台实现，主要用于平台注册和单元测试。
  static set instance(FlutterMemoryMonitorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// 获取平台版本，保留模板插件原有能力。
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// 获取原生平台侧轻量内存快照。
  Future<PlatformMemorySnapshot?> getMemorySnapshot() {
    throw UnimplementedError('getMemorySnapshot() has not been implemented.');
  }

  /// 获取原生平台侧详细内存快照。
  ///
  /// Android 详细快照可能调用 `Debug.getMemoryInfo()`，必须低频、后台线程执行。
  Future<PlatformMemorySnapshot?> getDetailedMemorySnapshot() {
    return getMemorySnapshot();
  }

  /// 系统内存压力事件流。
  Stream<MemoryPressureEvent> get memoryPressureEvents {
    return const Stream<MemoryPressureEvent>.empty();
  }
}
