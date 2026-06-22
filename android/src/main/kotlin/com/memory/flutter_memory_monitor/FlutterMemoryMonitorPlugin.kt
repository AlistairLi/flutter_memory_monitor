package com.memory.flutter_memory_monitor

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Debug
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Flutter 线上内存监控插件的 Android 实现。 */
class FlutterMemoryMonitorPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ComponentCallbacks2 {
  /// Dart 调用 Android 内存快照方法的通道。
  private lateinit var channel : MethodChannel

  /// Android 向 Dart 推送系统内存压力事件的通道。
  private lateinit var eventChannel: EventChannel

  /// Application Context，用于读取 ActivityManager 并注册内存压力回调。
  private var applicationContext: Context? = null

  /// 当前 Dart 侧事件订阅者。
  private var eventSink: EventChannel.EventSink? = null

  /// 详细 PSS 采样线程。`Debug.getMemoryInfo()` 可能扫描 VMA，不能在主线程执行。
  private var detailedExecutor: ExecutorService = Executors.newSingleThreadExecutor()

  /// 主线程 Handler，用于把后台采样结果安全回传给 Flutter。
  private val mainHandler = Handler(Looper.getMainLooper())

  /// Flutter engine 绑定时注册 MethodChannel、EventChannel 和系统回调。
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    if (detailedExecutor.isShutdown) {
      detailedExecutor = Executors.newSingleThreadExecutor()
    }
    applicationContext = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_memory_monitor")
    channel.setMethodCallHandler(this)
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_memory_monitor/events")
    eventChannel.setStreamHandler(this)
    applicationContext?.registerComponentCallbacks(this)
  }

  /// 处理 Dart 层发来的方法调用。
  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
      "getMemorySnapshot" -> buildMemorySnapshotAsync(result)
      else -> result.notImplemented()
    }
  }

  /// Flutter engine 解绑时释放通道和系统回调，避免 Context 泄漏。
  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    applicationContext?.unregisterComponentCallbacks(this)
    applicationContext = null
    eventSink = null
    detailedExecutor.shutdownNow()
  }

  /// Dart 开始监听系统内存压力事件。
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  /// Dart 取消监听系统内存压力事件。
  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  /// Android 系统内存压力回调。
  override fun onTrimMemory(level: Int) {
    // 系统内存压力等级会直接影响 OOM 风险，立即推给 Dart 侧做一次上下文采样。
    eventSink?.success(
      mapOf(
        "type" to "android_trim_memory",
        "level" to level,
        "timestamp_ms" to System.currentTimeMillis()
      )
    )
  }

  /// Android 低内存回调。
  override fun onLowMemory() {
    // 低内存回调通常比普通采样更关键，需要作为异常事件上报。
    eventSink?.success(
      mapOf(
        "type" to "android_low_memory",
        "timestamp_ms" to System.currentTimeMillis()
      )
    )
  }

  /// 配置变化回调；内存监控无需处理该事件。
  override fun onConfigurationChanged(newConfig: Configuration) {
    // 插件只关心内存压力，配置变化无需处理。
  }

  /// 采集 Android 基础内存快照。
  private fun buildBaseMemorySnapshot(): Map<String, Any?> {
    val runtime = Runtime.getRuntime()
    val systemInfo = ActivityManager.MemoryInfo()
    val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
    activityManager?.getMemoryInfo(systemInfo)

    // memoryClass/largeMemoryClass 是 ActivityManager 暴露的进程 heap 档位，
    // 只是读取系统已维护的常量级信息，不会像 Debug.getMemoryInfo() 一样扫描 VMA，
    // 因此可以放在基础字段中用于辅助判断 Java heap OOM 风险。
    val memoryClassBytes = activityManager?.memoryClass?.toLong()?.times(1024L * 1024L)
    val largeMemoryClassBytes = activityManager?.largeMemoryClass?.toLong()?.times(1024L * 1024L)

    return mapOf(
      "platform" to "android",
      "java_heap_used_bytes" to runtime.totalMemory() - runtime.freeMemory(),
      "java_heap_max_bytes" to runtime.maxMemory(),
      "android_memory_class_bytes" to memoryClassBytes,
      "android_large_memory_class_bytes" to largeMemoryClassBytes,
      "system_available_memory_bytes" to if (activityManager != null) systemInfo.availMem else null,
      "device_total_memory_bytes" to if (activityManager != null) systemInfo.totalMem else null,
      "system_low_memory" to if (activityManager != null) systemInfo.lowMemory else null
    )
  }

  /// 后台采集 Android 内存快照。
  ///
  /// 快照包含 PSS 和 memoryStats，需要调用 `Debug.getMemoryInfo()`。
  /// 原生侧统一放到单线程 Executor 中执行，不阻塞 Flutter platform thread。
  private fun buildMemorySnapshotAsync(result: Result) {
    detailedExecutor.execute {
      try {
        val snapshot = buildMemorySnapshot()
        mainHandler.post {
          result.success(snapshot)
        }
      } catch (throwable: Throwable) {
        mainHandler.post {
          result.success(
            buildBaseMemorySnapshot() + mapOf(
              "detailed_snapshot_error" to (throwable.message ?: throwable.javaClass.simpleName)
            )
          )
        }
      }
    }
  }

  /// 实际执行内存采样。调用方必须保证不在主线程执行。
  private fun buildMemorySnapshot(): Map<String, Any?> {
    val debugInfo = Debug.MemoryInfo()
    Debug.getMemoryInfo(debugInfo)
    val memoryStats = debugInfo.memoryStats

    return buildBaseMemorySnapshot() + mapOf(
      "android_total_pss_bytes" to debugInfo.totalPss * 1024L,
      "android_dalvik_pss_bytes" to debugInfo.dalvikPss * 1024L,
      "android_native_pss_bytes" to debugInfo.nativePss * 1024L,
      "android_other_pss_bytes" to debugInfo.otherPss * 1024L,
      "android_summary_java_heap_bytes" to memoryStats.toBytes("summary.java-heap"),
      "android_summary_native_heap_bytes" to memoryStats.toBytes("summary.native-heap"),
      "android_summary_code_bytes" to memoryStats.toBytes("summary.code"),
      "android_summary_stack_bytes" to memoryStats.toBytes("summary.stack"),
      "android_summary_graphics_bytes" to memoryStats.toBytes("summary.graphics"),
      "android_summary_private_other_bytes" to memoryStats.toBytes("summary.private-other"),
      "android_summary_system_bytes" to memoryStats.toBytes("summary.system"),
      "android_summary_total_swap_bytes" to memoryStats.toBytes("summary.total-swap")
    )
  }

  /// Debug.MemoryInfo.memoryStats 中的 summary 字段单位是 KB，统一转换成 bytes 回传 Dart。
  private fun Map<String, String>.toBytes(key: String): Long? {
    return this[key]?.toLongOrNull()?.times(1024L)
  }
}
