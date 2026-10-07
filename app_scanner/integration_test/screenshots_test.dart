// Scans the emulator's apps for real and screenshots the result:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart -d <device>
import 'dart:io';

import 'package:app_scanner/main.dart';
import 'package:app_scanner/model.dart';
import 'package:app_scanner/screens.dart';
import 'package:app_scanner/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        surfaceReady = true;
      }
      await binding.takeScreenshot(name);
    }

    final store = ScanStore();
    await tester.pumpWidget(AppScannerApp(store: store));
    await settle(4000);
    // An emulator has few apps of its own, so include the system ones.
    store.setShowSystem(true);
    await settle();
    expect(store.reports, isNotEmpty, reason: 'the emulator should have launchable apps');
    await shot('01_apps');

    // The riskiest app first.
    final AppReport worst = store.reports.first;
    await tester.tap(find.text(worst.app.label).first);
    await settle();
    final scan = find.text('فحص الكود');
    if (scan.evaluate().isNotEmpty) {
      await tester.tap(scan);
      await settle(8000);
    }
    await shot('02_app_detail');
    final cards = find.byType(FindingCard);
    if (cards.evaluate().isNotEmpty) {
      await tester.tap(cards.first);
      await settle();
      await shot('03_finding');
    }
    tester.state<NavigatorState>(find.byType(Navigator)).popUntil((r) => r.isFirst);
    await settle();
    await tester.tap(find.byTooltip('عن الفحص'));
    await settle();
    await shot('04_about');
  });
}
