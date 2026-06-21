import 'dart:async';

import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_method_channel.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeFlutterMemoryMonitorPlatform
    with MockPlatformInterfaceMixin
    implements FlutterMemoryMonitorPlatform {
  FakeFlutterMemoryMonitorPlatform({
    this.snapshots = const <PlatformMemorySnapshot?>[],
    this.detailedSnapshots = const <PlatformMemorySnapshot?>[],
    this.throwOnSnapshot = false,
  });

  final List<PlatformMemorySnapshot?> snapshots;
  final List<PlatformMemorySnapshot?> detailedSnapshots;
  final bool throwOnSnapshot;
  final StreamController<MemoryPressureEvent> pressureController =
      StreamController<MemoryPressureEvent>.broadcast();
  int snapshotIndex = 0;
  int detailedSnapshotIndex = 0;
  int detailedSnapshotCallCount = 0;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<PlatformMemorySnapshot?> getMemorySnapshot() async {
    if (throwOnSnapshot) {
      throw StateError('snapshot failed');
    }
    if (snapshots.isEmpty) {
      return null;
    }
    final int index =
        snapshotIndex < snapshots.length ? snapshotIndex : snapshots.length - 1;
    snapshotIndex += 1;
    return snapshots[index];
  }

  @override
  Future<PlatformMemorySnapshot?> getDetailedMemorySnapshot() async {
    detailedSnapshotCallCount += 1;
    if (detailedSnapshots.isEmpty) {
      return getMemorySnapshot();
    }
    final int index =
        detailedSnapshotIndex < detailedSnapshots.length
            ? detailedSnapshotIndex
            : detailedSnapshots.length - 1;
    detailedSnapshotIndex += 1;
    return detailedSnapshots[index];
  }

  @override
  Stream<MemoryPressureEvent> get memoryPressureEvents {
    return pressureController.stream;
  }

  Future<void> close() {
    return pressureController.close();
  }
}

class RecordingMemoryReporter implements MemoryReporter {
  final List<MemorySnapshot> snapshots = <MemorySnapshot>[];
  final List<MemoryIssue> issues = <MemoryIssue>[];

  @override
  Future<void> reportSnapshot(MemorySnapshot snapshot) async {
    snapshots.add(snapshot);
  }

