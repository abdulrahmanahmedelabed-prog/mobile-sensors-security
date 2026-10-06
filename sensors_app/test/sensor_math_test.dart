import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_lab/logic/sensor_math.dart';

void main() {
  test('qibla bearing from known cities', () {
    // Published Qibla directions (degrees from true north).
    expect(qiblaBearing(24.7136, 46.6753), closeTo(244.0, 1.5)); // Riyadh
    expect(qiblaBearing(30.0444, 31.2357), closeTo(136.0, 1.5)); // Cairo
    expect(qiblaBearing(51.5074, -0.1278), closeTo(119.0, 1.5)); // London
    expect(qiblaBearing(-6.2088, 106.8456), closeTo(295.0, 1.5)); // Jakarta
  });

  test('distance to Mecca', () {
    expect(distanceKm(24.7136, 46.6753, kaabaLat, kaabaLon), closeTo(790, 15));
    expect(distanceKm(kaabaLat, kaabaLon, kaabaLat, kaabaLon), closeTo(0, 1e-9));
  });

  test('azimuth from rotation vector', () {
    // Rotation of θ about Z: q = (0, 0, sin(θ/2), cos(θ/2)); heading is 360-θ.
    for (final deg in [0.0, 30.0, 90.0, 180.0, 270.0]) {
      final h = deg * math.pi / 360;
      final az = azimuthFromRotationVector([0, 0, math.sin(h), math.cos(h)]);
      expect((az - normalizeDegrees(-deg)).abs() % 360, closeTo(0, 1e-6));
    }
    // Without w the scalar part is reconstructed.
    expect(azimuthFromRotationVector([0, 0, 0]), closeTo(0, 1e-9));
  });

  test('altitude from pressure', () {
    expect(altitudeFromPressure(1013.25), closeTo(0, 1e-6));
    expect(altitudeFromPressure(899.0), closeTo(1000, 15));
  });

  test('tilt is zero when flat', () {
    final (pitch, roll) = tiltDegrees([0, 0, standardGravity]);
    expect(pitch, closeTo(0, 1e-9));
    expect(roll, closeTo(0, 1e-9));
  });

  test('shake detector debounces', () {
    final d = ShakeDetector();
    final t0 = DateTime(2026);
    expect(d.add([0, 0, 9.8], t0), isFalse);
    expect(d.add([30, 0, 9.8], t0), isTrue);
    expect(d.add([30, 0, 9.8], t0.add(const Duration(milliseconds: 100))), isFalse);
    expect(d.add([30, 0, 9.8], t0.add(const Duration(seconds: 1))), isTrue);
  });

  test('angle smoother wraps through north', () {
    final s = AngleSmoother(0.5);
    s.add(350);
    final v = s.add(10);
    expect(v, closeTo(0, 1e-9));
  });

  test('labels', () {
    expect(activityFrom(0.1), Activity.still);
    expect(activityFrom(2), Activity.walking);
    expect(activityFrom(6), Activity.running);
    expect(lightLabel(5), 'ظلام');
    expect(approxDb(-90), 0);
    expect(approxDb(10), 100);
  });
}
