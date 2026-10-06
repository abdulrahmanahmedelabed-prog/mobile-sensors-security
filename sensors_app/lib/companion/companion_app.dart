import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app_state.dart';
import '../data/catalog.dart';
import '../demos/motion_demos.dart';
import '../demos/other_demos.dart';
import '../logic/sensor_math.dart';
import '../platform/device.dart';
import '../widgets/common.dart';

/// «رفيق»: one app that uses every sensor. Each feature lists the sensors it
/// uses; the sensor map screen shows the reverse (sensor → where it is used).
class CompanionApp extends StatefulWidget {
  const CompanionApp({super.key, this.requireUnlock = true});
  final bool requireUnlock;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  late bool _locked = widget.requireUnlock;
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Leaving the app locks it again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.requireUnlock && !_busy) {
      setState(() => _locked = true);
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await authenticate(_auth, 'افتح «رفيق» ببصمتك');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _locked = !r.ok;
      _message = r.ok ? '' : r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: const Text('رفيق')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fingerprint, size: 96),
              const SizedBox(height: 12),
              const Text('«رفيق» مقفل ببصمتك (حساس البصمة).', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _unlock, child: const Text('فتح')),
              const SizedBox(height: 8),
              Text(_message, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
    }
    final features = <(String, IconData, String, List<String>, WidgetBuilder)>[
      (Feature.qibla, Icons.mosque, 'سهم يشير إلى مكة من أي مكان', ['gps', 'rotation', 'magnetometer', 'accelerometer', 'gyroscope'], (_) => const QiblaPage()),
      (Feature.tasbeeh, Icons.touch_app, 'سبّح بالتلويح فوق الجوال وصفّر بالهزّ', ['proximity', 'accelerometer'], (_) => const TasbeehPage()),
      (Feature.activity, Icons.directions_walk, 'خطواتك وحالتك والطوابق التي صعدتها', ['steps', 'linear', 'pressure'], (_) => const ActivityPage()),
      (Feature.environment, Icons.menu_book, 'هل المكان مناسب للقراءة؟ ضوء وضوضاء وحرارة', ['light', 'microphone', 'temperature', 'humidity'], (_) => const EnvironmentPage()),
      (Feature.level, Icons.straighten, 'ميزان ماء مع مؤشر ثبات اليد', ['gravity', 'gyroscope'], (_) => const LevelPage()),
      (Feature.magnifier, Icons.zoom_in, 'كبّر الخط الصغير، والكشاف يعمل وحده في الظلام', ['camera', 'light'], (_) => const MagnifierPage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('رفيق — تطبيق شامل'), actions: [
        IconButton(
          tooltip: 'خريطة الحساسات',
          icon: const Icon(Icons.account_tree),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SensorMapPage())),
        ),
        if (widget.requireUnlock)
          IconButton(tooltip: 'قفل', icon: const Icon(Icons.lock), onPressed: () => setState(() => _locked = true)),
      ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text(Feature.lock),
            subtitle: const Text('فتحت التطبيق ببصمتك، ويُقفل تلقائيًا عند الخروج منه.'),
            trailing: const SensorChips(names: ['البصمة']),
          ),
        ),
        for (final (title, icon, desc, sensors, page) in features)
          Card(
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: page)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                    const Icon(Icons.chevron_left),
                  ]),
                  const SizedBox(height: 4),
                  Text(desc),
                  const SizedBox(height: 6),
                  SensorChips(names: [for (final id in sensors) sensorById(id).name]),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SensorMapPage())),
          icon: const Icon(Icons.account_tree),
          label: const Text('أي حساس يُستخدم وأين؟'),
        ),
      ]),
    );
  }
}

/// Sensor → where it is used in «رفيق» (built from the catalog, so it cannot drift).
class SensorMapPage extends StatelessWidget {
  const SensorMapPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة الحساسات في «رفيق»')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final s in catalog)
          Card(
            child: ListTile(
              leading: Icon(s.icon),
              title: Text(s.name),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final MapEntry(key: feature, value: what) in s.usedIn.entries) Text('• $feature: $what'),
              ]),
            ),
          ),
      ]),
    );
  }
}

class QiblaPage extends StatelessWidget {
  const QiblaPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const DemoScaffold(title: Feature.qibla, children: [
      SensorChips(names: ['GPS', 'متجه الدوران', 'المغناطيس', 'التسارع', 'الجيروسكوب']),
      SizedBox(height: 8),
      Text('ضع الجوال مسطّحًا وأدره حتى يشير السهم العلوي إلى رمز المسجد.'),
      PermissionGate(
        permission: AppPermission.locationCoarse,
        reason: 'لحساب اتجاه مكة من مدينتك. يكفي الموقع التقريبي، ولا يُحفظ ولا يُرسل.',
        child: _QiblaBody(),
      ),
    ]);
  }
}

