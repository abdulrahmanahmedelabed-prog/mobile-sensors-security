import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'model.dart';
import 'store.dart';

Color gradeColor(Grade g) => switch (g) {
      Grade.safe => const Color(0xFF2E7D32),
      Grade.fair => const Color(0xFF9E9D24),
      Grade.attention => const Color(0xFFEF6C00),
      Grade.risky => const Color(0xFFC62828),
    };

Color severityColor(Severity s) => switch (s) {
      Severity.critical => const Color(0xFF7F1D1D),
      Severity.high => const Color(0xFFC62828),
      Severity.medium => const Color(0xFFEF6C00),
      Severity.low => const Color(0xFF9E9D24),
      Severity.info => const Color(0xFF546E7A),
    };

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.report, this.size = 48});
  final AppReport report;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(report.grade);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: report.score / 100,
            strokeWidth: size / 10,
            color: c,
            backgroundColor: c.withValues(alpha: 0.15),
          ),
        ),
        Text('${report.score}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: size / 3, color: c)),
      ]),
    );
  }
}

class AppIcon extends StatefulWidget {
  const AppIcon({super.key, required this.store, required this.package});
  final ScanStore store;
  final String package;

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  static final _cache = <String, Uint8List?>{};
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    if (_cache.containsKey(widget.package)) {
      _png = _cache[widget.package];
    } else {
      widget.store.packages.icon(widget.package).then((p) {
        _cache[widget.package] = p;
        if (mounted) setState(() => _png = p);
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) =>
      _png == null ? const Icon(Icons.android, size: 40) : Image.memory(_png!, width: 40, height: 40);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final ScanStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScanStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final reports = store.reports;
        return Scaffold(
          appBar: AppBar(title: const Text('فاحص التطبيقات'), actions: [
            IconButton(
              tooltip: 'عن الفحص',
              icon: const Icon(Icons.info_outline),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ]),
          body: store.loading
              ? const Center(child: CircularProgressIndicator())
              : store.error != null
                  ? Center(child: Text(store.error!))
                  : RefreshIndicator(
                      onRefresh: store.load,
                      child: ListView(children: [
                        _Summary(reports: reports),
                        SwitchListTile(
                          title: const Text('إظهار تطبيقات النظام'),
                          value: store.showSystem,
                          onChanged: store.setShowSystem,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: store.deepTotal > 0
                              ? Column(children: [
                                  LinearProgressIndicator(value: store.deepDone / store.deepTotal),
                                  Text('فحص الكود: ${store.deepDone} من ${store.deepTotal}'),
                                ])
                              : OutlinedButton.icon(
                                  onPressed: store.deepScanAll,
                                  icon: const Icon(Icons.manage_search),
                                  label: const Text('فحص عميق لكود كل التطبيقات (يبحث عن مفاتيح سرية مسرّبة)'),
                                ),
                        ),
                        for (final r in reports)
                          ListTile(
                            leading: AppIcon(store: store, package: r.app.package),
                            title: Text(r.app.label),
                            subtitle: Text(
                              '${gradeLabel(r.grade)} · ${r.findings.where((f) => f.severity != Severity.info).length} ملاحظة'
                              '${store.deepScanned(r.app.package) ? ' · فُحص الكود' : ''}',
                            ),
                            trailing: ScoreBadge(report: r),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => AppDetailScreen(store: store, package: r.app.package))),
                          ),
                      ]),
                    ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.reports});
  final List<AppReport> reports;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final g in Grade.values) g: reports.where((r) => r.grade == g).length};
    final avg = reports.isEmpty ? 0 : reports.fold<int>(0, (s, r) => s + r.score) ~/ reports.length;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('فُحص ${reports.length} تطبيقًا · متوسط الأمان $avg/100', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final g in Grade.values)
              Column(children: [
                Text('${counts[g]}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: gradeColor(g))),
                Text(gradeLabel(g)),
              ]),
          ]),
        ]),
      ),
    );
  }
}

