import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../logic/sensor_math.dart';
import '../platform/device.dart';
import '../widgets/common.dart';

/// Step counter: steps since the page opened.
class StepsDemo extends StatelessWidget {
  const StepsDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return const DemoScaffold(title: 'عدّاد الخطوات', children: [
      Text('عدّاد الخطوات شريحة منخفضة الاستهلاك تعدّ خطواتك حتى والشاشة مغلقة. '
          'يعدّ منذ آخر تشغيل للجوال، فنحسب الفرق منذ فتح الصفحة. امشِ بضع خطوات.'),
      SizedBox(height: 16),
      PermissionGate(
        permission: AppPermission.activity,
        reason: 'أندرويد يعدّ عدّاد الخطوات بيانات «نشاط بدني»، فيلزم إذن «النشاط البدني» لقراءته.',
        child: _StepsBody(),
      ),
    ]);
  }
}

class _StepsBody extends StatefulWidget {
  const _StepsBody();
  @override
  State<_StepsBody> createState() => _StepsBodyState();
}

class _StepsBodyState extends State<_StepsBody> with Listens {
  double? _start;
  double? _now;

  @override
  void initState() {
    super.initState();
    listen('s', Device.instance.sensor(SensorType.stepCounter, rate: SensorRate.normal), (v) {
      _start ??= v[0];
      _now = v[0];
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = errorFor('s');
    if (e != null) return e;
    if (_now == null) return const Text('ابدأ المشي… (قد تتأخر أول قراءة بضع ثوانٍ)');
    final steps = (_now! - _start!).round();
    return Column(children: [
      const Icon(Icons.directions_walk, size: 80),
      Reading(label: 'خطوات منذ فتح الصفحة', value: '$steps'),
      Text('≈ ${(steps * 0.75).toStringAsFixed(0)} متر'),
      const SizedBox(height: 8),
      Text('العدّاد الكلي منذ تشغيل الجوال: ${_now!.toStringAsFixed(0)}'),
    ]);
  }
}

/// GPS: coordinates, accuracy, speed, altitude.
class GpsDemo extends StatelessWidget {
  const GpsDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: 'موقعي', children: [
      const Text('يستقبل الجوال إشارات الأقمار الصناعية (GPS) ليحسب موقعك. يعمل أفضل في مكان مكشوف.'),
      const SizedBox(height: 16),
      PermissionGate(
        permission: AppPermission.locationFine,
        reason: 'لعرض إحداثياتك وسرعتك. الموقع يُعرض فقط ولا يُحفظ أو يُرسل.',
        child: LiveValue<LocationFix>(
          stream: Device.instance.location(),
          waiting: const Padding(padding: EdgeInsets.all(16), child: Text('جارٍ تحديد الموقع…')),
          builder: (context, f) => Column(children: [
            Reading(label: 'خط العرض', value: f.lat.toStringAsFixed(5), unit: '°'),
            Reading(label: 'خط الطول', value: f.lon.toStringAsFixed(5), unit: '°'),
            Reading(label: 'الدقة', value: '± ${f.accuracy.toStringAsFixed(0)}', unit: 'm'),
            if (f.speed != null) Reading(label: 'السرعة', value: (f.speed! * 3.6).toStringAsFixed(1), unit: 'km/h'),
            if (f.altitude != null) Reading(label: 'الارتفاع', value: f.altitude!.toStringAsFixed(0), unit: 'm'),
            Text('المصدر: ${f.provider == 'gps' ? 'الأقمار الصناعية' : 'الشبكة'}'),
            Text('المسافة إلى مكة: ${distanceKm(f.lat, f.lon, kaabaLat, kaabaLon).toStringAsFixed(0)} كم'),
          ]),
        ),
      ),
    ]);
  }
}

/// Microphone: sound level meter (loudness only, no recording).
class MicrophoneDemo extends StatelessWidget {
  const MicrophoneDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: 'مقياس الضوضاء', children: [
      const Text('نقيس شدة الصوت فقط كل عُشر ثانية؛ الصوت نفسه لا يُسجَّل ولا يُحفظ.'),
      const SizedBox(height: 16),
      PermissionGate(
        permission: AppPermission.microphone,
        reason: 'لقياس مستوى الضوضاء حولك.',
        child: LiveValue<double>(
          stream: Device.instance.soundLevel(),
          builder: (context, dbfs) {
            final db = approxDb(dbfs);
            return Column(children: [
              Reading(label: 'مستوى الصوت (تقريبي)', value: db.toStringAsFixed(0), unit: 'dB'),
              const SizedBox(height: 8),
              Meter(value: db, min: 20, max: 100, color: db > 80 ? Colors.red : null),
              const SizedBox(height: 8),
              Text(noiseLabel(db), style: Theme.of(context).textTheme.titleLarge),
            ]);
          },
        ),
      ),
    ]);
  }
}

/// Camera: preview and a photo kept in memory only.
class CameraDemo extends StatelessWidget {
  const CameraDemo({super.key});
  @override
  Widget build(BuildContext context) {
    return const DemoScaffold(title: 'الكاميرا', children: [
      Text('الكاميرا حساس ضوئي من ملايين النقاط. الصورة تبقى في الذاكرة وتُحذف عند إغلاق الصفحة.'),
      SizedBox(height: 16),
      PermissionGate(
        permission: AppPermission.camera,
        reason: 'لعرض ما تراه الكاميرا والتقاط صورة.',
        child: CameraView(allowCapture: true),
      ),
    ]);
  }
}

