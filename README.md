# flutter_memory_monitor

`flutter_memory_monitor` 是一个轻量级 Flutter 线上内存监控插件，用于采集进程内存、图片缓存、Android PSS、iOS phys_footprint 以及系统内存压力信号。

## 能力

- Flutter 层采集 `ProcessInfo.currentRss` 和 `ImageCache` 指标。
- Android 采集 total/dalvik/native/other PSS、Java heap、系统可用内存和低内存状态。
- iOS 采集 `phys_footprint`、resident size 和设备总内存。
- 支持周期采样、手动采样、页面进入/退出、业务场景开始/结束。
- 支持高内存、单次内存暴涨、页面/场景退出后不回落、系统内存压力事件识别。
- 默认 Android 采样不调用 `Debug.getMemoryInfo()`，避免 `libmeminfo.so` 慢调用导致 ANR。

## 基本使用

```dart
final monitor = FlutterMemoryMonitor();

monitor.start(
  config: const MemoryMonitorConfig(
    foregroundInterval: Duration(seconds: 60),
    routeExitDelay: Duration(seconds: 3),
    sceneEndDelay: Duration(seconds: 3),
    collectDetailedPlatformSnapshot: false,
  ),
  reporter: MyMemoryReporter(),
  contextProvider: () => <String, Object?>{
    'app_version': '1.0.0',
    'user_bucket': 'anonymous_bucket',
  },
);

await monitor.markRouteEnter('HomePage');
await monitor.markSceneStart('live_room', context: {'room_id': 'demo'});

final snapshot = await monitor.getSnapshot(reason: MemorySampleReason.manual);

await monitor.markSceneEnd('live_room');
await monitor.markRouteExit('HomePage');
```

实现上报器：

```dart
class MyMemoryReporter implements MemoryReporter {
  @override
  Future<void> reportSnapshot(MemorySnapshot snapshot) async {
    // 普通快照建议批量上报到 APM、日志或自建埋点平台。
    upload(snapshot.toMap());
  }

  @override
  Future<void> reportIssue(MemoryIssue issue) async {
    // 异常事件建议立即上报。
    upload(issue.toMap());
  }
}
```

## 指标说明

| 字段 | 说明 |
| --- | --- |
| `rss_bytes` | Dart 层读取的进程常驻内存 |
| `image_cache_bytes` | Flutter 图片缓存字节数 |
| `android_total_pss_bytes` | Android 系统视角下 App PSS 总量 |
| `android_native_pss_bytes` | Android native PSS，用于排查图片、engine、插件、音视频等占用 |
| `ios_phys_footprint_bytes` | iOS 内存压力判断的优先指标 |
| `device_total_memory_bytes` | 设备总内存，用于 RAM 分档 |

## 注意事项

- 插件第一版只做低成本线上采样，不做 heap dump、VM Service snapshot 或对象级跟踪。
- Android 默认返回轻量快照；`android_total_pss_bytes`、`android_native_pss_bytes` 等 PSS 字段只会在 `collectDetailedPlatformSnapshot=true` 且达到低频间隔时采集。
- Android 详细快照会在后台线程调用 `Debug.getMemoryInfo()`，仍建议只在灰度、诊断或专项排查中开启。
- `contextProvider` 中不要放手机号、token、精确用户标识等敏感信息。
- 默认前台周期采样为 60 秒；插件会对过短采样间隔做最小值保护，并在后台暂停周期采样。
- 页面/场景退出后的内存不回落只是“疑似泄漏”信号，最终引用链仍需结合 DevTools、Android Studio Profiler 或 Xcode Instruments 定位。
