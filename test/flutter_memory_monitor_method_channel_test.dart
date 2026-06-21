import 'package:flutter/services.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterMemoryMonitor platform =
      MethodChannelFlutterMemoryMonitor();
  const MethodChannel channel = MethodChannel('flutter_memory_monitor');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'getMemorySnapshot':
              return <String, Object?>{
                'platform': 'android',
                'android_total_pss_bytes': 1024,
                'android_native_pss_bytes': 512,
                'device_total_memory_bytes': 8 * 1024 * 1024 * 1024,
              };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('getMemorySnapshot', () async {
    final PlatformMemorySnapshot? snapshot = await platform.getMemorySnapshot();

    expect(snapshot, isNotNull);
    expect(snapshot!.platform, 'android');
    expect(snapshot.androidTotalPssBytes, 1024);
    expect(snapshot.androidNativePssBytes, 512);
    expect(snapshot.ramBucket, MemoryRamBucket.high);
  });
}
