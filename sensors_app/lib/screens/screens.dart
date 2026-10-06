import 'package:flutter/material.dart';

import '../companion/companion_app.dart';
import '../data/catalog.dart';
import '../platform/device.dart';
import '../widgets/common.dart';

/// The app's four parts, kept apart as in phyphox or Physics Toolbox:
/// try sensors (المختبر), use them (رفيق), learn (الدليل), inspect the phone (جوالي).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  // Tabs are built on first visit only, so رفيق asks for the fingerprint when
  // opened, not at app start; visited tabs keep their state.
  final _visited = <int>{0};

  static const _pages = <Widget>[LabScreen(), CompanionApp(), CatalogScreen(), PhoneScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          for (final (i, page) in _pages.indexed) _visited.contains(i) ? page : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.science_outlined), selectedIcon: Icon(Icons.science), label: 'المختبر'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'رفيق'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'الدليل'),
          NavigationDestination(icon: Icon(Icons.phone_android_outlined), selectedIcon: Icon(Icons.phone_android), label: 'جوالي'),
        ],
      ),
    );
  }
}

/// Which catalog sensors this phone has (null while unknown, e.g. GPS).
Future<Map<String, bool?>> sensorAvailability() async {
  List<SensorDescription> list;
  try {
    list = await Device.instance.sensors();
  } catch (_) {
    return {};
  }
  final types = {for (final s in list) s.type};
  return {for (final s in catalog) s.id: s.androidType == null ? null : types.contains(s.androidType)};
}

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.available});
  final bool? available;

  @override
  Widget build(BuildContext context) {
    return switch (available) {
      true => const Tooltip(message: 'موجود في جوالك', child: Icon(Icons.check_circle, color: Colors.green, size: 20)),
      false => const Tooltip(message: 'غير موجود في جوالك', child: Icon(Icons.cancel, color: Colors.grey, size: 20)),
      null => const SizedBox(width: 20),
    };
  }
}

/// Every sensor as a tile: tap to try it, ⓘ to read about it.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late final Future<Map<String, bool?>> _available = sensorAvailability();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المختبر: جرّب حساسات جوالك')),
      body: FutureBuilder(
        future: _available,
        builder: (context, snap) {
          final available = snap.data ?? const {};
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 150,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: catalog.length,
            itemBuilder: (context, i) {
              final s = catalog[i];
              final missing = available[s.id] == false;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: s.demo)),
                  child: Opacity(
                    opacity: missing ? 0.5 : 1,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(s.icon, size: 32, color: Theme.of(context).colorScheme.primary),
                          const Spacer(),
                          AvailabilityBadge(available: available[s.id]),
                          IconButton(
                            tooltip: 'عن ${s.name}',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.info_outline, size: 20),
                            onPressed: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => SensorDetailScreen(info: s))),
                          ),
                        ]),
                        const Spacer(),
                        Text(s.demoTitle, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(s.name, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The phone's own sensors and the app's privacy promises.
class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('جوالي'),
          bottom: const TabBar(tabs: [Tab(text: 'حساسات جوالي'), Tab(text: 'الخصوصية والأمان')]),
        ),
        body: const TabBarView(children: [MySensorsScreen(embedded: true), SecurityScreen(embedded: true)]),
      ),
    );
  }
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final Future<Map<String, bool?>> _available = sensorAvailability();
  String _query = '';

  bool _matches(SensorInfo s) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [s.name, s.english, s.measures, ...s.benefits, ...s.examples].any((t) => t.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دليل الحساسات')),
      body: FutureBuilder(
        future: _available,
        builder: (context, snap) {
          final available = snap.data ?? const {};
          final shown = catalog.where(_matches).toList();
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث: بوصلة، خطوات، ضوء، Gyroscope…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد نتائج.')),
            for (final g in SensorGroup.values)
              if (shown.any((s) => s.group == g)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(groupName(g), style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final s in shown.where((s) => s.group == g))
                  ListTile(
                    leading: Icon(s.icon),
                    title: Text(s.name),
                    subtitle: Text(s.english + (s.virtual ? ' · برمجي' : '')),
                    trailing: AvailabilityBadge(available: available[s.id]),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SensorDetailScreen(info: s))),
                  ),
              ],
          ]);
        },
      ),
    );
  }
}

