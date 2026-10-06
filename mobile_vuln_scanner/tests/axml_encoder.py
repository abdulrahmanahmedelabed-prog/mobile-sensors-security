"""Minimal Android binary XML encoder, used only to build test APKs."""

from __future__ import annotations

import struct
import xml.etree.ElementTree as ET

from mvscan.axml import ANDROID_NS, TYPE_INT_BOOLEAN, TYPE_STRING


def encode(root: ET.Element) -> bytes:
    strings: list[str] = []

    def idx(s: str) -> int:
        if s not in strings:
            strings.append(s)
        return strings.index(s)

    def split(key: str) -> tuple[str, str]:
        if key.startswith("{"):
            ns, name = key[1:].split("}", 1)
            return ns, name
        return "", key

    body = b""
    android = idx(ANDROID_NS)
    prefix = idx("android")
    body += struct.pack("<HHIII", 0x0100, 16, 24, 1, 0xFFFFFFFF) + struct.pack("<II", prefix, android)

    def walk(el: ET.Element) -> bytes:
        ns, name = split(el.tag)
        attrs = b""
        for key, value in el.attrib.items():
            ans, aname = split(key)
            if value in ("true", "false"):
                raw, dtype, data = 0xFFFFFFFF, TYPE_INT_BOOLEAN, 0xFFFFFFFF if value == "true" else 0
            else:
                raw = idx(value)
                dtype, data = TYPE_STRING, raw
            attrs += struct.pack("<IIIHBBI", idx(ans) if ans else 0xFFFFFFFF, idx(aname), raw, 8, 0, dtype, data)
        ext = struct.pack("<IIHHHHHH", idx(ns) if ns else 0xFFFFFFFF, idx(name), 20, 20, len(el.attrib), 0, 0, 0)
        start = struct.pack("<HHIII", 0x0102, 16, 16 + len(ext) + len(attrs), 1, 0xFFFFFFFF) + ext + attrs
        children = b"".join(walk(c) for c in el)
        end = struct.pack("<HHIII", 0x0103, 16, 24, 1, 0xFFFFFFFF) + struct.pack(
            "<II", idx(ns) if ns else 0xFFFFFFFF, idx(name))
        return start + children + end

    body += walk(root)
    body += struct.pack("<HHIII", 0x0101, 16, 24, 1, 0xFFFFFFFF) + struct.pack("<II", prefix, android)

    offsets, data = [], b""
    for s in strings:
        offsets.append(len(data))
        enc = s.encode("utf-16-le")
        data += struct.pack("<H", len(s)) + enc + b"\x00\x00"
    while len(data) % 4:
        data += b"\x00"
    header = 28
    strings_start = header + 4 * len(strings)
    pool = struct.pack("<HHIIIIII", 0x0001, header, strings_start + len(data), len(strings), 0, 0,
                       strings_start, 0) + b"".join(struct.pack("<I", o) for o in offsets) + data
    payload = pool + body
    return struct.pack("<HHI", 0x0003, 8, 8 + len(payload)) + payload
