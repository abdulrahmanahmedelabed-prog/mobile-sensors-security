import io
import json
import plistlib
import struct
import xml.etree.ElementTree as ET
import zipfile

import pytest

from mvscan import axml, cli, report
from mvscan.code import scan_text
from mvscan.models import Severity
from mvscan.scanner import dex_strings, scan

from axml_encoder import encode

A = "{http://schemas.android.com/apk/res/android}"
# Fake secrets, assembled at runtime so secret scanners (e.g. GitHub push
# protection) do not mistake the test data for leaked credentials.
FAKE_AWS = "AKIA" + "IOSFODNN7EXAMPLE"
FAKE_STRIPE = "sk_" + "live_" + "abcdefghijklmnopqrstuvwx"

VULN_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.bad">
  <uses-sdk android:minSdkVersion="19" android:targetSdkVersion="30"/>
  <uses-permission android:name="android.permission.READ_SMS"/>
  <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
  <application android:debuggable="true" android:allowBackup="true" android:usesCleartextTraffic="true">
    <activity android:name=".Main" android:exported="true">
      <intent-filter><action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
    <service android:name=".Sync"><intent-filter><action android:name="com.bad.SYNC"/></intent-filter></service>
    <provider android:name=".Files" android:authorities="com.bad.files" android:exported="true"/>
    <activity android:name=".Link" android:exported="true">
      <intent-filter><action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.BROWSABLE"/><data android:scheme="badapp"/></intent-filter>
    </activity>
  </application>
</manifest>"""

SAFE_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.good">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35"/>
  <application android:allowBackup="false" android:usesCleartextTraffic="false">
    <activity android:name=".Main" android:exported="true">
      <intent-filter><action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
    <service android:name=".Internal" android:exported="false"/>
  </application>
</manifest>"""


def ids(result):
    return {f.rule_id for f in result.sorted_findings()}


def write(tmp_path, rel, text):
    p = tmp_path / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    return p


def test_vulnerable_manifest(tmp_path):
    write(tmp_path, "android/app/src/main/AndroidManifest.xml", VULN_MANIFEST)
    found = ids(scan(str(tmp_path)))
    assert {"MV-MAN-001", "MV-MAN-002", "MV-MAN-003", "MV-MAN-004", "MV-MAN-005", "MV-MAN-006",
            "MV-MAN-008", "MV-MAN-009", "MV-MAN-011"} <= found


def test_safe_manifest_has_no_issues(tmp_path):
    write(tmp_path, "android/app/src/main/AndroidManifest.xml", SAFE_MANIFEST)
    r = scan(str(tmp_path))
    assert [f for f in r.sorted_findings() if f.severity >= Severity.LOW] == []


def test_permission_removed_by_tools_node_is_ignored(tmp_path):
    write(tmp_path, "AndroidManifest.xml", SAFE_MANIFEST.replace(
        '<application', '<uses-permission xmlns:tools="http://schemas.android.com/tools" '
        'android:name="android.permission.READ_SMS" tools:node="remove"/><application'))
    assert "MV-MAN-009" not in ids(scan(str(tmp_path)))


def test_launcher_activity_is_not_flagged(tmp_path):
    write(tmp_path, "AndroidManifest.xml", VULN_MANIFEST)
    names = [f.title for f in scan(str(tmp_path)).findings if f.rule_id == "MV-MAN-004"]
    assert not any(".Main" in n for n in names)
    assert any(".Sync" in n for n in names)


@pytest.mark.parametrize("ext,src,rule", [
    (".kt", f'val key = "{FAKE_AWS}"', "MV-SEC-002"),
    (".java", 'String password = "Sup3rS3cret!";', "MV-SEC-005"),
    (".dart", "final u = 'http://api.shop.com/login';", "MV-NET-001"),
    (".dart", "final u = 'ws://api.shop.com/live';", "MV-NET-001"),
    (".java", "public void checkServerTrusted(X509Certificate[] c, String a) {}", "MV-NET-002"),
    (".kt", "HostnameVerifier { _, _ -> true }", "MV-NET-003"),
    (".dart", "client.badCertificateCallback = (cert, host, port) => true;", "MV-NET-004"),
    (".java", "web.getSettings().setAllowUniversalAccessFromFileURLs(true);", "MV-WEB-003"),
    (".java", 'MessageDigest.getInstance("MD5");', "MV-CRY-001"),
    (".java", 'Cipher.getInstance("AES/ECB/PKCS5Padding");', "MV-CRY-002"),
    (".java", 'db.rawQuery("SELECT * FROM u WHERE n=\'" + name + "\'", null);', "MV-INJ-001"),
    (".dart", "db.rawQuery('SELECT * FROM u WHERE n=$name');", "MV-INJ-001"),
    (".kt", 'Log.d("auth", "token=$token")', "MV-LOG-001"),
    (".dart", "prefs.setString('auth_token', t);", "MV-STO-003"),
    (".java", "openFileOutput(\"x\", MODE_WORLD_READABLE);", "MV-STO-001"),
    (".java", "PendingIntent.getActivity(ctx, 0, i, 0);", "MV-IPC-001"),
    (".swift", "let w = UIWebView()", "MV-WEB-005"),
    (".js", "eval(userInput)", "MV-WEB-006"),
])
def test_code_rules_detect(ext, src, rule):
    assert rule in {f.rule_id for f in scan_text(src, "f" + ext, ext)}


