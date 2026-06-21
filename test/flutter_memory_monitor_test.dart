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
  });

  final List<PlatformMemorySnapshot?> snapshots;
  final StreamController<MemoryPressureEvent> pressureController =
      StreamController<MemoryPressureEvent>.broadcast();
  int snapshotIndex = 0;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<PlatformMemorySnapshot?> getMemorySnapshot() async {
    if (snapshots.isEmpty) {
      return null;
    }
    final int index =
        snapshotIndex < snapshots.length ? snapshotIndex : snapshots.length - 1;
    snapshotIndex += 1;
    return snapshots[index];
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
