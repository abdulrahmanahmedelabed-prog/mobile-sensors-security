import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/catalog.dart';
import '../data/devices.dart';
import '../platform/device.dart';

Color scoreColor(int score) {
  if (score >= 70) return const Color(0xFF2E7D32);
  if (score >= 50) return const Color(0xFF9E9D24);
  if (score >= 35) return const Color(0xFFEF6C00);
  return const Color(0xFFC62828);
}

/// This phone, described like the phones in the list, from what Android
/// reports (sensor types) and the biometrics local_auth sees.
Future<PhoneSpec?> thisPhone({Future<List<BiometricType>> Function()? biometrics}) async {
  try {
    final types = {for (final s in await Device.instance.sensors()) s.type};
    List<BiometricType> bio = const [];
    try {
      bio = await (biometrics ?? LocalAuthentication().getAvailableBiometrics)().timeout(const Duration(seconds: 3));
    } catch (_) {
      // No biometrics API, or it did not answer: treat as no fingerprint reader.
    }
    return PhoneSpec(
      name: 'جوالك',
      brand: '',
      year: DateTime.now().year,
      // Android does not say which kind of fingerprint reader it is.
      fingerprint: bio.isNotEmpty ? Fingerprint.optical : Fingerprint.none,
      gyro: types.contains(SensorType.gyroscope),
      compass: types.contains(SensorType.magneticField),
      proximity: types.contains(SensorType.proximity) ? Proximity.real : Proximity.none,
      barometer: types.contains(SensorType.pressure),
      ambientTemperature: types.contains(SensorType.ambientTemperature),
      humidity: types.contains(SensorType.humidity),
      heartRate: types.contains(21), // Sensor.TYPE_HEART_RATE
    );
  } catch (_) {
    return null;
  }
}

class ScoreBar extends StatelessWidget {
  const ScoreBar({super.key, required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final c = scoreColor(score);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: score / 100, minHeight: 10, color: c, backgroundColor: c.withValues(alpha: 0.15)),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(width: 36, child: Text('$score', style: TextStyle(fontWeight: FontWeight.bold, color: c))),
    ]);
  }
}

/// Phones ranked by how many of the important sensors they have.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.embedded = false, this.loadThisPhone = thisPhone});
  final bool embedded;
  final Future<PhoneSpec?> Function() loadThisPhone;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final Future<PhoneSpec?> _mine = widget.loadThisPhone();
  String? _brand;
  bool _androidOnly = false;

  @override
  Widget build(BuildContext context) {
    final brands = {for (final p in phones) p.brand}.toList()..sort();
    final ranked = rankedPhones(brand: _brand, androidOnly: _androidOnly);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('أفضل الأجهزة للحساسات')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        FutureBuilder(
          future: _mine,
          builder: (context, snap) {
            final mine = snap.data;
            if (mine == null) return const SizedBox.shrink();
            final s = sensorScore(mine);
            final better = phones.where((p) => sensorScore(p) > s).length;
            return Card(
              margin: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.smartphone, size: 36),
                title: const Text('جوالك'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ScoreBar(score: s),
                  Text(better == 0 ? 'جوالك في القمة مع أفضل الأجهزة هنا ✔' : 'يتفوّق عليه $better من ${phones.length} أجهزة في القائمة'),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneDetailScreen(phone: mine))),
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('الدرجة من 100 بحسب الحساسات المهمة: الجيروسكوب والبوصلة والبارومتر (3 نقاط لكل منها)، '
              'والبصمة فوق الصوتية والوجه ثلاثي الأبعاد (3)، وUWB والعمق (2)، والقرب الحقيقي (2)، '
              'والحرارة والرطوبة والنبض والأكسجين والطيف اللوني (1). ما لم يتأكد لا يُحسب.'),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            FilterChip(
              label: const Text('أندرويد فقط'),
              selected: _androidOnly,
              onSelected: (v) => setState(() => _androidOnly = v),
            ),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('الكل'), selected: _brand == null, onSelected: (_) => setState(() => _brand = null)),
            for (final b in brands) ...[
              const SizedBox(width: 6),
              ChoiceChip(label: Text(b), selected: _brand == b, onSelected: (_) => setState(() => _brand = b)),
            ],
          ]),
        ),
        for (final (i, p) in ranked.indexed)
          ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(p.fullName),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ScoreBar(score: sensorScore(p)),
              Text('${p.year}${p.ios ? ' · iOS (للمقارنة)' : ''}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneDetailScreen(phone: p))),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('المصادر: GSMArena ومواقع الشركات المصنّعة، تحقّقنا منها في أكتوبر 2026. '
              'الحساسات الموجودة في كل الجوالات (التسارع، والضوء، وGPS، والميكروفون، والكاميرا، وعدّاد الخطوات) لا تدخل في الدرجة.'),
        ),
      ]),
    );
  }
}

