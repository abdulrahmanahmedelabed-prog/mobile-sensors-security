import 'dart:math' as math;

const standardGravity = 9.80665;
const kaabaLat = 21.422487;
const kaabaLon = 39.826206;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
double normalizeDegrees(double d) => (d % 360 + 360) % 360;

/// Phone heading in degrees from magnetic north (0..360), from a rotation
/// vector [x, y, z, (w)] — the same maths as Android's
/// SensorManager.getRotationMatrixFromVector + getOrientation.
double azimuthFromRotationVector(List<double> v) {
  final q1 = v[0], q2 = v[1], q3 = v[2];
  final q0 = v.length > 3 && v[3] != 0 ? v[3] : math.sqrt(math.max(0, 1 - q1 * q1 - q2 * q2 - q3 * q3));
  final r1 = 2 * q1 * q2 - 2 * q3 * q0;
  final r4 = 1 - 2 * q1 * q1 - 2 * q3 * q3;
  return normalizeDegrees(_deg(math.atan2(r1, r4)));
}

/// Initial great-circle bearing from a point to the Kaaba, degrees from true north.
double qiblaBearing(double lat, double lon) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat), dl = _rad(kaabaLon - lon);
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return normalizeDegrees(_deg(math.atan2(y, x)));
}

/// Great-circle distance in kilometres (haversine).
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final dp = _rad(lat2 - lat1), dl = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dp / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 6371.0088 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Altitude in metres from air pressure (international barometric formula).
double altitudeFromPressure(double hPa, {double seaLevel = 1013.25}) =>
    44330 * (1 - math.pow(hPa / seaLevel, 1 / 5.255).toDouble());

double magnitude(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

/// Tilt from a gravity/accelerometer vector: (pitch, roll) in degrees.
(double, double) tiltDegrees(List<double> g) {
  final pitch = _deg(math.atan2(-g[1], math.sqrt(g[0] * g[0] + g[2] * g[2])));
  final roll = _deg(math.atan2(g[0], g[2]));
  return (pitch, roll);
}

enum Activity { still, walking, running }

/// Rough activity from the average linear-acceleration magnitude (m/s²).
Activity activityFrom(double avgLinearAccel) {
  if (avgLinearAccel < 0.6) return Activity.still;
  if (avgLinearAccel < 4.0) return Activity.walking;
  return Activity.running;
}

String activityLabel(Activity a) => switch (a) {
      Activity.still => 'ثابت',
      Activity.walking => 'يمشي',
      Activity.running => 'يجري / حركة قوية',
    };

String lightLabel(double lux) {
  if (lux < 10) return 'ظلام';
  if (lux < 50) return 'إضاءة خافتة';
  if (lux < 500) return 'إضاءة غرفة';
  if (lux < 2000) return 'إضاءة مكتب قوية';
  if (lux < 20000) return 'نهار (ظل)';
  return 'شمس مباشرة';
}

String noiseLabel(double approxDb) {
  if (approxDb < 35) return 'هادئ جدًا';
  if (approxDb < 50) return 'هادئ';
  if (approxDb < 65) return 'حديث عادي';
  if (approxDb < 80) return 'صاخب';
  return 'صاخب جدًا — احمِ سمعك';
}

/// The microphone is not calibrated: dBFS + 90 is a rough, relative dB value.
double approxDb(double dbfs) => (dbfs + 90).clamp(0, 120).toDouble();

/// Detects shakes: a spike above [threshold] m/s², at most one per [gap].
class ShakeDetector {
  ShakeDetector({this.threshold = 2.2 * standardGravity, this.gap = const Duration(milliseconds: 600)});
  final double threshold;
  final Duration gap;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  bool add(List<double> accel, [DateTime? now]) {
    now ??= DateTime.now();
    if (magnitude(accel) < threshold || now.difference(_last) < gap) return false;
    _last = now;
    return true;
  }
}

/// Smooths angles (degrees) without jumping at the 0/360 boundary.
class AngleSmoother {
  AngleSmoother([this.alpha = 0.15]);
  final double alpha;
  double? _value;

  double add(double deg) {
    final v = _value;
    if (v == null) return _value = deg;
    final diff = ((deg - v + 540) % 360) - 180;
    return _value = normalizeDegrees(v + alpha * diff);
  }
}
