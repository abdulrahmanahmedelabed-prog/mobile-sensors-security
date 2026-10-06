"""Pull the APKs of apps installed on a connected Android phone (USB debugging) for scanning.

Only fixed argument lists are passed to adb (never a shell string), and package
names and device paths are validated before use.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

PACKAGE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$")
APK_PATH_RE = re.compile(r"^/(?:data|system|product|vendor|system_ext|apex)/[A-Za-z0-9_./@=+~-]+\.apk$")


class AdbError(RuntimeError):
    pass


def _adb(*args: str, timeout: int = 120) -> str:
    exe = shutil.which("adb")
    if exe is None:
        raise AdbError("لم يُعثر على adb. ثبّت Android platform-tools وفعّل تصحيح USB في الجوال.")
    try:
        proc = subprocess.run([exe, *args], capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise AdbError("انتهت مهلة adb") from None
    if proc.returncode != 0:
        raise AdbError(proc.stderr.strip() or f"adb {' '.join(args)} failed")
    return proc.stdout


def list_packages(include_system: bool = False) -> list[str]:
    out = _adb("shell", "pm", "list", "packages", *([] if include_system else ["-3"]))
    pkgs = []
    for line in out.splitlines():
        name = line.strip().removeprefix("package:")
        if PACKAGE_RE.match(name):
            pkgs.append(name)
    return sorted(pkgs)


def apk_paths(package: str) -> list[str]:
    if not PACKAGE_RE.match(package):
        raise AdbError(f"اسم حزمة غير صالح: {package!r}")
    out = _adb("shell", "pm", "path", package)
    paths = [line.strip().removeprefix("package:") for line in out.splitlines()]
    return [p for p in paths if APK_PATH_RE.match(p)]


def pull_base_apk(package: str, dest_dir: Path) -> Path:
    paths = apk_paths(package)
    if not paths:
        raise AdbError(f"لا يوجد APK للحزمة {package}")
    base = next((p for p in paths if p.endswith("/base.apk")), paths[0])
    dest = dest_dir / f"{package}.apk"
    _adb("pull", base, str(dest), timeout=600)
    return dest
