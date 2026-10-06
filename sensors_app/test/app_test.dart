import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_lab/companion/companion_app.dart';
import 'package:sensors_lab/data/catalog.dart';
import 'package:sensors_lab/demos/environment_demos.dart';
import 'package:sensors_lab/main.dart';
import 'package:sensors_lab/platform/device.dart';
import 'package:sensors_lab/screens/screens.dart';

/// Fakes the native side: a phone with an accelerometer and a light sensor only.
void fakeDevice(WidgetTester tester) {
  final m = tester.binding.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('sensors_lab/device'), (call) async {
    switch (call.method) {
      case 'sensors':
        return [
          {'type': SensorType.accelerometer, 'name': 'acc', 'vendor': 'v', 'maxRange': 78.0, 'isDefault': true},
          {'type': SensorType.light, 'name': 'light', 'vendor': 'v', 'maxRange': 10000.0, 'isDefault': true},
        ];
      case 'permissionStatus':
        return false;
    }
    return null;
  });
  for (final type in [SensorType.light, SensorType.pressure]) {
    m.setMockStreamHandler(
      EventChannel('sensors_lab/sensor/$type'),
      MockStreamHandler.inline(onListen: (args, sink) {
        if (type == SensorType.light) {
          sink.success([25.0, 3.0]);
        } else {
          sink.error(code: 'UNAVAILABLE', message: 'none');
        }
      }),
    );
  }
}

Future<void> pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: w)));
  await tester.pumpAndSettle();
}

void main() {
  test('every sensor is documented and used in the comprehensive app', () {
    final ids = <String>{};
    for (final s in catalog) {
      expect(ids.add(s.id), isTrue, reason: 'duplicate id ${s.id}');
      expect(s.benefits.length, greaterThanOrEqualTo(2), reason: s.id);
      expect(s.measures, isNotEmpty);
      expect(s.how, isNotEmpty);
      expect(s.usedIn, isNotEmpty, reason: '${s.id} is not used in رفيق');
    }
    final features = catalog.expand((s) => s.usedIn.keys).toSet();
    expect(features, containsAll([Feature.qibla, Feature.tasbeeh, Feature.activity, Feature.environment,
        Feature.level, Feature.magnifier, Feature.lock]));
  });

  testWidgets('four tabs: lab, companion, guide, phone', (tester) async {
    fakeDevice(tester);
    await tester.pumpWidget(const SensorsLabApp());
    await tester.pumpAndSettle();
    for (final label in ['المختبر', 'رفيق', 'الدليل', 'جوالي']) {
      expect(find.text(label), findsOneWidget);
    }
    // Lab: every sensor is a tile; the phone has a light sensor but no barometer.
    expect(find.text('مقياس الإضاءة'), findsOneWidget);
    await tester.tap(find.text('مقياس الإضاءة'));
    await tester.pumpAndSettle();
    expect(find.byType(LightDemo), findsOneWidget);
    expect(find.text('الرسم البياني (آخر 10 ثوانٍ)'), findsOneWidget);
    await tester.tap(find.byType(BackButton)); // pageBack() looks for the English tooltip
    await tester.pumpAndSettle();

    await tester.tap(find.text('الدليل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'بوصلة');
    await tester.pumpAndSettle();
    expect(find.text('متجه الدوران (البوصلة الذكية)'), findsOneWidget);
    expect(find.text('حساس القرب'), findsNothing);

    await tester.tap(find.text('جوالي'));
    await tester.pumpAndSettle();
    expect(find.text('حساسات جوالي'), findsOneWidget);
    await tester.tap(find.text('الخصوصية والأمان'));
    await tester.pumpAndSettle();
    expect(find.text('لا إنترنت إطلاقًا'), findsOneWidget);

    // رفيق is locked until the fingerprint check passes.
    await tester.tap(find.text('رفيق'));
    await tester.pumpAndSettle();
    expect(find.text('«رفيق» مقفل ببصمتك (حساس البصمة).'), findsOneWidget);
  });

  testWidgets('sensor detail opens its demo', (tester) async {
    fakeDevice(tester);
    await pump(tester, SensorDetailScreen(info: sensorById('light')));
    expect(find.text('فوائده'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(FilledButton), 200);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(LightDemo), findsOneWidget);
    expect(find.text('25 lux', findRichText: true), findsOneWidget);
    expect(find.text('إضاءة خافتة'), findsOneWidget);
  });

  testWidgets('a sensor page works again after it was closed', (tester) async {
    fakeDevice(tester);
    await pump(tester, SensorDetailScreen(info: sensorById('light')));
    for (var i = 0; i < 3; i++) {
      await tester.scrollUntilVisible(find.byType(FilledButton), 200);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('25 lux', findRichText: true), findsOneWidget, reason: 'visit ${i + 1}');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('missing sensor shows a message instead of crashing', (tester) async {
    fakeDevice(tester);
    await pump(tester, const ActivityPage());
    expect(find.text('هذا الحساس غير موجود في جوالك.'), findsWidgets);
  });

  testWidgets('permission is explained before it is requested', (tester) async {
    fakeDevice(tester);
    await pump(tester, const QiblaPage());
    expect(find.text('لماذا نحتاج هذا الإذن؟'), findsOneWidget);
    expect(find.text('السماح'), findsOneWidget);
  });

  testWidgets('companion lists every feature and the sensor map', (tester) async {
    fakeDevice(tester);
    await pump(tester, const CompanionApp(requireUnlock: false));
    for (final f in [Feature.lock, Feature.qibla, Feature.tasbeeh, Feature.activity]) {
      expect(find.text(f), findsOneWidget);
    }
    await tester.tap(find.byTooltip('خريطة الحساسات'));
    await tester.pumpAndSettle();
    expect(find.text('خريطة الحساسات في «رفيق»'), findsOneWidget);
  });

  testWidgets('my sensors lists what the phone reports', (tester) async {
    fakeDevice(tester);
    await pump(tester, const MySensorsScreen());
    expect(find.text('مقياس التسارع'), findsOneWidget);
    expect(find.text('حساس الضوء'), findsOneWidget);
  });
}
