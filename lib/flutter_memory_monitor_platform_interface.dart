import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_memory_monitor_method_channel.dart';

abstract class FlutterMemoryMonitorPlatform extends PlatformInterface {
  /// Constructs a FlutterMemoryMonitorPlatform.
  FlutterMemoryMonitorPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMemoryMonitorPlatform _instance = MethodChannelFlutterMemoryMonitor();

  /// The default instance of [FlutterMemoryMonitorPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterMemoryMonitor].
  static FlutterMemoryMonitorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterMemoryMonitorPlatform] when
  /// they register themselves.
  static set instance(FlutterMemoryMonitorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
