"""Walk a target (project folder, APK/XAPK/APKS, IPA, or single file) and run the rules.

Archives are read in memory entry by entry, never extracted, so a hostile
archive cannot write outside a folder (zip-slip) and size caps stop zip bombs.
"""

from __future__ import annotations

import io
import os
import plistlib
import re
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from . import android, axml, code, ios
from .models import Finding, ScanResult, Severity

SKIP_DIRS = {".git", ".hg", ".svn", "build", ".dart_tool", ".gradle", "node_modules", "Pods", ".idea",
             ".vscode", "__pycache__", ".venv", "venv", ".pub-cache", "DerivedData", ".cxx"}
MAX_TEXT_FILE = 2 * 1024 * 1024
MAX_ENTRY = 64 * 1024 * 1024
MAX_ARCHIVE_TOTAL = 512 * 1024 * 1024
MAX_FILES = 50_000
MAX_DEX_STRINGS = 300_000


class _Budget:
    def __init__(self, total: int):
        self.left = total

    def read(self, zf: zipfile.ZipFile, info: zipfile.ZipInfo, cap: int = MAX_ENTRY) -> bytes | None:
        if info.file_size > cap or info.file_size > self.left:
            return None
        with zf.open(info) as fh:
            data = fh.read(cap + 1)
        if len(data) > cap:  # declared size lied
            return None
        self.left -= len(data)
        return data


def _decode_text(data: bytes) -> str | None:
    if b"\x00" in data[:4096]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def _parse_xml(data: bytes) -> ET.Element | None:
    try:
        if axml.is_binary_xml(data):
            return axml.parse(data)
        text = _decode_text(data)
        if text is None or "<!DOCTYPE" in text or "<!ENTITY" in text:
            return None  # no DTDs: avoids entity expansion attacks
        return ET.fromstring(text)
    except (ET.ParseError, axml.AxmlError, ValueError):
        return None


def _target_sdk_from_gradle(root: Path) -> int | None:
    for name in ("build.gradle", "build.gradle.kts"):
        p = root / "android" / "app" / name
        if not p.is_file():
            p = root / "app" / name
        if p.is_file():
            m = re.search(r"targetSdk(?:Version)?\s*=?\s*(\d+)", p.read_text("utf-8", "replace"))
            if m:
                return int(m.group(1))
    return None


