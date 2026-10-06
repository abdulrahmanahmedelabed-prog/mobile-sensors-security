"""Draws the launcher icons of both apps (run once; outputs are committed)."""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
S = 1024


def background(top, bottom):
    img = Image.new("RGBA", (S, S))
    grad = Image.new("RGBA", (1, S))
    for y in range(S):
        t = y / (S - 1)
        grad.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    img.paste(grad.resize((S, S)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=230, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    return out


def sensors_icon():
    img = background((0, 150, 136), (0, 77, 64))
    d = ImageDraw.Draw(img)
    # Phone in the middle.
    d.rounded_rectangle((392, 300, 632, 724), radius=48, outline="white", width=36)
    d.ellipse((492, 640, 532, 680), fill="white")
    # Waves on both sides: a sensor picking up the world.
    for i, r in enumerate((300, 400)):
        w = 34 - i * 6
        for start in (-40, 140):
            d.arc((512 - r, 512 - r, 512 + r, 512 + r), start=start, end=start + 80, fill="white", width=w)
    return img


def scanner_icon():
    img = background((57, 73, 171), (26, 35, 126))
    d = ImageDraw.Draw(img)
    # Shield.
    cx, top, bottom, half = 512, 220, 820, 250
    pts = [(cx, top), (cx + half, top + 90)]
    for k in range(0, 21):
        t = k / 20
        x = cx + half * math.cos(t * math.pi / 2)
        y = top + 90 + (bottom - top - 90) * math.sin(t * math.pi / 2)
        pts.append((x, y))
    pts += [(cx - x + cx, y) for x, y in reversed(pts[2:])] + [(cx - half, top + 90)]
    d.polygon(pts, fill="white")
    # Check mark.
    d.line([(400, 520), (480, 610), (640, 420)], fill=(26, 35, 126), width=70, joint="curve")
    return img


def write(img, app):
    res = ROOT / app / "android/app/src/main/res"
    for density, px in SIZES.items():
        img.resize((px, px), Image.LANCZOS).save(res / f"mipmap-{density}/ic_launcher.png", optimize=True)


if __name__ == "__main__":
    write(sensors_icon(), "sensors_app")
    write(scanner_icon(), "app_scanner")
    if "--preview" in sys.argv:
        sensors_icon().resize((256, 256)).save("/tmp/sensors_icon.png")
        scanner_icon().resize((256, 256)).save("/tmp/scanner_icon.png")
