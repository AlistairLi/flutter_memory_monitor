package com.memory.flutter_memory_monitor

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Debug
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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

  /// Flutter engine 绑定时注册 MethodChannel、EventChannel 和系统回调。
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
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
      "getMemorySnapshot" -> result.success(buildMemorySnapshot())
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

  /// 采集 Android 当前进程和系统内存快照。
  private fun buildMemorySnapshot(): Map<String, Any?> {
    val debugInfo = Debug.MemoryInfo()
    Debug.getMemoryInfo(debugInfo)

    val runtime = Runtime.getRuntime()
    val systemInfo = ActivityManager.MemoryInfo()
    val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
    activityManager?.getMemoryInfo(systemInfo)

    return mapOf(
      "platform" to "android",
      "android_total_pss_bytes" to debugInfo.totalPss * 1024L,
      "android_dalvik_pss_bytes" to debugInfo.dalvikPss * 1024L,
      "android_native_pss_bytes" to debugInfo.nativePss * 1024L,
      "android_other_pss_bytes" to debugInfo.otherPss * 1024L,
      "java_heap_used_bytes" to runtime.totalMemory() - runtime.freeMemory(),
      "java_heap_max_bytes" to runtime.maxMemory(),
      "system_available_memory_bytes" to if (activityManager != null) systemInfo.availMem else null,
      "device_total_memory_bytes" to if (activityManager != null) systemInfo.totalMem else null,
      "system_low_memory" to if (activityManager != null) systemInfo.lowMemory else null
    )
  }
}
