import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'flutter_memory_monitor_platform_interface.dart';
import 'src/memory_models.dart';
import 'src/memory_monitor_config.dart';

export 'src/memory_models.dart';
export 'src/memory_monitor_config.dart';

/// 读取当前时间的函数类型，便于单元测试注入固定时间。
typedef MemoryNowProvider = DateTime Function();

/// 读取 RSS 的函数类型，便于测试和平台差异兜底。
typedef MemoryRssReader = int? Function();

/// 读取图片缓存指标的函数类型。
typedef MemoryImageCacheReader = ImageCacheMetrics Function();

/// 业务上下文提供器，调用方可补充 app version、用户分桶、网络类型等字段。
typedef MemoryContextProvider = Map<String, Object?> Function();

/// 内存快照和异常上报接口。
///
/// SDK 只负责采样和识别异常，实际上传到 Firebase、Sentry、自建埋点等平台由业务侧实现。
abstract class MemoryReporter {
  /// 上报普通内存快照。
  Future<void> reportSnapshot(MemorySnapshot snapshot);

  /// 上报内存异常事件。
  Future<void> reportIssue(MemoryIssue issue);
}

/// Flutter 线上内存监控入口。
///
/// 负责采集 Flutter 图片缓存、Dart RSS、原生平台内存，并根据配置识别高内存、
/// 内存暴涨、页面/场景退出后不回落等第一版线上可观测问题。
class FlutterMemoryMonitor with WidgetsBindingObserver {
  /// 创建内存监控器。
  FlutterMemoryMonitor({
    FlutterMemoryMonitorPlatform? platform,
    MemoryNowProvider? nowProvider,
    MemoryRssReader? rssReader,
    MemoryImageCacheReader? imageCacheReader,
  }) : _platform = platform ?? FlutterMemoryMonitorPlatform.instance,
       _nowProvider = nowProvider ?? DateTime.now,
       _rssReader = rssReader ?? _readCurrentRss,
       _imageCacheReader = imageCacheReader ?? _readImageCacheMetrics;

  final FlutterMemoryMonitorPlatform _platform;
  final MemoryNowProvider _nowProvider;
  final MemoryRssReader _rssReader;
  final MemoryImageCacheReader _imageCacheReader;

  MemoryMonitorConfig _config = const MemoryMonitorConfig();
  MemoryReporter? _reporter;
  MemoryContextProvider? _contextProvider;
  Timer? _periodicTimer;
  StreamSubscription<MemoryPressureEvent>? _pressureSubscription;
  final Set<Timer> _retainedCheckTimers = <Timer>{};
  MemorySnapshot? _previousSnapshot;
  bool _isRunning = false;
  bool _isSampling = false;
  bool _isForeground = true;
  bool _observingLifecycle = false;
  String _appState = 'foreground';
  int _memoryPressureCount = 0;
  final Map<String, DateTime> _lastIssueReportedAtByType =
      <String, DateTime>{};
  final List<MemorySnapshot> _recentSnapshots = <MemorySnapshot>[];
  final Map<String, MemorySnapshot> _routeBaselines =
      <String, MemorySnapshot>{};
  final Map<String, _SceneMemoryState> _sceneStates =
      <String, _SceneMemoryState>{};
  final List<String> _routeStack = <String>[];
  final Set<String> _activeScenes = <String>{};

  /// 最近保留的内存快照，用于崩溃前后或异常样本排查。
  List<MemorySnapshot> get recentSnapshots {
    return List<MemorySnapshot>.unmodifiable(_recentSnapshots);
  }

  /// 当前页面栈快照。
  List<String> get routeStack {
    return List<String>.unmodifiable(_routeStack);
  }

  /// 当前活跃业务场景快照。
  Set<String> get activeScenes {
    return Set<String>.unmodifiable(_activeScenes);
  }