class AppDetailScreen extends StatelessWidget {
  const AppDetailScreen({super.key, required this.store, required this.package});
  final ScanStore store;
  final String package;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final r = store.reports.where((r) => r.app.package == package).firstOrNull;
        if (r == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('التطبيق غير موجود')));
        final a = r.app;
        final updated = a.lastUpdate == 0 ? '—' : DateTime.fromMillisecondsSinceEpoch(a.lastUpdate).toString().substring(0, 10);
        return Scaffold(
          appBar: AppBar(title: Text(a.label)),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              ScoreBadge(report: r, size: 88),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(gradeLabel(r.grade),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: gradeColor(r.grade))),
                  Directionality(textDirection: TextDirection.ltr, child: Text(a.package, style: const TextStyle(fontSize: 12))),
                  Text('الإصدار ${a.versionName ?? '?'} · يستهدف API ${a.targetSdk} · آخر تحديث $updated'),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              if (!store.deepScanned(a.package))
                FilledButton.icon(
                  onPressed: store.deepRunning(a.package) ? null : () => store.deepScanApp(a),
                  icon: store.deepRunning(a.package)
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.manage_search),
                  label: const Text('فحص الكود'),
                ),
              OutlinedButton.icon(
                onPressed: () => store.packages.openSettings(a.package),
                icon: const Icon(Icons.settings),
                label: const Text('الأذونات / الحذف'),
              ),
            ]),
            const SizedBox(height: 12),
            if (r.findings.isEmpty) const Card(child: ListTile(leading: Icon(Icons.verified, color: Colors.green), title: Text('لم نجد ملاحظات ✔'))),
            for (final f in r.findings) FindingCard(finding: f),
          ]),
        );
      },
    );
  }
}

class FindingCard extends StatelessWidget {
  const FindingCard({super.key, required this.finding});
  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final f = finding;
    final c = severityColor(f.severity);
    return Card(
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
          child: Text(f.severity.arabic, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        title: Text(f.title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.explanation),
          const SizedBox(height: 8),
          Text('ماذا تفعل؟ ${f.advice}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (f.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final d in f.details.take(30)) Text('• $d', style: const TextStyle(fontSize: 12)),
            if (f.details.length > 30) Text('… و${f.details.length - 30} أخرى'),
          ],
          Text(f.id, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const checks = [
    ('مصدر التثبيت', 'هل جاء التطبيق من متجر رسمي؟'),
    ('التوقيع', 'هل هو موقّع بمفتاح تجريبي أو شهادة ضعيفة؟ (نسخ معدّلة)'),
    ('وضع التصحيح', 'هل هو نسخة مطوّرين قابلة للتصحيح؟'),
    ('عمر التطبيق', 'هل يستهدف أندرويد قديمًا يتجاوز حمايات الخصوصية؟ ومتى حُدّث آخر مرة؟'),
    ('الاتصال', 'هل يسمح باتصال HTTP غير مشفّر؟'),
    ('الصلاحيات', 'صلاحيات قوية (رسائل، والظهور فوق التطبيقات، وإمكانية الوصول…) وأذونات بياناتك'),
    ('الأجزاء المكشوفة', 'مزوّدات محتوى وخدمات يمكن لأي تطبيق آخر استدعاؤها دون إذن'),
    ('الفحص العميق', 'يقرأ كود التطبيق بحثًا عن مفاتيح سرية مسرّبة وعناوين HTTP'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عن الفحص')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.privacy_tip),
            title: Text('خصوصيتك'),
            subtitle: Text('هذا التطبيق بلا أي إذن، ولا إنترنت، ولا يحفظ شيئًا. يقرأ فقط ما يتيحه أندرويد لكل التطبيقات، '
                'ولا يغيّر أي تطبيق آخر.'),
          ),
        ),
        for (final (t, d) in checks) ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(t), subtitle: Text(d)),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info),
            title: Text('حدود الفحص'),
            subtitle: Text('الدرجة تقدير آلي وليست حكمًا نهائيًا: تطبيق بدرجة عالية قد يجمع بياناتك بطرق مشروعة، '
                'وملاحظة قد تكون مقصودة من المطوّر. يظهر هنا كل تطبيق له أيقونة في قائمة التطبيقات. '
                'للفحص الأعمق للكود من الكمبيوتر استخدم أداة mvscan.'),
          ),
        ),
      ]),
    );
  }
}
