"""Text, JSON and HTML reports. Everything taken from scanned files is escaped."""

from __future__ import annotations

import html
import json
from datetime import datetime, timezone

from . import __version__
from .models import ScanResult, Severity


def _safe(text: str) -> str:
    # Scanned content may carry terminal escape sequences; drop control characters.
    return "".join(ch if ch.isprintable() or ch == " " else "?" for ch in text)


def to_text(results: list[ScanResult], min_severity: Severity = Severity.INFO) -> str:
    lines = []
    for r in results:
        findings = [f for f in r.sorted_findings() if f.severity >= min_severity]
        lines.append("=" * 72)
        lines.append(f"الهدف: {_safe(r.target)}  ({r.kind}، {r.files_scanned} ملف)")
        c = r.counts()
        lines.append("النتائج: " + "  ".join(f"{Severity[k.upper()].arabic}={v}" for k, v in reversed(c.items())))
        lines.append("-" * 72)
        if not findings:
            lines.append("لا توجد ثغرات بهذا المستوى أو أعلى. ✔")
        for f in findings:
            where = _safe(f.location) + (f":{f.line}" if f.line else "")
            lines.append(f"[{f.severity.arabic} / {f.severity.name}] {f.rule_id} {f.cwe}".rstrip())
            lines.append(f"  {_safe(f.title)}")
            lines.append(f"  المكان: {where}")
            if f.evidence:
                lines.append(f"  الدليل: {_safe(f.evidence)}")
            if f.recommendation:
                lines.append(f"  الحل: {f.recommendation}")
            lines.append("")
        for e in r.errors:
            lines.append(f"تنبيه: {_safe(e)}")
    return "\n".join(lines)


def to_json(results: list[ScanResult], min_severity: Severity = Severity.INFO) -> str:
    return json.dumps({
        "tool": "mvscan",
        "version": __version__,
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "results": [{
            "target": r.target,
            "kind": r.kind,
            "files_scanned": r.files_scanned,
            "counts": r.counts(),
            "findings": [f.to_dict() for f in r.sorted_findings() if f.severity >= min_severity],
            "errors": r.errors,
        } for r in results],
    }, ensure_ascii=False, indent=2)


_COLORS = {
    Severity.CRITICAL: "#7f1d1d", Severity.HIGH: "#b91c1c", Severity.MEDIUM: "#c2410c",
    Severity.LOW: "#a16207", Severity.INFO: "#475569",
}


def to_html(results: list[ScanResult], min_severity: Severity = Severity.INFO) -> str:
    e = html.escape
    parts = []
    for r in results:
        rows = []
        for f in r.sorted_findings():
            if f.severity < min_severity:
                continue
            where = f.location + (f":{f.line}" if f.line else "")
            rows.append(
                f"<tr><td><span class='sev' style='background:{_COLORS[f.severity]}'>{e(f.severity.arabic)}</span></td>"
                f"<td><b>{e(f.title)}</b><div class='meta'>{e(f.rule_id)} {e(f.cwe)}</div>"
                f"<div class='ev'><code>{e(f.evidence)}</code></div><div>{e(f.recommendation)}</div></td>"
                f"<td class='loc'><code>{e(where)}</code></td></tr>")
        counts = " · ".join(f"{e(Severity[k.upper()].arabic)}: {v}" for k, v in reversed(r.counts().items()))
        body = "".join(rows) or "<tr><td colspan='3'>لا توجد ثغرات بهذا المستوى ✔</td></tr>"
        errors = "".join(f"<li>{e(x)}</li>" for x in r.errors)
        parts.append(
            f"<section><h2>{e(r.target)}</h2><p>{e(r.kind)} — {r.files_scanned} ملف — {counts}</p>"
            f"<table><thead><tr><th>الخطورة</th><th>الثغرة والحل</th><th>المكان</th></tr></thead>"
            f"<tbody>{body}</tbody></table>{'<ul>' + errors + '</ul>' if errors else ''}</section>")
    return f"""<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>تقرير ثغرات التطبيق</title>
<style>
body{{font-family:system-ui,'Segoe UI',Tahoma,sans-serif;margin:0 auto;max-width:1100px;padding:16px;background:#f8fafc;color:#0f172a}}
table{{width:100%;border-collapse:collapse;background:#fff}}th,td{{border:1px solid #e2e8f0;padding:8px;vertical-align:top;text-align:start}}
.sev{{color:#fff;border-radius:6px;padding:2px 8px;white-space:nowrap}}.meta{{color:#64748b;font-size:12px}}
.ev code,.loc code{{direction:ltr;unicode-bidi:embed;word-break:break-all;font-size:12px}}.ev{{margin:4px 0;background:#f1f5f9;padding:4px}}
</style></head><body><h1>تقرير فحص ثغرات تطبيقات الجوال (mvscan {e(__version__)})</h1>{''.join(parts)}</body></html>"""
