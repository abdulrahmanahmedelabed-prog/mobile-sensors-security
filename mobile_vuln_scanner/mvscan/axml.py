"""Decoder for Android binary XML (AndroidManifest.xml and res/xml inside an APK).

It produces an ElementTree in the same shape ElementTree gives for a text
manifest (attributes keyed "{namespace}name"), so one set of manifest rules
serves both source projects and built APKs. The input is untrusted: every
offset is bounds-checked and malformed data raises AxmlError, never more.
"""

from __future__ import annotations

import struct
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"

RES_STRING_POOL_TYPE = 0x0001
RES_XML_TYPE = 0x0003
RES_XML_START_NAMESPACE_TYPE = 0x0100
RES_XML_END_NAMESPACE_TYPE = 0x0101
RES_XML_START_ELEMENT_TYPE = 0x0102
RES_XML_END_ELEMENT_TYPE = 0x0103
RES_XML_CDATA_TYPE = 0x0104
RES_XML_RESOURCE_MAP_TYPE = 0x0180

TYPE_NULL = 0x00
TYPE_REFERENCE = 0x01
TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11
TYPE_INT_BOOLEAN = 0x12

UTF8_FLAG = 1 << 8
NO_INDEX = 0xFFFFFFFF
MAX_STRINGS = 200_000
MAX_DEPTH = 256

# Obfuscated APKs may blank attribute names in the string pool; the resource
# map still says which framework attribute each one is.
ATTR_IDS = {
    0x01010003: "name",
    0x01010006: "permission",
    0x01010007: "readPermission",
    0x01010008: "writePermission",
    0x01010009: "protectionLevel",
    0x0101000E: "enabled",
    0x0101000F: "debuggable",
    0x01010010: "exported",
    0x01010012: "taskAffinity",
    0x01010018: "authorities",
    0x0101001B: "grantUriPermissions",
    0x0101001D: "launchMode",
    0x01010027: "scheme",
    0x01010028: "host",
    0x0101020C: "minSdkVersion",
    0x0101021B: "versionCode",
    0x0101021C: "versionName",
    0x01010270: "targetSdkVersion",
    0x01010272: "testOnly",
    0x01010280: "allowBackup",
    0x010104EC: "usesCleartextTraffic",
    0x010104EE: "autoVerify",
    0x01010527: "networkSecurityConfig",
}


class AxmlError(ValueError):
    pass


def is_binary_xml(data: bytes) -> bool:
    return len(data) >= 8 and struct.unpack_from("<HH", data, 0)[0] == RES_XML_TYPE


def _u16(data: bytes, off: int) -> int:
    if off < 0 or off + 2 > len(data):
        raise AxmlError("truncated u16")
    return struct.unpack_from("<H", data, off)[0]


def _u32(data: bytes, off: int) -> int:
    if off < 0 or off + 4 > len(data):
        raise AxmlError("truncated u32")
    return struct.unpack_from("<I", data, off)[0]


def _read_string_pool(data: bytes, start: int, end: int) -> list[str]:
    header_size = _u16(data, start + 2)
    count = _u32(data, start + 8)
    flags = _u32(data, start + 16)
    strings_start = _u32(data, start + 20)
    if count > MAX_STRINGS:
        raise AxmlError("string pool too large")
    utf8 = bool(flags & UTF8_FLAG)
    out = []
    for i in range(count):
        rel = _u32(data, start + header_size + 4 * i)
        pos = start + strings_start + rel
        if pos >= end:
            raise AxmlError("string offset out of chunk")
        if utf8:
            # UTF-16 length (skipped), then UTF-8 byte length; each 1 or 2 bytes.
            n = data[pos]
            pos += 2 if n & 0x80 else 1
            if pos >= end:
                raise AxmlError("truncated utf8 string")
            n = data[pos]
            if n & 0x80:
                if pos + 1 >= end:
                    raise AxmlError("truncated utf8 string")
                n = ((n & 0x7F) << 8) | data[pos + 1]
                pos += 2
            else:
                pos += 1
            if pos + n > end:
                raise AxmlError("utf8 string overflows chunk")
            out.append(data[pos : pos + n].decode("utf-8", "replace"))
        else:
            n = _u16(data, pos)
            pos += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | _u16(data, pos)
                pos += 2
            if pos + 2 * n > end:
                raise AxmlError("utf16 string overflows chunk")
            out.append(data[pos : pos + 2 * n].decode("utf-16-le", "replace"))
    return out