@pytest.mark.parametrize("ext,src", [
    (".java", 'String password = "";'),
    (".dart", "final password = 'changeme';"),
    (".dart", "final u = 'https://api.shop.com/login';"),
    (".xml", '<a xmlns:android="http://schemas.android.com/apk/res/android"/>'),
    (".java", 'MessageDigest.getInstance("SHA-256");'),
    (".java", 'db.rawQuery("SELECT * FROM u WHERE n=?", new String[]{name});'),
    (".java", "PendingIntent.getActivity(ctx, 0, i, PendingIntent.FLAG_IMMUTABLE);"),
    (".kt", "// web.settings.setAllowFileAccessFromFileURLs(true)"),
    (".dart", "final u = 'http://shop.com/x'; // mvscan:ignore reviewed"),
])
def test_code_rules_ignore_safe_code(ext, src):
    assert [f for f in scan_text(src, "f" + ext, ext) if f.severity >= Severity.LOW] == []


def test_secrets_are_masked_in_reports():
    f = scan_text(f'val k = "{FAKE_AWS}"', "a.kt", ".kt")[0]
    assert FAKE_AWS not in f.evidence
    assert f.evidence.count("*") >= 8


def test_network_security_config(tmp_path):
    write(tmp_path, "res/xml/network_security_config.xml", """<network-security-config>
      <base-config cleartextTrafficPermitted="true"><trust-anchors>
        <certificates src="system"/><certificates src="user"/></trust-anchors></base-config>
      <domain-config cleartextTrafficPermitted="true"><domain>10.0.2.2</domain></domain-config>
    </network-security-config>""")
    findings = scan(str(tmp_path)).sorted_findings()
    sev = {(f.rule_id, f.severity) for f in findings}
    assert ("MV-NSC-001", Severity.MEDIUM) in sev and ("MV-NSC-001", Severity.LOW) in sev
    assert ("MV-NSC-002", Severity.MEDIUM) in sev


def test_doctype_is_refused(tmp_path):
    write(tmp_path, "AndroidManifest.xml", '<!DOCTYPE m [<!ENTITY a "aaaa">]><manifest>&a;</manifest>')
    assert scan(str(tmp_path)).errors


def test_gradle_rules(tmp_path):
    write(tmp_path, "android/app/build.gradle", """android {
      defaultConfig { minSdkVersion 21; targetSdkVersion 34 }
      signingConfigs { release { storePassword "hunter22" } }
      buildTypes { release { signingConfig signingConfigs.debug } }
    }""")
    r = scan(str(tmp_path))
    assert {"MV-MAN-006", "MV-GRD-002", "MV-GRD-003"} <= ids(r)
    assert all("hunter22" not in f.evidence for f in r.findings)


def test_info_plist(tmp_path):
    (tmp_path / "Info.plist").write_bytes(plistlib.dumps({
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
        "CFBundleURLTypes": [{"CFBundleURLSchemes": ["myapp"]}],
        "NSCameraUsageDescription": "scan codes",
    }))
    assert {"MV-IOS-001", "MV-IOS-005", "MV-IOS-006"} <= ids(scan(str(tmp_path)))


def test_symlinks_are_not_followed(tmp_path):
    outside = tmp_path / "outside"
    write(outside, "secret.kt", f'val k = "{FAKE_AWS}"')
    proj = tmp_path / "proj"
    proj.mkdir()
    (proj / "link").symlink_to(outside, target_is_directory=True)
    assert "MV-SEC-002" not in ids(scan(str(proj)))


def _dex(strings):
    data_off = 0x70 + 4 * len(strings)
    blob, offsets = b"", []
    for s in strings:
        offsets.append(data_off + len(blob))
        b = s.encode()
        blob += bytes([len(s)]) + b + b"\x00"
    header = bytearray(0x70)
    header[:8] = b"dex\n035\x00"
    struct.pack_into("<II", header, 0x38, len(strings), 0x70)
    return bytes(header) + b"".join(struct.pack("<I", o) for o in offsets) + blob


