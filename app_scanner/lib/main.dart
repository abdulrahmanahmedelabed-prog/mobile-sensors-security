import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens.dart';
import 'store.dart';

void main() => runApp(AppScannerApp(store: ScanStore()));

class AppScannerApp extends StatelessWidget {
  const AppScannerApp({super.key, required this.store});
  final ScanStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF283593);
    return MaterialApp(
      title: 'فاحص التطبيقات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomeScreen(store: store),
    );
  }
}
