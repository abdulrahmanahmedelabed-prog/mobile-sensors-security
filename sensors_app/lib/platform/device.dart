import 'package:flutter/services.dart';

/// Android sensor type numbers (android.hardware.Sensor.TYPE_*).
abstract final class SensorType {
  static const accelerometer = 1;
  static const magneticField = 2;
  static const gyroscope = 4;
  static const light = 5;
  static const pressure = 6;
  static const proximity = 8;
  static const gravity = 9;
  static const linearAcceleration = 10;
  static const rotationVector = 11;
  static const humidity = 12;
  static const ambientTemperature = 13;
  static const gameRotationVector = 15;
  static const stepDetector = 18;
  static const stepCounter = 19;
}

/// Sampling rates accepted by the native side (SensorManager.SENSOR_DELAY_*).
enum SensorRate {
  game(1),
  ui(2),
  normal(3);

  const SensorRate(this.code);
  final int code;
}

/// Runtime permissions the app may ask for (an allow-list mirrored in Kotlin).
enum AppPermission { locationCoarse, locationFine, microphone, camera, activity }

extension on AppPermission {
  String get wire => switch (this) {
        AppPermission.locationCoarse => 'location_coarse',
        AppPermission.locationFine => 'location_fine',
        AppPermission.microphone => 'microphone',
        AppPermission.camera => 'camera',
        AppPermission.activity => 'activity',
      };
}

class SensorDescription {
  SensorDescription.fromMap(Map<Object?, Object?> m)
      : type = m['type'] as int,
        name = m['name'] as String? ?? '',
        vendor = m['vendor'] as String? ?? '',
        maxRange = (m['maxRange'] as num?)?.toDouble() ?? 0,
        resolution = (m['resolution'] as num?)?.toDouble() ?? 0,
        power = (m['power'] as num?)?.toDouble() ?? 0,
        minDelayUs = m['minDelayUs'] as int? ?? 0,
        isDefault = m['isDefault'] as bool? ?? false,
        isWakeUp = m['isWakeUp'] as bool? ?? false;

  final int type;
  final String name;
  final String vendor;
  final double maxRange;
  final double resolution;
  final double power;
  final int minDelayUs;
  final bool isDefault;
  final bool isWakeUp;
}

class LocationFix {
  LocationFix.fromMap(Map<Object?, Object?> m)
      : lat = (m['lat'] as num).toDouble(),
        lon = (m['lon'] as num).toDouble(),
        accuracy = (m['accuracy'] as num?)?.toDouble() ?? 0,
        altitude = (m['altitude'] as num?)?.toDouble(),
        speed = (m['speed'] as num?)?.toDouble(),
        bearing = (m['bearing'] as num?)?.toDouble(),
        provider = m['provider'] as String? ?? '';

  final double lat;
  final double lon;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? bearing;
  final String provider;
}

/// Readings and permissions from the phone. Streams are shared, so several
/// widgets can watch one sensor while the native side registers it once.
///
/// They are kept as the broadcast streams EventChannel returns (only mapped):
/// those start the native sensor when the first listener arrives and stop it
/// when the last one leaves, any number of times. (asBroadcastStream would
/// not: once its last listener left, a page opened again got no readings.)
class Device {
  Device._();
  static final instance = Device._();

  static const _method = MethodChannel('sensors_lab/device');
  final _sensorStreams = <String, Stream<List<double>>>{};
  Stream<LocationFix>? _location;
  Stream<double>? _sound;
  List<SensorDescription>? _sensors;

  Stream<List<double>> sensor(int type, {SensorRate rate = SensorRate.ui}) {
    // One stream per sensor: the native side has one listener per channel,
    // so the rate of the first request wins while it is being watched.
    return _sensorStreams.putIfAbsent('$type', () {
      return EventChannel('sensors_lab/sensor/$type')
          .receiveBroadcastStream({'rate': rate.code})
          .map((e) => [for (final v in e as List<Object?>) (v as num).toDouble()]);
    });
  }

  Stream<LocationFix> location() => _location ??= const EventChannel('sensors_lab/location')
      .receiveBroadcastStream()
      .map((e) => LocationFix.fromMap(e as Map<Object?, Object?>));

  /// Loudness in dBFS (-90 silence … 0 loudest) every ~100 ms.
  Stream<double> soundLevel() => _sound ??= const EventChannel('sensors_lab/sound')
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  Future<List<SensorDescription>> sensors() async {
    final list = await _method.invokeListMethod<Object?>('sensors') ?? const [];
    return _sensors = [for (final m in list) SensorDescription.fromMap(m as Map<Object?, Object?>)];
  }

  Future<SensorDescription?> describe(int type) async {
    final all = _sensors ?? await sensors();
    for (final s in all) {
      if (s.type == type && s.isDefault) return s;
    }
    return null;
  }

  Future<bool> has(int type) async => await describe(type) != null;

  Future<double> magneticDeclination(double lat, double lon) async =>
      await _method.invokeMethod<double>('declination', {'lat': lat, 'lon': lon}) ?? 0;

  Future<bool> isGranted(AppPermission p) async =>
      await _method.invokeMethod<bool>('permissionStatus', {'name': p.wire}) ?? false;

  Future<bool> request(AppPermission p) async =>
      await _method.invokeMethod<bool>('requestPermission', {'name': p.wire}) ?? false;

  Future<void> openAppSettings() => _method.invokeMethod('openAppSettings');
}
