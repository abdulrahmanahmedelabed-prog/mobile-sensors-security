// Walks through the main screens on an Android emulator and screenshots them
// for the README and the project site:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart -d <device>
// Screenshots are written to screenshots/ by the driver.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sensors_lab/companion/companion_app.dart';
import 'package:sensors_lab/data/catalog.dart';
import 'package:sensors_lab/main.dart';
import 'package:sensors_lab/screens/devices_screen.dart';
import 'package:sensors_lab/screens/screens.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    var surfaceReady = false;
    Future<void> settle([int ms = 1500]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }

    Future<void> shot(String name) async {
      if (Platform.isAndroid && !surfaceReady) {
        // Android draws to a surface that must become an image first.
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        surfaceReady = true;
      }
      await binding.takeScreenshot(name);
    }

    Future<void> show(Widget page, String name, {int ms = 1500}) async {
      // A new key gives a fresh Navigator, so pages pushed by an earlier
      // step do not stay on top of this one.
      await tester.pumpWidget(SensorsLabApp(key: UniqueKey(), home: page));
      await settle(ms);
      expect(find.byWidget(page), findsOneWidget);
      await shot(name);
    }

    await tester.pumpWidget(const SensorsLabApp());
    await settle();
    await shot('01_lab');

    // The emulator's virtual sensors move a little, so the graph has data.
    await tester.tap(find.text('عدّاد الهزّات'));
    await settle(4000);
    await shot('02_accelerometer');

    await show(const CompanionApp(requireUnlock: false), '03_companion');
    await show(SensorDetailScreen(info: sensorById('pressure')), '04_guide_detail');
    await tester.scrollUntilVisible(find.text('أجهزة تدعم هذا الحساس'), 300, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await settle(800);
    await shot('05_phones_with_sensor');
    await show(const DevicesScreen(), '06_best_phones');
    await show(const CatalogScreen(), '07_guide');
    await show(const MySensorsScreen(), '08_my_sensors');
  });
}
