import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'model.dart';

/// Reads an installed app's APK (readable by any app on Android) and looks
/// for secrets and plain-HTTP addresses inside its compiled code.
///
/// The APK is untrusted input: entries are read one at a time with size
/// caps, nothing is extracted to disk, and every offset is bounds-checked.
class ApkReader {
  ApkReader(this._file, this._length);

  static const maxEntry = 64 * 1024 * 1024;
  static const maxEntries = 20000;

  final RandomAccessFile _file;
  final int _length;

  static ApkReader open(String path) {
    final f = File(path).openSync();
    return ApkReader(f, f.lengthSync());
  }

  void close() => _file.closeSync();

  Uint8List _read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _length) throw const FormatException('out of bounds');
    _file.setPositionSync(offset);
    return _file.readSync(length);
  }

  /// Central directory: name → (compression method, compressed size, size, local header offset).
  List<ZipEntry> entries() {
    final tailLen = _length < 65557 ? _length : 65557;
    final tail = _read(_length - tailLen, tailLen);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('not a zip');
    final e = ByteData.sublistView(tail, eocd);
    final count = e.getUint16(10, Endian.little);
    final cdSize = e.getUint32(12, Endian.little);
    final cdOffset = e.getUint32(16, Endian.little);
    final cd = ByteData.sublistView(_read(cdOffset, cdSize));
    final out = <ZipEntry>[];
    var p = 0;
    for (var i = 0; i < count && i < maxEntries; i++) {
      if (p + 46 > cd.lengthInBytes || cd.getUint32(p, Endian.little) != 0x02014b50) break;
      final method = cd.getUint16(p + 10, Endian.little);
      final csize = cd.getUint32(p + 20, Endian.little);
      final size = cd.getUint32(p + 24, Endian.little);
      final nameLen = cd.getUint16(p + 28, Endian.little);
      final extraLen = cd.getUint16(p + 30, Endian.little);
      final commentLen = cd.getUint16(p + 32, Endian.little);
      final local = cd.getUint32(p + 42, Endian.little);
      if (p + 46 + nameLen > cd.lengthInBytes) break;
      final name = utf8.decode(Uint8List.sublistView(cd, p + 46, p + 46 + nameLen), allowMalformed: true);
      out.add(ZipEntry(name, method, csize, size, local));
      p += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  Uint8List? readEntry(ZipEntry entry) {
    if (entry.size > maxEntry || entry.compressedSize > maxEntry) return null;
    final h = ByteData.sublistView(_read(entry.localOffset, 30));
    if (h.getUint32(0, Endian.little) != 0x04034b50) return null;
    final start = entry.localOffset + 30 + h.getUint16(26, Endian.little) + h.getUint16(28, Endian.little);
    final raw = _read(start, entry.compressedSize);
    if (entry.method == 0) return raw;
    if (entry.method != 8) return null;
    final out = BytesBuilder(copy: false);
    final sink = ByteConversionSink.withCallback((chunk) {
      if (out.length + chunk.length > maxEntry) throw const FormatException('entry too large');
      out.add(chunk);
    });
    final inflate = ZLibDecoder(raw: true).startChunkedConversion(sink);
    inflate.add(raw);
    inflate.close();
    return out.takeBytes();
  }
}

class ZipEntry {
  const ZipEntry(this.name, this.method, this.compressedSize, this.size, this.localOffset);
  final String name;
  final int method;
  final int compressedSize;
  final int size;
  final int localOffset;
}

/// The string table of a .dex file.
List<String> dexStrings(Uint8List dex, {int limit = 300000}) {
  if (dex.length < 0x70 || dex[0] != 0x64 || dex[1] != 0x65 || dex[2] != 0x78) return const [];
  final d = ByteData.sublistView(dex);
  final count = d.getUint32(0x38, Endian.little);
  final off = d.getUint32(0x3c, Endian.little);
  final out = <String>[];
  for (var i = 0; i < count && i < limit; i++) {
    final p = off + 4 * i;
    if (p + 4 > dex.length) break;
    var pos = d.getUint32(p, Endian.little);
    for (var k = 0; k < 5 && pos < dex.length; k++) {
      if (dex[pos++] & 0x80 == 0) break;
    }
    var end = pos;
    while (end < dex.length && dex[end] != 0 && end - pos < 8192) {
      end++;
    }
    if (end >= dex.length || dex[end] != 0) continue;
    out.add(utf8.decode(Uint8List.sublistView(dex, pos, end), allowMalformed: true));
  }
  return out;
}

/// Printable ASCII runs (for native libraries such as Flutter's libapp.so).
Iterable<String> printableStrings(Uint8List data, {int minLength = 12}) sync* {
  var start = -1;
  for (var i = 0; i <= data.length; i++) {
    final b = i < data.length ? data[i] : 0;
    if (b >= 0x20 && b < 0x7f) {
      if (start < 0) start = i;
    } else {
      if (start >= 0 && i - start >= minLength) yield latin1.decode(Uint8List.sublistView(data, start, i));
      start = -1;
    }
  }
}

class SecretRule {
  const SecretRule(this.name, this.pattern, this.severity);
  final String name;
  final RegExp pattern;
  final Severity severity;
}

final secretRules = [
  SecretRule('مفتاح خاص (Private key)', RegExp(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'), Severity.critical),
  SecretRule('مفتاح AWS', RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'), Severity.high),
  SecretRule('رمز Stripe سرّي', RegExp(r'\b[rs]k_live_[0-9A-Za-z]{16,}\b'), Severity.high),
  SecretRule('رمز Slack', RegExp(r'\bxox[abprs]-[0-9A-Za-z-]{10,}\b'), Severity.high),
  SecretRule('رمز GitHub', RegExp(r'\b(?:gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{40,})\b'), Severity.high),
  SecretRule('مفتاح SendGrid', RegExp(r'\bSG\.[0-9A-Za-z_\-]{22}\.[0-9A-Za-z_\-]{43}\b'), Severity.high),
];

final _http = RegExp(r'^http://(?!localhost|127\.0\.0\.1|10\.0\.2\.2|schemas\.|www\.w3\.org|ns\.adobe|xml\.org|purl\.org|'
    r'www\.apache\.org|java\.sun|xmlpull|www\.example|example\.)[\w.-]+\.[a-z]{2,}', caseSensitive: false);

String mask(String s) => s.length <= 8 ? '*' * s.length : '${s.substring(0, 4)}${'*' * (s.length - 8)}${s.substring(s.length - 4)}';

/// Findings from the strings of an app's code.
List<Finding> checkStrings(Iterable<String> strings) {
  final secrets = <SecretRule, Set<String>>{};
  final urls = <String>{};
  for (final s in strings) {
    if (s.length > 4000) continue;
    for (final r in secretRules) {
      final m = r.pattern.firstMatch(s);
      if (m != null) secrets.putIfAbsent(r, () => {}).add(mask(m.group(0)!));
    }
    final u = _http.firstMatch(s);
    if (u != null) urls.add(u.group(0)!);
  }
  return [
    for (final MapEntry(key: rule, value: found) in secrets.entries)
      Finding(
        id: 'AS-KEY',
        severity: rule.severity,
        title: '${rule.name} مكتوب داخل التطبيق',
        explanation: 'وضع المطوّر مفتاحًا سرّيًا داخل كود التطبيق، وأي شخص يستطيع استخراجه واستخدامه '
            '(مثلًا للوصول إلى خوادم الشركة أو بيانات المستخدمين).',
        advice: 'ثغرة عند المطوّر: أبلغه بها. لا تحفظ بيانات حساسة في هذا التطبيق حتى يصلحها.',
        details: found.toList(),
      ),
    if (urls.isNotEmpty)
      Finding(
        id: 'AS-HTTP',
        severity: Severity.low,
        title: 'عناوين HTTP غير مشفّرة في الكود (${urls.length})',
        explanation: 'قد يتصل التطبيق ببعض هذه العناوين دون تشفير.',
        advice: 'تجنّب استخدامه لبيانات حساسة على شبكات Wi-Fi العامة.',
        details: (urls.toList()..sort()).take(20).toList(),
      ),
  ];
}

/// Scans the code inside the given APK files (base + splits) off the UI thread.
Future<List<Finding>> deepScan(List<String> apkPaths) => Isolate.run(() => deepScanSync(apkPaths));

List<Finding> deepScanSync(List<String> apkPaths) {
  final strings = <String>[];
  var budget = 512 * 1024 * 1024;
  for (final path in apkPaths) {
    ApkReader? r;
    try {
      r = ApkReader.open(path);
      for (final e in r.entries()) {
        final isDex = RegExp(r'^classes\d*\.dex$').hasMatch(e.name);
        final isLib = e.name.startsWith('lib/') && e.name.endsWith('.so') &&
            (e.name.endsWith('/libapp.so') || e.name.endsWith('/libreactnativejni.so'));
        final isBundle = e.name.endsWith('.bundle') || e.name.endsWith('index.android.bundle');
        if (!isDex && !isLib && !isBundle) continue;
        if (e.size > budget) break;
        final data = r.readEntry(e);
        if (data == null) continue;
        budget -= data.length;
        strings.addAll(isDex ? dexStrings(data) : printableStrings(data));
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    } finally {
      r?.close();
    }
  }
  return checkStrings(strings);
}
