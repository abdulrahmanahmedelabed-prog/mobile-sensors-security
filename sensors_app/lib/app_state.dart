import 'package:flutter/material.dart';

/// App-wide theme, switched by the light sensor when auto night mode is on.
/// Kept in memory only: the app stores nothing on the phone.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final autoNightMode = ValueNotifier<bool>(false);
