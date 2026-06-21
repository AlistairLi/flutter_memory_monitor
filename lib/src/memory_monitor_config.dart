import 'memory_models.dart';

/// 内存监控配置。
class MemoryMonitorConfig {
  /// 创建内存监控配置。
  const MemoryMonitorConfig({
    this.foregroundInterval = const Duration(seconds: 60),
    this.minForegroundInterval = const Duration(seconds: 60),
    this.routeExitDelay = const Duration(seconds: 3),
    this.sceneEndDelay = const Duration(seconds: 3),
    this.maxLocalSnapshots = 30,
    this.reportNormalSnapshots = true,
    this.reportIssueImmediately = true,
    this.pausePeriodicSamplingInBackground = true,
    this.collectDetailedPlatformSnapshot = false,
    this.detailedPlatformSnapshotInterval = const Duration(minutes: 2),
    this.minDetailedPlatformSnapshotInterval = const Duration(minutes: 2),
    this.platformSnapshotTimeout = const Duration(seconds: 2),
    this.memorySpikeThresholdBytes = 50 * 1024 * 1024,
    this.memorySpikeThresholdRatio = 0.2,
    this.routeRetainedThresholdBytes = 10 * 1024 * 1024,
    this.sceneRetainedThresholdBytes = 30 * 1024 * 1024,
    this.highMemoryThresholdByRamBucket = const <String, int>{},
    this.highMemoryRatioByRamBucket = const <String, double>{
      MemoryRamBucket.low: 0.40,
      MemoryRamBucket.mid: 0.30,
      MemoryRamBucket.high: 0.25,
    },
  });

  /// App 前台周期采样间隔。
  final Duration foregroundInterval;

  /// App 前台周期采样最小间隔，防止调用方误配高频采样造成性能问题。
  final Duration minForegroundInterval;

  /// 页面退出后延迟采样时间，用于观察内存是否回落。
  final Duration routeExitDelay;

  /// 业务场景结束后延迟采样时间，用于观察内存是否回落。
  final Duration sceneEndDelay;

  /// 本地保留的最近快照数量。
  final int maxLocalSnapshots;

  /// 是否将普通快照交给上报器；关闭后仍会上报异常。
  final bool reportNormalSnapshots;

  /// 是否发现异常后立即调用上报器。
  final bool reportIssueImmediately;

  /// 是否在后台暂停周期采样。
  final bool pausePeriodicSamplingInBackground;

  /// 是否允许采集包含 Android PSS 的详细平台快照。
  ///
  /// Android 详细快照会调用 `Debug.getMemoryInfo()`，该 API 可能扫描 VMA 并触发
  /// `libmeminfo.so` 慢调用，所以默认关闭，只建议灰度或专项诊断低频打开。
  final bool collectDetailedPlatformSnapshot;

  /// 详细平台快照采样间隔。
  final Duration detailedPlatformSnapshotInterval;

  /// 详细平台快照最小采样间隔。
  final Duration minDetailedPlatformSnapshotInterval;

  /// 平台通道采样超时时间，避免原生侧异常慢调用拖住 Dart 自动采样链路。
  final Duration platformSnapshotTimeout;

  /// 单次内存增长的绝对阈值。
  final int memorySpikeThresholdBytes;

  /// 单次内存增长的相对阈值。
  final double memorySpikeThresholdRatio;

  /// 页面退出后保留内存的默认阈值。
  final int routeRetainedThresholdBytes;

  /// 业务场景结束后保留内存的默认阈值。
  final int sceneRetainedThresholdBytes;

  /// 按 RAM 档位配置的高内存绝对阈值，优先级高于比例阈值。
  final Map<String, int> highMemoryThresholdByRamBucket;

  /// 按 RAM 档位配置的高内存比例阈值。
  final Map<String, double> highMemoryRatioByRamBucket;

  /// 生效的前台采样间隔。`Duration.zero` 表示关闭周期采样。
  Duration get effectiveForegroundInterval {
    if (foregroundInterval <= Duration.zero) {
      return Duration.zero;
    }
    if (foregroundInterval < minForegroundInterval) {
      return minForegroundInterval;
    }
    return foregroundInterval;
  }

  /// 生效的详细平台快照间隔。`Duration.zero` 表示每次允许检查。
  Duration get effectiveDetailedPlatformSnapshotInterval {
    if (detailedPlatformSnapshotInterval <= Duration.zero) {
      return Duration.zero;
    }
    if (detailedPlatformSnapshotInterval <
        minDetailedPlatformSnapshotInterval) {
      return minDetailedPlatformSnapshotInterval;
    }
    return detailedPlatformSnapshotInterval;
  }
}
