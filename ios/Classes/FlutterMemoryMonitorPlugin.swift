import Flutter
import UIKit
import os

/// Flutter 线上内存监控插件的 iOS 实现。
public class FlutterMemoryMonitorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  /// 当前 Dart 侧事件订阅者。
  private var eventSink: FlutterEventSink?

  /// iOS memory warning 通知观察者。
  private var memoryWarningObserver: NSObjectProtocol?

  /// 注册 MethodChannel 和 EventChannel。
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_memory_monitor", binaryMessenger: registrar.messenger())
    let instance = FlutterMemoryMonitorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let eventChannel = FlutterEventChannel(name: "flutter_memory_monitor/events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
  }

  /// 处理 Dart 层发来的方法调用。
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getMemorySnapshot":
      result(buildMemorySnapshot())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Dart 开始监听 iOS memory warning。
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
      memoryWarningObserver = nil
    }
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // iOS memory warning 是线上 OOM 前的重要信号，立即推给 Dart 侧补采样。
      self?.eventSink?([
        "type": "ios_memory_warning",
        "timestamp_ms": Int64(Date().timeIntervalSince1970 * 1000)
      ])
    }
    return nil
  }

  /// Dart 取消监听 iOS memory warning。
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
      memoryWarningObserver = nil
    }
    return nil
  }

  /// 采集 iOS 当前进程内存快照。
  private func buildMemorySnapshot() -> [String: Any?] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )

    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }

    if result != KERN_SUCCESS {
      return ["platform": "ios"]
    }

    return [
      "platform": "ios",
      "ios_phys_footprint_bytes": toInt64(info.phys_footprint),
      "ios_resident_size_bytes": toInt64(info.resident_size),
      // os_proc_available_memory() 是系统给当前进程的动态可用内存估算，
      // 读取成本低，不会触发 heap 遍历或对象扫描，适合线上周期采样。
      // 它不是固定 jetsam 阈值，但能和 phys_footprint 一起判断 OOM 风险。
      "ios_available_memory_for_process_bytes": availableMemoryForProcess(),
      "device_total_memory_bytes": toInt64(ProcessInfo.processInfo.physicalMemory)
    ]
  }

  /// 读取 iOS 当前进程估算还可继续申请的内存。
  ///
  /// os_proc_available_memory 从 iOS 13 开始可用；低版本返回 nil，避免破坏 iOS 12 兼容性。
  private func availableMemoryForProcess() -> Int64? {
    if #available(iOS 13.0, *) {
      return toInt64(UInt64(os_proc_available_memory()))
    }
    return nil
  }

  /// MethodChannel 标准 codec 对 UInt64 不稳定，统一压到 Int64 范围内回传。
  private func toInt64(_ value: UInt64) -> Int64 {
    return value > UInt64(Int64.max) ? Int64.max : Int64(value)
  }
}
