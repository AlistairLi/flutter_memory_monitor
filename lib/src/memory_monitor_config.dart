import 'memory_models.dart';

/// 内存监控配置。
class MemoryMonitorConfig {
  /// 创建内存监控配置。
  const MemoryMonitorConfig({
    this.foregroundInterval = const Duration(seconds: 60),
    this.routeExitDelay = const Duration(seconds: 3),
    this.sceneEndDelay = const Duration(seconds: 3),
    this.maxLocalSnapshots = 30,
    this.reportNormalSnapshots = true,
    this.reportIssueImmediately = true,
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
}
