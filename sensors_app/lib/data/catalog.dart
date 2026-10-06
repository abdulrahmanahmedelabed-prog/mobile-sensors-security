import 'package:flutter/material.dart';

import '../demos/environment_demos.dart';
import '../demos/motion_demos.dart';
import '../demos/other_demos.dart';
import '../platform/device.dart';

enum SensorGroup { motion, position, environment, media, security }

String groupName(SensorGroup g) => switch (g) {
      SensorGroup.motion => 'حساسات الحركة',
      SensorGroup.position => 'حساسات الموقع والاتجاه',
      SensorGroup.environment => 'حساسات البيئة',
      SensorGroup.media => 'الصوت والصورة',
      SensorGroup.security => 'الأمان',
    };

/// Companion feature names, shared with the comprehensive app and its sensor map.
abstract final class Feature {
  static const qibla = 'اتجاه القبلة';
  static const tasbeeh = 'المسبحة الذكية';
  static const activity = 'نشاطي اليومي';
  static const environment = 'بيئة القراءة';
  static const level = 'الميزان';
  static const magnifier = 'العدسة المكبّرة';
  static const lock = 'قفل البصمة';
}

class SensorInfo {
  const SensorInfo({
    required this.id,
    required this.name,
    required this.english,
    required this.icon,
    required this.group,
    required this.measures,
    required this.how,
    required this.benefits,
    required this.examples,
    required this.demoTitle,
    required this.demo,
    required this.usedIn,
    this.androidType,
    this.permission,
    this.virtual = false,
  });

  final String id;
  final String name;
  final String english;
  final IconData icon;
  final SensorGroup group;
  final String measures;
  final String how;
  final List<String> benefits;
  final List<String> examples;
  final String demoTitle;
  final WidgetBuilder demo;
  /// Comprehensive-app features (Feature.*) that use this sensor, with what for.
  final Map<String, String> usedIn;
  /// android.hardware.Sensor.TYPE_* when it is a SensorManager sensor.
  final int? androidType;
  /// Runtime permission needed, in plain Arabic, or null.
  final String? permission;
  /// Software ("virtual") sensor computed from other hardware sensors.
  final bool virtual;
}