def scan_file_bytes(name: str, data: bytes, result: ScanResult, target_sdk: int | None = None) -> None:
    """Scan one file's contents; name decides which rules apply."""
    base = os.path.basename(name.rsplit("!", 1)[-1])
    ext = os.path.splitext(base)[1].lower()
    result.files_scanned += 1

    if base == "AndroidManifest.xml":
        root = _parse_xml(data)
        if root is not None:
            result.findings.extend(android.check_manifest(root, name, target_sdk))
        else:
            result.errors.append(f"{name}: تعذّر تحليل الملف")
        if not axml.is_binary_xml(data):
            text = _decode_text(data)
            if text:
                result.findings.extend(code.scan_text(text, name, ".xml"))
        return
    if ext == ".xml":
        if axml.is_binary_xml(data):
            root = _parse_xml(data)
            if root is not None and root.tag == "network-security-config":
                result.findings.extend(android.check_network_security_config(root, name))
            return
        text = _decode_text(data)
        if text is None:
            return
        if "network-security-config" in text:
            root = _parse_xml(data)
            if root is not None:
                result.findings.extend(android.check_network_security_config(root, name))
        result.findings.extend(code.scan_text(text, name, ext))
        return
    if base == "Info.plist" or ext == ".plist":
        try:
            plist = plistlib.loads(data)
        except Exception:  # malformed plists come in many shapes
            plist = None
        if isinstance(plist, dict) and base == "Info.plist":
            result.findings.extend(ios.check_info_plist(plist, name))
        text = _decode_text(data) if not data.startswith(b"bplist") else None
        if text:
            result.findings.extend(code.scan_text(text, name, ".plist"))
        return
    if ext in (".gradle", ".kts") and base.startswith("build.gradle"):
        text = _decode_text(data) or ""
        result.findings.extend(android.check_gradle(text, name))
        result.findings.extend(code.scan_text(text, name, ext))
        return
    if ext == ".dex":
        result.findings.extend(code.scan_strings(dex_strings(data), name))
        return
    if ext in (".so", ".dylib") or (ext == "" and data[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")):
        result.findings.extend(code.scan_strings(code.printable_strings(data), name))
        return
    if ext in code.ALL or base.startswith(".env"):
        if len(data) > MAX_TEXT_FILE:
            return
        text = _decode_text(data)
        if text is not None:
            if ext == ".js" and text.count("\n") < 5 and len(text) > 100_000:
                # Minified bundle (e.g. React Native): line rules are meaningless, secrets are not.
                result.findings.extend(code.scan_strings(text.split('"'), name))
            else:
                result.findings.extend(code.scan_text(text, name, ext if ext else ".env"))


def dex_strings(data: bytes) -> list[str]:
    """String table of a .dex file (bounds-checked; returns what it can)."""
    if len(data) < 0x70 or not data.startswith(b"dex\n"):
        return []
    size, off = struct.unpack_from("<II", data, 0x38)
    size = min(size, MAX_DEX_STRINGS)
    out = []
    for i in range(size):
        p = off + 4 * i
        if p + 4 > len(data):
            break
        pos = struct.unpack_from("<I", data, p)[0]
        # uleb128 length in UTF-16 units, then MUTF-8 bytes up to NUL.
        for _ in range(5):
            if pos >= len(data):
                break
            b = data[pos]
            pos += 1
            if not b & 0x80:
                break
        end = data.find(b"\x00", pos, pos + 8192)
        if end < 0:
            continue
        out.append(data[pos:end].decode("utf-8", "replace"))
    return out


def scan_zip(zf: zipfile.ZipFile, label: str, result: ScanResult, depth: int = 0) -> None:
    budget = _Budget(MAX_ARCHIVE_TOTAL)
    infos = [i for i in zf.infolist() if not i.is_dir()][:MAX_FILES]
    is_ipa = any(i.filename.startswith("Payload/") for i in infos)
    for info in infos:
        name = info.filename
        base = os.path.basename(name)
        ext = os.path.splitext(base)[1].lower()
        if ".." in Path(name).parts:
            result.errors.append(f"{label}: مسار مشبوه داخل الأرشيف: {name}")
            continue
        wanted = (
            base == "AndroidManifest.xml"
            or (name.startswith("res/xml/") and ext == ".xml")
            or ext in (".dex", ".so", ".js", ".json", ".properties", ".plist", ".xml", ".dylib")
            or (is_ipa and ".app/" in name and base and "." not in base and name.count("/") == 2)
            or (depth == 0 and ext == ".apk")
        )
        if not wanted:
            continue
        data = budget.read(zf, info)
        if data is None:
            result.errors.append(f"{label}: تخطّي ملف كبير جدًا: {name}")
            continue
        loc = f"{label}!{name}"
        if ext == ".apk":
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as inner:
                    scan_zip(inner, loc, result, depth + 1)
            except zipfile.BadZipFile:
                result.errors.append(f"{loc}: ملف APK تالف")
            continue
        scan_file_bytes(loc, data, result)
    is_apk = any(i.filename == "AndroidManifest.xml" for i in infos)
    v1_signed = any(i.filename.startswith("META-INF/") and i.filename.endswith((".RSA", ".DSA", ".EC")) for i in infos)
    if is_apk and not v1_signed and not _has_v2_signature(zf):
        result.add(Finding("MV-APK-001", Severity.MEDIUM, "ملف APK غير موقّع", label,
                           recommendation="لا تثبّت تطبيقًا غير موقّع؛ قد يكون معدّلًا.", cwe="CWE-347"))


def _has_v2_signature(zf: zipfile.ZipFile) -> bool:
    fp = zf.fp
    if fp is None:
        return False
    try:
        cd_offset = zf.start_dir
        fp.seek(max(0, cd_offset - 16))
        return fp.read(16) == b"APK Sig Block 42"
    except (OSError, AttributeError):
        return False


def scan_directory(root: Path, result: ScanResult) -> None:
    target_sdk = _target_sdk_from_gradle(root)
    count = 0
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not os.path.islink(os.path.join(dirpath, d)))
        for fn in sorted(filenames):
            path = Path(dirpath) / fn
            if path.is_symlink():
                continue
            ext = path.suffix.lower()
            if not (ext in code.ALL or fn in ("AndroidManifest.xml", "Info.plist") or fn.startswith(".env")
                    or fn.startswith("build.gradle")):
                continue
            try:
                if path.stat().st_size > MAX_TEXT_FILE:
                    continue
                data = path.read_bytes()
            except OSError as e:
                result.errors.append(f"{path}: {e.strerror}")
                continue
            rel = str(path.relative_to(root))
            scan_file_bytes(rel, data, result, target_sdk)
            count += 1
            if count >= MAX_FILES:
                result.errors.append("تم الوصول إلى الحد الأقصى لعدد الملفات")
                return


def scan(target: str) -> ScanResult:
    path = Path(target)
    if path.is_dir():
        result = ScanResult(str(path), "project")
        scan_directory(path, result)
        return result
    if not path.is_file():
        raise FileNotFoundError(target)
    ext = path.suffix.lower()
    if ext in (".apk", ".xapk", ".apks", ".ipa", ".zip", ".apkm"):
        kind = "ipa" if ext == ".ipa" else "apk"
        result = ScanResult(str(path), kind)
        try:
            with zipfile.ZipFile(path) as zf:
                scan_zip(zf, path.name, result)
        except zipfile.BadZipFile:
            result.errors.append(f"{path.name}: ليس أرشيفًا صالحًا")
        return result
    result = ScanResult(str(path), "file")
    if path.stat().st_size <= MAX_ENTRY:
        scan_file_bytes(path.name, path.read_bytes(), result)
    return result