def _format_value(strings: list[str], raw: int, data_type: int, value: int) -> str:
    if raw != NO_INDEX and raw < len(strings):
        return strings[raw]
    if data_type == TYPE_STRING and value < len(strings):
        return strings[value]
    if data_type == TYPE_INT_BOOLEAN:
        return "true" if value else "false"
    if data_type == TYPE_REFERENCE:
        return f"@0x{value:08x}"
    if data_type == TYPE_INT_HEX:
        return f"0x{value:x}"
    if data_type == TYPE_NULL:
        return ""
    # Signed decimal for ints; anything exotic (floats, dimensions) stays raw.
    return str(value - (1 << 32) if value & 0x80000000 else value)


def parse(data: bytes) -> ET.Element:
    """Decode binary XML into an ElementTree root element."""
    if not is_binary_xml(data):
        raise AxmlError("not Android binary XML")
    total = min(_u32(data, 4), len(data))
    off = _u16(data, 2)
    strings: list[str] = []
    res_ids: list[int] = []
    root = None
    stack: list[ET.Element] = []

    def name_of(index: int) -> str:
        if index == NO_INDEX:
            return ""
        name = strings[index] if index < len(strings) else ""
        if not name and index < len(res_ids):
            name = ATTR_IDS.get(res_ids[index], f"attr_0x{res_ids[index]:08x}")
        return name

    while off + 8 <= total:
        ctype = _u16(data, off)
        hsize = _u16(data, off + 2)
        csize = _u32(data, off + 4)
        if csize < 8 or off + csize > total:
            raise AxmlError("bad chunk size")
        end = off + csize
        if ctype == RES_STRING_POOL_TYPE:
            strings = _read_string_pool(data, off, end)
        elif ctype == RES_XML_RESOURCE_MAP_TYPE:
            res_ids = [_u32(data, p) for p in range(off + hsize, end - 3, 4)]
        elif ctype == RES_XML_START_ELEMENT_TYPE:
            ext = off + hsize
            ns_idx = _u32(data, ext)
            tag = name_of(_u32(data, ext + 4))
            attr_start = _u16(data, ext + 8)
            attr_size = _u16(data, ext + 10)
            attr_count = _u16(data, ext + 12)
            if attr_size < 20:
                raise AxmlError("bad attribute size")
            ns = strings[ns_idx] if ns_idx != NO_INDEX and ns_idx < len(strings) else ""
            elem = ET.Element(f"{{{ns}}}{tag}" if ns else tag)
            for i in range(attr_count):
                a = ext + attr_start + i * attr_size
                if a + 20 > end:
                    raise AxmlError("attribute overflows chunk")
                a_ns = _u32(data, a)
                a_name = name_of(_u32(data, a + 4))
                raw = _u32(data, a + 8)
                dtype = data[a + 15]
                val = _u32(data, a + 16)
                uri = strings[a_ns] if a_ns != NO_INDEX and a_ns < len(strings) else ""
                key = f"{{{uri}}}{a_name}" if uri else a_name
                elem.set(key, _format_value(strings, raw, dtype, val))
            if stack:
                stack[-1].append(elem)
            elif root is None:
                root = elem
            else:
                raise AxmlError("multiple root elements")
            stack.append(elem)
            if len(stack) > MAX_DEPTH:
                raise AxmlError("nesting too deep")
        elif ctype == RES_XML_END_ELEMENT_TYPE:
            if stack:
                stack.pop()
        off = end

    if root is None:
        raise AxmlError("no root element")
    return root
