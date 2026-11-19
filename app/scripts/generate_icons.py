#!/usr/bin/env python3
"""Generate Aldia's original geometric A, without fonts or downloaded artwork.

Run from any directory: python3 app/scripts/generate_icons.py
Requires Pillow on the developer machine only; no Flutter dependency.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parents[1]
RES = APP / "android/app/src/main/res"
ASSETS = APP / "ios/Runner/Assets.xcassets"
GRAPHITE = "#242424"


def icon(size, transparent=False, mark_scale=1.0):
    # Supersampling keeps the smallest notification/settings icons crisp.
    canvas = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0) if transparent else GRAPHITE)
    draw = ImageDraw.Draw(canvas)

    def points(coords):
        return [(round((0.5 + (x - 0.5) * mark_scale) * size * 4),
                 round((0.5 + (y - 0.5) * mark_scale) * size * 4)) for x, y in coords]

    draw.polygon(points([(0.5, 0.23), (0.77, 0.77), (0.62, 0.77),
                         (0.55, 0.61), (0.45, 0.61), (0.38, 0.77), (0.23, 0.77)]), fill="white")
    draw.polygon(points([(0.5, 0.40), (0.44, 0.53), (0.56, 0.53)]),
                 fill=(0, 0, 0, 0) if transparent else GRAPHITE)
    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)
    return canvas if transparent else canvas.convert("RGB")


def save(path, size, transparent=False, mark_scale=1.0):
    path.parent.mkdir(parents=True, exist_ok=True)
    icon(size, transparent, mark_scale).save(path, optimize=True)


def main():
    for density, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        save(RES / f"mipmap-{density}/ic_launcher.png", round(48 * scale))
        # Fit every corner inside Android's central 66 dp safe circle on a 108 dp layer.
        save(RES / f"mipmap-{density}/ic_launcher_foreground.png", round(108 * scale), True, 0.72)
        save(RES / f"drawable-{density}/launch_mark.png", round(128 * scale), True)
    catalog = ASSETS / "AppIcon.appiconset"
    entries = json.loads((catalog / "Contents.json").read_text())["images"]
    for entry in entries:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x")))
        save(catalog / entry["filename"], size)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        save(ASSETS / f"LaunchImage.imageset/LaunchImage{suffix}.png", 128 * scale, True)
    print("Generated Android legacy/adaptive icons, splash marks, and all iOS AppIcon/LaunchImage sizes.")


if __name__ == "__main__":
    main()
