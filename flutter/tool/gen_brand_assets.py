#!/usr/bin/env python3
"""Generates the app icon and splash images (exactly as the design "App icon · Splash", 1024 coordinate system).

    python3 tool/gen_brand_assets.py
    dart run flutter_launcher_icons && dart run flutter_native_splash:create

Drawing: white ring (speaker LED ring) + light-green dot at the top (standby LED) + three bars in the center (speech), on #0B6E6D.
The font IBM Plex Sans KR (OFL) is not kept in the repository; it is downloaded to ~/.cache/aipa-fonts on first run.
The resulting PNGs are saved to assets/brand/ and committed to the repository.
"""
import pathlib
import urllib.request

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "brand"
FONT_DIR = pathlib.Path.home() / ".cache" / "aipa-fonts"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/ibmplexsanskr/IBMPlexSansKR-{}.ttf"

ACCENT = (0x0B, 0x6E, 0x6D, 255)
LED = (0x9B, 0xE7, 0xC4, 255)
WHITE = (255, 255, 255, 255)
SUBTLE = (0xD6, 0xF0, 0xEE, 255)
SS = 4  # draw at 4x, then shrink to smooth the edges


def glyph(size, *, scale=1.0, background=None, led=True, mono=False):
    """Draws the 1024-unit artwork at size×size. If scale<1, shrinks it toward the center (adaptive icon safe zone)"""
    big = size * SS
    img = Image.new("RGBA", (big, big), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / 1024 * scale
    off = big * (1 - scale) / 2

    def p(v):
        return off + v * k

    # ring: center 512, radius 300, thickness 56
    r_out, r_in = (300 + 28) * k, (300 - 28) * k
    c = p(512)
    d.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=WHITE)
    d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=background or (0, 0, 0, 0))
    # Standby LED dot (white in the monochrome icon)
    if led:
        rr = 38 * k
        cy = p(212)
        d.ellipse([c - rr, cy - rr, c + rr, cy + rr], fill=WHITE if mono else LED)
    # three bars: (x, y, height), width 56, rounded ends
    for x, y, h in ((384, 442, 140), (484, 372, 280), (584, 442, 140)):
        d.rounded_rectangle([p(x), p(y), p(x + 56), p(y + h)], radius=28 * k, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def font(weight, px):
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    path = FONT_DIR / f"IBMPlexSansKR-{weight}.ttf"
    if not path.exists():
        urllib.request.urlretrieve(FONT_URL.format(weight), path)
    return ImageFont.truetype(str(path), px)


def branding(width=800, height=320):
    """Bottom of the splash: "AI-PA / Our family's voice assistant" (Android 12 branding max 200×80dp = 800×320px @4x)"""
    big = Image.new("RGBA", (width * SS, height * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    title = font("Bold", 88 * SS)
    sub = font("Regular", 52 * SS)
    cx = width * SS / 2
    d.text((cx, height * SS * 0.40), "AI-PA", font=title, fill=WHITE, anchor="mm")
    d.text((cx, height * SS * 0.78), "Our family's voice assistant", font=sub, fill=SUBTLE, anchor="mm")
    return big.resize((width, height), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # App icon (iOS and older Android): fills the background; the OS rounds the corners
    glyph(1024, background=ACCENT).save(OUT / "icon.png")
    # Android adaptive icon foreground: no background, shrunk inside the safe zone (66% diameter) → ring diameter about 54%
    glyph(1024, scale=0.84).save(OUT / "icon_foreground.png")
    # Android 13 themed icon: uses a single color (white)
    glyph(1024, scale=0.84, mono=True).save(OUT / "icon_monochrome.png")
    # Splash center artwork: design 168dp @4x
    glyph(672).save(OUT / "splash_logo.png")
    # Android 12+ splash icon: the artwork must fit in a 192dp-diameter circle inside a 288dp canvas (1152 @4x)
    glyph(1152).save(OUT / "splash_android12.png")
    branding().save(OUT / "splash_branding.png")
    for f in sorted(OUT.glob("*.png")):
        print(f"{f.relative_to(ROOT)}  {Image.open(f).size}")


if __name__ == "__main__":
    main()