final List<SensorInfo> catalog = [
  SensorInfo(
    id: 'accelerometer',
    name: 'مقياس التسارع',
    english: 'Accelerometer',
    icon: Icons.vibration,
    group: SensorGroup.motion,
    androidType: SensorType.accelerometer,
    measures: 'التسارع على المحاور الثلاثة X و Y و Z بوحدة م/ث² (ومنه الجاذبية والاهتزاز).',
    how: 'كتلة دقيقة جدًا معلّقة بنوابض داخل شريحة MEMS؛ عند الحركة تنزاح فتتغير السعة الكهربائية بينها وبين ألواح ثابتة.',
    benefits: [
      'تدوير الشاشة تلقائيًا بين الطول والعرض',
      'اكتشاف الهزّ والسقوط (مثلًا: تنبيه طوارئ عند سقوط كبار السن)',
      'عدّ الخطوات وقياس النشاط البدني',
      'التحكم في الألعاب بإمالة الجوال',
    ],
    examples: ['تدوير الشاشة', 'هزّ للتراجع عن الكتابة', 'ألعاب السباق'],
    demoTitle: 'عدّاد الهزّات',
    demo: (_) => const AccelerometerDemo(),
    usedIn: {
      Feature.tasbeeh: 'هزّة قوية تصفّر العدّاد',
      Feature.qibla: 'جزء من «متجه الدوران» لمعرفة اتجاه الجوال',
    },
  ),
  SensorInfo(
    id: 'gyroscope',
    name: 'الجيروسكوب',
    english: 'Gyroscope',
    icon: Icons.threesixty,
    group: SensorGroup.motion,
    androidType: SensorType.gyroscope,
    measures: 'سرعة الدوران حول كل محور بوحدة راديان/ثانية.',
    how: 'كتلة تهتز داخل شريحة MEMS؛ عند الدوران تنحرف بفعل «قوة كوريوليس» فيُقاس الانحراف.',
    benefits: [
      'تثبيت الصورة والفيديو من اهتزاز اليد',
      'الواقع الافتراضي والمعزّز وصور 360°',
      'تحسين دقة البوصلة والاتجاه مع المغناطيس والتسارع',
      'ألعاب التوجيه بحركة الجوال',
    ],
    examples: ['الصور البانورامية', 'خرائط Google (اتجاه السهم)', 'ألعاب VR'],
    demoTitle: 'مؤشر الدوران',
    demo: (_) => const GyroscopeDemo(),
    usedIn: {
      Feature.qibla: 'يثبّت سهم القبلة ويمنع ارتجافه (داخل متجه الدوران)',
      Feature.level: 'مؤشر «ثبات اليد» عند القياس',
    },
  ),
  SensorInfo(
    id: 'magnetometer',
    name: 'مقياس المجال المغناطيسي',
    english: 'Magnetometer',
    icon: Icons.explore,
    group: SensorGroup.position,
    androidType: SensorType.magneticField,
    measures: 'شدة المجال المغناطيسي واتجاهه بالميكروتسلا (µT).',
    how: 'شريحة تعتمد «تأثير هول»: يتغير الجهد الكهربائي عبر موصل يمر فيه تيار بحسب المجال المغناطيسي.',
    benefits: [
      'البوصلة ومعرفة الشمال',
      'تحديد اتجاه القبلة',
      'كشف المعادن والأسلاك داخل الجدران (تقريبيًا)',
      'اكتشاف إغلاق الغطاء المغناطيسي للجوال',
    ],
    examples: ['تطبيقات البوصلة والقبلة', 'الخرائط'],
    demoTitle: 'كاشف المعادن',
    demo: (_) => const MagnetometerDemo(),
    usedIn: {Feature.qibla: 'يعرف أين الشمال المغناطيسي'},
  ),
  SensorInfo(
    id: 'rotation',
    name: 'متجه الدوران (البوصلة الذكية)',
    english: 'Rotation vector',
    icon: Icons.screen_rotation_alt,
    group: SensorGroup.position,
    androidType: SensorType.rotationVector,
    virtual: true,
    measures: 'اتجاه الجوال الكامل في الفراغ (أي جهة يشير إليها وكم هو مائل).',
    how: 'حساس برمجي: يدمج التسارع + المغناطيس + الجيروسكوب بخوارزمية (Sensor Fusion) لنتيجة أدق وأثبت من كل واحد منفردًا.',
    benefits: ['بوصلة ثابتة ودقيقة', 'الواقع المعزّز', 'معرفة اتجاه الكاميرا', 'تطبيقات الفلك ومواقع النجوم'],
    examples: ['خرائط Google', 'Sky Map', 'تطبيقات القبلة'],
    demoTitle: 'البوصلة',
    demo: (_) => const CompassDemo(),
    usedIn: {Feature.qibla: 'اتجاه الجوال الآن، لمقارنته باتجاه مكة'},
  ),
  SensorInfo(
    id: 'gravity',
    name: 'حساس الجاذبية',
    english: 'Gravity',
    icon: Icons.south,
    group: SensorGroup.motion,
    androidType: SensorType.gravity,
    virtual: true,
    measures: 'اتجاه الجاذبية وشدتها على المحاور الثلاثة (م/ث²).',
    how: 'حساس برمجي: يستخرج مركّبة الجاذبية من مقياس التسارع بعد إزالة الحركة السريعة (بمساعدة الجيروسكوب).',
    benefits: ['ميزان الماء (هل السطح مستوٍ؟)', 'معرفة ميل الجوال بدقة', 'اكتشاف وضع الجوال على وجهه'],
    examples: ['تطبيقات الميزان', 'الكاميرا (خط الأفق)'],
    demoTitle: 'ميزان الماء',
    demo: (_) => const LevelDemo(),
    usedIn: {Feature.level: 'فقاعة الميزان وزوايا الميل'},
  ),
  SensorInfo(
    id: 'linear',
    name: 'التسارع الخطي',
    english: 'Linear acceleration',
    icon: Icons.directions_run,
    group: SensorGroup.motion,
    androidType: SensorType.linearAcceleration,
    virtual: true,
    measures: 'تسارع حركتك أنت فقط بعد طرح الجاذبية (م/ث²).',
    how: 'حساس برمجي = مقياس التسارع − الجاذبية.',
    benefits: ['معرفة هل المستخدم ثابت أم يمشي أم يجري', 'قياس شدة التمرين', 'اكتشاف الحوادث والسقوط'],
    examples: ['تطبيقات اللياقة', 'اكتشاف حوادث السيارات'],
    demoTitle: 'مقياس النشاط',
    demo: (_) => const LinearAccelerationDemo(),
    usedIn: {Feature.activity: 'حالتك الآن: ثابت / تمشي / تجري'},
  ),
  SensorInfo(
    id: 'steps',
    name: 'عدّاد الخطوات',
    english: 'Step counter',
    icon: Icons.directions_walk,
    group: SensorGroup.motion,
    androidType: SensorType.stepCounter,
    permission: 'النشاط البدني',
    measures: 'عدد الخطوات منذ آخر تشغيل للجوال.',
    how: 'شريحة منخفضة الاستهلاك جدًا تحلل نمط التسارع وتعدّ الخطوات حتى والشاشة مغلقة.',
    benefits: ['متابعة المشي اليومي', 'حساب المسافة والسعرات تقريبيًا', 'استهلاك بطارية أقل بكثير من حساب الخطوات برمجيًا'],
    examples: ['Google Fit', 'Samsung Health'],
    demoTitle: 'عدّاد الخطوات',
    demo: (_) => const StepsDemo(),
    usedIn: {Feature.activity: 'خطواتك والمسافة منذ فتح الصفحة'},
  ),
  SensorInfo(
    id: 'gps',
    name: 'نظام تحديد المواقع GPS',
    english: 'GPS / GNSS',
    icon: Icons.satellite_alt,
    group: SensorGroup.position,
    permission: 'الموقع',
    measures: 'خط العرض وخط الطول والارتفاع والسرعة.',
    how: 'يستقبل إشارات زمنية من 4 أقمار صناعية أو أكثر (GPS، غلوناس، غاليليو، بيدو) ويحسب موقعه من فروق زمن الوصول.',
    benefits: ['الخرائط والملاحة', 'حساب اتجاه القبلة ومواقيت الصلاة', 'تتبع الجري وركوب الدراجة', 'العثور على الجوال المفقود'],
    examples: ['خرائط Google', 'أوبر وكريم', 'تطبيقات الصلاة'],
    demoTitle: 'موقعي',
    demo: (_) => const GpsDemo(),
    usedIn: {Feature.qibla: 'موقعك التقريبي لحساب اتجاه مكة والمسافة إليها'},
  ),
  SensorInfo(
    id: 'light',
    name: 'حساس الضوء',
    english: 'Ambient light',
    icon: Icons.light_mode,
    group: SensorGroup.environment,
    androidType: SensorType.light,
    measures: 'شدة الإضاءة حولك باللوكس (lux).',
    how: 'ثنائي ضوئي (Photodiode) قرب السماعة العلوية يولّد تيارًا يتناسب مع كمية الضوء.',
    benefits: ['السطوع التلقائي للشاشة (يوفر البطارية ويريح العين)', 'الوضع الليلي التلقائي', 'قياس إضاءة غرفة القراءة أو التصوير'],
    examples: ['السطوع التلقائي', 'الكاميرا'],
    demoTitle: 'مقياس الإضاءة',
    demo: (_) => const LightDemo(),
    usedIn: {
      Feature.environment: 'هل الإضاءة مناسبة للقراءة؟ ويقترح الوضع الليلي',
      Feature.magnifier: 'يشغّل كشاف الكاميرا تلقائيًا في الظلام',
    },
  ),
  SensorInfo(
    id: 'proximity',
    name: 'حساس القرب',
    english: 'Proximity',
    icon: Icons.sensor_occupied,
    group: SensorGroup.environment,
    androidType: SensorType.proximity,
    measures: 'هل يوجد جسم قريب من أعلى الشاشة (قريب/بعيد أو مسافة بالسنتيمتر).',
    how: 'يرسل ضوءًا تحت أحمر غير مرئي ويقيس كمية الضوء المنعكس.',
    benefits: ['إطفاء الشاشة عند وضع الجوال على الأذن أثناء المكالمة', 'منع اللمس العرضي في الجيب', 'تحكم بالتلويح دون لمس'],
    examples: ['المكالمات', 'وضع الجيب'],
    demoTitle: 'عدّاد بالتلويح',
    demo: (_) => const ProximityDemo(),
    usedIn: {Feature.tasbeeh: 'كل تلويحة فوق الجوال = تسبيحة، دون لمس الشاشة'},
  ),
  SensorInfo(
    id: 'pressure',
    name: 'البارومتر (ضغط الهواء)',
    english: 'Barometer',
    icon: Icons.speed,
    group: SensorGroup.environment,
    androidType: SensorType.pressure,
    measures: 'ضغط الهواء بالهيكتوباسكال (hPa).',
    how: 'غشاء دقيق يتقوّس مع تغير ضغط الهواء فتتغير مقاومته الكهربائية.',
    benefits: ['حساب الارتفاع وعدد الطوابق التي صعدتها', 'تسريع تحديد الموقع GPS بمعرفة الارتفاع', 'توقع تغير الطقس'],
    examples: ['Google Fit (الطوابق)', 'تطبيقات تسلق الجبال'],
    demoTitle: 'مقياس الارتفاع',
    demo: (_) => const PressureDemo(),
    usedIn: {Feature.activity: 'الطوابق التي صعدتها'},
  ),
  SensorInfo(
    id: 'temperature',
    name: 'حساس حرارة الجو',
    english: 'Ambient temperature',
    icon: Icons.thermostat,
    group: SensorGroup.environment,
    androidType: SensorType.ambientTemperature,
    measures: 'درجة حرارة الهواء المحيط (°م). موجود في قلة من الجوالات.',
    how: 'مقاومة حرارية (Thermistor) تتغير مقاومتها مع الحرارة.',
    benefits: ['معرفة حرارة الغرفة', 'تطبيقات الطقس المحلية'],
    examples: ['Samsung Galaxy S4 (من أوائل الجوالات التي ضمّته)'],
    demoTitle: 'ميزان الحرارة',
    demo: (_) => const SimpleValueDemo(
        title: 'ميزان الحرارة', type: SensorType.ambientTemperature, label: 'حرارة الجو', unit: '°C',
        note: 'هذا الحساس نادر في الجوالات الحديثة.'),
    usedIn: {Feature.environment: 'حرارة الغرفة إن وُجد الحساس'},
  ),
  SensorInfo(
    id: 'humidity',
    name: 'حساس الرطوبة',
    english: 'Relative humidity',
    icon: Icons.water_drop,
    group: SensorGroup.environment,
    androidType: SensorType.humidity,
    measures: 'الرطوبة النسبية للهواء (%). موجود في قلة من الجوالات.',
    how: 'مادة تمتص بخار الماء فتتغير سعتها الكهربائية.',
    benefits: ['معرفة راحة الجو', 'تنبيه الرطوبة العالية'],
    examples: ['بعض جوالات سامسونج القديمة'],
    demoTitle: 'مقياس الرطوبة',
    demo: (_) => const SimpleValueDemo(
        title: 'مقياس الرطوبة', type: SensorType.humidity, label: 'الرطوبة', unit: '%',
        note: 'هذا الحساس نادر في الجوالات الحديثة.'),
    usedIn: {Feature.environment: 'رطوبة الغرفة إن وُجد الحساس'},
  ),
  SensorInfo(
    id: 'microphone',
    name: 'الميكروفون',
    english: 'Microphone',
    icon: Icons.mic,
    group: SensorGroup.media,
    permission: 'الميكروفون',
    measures: 'موجات الصوت (ومنها شدة الصوت بالديسيبل).',
    how: 'غشاء MEMS يهتز مع الصوت فتتغير السعة الكهربائية، ثم تُحوَّل إلى أرقام.',
    benefits: ['المكالمات والتسجيل', 'الأوامر الصوتية والمساعد الصوتي', 'قياس الضوضاء', 'التعرف على التلاوة والأغاني'],
    examples: ['المساعد الصوتي', 'Shazam', 'تطبيقات تسميع القرآن'],
    demoTitle: 'مقياس الضوضاء',
    demo: (_) => const MicrophoneDemo(),
    usedIn: {Feature.environment: 'هل المكان هادئ للقراءة والحفظ؟ (الشدة فقط، بلا تسجيل)'},
  ),
  SensorInfo(
    id: 'camera',
    name: 'الكاميرا',
    english: 'Camera',
    icon: Icons.photo_camera,
    group: SensorGroup.media,
    permission: 'الكاميرا',
    measures: 'الضوء الساقط على ملايين النقاط (بكسل) لتكوين صورة.',
    how: 'شريحة CMOS: كل بكسل ثنائي ضوئي صغير خلفه مرشّح لون (أحمر/أخضر/أزرق).',
    benefits: ['التصوير والفيديو', 'قراءة رموز QR', 'التعرف على النصوص (OCR)', 'قياس النبض بوضع الإصبع على الكاميرا', 'عدسة مكبّرة لضعاف البصر'],
    examples: ['الكاميرا', 'Google Lens', 'الدفع بـ QR'],
    demoTitle: 'الكاميرا',
    demo: (_) => const CameraDemo(),
    usedIn: {Feature.magnifier: 'عدسة مكبّرة لقراءة الخط الصغير'},
  ),
  SensorInfo(
    id: 'biometric',
    name: 'حساس البصمة / الوجه',
    english: 'Biometrics',
    icon: Icons.fingerprint,
    group: SensorGroup.security,
    measures: 'نقوش بصمة الإصبع (أو ملامح الوجه) للتحقق من هوية صاحب الجوال.',
    how: 'حساس سعوي أو ضوئي أو فوق صوتي يصوّر نقوش الإصبع، وتُقارن داخل «منطقة آمنة» معزولة في المعالج؛ لا تصل البصمة لأي تطبيق.',
    benefits: ['فتح الجوال بسرعة وأمان', 'حماية التطبيقات الحساسة (البنوك)', 'تأكيد الدفع'],
    examples: ['تطبيقات البنوك', 'Google Pay / Apple Pay', 'قفل التطبيقات'],
    demoTitle: 'قفل البصمة',
    demo: (_) => const BiometricDemo(),
    usedIn: {Feature.lock: 'يقفل التطبيق الشامل ويعيد قفله عند الخروج منه'},
  ),
];

SensorInfo sensorById(String id) => catalog.firstWhere((s) => s.id == id);
