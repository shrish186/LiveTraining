"""Draws the app icon (placeholder brand mark) and writes every iOS and Android size.

    python tool/make_icon.py      # from mobile/, needs Pillow

A ring (readiness/recovery, as on the Home screen) around a motion trace with one tall impact
spike. Replace with a designer's icon later; keep the 1024 px master free of transparency (App Store rule).
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

BG = (10, 11, 13)
ACCENT = (76, 201, 240)
LOAD = (155, 135, 245)
ROOT = Path(__file__).resolve().parent.parent


def master(size: int = 1024) -> Image.Image:
    s = 4  # draw large, then downsample for smooth edges
    n = size * s
    img = Image.new("RGB", (n, n), BG)
    d = ImageDraw.Draw(img)
    c, r, w = n / 2, n * 0.34, n * 0.055
    d.arc((c - r, c - r, c + r, c + r), start=-90, end=-90 + 360 * 0.78, fill=ACCENT, width=int(w))
    d.arc((c - r, c - r, c + r, c + r), start=-90 + 360 * 0.80, end=-90 + 360 * 0.98, fill=LOAD, width=int(w))
    # motion trace: small strides, one big impact spike
    pts = []
    x0, x1 = c - r * 0.62, c + r * 0.62
    for i in range(201):
        f = i / 200
        x = x0 + (x1 - x0) * f
        y = c + r * 0.08 * math.sin(f * math.pi * 8) * (1 - abs(f - 0.6) * 1.2)
        if 0.56 < f < 0.64:
            y -= r * 0.62 * (1 - abs(f - 0.6) / 0.04)
        pts.append((x, y))
    d.line(pts, fill=(242, 244, 247), width=int(n * 0.03), joint="curve")
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    big = master()
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for img in json.loads((ios / "Contents.json").read_text())["images"]:
        pt = float(img["size"].split("x")[0])
        px = round(pt * int(img["scale"][0]))
        big.resize((px, px), Image.LANCZOS).save(ios / img["filename"])
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in android.items():
        out = ROOT / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png"
        if out.exists():
            big.resize((px, px), Image.LANCZOS).save(out)
    print("icons written")


if __name__ == "__main__":
    main()
