/// 内存采样触发原因常量。
///
/// 使用字符串而不是 enum，是为了方便直接上报到日志、APM 或埋点平台。
class MemorySampleReason {
  MemorySampleReason._();

  /// 手动触发采样。
  static const String manual = 'manual';

  /// 周期定时采样。
  static const String periodic = 'periodic';

  /// 页面进入时采样。
  static const String routeEnter = 'route_enter';

  /// 页面退出时采样。
  static const String routeExit = 'route_exit';

  /// 页面退出后延迟采样，用来观察内存是否回落。
  static const String routeExitAfterDelay = 'route_exit_after_delay';

  /// 业务场景开始时采样。
  static const String sceneStart = 'scene_start';

  /// 业务场景结束时采样。
  static const String sceneEnd = 'scene_end';

  /// 业务场景结束后延迟采样，用来观察内存是否回落。
  static const String sceneEndAfterDelay = 'scene_end_after_delay';

  /// 系统内存压力回调触发采样。
  static const String systemMemoryPressure = 'system_memory_pressure';
}

/// 内存异常类型常量。
class MemoryIssueType {
  MemoryIssueType._();

  /// 进程内存超过当前设备档位阈值。
  static const String highMemory = 'high_memory';

  /// 两次采样之间内存增长过快。
  static const String memorySpike = 'memory_spike';

  /// 页面退出后仍保留较多内存。
  static const String routeMemoryRetained = 'route_memory_retained';

  /// 业务场景结束后仍保留较多内存。
  static const String sceneMemoryRetained = 'scene_memory_retained';

  /// Android trim/low memory 或 iOS memory warning。
  static const String systemMemoryPressure = 'system_memory_pressure';
}

/// 设备内存档位常量。
class MemoryRamBucket {
  MemoryRamBucket._();

  /// 低内存设备，小于 3GB。
  static const String low = 'low';

  /// 中端内存设备，3GB 到 6GB。
  static const String mid = 'mid';

  /// 高内存设备，大于等于 6GB。
  static const String high = 'high';

  /// 无法识别设备总内存时使用。
  static const String unknown = 'unknown';
}

/// Flutter 图片缓存指标。
class ImageCacheMetrics {
  /// 创建一组图片缓存指标。
  const ImageCacheMetrics({
    required this.currentSizeBytes,
    required this.currentSize,
    required this.liveImageCount,
    required this.pendingImageCount,
    required this.maximumSizeBytes,
    required this.maximumSize,
  });

  /// 当前图片缓存字节数。
  final int currentSizeBytes;

  /// 当前图片缓存条目数。
  final int currentSize;

  /// 仍被页面或组件持有的图片数量。
  final int liveImageCount;

  /// 正在解码或加载中的图片数量。
  final int pendingImageCount;

  /// 图片缓存最大字节数。
  final int maximumSizeBytes;

  /// 图片缓存最大条目数。
  final int maximumSize;

  /// 空指标，主要用于测试或没有 Flutter binding 的兜底场景。
  static const ImageCacheMetrics empty = ImageCacheMetrics(
    currentSizeBytes: 0,
    currentSize: 0,
    liveImageCount: 0,
    pendingImageCount: 0,
    maximumSizeBytes: 0,
    maximumSize: 0,
  );

  /// 转为可直接上报的 Map。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'image_cache_bytes': currentSizeBytes,
      'image_cache_count': currentSize,
      'image_live_count': liveImageCount,
      'image_pending_count': pendingImageCount,
      'image_cache_max_bytes': maximumSizeBytes,
      'image_cache_max_count': maximumSize,
    };
  }
}

/// 原生平台采集到的内存快照。
class PlatformMemorySnapshot {
  /// 创建一条原生平台内存快照。
  const PlatformMemorySnapshot({
    this.platform,
    this.androidTotalPssBytes,
    this.androidDalvikPssBytes,
    this.androidNativePssBytes,
    this.androidOtherPssBytes,
    this.iosPhysFootprintBytes,
    this.iosResidentSizeBytes,
    this.javaHeapUsedBytes,
    this.javaHeapMaxBytes,
    this.systemAvailableMemoryBytes,
    this.deviceTotalMemoryBytes,
    this.systemLowMemory,
    this.raw = const <String, Object?>{},
  });

  /// 平台名称，例如 android 或 ios。
  final String? platform;

