import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sensors_lab/data/catalog.dart';
import 'package:sensors_lab/data/devices.dart';
import 'package:sensors_lab/platform/device.dart';
import 'package:sensors_lab/screens/devices_screen.dart';
import 'package:sensors_lab/screens/screens.dart';

void main() {
  test('phone list is consistent', () {
    final names = <String>{};
    for (final p in phones) {
      expect(names.add(p.fullName), isTrue, reason: 'duplicate ${p.name}');
      expect(sensorScore(p), inInclusiveRange(0, 100));
    }
    expect(phones.length, greaterThanOrEqualTo(20));
  });

  test('ranking is sorted and filters work', () {
    final r = rankedPhones();
    for (var i = 1; i < r.length; i++) {
      expect(sensorScore(r[i - 1]), greaterThanOrEqualTo(sensorScore(r[i])));
    }
    expect(rankedPhones(brand: 'Apple').every((p) => p.brand == 'Apple'), isTrue);
    expect(rankedPhones(androidOnly: true).any((p) => p.ios), isFalse);
  });

  test('unknown specs earn nothing and are reported as unknown', () {
    const unknown = PhoneSpec(name: 'x', brand: 'b', year: 2025, fingerprint: null, gyro: null, compass: null, proximity: null, barometer: null, face3d: null, uwb: null);
    expect(rawScore(unknown), 0);
    expect(phoneHas(unknown, 'pressure'), isNull);
    expect(phoneHas(unknown, 'accelerometer'), isTrue);
  });

  test('sensor support lookups', () {
    final s4 = phones.firstWhere((p) => p.name == 'Galaxy S4');
    expect(phoneHas(s4, 'humidity'), isTrue);
    final a36 = phones.firstWhere((p) => p.name == 'Galaxy A36');
    expect(phoneHas(a36, 'pressure'), isFalse);
    expect(phoneHas(a36, 'proximity'), isTrue); // virtual still counts as present
    final iphone = phones.firstWhere((p) => p.name == 'iPhone 17');
    expect(phoneHas(iphone, 'biometric'), isTrue); // Face ID without a fingerprint reader
  });

  void fakeDevice(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('sensors_lab/device'), (call) async {
      if (call.method == 'sensors') {
        return [
          for (final t in [SensorType.accelerometer, SensorType.gyroscope, SensorType.magneticField, SensorType.proximity])
            {'type': t, 'name': 's$t', 'vendor': 'v', 'isDefault': true},
        ];
      }
      return null;
    });
  }

  testWidgets('sensor page lists the phones that have it', (tester) async {
    fakeDevice(tester);
    await tester.pumpWidget(MaterialApp(home: SensorDetailScreen(info: sensorById('pressure'))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('أجهزة تدعم هذا الحساس'), 200);
    expect(find.textContaining('Galaxy S26 Ultra'), findsWidgets);
    expect(find.textContaining('Galaxy A36'), findsNothing);
    expect(find.textContaining('OnePlus 13 (غير مؤكد)'), findsOneWidget);
  });

  testWidgets('ranking shows this phone and opens a phone', (tester) async {
    fakeDevice(tester);
    await tester.pumpWidget(MaterialApp(
      home: DevicesScreen(loadThisPhone: () => thisPhone(biometrics: () async => [BiometricType.fingerprint])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('جوالك'), findsOneWidget);
    final top = rankedPhones().first;
    await tester.tap(find.text(top.fullName));
    await tester.pumpAndSettle();
    expect(find.text('درجة الحساسات'), findsOneWidget);
  });
}