class _QiblaBody extends StatefulWidget {
  const _QiblaBody();
  @override
  State<_QiblaBody> createState() => _QiblaBodyState();
}

class _QiblaBodyState extends State<_QiblaBody> with Listens {
  final _smooth = AngleSmoother();
  LocationFix? _fix;
  double _declination = 0;
  double? _heading;
  int _accuracy = 3;
  bool _wasFacing = false;

  @override
  void initState() {
    super.initState();
    listen('loc', Device.instance.location(), (f) {
      final first = _fix == null;
      _fix = f;
      if (first) {
        Device.instance.magneticDeclination(f.lat, f.lon).then((d) {
          if (mounted) setState(() => _declination = d);
        }, onError: (_) {});
      }
    });
    listen('rot', Device.instance.sensor(SensorType.rotationVector, rate: SensorRate.game), (v) {
      _heading = _smooth.add(azimuthFromRotationVector(v));
      _accuracy = v.last.round();
    });
  }

  @override
  Widget build(BuildContext context) {
    final err = errorFor('loc') ?? errorFor('rot');
    if (err != null) return err;
    final f = _fix, h = _heading;
    if (f == null || h == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('جارٍ تحديد موقعك واتجاه الجوال…'));
    }
    final trueHeading = normalizeDegrees(h + _declination);
    final qibla = qiblaBearing(f.lat, f.lon);
    final offset = ((qibla - trueHeading + 540) % 360) - 180;
    final facing = offset.abs() < 5;
    if (facing && !_wasFacing) HapticFeedback.heavyImpact();
    _wasFacing = facing;
    return Column(children: [
      const SizedBox(height: 12),
      CompassDial(heading: trueHeading, target: qibla),
      const SizedBox(height: 12),
      Text(facing ? 'أنت متجه إلى القبلة ✔' : (offset > 0 ? 'استدر يمينًا ${offset.abs().toStringAsFixed(0)}°' : 'استدر يسارًا ${offset.abs().toStringAsFixed(0)}°'),
          style: TextStyle(fontSize: 22, color: facing ? Colors.green : null, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('اتجاه القبلة من موقعك: ${qibla.toStringAsFixed(1)}° من الشمال الحقيقي'),
      Text('المسافة إلى مكة: ${distanceKm(f.lat, f.lon, kaabaLat, kaabaLon).toStringAsFixed(0)} كم'),
      Text('الانحراف المغناطيسي هنا: ${_declination.toStringAsFixed(1)}°'),
      const SizedBox(height: 8),
      CalibrationHint(accuracy: _accuracy),
    ]);
  }
}

class TasbeehPage extends StatefulWidget {
  const TasbeehPage({super.key});
  @override
  State<TasbeehPage> createState() => _TasbeehPageState();
}

class _TasbeehPageState extends State<TasbeehPage> with Listens {
  final _shake = ShakeDetector();
  double _maxRange = 5;
  bool _near = false;
  int _count = 0;
  int _target = 33;

  @override
  void initState() {
    super.initState();
    Device.instance.describe(SensorType.proximity).then((d) {
      if (d != null && d.maxRange > 0 && mounted) setState(() => _maxRange = d.maxRange);
    }, onError: (_) {});
    listen('p', Device.instance.sensor(SensorType.proximity), (v) {
      final near = v[0] < _maxRange;
      if (near && !_near) _increment();
      _near = near;
    });
    listen('a', Device.instance.sensor(SensorType.accelerometer, rate: SensorRate.game), (v) {
      if (_shake.add(v)) {
        _count = 0;
        HapticFeedback.vibrate();
      }
    });
  }

  void _increment() {
    _count++;
    if (_count % _target == 0) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: Feature.tasbeeh, children: [
      const SensorChips(names: ['القرب', 'التسارع']),
      const SizedBox(height: 8),
      const Text('لوّح بيدك فوق أعلى الشاشة (حساس القرب) أو المس الدائرة. هزّة قوية تصفّر العدّاد، '
          'واهتزاز مميز عند كل دورة.'),
      ?errorFor('p'),
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          onTap: () => setState(_increment),
          child: CircleAvatar(
            radius: 110,
            backgroundColor: _near ? Colors.orange : Theme.of(context).colorScheme.primaryContainer,
            child: Text('$_count', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(child: Text('الدورة: ${_count ~/ _target} — الهدف $_target')),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 33, label: Text('33')),
          ButtonSegment(value: 100, label: Text('100')),
          ButtonSegment(value: 1000, label: Text('1000')),
        ],
        selected: {_target},
        onSelectionChanged: (s) => setState(() => _target = s.first),
      ),
    ]);
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const DemoScaffold(title: Feature.activity, children: [
      SensorChips(names: ['عدّاد الخطوات', 'التسارع الخطي', 'البارومتر']),
      SizedBox(height: 12),
      _MotionState(),
      Divider(),
      _Floors(),
      Divider(),
      PermissionGate(
        permission: AppPermission.activity,
        reason: 'لقراءة عدّاد الخطوات (إذن «النشاط البدني»).',
        child: _Steps(),
      ),
    ]);
  }
}

