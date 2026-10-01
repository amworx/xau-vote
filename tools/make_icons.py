"""Generate XV (XAU-Vote) launcher icons at every required density.

Brand geometry mirrors the in-app BrandMark: cobalt #2347F5 rounded square,
white "XV" in Sora ExtraBold. Kept in-repo so the icon can be regenerated
deterministically instead of being hand-edited binary art.

Usage:  python tools/make_icons.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "src" / "app"

COBALT = (0x23, 0x47, 0xF5)
WHITE = (0xFF, 0xFF, 0xFF)
FONT_TTF = APP / "assets" / "fonts" / "sora-v17-latin-800.ttf"

# Legacy ic_launcher is a plain square; web maskable icons need the glyph
# inside the 80% safe zone so platform masks never clip it.
ANDROID = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
WEB = {"Icon-192.png": 192, "Icon-512.png": 512}
WEB_MASKABLE = {"Icon-maskable-192.png": 192, "Icon-maskable-512.png": 512}
IOS = APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"


def _font(px: float) -> ImageFont.FreeTypeFont:
    """Load Sora ExtraBold at `px` tall.

    Falls back to a Pillow default if the bundled TTF is unreadable so the
    script never hard-fails on a fresh checkout.
    """
    try:
        return ImageFont.truetype(str(FONT_TTF), int(round(px)))
    except OSError:
        print(f"  ! {FONT_TTF.name} unreadable, falling back to default font")
        return ImageFont.load_default()


def render(size: int, glyph_ratio: float = 0.52, bleed: bool = True) -> Image.Image:
    """Cobalt rounded square with a centred white XV.

    `bleed=False` draws the square edge-to-edge (maskable icons, where the OS
    supplies its own shape).
    """
    ss = size * 4  # supersample, then downscale for clean edges
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    radius = 0 if not bleed else int(ss * 0.225)  # ~iOS/Android squircle ratio
    inset = 0 if not bleed else int(ss * 0.02)
    d.rounded_rectangle(
        [inset, inset, ss - inset - 1, ss - inset - 1],
        radius=radius,
        fill=COBALT + (255,),
    )

    font = _font(ss * glyph_ratio)
    box = d.textbbox((0, 0), "XV", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    # Centre on the glyph's visual box, compensating for the ascent offset
    # textbbox reports, so the monogram looks optically centred.
    x = (ss - w) / 2 - box[0]
    y = (ss - h) / 2 - box[1]
    d.text((x, y), "XV", font=font, fill=WHITE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    if not FONT_TTF.exists():
        print(f"missing {FONT_TTF}", file=sys.stderr)
        return 1

    written = 0

    # Android launcher icons.
    for folder, size in ANDROID.items():
        out_dir = APP / "android" / "app" / "src" / "main" / "res" / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for name in ("ic_launcher.png", "ic_launcher_round.png", "ic_launcher_foreground.png"):
            render(size).save(out_dir / name)
            written += 1

    # Web icons.
    web = APP / "web" / "icons"
    web.mkdir(parents=True, exist_ok=True)
    for name, size in WEB.items():
        render(size).save(web / name)
        written += 1
    for name, size in WEB_MASKABLE.items():
        render(size, glyph_ratio=0.42, bleed=False).save(web / name)
        written += 1
    render(64).save(APP / "web" / "favicon.png")
    written += 1

    # iOS: a single 1024 marketing icon is what the asset catalog needs;
    # the existing Contents.json references are left untouched.
    if IOS.exists():
        render(1024).save(IOS / "AppIcon-1024x1024.png")
        written += 1
    else:
        print(f"  ! {IOS} not found - skipped iOS icon")

    print(f"wrote {written} icon files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())