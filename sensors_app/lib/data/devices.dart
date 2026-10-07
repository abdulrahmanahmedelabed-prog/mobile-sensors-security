/// Sensor specs of popular phones, for "which phones have this sensor?" and
/// the best-phones ranking.
///
/// Checked in October 2026 against GSMArena, the makers' spec pages
/// (apple.com, vivo.com, oppo.com, mi.com) and Samsung's own announcements.
/// `null` means the sources disagree or say nothing: the app shows it as
/// "غير مؤكد" rather than guessing. Accelerometer, light sensor, GPS,
/// microphone and camera are in every phone listed, so they are not stored.
library;

enum Fingerprint { ultrasonic, optical, side, none }

enum Proximity { real, virtual, none }

class PhoneSpec {
  const PhoneSpec({
    required this.name,
    required this.brand,
    required this.year,
    required this.fingerprint,
    required this.gyro,
    required this.compass,
    required this.proximity,
    required this.barometer,
    this.face3d = false,
    this.uwb = false,
    this.thermometer = false,
    this.ambientTemperature = false,
    this.humidity = false,
    this.heartRate = false,
    this.spo2 = false,
    this.depth = false,
    this.colorSpectrum = false,
    this.ios = false,
    this.note,
  });

  final String name;
  final String brand;
  final int year;
  final Fingerprint? fingerprint;
  final bool? gyro;
  final bool? compass;
  final Proximity? proximity;
  final bool? barometer;
  /// 3D face unlock (Face ID or structured light), not 2D camera face unlock.
  final bool? face3d;
  /// Ultra-wideband: finds tags and other phones to within centimetres.
  final bool? uwb;
  /// Infrared thermometer for objects/skin (not air temperature).
  final bool? thermometer;
  final bool? ambientTemperature;
  final bool? humidity;
  final bool? heartRate;
  final bool? spo2;
  /// LiDAR or time-of-flight depth sensor.
  final bool? depth;
  /// Colour spectrum / multispectral sensor for true-to-life photo colours.
  final bool? colorSpectrum;
  /// iPhones are listed for comparison; this app itself runs on Android.
  final bool ios;
  final String? note;

  /// "Samsung Galaxy S25", but "Xiaomi 15 Ultra" (not "Xiaomi Xiaomi 15 Ultra").
  String get fullName => brand.isEmpty || name.startsWith(brand) ? name : '$brand $name';
}

const phones = <PhoneSpec>[
  PhoneSpec(name: 'Galaxy S26 Ultra', brand: 'Samsung', year: 2026, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, uwb: true),
  PhoneSpec(name: 'Galaxy S25 Ultra', brand: 'Samsung', year: 2025, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, uwb: true),
  PhoneSpec(name: 'Galaxy S25', brand: 'Samsung', year: 2025, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, uwb: null),
  PhoneSpec(name: 'Galaxy A56', brand: 'Samsung', year: 2025, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.virtual, barometer: false),
  PhoneSpec(name: 'Galaxy A36', brand: 'Samsung', year: 2025, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.virtual, barometer: false),
  PhoneSpec(name: 'Galaxy A16', brand: 'Samsung', year: 2024, fingerprint: Fingerprint.side, gyro: null, compass: true, proximity: Proximity.virtual, barometer: false, note: 'المصادر تختلف في وجود الجيروسكوب'),
  PhoneSpec(name: 'Pixel 10 Pro', brand: 'Google', year: 2025, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, uwb: true, thermometer: true),
  PhoneSpec(name: 'Pixel 10', brand: 'Google', year: 2025, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, uwb: false),
  PhoneSpec(name: 'Pixel 9a', brand: 'Google', year: 2025, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.real, barometer: true),
  PhoneSpec(name: 'iPhone 17 Pro Max', brand: 'Apple', year: 2025, fingerprint: Fingerprint.none, gyro: true, compass: true, proximity: Proximity.real, barometer: true, face3d: true, uwb: true, depth: true, ios: true),
  PhoneSpec(name: 'iPhone 17', brand: 'Apple', year: 2025, fingerprint: Fingerprint.none, gyro: true, compass: true, proximity: Proximity.real, barometer: true, face3d: true, uwb: true, ios: true),
  PhoneSpec(name: 'iPhone 16e', brand: 'Apple', year: 2025, fingerprint: Fingerprint.none, gyro: true, compass: true, proximity: Proximity.real, barometer: true, face3d: true, uwb: false, ios: true),
  PhoneSpec(name: 'Xiaomi 15 Ultra', brand: 'Xiaomi', year: 2025, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true),
  PhoneSpec(name: 'Redmi Note 14 Pro 5G', brand: 'Xiaomi', year: 2024, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.virtual, barometer: false, note: 'حساس قرب بالموجات فوق الصوتية بدل الضوئي'),
  PhoneSpec(name: 'Pura 80 Ultra', brand: 'Huawei', year: 2025, fingerprint: Fingerprint.side, gyro: true, compass: true, proximity: Proximity.real, barometer: true, colorSpectrum: true),
  PhoneSpec(name: 'Magic7 Pro', brand: 'Honor', year: 2024, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: false, face3d: true, depth: true, colorSpectrum: true),
  PhoneSpec(name: 'OnePlus 13', brand: 'OnePlus', year: 2024, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: null, colorSpectrum: true, note: 'المصادر تختلف في وجود البارومتر'),
  PhoneSpec(name: 'X200 Pro', brand: 'vivo', year: 2024, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: null, colorSpectrum: true),
  PhoneSpec(name: 'Find X8 Pro', brand: 'OPPO', year: 2024, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.real, barometer: false, colorSpectrum: true),
  PhoneSpec(name: 'Note 50 Pro', brand: 'Infinix', year: 2025, fingerprint: Fingerprint.optical, gyro: true, compass: true, proximity: Proximity.virtual, barometer: false, heartRate: true, spo2: true),
  PhoneSpec(name: 'Galaxy S10', brand: 'Samsung', year: 2019, fingerprint: Fingerprint.ultrasonic, gyro: true, compass: true, proximity: Proximity.real, barometer: true, heartRate: true, spo2: true, note: 'جهاز قديم: آخر هاتف رائد من سامسونج بحساس نبض'),
  PhoneSpec(name: 'Galaxy S4', brand: 'Samsung', year: 2013, fingerprint: Fingerprint.none, gyro: true, compass: true, proximity: Proximity.real, barometer: true, ambientTemperature: true, humidity: true, note: 'جهاز قديم: من القلائل التي ضمّت حساسي حرارة الجو والرطوبة'),
];