  /// Android PSS 总量，系统视角下更接近 App 实际占用。
  final int? androidTotalPssBytes;

  /// Android Dalvik/ART 相关 PSS。
  final int? androidDalvikPssBytes;

  /// Android native PSS，用于观察图片、engine、插件和音视频等占用。
  final int? androidNativePssBytes;

  /// Android 其他 PSS。
  final int? androidOtherPssBytes;

  /// iOS phys_footprint，优先用于判断 iOS 内存压力。
  final int? iosPhysFootprintBytes;

  /// iOS resident size，作为辅助观察指标。
  final int? iosResidentSizeBytes;

  /// Android Java heap 当前使用量。
  final int? javaHeapUsedBytes;

  /// Android Java heap 上限。
  final int? javaHeapMaxBytes;

  /// 系统当前可用内存。
  final int? systemAvailableMemoryBytes;

  /// 设备总内存，用于 RAM 分档和阈值归一化。
  final int? deviceTotalMemoryBytes;

  /// 系统是否已处于低内存状态。
  final bool? systemLowMemory;

  /// 原始平台字段，保留给后续排查和兼容扩展。
  final Map<String, Object?> raw;

  /// 从 MethodChannel 返回值解析平台快照。
  factory PlatformMemorySnapshot.fromMap(Map<dynamic, dynamic> map) {
    return PlatformMemorySnapshot(
      platform: _asString(map['platform']),
      androidTotalPssBytes: _asInt(map['android_total_pss_bytes']),
      androidDalvikPssBytes: _asInt(map['android_dalvik_pss_bytes']),
      androidNativePssBytes: _asInt(map['android_native_pss_bytes']),
      androidOtherPssBytes: _asInt(map['android_other_pss_bytes']),
      iosPhysFootprintBytes: _asInt(map['ios_phys_footprint_bytes']),
      iosResidentSizeBytes: _asInt(map['ios_resident_size_bytes']),
      javaHeapUsedBytes: _asInt(map['java_heap_used_bytes']),
      javaHeapMaxBytes: _asInt(map['java_heap_max_bytes']),
      systemAvailableMemoryBytes: _asInt(map['system_available_memory_bytes']),
      deviceTotalMemoryBytes: _asInt(map['device_total_memory_bytes']),
      systemLowMemory: _asBool(map['system_low_memory']),
      raw: _normalizeMap(map),
    );
  }

  /// 当前平台最值得用来判断线上压力的主内存指标。
  int? get primaryMemoryBytes {
    return androidTotalPssBytes ??
        iosPhysFootprintBytes ??
        iosResidentSizeBytes;
  }

  /// 根据设备总内存计算 RAM 档位。
  String get ramBucket {
    final int? total = deviceTotalMemoryBytes;
    if (total == null || total <= 0) {
      return MemoryRamBucket.unknown;
    }
    const int gib = 1024 * 1024 * 1024;
    if (total < 3 * gib) {
      return MemoryRamBucket.low;
    }
    if (total < 6 * gib) {
      return MemoryRamBucket.mid;
    }
    return MemoryRamBucket.high;
  }

  /// 转为可直接上报的 Map。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (platform != null) 'platform': platform,
      if (androidTotalPssBytes != null)
        'android_total_pss_bytes': androidTotalPssBytes,
      if (androidDalvikPssBytes != null)
        'android_dalvik_pss_bytes': androidDalvikPssBytes,
      if (androidNativePssBytes != null)
        'android_native_pss_bytes': androidNativePssBytes,
      if (androidOtherPssBytes != null)
        'android_other_pss_bytes': androidOtherPssBytes,
      if (iosPhysFootprintBytes != null)
        'ios_phys_footprint_bytes': iosPhysFootprintBytes,
      if (iosResidentSizeBytes != null)
        'ios_resident_size_bytes': iosResidentSizeBytes,
      if (javaHeapUsedBytes != null) 'java_heap_used_bytes': javaHeapUsedBytes,
      if (javaHeapMaxBytes != null) 'java_heap_max_bytes': javaHeapMaxBytes,
      if (systemAvailableMemoryBytes != null)
        'system_available_memory_bytes': systemAvailableMemoryBytes,
      if (deviceTotalMemoryBytes != null)
        'device_total_memory_bytes': deviceTotalMemoryBytes,
      if (systemLowMemory != null) 'system_low_memory': systemLowMemory,
    };
  }
}