  /// 获取平台版本。保留模板插件原有 API，避免破坏已有调用。
  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  /// 启动前台周期采样和系统内存压力监听。
  ///
  /// 第一版不做本地持久化，因此疑似 OOM 补报需要业务侧结合最近快照自行落盘。
  void start({
    required MemoryReporter reporter,
    MemoryMonitorConfig config = const MemoryMonitorConfig(),
    MemoryContextProvider? contextProvider,
  }) {
    stop();
    _isRunning = true;
    _reporter = reporter;
    _config = config;
    _contextProvider = contextProvider;
    _updateLifecycleState(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;

    _restartPeriodicTimer();

    _pressureSubscription = _platform.memoryPressureEvents.listen(
      (MemoryPressureEvent event) {
        unawaited(_handleMemoryPressure(event));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('flutter_memory_monitor event stream failed: $error');
      },
    );
  }

  /// 停止周期采样、延迟检查和系统内存压力监听。
  void stop() {
    _isRunning = false;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    for (final Timer timer in _retainedCheckTimers) {
      timer.cancel();
    }
    _retainedCheckTimers.clear();
    unawaited(_pressureSubscription?.cancel());
    _pressureSubscription = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _isSampling = false;
    _reporter = null;
    _contextProvider = null;
    _lastIssueReportedAtByType.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateLifecycleState(state);
    _restartPeriodicTimer();
    if (!_isRunning) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _collectAutomaticSnapshot(reason: MemorySampleReason.foreground),
      );
    }
  }

  /// 立即采集一条内存快照。
  Future<MemorySnapshot> getSnapshot({
    String reason = MemorySampleReason.manual,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    return _collectSnapshot(reason: reason, context: context);
  }

  /// 标记页面进入，并记录页面级内存基线。
  Future<MemorySnapshot> markRouteEnter(
    String routeName, {
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    _routeStack.add(routeName);
    final MemorySnapshot snapshot = await _collectSnapshot(
      reason: MemorySampleReason.routeEnter,
      context: <String, Object?>{...context, 'route_name': routeName},
    );
    _routeBaselines[routeName] = snapshot;
    return snapshot;
  }

  /// 标记页面退出，并在配置的延迟后检查内存是否回落。
  Future<MemorySnapshot> markRouteExit(
    String routeName, {
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    final int index = _routeStack.lastIndexOf(routeName);
    if (index >= 0) {
      _routeStack.removeAt(index);
    }

    final MemorySnapshot? baseline = _routeBaselines.remove(routeName);
    late final MemorySnapshot snapshot;
    if (_config.collectRouteExitSnapshot || baseline == null) {
      snapshot = await _collectSnapshot(
        reason: MemorySampleReason.routeExit,
        context: <String, Object?>{...context, 'route_name': routeName},
      );
    } else {
      snapshot = baseline;
    }
    if (baseline != null) {
      await _scheduleRetainedCheck(
        baseline: baseline,
        reason: MemorySampleReason.routeExitAfterDelay,
        issueType: MemoryIssueType.routeMemoryRetained,
        thresholdBytes: _config.routeRetainedThresholdBytes,
        delay: _config.routeExitDelay,
        context: <String, Object?>{...context, 'route_name': routeName},
      );
    }
    return snapshot;
  }

  /// 标记业务场景开始，并记录场景级内存基线。
  Future<MemorySnapshot> markSceneStart(
    String sceneName, {
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    _activeScenes.add(sceneName);
    final MemorySnapshot snapshot = await _collectSnapshot(
      reason: MemorySampleReason.sceneStart,
      context: <String, Object?>{...context, 'scene_name': sceneName},
    );
    _sceneStates[sceneName] = _SceneMemoryState(snapshot);
    return snapshot;
  }

  /// 标记业务场景结束，并在配置的延迟后检查内存是否回落。
  Future<MemorySnapshot> markSceneEnd(
    String sceneName, {
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    final MemorySnapshot snapshot = await _collectSnapshot(
      reason: MemorySampleReason.sceneEnd,
      context: <String, Object?>{...context, 'scene_name': sceneName},
    );
    _activeScenes.remove(sceneName);
    final _SceneMemoryState? sceneState = _sceneStates.remove(sceneName);
    if (sceneState != null) {
      await _scheduleRetainedCheck(
        baseline: sceneState.baselineSnapshot,
        reason: MemorySampleReason.sceneEndAfterDelay,
        issueType: MemoryIssueType.sceneMemoryRetained,
        thresholdBytes: _config.sceneRetainedThresholdBytes,
        delay: _config.sceneEndDelay,
        context: <String, Object?>{
          ...context,
          'scene_name': sceneName,
          ...sceneState.toContext(snapshot),
        },
      );
    }
    return snapshot;
  }

  Future<void> _handleMemoryPressure(MemoryPressureEvent event) async {
    _memoryPressureCount += 1;
    for (final _SceneMemoryState state in _sceneStates.values) {
      state.memoryPressureCount += 1;
    }
    final MemorySnapshot? snapshot = await _collectAutomaticSnapshot(
      reason: MemorySampleReason.systemMemoryPressure,
      context: <String, Object?>{'memory_pressure': event.toMap()},
    );
    if (snapshot == null) {
      return;
    }
    await _reportIssue(
      MemoryIssue(
        type: MemoryIssueType.systemMemoryPressure,
        timestampMs: snapshot.timestampMs,
        snapshot: snapshot,
        context: event.toMap(),
      ),
    );
  }

  Future<MemorySnapshot> _collectSnapshot({
    required String reason,
    required Map<String, Object?> context,
  }) async {
    final DateTime now = _nowProvider();
    final PlatformMemorySnapshot? platformSnapshot =
        await _readPlatformSnapshot();
    final MemorySnapshot snapshot = MemorySnapshot(
      timestampMs: now.millisecondsSinceEpoch,
      reason: reason,
      rssBytes: _readRssSafely(),
      imageCache: _readImageCacheSafely(),
      platform: platformSnapshot,
      context: _mergeContext(context),
    );

    final MemorySnapshot? previous = _previousSnapshot;
    _rememberSnapshot(snapshot);
    _previousSnapshot = snapshot;
    _updateActiveSceneStats(snapshot);

    if (_config.reportNormalSnapshots) {
      await _reportSnapshot(snapshot);
    }
    await _detectSnapshotIssues(snapshot, previous);
    return snapshot;
  }

  Future<MemorySnapshot?> _collectAutomaticSnapshot({
    required String reason,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    // 自动采样使用串行保护：如果上一次还没完成，直接跳过本次，避免堆积导致卡顿。
    if (!_isRunning || _isSampling) {
      return null;
    }
    _isSampling = true;
    try {
      return await _collectSnapshot(
        reason: reason,
        context: context,
      );
    } catch (error) {
      debugPrint('flutter_memory_monitor auto snapshot failed: $error');
      return null;
    } finally {
      _isSampling = false;
    }
  }

  Future<PlatformMemorySnapshot?> _readPlatformSnapshot() async {
    try {
      return await _platform
          .getMemorySnapshot()
          .timeout(_config.platformSnapshotTimeout);
    } catch (error) {
      debugPrint('flutter_memory_monitor platform snapshot failed: $error');
      return null;
    }
  }

  Map<String, Object?> _mergeContext(Map<String, Object?> context) {
    Map<String, Object?> providerContext = const <String, Object?>{};
    try {
      providerContext = _contextProvider?.call() ?? const <String, Object?>{};
    } catch (error) {
      debugPrint('flutter_memory_monitor contextProvider failed: $error');
    }
    return <String, Object?>{
      ...providerContext,
      ...context,
      'app_state': _appState,
      'memory_pressure_count': _memoryPressureCount,
      if (_routeStack.isNotEmpty) 'route_stack': List<String>.of(_routeStack),
      if (_activeScenes.isNotEmpty)
        'active_scenes': List<String>.of(_activeScenes),
    };
  }

  void _rememberSnapshot(MemorySnapshot snapshot) {
    final int max = _config.maxLocalSnapshots;
    if (max <= 0) {
      _recentSnapshots.clear();
      return;
    }
    _recentSnapshots.add(snapshot);
    while (_recentSnapshots.length > max) {
      _recentSnapshots.removeAt(0);
    }
  }

  void _updateActiveSceneStats(MemorySnapshot snapshot) {
    for (final _SceneMemoryState state in _sceneStates.values) {
      state.record(snapshot);
    }
  }

  Future<void> _detectSnapshotIssues(
    MemorySnapshot snapshot,
    MemorySnapshot? previous,
  ) async {
    await _detectHighMemory(snapshot);
    if (previous != null) {
      await _detectMemorySpike(snapshot, previous);
    }
  }

  Future<void> _detectHighMemory(MemorySnapshot snapshot) async {
    final int? memory = snapshot.primaryMemoryBytes;
    if (memory == null) {
      return;
    }
    final int? threshold = _highMemoryThreshold(snapshot);
    if (threshold == null || memory <= threshold) {
      return;
    }
    await _reportIssue(
      MemoryIssue(
        type: MemoryIssueType.highMemory,
        timestampMs: snapshot.timestampMs,
        snapshot: snapshot,
        deltaBytes: memory - threshold,
        context: <String, Object?>{
          'threshold_bytes': threshold,
          'ram_bucket': snapshot.ramBucket,
          'device_tier': snapshot.deviceTier,
          'mem_level': snapshot.memLevel,
        },
      ),
    );
  }

  int? _highMemoryThreshold(MemorySnapshot snapshot) {
    final String bucket = snapshot.ramBucket;
    final int? absolute = _config.highMemoryThresholdByRamBucket[bucket];
    if (absolute != null) {
      return absolute;
    }

    final int? total = snapshot.deviceTotalMemoryBytes;
    final double? ratio = _config.highMemoryRatioByRamBucket[bucket];
    if (total == null || ratio == null) {
      return null;
    }
    return (total * ratio).round();
  }

  Future<void> _detectMemorySpike(
    MemorySnapshot snapshot,
    MemorySnapshot previous,
  ) async {
    final _MemorySignal? current = _memorySignal(snapshot);
    final _MemorySignal? previousSignal = _memorySignal(previous);
    if (current == null ||
        previousSignal == null ||
        current.source != previousSignal.source ||
        previousSignal.bytes <= 0) {
      return;
    }

    final int delta = current.bytes - previousSignal.bytes;
    final double ratio = delta / previousSignal.bytes;
    if (delta < _config.memorySpikeThresholdBytes ||
        ratio < _config.memorySpikeThresholdRatio) {
      return;
    }

    await _reportIssue(
      MemoryIssue(
        type: MemoryIssueType.memorySpike,
        timestampMs: snapshot.timestampMs,
        snapshot: snapshot,
        baselineSnapshot: previous,
        deltaBytes: delta,
        context: <String, Object?>{
          'memory_signal_source': current.source,
          'previous_memory_bytes': previousSignal.bytes,
          'current_memory_bytes': current.bytes,
          'ratio': ratio,
        },
      ),
    );
  }

  _MemorySignal? _memorySignal(MemorySnapshot snapshot) {
    final PlatformMemorySnapshot? platform = snapshot.platform;
    final int? androidPss = platform?.androidTotalPssBytes;
    if (androidPss != null) {
      return _MemorySignal('android_total_pss_bytes', androidPss);
    }
    final int? iosFootprint = platform?.iosPhysFootprintBytes;
    if (iosFootprint != null) {
      return _MemorySignal('ios_phys_footprint_bytes', iosFootprint);
    }
    final int? iosResident = platform?.iosResidentSizeBytes;
    if (iosResident != null) {
      return _MemorySignal('ios_resident_size_bytes', iosResident);
    }
    final int? rss = snapshot.rssBytes;
    if (rss != null) {
      return _MemorySignal('rss_bytes', rss);
    }
    return null;
  }

  Future<void> _scheduleRetainedCheck({
    required MemorySnapshot baseline,
    required String reason,
    required String issueType,
    required int thresholdBytes,
    required Duration delay,
    required Map<String, Object?> context,
  }) async {
    // 测试和极短场景使用 zero delay 时直接 await，避免异步检查不可控。
    if (delay <= Duration.zero) {
      if (!_isRunning) {
        return;
      }
      await _checkRetainedMemory(
        baseline: baseline,
        reason: reason,
        issueType: issueType,
        thresholdBytes: thresholdBytes,
        context: context,
      );
      return;
    }

    late final Timer timer;
    timer = Timer(delay, () {
      _retainedCheckTimers.remove(timer);
      if (!_isRunning) {
        return;
      }
      unawaited(
        _checkRetainedMemory(
          baseline: baseline,
          reason: reason,
          issueType: issueType,
          thresholdBytes: thresholdBytes,
          context: context,
        ),
      );
    });
    _retainedCheckTimers.add(timer);
  }

  Future<void> _checkRetainedMemory({
    required MemorySnapshot baseline,
    required String reason,
    required String issueType,
    required int thresholdBytes,
    required Map<String, Object?> context,
  }) async {
    if (!_isRunning) {
      return;
    }
    final MemorySnapshot snapshot = await _collectSnapshot(
      reason: reason,
      context: context,
    );
    final _MemorySignal? current = _memorySignal(snapshot);
    final _MemorySignal? baselineSignal = _memorySignal(baseline);
    if (current == null ||
        baselineSignal == null ||
        current.source != baselineSignal.source) {
      return;
    }

    final int delta = current.bytes - baselineSignal.bytes;
    if (delta <= thresholdBytes) {
      return;
    }

    await _reportIssue(
      MemoryIssue(
        type: issueType,
        timestampMs: snapshot.timestampMs,
        snapshot: snapshot,
        baselineSnapshot: baseline,
        deltaBytes: delta,
        context: <String, Object?>{
          ...context,
          'memory_signal_source': current.source,
          'threshold_bytes': thresholdBytes,
        },
      ),
    );
  }

  void _restartPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    if (!_isRunning) {
      return;
    }
    if (_config.pausePeriodicSamplingInBackground && !_isForeground) {
      return;
    }
    final Duration interval = _config.effectiveForegroundInterval;
    if (interval <= Duration.zero) {
      return;
    }
    _periodicTimer = Timer.periodic(interval, (_) {
      unawaited(_collectAutomaticSnapshot(reason: MemorySampleReason.periodic));
    });
  }

  void _updateLifecycleState(AppLifecycleState? state) {
    _isForeground = state == null || state == AppLifecycleState.resumed;
    _appState = _isForeground ? 'foreground' : 'background';
  }

  Future<void> _reportSnapshot(MemorySnapshot snapshot) async {
    final MemoryReporter? reporter = _reporter;
    if (reporter == null) {
      return;
    }
    try {
      await reporter.reportSnapshot(snapshot);
    } catch (error) {
      debugPrint('flutter_memory_monitor reportSnapshot failed: $error');
    }
  }

  Future<void> _reportIssue(MemoryIssue issue) async {
    if (!_config.reportIssueImmediately) {
      return;
    }
    if (_isIssueInCooldown(issue)) {
      return;
    }
    final MemoryReporter? reporter = _reporter;
    if (reporter == null) {
      return;
    }
    try {
      await reporter.reportIssue(issue);
      _lastIssueReportedAtByType[issue.type] =
          DateTime.fromMillisecondsSinceEpoch(issue.timestampMs);
    } catch (error) {
      debugPrint('flutter_memory_monitor reportIssue failed: $error');
    }
  }

  bool _isIssueInCooldown(MemoryIssue issue) {
    final Duration cooldown = _config.issueReportCooldown;
    if (cooldown <= Duration.zero) {
      return false;
    }
    final DateTime issueTime = DateTime.fromMillisecondsSinceEpoch(
      issue.timestampMs,
    );
    final DateTime? lastReportedAt = _lastIssueReportedAtByType[issue.type];
    return lastReportedAt != null &&
        issueTime.difference(lastReportedAt) < cooldown;
  }

  int? _readRssSafely() {
    try {
      return _rssReader();
    } catch (error) {
      debugPrint('flutter_memory_monitor rss read failed: $error');
      return null;
    }
  }

  ImageCacheMetrics _readImageCacheSafely() {
    try {
      return _imageCacheReader();
    } catch (error) {
      debugPrint('flutter_memory_monitor image cache read failed: $error');
      return ImageCacheMetrics.empty;
    }
  }
}

class _MemorySignal {
  const _MemorySignal(this.source, this.bytes);

  final String source;
  final int bytes;
}

int? _readCurrentRss() {
  return ProcessInfo.currentRss;
}

ImageCacheMetrics _readImageCacheMetrics() {
  final ImageCache cache = PaintingBinding.instance.imageCache;
  return ImageCacheMetrics(
    currentSizeBytes: cache.currentSizeBytes,
    currentSize: cache.currentSize,
    liveImageCount: cache.liveImageCount,
    pendingImageCount: cache.pendingImageCount,
    maximumSizeBytes: cache.maximumSizeBytes,
    maximumSize: cache.maximumSize,
  );
}

class _SceneMemoryState {
  _SceneMemoryState(this.baselineSnapshot)
    : peakSnapshot = baselineSnapshot,
      peakMemoryBytes = baselineSnapshot.primaryMemoryBytes;

  final MemorySnapshot baselineSnapshot;
  MemorySnapshot peakSnapshot;
  int? peakMemoryBytes;
  int memoryPressureCount = 0;

  void record(MemorySnapshot snapshot) {
    final int? memory = snapshot.primaryMemoryBytes;
    if (memory == null) {
      return;
    }
    final int? currentPeak = peakMemoryBytes;
    if (currentPeak == null || memory > currentPeak) {
      peakMemoryBytes = memory;
      peakSnapshot = snapshot;
    }
  }

  Map<String, Object?> toContext(MemorySnapshot endSnapshot) {
    final int? startMemory = baselineSnapshot.primaryMemoryBytes;
    final int? endMemory = endSnapshot.primaryMemoryBytes;
    return <String, Object?>{
      if (startMemory != null) 'scene_start_memory_bytes': startMemory,
      if (endMemory != null) 'scene_end_memory_bytes': endMemory,
      if (peakMemoryBytes != null) 'scene_peak_memory_bytes': peakMemoryBytes,
      if (startMemory != null && endMemory != null)
        'scene_delta_bytes': endMemory - startMemory,
      'scene_memory_pressure_count': memoryPressureCount,
    };
  }
}
