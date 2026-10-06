import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_scanner/deep_scan.dart';
import 'package:app_scanner/main.dart';
import 'package:app_scanner/model.dart';
import 'package:app_scanner/rules.dart';
import 'package:app_scanner/store.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake secrets assembled at runtime so secret scanners ignore the test data.
final fakeAws = 'AKIA${'IOSFODNN7EXAMPLE'}';
final fakeStripe = 'sk_${'live_'}abcdefghijklmnopqrstuvwx';

AppInfo app({
  String package = 'com.example.app',
  int targetSdk = 34,
  bool debuggable = false,
  bool cleartext = false,
  String? installer = 'com.android.vending',
  List<Permission> permissions = const [],
  List<Component> components = const [],
  List<Certificate> certificates = const [],
  int lastUpdate = 0,
}) =>
    AppInfo(
      package: package,
      label: package,
      targetSdk: targetSdk,
      debuggable: debuggable,
      cleartext: cleartext,
      installer: installer,
      permissions: permissions,
      components: components,
      certificates: certificates,
      lastUpdate: lastUpdate,
    );

Set<String> ids(AppInfo a) => {for (final f in checkApp(a, deviceSdk: 35, now: DateTime(2026, 10))) f.id};

Uint8List dex(List<String> strings) {
  final dataOff = 0x70 + 4 * strings.length;
  final header = ByteData(0x70);
  for (final (i, b) in 'dex\n035\x00'.codeUnits.indexed) {
    header.setUint8(i, b);
  }
  header.setUint32(0x38, strings.length, Endian.little);
  header.setUint32(0x3c, 0x70, Endian.little);
  final ids = ByteData(4 * strings.length);
  final data = BytesBuilder();
  for (final (i, s) in strings.indexed) {
    ids.setUint32(4 * i, dataOff + data.length, Endian.little);
    data
      ..addByte(s.length)
      ..add(utf8.encode(s))
      ..addByte(0);
  }
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(ids.buffer.asUint8List())
        ..add(data.takeBytes()))
      .takeBytes();
}

