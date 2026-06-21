import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_memory_monitor_platform_interface.dart';

/// An implementation of [FlutterMemoryMonitorPlatform] that uses method channels.
class MethodChannelFlutterMemoryMonitor extends FlutterMemoryMonitorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_memory_monitor');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
