import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Series colours that stay distinct in light and dark themes (X, Y, Z).
const seriesColors = [Color(0xFFE53935), Color(0xFF43A047), Color(0xFF1E88E5)];

/// A rolling graph of the last [window] of a sensor, with live / min / max
/// per series and a pause button — like the graphs of phyphox or Physics
/// Toolbox. Samples live only in this widget and disappear with it.
class LiveChart extends StatefulWidget {
  const LiveChart({
    super.key,
    required this.stream,
    required this.labels,
    this.unit = '',
    this.window = const Duration(seconds: 10),
    this.digits = 2,
    this.map,
  });

  final Stream<List<double>> stream;
  /// One label per series to draw (e.g. ['X','Y','Z'] or ['lux']).
  final List<String> labels;
  final String unit;
  final Duration window;
  final int digits;
  /// Optional transform from a raw reading to the plotted values.
  final List<double> Function(List<double> raw)? map;

  @override
  State<LiveChart> createState() => _LiveChartState();
}

class _Sample {
  const _Sample(this.t, this.v);
  final int t;
  final List<double> v;
}

class _LiveChartState extends State<LiveChart> {
  final _samples = <_Sample>[];
  final _watch = Stopwatch()..start();
  StreamSubscription<List<double>>? _sub;
  bool _paused = false;
  bool _failed = false;
  late List<double> _min = List.filled(widget.labels.length, double.infinity);
  late List<double> _max = List.filled(widget.labels.length, double.negativeInfinity);

  @override
  void initState() {
    super.initState();
    // A missing sensor is already explained by the page; just hide the graph.
    _sub = widget.stream.listen(_add, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _add(List<double> raw) {
    if (_paused || !mounted) return;
    final mapped = widget.map?.call(raw) ?? raw;
    final v = [for (var i = 0; i < widget.labels.length && i < mapped.length; i++) mapped[i]];
    if (v.length < widget.labels.length) return;
    final now = _watch.elapsedMilliseconds;
    setState(() {
      _samples.add(_Sample(now, v));
      final cutoff = now - widget.window.inMilliseconds;
      while (_samples.isNotEmpty && _samples.first.t < cutoff) {
        _samples.removeAt(0);
      }
      for (var i = 0; i < v.length; i++) {
        _min[i] = math.min(_min[i], v[i]);
        _max[i] = math.max(_max[i], v[i]);
      }
    });
  }

  void _reset() => setState(() {
        _samples.clear();
        _min = List.filled(widget.labels.length, double.infinity);
        _max = List.filled(widget.labels.length, double.negativeInfinity);
      });

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _fmt(double v) => v.isFinite ? v.toStringAsFixed(widget.digits) : '—';

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final last = _samples.isEmpty ? null : _samples.last.v;
    final multi = widget.labels.length > 1;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('الرسم البياني (آخر ${widget.window.inSeconds} ثوانٍ)', style: Theme.of(context).textTheme.titleSmall)),
            IconButton(
              tooltip: _paused ? 'متابعة' : 'إيقاف مؤقت',
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              onPressed: () => setState(() => _paused = !_paused),
            ),
            IconButton(tooltip: 'تصفير', icon: const Icon(Icons.restart_alt), onPressed: _reset),
          ]),
          Semantics(
            label: 'رسم بياني لقراءات الحساس',
            child: SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _ChartPainter(
                  samples: List.of(_samples),
                  window: widget.window.inMilliseconds,
                  now: _samples.isEmpty ? 0 : _samples.last.t,
                  colors: multi ? seriesColors : [scheme.primary],
                  grid: scheme.outlineVariant,
                  text: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                TableRow(children: [
                  const SizedBox(),
                  for (final h in ['الآن', 'أقل', 'أعلى'])
                    Text(h, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
                ]),
                for (final (i, l) in widget.labels.indexed)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(l, style: TextStyle(color: multi ? seriesColors[i % 3] : scheme.primary, fontWeight: FontWeight.bold)),
                    ),
                    Text(last == null ? '—' : _fmt(last[i]), textAlign: TextAlign.center),
                    Text(_fmt(_min[i]), textAlign: TextAlign.center),
                    Text(_fmt(_max[i]), textAlign: TextAlign.center),
                  ]),
              ],
            ),
          ),
          if (widget.unit.isNotEmpty)
            Text('الوحدة: ${widget.unit}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.window,
    required this.now,
    required this.colors,
    required this.grid,
    required this.text,
  });

  final List<_Sample> samples;
  final int window;
  final int now;
  final List<Color> colors;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (samples.length < 2) return;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final s in samples) {
      for (final v in s.v) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (hi - lo < 1e-6) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    double x(int t) => size.width * (1 - (now - t) / window);
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));
    final series = samples.first.v.length;
    for (var k = 0; k < series; k++) {
      final path = Path()..moveTo(x(samples.first.t), y(samples.first.v[k]));
      for (final s in samples.skip(1)) {
        path.lineTo(x(s.t), y(s.v[k]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[k % colors.length]
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    final style = TextStyle(color: text, fontSize: 10);
    for (final (v, dy) in [(hi, 0.0), (lo, size.height - 12)]) {
      final tp = TextPainter(text: TextSpan(text: v.toStringAsFixed(1), style: style), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, dy));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
