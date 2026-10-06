import 'model.dart';

/// Installers that review apps before publishing them.
const trustedInstallers = {
  'com.android.vending', // Google Play
  'com.google.android.packageinstaller',
  'com.android.packageinstaller',
  'com.huawei.appmarket', // AppGallery
  'com.sec.android.app.samsungapps', // Galaxy Store
  'com.xiaomi.market', 'com.xiaomi.mipicks', // GetApps
  'com.heytap.market', 'com.oppo.market', // OPPO / realme
  'com.bbk.appstore', // vivo
  'com.amazon.venezia', // Amazon Appstore
  'org.fdroid.fdroid', // F-Droid
};

/// Rarely needed permissions that give an app power over the phone.
const powerfulPermissions = {
  'SYSTEM_ALERT_WINDOW': 'الظهور فوق التطبيقات الأخرى (قد يُستخدم لخداعك بشاشات مزيفة)',
  'REQUEST_INSTALL_PACKAGES': 'تثبيت تطبيقات أخرى',
  'MANAGE_EXTERNAL_STORAGE': 'الوصول إلى كل الملفات',
  'QUERY_ALL_PACKAGES': 'معرفة كل التطبيقات المثبتة',
  'READ_SMS': 'قراءة الرسائل (ومنها رموز التحقق)',
  'RECEIVE_SMS': 'استقبال الرسائل',
  'SEND_SMS': 'إرسال رسائل (قد تكون مدفوعة)',
  'READ_CALL_LOG': 'قراءة سجل المكالمات',
  'WRITE_SETTINGS': 'تغيير إعدادات النظام',
  'PACKAGE_USAGE_STATS': 'معرفة التطبيقات التي تستخدمها ومتى',
  'ACCESS_BACKGROUND_LOCATION': 'تتبع موقعك والتطبيق مغلق',
  'REQUEST_DELETE_PACKAGES': 'حذف تطبيقات',
};

/// Services that, once enabled, see or control everything on screen.
const powerfulServices = {
  'android.permission.BIND_ACCESSIBILITY_SERVICE': 'خدمة إمكانية الوصول: ترى كل ما على الشاشة وتستطيع الضغط نيابة عنك',
  'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE': 'قراءة كل الإشعارات (ومنها رموز التحقق والرسائل)',
  'android.permission.BIND_DEVICE_ADMIN': 'مسؤول الجهاز: قفل الجوال أو مسحه',
  'android.permission.BIND_VPN_SERVICE': 'شبكة VPN: يمر عبرها كل اتصال الإنترنت',
};

/// Personal-data permissions: listed for awareness, not counted as flaws.
const personalPermissions = {
  'ACCESS_FINE_LOCATION': 'الموقع الدقيق',
  'ACCESS_COARSE_LOCATION': 'الموقع التقريبي',
  'CAMERA': 'الكاميرا',
  'RECORD_AUDIO': 'الميكروفون',
  'READ_CONTACTS': 'جهات الاتصال',
  'READ_CALENDAR': 'التقويم',
  'BODY_SENSORS': 'حساسات الجسم',
  'ACTIVITY_RECOGNITION': 'النشاط البدني',
  'READ_MEDIA_IMAGES': 'الصور',
  'READ_MEDIA_VIDEO': 'الفيديو',
  'READ_EXTERNAL_STORAGE': 'الملفات',
  'READ_PHONE_STATE': 'حالة الهاتف ورقمه',
  'CALL_PHONE': 'الاتصال',
  'GET_ACCOUNTS': 'الحسابات',
};

String _short(String name) => name.split('.').last;