def _apk(path, manifest_xml, extra=None, signed=True):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("AndroidManifest.xml", encode(ET.fromstring(manifest_xml)))
        zf.writestr("classes.dex", _dex(["Lcom/bad/Main;", "http://tracker.bad.com/collect",
                                          FAKE_AWS]))
        if signed:
            zf.writestr("META-INF/CERT.RSA", b"x")
        for name, data in (extra or {}).items():
            zf.writestr(name, data)


def test_binary_manifest_roundtrip():
    root = axml.parse(encode(ET.fromstring(VULN_MANIFEST)))
    assert root.tag == "manifest"
    app = root.find("application")
    assert app.get(A + "debuggable") == "true"
    assert root.find("application/provider").get(A + "authorities") == "com.bad.files"


def test_dex_strings():
    assert FAKE_AWS in dex_strings(_dex(["a", FAKE_AWS]))
    assert dex_strings(b"not a dex") == []


def test_apk_scan(tmp_path):
    apk = tmp_path / "bad.apk"
    nsc = ET.fromstring('<network-security-config><base-config cleartextTrafficPermitted="true"/>'
                        '</network-security-config>')
    _apk(apk, VULN_MANIFEST, {"res/xml/nsc.xml": encode(nsc)}, signed=False)
    found = ids(scan(str(apk)))
    assert {"MV-MAN-001", "MV-MAN-005", "MV-SEC-002", "MV-NET-001", "MV-NSC-001", "MV-APK-001"} <= found


def test_xapk_with_nested_apk(tmp_path):
    inner = tmp_path / "base.apk"
    _apk(inner, VULN_MANIFEST)
    xapk = tmp_path / "app.xapk"
    with zipfile.ZipFile(xapk, "w") as zf:
        zf.write(inner, "com.bad.apk")
    assert "MV-MAN-001" in ids(scan(str(xapk)))


def test_ipa_scan(tmp_path):
    ipa = tmp_path / "app.ipa"
    with zipfile.ZipFile(ipa, "w") as zf:
        zf.writestr("Payload/App.app/Info.plist", plistlib.dumps(
            {"NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}}, fmt=plistlib.FMT_BINARY))
        zf.writestr("Payload/App.app/App", b"\xcf\xfa\xed\xfe" + b"\x00" * 16 + FAKE_STRIPE.encode() + b"\x00")
    assert {"MV-IOS-001", "MV-SEC-004"} <= ids(scan(str(ipa)))


def test_zip_slip_entry_is_reported_not_extracted(tmp_path):
    z = tmp_path / "evil.apk"
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr("../../evil.xml", "<x/>")
    r = scan(str(z))
    assert any("مشبوه" in e for e in r.errors)
    assert not (tmp_path.parent / "evil.xml").exists()


@pytest.mark.parametrize("blob", [b"", b"\x03\x00\x08\x00\xff\xff\xff\xff", b"\x03\x00\x08\x00" + b"\x10\x00\x00\x00" + b"\x01" * 8,
                                  b"\x03\x00\x08\x00\x20\x00\x00\x00\x01\x00\x1c\x00\xff\xff\x00\x00" + b"\xff" * 16])
def test_malformed_binary_xml_raises_cleanly(blob):
    with pytest.raises(axml.AxmlError):
        axml.parse(blob)


def test_reports_escape_html_and_cli_exit_codes(tmp_path, capsys):
    write(tmp_path, "a.dart", "final u = 'http://x.bad.com/<script>';")
    r = scan(str(tmp_path))
    page = report.to_html([r])
    assert "<script>" not in page and "&lt;script&gt;" in page
    data = json.loads(report.to_json([r]))
    assert data["results"][0]["counts"]["medium"] == 1
    assert cli.main([str(tmp_path), "--fail-on", "medium", "--format", "json"]) == 1
    assert cli.main([str(tmp_path), "--fail-on", "high", "--format", "json"]) == 0
    capsys.readouterr()


def test_text_report_strips_control_characters(tmp_path):
    write(tmp_path, "a.dart", "final u = 'http://x.bad.com/\x1b[2J';")
    assert "\x1b" not in report.to_text([scan(str(tmp_path))])


def test_adb_rejects_bad_package_names():
    from mvscan import adb
    with pytest.raises(adb.AdbError):
        adb.apk_paths("com.x; rm -rf /")
    assert adb.APK_PATH_RE.match("/data/app/~~abc==/com.x-1/base.apk")
    assert not adb.APK_PATH_RE.match("/data/app/x.apk; reboot")
