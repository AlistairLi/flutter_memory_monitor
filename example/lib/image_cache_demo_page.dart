import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_memory_monitor/flutter_memory_monitor.dart';

class ImageCacheDemoPage extends StatefulWidget {
  const ImageCacheDemoPage({required this.monitor, super.key});

  final FlutterMemoryMonitor monitor;

  @override
  State<ImageCacheDemoPage> createState() => _ImageCacheDemoPageState();
}

class _ImageCacheDemoPageState extends State<ImageCacheDemoPage> {
  final List<Uint8List> _images = <Uint8List>[];
  MemorySnapshot? _snapshot;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.monitor.markRouteEnter(
        'ImageCacheDemoPage',
        context: const <String, Object?>{'demo': 'image_cache'},
      ),
    );
  }

  @override
  void dispose() {
    unawaited(
      widget.monitor.markRouteExit(
        'ImageCacheDemoPage',
        context: const <String, Object?>{'demo': 'image_cache'},
      ),
    );
    super.dispose();
  }

  Future<void> _loadImages() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
    });

    final List<Uint8List> images = <Uint8List>[];
    for (int i = 0; i < 12; i += 1) {
      images.add(await _createDemoImage(i));
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _images
        ..clear()
        ..addAll(images);
    });

    for (final Uint8List bytes in images) {
      if (!mounted) {
        return;
      }
      await precacheImage(MemoryImage(bytes), context);
    }
    await _sampleImageCache(reason: 'load_images');

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _clearImageCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    setState(() {
      _images.clear();
    });
    await _sampleImageCache(reason: 'clear_image_cache');
  }

  Future<void> _sampleImageCache({String reason = 'sample_image_cache'}) async {
    final MemorySnapshot snapshot = await widget.monitor.getSnapshot(
      reason: MemorySampleReason.manual,
      context: <String, Object?>{
        'button': reason,
        'demo': 'image_cache',
        'image_count': _images.length,
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ImageCacheMetrics? metrics = _snapshot?.imageCache;
    return Scaffold(
      appBar: AppBar(title: const Text('ImageCacheMetrics demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _ImageCacheMetricsCard(metrics: metrics),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _loadImages,
            child: Text(_loading ? '正在加载图片...' : '加载 12 张演示图片'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _sampleImageCache(),
            child: const Text('采集 ImageCacheMetrics'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _clearImageCache,
            child: const Text('清空图片缓存并采样'),
          ),
          const SizedBox(height: 16),
          _ImageGrid(images: _images),
        ],
      ),
    );
  }
}

class _ImageCacheMetricsCard extends StatelessWidget {
  const _ImageCacheMetricsCard({required this.metrics});

  final ImageCacheMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final ImageCacheMetrics? data = metrics;
    if (data == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('先加载图片或手动采样，查看 ImageCacheMetrics 数据。'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'ImageCacheMetrics',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _MetricRow(
              label: 'currentSizeBytes',
              value: _formatBytes(data.currentSizeBytes),
            ),
            _MetricRow(label: 'currentSize', value: '${data.currentSize}'),
            _MetricRow(
              label: 'liveImageCount',
              value: '${data.liveImageCount}',
            ),
            _MetricRow(
              label: 'pendingImageCount',
              value: '${data.pendingImageCount}',
            ),
            _MetricRow(
              label: 'maximumSizeBytes',
              value: _formatBytes(data.maximumSizeBytes),
            ),
            _MetricRow(label: 'maximumSize', value: '${data.maximumSize}'),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox(height: 160, child: Center(child: Text('暂无图片')));
    }
    return GridView.builder(
      itemCount: images.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (BuildContext context, int index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            images[index],
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

Future<Uint8List> _createDemoImage(int index) async {
  const int width = 720;
  const int height = 480;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Paint paint = Paint();
  final List<Color> colors = <Color>[
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.cyan,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
    Colors.blueGrey,
  ];

  paint.color = colors[index % colors.length];
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );

  for (int i = 0; i < 8; i += 1) {
    paint.color = colors[(index + i + 3) % colors.length].withValues(
      alpha: 0.55,
    );
    canvas.drawCircle(
      Offset(80.0 + i * 92.0, 80.0 + ((index + i) % 4) * 96.0),
      64.0 + (index % 3) * 18.0,
      paint,
    );
  }

  final TextPainter textPainter = TextPainter(
    text: TextSpan(
      text: 'Image ${index + 1}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 64,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(canvas, const Offset(32, 32));

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

String _formatBytes(int bytes) {
  final double mib = bytes / 1024 / 1024;
  return '${mib.toStringAsFixed(1)} MB';
}