class _MotionState extends StatefulWidget {
  const _MotionState();
  @override
  State<_MotionState> createState() => _MotionStateState();
}

class _MotionStateState extends State<_MotionState> with Listens {
  double _avg = 0;
  bool _has = false;

  @override
  void initState() {
    super.initState();
    listen('l', Device.instance.sensor(SensorType.linearAcceleration, rate: SensorRate.game), (v) {
      _has = true;
      _avg = _avg * 0.95 + magnitude(v) * 0.05;
    });
  }

  @override
  Widget build(BuildContext context) {
    return errorFor('l') ??
        ListTile(
          leading: const Icon(Icons.directions_run, size: 36),
          title: const Text('حالتك الآن (التسارع الخطي)'),
          subtitle: Text(_has ? activityLabel(activityFrom(_avg)) : '…', style: const TextStyle(fontSize: 20)),
        );
  }
}

class _Floors extends StatefulWidget {
  const _Floors();
  @override
  State<_Floors> createState() => _FloorsState();
}

class _FloorsState extends State<_Floors> with Listens {
  double? _start;
  double? _alt;

  @override
  void initState() {
    super.initState();
    listen('b', Device.instance.sensor(SensorType.pressure), (v) {
      _alt = altitudeFromPressure(v[0]);
      _start ??= _alt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = errorFor('b');
    if (e != null) return e;
    final d = (_alt ?? 0) - (_start ?? 0);
    return ListTile(
      leading: const Icon(Icons.stairs, size: 36),
      title: const Text('الطوابق منذ فتح الصفحة (البارومتر)'),
      subtitle: Text(_alt == null ? '…' : '${(d / 3).toStringAsFixed(1)} طابق (${d.toStringAsFixed(1)} م)',
          style: const TextStyle(fontSize: 20)),
    );
  }
}

class _Steps extends StatefulWidget {
  const _Steps();
  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> with Listens {
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
    final steps = _now == null ? 0 : (_now! - _start!).round();
    return ListTile(
      leading: const Icon(Icons.directions_walk, size: 36),
      title: const Text('الخطوات منذ فتح الصفحة (عدّاد الخطوات)'),
      subtitle: Text('$steps خطوة ≈ ${(steps * 0.75).toStringAsFixed(0)} م', style: const TextStyle(fontSize: 20)),
    );
  }
}

class EnvironmentPage extends StatefulWidget {
  const EnvironmentPage({super.key});
  @override
  State<EnvironmentPage> createState() => _EnvironmentPageState();
}

class _EnvironmentPageState extends State<EnvironmentPage> with Listens {
  double? _lux;
  double? _temp;
  double? _humidity;

  @override
  void initState() {
    super.initState();
    listen('light', Device.instance.sensor(SensorType.light), (v) {
      _lux = v[0];
      if (autoNightMode.value) {
        // Hysteresis so the theme does not flicker around the threshold.
        if (v[0] < 15) themeMode.value = ThemeMode.dark;
        if (v[0] > 60) themeMode.value = ThemeMode.light;
      }
    });
    // Rare sensors: subscribe only if present, so most phones show nothing.
    Device.instance.has(SensorType.ambientTemperature).then((has) {
      if (has && mounted) listen('t', Device.instance.sensor(SensorType.ambientTemperature, rate: SensorRate.normal), (v) => _temp = v[0]);
    }, onError: (_) {});
    Device.instance.has(SensorType.humidity).then((has) {
      if (has && mounted) listen('h', Device.instance.sensor(SensorType.humidity, rate: SensorRate.normal), (v) => _humidity = v[0]);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final lux = _lux;
    return DemoScaffold(title: Feature.environment, children: [
      const SensorChips(names: ['الضوء', 'الميكروفون', 'الحرارة', 'الرطوبة']),
      const SizedBox(height: 8),
      errorFor('light') ??
          ListTile(
            leading: const Icon(Icons.light_mode, size: 36),
            title: Text(lux == null ? 'الإضاءة…' : 'الإضاءة: ${lux.toStringAsFixed(0)} lux — ${lightLabel(lux)}'),
            subtitle: Text(lux == null ? '' : (lux < 50 ? 'ضعيفة للقراءة: أشعل ضوءًا.' : 'مناسبة للقراءة ✔')),
          ),
      ValueListenableBuilder(
        valueListenable: autoNightMode,
        builder: (context, on, _) => SwitchListTile(
          title: const Text('الوضع الليلي التلقائي حسب الإضاءة'),
          value: on,
          onChanged: (v) {
            autoNightMode.value = v;
            if (!v) themeMode.value = ThemeMode.system;
          },
        ),
      ),
      if (_temp != null) ListTile(leading: const Icon(Icons.thermostat), title: Text('الحرارة: ${_temp!.toStringAsFixed(1)} °C')),
      if (_humidity != null) ListTile(leading: const Icon(Icons.water_drop), title: Text('الرطوبة: ${_humidity!.toStringAsFixed(0)} %')),
      if (_temp == null && _humidity == null)
        const ListTile(leading: Icon(Icons.info_outline), title: Text('لا يوجد حساس حرارة أو رطوبة في هذا الجوال (وهذا طبيعي).')),
      const Divider(),
      PermissionGate(
        permission: AppPermission.microphone,
        reason: 'لقياس هدوء المكان (الشدة فقط، بلا تسجيل).',
        child: LiveValue<double>(
          stream: Device.instance.soundLevel(),
          builder: (context, dbfs) {
            final db = approxDb(dbfs);
            return ListTile(
              leading: const Icon(Icons.mic, size: 36),
              title: Text('الضوضاء: ${db.toStringAsFixed(0)} dB تقريبًا — ${noiseLabel(db)}'),
              subtitle: Text(db < 50 ? 'المكان مناسب للقراءة والحفظ ✔' : 'المكان صاخب للتركيز.'),
            );
          },
        ),
      ),
    ]);
  }
}

class LevelPage extends StatefulWidget {
  const LevelPage({super.key});
  @override
  State<LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends State<LevelPage> with Listens {
  List<double>? _g;
  double _shake = 0;

  @override
  void initState() {
    super.initState();
    listen('g', Device.instance.sensor(SensorType.gravity, rate: SensorRate.game), (v) => _g = v);
    listen('r', Device.instance.sensor(SensorType.gyroscope, rate: SensorRate.game),
        (v) => _shake = _shake * 0.9 + magnitude(v) * 0.1);
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final steady = _shake < 0.05;
    return DemoScaffold(title: Feature.level, children: [
      const SensorChips(names: ['الجاذبية', 'الجيروسكوب']),
      const SizedBox(height: 16),
      errorFor('g') ?? (g == null ? const Center(child: CircularProgressIndicator()) : BubbleLevel(gravity: g)),
      const SizedBox(height: 16),
      if (errorFor('r') == null)
        ListTile(
          leading: Icon(steady ? Icons.check_circle : Icons.waves, color: steady ? Colors.green : Colors.orange),
          title: Text(steady ? 'الجوال ثابت — القراءة موثوقة' : 'الجوال يتحرك — انتظر حتى يثبت'),
          subtitle: const Text('من الجيروسكوب'),
        ),
    ]);
  }
}

class MagnifierPage extends StatefulWidget {
  const MagnifierPage({super.key});
  @override
  State<MagnifierPage> createState() => _MagnifierPageState();
}

class _MagnifierPageState extends State<MagnifierPage> with Listens {
  double _zoom = 2;
  bool _autoTorch = true;
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    listen('light', Device.instance.sensor(SensorType.light), (v) {
      if (v[0] < 15) _dark = true;
      if (v[0] > 40) _dark = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(title: Feature.magnifier, children: [
      const SensorChips(names: ['الكاميرا', 'الضوء']),
      const SizedBox(height: 8),
      PermissionGate(
        permission: AppPermission.camera,
        reason: 'لعرض الخط مكبّرًا. لا تُلتقط ولا تُحفظ أي صورة.',
        child: CameraView(zoom: _zoom, torch: _autoTorch && _dark),
      ),
      Row(children: [
        const Icon(Icons.zoom_in),
        Expanded(
          child: Slider(value: _zoom, min: 1, max: 8, divisions: 14, label: '×${_zoom.toStringAsFixed(1)}',
              onChanged: (v) => setState(() => _zoom = v)),
        ),
      ]),
      SwitchListTile(
        title: const Text('تشغيل الكشاف تلقائيًا في الظلام (حساس الضوء)'),
        subtitle: Text(errors.containsKey('light') ? 'لا يوجد حساس ضوء' : (_dark ? 'المكان مظلم: الكشاف يعمل' : 'الإضاءة كافية')),
        value: _autoTorch,
        onChanged: (v) => setState(() => _autoTorch = v),
      ),
    ]);
  }
}
