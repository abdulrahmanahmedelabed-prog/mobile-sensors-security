import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'screens/screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Compass, Qibla and level readings assume portrait.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SensorsLabApp());
}

class SensorsLabApp extends StatelessWidget {
  const SensorsLabApp({super.key, this.home = const HomeScreen()});
  /// The first screen; screenshots and tests open a specific one.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00796B);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'حساسات الجوال',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: mode,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        home: home,
      ),
    );
  }
}
