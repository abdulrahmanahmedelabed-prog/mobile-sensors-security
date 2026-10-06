/// What Android reports about one installed app (see MainActivity.kt).
class AppInfo {
  AppInfo({
    required this.package,
    required this.label,
    this.versionName,
    this.versionCode = 0,
    required this.targetSdk,
    this.minSdk = 0,
    this.system = false,
    this.updatedSystem = false,
    this.debuggable = false,
    this.allowBackup = false,
    this.cleartext = false,
    this.testOnly = false,
    this.installer,
    this.lastUpdate = 0,
    this.apkPaths = const [],
    this.permissions = const [],
    this.components = const [],
    this.certificates = const [],
  });

  factory AppInfo.fromMap(Map<Object?, Object?> m) => AppInfo(
        package: m['package'] as String,
        label: m['label'] as String? ?? m['package'] as String,
        versionName: m['versionName'] as String?,
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        targetSdk: (m['targetSdk'] as num?)?.toInt() ?? 0,
        minSdk: (m['minSdk'] as num?)?.toInt() ?? 0,
        system: m['system'] as bool? ?? false,
        updatedSystem: m['updatedSystem'] as bool? ?? false,
        debuggable: m['debuggable'] as bool? ?? false,
        allowBackup: m['allowBackup'] as bool? ?? false,
        cleartext: m['cleartext'] as bool? ?? false,
        testOnly: m['testOnly'] as bool? ?? false,
        installer: m['installer'] as String?,
        lastUpdate: (m['lastUpdate'] as num?)?.toInt() ?? 0,
        apkPaths: [for (final p in m['apkPaths'] as List<Object?>? ?? const []) p as String],
        permissions: [
          for (final p in m['permissions'] as List<Object?>? ?? const [])
            Permission((p as Map<Object?, Object?>)['name'] as String, p['granted'] as bool? ?? false),
        ],
        components: [
          for (final c in m['components'] as List<Object?>? ?? const []) Component.fromMap(c as Map<Object?, Object?>),
        ],
        certificates: [
          for (final c in m['certificates'] as List<Object?>? ?? const []) Certificate.fromMap(c as Map<Object?, Object?>),
        ],
      );

  final String package;
  final String label;
  final String? versionName;
  final int versionCode;
  final int targetSdk;
  final int minSdk;
  final bool system;
  final bool updatedSystem;
  final bool debuggable;
  final bool allowBackup;
  final bool cleartext;
  final bool testOnly;
  final String? installer;
  final int lastUpdate;
  final List<String> apkPaths;
  final List<Permission> permissions;
  final List<Component> components;
  final List<Certificate> certificates;
}

class Permission {
  const Permission(this.name, this.granted);
  final String name;
  final bool granted;
  String get short => name.split('.').last;
}

class Component {
  const Component({
    required this.kind,
    required this.name,
    this.exported = false,
    this.enabled = true,
    this.permission,
    this.launcher = false,
    this.readPermission,
    this.writePermission,
    this.authority,
  });

  factory Component.fromMap(Map<Object?, Object?> m) => Component(
        kind: m['kind'] as String,
        name: m['name'] as String,
        exported: m['exported'] as bool? ?? false,
        enabled: m['enabled'] as bool? ?? true,
        permission: m['permission'] as String?,
        launcher: m['launcher'] as bool? ?? false,
        readPermission: m['readPermission'] as String?,
        writePermission: m['writePermission'] as String?,
        authority: m['authority'] as String?,
      );

  final String kind;
  final String name;
  final bool exported;
  final bool enabled;
  final String? permission;
  final bool launcher;
  final String? readPermission;
  final String? writePermission;
  final String? authority;
}

class Certificate {
  const Certificate({required this.sha256, this.subject, this.algorithm, this.keyBits, this.notAfter});

  factory Certificate.fromMap(Map<Object?, Object?> m) => Certificate(
        sha256: m['sha256'] as String? ?? '',
        subject: m['subject'] as String?,
        algorithm: m['algorithm'] as String?,
        keyBits: (m['keyBits'] as num?)?.toInt(),
        notAfter: (m['notAfter'] as num?)?.toInt(),
      );

  final String sha256;
  final String? subject;
  final String? algorithm;
  final int? keyBits;
  final int? notAfter;
}

enum Severity {
  info(0, 'معلومة'),
  low(3, 'منخفضة'),
  medium(8, 'متوسطة'),
  high(20, 'عالية'),
  critical(40, 'حرجة');

  const Severity(this.penalty, this.arabic);
  /// Points taken off the app's score of 100.
  final int penalty;
  final String arabic;
}

class Finding {
  const Finding({
    required this.id,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.advice,
    this.details = const [],
  });

  final String id;
  final Severity severity;
  final String title;
  /// What it means, for a non-programmer.
  final String explanation;
  /// What the phone's owner can do about it.
  final String advice;
  final List<String> details;
}

enum Grade { safe, fair, attention, risky }

class AppReport {
  AppReport(this.app, List<Finding> findings)
      : findings = [...findings]..sort((a, b) => b.severity.index.compareTo(a.severity.index));

  final AppInfo app;
  final List<Finding> findings;

  int get score => (100 - findings.fold<int>(0, (s, f) => s + f.severity.penalty)).clamp(0, 100);

  Grade get grade {
    final s = score;
    if (s >= 85) return Grade.safe;
    if (s >= 65) return Grade.fair;
    if (s >= 40) return Grade.attention;
    return Grade.risky;
  }
}

String gradeLabel(Grade g) => switch (g) {
      Grade.safe => 'آمن',
      Grade.fair => 'مقبول',
      Grade.attention => 'يحتاج انتباهًا',
      Grade.risky => 'خطر',
    };
