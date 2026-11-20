#!/usr/bin/env python3
"""Regenerate the Android launcher icons from a square logo.

Run from the repository root:

    python3 tool/gen_launcher_icons.py /path/to/LogoBW.png

Requires Pillow (`pip install pillow`). It writes:

  * `res/drawable/ic_launcher_foreground.png`  — 1080x1080, transparent, the
    artwork scaled into Android's 66% safe zone (the outer third is masked on
    circular launchers);
  * `res/drawable/ic_launcher_monochrome.png`  — same geometry, opaque-black
    silhouette for Android 13+ themed icons;
  * `res/mipmap-{m,h,xh,xxh,xxxhdpi}/ic_launcher.png` — 48/72/96/144/192 with
    the brand background baked in, for API < 26.

The background colour MUST match `res/values/colors.xml`
(`ic_launcher_background`) — the adaptive icon paints it behind the foreground.
"""
import sys

from PIL import Image

RES = "android/app/src/main/res"
# Pillow ≥ 10 moved the resampling filters to Image.Resampling.
LANCZOS = Image.Resampling.LANCZOS  # type: ignore[attr-defined]
BG = (0xF6, 0xF1, 0xE7, 0xFF)  # AppColors warm plaster (ic_launcher_background)
ADAPTIVE = 1080
SAFE_ZONE = 0.66   # of the 108dp adaptive canvas
LEGACY_FILL = 0.78  # legacy icons are masked by the launcher, so fill more


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    logo = Image.open(sys.argv[1]).convert("RGBA")
    if logo.width != logo.height:
        print(f"warning: {logo.width}x{logo.height} is not square", file=sys.stderr)
    art = logo.crop(logo.getchannel("A").getbbox())

    def place(size, frac, background=None, silhouette=False):
        target = int(size * frac)
        scale = target / max(art.size)
        w = max(1, round(art.width * scale))
        h = max(1, round(art.height * scale))
        layer_art = art.resize((w, h), LANCZOS)
        if silhouette:
            layer_art = Image.merge(
                "RGBA",
                (Image.new("L", (w, h), 0xFF), Image.new("L", (w, h), 0xFF),
                 Image.new("L", (w, h), 0xFF), layer_art.getchannel("A")),
            )
        layer = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))
        layer.paste(layer_art, ((size - w) // 2, (size - h) // 2), layer_art)
        return layer

    def save(path, img):
        img.save(path, "PNG", optimize=True)
        print("wrote", path, img.size)

    save(f"{RES}/drawable/ic_launcher_foreground.png",
         place(ADAPTIVE, SAFE_ZONE))
    save(f"{RES}/drawable/ic_launcher_monochrome.png",
         place(ADAPTIVE, SAFE_ZONE, silhouette=True))
    for dpi, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(f"{RES}/mipmap-{dpi}/ic_launcher.png",
             place(px, LEGACY_FILL, background=BG))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
