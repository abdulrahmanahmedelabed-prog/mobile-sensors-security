import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'deep_scan.dart';
import 'model.dart';
import 'rules.dart';

/// Talks to MainActivity.kt.
class Packages {
  static const _channel = MethodChannel('app_scanner/packages');

  Future<List<AppInfo>> list() async {
    final raw = await _channel.invokeListMethod<Object?>('list') ?? const [];
    return [for (final m in raw) AppInfo.fromMap(m as Map<Object?, Object?>)];
  }

  Future<int> sdk() async => await _channel.invokeMethod<int>('sdk') ?? 34;

  Future<Uint8List?> icon(String package) => _channel.invokeMethod<Uint8List>('icon', {'package': package});

  Future<void> openSettings(String package) => _channel.invokeMethod('openSettings', {'package': package});
}

/// Scan results for every visible app. Lives in memory only.
class ScanStore extends ChangeNotifier {
  ScanStore({Packages? packages, this.deepScanner = deepScan}) : packages = packages ?? Packages();

  final Packages packages;
  final Future<List<Finding>> Function(List<String> apkPaths) deepScanner;

  List<AppInfo> _apps = const [];
  final _deep = <String, List<Finding>>{};
  final _deepRunning = <String>{};
  int _deviceSdk = 34;
  bool loading = false;
  String? error;
  bool showSystem = false;
  int deepDone = 0;
  int deepTotal = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _deviceSdk = await packages.sdk();
      _apps = await packages.list();
    } on PlatformException catch (e) {
      error = 'تعذّرت قراءة التطبيقات (${e.code}).';
    } on MissingPluginException {
      error = 'هذا التطبيق يعمل على أندرويد فقط.';
    }
    loading = false;
    notifyListeners();
  }

  int get deviceSdk => _deviceSdk;
  bool deepScanned(String package) => _deep.containsKey(package);
  bool deepRunning(String package) => _deepRunning.contains(package);

  AppReport report(AppInfo app) =>
      AppReport(app, [...checkApp(app, deviceSdk: _deviceSdk), ...?_deep[app.package]]);

  List<AppReport> get reports {
    final list = [
      for (final a in _apps)
        if (showSystem || !(a.system && !a.updatedSystem)) report(a),
    ];
    list.sort((a, b) => a.score != b.score ? a.score.compareTo(b.score) : a.app.label.compareTo(b.app.label));
    return list;
  }

  void setShowSystem(bool v) {
    showSystem = v;
    notifyListeners();
  }

  Future<void> deepScanApp(AppInfo app) async {
    if (_deepRunning.contains(app.package)) return;
    _deepRunning.add(app.package);
    notifyListeners();
    try {
      _deep[app.package] = await deepScanner(app.apkPaths);
    } catch (_) {
      _deep[app.package] = const [];
    } finally {
      _deepRunning.remove(app.package);
      notifyListeners();
    }
  }

  Future<void> deepScanAll() async {
    final todo = [for (final r in reports) if (!_deep.containsKey(r.app.package)) r.app];
    deepTotal = todo.length;
    deepDone = 0;
    notifyListeners();
    for (final app in todo) {
      await deepScanApp(app);
      deepDone++;
      notifyListeners();
    }
    deepTotal = 0;
    notifyListeners();
  }
}