/// Back-camera preview, released whenever the app leaves the screen.
class CameraView extends StatefulWidget {
  const CameraView({super.key, this.allowCapture = false, this.zoom = 1, this.torch = false});
  final bool allowCapture;
  final double zoom;
  final bool torch;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  Uint8List? _photo;
  double _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'no camera');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _maxZoom = await c.getMaxZoomLevel();
      setState(() => _controller = c);
      await _apply();
    } on CameraException {
      if (mounted) setState(() => _error = 'تعذّر فتح الكاميرا.');
    }
  }

  Future<void> _apply() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setZoomLevel(widget.zoom.clamp(1, _maxZoom).toDouble());
      await c.setFlashMode(widget.torch ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      // Zoom or torch unsupported on this camera: keep the plain preview.
    }
  }

  @override
  void didUpdateWidget(CameraView old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom || old.torch != widget.torch) _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null && _error == null) {
      _open();
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || c.value.isTakingPicture) return;
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      // The plugin writes to the cache folder; remove it so nothing stays on disk.
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // Already gone.
      }
      if (mounted) setState(() => _photo = bytes);
    } on CameraException {
      if (mounted) setState(() => _error = 'تعذّر التقاط الصورة.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Unavailable(message: _error!);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 1 / c.value.aspectRatio, child: CameraPreview(c)),
      ),
      if (widget.allowCapture) ...[
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _capture, icon: const Icon(Icons.camera), label: const Text('التقاط')),
        if (_photo != null) ...[
          const SizedBox(height: 12),
          Image.memory(_photo!, height: 200),
          TextButton(onPressed: () => setState(() => _photo = null), child: const Text('حذف الصورة')),
        ],
      ],
    ]);
  }
}

/// Fingerprint / face: authenticate with the phone's biometrics.
class BiometricDemo extends StatefulWidget {
  const BiometricDemo({super.key});
  @override
  State<BiometricDemo> createState() => _BiometricDemoState();
}

class _BiometricDemoState extends State<BiometricDemo> {
  final _auth = LocalAuthentication();
  List<BiometricType> _types = const [];
  String _status = '';
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _auth.getAvailableBiometrics().then((t) {
      if (mounted) setState(() => _types = t);
    }, onError: (_) {});
  }

  Future<void> _check() async {
    final r = await authenticate(_auth, 'تحقق من بصمتك للتجربة');
    if (!mounted) return;
    setState(() {
      _ok = r.ok;
      _status = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      BiometricType.fingerprint: 'بصمة الإصبع',
      BiometricType.face: 'بصمة الوجه',
      BiometricType.iris: 'قزحية العين',
      BiometricType.strong: 'بصمة قوية',
      BiometricType.weak: 'بصمة ضعيفة',
    };
    return DemoScaffold(title: 'قفل البصمة', children: [
      const Text('حساس البصمة يقارن بصمتك بنسخة مشفّرة داخل شريحة آمنة في الجوال. '
          'التطبيق لا يرى البصمة أبدًا؛ يتلقى فقط «نجح» أو «فشل».'),
      const SizedBox(height: 12),
      Text('المتاح في جوالك: ${_types.isEmpty ? 'غير معروف / لا يوجد' : _types.map((t) => names[t] ?? t.name).join('، ')}'),
      const SizedBox(height: 24),
      Icon(
        _ok == null ? Icons.fingerprint : (_ok! ? Icons.lock_open : Icons.lock),
        size: 120,
        color: _ok == null ? null : (_ok! ? Colors.green : Colors.red),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _check, child: const Text('تحقق')),
      const SizedBox(height: 8),
      Text(_status, textAlign: TextAlign.center),
    ]);
  }
}

class AuthResult {
  const AuthResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Biometric (or screen-lock) authentication with Arabic error messages.
Future<AuthResult> authenticate(LocalAuthentication auth, String reason) async {
  try {
    final ok = await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    return AuthResult(ok, ok ? 'تم التحقق ✔' : 'لم يتم التحقق');
  } on LocalAuthException catch (e) {
    final msg = switch (e.code) {
      LocalAuthExceptionCode.noBiometricHardware => 'لا يوجد حساس بصمة في هذا الجوال.',
      LocalAuthExceptionCode.noBiometricsEnrolled => 'لم تُسجَّل بصمة في الجوال. أضفها من الإعدادات.',
      LocalAuthExceptionCode.noCredentialsSet => 'لا يوجد قفل شاشة. فعّل قفل الشاشة أولًا.',
      LocalAuthExceptionCode.temporaryLockout => 'محاولات كثيرة. انتظر قليلًا.',
      LocalAuthExceptionCode.biometricLockout => 'البصمة مقفلة. افتح الجوال بالرمز أولًا.',
      LocalAuthExceptionCode.userCanceled || LocalAuthExceptionCode.systemCanceled => 'أُلغي التحقق.',
      _ => 'تعذّر التحقق.',
    };
    return AuthResult(false, msg);
  } catch (_) {
    return const AuthResult(false, 'البصمة غير متاحة على هذا الجهاز.');
  }
}
