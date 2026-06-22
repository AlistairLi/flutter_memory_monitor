import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor_method_channel.dart';

class NativeMemoryPressureDemoPage extends StatefulWidget {
  const NativeMemoryPressureDemoPage({required this.monitor, super.key});

  final FlutterMemoryMonitor monitor;

  @override
  State<NativeMemoryPressureDemoPage> createState() =>
      _NativeMemoryPressureDemoPageState();
}

class _NativeMemoryPressureDemoPageState
    extends State<NativeMemoryPressureDemoPage> {
  static const int _chunkBytes = 16 * 1024 * 1024;
  static const int _maxChunks = 24;

  final MethodChannelFlutterMemoryMonitor _platform =
      MethodChannelFlutterMemoryMonitor();
  final List<Uint8List> _retainedChunks = <Uint8List>[];
  final List<String> _events = <String>[];
  StreamSubscription<MemoryPressureEvent>? _pressureSubscription;
  PlatformMemorySnapshot? _platformSnapshot;
  MemorySnapshot? _monitorSnapshot;
  bool _allocating = false;

  @override
  void initState() {
    super.initState();
    _pressureSubscription = _platform.memoryPressureEvents.listen(
      _handlePressureEvent,
      onError: (Object error, StackTrace stackTrace) {
        _insertEvent('event stream error: $error');
      },
    );
    unawaited(
      widget.monitor.markRouteEnter(
        'NativeMemoryPressureDemoPage',
        context: const <String, Object?>{'demo': 'native_memory_pressure'},
      ),
    );
    unawaited(_refreshSnapshots(reason: 'page_enter'));
  }

  @override
  void dispose() {
    unawaited(_pressureSubscription?.cancel());
    unawaited(
      widget.monitor.markRouteExit(
        'NativeMemoryPressureDemoPage',
        context: const <String, Object?>{'demo': 'native_memory_pressure'},
      ),
    );
    _retainedChunks.clear();
    super.dispose();
  }

  Future<void> _allocateMemoryPressure() async {
    if (_allocating || _retainedChunks.length >= _maxChunks) {
      return;
    }
    setState(() {
      _allocating = true;
    });

    final int start = _retainedChunks.length;
    final int target = (start + 4).clamp(0, _maxChunks);
    for (int index = start; index < target; index += 1) {
      final Uint8List chunk = Uint8List(_chunkBytes);
      for (int offset = 0; offset < chunk.length; offset += 4096) {
        chunk[offset] = (index + offset) & 0xff;
      }
      _retainedChunks.add(chunk);
      _insertEvent(
        'allocated chunk ${index + 1}/$_maxChunks, retained=${_formatBytes(_retainedBytes)}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    await _refreshSnapshots(reason: 'allocate_memory_pressure');
    if (!mounted) {
      return;
    }
    setState(() {
      _allocating = false;
    });
  }

  Future<void> _releaseMemory() async {
    _retainedChunks.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _insertEvent('released retained chunks');
    await _refreshSnapshots(reason: 'release_memory_pressure');
  }

  Future<void> _refreshSnapshots({String reason = 'manual_refresh'}) async {
    PlatformMemorySnapshot? platformSnapshot;
    try {
      platformSnapshot = await _platform.getMemorySnapshot().timeout(
        const Duration(seconds: 2),
      );
    } catch (error) {
      _insertEvent('getMemorySnapshot failed: $error');
    }
    final MemorySnapshot monitorSnapshot = await widget.monitor.getSnapshot(
      reason: MemorySampleReason.manual,
      context: <String, Object?>{
        'button': reason,
        'demo': 'native_memory_pressure',
        'retained_bytes': _retainedBytes,
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _platformSnapshot = platformSnapshot;
      _monitorSnapshot = monitorSnapshot;
    });
  }

  void _handlePressureEvent(MemoryPressureEvent event) {
    _insertEvent(
      'memoryPressureEvents: type=${event.type}, level=${event.level ?? '-'}, time=${event.timestampMs}',
    );
  }

  void _insertEvent(String event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _events.insert(0, event);
      if (_events.length > 40) {
        _events.removeRange(40, _events.length);
      }
    });
  }

  int get _retainedBytes {
    return _retainedChunks.length * _chunkBytes;
  }

  @override
  Widget build(BuildContext context) {
    final PlatformMemorySnapshot? platform = _platformSnapshot;
    final MemorySnapshot? monitor = _monitorSnapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Native memory pressure demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _PressureStatusCard(
            retainedBytes: _retainedBytes,
            chunkCount: _retainedChunks.length,
            maxChunks: _maxChunks,
            platformSnapshot: platform,
            monitorSnapshot: monitor,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _allocating || _retainedChunks.length >= _maxChunks
                ? null
                : _allocateMemoryPressure,
            child: Text(_allocating ? '正在分配内存...' : '分配 64 MB 制造压力'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _refreshSnapshots,
            child: const Text('刷新原生内存快照'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _retainedChunks.isEmpty ? null : _releaseMemory,
            child: const Text('释放测试内存'),
          ),
          const SizedBox(height: 16),
          const Text('memoryPressureEvents 原始事件'),
          const SizedBox(height: 8),
          if (_events.isEmpty)
            const Text('暂无事件。继续点击分配内存，等待系统触发原生内存压力回调。')
          else
            ..._events.map(
              (String event) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(event),
              ),
            ),
        ],
      ),
    );
  }
}

