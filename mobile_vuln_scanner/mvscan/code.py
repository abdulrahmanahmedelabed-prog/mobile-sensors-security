"""Source and binary-string rules: secrets, insecure network, WebView, crypto,
storage, injection and logging, for Java, Kotlin, Dart, Swift, Objective-C and JS.

A line containing "mvscan:ignore" is skipped, so a reviewed false positive can
be silenced next to the code it concerns.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .models import Finding, Severity, clip, mask_secret

JVM = {".java", ".kt", ".kts"}
DART = {".dart"}
APPLE = {".swift", ".m", ".mm"}
JS = {".js", ".jsx", ".ts", ".tsx", ".mjs"}
CODE = JVM | DART | APPLE | JS
CONFIG = {".xml", ".json", ".properties", ".yaml", ".yml", ".plist", ".gradle", ".env", ".cfg", ".ini", ".txt"}
ALL = CODE | CONFIG

SENSITIVE_WORD = r"(?:password|passwd|pwd|secret|token|api[_-]?key|otp|pin[_-]?code|credit[_-]?card|cvv|ssn)"


@dataclass(frozen=True)
class Rule:
    rule_id: str
    severity: Severity
    title: str
    pattern: re.Pattern
    exts: frozenset
    recommendation: str
    cwe: str = ""
    secret: bool = False      # mask the matched value in reports
    multiline: bool = False   # match across the whole file, not per line


def R(rule_id, severity, title, pattern, exts, recommendation, cwe="", secret=False, multiline=False, flags=0):
    return Rule(rule_id, severity, title, re.compile(pattern, flags), frozenset(exts), recommendation, cwe,
                secret, multiline)


SECRET_RULES = [
    R("MV-SEC-001", Severity.CRITICAL, "مفتاح خاص مكتوب داخل التطبيق",
      r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----", ALL,
      "احذف المفتاح فورًا، ألغِه واستبدله، ولا تضع مفاتيح خاصة داخل التطبيق: أي أحد يستطيع استخراجها.",
      "CWE-321"),
    R("MV-SEC-002", Severity.HIGH, "مفتاح وصول AWS مكتوب في الكود",
      r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b", ALL,
      "ألغِ المفتاح من لوحة AWS وانقل الطلبات إلى خادمك أو استخدم Cognito بصلاحيات محدودة.", "CWE-798", True),
    R("MV-SEC-003", Severity.MEDIUM, "مفتاح Google API مكتوب في التطبيق",
      r"\bAIza[0-9A-Za-z_\-]{35}\b", ALL,
      "قيّد المفتاح في Google Cloud Console باسم الحزمة وبصمة التوقيع وبالخدمات المطلوبة فقط.", "CWE-798", True),
    R("MV-SEC-004", Severity.HIGH, "رمز خدمة سرّي مكتوب في الكود",
      r"\b(?:sk_live_[0-9A-Za-z]{16,}|rk_live_[0-9A-Za-z]{16,}|xox[abprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{36}"
      r"|github_pat_[0-9A-Za-z_]{40,}|glpat-[0-9A-Za-z_\-]{20}|AC[0-9a-f]{32}|SG\.[0-9A-Za-z_\-]{22}\.[0-9A-Za-z_\-]{43})\b",
      ALL, "ألغِ الرمز فورًا واستبدله، وأبقِ الرموز السرية على الخادم فقط.", "CWE-798", True),
    R("MV-SEC-005", Severity.HIGH, "كلمة مرور أو مفتاح سرّي مكتوب في الكود",
      r"(?i)\b[\w.]*" + SENSITIVE_WORD + r"[\w]*\b\s*[:=]+\s*(?:const\s+)?[\"']([^\"'\s$]{6,})[\"']", ALL,
      "لا تكتب أسرارًا في الكود؛ اجلبها من الخادم بعد تسجيل الدخول، أو احفظ ما يخص المستخدم في Keystore/Keychain.",
      "CWE-798", True),
]

NETWORK_RULES = [
    R("MV-NET-001", Severity.MEDIUM, "رابط HTTP/WS غير مشفّر",
      r"[\"'](?:http|ws)://(?!localhost\b|127\.0\.0\.1\b|10\.0\.2\.2\b|\[::1\]|0\.0\.0\.0\b|schemas\.android\.com|"
      r"www\.w3\.org|ns\.adobe\.com|xml\.org|schemas\.xmlsoap\.org|www\.apple\.com/DTDs|purl\.org|"
      r"apache\.org/licenses|java\.sun\.com|xmlpull\.org|example\.(?:com|org))[^\"'\s]+[\"']", CODE,
      "استخدم https:// و wss:// ؛ البيانات عبر HTTP يمكن قراءتها وتعديلها من أي شبكة عامة.", "CWE-319"),
    R("MV-NET-002", Severity.HIGH, "TrustManager يقبل كل الشهادات",
      r"checkServerTrusted\s*\([^)]*\)\s*(?::\s*Unit\s*)?(?:throws\s+[\w.,\s]+)?\{\s*(?://[^\n]*\s*)*\}", JVM,
      "لا تتجاوز التحقق من الشهادات أبدًا؛ استخدم TrustManager الافتراضي، ولشهادة خاصة استخدم network_security_config.",
      "CWE-295", multiline=True),
    R("MV-NET-003", Severity.HIGH, "HostnameVerifier يقبل أي اسم خادم",
      r"ALLOW_ALL_HOSTNAME_VERIFIER|NoopHostnameVerifier|HostnameVerifier\s*\{\s*_\s*,\s*_\s*->\s*true\s*\}"
      r"|boolean\s+verify\s*\([^)]*\)\s*\{\s*return\s+true\s*;", JVM,
      "احذف الـ HostnameVerifier المخصّص واعتمد على التحقق الافتراضي.", "CWE-297", multiline=True),
    R("MV-NET-004", Severity.HIGH, "قبول أي شهادة TLS في Dart (badCertificateCallback)",
      r"badCertificateCallback\s*=\s*(?:\([^)]*\)\s*=>\s*true|\([^)]*\)\s*\{\s*return\s+true\s*;)", DART,
      "احذف badCertificateCallback، أو قارن بصمة شهادة محددة بدل إرجاع true.", "CWE-295", multiline=True),
    R("MV-NET-005", Severity.HIGH, "WebView يتجاهل أخطاء SSL",
      r"onReceivedSslError[\s\S]{0,300}?\.proceed\s*\(\s*\)", JVM,
      "استدعِ handler.cancel() بدل proceed().", "CWE-295", multiline=True),
    R("MV-NET-006", Severity.HIGH, "تعطيل التحقق من شهادات TLS في JavaScript",
      r"rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED", JS,
      "أبقِ التحقق من الشهادات مفعّلًا.", "CWE-295"),
    R("MV-NET-007", Severity.HIGH, "تجاوز التحقق من شهادة الخادم في iOS",
      r"\.useCredential\s*,\s*URLCredential\s*\(\s*trust|allowInvalidCertificates\s*=\s*(?:YES|true)"
      r"|validatesDomainName\s*=\s*(?:NO|false)", APPLE,
      "لا تقبل الشهادات دون تقييم SecTrustEvaluateWithError.", "CWE-295"),
]

WEB_RULES = [
    R("MV-WEB-001", Severity.LOW, "JavaScript مفعّل في WebView",
      r"setJavaScriptEnabled\s*\(\s*true\s*\)|javaScriptEnabled\s*=\s*true|JavaScriptMode\.unrestricted", JVM | DART,
      "فعّله فقط لمحتوى موثوق عبر HTTPS، ولا تحمّل روابط يتحكم بها المستخدم.", "CWE-749"),
    R("MV-WEB-002", Severity.MEDIUM, "واجهة JavaScript مكشوفة لصفحات الويب (addJavascriptInterface)",
      r"addJavascriptInterface\s*\(", JVM,
      "اكشف أقل عدد من الدوال، وحمّل محتوى موثوقًا فقط؛ أي صفحة محمّلة تستطيع استدعاءها.", "CWE-749"),
    R("MV-WEB-003", Severity.HIGH, "WebView يسمح بالوصول إلى الملفات من روابط file://",
      r"setAllowUniversalAccessFromFileURLs\s*\(\s*true|setAllowFileAccessFromFileURLs\s*\(\s*true"
      r"|allowUniversalAccessFromFileURLs\s*=\s*true|allowFileAccessFromFileURLs\s*=\s*true", JVM,
      "اتركها false (الافتراضي)، واستخدم WebViewAssetLoader لتحميل الملفات المحلية.", "CWE-200"),
    R("MV-WEB-004", Severity.MEDIUM, "تصحيح WebView مفعّل",
      r"setWebContentsDebuggingEnabled\s*\(\s*true\s*\)", JVM,
      "فعّله في نسخ التصحيح فقط (BuildConfig.DEBUG).", "CWE-489"),
    R("MV-WEB-005", Severity.MEDIUM, "UIWebView قديم وغير آمن",
      r"\bUIWebView\b", APPLE, "استخدم WKWebView.", "CWE-477"),
    R("MV-WEB-006", Severity.MEDIUM, "تنفيذ نص كبرنامج (eval)",
      r"(?<![\w.])eval\s*\(|new\s+Function\s*\(", JS,
      "لا تنفّذ نصوصًا ديناميكية؛ استخدم JSON.parse للبيانات.", "CWE-95"),
]

CRYPTO_RULES = [
    R("MV-CRY-001", Severity.MEDIUM, "خوارزمية تجزئة ضعيفة (MD5/SHA-1)",
      r"MessageDigest\.getInstance\s*\(\s*\"(?:MD5|SHA-?1|MD4|MD2)\"|\b(?:md5|sha1)\.convert\s*\(|\bCC_(?:MD5|SHA1)\s*\(|Insecure\.(?:MD5|SHA1)",
      JVM | DART | APPLE, "استخدم SHA-256 أو أقوى، ولكلمات المرور استخدم PBKDF2/Argon2/bcrypt.", "CWE-328"),
    R("MV-CRY-002", Severity.HIGH, "تشفير ضعيف (DES/RC4/ECB)",
      r"Cipher\.getInstance\s*\(\s*\"(?:DES|DESede|RC4|RC2|Blowfish|AES)(?:/ECB[^\"]*)?\"|AES/ECB|kCCAlgorithmDES|kCCOptionECBMode"
      r"|AESMode\.ecb", JVM | DART | APPLE,
      "استخدم AES/GCM/NoPadding مع IV عشوائي لكل رسالة، ومفاتيح من Android Keystore/iOS Keychain.", "CWE-327"),
    R("MV-CRY-003", Severity.HIGH, "مفتاح تشفير أو IV ثابت في الكود",
      r"(?:SecretKeySpec|IvParameterSpec)\s*\(\s*\"[^\"]*\"|(?:SecretKeySpec|IvParameterSpec)\s*\(\s*\"[^\"]+\"\s*\.(?:toByteArray|getBytes)"
      r"|Key\.fromUtf8\s*\(\s*['\"]|IV\.fromUtf8\s*\(\s*['\"]", JVM | DART,
      "ولّد المفاتيح داخل Keystore/Keychain وIV عشوائيًا لكل عملية تشفير.", "CWE-321"),
    R("MV-CRY-004", Severity.MEDIUM, "SecureRandom ببذرة ثابتة (قابل للتوقع)",
      r"SecureRandom\s*\(\s*[\w\"]+.*\)|\.setSeed\s*\(", JVM,
      "استخدم new SecureRandom() دون بذرة.", "CWE-336"),
    R("MV-CRY-005", Severity.LOW, "مولّد أرقام عشوائية غير آمن لقيمة أمنية",
      r"(?i)(?:\bRandom\s*\(\s*\)|Math\.random\s*\(\s*\)).*(?:token|otp|salt|nonce|password|secret|session)"
      r"|(?:token|otp|salt|nonce|password|secret|session)\w*\s*=.*(?:\bRandom\s*\(\s*\)|Math\.random\s*\(\s*\))",
      JVM | DART | JS, "استخدم Random.secure() في Dart أو SecureRandom في Java/Kotlin أو crypto.getRandomValues.",
      "CWE-338"),
]

STORAGE_RULES = [
    R("MV-STO-001", Severity.HIGH, "ملف قابل للقراءة/الكتابة من كل التطبيقات",
      r"MODE_WORLD_(?:READABLE|WRITEABLE)|setReadable\s*\(\s*true\s*,\s*false\s*\)|setWritable\s*\(\s*true\s*,\s*false\s*\)",
      JVM, "استخدم MODE_PRIVATE وتخزين التطبيق الداخلي.", "CWE-732"),
    R("MV-STO-002", Severity.LOW, "حفظ في التخزين الخارجي المشترك",
      r"getExternalStorageDirectory|getExternalStoragePublicDirectory|WRITE_EXTERNAL_STORAGE", JVM,
      "التخزين الخارجي مقروء لتطبيقات أخرى؛ احفظ البيانات الخاصة في filesDir.", "CWE-922"),
    R("MV-STO-003", Severity.MEDIUM, "حفظ بيانات حساسة دون تشفير",
      r"(?i)(?:putString|setString|edit\(\)\.put\w*|UserDefaults[\w.]*\.set|setValue|AsyncStorage\.setItem|localStorage\.setItem)"
      r"\s*\(.{0,40}[\"']\w*" + SENSITIVE_WORD + r"\w*[\"']", CODE,
      "استخدم EncryptedSharedPreferences/Android Keystore أو iOS Keychain أو flutter_secure_storage.", "CWE-312"),
    R("MV-STO-004", Severity.LOW, "نسخ بيانات حساسة إلى الحافظة",
      r"(?i)(?:setPrimaryClip|Clipboard\.setData|UIPasteboard\.general\.string\s*=).{0,80}" + SENSITIVE_WORD, CODE,
      "الحافظة مقروءة لتطبيقات أخرى؛ لا تنسخ إليها الأسرار، أو علّمها حساسة (EXTRA_IS_SENSITIVE).", "CWE-200"),
]

INJECTION_RULES = [
    R("MV-INJ-001", Severity.HIGH, "استعلام SQL مبني بدمج نصوص (حقن SQL)",
      r"(?:rawQuery|execSQL|rawInsert|rawUpdate|rawDelete|compileStatement|executeSql)\s*\(\s*"
      r"(?:\"[^\"]*\"\s*\+|'[^']*'\s*\+|[\"'][^\"']*\$\{?[A-Za-z_]|String\.format\s*\(|f[\"'])", CODE,
      "استخدم الاستعلامات ذات المعاملات (? مع selectionArgs/arguments) بدل دمج المُدخلات في نص الاستعلام.",
      "CWE-89"),
    R("MV-INJ-002", Severity.MEDIUM, "تشغيل أوامر نظام من التطبيق",
      r"Runtime\.getRuntime\(\)\.exec\s*\(|\bProcessBuilder\s*\(|\bProcess\.(?:run|start)\s*\(", JVM | DART,
      "تجنّب تنفيذ الأوامر، وإن لزم فلا تمرر مُدخلات المستخدم ولا تستخدم sh -c.", "CWE-78"),
    R("MV-INJ-003", Severity.MEDIUM, "تحميل كود ديناميكي",
      r"\b(?:DexClassLoader|PathClassLoader|InMemoryDexClassLoader|BaseDexClassLoader)\s*\(", JVM,
      "لا تحمّل كودًا من مصادر خارجية؛ إن كان ضروريًا فتحقق من توقيعه واحفظه في التخزين الداخلي.", "CWE-94"),
    R("MV-INJ-004", Severity.LOW, "مسار ملف من مُدخل خارجي (احتمال تجاوز المسار)",
      r"File\s*\(.{0,60}(?:getLastPathSegment|getQueryParameter|getStringExtra)\s*\(", JVM,
      "طبّع المسار (canonicalPath) وتحقق أنه داخل المجلد المسموح.", "CWE-22"),
]

IPC_RULES = [
    R("MV-IPC-001", Severity.MEDIUM, "PendingIntent دون FLAG_IMMUTABLE",
      r"PendingIntent\.get(?:Activity|Service|Broadcast|ForegroundService)\s*\((?![^;]*(?:FLAG_IMMUTABLE|FLAG_MUTABLE))[^;]*;",
      JVM, "أضف PendingIntent.FLAG_IMMUTABLE حتى لا يعدّل تطبيق آخر الـ Intent.", "CWE-927", multiline=True),
    R("MV-IPC-002", Severity.LOW, "بث مثبّت (sticky broadcast) مقروء لأي تطبيق",
      r"sendStickyBroadcast\s*\(", JVM, "استخدم بثًا محليًا أو صريحًا محميًا بإذن.", "CWE-927"),
    R("MV-IPC-003", Severity.LOW, "تسجيل مستقبِل بث دون RECEIVER_NOT_EXPORTED",
      r"registerReceiver\s*\((?![^;]*(?:RECEIVER_NOT_EXPORTED|RECEIVER_EXPORTED))[^;]*;", JVM,
      "مرّر ContextCompat.RECEIVER_NOT_EXPORTED ما لم يكن البث من تطبيقات أخرى مقصودًا.", "CWE-925",
      multiline=True),
]

LOG_RULES = [
    R("MV-LOG-001", Severity.MEDIUM, "طباعة بيانات حساسة في السجل",
      r"(?i)(?:\bLog\.[vdiwe]|\bprint|\bdebugPrint|\bprintln|\bNSLog|console\.(?:log|debug|info)|\blog\.(?:d|i|w|e))\s*\(.*"
      + SENSITIVE_WORD, CODE,
      "لا تطبع الأسرار في السجل؛ السجلات تُقرأ عبر adb وتُرسل أحيانًا مع تقارير الأعطال.", "CWE-532"),
]

ALL_RULES = SECRET_RULES + NETWORK_RULES + WEB_RULES + CRYPTO_RULES + STORAGE_RULES + INJECTION_RULES + IPC_RULES + LOG_RULES
# Rules worth running over strings recovered from compiled code (dex, .so, js bundles).
BINARY_RULES = SECRET_RULES

_PLACEHOLDER = re.compile(r"(?i)^(?:x+|\*+|\.+|your[_-]?\w*|changeme|password|secret|token|example\w*|test\w*|dummy\w*|"
                          r"sample\w*|placeholder|null|none|todo|<[^>]*>|\$\{?\w+\}?|%s|\{\w*\})$")


def _comment_only(line: str) -> bool:
    s = line.lstrip()
    return s.startswith(("//", "*", "/*", "#", "<!--"))


def _evidence(rule: Rule, match: re.Match, line: str) -> str:
    if rule.secret:
        value = match.group(1) if match.lastindex else match.group(0)
        return clip(line.strip().replace(value, mask_secret(value)))
    return clip(line.strip())


def scan_text(text: str, location: str, ext: str) -> list[Finding]:
    out: list[Finding] = []
    lines = text.splitlines()
    rules = [r for r in ALL_RULES if ext in r.exts]
    for rule in rules:
        if rule.multiline:
            for m in rule.pattern.finditer(text):
                lineno = text.count("\n", 0, m.start()) + 1
                line = lines[lineno - 1] if lineno <= len(lines) else ""
                if "mvscan:ignore" in line or _comment_only(line):
                    continue
                out.append(Finding(rule.rule_id, rule.severity, rule.title, location, lineno,
                                   clip(m.group(0)), rule.recommendation, rule.cwe))
            continue
        for lineno, line in enumerate(lines, 1):
            if len(line) > 4000 or "mvscan:ignore" in line:
                continue
            # Secrets matter even in comments; code patterns in comments do not.
            if not rule.secret and _comment_only(line):
                continue
            m = rule.pattern.search(line)
            if not m:
                continue
            if rule.rule_id == "MV-SEC-005" and _PLACEHOLDER.match(m.group(1)):
                continue
            out.append(Finding(rule.rule_id, rule.severity, rule.title, location, lineno,
                               _evidence(rule, m, line), rule.recommendation, rule.cwe))
    return out


_PRINTABLE = re.compile(rb"[\x20-\x7e]{8,}")
_HTTP_IN_BINARY = re.compile(r"^http://(?!localhost|127\.0\.0\.1|10\.0\.2\.2|schemas\.|www\.w3\.org|ns\.adobe|"
                             r"xml\.org|purl\.org|www\.apache\.org|java\.sun|xmlpull|www\.example|example\.)[\w.-]+\.\w+")


def printable_strings(data: bytes, limit: int = 400_000) -> list[str]:
    out = []
    for m in _PRINTABLE.finditer(data):
        out.append(m.group(0).decode("ascii"))
        if len(out) >= limit:
            break
    return out


def scan_strings(strings: list[str], location: str) -> list[Finding]:
    """Rules for compiled code, where only strings (no lines) are available."""
    out: list[Finding] = []
    for s in strings:
        if len(s) > 4000:
            continue
        for rule in BINARY_RULES:
            if rule.rule_id == "MV-SEC-005":
                continue  # assignments do not survive compilation
            m = rule.pattern.search(s)
            if m:
                out.append(Finding(rule.rule_id, rule.severity, rule.title, location,
                                   evidence=mask_secret(m.group(0)), recommendation=rule.recommendation,
                                   cwe=rule.cwe))
    urls = sorted({s.split()[0] for s in strings if _HTTP_IN_BINARY.match(s)})
    if urls:
        sample = ", ".join(urls[:5]) + (f" (+{len(urls) - 5})" if len(urls) > 5 else "")
        out.append(Finding("MV-NET-001", Severity.LOW, f"روابط HTTP غير مشفّرة في الكود المترجم ({len(urls)})",
                           location, evidence=clip(sample, 240),
                           recommendation="تحقق أن التطبيق لا يرسل بيانات عبر هذه الروابط؛ استخدم HTTPS.",
                           cwe="CWE-319"))
    return out
