import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterMemoryMonitor _monitor = FlutterMemoryMonitor();
  final List<String> _logs = <String>[];
  MemorySnapshot? _lastSnapshot;
  bool _roomActive = false;

  @override
  void initState() {
    super.initState();
    _startMonitor();
  }

  @override
  void dispose() {
    _monitor.stop();
    unawaited(_monitor.markRouteExit('ExampleHome'));
    super.dispose();
  }

  void _startMonitor() {
    _monitor.start(
      config: const MemoryMonitorConfig(
        foregroundInterval: Duration(seconds: 30),
        routeExitDelay: Duration(seconds: 2),
        sceneEndDelay: Duration(seconds: 2),
        maxLocalSnapshots: 20,
      ),
      reporter: _ExampleMemoryReporter(
        onSnapshot: _handleSnapshot,
        onIssue: _handleIssue,
      ),
      contextProvider:
          () => <String, Object?>{
            'app_version': 'example',
            'user_bucket': 'demo',
          },
    );
    unawaited(_monitor.markRouteEnter('ExampleHome'));
  }

  Future<void> _sampleNow() async {
    await _monitor.getSnapshot(
      reason: MemorySampleReason.manual,
      context: const <String, Object?>{'button': 'sample_now'},
    );
  }

  Future<void> _toggleRoomScene() async {
    if (_roomActive) {
      await _monitor.markSceneEnd(
        'voice_room',
        context: const <String, Object?>{'room_id': 'demo_room'},
      );
    } else {
      await _monitor.markSceneStart(
        'voice_room',
        context: const <String, Object?>{'room_id': 'demo_room'},
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _roomActive = !_roomActive;
    });
  }

  void _handleSnapshot(MemorySnapshot snapshot) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastSnapshot = snapshot;
      _logs.insert(
        0,
        'snapshot ${snapshot.reason}: ${_formatBytes(snapshot.primaryMemoryBytes)}',
      );
      _trimLogs();
    });
  }

  void _handleIssue(MemoryIssue issue) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(
        0,
        'issue ${issue.type}: delta=${_formatBytes(issue.deltaBytes)}',
      );
      _trimLogs();
    });
  }

  void _trimLogs() {
    if (_logs.length > 30) {
      _logs.removeRange(30, _logs.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Memory monitor example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SnapshotCard(snapshot: _lastSnapshot),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _sampleNow,
                child: const Text('采集一次内存快照'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _toggleRoomScene,
                child: Text(_roomActive ? '结束语聊房场景' : '开始语聊房场景'),
              ),
              const SizedBox(height: 16),
              const Text('采样日志'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (BuildContext context, int index) {
                    return Text(_logs[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot});

  final MemorySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final MemorySnapshot? data = snapshot;
    if (data == null) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('暂无内存快照')),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('原因：${data.reason}'),
            Text('主内存：${_formatBytes(data.primaryMemoryBytes)}'),
            Text('RSS：${_formatBytes(data.rssBytes)}'),
            Text('图片缓存：${_formatBytes(data.imageCache.currentSizeBytes)}'),
            Text('图片数量：${data.imageCache.currentSize}'),
            Text('RAM 档位：${data.ramBucket}'),
          ],
        ),
      ),
    );
  }
}

class _ExampleMemoryReporter implements MemoryReporter {
  const _ExampleMemoryReporter({
    required this.onSnapshot,
    required this.onIssue,
  });

  final ValueChanged<MemorySnapshot> onSnapshot;
  final ValueChanged<MemoryIssue> onIssue;

  @override
  Future<void> reportSnapshot(MemorySnapshot snapshot) async {
    onSnapshot(snapshot);
  }

  @override
  Future<void> reportIssue(MemoryIssue issue) async {
    onIssue(issue);
  }
}

String _formatBytes(int? bytes) {
  if (bytes == null) {
    return '-';
  }
  final double mib = bytes / 1024 / 1024;
  return '${mib.toStringAsFixed(1)} MB';
}