class _PressureStatusCard extends StatelessWidget {
  const _PressureStatusCard({
    required this.retainedBytes,
    required this.chunkCount,
    required this.maxChunks,
    required this.platformSnapshot,
    required this.monitorSnapshot,
  });

  final int retainedBytes;
  final int chunkCount;
  final int maxChunks;
  final PlatformMemorySnapshot? platformSnapshot;
  final MemorySnapshot? monitorSnapshot;

  @override
  Widget build(BuildContext context) {
    final PlatformMemorySnapshot? platform = platformSnapshot;
    final MemorySnapshot? monitor = monitorSnapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('测试状态', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '保留内存：${_formatBytes(retainedBytes)} ($chunkCount/$maxChunks)',
            ),
            Text('原生平台：${platform?.platform ?? '-'}'),
            Text(
              'App 内存上限：${_formatNullableBytes(platform?.appMemoryLimitBytes)}',
            ),
            Text(
              'App 剩余可用：${_formatNullableBytes(platform?.appAvailableMemoryBytes)}',
            ),
            Text(
              'Android Java heap 上限：${_formatNullableBytes(platform?.javaHeapMaxBytes)}',
            ),
            Text(
              'Android memoryClass：${_formatNullableBytes(platform?.androidMemoryClassBytes)}',
            ),
            Text(
              'Android largeMemoryClass：${_formatNullableBytes(platform?.androidLargeMemoryClassBytes)}',
            ),
            Text(
              'iOS 进程可用内存：${_formatNullableBytes(platform?.iosAvailableMemoryForProcessBytes)}',
            ),
            Text('系统低内存：${platform?.systemLowMemory ?? '-'}'),
            Text(
              '系统可用内存：${_formatNullableBytes(platform?.systemAvailableMemoryBytes)}',
            ),
            Text(
              '设备总内存：${_formatNullableBytes(platform?.deviceTotalMemoryBytes)}',
            ),
            Text('插件主内存：${_formatNullableBytes(monitor?.primaryMemoryBytes)}'),
            Text('RSS：${_formatNullableBytes(monitor?.rssBytes)}'),
          ],
        ),
      ),
    );
  }
}

String _formatNullableBytes(int? bytes) {
  if (bytes == null) {
    return '-';
  }
  return _formatBytes(bytes);
}

String _formatBytes(int bytes) {
  final double mib = bytes / 1024 / 1024;
  return '${mib.toStringAsFixed(1)} MB';
}
