import 'package:flutter/material.dart';

import '../companion/companion_app.dart';
import '../data/catalog.dart';
import '../platform/device.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, WidgetBuilder)>[
      (Icons.menu_book, 'دليل الحساسات', '${catalog.length} حساسًا: ماذا يقيس كل حساس، وكيف يعمل، وما فوائده، مع تجربة بسيطة لكل منها',
          (_) => const CatalogScreen()),
      (Icons.apps, 'رفيق: التطبيق الشامل', 'تطبيق واحد يستخدم كل الحساسات: القبلة، والمسبحة، والنشاط، وبيئة القراءة، والميزان، والعدسة المكبّرة',
          (_) => const CompanionApp()),
      (Icons.phone_android, 'حساسات جوالي', 'قائمة بكل الحساسات الموجودة فعليًا في جوالك ومواصفاتها', (_) => const MySensorsScreen()),
      (Icons.shield, 'الأمان والخصوصية', 'كيف يحمي هذا التطبيق بياناتك', (_) => const SecurityScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('حساسات الجوال')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final (icon, title, sub, page) in items)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Icon(icon, size: 40),
              title: Text(title, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(sub),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: page)),
            ),
          ),
      ]),
    );
  }
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دليل الحساسات')),
      body: ListView(children: [
        for (final g in SensorGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(groupName(g), style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final s in catalog.where((s) => s.group == g))
            ListTile(
              leading: Icon(s.icon),
              title: Text(s.name),
              subtitle: Text(s.english),
              trailing: s.virtual ? const Chip(label: Text('برمجي')) : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SensorDetailScreen(info: s))),
            ),
        ],
      ]),
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
  const MySensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حساسات جوالي')),
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
  const SecurityScreen({super.key});

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
      appBar: AppBar(title: const Text('الأمان والخصوصية')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final (title, body) in points)
          Card(child: ListTile(leading: const Icon(Icons.verified_user), title: Text(title), subtitle: Text(body))),
      ]),
    );
  }
}
