"""Command line: mvscan TARGET... | mvscan --adb [--package NAME]"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from . import __version__, adb, report
from .models import ScanResult, Severity
from .scanner import scan


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mvscan",
        description="كاشف الثغرات البرمجية في تطبيقات الجوال (أندرويد / iOS / Flutter / React Native).",
    )
    p.add_argument("targets", nargs="*", help="مجلد مشروع، أو ملف .apk / .xapk / .apks / .ipa")
    p.add_argument("--adb", action="store_true", help="افحص التطبيقات المثبتة في جوال متصل عبر USB")
    p.add_argument("--package", action="append", default=[], help="مع --adb: اسم حزمة محددة (يتكرر)")
    p.add_argument("--include-system", action="store_true", help="مع --adb: يشمل تطبيقات النظام")
    p.add_argument("--format", choices=("text", "json", "html", "sarif"), default="text")
    p.add_argument("--sarif-base", default="", help="مع sarif: جذر المستودع لجعل المسارات نسبية إليه")
    p.add_argument("-o", "--output", help="اكتب التقرير في ملف بدل الشاشة")
    p.add_argument("--min-severity", default="info", help="أقل خطورة تُعرض: info/low/medium/high/critical")
    p.add_argument("--fail-on", default=None,
                   help="أنهِ بخطأ (رمز 1) إن وُجدت ثغرة بهذه الخطورة أو أعلى؛ مفيد في CI")
    p.add_argument("--version", action="version", version=f"mvscan {__version__}")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        min_sev = Severity.parse(args.min_severity)
        fail_on = Severity.parse(args.fail_on) if args.fail_on else None
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    if not args.targets and not args.adb:
        build_parser().print_help()
        return 2

    results: list[ScanResult] = []
    for t in args.targets:
        try:
            results.append(scan(t))
        except FileNotFoundError:
            print(f"غير موجود: {t}", file=sys.stderr)
            return 2

    if args.adb:
        try:
            packages = args.package or adb.list_packages(args.include_system)
            with tempfile.TemporaryDirectory(prefix="mvscan-") as tmp:
                for i, pkg in enumerate(packages, 1):
                    print(f"[{i}/{len(packages)}] {pkg}", file=sys.stderr)
                    try:
                        apk = adb.pull_base_apk(pkg, Path(tmp))
                    except adb.AdbError as e:
                        print(f"  تخطّي: {e}", file=sys.stderr)
                        continue
                    r = scan(str(apk))
                    r.target = pkg
                    results.append(r)
                    apk.unlink(missing_ok=True)
        except adb.AdbError as e:
            print(e, file=sys.stderr)
            return 2

    if args.format == "sarif":
        out = report.to_sarif(results, min_sev, args.sarif_base)
    else:
        render = {"text": report.to_text, "json": report.to_json, "html": report.to_html}[args.format]
        out = render(results, min_sev)
    if args.output:
        Path(args.output).write_text(out, encoding="utf-8")
        print(f"كُتب التقرير في {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(out + "\n")

    if fail_on is not None and any(f.severity >= fail_on for r in results for f in r.sorted_findings()):
        return 1
    return 0
