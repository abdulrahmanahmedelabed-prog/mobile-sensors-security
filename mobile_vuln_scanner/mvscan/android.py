"""Android configuration rules: AndroidManifest.xml, network security config, Gradle."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET

from .axml import ANDROID_NS
from .models import Finding, Severity, clip

A = f"{{{ANDROID_NS}}}"
TOOLS_NODE = "{http://schemas.android.com/tools}node"

COMPONENTS = ("activity", "activity-alias", "service", "receiver", "provider")

# Permissions that reach the user's private data or control of the phone.
SENSITIVE_PERMISSIONS = {
    "READ_SMS", "SEND_SMS", "RECEIVE_SMS", "READ_CALL_LOG", "WRITE_CALL_LOG",
    "PROCESS_OUTGOING_CALLS", "READ_CONTACTS", "WRITE_CONTACTS", "READ_PHONE_STATE",
    "READ_PHONE_NUMBERS", "CALL_PHONE", "ACCESS_FINE_LOCATION",
    "ACCESS_BACKGROUND_LOCATION", "RECORD_AUDIO", "CAMERA", "BODY_SENSORS",
    "BODY_SENSORS_BACKGROUND", "ACTIVITY_RECOGNITION", "READ_EXTERNAL_STORAGE",
    "WRITE_EXTERNAL_STORAGE", "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO",
    "READ_MEDIA_AUDIO", "GET_ACCOUNTS", "READ_CALENDAR", "WRITE_CALENDAR",
}
# Rarely needed and abused by malware: worth a human double-check.
HIGH_RISK_PERMISSIONS = {
    "SYSTEM_ALERT_WINDOW", "REQUEST_INSTALL_PACKAGES", "MANAGE_EXTERNAL_STORAGE",
    "QUERY_ALL_PACKAGES", "BIND_ACCESSIBILITY_SERVICE", "BIND_DEVICE_ADMIN",
    "WRITE_SETTINGS", "READ_LOGS", "INSTALL_PACKAGES", "PACKAGE_USAGE_STATS",
    "BIND_NOTIFICATION_LISTENER_SERVICE", "REQUEST_DELETE_PACKAGES",
}


def _attr(elem: ET.Element, name: str) -> str | None:
    return elem.get(A + name)


def _is_true(value: str | None) -> bool:
    return value is not None and value.strip().lower() in ("true", "1", "0xffffffff", "-1")


def _int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def _short_perm(name: str) -> str:
    return name.rsplit(".", 1)[-1]


def check_manifest(root: ET.Element, location: str, target_sdk: int | None = None) -> list[Finding]:
    out: list[Finding] = []
    if root.tag != "manifest":
        return out
    app = root.find("application")
    uses_sdk = root.find("uses-sdk")
    if uses_sdk is not None:
        target_sdk = _int(_attr(uses_sdk, "targetSdkVersion")) or target_sdk
        min_sdk = _int(_attr(uses_sdk, "minSdkVersion"))
        if min_sdk is not None and min_sdk < 23:
            out.append(Finding(
                "MV-MAN-006", Severity.LOW, "يدعم إصدارات أندرويد قديمة جدًا (minSdk أقل من 23)",
                location, evidence=f"minSdkVersion={min_sdk}",
                recommendation="ارفع minSdkVersion إلى 23 أو أكثر: الإصدارات الأقدم بلا أذونات وقت التشغيل ولا تصلها تحديثات أمنية.",
                cwe="CWE-1104"))

    for perm in root.findall("uses-permission") + root.findall("uses-permission-sdk-23"):
        if perm.get(TOOLS_NODE) in ("remove", "removeAll"):
            continue  # stripped from the merged manifest
        name = _attr(perm, "name") or ""
        short = _short_perm(name)
        if short in HIGH_RISK_PERMISSIONS:
            out.append(Finding(
                "MV-MAN-008", Severity.MEDIUM, f"إذن عالي الخطورة: {short}", location, evidence=name,
                recommendation="تحقق أن التطبيق يحتاج هذا الإذن فعلًا؛ يستغله البرمجيات الخبيثة كثيرًا وترفضه متاجر التطبيقات دون مبرر.",
                cwe="CWE-250"))
        elif short in SENSITIVE_PERMISSIONS:
            out.append(Finding(
                "MV-MAN-009", Severity.INFO, f"إذن يصل إلى بيانات خاصة: {short}", location, evidence=name,
                recommendation="اطلبه وقت الحاجة فقط مع شرح للمستخدم، ولا ترسل بياناته خارج الجهاز دون موافقة."))

    if app is None:
        return out

    if _is_true(_attr(app, "debuggable")):
        out.append(Finding(
            "MV-MAN-001", Severity.HIGH, "التطبيق قابل للتصحيح (debuggable)", location,
            evidence='android:debuggable="true"',
            recommendation="احذف android:debuggable من الـ manifest ودع نظام البناء يضبطه false في نسخة الإصدار؛ وإلا يمكن لأي شخص معه الجهاز قراءة بيانات التطبيق وتشغيل كود داخله.",
            cwe="CWE-489"))
    if _is_true(_attr(app, "testOnly")):
        out.append(Finding(
            "MV-MAN-007", Severity.LOW, "نسخة اختبار (testOnly)", location,
            evidence='android:testOnly="true"', recommendation="لا توزّع نسخ testOnly للمستخدمين.",
            cwe="CWE-489"))

    backup = _attr(app, "allowBackup")
    if backup is None:
        out.append(Finding(
            "MV-MAN-002", Severity.LOW, "النسخ الاحتياطي لبيانات التطبيق مفعّل افتراضيًا", location,
            evidence="android:allowBackup غير محدد (القيمة الافتراضية true)",
            recommendation='اضبط android:allowBackup="false" أو حدّد ما يُنسخ عبر dataExtractionRules حتى لا تُستخرج البيانات الحساسة عبر adb backup أو السحابة.',
            cwe="CWE-530"))
    elif _is_true(backup):
        out.append(Finding(
            "MV-MAN-002", Severity.MEDIUM, "النسخ الاحتياطي لبيانات التطبيق مفعّل", location,
            evidence='android:allowBackup="true"',
            recommendation='اضبط android:allowBackup="false" أو استبعد الملفات الحساسة عبر dataExtractionRules.',
            cwe="CWE-530"))

    cleartext = _attr(app, "usesCleartextTraffic")
    if _is_true(cleartext):
        out.append(Finding(
            "MV-MAN-003", Severity.MEDIUM, "يسمح باتصال HTTP غير مشفّر", location,
            evidence='android:usesCleartextTraffic="true"',
            recommendation="استخدم HTTPS فقط، وإن احتجت HTTP لخادم محلي فاسمح به لذلك النطاق وحده عبر network_security_config.",
            cwe="CWE-319"))
    elif cleartext is None and target_sdk is not None and target_sdk < 28:
        out.append(Finding(
            "MV-MAN-003", Severity.LOW, "HTTP غير المشفّر مسموح افتراضيًا (targetSdk أقل من 28)", location,
            evidence=f"targetSdkVersion={target_sdk}",
            recommendation='اضبط android:usesCleartextTraffic="false" أو ارفع targetSdkVersion.',
            cwe="CWE-319"))

    for kind in COMPONENTS:
        for comp in app.findall(kind):
            out.extend(_check_component(kind, comp, location, target_sdk))
    return out


def _check_component(kind: str, comp: ET.Element, location: str, target_sdk: int | None) -> list[Finding]:
    out: list[Finding] = []
    name = _attr(comp, "name") or "?"
    filters = comp.findall("intent-filter")
    exported_attr = _attr(comp, "exported")
    if exported_attr is None:
        # Before Android 12 a component with an intent-filter was exported implicitly.
        exported = bool(filters) and (target_sdk is None or target_sdk < 31)
        if kind == "provider" and exported_attr is None and target_sdk is not None and target_sdk < 17:
            exported = True
    else:
        exported = _is_true(exported_attr)
    if _attr(comp, "enabled") == "false":
        return out

    is_launcher = any(
        f.find(f"action[@{A}name='android.intent.action.MAIN']") is not None
        and f.find(f"category[@{A}name='android.intent.category.LAUNCHER']") is not None
        for f in filters
    )

    for f in filters:
        browsable = f.find(f"category[@{A}name='android.intent.category.BROWSABLE']") is not None
        if not browsable:
            continue
        schemes = {_attr(d, "scheme") for d in f.findall("data")} - {None}
        custom = sorted(s for s in schemes if s not in ("http", "https"))
        if custom:
            out.append(Finding(
                "MV-MAN-011", Severity.LOW, f"رابط عميق بمخطط مخصّص في {name}", location,
                evidence="scheme=" + ",".join(custom),
                recommendation="أي تطبيق آخر يمكنه تسجيل المخطط نفسه واعتراض الروابط؛ استخدم App Links (https مع autoVerify) وتحقق من كل مُدخلات الرابط.",
                cwe="CWE-939"))
        elif schemes and not _is_true(_attr(f, "autoVerify")):
            out.append(Finding(
                "MV-MAN-011", Severity.LOW, f"رابط https غير موثّق (autoVerify) في {name}", location,
                evidence="scheme=" + ",".join(sorted(schemes)),
                recommendation='أضف android:autoVerify="true" وملف assetlinks.json حتى لا تعترض تطبيقات أخرى روابطك.',
                cwe="CWE-939"))

    if not exported or is_launcher:
        return out

    if kind == "provider":
        guarded = any(_attr(comp, p) for p in ("permission", "readPermission", "writePermission"))
        if not guarded:
            out.append(Finding(
                "MV-MAN-005", Severity.HIGH, f"مزوّد محتوى مكشوف بلا إذن: {name}", location,
                evidence=f"authorities={_attr(comp, 'authorities') or '?'}",
                recommendation='اجعله android:exported="false"، أو احمِه بإذن protectionLevel="signature".',
                cwe="CWE-926"))
    elif not _attr(comp, "permission"):
        sev = Severity.MEDIUM if kind in ("service", "receiver") else Severity.LOW
        out.append(Finding(
            "MV-MAN-004", sev, f"مكوّن مكشوف لتطبيقات أخرى بلا إذن ({kind}): {name}", location,
            evidence="exported" + ("" if exported_attr else " (ضمنيًا بسبب intent-filter)"),
            recommendation='اضبط android:exported="false" إن لم يكن مطلوبًا من خارج التطبيق، أو احمِه بـ android:permission، وتحقق من كل بيانات الـ Intent الواردة.',
            cwe="CWE-926"))
    return out


def check_network_security_config(root: ET.Element, location: str) -> list[Finding]:
    out: list[Finding] = []
    if root.tag != "network-security-config":
        return out
    for tag in ("base-config", "domain-config"):
        for cfg in root.iter(tag):
            if _is_true(cfg.get("cleartextTrafficPermitted")):
                domains = [d.text or "" for d in cfg.findall("domain")]
                local = domains and all(
                    re.fullmatch(r"(localhost|127\.0\.0\.1|10\.0\.2\.2|\[::1\])", d.strip()) for d in domains)
                out.append(Finding(
                    "MV-NSC-001", Severity.LOW if local else Severity.MEDIUM,
                    "إعداد الشبكة يسمح بـ HTTP غير مشفّر", location,
                    evidence=f"<{tag} cleartextTrafficPermitted=\"true\"> " + ",".join(domains),
                    recommendation="اقصر HTTP على نطاقات التطوير المحلية فقط، واستخدم HTTPS لكل ما سواها.",
                    cwe="CWE-319"))
    for cfg in list(root.iter("base-config")) + list(root.iter("domain-config")):
        for cert in cfg.iter("certificates"):
            if cert.get("src") == "user":
                out.append(Finding(
                    "MV-NSC-002", Severity.MEDIUM, "يثق بشهادات يثبّتها المستخدم", location,
                    evidence='<certificates src="user"/>',
                    recommendation="انقلها إلى <debug-overrides> فقط؛ في الإصدار تسمح بالتنصّت على الاتصال (MITM).",
                    cwe="CWE-295"))
    return out


GRADLE_RULES = [
    (re.compile(r"\bdebuggable\s*(=)?\s*true"), "MV-GRD-001", Severity.HIGH,
     "تفعيل debuggable في إعدادات البناء",
     "لا تفعّل debuggable في buildType الإصدار.", "CWE-489"),
    (re.compile(r"signingConfig\s*(=)?\s*signingConfigs\.(getByName\(\s*\"debug\"\s*\)|debug)"), "MV-GRD-002",
     Severity.MEDIUM, "نسخة الإصدار موقّعة بمفتاح التصحيح (debug)",
     "أنشئ مفتاح توقيع خاصًا بالإصدار واحفظه خارج المستودع (متغيرات بيئة/أسرار CI)؛ مفتاح debug معروف ويمكن لأي أحد توقيع تحديث مزيّف به.",
     "CWE-321"),
    (re.compile(r"\bminSdk(Version)?\s*(=)?\s*(1\d|2[0-2])\b"), "MV-MAN-006", Severity.LOW,
     "يدعم إصدارات أندرويد قديمة جدًا (minSdk أقل من 23)",
     "ارفع minSdk إلى 23 أو أكثر.", "CWE-1104"),
    (re.compile(r"\b(storePassword|keyPassword)\s*(=)?\s*[\"'][^\"']+[\"']"), "MV-GRD-003", Severity.HIGH,
     "كلمة مرور مفتاح التوقيع مكتوبة في ملف البناء",
     "اقرأ كلمات المرور من متغيرات البيئة أو key.properties مستبعد من git.", "CWE-798"),
]


def check_gradle(text: str, location: str) -> list[Finding]:
    out = []
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or "mvscan:ignore" in line:
            continue
        for rx, rid, sev, title, rec, cwe in GRADLE_RULES:
            if rx.search(line):
                ev = stripped if rid != "MV-GRD-003" else rx.search(line).group(1) + " = ****"
                out.append(Finding(rid, sev, title, location, lineno, clip(ev), rec, cwe))
    return out
