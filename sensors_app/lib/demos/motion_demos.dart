import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/sensor_math.dart';
import '../platform/device.dart';
import '../widgets/common.dart';
import '../widgets/live_chart.dart';

/// Accelerometer: live x/y/z and a shake counter.
class AccelerometerDemo extends StatefulWidget {
  const AccelerometerDemo({super.key});
  @override
  State<AccelerometerDemo> createState() => _AccelerometerDemoState();
}

class _AccelerometerDemoState extends State<AccelerometerDemo> with Listens {
  final _shake = ShakeDetector();
  List<double>? _v;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    listen('a', Device.instance.sensor(SensorType.accelerometer, rate: SensorRate.game), (v) {
      _v = v;
      if (_shake.add(v)) {
        _shakes++;
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return DemoScaffold(title: 'عدّاد الهزّات', children: [
      const Text('هزّ الجوال بقوة ليزيد العدّاد. ضعه على طاولة ستجد Z ≈ 9.8 (الجاذبية).'),
      const SizedBox(height: 16),
      errorFor('a') ??
          (v == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  AxesRow(values: v, unit: 'm/s²'),
                  const SizedBox(height: 16),
                  Reading(label: 'الشدة الكلية', value: magnitude(v).toStringAsFixed(2), unit: 'm/s²'),
                  const SizedBox(height: 24),
                  Reading(label: 'عدد الهزّات', value: '$_shakes'),
                  TextButton(onPressed: () => setState(() => _shakes = 0), child: const Text('تصفير')),
                ])),
      LiveChart(stream: Device.instance.sensor(SensorType.accelerometer, rate: SensorRate.game), labels: const ['X', 'Y', 'Z'], unit: 'm/s²'),
    ]);
  }
}

/// Gyroscope: rotation speed, and a dial that turns as the phone turns.
class GyroscopeDemo extends StatefulWidget {
  const GyroscopeDemo({super.key});
  @override
  State<GyroscopeDemo> createState() => _GyroscopeDemoState();
}

class _GyroscopeDemoState extends State<GyroscopeDemo> with Listens {
  List<double>? _v;
  double _angle = 0;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    listen('g', Device.instance.sensor(SensorType.gyroscope, rate: SensorRate.game), (v) {
      final now = DateTime.now();
      if (_last != null) _angle += v[2] * now.difference(_last!).inMicroseconds / 1e6;
      _last = now;
      _v = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return DemoScaffold(title: 'مؤشر الدوران', children: [
      const Text('أدِر الجوال وهو مسطّح على الطاولة: يقيس الجيروسكوب سرعة الدوران، ونجمعها لنعرف زاوية الدوران.'),
      const SizedBox(height: 16),
      errorFor('g') ??
          (v == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  AxesRow(values: v, unit: 'rad/s'),
                  const SizedBox(height: 24),
                  Transform.rotate(angle: -_angle, child: const Icon(Icons.navigation, size: 120)),
                  Reading(label: 'زاوية الدوران حول Z', value: normalizeDegrees(_angle * 180 / math.pi).toStringAsFixed(0), unit: '°'),
                  TextButton(onPressed: () => setState(() => _angle = 0), child: const Text('تصفير')),
                ])),
      LiveChart(stream: Device.instance.sensor(SensorType.gyroscope, rate: SensorRate.game), labels: const ['X', 'Y', 'Z'], unit: 'rad/s'),
    ]);
  }
}

/// Magnetometer: field strength as a simple metal detector.
class MagnetometerDemo extends StatelessWidget {
  const MagnetometerDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: 'كاشف المعادن', children: [
      const Text('المجال المغناطيسي للأرض بين 25 و 65 ميكروتسلا. قرّب الجوال من جسم حديدي أو مغناطيس وراقب الارتفاع.'),
      const SizedBox(height: 16),
      LiveValue<List<double>>(
        stream: Device.instance.sensor(SensorType.magneticField),
        builder: (context, v) {
          final m = magnitude(v);
          final metal = m > 80;
          return Column(children: [
            AxesRow(values: v, unit: 'µT', digits: 1),
            const SizedBox(height: 16),
            Reading(label: 'شدة المجال', value: m.toStringAsFixed(1), unit: 'µT'),
            const SizedBox(height: 8),
            Meter(value: m, min: 0, max: 300, color: metal ? Colors.red : null),
            const SizedBox(height: 8),
            Text(metal ? 'يوجد معدن أو مغناطيس قريب!' : 'لا يوجد معدن قريب',
                style: TextStyle(fontSize: 18, color: metal ? Colors.red : null)),
          ]);
        },
      ),
      LiveChart(stream: Device.instance.sensor(SensorType.magneticField), labels: const ['X', 'Y', 'Z'], unit: 'µT', digits: 1),
    ]);
  }
}

/// Rotation vector (fused accelerometer + magnetometer + gyroscope): compass.
class CompassDemo extends StatefulWidget {
  const CompassDemo({super.key});
  @override
  State<CompassDemo> createState() => _CompassDemoState();
}

class _CompassDemoState extends State<CompassDemo> with Listens {
  final _smooth = AngleSmoother();
  double? _heading;
  int _accuracy = 3;

