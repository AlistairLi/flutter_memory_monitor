
import 'flutter_memory_monitor_platform_interface.dart';

class FlutterMemoryMonitor {
  Future<String?> getPlatformVersion() {
    return FlutterMemoryMonitorPlatform.instance.getPlatformVersion();
  }
}