/// Points for the ranking: rarer and more useful sensors weigh more.
/// Unknown (null) earns nothing.
class Weights {
  static const gyro = 3, compass = 3, barometer = 3, face3d = 3, uwb = 2, depth = 2;
  static const proximityReal = 2, proximityVirtual = 1;
  static const fingerprintUltrasonic = 3, fingerprintOther = 2;
  static const thermometer = 1, ambientTemperature = 1, humidity = 1, heartRate = 1, spo2 = 1, colorSpectrum = 1;
  static const max = gyro + compass + barometer + face3d + uwb + depth + proximityReal + fingerprintUltrasonic +
      thermometer + ambientTemperature + humidity + heartRate + spo2 + colorSpectrum;
}

int _w(bool? has, int points) => has == true ? points : 0;

int rawScore(PhoneSpec p) =>
    _w(p.gyro, Weights.gyro) +
    _w(p.compass, Weights.compass) +
    _w(p.barometer, Weights.barometer) +
    _w(p.face3d, Weights.face3d) +
    _w(p.uwb, Weights.uwb) +
    _w(p.depth, Weights.depth) +
    switch (p.proximity) {
      Proximity.real => Weights.proximityReal,
      Proximity.virtual => Weights.proximityVirtual,
      _ => 0,
    } +
    switch (p.fingerprint) {
      Fingerprint.ultrasonic => Weights.fingerprintUltrasonic,
      Fingerprint.optical || Fingerprint.side => Weights.fingerprintOther,
      _ => 0,
    } +
    _w(p.thermometer, Weights.thermometer) +
    _w(p.ambientTemperature, Weights.ambientTemperature) +
    _w(p.humidity, Weights.humidity) +
    _w(p.heartRate, Weights.heartRate) +
    _w(p.spo2, Weights.spo2) +
    _w(p.colorSpectrum, Weights.colorSpectrum);

/// 0..100.
int sensorScore(PhoneSpec p) => (rawScore(p) * 100 / Weights.max).round();

List<PhoneSpec> rankedPhones({String? brand, bool androidOnly = false}) {
  final list = [
    for (final p in phones)
      if ((brand == null || p.brand == brand) && (!androidOnly || !p.ios)) p,
  ];
  list.sort((a, b) {
    final s = sensorScore(b).compareTo(sensorScore(a));
    return s != 0 ? s : b.year.compareTo(a.year);
  });
  return list;
}

/// Whether [p] has the catalog sensor [sensorId]: true, false, or null when
/// unknown. Sensors every phone has return true.
bool? phoneHas(PhoneSpec p, String sensorId) => switch (sensorId) {
      'gyroscope' => p.gyro,
      'magnetometer' => p.compass,
      // Fused from accelerometer + compass, steadier with a gyroscope.
      'rotation' => p.compass == false ? false : (p.compass == true && p.gyro == true ? true : null),
      'proximity' => p.proximity == null ? null : p.proximity != Proximity.none,
      'pressure' => p.barometer,
      'temperature' => p.ambientTemperature,
      'humidity' => p.humidity,
      'biometric' => p.fingerprint == null && p.face3d == null
          ? null
          : (p.fingerprint != null && p.fingerprint != Fingerprint.none) || p.face3d == true,
      _ => true, // accelerometer, gravity, linear acceleration, steps, GPS, light, microphone, camera
    };

/// Sensors every listed phone has, so a per-phone list would add nothing.
const universalSensors = {'accelerometer', 'gravity', 'linear', 'steps', 'gps', 'light', 'microphone', 'camera'};

String fingerprintLabel(Fingerprint? f) => switch (f) {
      Fingerprint.ultrasonic => 'تحت الشاشة بالموجات فوق الصوتية (الأدق، ويعمل مع الأصابع المبللة)',
      Fingerprint.optical => 'تحت الشاشة ضوئي',
      Fingerprint.side => 'على الجانب',
      Fingerprint.none => 'لا يوجد',
      null => 'غير مؤكد',
    };

String proximityLabel(Proximity? p) => switch (p) {
      Proximity.real => 'حساس حقيقي',
      Proximity.virtual => 'افتراضي (برمجي عبر شاشة اللمس، أقل دقة)',
      Proximity.none => 'لا يوجد',
      null => 'غير مؤكد',
    };
