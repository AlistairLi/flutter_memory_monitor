import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_platform_interface.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterMemoryMonitorPlatform
    with MockPlatformInterfaceMixin
    implements FlutterMemoryMonitorPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterMemoryMonitorPlatform initialPlatform = FlutterMemoryMonitorPlatform.instance;

  test('$MethodChannelFlutterMemoryMonitor is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMemoryMonitor>());
  });

  test('getPlatformVersion', () async {
    FlutterMemoryMonitor flutterMemoryMonitorPlugin = FlutterMemoryMonitor();
    MockFlutterMemoryMonitorPlatform fakePlatform = MockFlutterMemoryMonitorPlatform();
    FlutterMemoryMonitorPlatform.instance = fakePlatform;

    expect(await flutterMemoryMonitorPlugin.getPlatformVersion(), '42');
  });
}