/// 一次完整的 Flutter + 原生内存采样。
class MemorySnapshot {
  /// 创建一条内存快照。
  const MemorySnapshot({
    required this.timestampMs,
    required this.reason,
    required this.rssBytes,
    required this.imageCache,
    required this.context,
    this.platform,
  });

  /// 采样时间，毫秒时间戳。
  final int timestampMs;

  /// 采样触发原因。
  final String reason;

  /// Dart `ProcessInfo.currentRss` 返回的进程常驻内存。
  final int? rssBytes;

  /// Flutter 图片缓存指标。
  final ImageCacheMetrics imageCache;

  /// 原生平台内存快照。
  final PlatformMemorySnapshot? platform;

  /// 业务上下文，例如 route、scene、app version、设备分桶等。
  final Map<String, Object?> context;

  /// 当前最适合判断内存压力的主指标。
  int? get primaryMemoryBytes {
    return platform?.primaryMemoryBytes ?? rssBytes;
  }

  /// 当前设备 RAM 档位。
  String get ramBucket {
    return platform?.ramBucket ?? MemoryRamBucket.unknown;
  }

  /// 设备总内存。
  int? get deviceTotalMemoryBytes {
    return platform?.deviceTotalMemoryBytes;
  }

  /// 转为可直接上报的 Map。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'timestamp_ms': timestampMs,
      'sample_reason': reason,
      if (rssBytes != null) 'rss_bytes': rssBytes,
      ...imageCache.toMap(),
      if (platform != null) 'platform_memory': platform!.toMap(),
      if (context.isNotEmpty) 'context': context,
    };
  }
}

/// 系统内存压力事件。
class MemoryPressureEvent {
  /// 创建系统内存压力事件。
  const MemoryPressureEvent({
    required this.type,
    required this.timestampMs,
    this.level,
    this.context = const <String, Object?>{},
  });

  /// 事件类型，例如 android_trim_memory、android_low_memory、ios_memory_warning。
  final String type;

  /// 事件发生时间，毫秒时间戳。
  final int timestampMs;

  /// Android trim memory 等级，iOS 可为空。
  final int? level;

  /// 平台附加上下文。
  final Map<String, Object?> context;

  /// 从 EventChannel 返回值解析系统内存压力事件。
  factory MemoryPressureEvent.fromMap(Map<dynamic, dynamic> map) {
    return MemoryPressureEvent(
      type: _asString(map['type']) ?? 'memory_pressure',
      timestampMs:
          _asInt(map['timestamp_ms']) ?? DateTime.now().millisecondsSinceEpoch,
      level: _asInt(map['level']),
      context: _normalizeMap(map),
    );
  }

  /// 转为可直接上报的 Map。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'type': type,
      'timestamp_ms': timestampMs,
      if (level != null) 'level': level,
      if (context.isNotEmpty) 'context': context,
    };
  }
}

/// 内存异常事件。
class MemoryIssue {
  /// 创建一条内存异常事件。
  const MemoryIssue({
    required this.type,
    required this.timestampMs,
    required this.snapshot,
    this.baselineSnapshot,
    this.deltaBytes,
    this.context = const <String, Object?>{},
  });

  /// 异常类型。
  final String type;

  /// 异常触发时间，毫秒时间戳。
  final int timestampMs;

  /// 触发异常时的快照。
  final MemorySnapshot snapshot;

  /// 用于对比的基线快照，例如页面进入时的内存。
  final MemorySnapshot? baselineSnapshot;

  /// 当前快照相对基线或上一次快照的增长量。
  final int? deltaBytes;

  /// 异常附加上下文。
  final Map<String, Object?> context;

  /// 转为可直接上报的 Map。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'type': type,
      'timestamp_ms': timestampMs,
      'snapshot': snapshot.toMap(),
      if (baselineSnapshot != null)
        'baseline_snapshot': baselineSnapshot!.toMap(),
      if (deltaBytes != null) 'delta_bytes': deltaBytes,
      if (context.isNotEmpty) 'context': context,
    };
  }
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return bool.tryParse(value);
  }
  return null;
}

Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> map) {
  return map.map((dynamic key, dynamic value) {
    return MapEntry<String, Object?>(key.toString(), value);
  });
}