class PhoneDetailScreen extends StatelessWidget {
  const PhoneDetailScreen({super.key, required this.phone});
  final PhoneSpec phone;

  @override
  Widget build(BuildContext context) {
    final p = phone;
    Widget row(String name, bool? has, [String? detail]) => ListTile(
          dense: true,
          leading: Icon(
            has == true ? Icons.check_circle : (has == false ? Icons.cancel : Icons.help_outline),
            color: has == true ? Colors.green : (has == false ? Colors.grey : Colors.orange),
          ),
          title: Text(name),
          subtitle: detail == null ? null : Text(detail),
          trailing: has == null ? const Text('غير مؤكد') : null,
        );
    final title = p.brand.isEmpty ? p.name : p.fullName;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('درجة الحساسات', style: Theme.of(context).textTheme.titleMedium),
              ScoreBar(score: sensorScore(p)),
              if (p.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.note!)),
              if (p.brand.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('من قراءة أندرويد لحساسات جوالك. نوع البصمة والوجه ثلاثي الأبعاد وUWB لا يمكن معرفتها من التطبيق.'),
                ),
            ]),
          ),
        ),
        row('الجيروسكوب', p.gyro),
        row('البوصلة (المغناطيس)', p.compass),
        row('البارومتر', p.barometer),
        row('حساس القرب', p.proximity == null ? null : p.proximity != Proximity.none, proximityLabel(p.proximity)),
        row('البصمة', p.fingerprint == null ? null : p.fingerprint != Fingerprint.none, fingerprintLabel(p.fingerprint)),
        row('بصمة الوجه ثلاثية الأبعاد', p.face3d),
        row('UWB (تحديد المكان بدقة سنتيمترات)', p.uwb),
        row('حساس العمق (LiDAR / ToF)', p.depth),
        row('مستشعر الطيف اللوني للكاميرا', p.colorSpectrum),
        row('ميزان حرارة بالأشعة تحت الحمراء', p.thermometer),
        row('حرارة الجو', p.ambientTemperature),
        row('الرطوبة', p.humidity),
        row('نبض القلب', p.heartRate),
        row('أكسجين الدم', p.spo2),
        const Divider(),
        const ListTile(
          dense: true,
          leading: Icon(Icons.check_circle, color: Colors.green),
          title: Text('التسارع، والضوء، وGPS، والميكروفون، والكاميرا، وعدّاد الخطوات'),
          subtitle: Text('موجودة في كل الجوالات الحديثة'),
        ),
      ]),
    );
  }
}

/// "Which phones have this sensor?" for a catalog sensor.
class SupportingPhones extends StatelessWidget {
  const SupportingPhones({super.key, required this.info});
  final SensorInfo info;

  @override
  Widget build(BuildContext context) {
    if (universalSensors.contains(info.id)) {
      return const Text('موجود في كل الجوالات الحديثة تقريبًا، فلا تحتاج للبحث عنه عند الشراء.');
    }
    final yes = [for (final p in rankedPhones()) if (phoneHas(p, info.id) == true) p];
    final unknown = [for (final p in rankedPhones()) if (phoneHas(p, info.id) == null) p];
    final no = phones.length - yes.length - unknown.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('يدعمه ${yes.length} من ${phones.length} أجهزة في قائمتنا${no > 0 ? '، ولا يدعمه $no' : ''}:'),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in yes)
          ActionChip(
            avatar: const Icon(Icons.check, size: 16, color: Colors.green),
            label: Text(p.fullName),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneDetailScreen(phone: p))),
          ),
        for (final p in unknown)
          ActionChip(
            avatar: const Icon(Icons.help_outline, size: 16, color: Colors.orange),
            label: Text('${p.fullName} (غير مؤكد)'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneDetailScreen(phone: p))),
          ),
      ]),
      if (yes.isEmpty) const Text('لا يوجد جهاز حديث في القائمة يضمّه؛ وُجد في جوالات قديمة فقط.'),
      TextButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen())),
        icon: const Icon(Icons.leaderboard),
        label: const Text('أفضل الأجهزة في كل الحساسات'),
      ),
    ]);
  }
}
