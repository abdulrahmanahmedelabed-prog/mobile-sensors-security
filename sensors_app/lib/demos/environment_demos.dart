import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/sensor_math.dart';
import '../platform/device.dart';
import '../widgets/common.dart';

/// Light sensor: lux meter with a reading-comfort hint.
class LightDemo extends StatelessWidget {
  const LightDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: 'مقياس الإضاءة', children: [
      const Text('حساس الضوء (أعلى الشاشة غالبًا) يقيس شدة الإضاءة باللوكس. غطّه بإصبعك أو وجّهه للمصباح.'),
      const SizedBox(height: 16),
      LiveValue<List<double>>(
        stream: Device.instance.sensor(SensorType.light),
        builder: (context, v) => Column(children: [
          Reading(label: 'شدة الإضاءة', value: v[0].toStringAsFixed(0), unit: 'lux'),
          const SizedBox(height: 8),
          Meter(value: v[0], min: 0, max: 1000),
          const SizedBox(height: 8),
          Text(lightLabel(v[0]), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(v[0] < 50 ? 'الإضاءة ضعيفة للقراءة: أشعل ضوءًا لراحة عينيك.' : 'الإضاءة مناسبة للقراءة.'),
        ]),
      ),
    ]);
  }
}

/// Proximity: near/far, used here as a touch-free counter (wave your hand).
class ProximityDemo extends StatefulWidget {
  const ProximityDemo({super.key});
  @override
  State<ProximityDemo> createState() => _ProximityDemoState();
}

class _ProximityDemoState extends State<ProximityDemo> with Listens {
  double _maxRange = 5;
  bool? _near;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    Device.instance.describe(SensorType.proximity).then((d) {
      if (d != null && d.maxRange > 0 && mounted) setState(() => _maxRange = d.maxRange);
    }, onError: (_) {});
    listen('p', Device.instance.sensor(SensorType.proximity), (v) {
      final near = v[0] < _maxRange;
      if (near && _near == false) {
        _count++;
        HapticFeedback.selectionClick();
      }
      _near = near;
    });
  }

  @override
  Widget build(BuildContext context) {
    final near = _near;
    return DemoScaffold(title: 'عدّاد بالتلويح', children: [
      const Text('حساس القرب يكتشف الأجسام القريبة من أعلى الشاشة (مثل أذنك أثناء المكالمة فتنطفئ الشاشة). '
          'لوّح بيدك فوقه ليزيد العدّاد دون لمس الشاشة.'),
      const SizedBox(height: 24),
      errorFor('p') ??
          (near == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Icon(near ? Icons.back_hand : Icons.crop_free, size: 100, color: near ? Colors.orange : null),
                  Text(near ? 'قريب' : 'بعيد', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  Reading(label: 'العدد', value: '$_count'),
                  TextButton(onPressed: () => setState(() => _count = 0), child: const Text('تصفير')),
                ])),
    ]);
  }
}

/// Barometer: pressure, altitude and change since the page opened.
class PressureDemo extends StatefulWidget {
  const PressureDemo({super.key});
  @override
  State<PressureDemo> createState() => _PressureDemoState();
}

class _PressureDemoState extends State<PressureDemo> with Listens {
  double? _p;
  double? _startAlt;

  @override
  void initState() {
    super.initState();
    listen('b', Device.instance.sensor(SensorType.pressure), (v) {
      _p = v[0];
      _startAlt ??= altitudeFromPressure(v[0]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return DemoScaffold(title: 'مقياس الارتفاع', children: [
      const Text('البارومتر يقيس ضغط الهواء، والضغط يقل كلما ارتفعت. اصعد درجًا وراقب تغيّر الارتفاع.'),
      const SizedBox(height: 16),
      errorFor('b') ??
          (p == null
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (context) {
                  final alt = altitudeFromPressure(p);
                  final delta = alt - (_startAlt ?? alt);
                  return Column(children: [
                    Reading(label: 'ضغط الهواء', value: p.toStringAsFixed(1), unit: 'hPa'),
                    const SizedBox(height: 12),
                    Reading(label: 'الارتفاع التقريبي عن سطح البحر', value: alt.toStringAsFixed(0), unit: 'm'),
                    const SizedBox(height: 12),
                    Reading(label: 'التغيّر منذ فتح الصفحة', value: delta.toStringAsFixed(1), unit: 'm'),
                    Text('≈ ${(delta / 3).toStringAsFixed(1)} طابق'),
                    TextButton(onPressed: () => setState(() => _startAlt = alt), child: const Text('تصفير')),
                  ]);
                })),
    ]);
  }
}

/// Ambient temperature or humidity (present on few phones).
class SimpleValueDemo extends StatelessWidget {
  const SimpleValueDemo({super.key, required this.title, required this.type, required this.label, required this.unit, required this.note});
  final String title;
  final int type;
  final String label;
  final String unit;
  final String note;

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: title, children: [
      Text(note),
      const SizedBox(height: 16),
      LiveValue<List<double>>(
        stream: Device.instance.sensor(type, rate: SensorRate.normal),
        builder: (context, v) => Reading(label: label, value: v[0].toStringAsFixed(1), unit: unit),
      ),
    ]);
  }
}
