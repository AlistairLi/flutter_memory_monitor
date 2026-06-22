import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlatformMemorySnapshot parses maps and chooses primary memory', () {
    final PlatformMemorySnapshot snapshot =
        PlatformMemorySnapshot.fromMap(<String, Object?>{
          'platform': 'ios',
          'ios_phys_footprint_bytes': 300,
          'ios_resident_size_bytes': 200,
          'ios_available_memory_for_process_bytes': 700,
          'device_total_memory_bytes': 600,
          'system_low_memory': false,
        });

    expect(snapshot.platform, 'ios');
    expect(snapshot.primaryMemoryBytes, 300);
    expect(snapshot.memLevel, MemoryLevel.high);
    expect(snapshot.ramBucket, MemoryRamBucket.low);
    expect(snapshot.appMemoryLimitBytes, 1000);
    expect(snapshot.appAvailableMemoryBytes, 700);
    expect(snapshot.toMap()['ios_phys_footprint_bytes'], 300);
    expect(snapshot.toMap()['app_memory_limit_bytes'], 1000);
  });

  test('PlatformMemorySnapshot parses Android app memory limits', () {
    final PlatformMemorySnapshot snapshot =
        PlatformMemorySnapshot.fromMap(<String, Object?>{
          'platform': 'android',
          'java_heap_used_bytes': 200,
          'java_heap_max_bytes': 1000,
          'android_summary_java_heap_bytes': 210,
          'android_summary_native_heap_bytes': 320,
          'android_summary_graphics_bytes': 430,
          'android_memory_class_bytes': 512,
          'android_large_memory_class_bytes': 1024,
        });

    expect(snapshot.javaHeapUsedBytes, 200);
    expect(snapshot.javaHeapMaxBytes, 1000);
    expect(snapshot.androidSummaryJavaHeapBytes, 210);
    expect(snapshot.androidSummaryNativeHeapBytes, 320);
    expect(snapshot.androidSummaryGraphicsBytes, 430);
    expect(snapshot.androidMemoryClassBytes, 512);
    expect(snapshot.androidLargeMemoryClassBytes, 1024);
    expect(snapshot.appMemoryLimitBytes, 1000);
    expect(snapshot.appAvailableMemoryBytes, 800);
    expect(snapshot.toMap()['android_summary_java_heap_bytes'], 210);
    expect(snapshot.toMap()['android_memory_class_bytes'], 512);
  });

  test('MemorySnapshot serializes image cache, platform and context', () {
    const MemorySnapshot snapshot = MemorySnapshot(
      timestampMs: 1000,
      reason: MemorySampleReason.manual,
      rssBytes: 100,
      imageCache: ImageCacheMetrics(
        currentSizeBytes: 10,
        currentSize: 1,
        liveImageCount: 1,
        pendingImageCount: 0,
        maximumSizeBytes: 100,
        maximumSize: 20,
      ),
      platform: PlatformMemorySnapshot(
        platform: 'android',
        androidTotalPssBytes: 200,
      ),
      context: <String, Object?>{'route_name': 'home'},
    );

    final Map<String, Object?> map = snapshot.toMap();

    expect(map['sample_reason'], MemorySampleReason.manual);
    expect(map['rss_bytes'], 100);
    expect(map['image_cache_bytes'], 10);
    expect(snapshot.primaryMemoryBytes, 200);
    expect(map['context'], <String, Object?>{'route_name': 'home'});
  });

  test('MemoryMonitorConfig clamps sampling intervals', () {
    const MemoryMonitorConfig config = MemoryMonitorConfig(
      foregroundInterval: Duration(seconds: 5),
      minForegroundInterval: Duration(seconds: 60),
    );

    expect(config.effectiveForegroundInterval, const Duration(seconds: 60));
  });
}