List<Finding> checkApp(AppInfo app, {required int deviceSdk, DateTime? now}) {
  now ??= DateTime.now();
  final out = <Finding>[];

  if (app.debuggable) {
    out.add(const Finding(
      id: 'AS-DBG',
      severity: Severity.high,
      title: 'نسخة تجريبية قابلة للتصحيح',
      explanation: 'يمكن لأي شخص يصل لجوالك بكابل أن يقرأ بيانات هذا التطبيق ويشغّل كودًا داخله. التطبيقات الرسمية لا تكون هكذا.',
      advice: 'ثبّت النسخة الرسمية من المتجر، أو احذف التطبيق إن لم تعرف مصدره.',
    ));
  }
  if (app.testOnly) {
    out.add(const Finding(
      id: 'AS-TEST',
      severity: Severity.low,
      title: 'نسخة اختبار للمطوّرين',
      explanation: 'هذه النسخة معدّة للاختبار وليست للاستخدام العام.',
      advice: 'استبدلها بالنسخة الرسمية.',
    ));
  }

  if (app.targetSdk > 0 && app.targetSdk < 23) {
    out.add(Finding(
      id: 'AS-TGT',
      severity: Severity.high,
      title: 'مبني لأندرويد قديم جدًا (API ${app.targetSdk})',
      explanation: 'التطبيقات المبنية لما قبل أندرويد 6 تأخذ كل أذوناتها تلقائيًا دون أن تسألك.',
      advice: 'ابحث عن تحديث أو بديل حديث له، وراجع أذوناته من الإعدادات.',
    ));
  } else if (app.targetSdk > 0 && app.targetSdk < 29) {
    out.add(Finding(
      id: 'AS-TGT',
      severity: Severity.medium,
      title: 'مبني لإصدار أندرويد قديم (API ${app.targetSdk})',
      explanation: 'لا يستفيد من حمايات أندرويد الحديثة للخصوصية (مثل عزل الملفات وتقييد الموقع في الخلفية). '
          'متجر Google Play يرفض هذه التطبيقات الآن.',
      advice: 'حدّثه من المتجر؛ وإن لم يُحدَّث منذ سنوات فقد تخلّى عنه مطوّره.',
    ));
  } else if (app.targetSdk > 0 && app.targetSdk < deviceSdk - 3) {
    out.add(Finding(
      id: 'AS-TGT',
      severity: Severity.low,
      title: 'لا يستهدف إصدارات أندرويد الحديثة (API ${app.targetSdk})',
      explanation: 'التطبيق متأخر عن إصدار نظامك (API $deviceSdk) بعدة سنوات.',
      advice: 'تحقق من وجود تحديث.',
    ));
  }

  if (app.cleartext) {
    out.add(const Finding(
      id: 'AS-CLR',
      severity: Severity.medium,
      title: 'يسمح بالاتصال غير المشفّر (HTTP)',
      explanation: 'على شبكات Wi-Fi العامة يمكن لغيرك رؤية ما يرسله هذا التطبيق أو تعديله إن استخدم HTTP.',
      advice: 'تجنّب إدخال كلمات مرور أو بيانات حساسة فيه وأنت على شبكة عامة.',
    ));
  }
  if (app.allowBackup && app.targetSdk > 0 && app.targetSdk < 31) {
    out.add(const Finding(
      id: 'AS-BAK',
      severity: Severity.low,
      title: 'بياناته قابلة للنسخ الاحتياطي عبر الكابل',
      explanation: 'يمكن لمن يصل لجوالك وهو مفتوح أن ينسخ بيانات التطبيق إلى كمبيوتر.',
      advice: 'اقفل جوالك برمز قوي ولا تتركه مفتوحًا مع غيرك.',
    ));
  }

  final installer = app.installer;
  if (!app.system && !app.updatedSystem && (installer == null || !trustedInstallers.contains(installer))) {
    out.add(Finding(
      id: 'AS-SRC',
      severity: Severity.medium,
      title: 'مثبّت من خارج المتاجر الرسمية',
      explanation: 'لم يمر هذا التطبيق بفحص متجر رسمي${installer == null ? '' : ' (مصدر التثبيت: $installer)'}. '
          'أغلب البرمجيات الخبيثة تنتشر هكذا.',
      advice: 'إن لم تكن متأكدًا من مصدره فاحذفه وثبّته من المتجر الرسمي.',
    ));
  }

  for (final c in app.certificates) {
    final subject = c.subject ?? '';
    if (subject.contains('CN=Android Debug')) {
      out.add(const Finding(
        id: 'AS-CERT',
        severity: Severity.high,
        title: 'موقّع بمفتاح المطوّرين التجريبي',
        explanation: 'النسخ الرسمية توقَّع بمفتاح خاص بالشركة. هذا التوقيع يعني نسخة غير رسمية أو معدّلة.',
        advice: 'احذفه وثبّت النسخة الرسمية.',
      ));
    } else if (c.keyBits != null && c.algorithm != null && c.algorithm!.contains('RSA') && c.keyBits! < 2048) {
      out.add(Finding(
        id: 'AS-CERT',
        severity: Severity.low,
        title: 'مفتاح توقيع ضعيف (${c.keyBits} بت)',
        explanation: 'مفاتيح RSA الأقل من 2048 بت لم تعد تعتبر قوية.',
        advice: 'لا يلزمك فعل شيء؛ هذه ملاحظة للمطوّر.',
      ));
    } else if (c.algorithm != null && RegExp(r'^(MD5|SHA1)with', caseSensitive: false).hasMatch(c.algorithm!)) {
      out.add(Finding(
        id: 'AS-CERT',
        severity: Severity.low,
        title: 'شهادة توقيع بخوارزمية قديمة (${c.algorithm})',
        explanation: 'الخوارزميات MD5 و SHA-1 ضعيفة.',
        advice: 'لا يلزمك فعل شيء؛ هذه ملاحظة للمطوّر.',
      ));
    }
  }

  final granted = {for (final p in app.permissions) if (p.granted) _short(p.name)};
  final requested = {for (final p in app.permissions) _short(p.name)};
  final powerful = [
    for (final e in powerfulPermissions.entries)
      if (requested.contains(e.key)) '${e.value}${granted.contains(e.key) ? ' — مسموح' : ''}',
  ];
  final services = {
    for (final c in app.components)
      if (c.kind == 'service' && powerfulServices.containsKey(c.permission)) powerfulServices[c.permission]!,
  }.toList();
  if (powerful.isNotEmpty || services.isNotEmpty) {
    out.add(Finding(
      id: 'AS-PWR',
      severity: Severity.medium,
      title: 'يطلب صلاحيات قوية (${powerful.length + services.length})',
      explanation: 'هذه الصلاحيات تعطي التطبيق تحكمًا واسعًا، وتستغلها التطبيقات الخبيثة كثيرًا. قد تكون مبرّرة (مثل تطبيق رسائل يقرأ الرسائل).',
      advice: 'اسأل نفسك: هل يحتاج هذا التطبيق كل هذا لعمله؟ إن لم يكن، فاسحب الإذن من الإعدادات أو احذفه.',
      details: [...powerful, ...services],
    ));
  }

  final personal = [
    for (final e in personalPermissions.entries)
      if (granted.contains(e.key)) e.value,
  ];
  if (personal.isNotEmpty) {
    out.add(Finding(
      id: 'AS-PRV',
      severity: Severity.info,
      title: 'يصل إلى بياناتك الشخصية (${personal.length})',
      explanation: 'أذونات منحتها لهذا التطبيق.',
      advice: 'اسحب ما لا يحتاجه من «الإعدادات ← التطبيقات ← الأذونات».',
      details: personal,
    ));
  }

  bool open(Component c) => c.exported && c.enabled && !c.launcher;
  final providers = [
    for (final c in app.components)
      if (c.kind == 'provider' && open(c) && c.readPermission == null && c.writePermission == null) c.authority ?? c.name,
  ];
  if (providers.isNotEmpty) {
    out.add(Finding(
      id: 'AS-PROV',
      severity: Severity.high,
      title: 'يشارك بيانات مع أي تطبيق آخر دون إذن (${providers.length})',
      explanation: 'فيه «مزوّد محتوى» مفتوح: أي تطبيق آخر على جوالك يمكنه طلب بياناته دون أن يُسأل.',
      advice: 'قد يكون مقصودًا (مثل مشاركة الملفات)، لكنه خطأ أمني شائع. أبلغ المطوّر إن كان التطبيق يحفظ بيانات حساسة.',
      details: providers,
    ));
  }
  final ipc = [
    for (final c in app.components)
      if ((c.kind == 'service' || c.kind == 'receiver') && open(c) && c.permission == null) '${c.kind}: ${c.name}',
  ];
  if (ipc.isNotEmpty) {
    out.add(Finding(
      id: 'AS-EXP',
      severity: ipc.length > 5 ? Severity.medium : Severity.low,
      title: 'أجزاء يمكن لأي تطبيق تشغيلها (${ipc.length})',
      explanation: 'خدمات أو مستقبلات رسائل مفتوحة لكل التطبيقات دون إذن. إن لم يتحقق المطوّر مما يصلها فقد يستغلها تطبيق خبيث.',
      advice: 'ملاحظة للمطوّر؛ حافظ على تحديث التطبيق.',
      details: ipc,
    ));
  }

  if (app.lastUpdate > 0) {
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(app.lastUpdate));
    if (age.inDays > 730) {
      out.add(Finding(
        id: 'AS-OLD',
        severity: Severity.low,
        title: 'لم يُحدَّث منذ ${age.inDays ~/ 365} سنوات',
        explanation: 'التطبيقات غير المحدَّثة لا تصلها إصلاحات الثغرات.',
        advice: 'حدّثه من المتجر أو ابحث عن بديل.',
      ));
    }
  }
  return out;
}