/// Minimal zip writer (deflate) for test APKs.
Uint8List zip(Map<String, Uint8List> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  for (final MapEntry(key: name, value: data) in files.entries) {
    final comp = Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
    final nameBytes = utf8.encode(name);
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(8, 8, Endian.little)
      ..setUint32(18, comp.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(comp);
    final cd = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(10, 8, Endian.little)
      ..setUint32(20, comp.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(cd.buffer.asUint8List())
      ..add(nameBytes);
  }
  final cdOffset = out.length;
  final cdBytes = central.takeBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

class FakePackages extends Packages {
  FakePackages(this.apps);
  final List<AppInfo> apps;
  @override
  Future<List<AppInfo>> list() async => apps;
  @override
  Future<int> sdk() async => 35;
  @override
  Future<Uint8List?> icon(String package) async => null;
}

void main() {
  group('rules', () {
    test('a clean store app has no findings and full score', () {
      final r = AppReport(app(), checkApp(app(), deviceSdk: 35, now: DateTime(2026, 10)));
      expect(r.findings, isEmpty);
      expect(r.score, 100);
      expect(r.grade, Grade.safe);
    });

    test('debuggable, cleartext, old target and sideloading are flagged', () {
      final found = ids(app(debuggable: true, cleartext: true, targetSdk: 22, installer: null));
      expect(found, containsAll(['AS-DBG', 'AS-CLR', 'AS-TGT', 'AS-SRC']));
    });

    test('severity of an old target SDK', () {
      Severity sev(int t) => checkApp(app(targetSdk: t), deviceSdk: 35).firstWhere((f) => f.id == 'AS-TGT').severity;
      expect(sev(22), Severity.high);
      expect(sev(28), Severity.medium);
      expect(sev(30), Severity.low);
      expect(ids(app(targetSdk: 33)), isNot(contains('AS-TGT')));
    });

    test('debug certificate', () {
      expect(ids(app(certificates: const [Certificate(sha256: 'x', subject: 'CN=Android Debug,O=Android,C=US')])),
          contains('AS-CERT'));
    });

    test('powerful permissions and services', () {
      final a = app(
        permissions: const [Permission('android.permission.READ_SMS', true), Permission('android.permission.CAMERA', true)],
        components: const [
          Component(kind: 'service', name: 'Acc', exported: true, permission: 'android.permission.BIND_ACCESSIBILITY_SERVICE'),
        ],
      );
      final f = checkApp(a, deviceSdk: 35);
      final pwr = f.firstWhere((x) => x.id == 'AS-PWR');
      expect(pwr.details.length, 2);
      expect(f.firstWhere((x) => x.id == 'AS-PRV').severity, Severity.info);
      // A permission-guarded service is not "open to any app".
      expect(f.map((x) => x.id), isNot(contains('AS-EXP')));
    });

    test('exported components without permission, launcher excluded', () {
      final a = app(components: const [
        Component(kind: 'activity', name: 'Main', exported: true, launcher: true),
        Component(kind: 'provider', name: 'Files', exported: true, authority: 'com.example.files'),
        Component(kind: 'receiver', name: 'Rx', exported: true),
        Component(kind: 'service', name: 'Off', exported: true, enabled: false),
      ]);
      final f = checkApp(a, deviceSdk: 35);
      expect(f.firstWhere((x) => x.id == 'AS-PROV').details, ['com.example.files']);
      expect(f.firstWhere((x) => x.id == 'AS-EXP').details, ['receiver: Rx']);
    });

    test('not updated for years', () {
      expect(ids(app(lastUpdate: DateTime(2021).millisecondsSinceEpoch)), contains('AS-OLD'));
    });

    test('score never goes below zero', () {
      final r = AppReport(app(), List.filled(10, const Finding(id: 'x', severity: Severity.critical, title: '', explanation: '', advice: '')));
      expect(r.score, 0);
      expect(r.grade, Grade.risky);
    });
  });

  group('deep scan', () {
    test('dex string table', () {
      expect(dexStrings(dex(['a', 'hello'])), ['a', 'hello']);
      expect(dexStrings(Uint8List.fromList([1, 2, 3])), isEmpty);
    });

    test('finds secrets in an APK and masks them', () {
      final dir = Directory.systemTemp.createTempSync('apk');
      addTearDown(() => dir.deleteSync(recursive: true));
      final apk = File('${dir.path}/base.apk')
        ..writeAsBytesSync(zip({
          'AndroidManifest.xml': Uint8List(8),
          'classes.dex': dex(['Lcom/x/Main;', fakeAws, 'http://tracker.bad-site.com/x']), // mvscan:ignore test data
          'lib/arm64-v8a/libapp.so': Uint8List.fromList([0, ...utf8.encode('key=$fakeStripe'), 0]),
        }));
      final f = deepScanSync([apk.path]);
      final titles = f.map((x) => x.title).join('|');
      expect(titles, contains('AWS'));
      expect(titles, contains('Stripe'));
      expect(f.any((x) => x.id == 'AS-HTTP'), isTrue);
      for (final x in f) {
        for (final d in x.details) {
          expect(d, isNot(contains(fakeAws)));
          expect(d, isNot(contains(fakeStripe)));
        }
      }
    });

    test('broken or missing files do not crash', () {
      final dir = Directory.systemTemp.createTempSync('apk');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File('${dir.path}/bad.apk')..writeAsBytesSync(List.filled(100, 7));
      expect(deepScanSync([bad.path, '${dir.path}/missing.apk']), isEmpty);
    });
  });

  testWidgets('lists apps from riskiest to safest and opens details', (tester) async {
    final store = ScanStore(
      packages: FakePackages([
        app(package: 'com.good.app'),
        app(package: 'com.bad.app', debuggable: true, installer: null, cleartext: true),
      ]),
      deepScanner: (_) async => const [],
    );
    await tester.pumpWidget(AppScannerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('فُحص 2 تطبيقًا · متوسط الأمان 82/100'), findsOneWidget);
    final bad = tester.getTopLeft(find.text('com.bad.app'));
    final good = tester.getTopLeft(find.text('com.good.app'));
    expect(bad.dy, lessThan(good.dy));
    await tester.tap(find.text('com.bad.app'));
    await tester.pumpAndSettle();
    expect(find.text('نسخة تجريبية قابلة للتصحيح'), findsOneWidget);
    await tester.tap(find.text('فحص الكود'));
    await tester.pumpAndSettle();
    expect(find.text('فحص الكود'), findsNothing);
  });
}