  @override
  Future<void> reportIssue(MemoryIssue issue) async {
    issues.add(issue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final FlutterMemoryMonitorPlatform initialPlatform =
      FlutterMemoryMonitorPlatform.instance;

  test('$MethodChannelFlutterMemoryMonitor is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMemoryMonitor>());
  });

  test('getPlatformVersion', () async {
    final FakeFlutterMemoryMonitorPlatform fakePlatform =
        FakeFlutterMemoryMonitorPlatform();
    final FlutterMemoryMonitor flutterMemoryMonitorPlugin =
        FlutterMemoryMonitor(platform: fakePlatform);

    expect(await flutterMemoryMonitorPlugin.getPlatformVersion(), '42');
    await fakePlatform.close();
  });

  test(
    'getSnapshot collects rss, image cache, platform data and context',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 200,
                deviceTotalMemoryBytes: 8 * 1024 * 1024 * 1024,
              ),
            ],
          );
      final FlutterMemoryMonitor monitor = FlutterMemoryMonitor(
        platform: fakePlatform,
        nowProvider: () => DateTime.fromMillisecondsSinceEpoch(1000),
        rssReader: () => 100,
        imageCacheReader:
            () => const ImageCacheMetrics(
              currentSizeBytes: 10,
              currentSize: 2,
              liveImageCount: 1,
              pendingImageCount: 0,
              maximumSizeBytes: 100,
              maximumSize: 20,
            ),
      );

      final MemorySnapshot snapshot = await monitor.getSnapshot(
        context: const <String, Object?>{'route_name': 'home'},
      );

      expect(snapshot.timestampMs, 1000);
      expect(snapshot.rssBytes, 100);
      expect(snapshot.primaryMemoryBytes, 200);
      expect(snapshot.imageCache.currentSizeBytes, 10);
      expect(snapshot.ramBucket, MemoryRamBucket.high);
      expect(snapshot.context['route_name'], 'home');
      expect(monitor.recentSnapshots, hasLength(1));
      await fakePlatform.close();
    },
  );

  test(
    'reports high memory when primary memory exceeds RAM bucket threshold',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 500,
                deviceTotalMemoryBytes: 1000,
              ),
            ],
          );
      final RecordingMemoryReporter reporter = RecordingMemoryReporter();
      final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

      monitor.start(
        reporter: reporter,
        config: const MemoryMonitorConfig(
          foregroundInterval: Duration.zero,
          reportNormalSnapshots: false,
          highMemoryThresholdByRamBucket: <String, int>{
            MemoryRamBucket.low: 400,
          },
        ),
      );
      await monitor.getSnapshot();

      expect(reporter.snapshots, isEmpty);
      expect(reporter.issues, hasLength(1));
      expect(reporter.issues.single.type, MemoryIssueType.highMemory);
      expect(reporter.issues.single.deltaBytes, 100);
      monitor.stop();
      await fakePlatform.close();
    },
  );

  test(
    'reports memory spike when increase exceeds absolute and ratio threshold',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 100,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 180,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
            ],
          );
      final RecordingMemoryReporter reporter = RecordingMemoryReporter();
      final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

      monitor.start(
        reporter: reporter,
        config: const MemoryMonitorConfig(
          foregroundInterval: Duration.zero,
          reportNormalSnapshots: false,
          memorySpikeThresholdBytes: 50,
          memorySpikeThresholdRatio: 0.2,
        ),
      );
      await monitor.getSnapshot();
      await monitor.getSnapshot();

      expect(reporter.issues, hasLength(1));
      expect(reporter.issues.single.type, MemoryIssueType.memorySpike);
      expect(reporter.issues.single.deltaBytes, 80);
      monitor.stop();
      await fakePlatform.close();
    },
  );

  test(
    'reports route retained memory after delayed route exit check',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 100,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 120,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 140,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
            ],
          );
      final RecordingMemoryReporter reporter = RecordingMemoryReporter();
      final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

      monitor.start(
        reporter: reporter,
        config: const MemoryMonitorConfig(
          foregroundInterval: Duration.zero,
          routeExitDelay: Duration.zero,
          reportNormalSnapshots: false,
          routeRetainedThresholdBytes: 10,
        ),
      );
      await monitor.markRouteEnter('HomePage');
      await monitor.markRouteExit('HomePage');

      expect(monitor.routeStack, isEmpty);
      expect(
        reporter.issues.map((MemoryIssue issue) => issue.type),
        contains(MemoryIssueType.routeMemoryRetained),
      );
      monitor.stop();
      await fakePlatform.close();
    },
  );

  test('reports system memory pressure events from platform stream', () async {
    final FakeFlutterMemoryMonitorPlatform fakePlatform =
        FakeFlutterMemoryMonitorPlatform(
          snapshots: const <PlatformMemorySnapshot?>[
            PlatformMemorySnapshot(
              platform: 'android',
              androidTotalPssBytes: 100,
              deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
            ),
          ],
        );
    final RecordingMemoryReporter reporter = RecordingMemoryReporter();
    final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

    monitor.start(
      reporter: reporter,
      config: const MemoryMonitorConfig(
        foregroundInterval: Duration.zero,
        reportNormalSnapshots: false,
      ),
    );
    fakePlatform.pressureController.add(
      const MemoryPressureEvent(
        type: 'android_trim_memory',
        timestampMs: 2000,
        level: 80,
      ),
    );
    await pumpEventQueue();

    expect(reporter.issues, hasLength(1));
    expect(reporter.issues.single.type, MemoryIssueType.systemMemoryPressure);
    expect(reporter.issues.single.context['level'], 80);
    monitor.stop();
    await fakePlatform.close();
  });

  test(
    'uses detailed platform snapshot only after configured interval',
    () async {
      DateTime now = DateTime.fromMillisecondsSinceEpoch(0);
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                collectionLevel: 'light',
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
            ],
            detailedSnapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                collectionLevel: 'detailed',
                androidTotalPssBytes: 100,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
            ],
          );
      final RecordingMemoryReporter reporter = RecordingMemoryReporter();
      final FlutterMemoryMonitor monitor = FlutterMemoryMonitor(
        platform: fakePlatform,
        nowProvider: () => now,
        rssReader: () => 50,
        imageCacheReader: () => ImageCacheMetrics.empty,
      );

      monitor.start(
        reporter: reporter,
        config: const MemoryMonitorConfig(
          foregroundInterval: Duration.zero,
          reportNormalSnapshots: false,
          collectDetailedPlatformSnapshot: true,
          detailedPlatformSnapshotInterval: Duration(seconds: 10),
          minDetailedPlatformSnapshotInterval: Duration(seconds: 10),
        ),
      );
      final MemorySnapshot first = await monitor.getSnapshot();
      now = now.add(const Duration(seconds: 5));
      final MemorySnapshot second = await monitor.getSnapshot();

      expect(first.platform?.collectionLevel, 'detailed');
      expect(second.platform?.collectionLevel, 'light');
      expect(fakePlatform.detailedSnapshotCallCount, 1);
      monitor.stop();
      await fakePlatform.close();
    },
  );

  test(
    'falls back to partial snapshot when platform snapshot throws',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(throwOnSnapshot: true);
      final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

      final MemorySnapshot snapshot = await monitor.getSnapshot();

      expect(snapshot.platform, isNull);
      expect(snapshot.rssBytes, 1);
      expect(snapshot.imageCache, ImageCacheMetrics.empty);
      await fakePlatform.close();
    },
  );

  test(
    'records scene peak, delta and pressure count in retained issue',
    () async {
      final FakeFlutterMemoryMonitorPlatform fakePlatform =
          FakeFlutterMemoryMonitorPlatform(
            snapshots: const <PlatformMemorySnapshot?>[
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 100,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 180,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 150,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
              PlatformMemorySnapshot(
                platform: 'android',
                androidTotalPssBytes: 160,
                deviceTotalMemoryBytes: 10 * 1024 * 1024 * 1024,
              ),
            ],
          );
      final RecordingMemoryReporter reporter = RecordingMemoryReporter();
      final FlutterMemoryMonitor monitor = _createMonitor(fakePlatform);

      monitor.start(
        reporter: reporter,
        config: const MemoryMonitorConfig(
          foregroundInterval: Duration.zero,
          sceneEndDelay: Duration.zero,
          reportNormalSnapshots: false,
          sceneRetainedThresholdBytes: 10,
        ),
      );
      await monitor.markSceneStart('voice_room');
      fakePlatform.pressureController.add(
        const MemoryPressureEvent(
          type: 'android_trim_memory',
          timestampMs: 2000,
          level: 80,
        ),
      );
      await pumpEventQueue();
      await monitor.markSceneEnd('voice_room');

      final MemoryIssue retainedIssue = reporter.issues.firstWhere(
        (MemoryIssue issue) =>
            issue.type == MemoryIssueType.sceneMemoryRetained,
      );
      expect(retainedIssue.context['scene_peak_memory_bytes'], 180);
      expect(retainedIssue.context['scene_delta_bytes'], 50);
      expect(retainedIssue.context['scene_memory_pressure_count'], 1);
      monitor.stop();
      await fakePlatform.close();
    },
  );
}

FlutterMemoryMonitor _createMonitor(
  FakeFlutterMemoryMonitorPlatform platform, {
  int rssBytes = 1,
}) {
  return FlutterMemoryMonitor(
    platform: platform,
    nowProvider: () => DateTime.fromMillisecondsSinceEpoch(1000),
    rssReader: () => rssBytes,
    imageCacheReader: () => ImageCacheMetrics.empty,
  );
}