class SensorDetailScreen extends StatelessWidget {
  const SensorDetailScreen({super.key, required this.info});
  final SensorInfo info;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget section(String title, Widget body) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 4),
            body,
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(info.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Icon(info.icon, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.name, style: t.headlineSmall),
              Text(info.english + (info.virtual ? ' — حساس برمجي' : '')),
            ]),
          ),
        ]),
        section('ماذا يقيس؟', Text(info.measures)),
        section('كيف يعمل؟', Text(info.how)),
        section('فوائده', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in info.benefits) Text('✓ $b'),
        ])),
        section('أمثلة من تطبيقات معروفة', Text(info.examples.join('، '))),
        section('الإذن المطلوب', Text(info.permission == null ? 'لا يحتاج إذنًا' : 'إذن «${info.permission}» — يُطلب عند فتح التجربة فقط')),
        section('أين يُستخدم في «رفيق»؟', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final MapEntry(key: f, value: what) in info.usedIn.entries) Text('• $f: $what'),
        ])),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: info.demo)),
          icon: const Icon(Icons.play_arrow),
          label: Text('جرّب: ${info.demoTitle}'),
        ),
      ]),
    );
  }
}

class MySensorsScreen extends StatelessWidget {
  const MySensorsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('حساسات جوالي')),
      body: FutureBuilder<List<SensorDescription>>(
        future: Device.instance.sensors(),
        builder: (context, snap) {
          if (snap.hasError) return Unavailable(message: describeStreamError(snap.error!));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          final known = {for (final s in catalog) if (s.androidType != null) s.androidType!: s};
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('في جوالك ${list.length} حساسًا (منها حساسات برمجية ونسخ احتياطية تستيقظ الجوال).'),
            ),
            for (final s in list)
              ListTile(
                leading: Icon(known[s.type]?.icon ?? Icons.sensors),
                title: Text(known[s.type]?.name ?? 'نوع ${s.type}'),
                subtitle: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${s.name} — ${s.vendor}\nmax ${s.maxRange.toStringAsFixed(2)}, '
                      'res ${s.resolution.toStringAsPrecision(2)}, ${s.power.toStringAsFixed(2)} mA'
                      '${s.isWakeUp ? ', wake-up' : ''}'),
                ),
                isThreeLine: true,
              ),
          ]);
        },
      ),
    );
  }
}

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key, this.embedded = false});
  final bool embedded;

  static const points = [
    ('لا إنترنت إطلاقًا', 'التطبيق لا يملك إذن الإنترنت، فلا يمكنه إرسال أي قراءة خارج جوالك حتى لو أراد.'),
    ('لا تخزين', 'لا يحفظ أي قراءة أو صورة أو صوت. الصورة الملتقطة تبقى في الذاكرة وتُحذف عند الإغلاق.'),
    ('الإذن عند الحاجة فقط', 'كل إذن يُطلب عند فتح الميزة التي تحتاجه، مع شرح السبب، ويمكنك رفضه.'),
    ('أقل صلاحية ممكنة', 'القبلة تكتفي بالموقع التقريبي، والميكروفون يقيس شدة الصوت فقط دون تسجيل.'),
    ('لا عمل في الخلفية', 'كل الحساسات تتوقف فور خروجك من التطبيق أو إغلاق الصفحة.'),
    ('البصمة لا تغادر الشريحة الآمنة', 'التطبيق يتلقى «نجح/فشل» فقط، ويُقفل «رفيق» عند الخروج منه.'),
    ('لا نسخ احتياطي', 'النسخ الاحتياطي معطّل، وإعدادات الشبكة تمنع HTTP غير المشفّر.'),
    ('تحقق من المدخلات', 'الجزء الأصلي (Kotlin) لا يقبل إلا أنواع حساسات وأذونات من قائمة مسموحة.'),
    ('فحص آلي للثغرات', 'كل نسخة تُفحص بأداة mvscan في GitHub Actions قبل البناء.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('الأمان والخصوصية')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final (title, body) in points)
          Card(child: ListTile(leading: const Icon(Icons.verified_user), title: Text(title), subtitle: Text(body))),
      ]),
    );
  }
}
