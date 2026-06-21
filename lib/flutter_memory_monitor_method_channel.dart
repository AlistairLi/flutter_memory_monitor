import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_memory_monitor_platform_interface.dart';
import 'src/memory_models.dart';

/// 基于 MethodChannel/EventChannel 的默认平台实现。
class MethodChannelFlutterMemoryMonitor extends FlutterMemoryMonitorPlatform {
  /// 调用原生方法的通道。
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_memory_monitor');

  /// 原生内存压力事件通道。
  @visibleForTesting
  final eventChannel = const EventChannel('flutter_memory_monitor/events');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<PlatformMemorySnapshot?> getMemorySnapshot() async {
    final Map<dynamic, dynamic>? result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('getMemorySnapshot');
    if (result == null) {
      return null;
    }
    return PlatformMemorySnapshot.fromMap(result);
  }

  @override
  Future<PlatformMemorySnapshot?> getDetailedMemorySnapshot() async {
    final Map<dynamic, dynamic>? result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('getDetailedMemorySnapshot');
    if (result == null) {
      return null;
    }
    return PlatformMemorySnapshot.fromMap(result);
  }

  @override
  Stream<MemoryPressureEvent> get memoryPressureEvents {
    return eventChannel
        .receiveBroadcastStream()
        .where((Object? event) {
          return event is Map<dynamic, dynamic>;
        })
        .map((Object? event) {
          return MemoryPressureEvent.fromMap(event! as Map<dynamic, dynamic>);
        });
  }
}