  @override
  void initState() {
    super.initState();
    listen('r', Device.instance.sensor(SensorType.rotationVector, rate: SensorRate.game), (v) {
      _heading = _smooth.add(azimuthFromRotationVector(v));
      _accuracy = v.last.round();
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _heading;
    return DemoScaffold(title: 'البوصلة', children: [
      const Text('حساس «متجه الدوران» يدمج التسارع والمغناطيس والجيروسكوب ليعطي اتجاه الجوال بدقة. '
          'إذا كانت القراءة غير دقيقة فحرّك الجوال على شكل رقم 8 لمعايرته.'),
      const SizedBox(height: 24),
      errorFor('r') ??
          (h == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  CompassDial(heading: h),
                  const SizedBox(height: 12),
                  Reading(label: 'الاتجاه (من الشمال المغناطيسي)', value: h.toStringAsFixed(0), unit: '°'),
                  const SizedBox(height: 8),
                  CalibrationHint(accuracy: _accuracy),
                ])),
    ]);
  }
}

class CompassDial extends StatelessWidget {
  const CompassDial({super.key, required this.heading, this.target});
  final double heading;
  /// Optional bearing to point at (e.g. the Qibla), degrees from the same north.
  final double? target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(alignment: Alignment.center, children: [
        Transform.rotate(
          angle: -heading * math.pi / 180,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outline, width: 3)),
            ),
            for (final (label, deg) in [('ش', 0.0), ('شر', 90.0), ('ج', 180.0), ('غ', 270.0)])
              Transform.rotate(
                angle: deg * math.pi / 180,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(label,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: deg == 0 ? Colors.red : null)),
                  ),
                ),
              ),
            if (target != null)
              Transform.rotate(
                angle: target! * math.pi / 180,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 36),
                    child: Icon(Icons.mosque, size: 36, color: scheme.primary),
                  ),
                ),
              ),
          ]),
        ),
        Icon(Icons.arrow_upward, size: 64, color: scheme.primary),
      ]),
    );
  }
}

/// Gravity: a bubble level.
class LevelDemo extends StatelessWidget {
  const LevelDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: 'ميزان الماء', children: [
      const Text('حساس الجاذبية يعرف أين «الأسفل». ضع الجوال على سطح لتعرف هل هو مستوٍ.'),
      const SizedBox(height: 24),
      LiveValue<List<double>>(
        stream: Device.instance.sensor(SensorType.gravity, rate: SensorRate.game),
        builder: (context, g) => BubbleLevel(gravity: g),
      ),
      LiveChart(stream: Device.instance.sensor(SensorType.gravity, rate: SensorRate.game), labels: const ['X', 'Y', 'Z'], unit: 'm/s²'),
    ]);
  }
}

class BubbleLevel extends StatelessWidget {
  const BubbleLevel({super.key, required this.gravity});
  final List<double> gravity;

  @override
  Widget build(BuildContext context) {
    final (pitch, roll) = tiltDegrees(gravity);
    final flat = pitch.abs() < 1.5 && roll.abs() < 1.5;
    // Bubble floats opposite to gravity's sideways pull.
    final dx = (-gravity[0] / standardGravity).clamp(-1.0, 1.0);
    final dy = (gravity[1] / standardGravity).clamp(-1.0, 1.0);
    return Column(children: [
      Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: flat ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.15),
            border: Border.all(width: 2),
          ),
          child: Stack(children: [
            const Center(child: Icon(Icons.add, size: 40)),
            Align(
              alignment: Alignment(dx, dy),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: flat ? Colors.green : Colors.orange),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text(flat ? 'مستوٍ تمامًا ✔' : 'مائل', style: const TextStyle(fontSize: 20)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Reading(label: 'الميل للأمام', value: pitch.toStringAsFixed(1), unit: '°'),
        Reading(label: 'الميل للجانب', value: roll.toStringAsFixed(1), unit: '°'),
      ]),
    ]);
  }
}

/// Linear acceleration (motion without gravity): activity meter.
class LinearAccelerationDemo extends StatefulWidget {
  const LinearAccelerationDemo({super.key});
  @override
  State<LinearAccelerationDemo> createState() => _LinearAccelerationDemoState();
}

class _LinearAccelerationDemoState extends State<LinearAccelerationDemo> with Listens {
  double _avg = 0;
  List<double>? _v;

  @override
  void initState() {
    super.initState();
    listen('l', Device.instance.sensor(SensorType.linearAcceleration, rate: SensorRate.game), (v) {
      _v = v;
      _avg = _avg * 0.95 + magnitude(v) * 0.05;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return DemoScaffold(title: 'مقياس النشاط', children: [
      const Text('التسارع الخطي = التسارع بعد طرح الجاذبية، أي حركتك أنت فقط. امشِ أو اجرِ والجوال معك.'),
      const SizedBox(height: 16),
      errorFor('l') ??
          (v == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  AxesRow(values: v, unit: 'm/s²'),
                  const SizedBox(height: 16),
                  Meter(value: _avg, min: 0, max: 8),
                  const SizedBox(height: 8),
                  Text(activityLabel(activityFrom(_avg)), style: Theme.of(context).textTheme.headlineSmall),
                ])),
      LiveChart(stream: Device.instance.sensor(SensorType.linearAcceleration, rate: SensorRate.game), labels: const ['X', 'Y', 'Z'], unit: 'm/s²'),
    ]);
  }
}
