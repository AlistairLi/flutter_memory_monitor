import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlatformMemorySnapshot parses maps and chooses primary memory', () {
    final PlatformMemorySnapshot snapshot =
        PlatformMemorySnapshot.fromMap(<String, Object?>{
          'platform': 'ios',
          'collection_level': 'light',
          'ios_phys_footprint_bytes': 300,
          'ios_resident_size_bytes': 200,
          'device_total_memory_bytes': 600,
          'system_low_memory': false,
        });

    expect(snapshot.platform, 'ios');
    expect(snapshot.collectionLevel, 'light');
    expect(snapshot.primaryMemoryBytes, 300);
    expect(snapshot.memLevel, MemoryLevel.high);
    expect(snapshot.ramBucket, MemoryRamBucket.low);
    expect(snapshot.toMap()['ios_phys_footprint_bytes'], 300);
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
      detailedPlatformSnapshotInterval: Duration(seconds: 10),
      minDetailedPlatformSnapshotInterval: Duration(minutes: 2),
    );

    expect(config.effectiveForegroundInterval, const Duration(seconds: 60));
    expect(
      config.effectiveDetailedPlatformSnapshotInterval,
      const Duration(minutes: 2),
    );
  });
}
