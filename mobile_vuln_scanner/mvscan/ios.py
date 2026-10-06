"""iOS rules for Info.plist (App Transport Security, file sharing, URL schemes)."""

from __future__ import annotations

from .models import Finding, Severity


def check_info_plist(plist: dict, location: str) -> list[Finding]:
    out: list[Finding] = []
    if not isinstance(plist, dict):
        return out
    ats = plist.get("NSAppTransportSecurity")
    if isinstance(ats, dict):
        if ats.get("NSAllowsArbitraryLoads") is True:
            out.append(Finding(
                "MV-IOS-001", Severity.MEDIUM, "App Transport Security معطّل (NSAllowsArbitraryLoads)", location,
                evidence="NSAllowsArbitraryLoads = true",
                recommendation="احذفه واستخدم HTTPS؛ وإن احتجت استثناءً فاجعله لنطاق محدد عبر NSExceptionDomains.",
                cwe="CWE-319"))
        if ats.get("NSAllowsArbitraryLoadsInWebContent") is True:
            out.append(Finding(
                "MV-IOS-002", Severity.LOW, "يسمح بمحتوى ويب غير مشفّر", location,
                evidence="NSAllowsArbitraryLoadsInWebContent = true",
                recommendation="حمّل محتوى الويب عبر HTTPS فقط.", cwe="CWE-319"))
        domains = ats.get("NSExceptionDomains")
        if isinstance(domains, dict):
            for domain, cfg in domains.items():
                if isinstance(cfg, dict) and cfg.get("NSExceptionAllowsInsecureHTTPLoads") is True:
                    out.append(Finding(
                        "MV-IOS-003", Severity.LOW, f"استثناء HTTP غير مشفّر للنطاق {domain}", location,
                        evidence="NSExceptionAllowsInsecureHTTPLoads = true",
                        recommendation="فعّل HTTPS على الخادم واحذف الاستثناء.", cwe="CWE-319"))
    if plist.get("UIFileSharingEnabled") is True:
        out.append(Finding(
            "MV-IOS-004", Severity.LOW, "مجلد مستندات التطبيق ظاهر في تطبيق الملفات/iTunes", location,
            evidence="UIFileSharingEnabled = true",
            recommendation="لا تحفظ بيانات حساسة في Documents، أو عطّل المشاركة.", cwe="CWE-552"))
    for url_type in plist.get("CFBundleURLTypes") or []:
        if isinstance(url_type, dict):
            schemes = [s for s in url_type.get("CFBundleURLSchemes") or [] if isinstance(s, str)]
            if schemes:
                out.append(Finding(
                    "MV-IOS-005", Severity.LOW, "مخطط روابط مخصّص (URL scheme)", location,
                    evidence=",".join(schemes),
                    recommendation="يمكن لتطبيق آخر تسجيل المخطط نفسه؛ استخدم Universal Links وتحقق من مُدخلات الرابط.",
                    cwe="CWE-939"))
    for key, value in plist.items():
        if isinstance(key, str) and key.endswith("UsageDescription"):
            out.append(Finding(
                "MV-IOS-006", Severity.INFO, f"يطلب إذنًا: {key[2:-16] if key.startswith('NS') else key}",
                location, evidence=f"{key}: {value}"[:160],
                recommendation="تأكد أن الشرح المعروض للمستخدم صادق ويطابق الاستخدام الفعلي."))
    return out
