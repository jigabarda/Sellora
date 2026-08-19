"""Regenerates the Android launcher icon from the same shapes as the in-app mark.

The icon is not hand-drawn art: it is the `SelloraLogo` widget expressed as
PNGs, so the tile on the home screen and the mark inside the app cannot drift
apart. Both take the accent colour, the 28%-of-the-side squircle radius, and the
letter S from PlusJakartaSans ExtraBold — the same cut the wordmark uses.

Run from the project root, after changing the accent or the mark:

    python tool/generate_launcher_icon.py

Writes, for every density:
  * mipmap-*/ic_launcher.png             legacy, full-bleed squircle
  * mipmap-*/ic_launcher_foreground.png  adaptive foreground, S on transparency
and once:
  * drawable/ic_launcher_background.xml  adaptive background, the gradient
  * mipmap-anydpi-v26/ic_launcher.xml    ties the two together

Requires Pillow.
"""

import colorsys
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
FONT = os.path.join(ROOT, "assets", "fonts", "PlusJakartaSans-ExtraBold.ttf")

# lib/core/sellora_tokens.dart -> SelloraTokens.light.accent
ACCENT = (0x4F, 0x46, 0xE5)

# Legacy icon: the launcher scales one bitmap per bucket.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive icons are authored on a 108dp canvas whatever the density.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

# Drawn large and reduced, so the squircle and the letter get real antialiasing
# instead of the stair-stepping PIL leaves on a 48px shape.
SS = 8


def shifted(rgb, d_light, d_sat=0.0):
    """The accent moved in HSL, matching SelloraLogo's gradient stops."""
    r, g, b = (c / 255 for c in rgb)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = min(1.0, max(0.0, l + d_light))
    s = min(1.0, max(0.0, s + d_sat))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return tuple(round(c * 255) for c in (r, g, b))


TOP = shifted(ACCENT, +0.10, -0.05)
BOTTOM = shifted(ACCENT, -0.16)


def diagonal_gradient(size):
    """Top-left to bottom-right, the same direction as the widget's gradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            # Distance along the diagonal, normalised.
            t = (x + y) / (2 * (size - 1)) if size > 1 else 0
            px[x, y] = tuple(
                round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)
            )
    return img


def fitted_font(target_height, text="S"):
    """A font size whose glyph is `target_height` tall, found by measuring."""
    size = max(8, int(target_height * 1.4))
    for _ in range(60):
        font = ImageFont.truetype(FONT, size)
        box = font.getbbox(text)
        height = box[3] - box[1]
        if height == 0:
            break
        if abs(height - target_height) <= 1:
            return font
        size = max(8, round(size * target_height / height))
    return ImageFont.truetype(FONT, size)


def draw_s(img, canvas, cap_fraction):
    """Centres the S on its ink, not on its em box, which sits high."""
    font = fitted_font(canvas * cap_fraction)
    draw = ImageDraw.Draw(img)
    box = font.getbbox("S")
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text(
        ((canvas - w) / 2 - box[0], (canvas - h) / 2 - box[1]),
        "S",
        font=font,
        fill=(255, 255, 255, 255),
    )


def legacy(size):
    canvas = size * SS
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1),
        radius=canvas * 0.28,  # same proportion as SelloraLogo
        fill=255,
    )
    tile = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    tile.paste(diagonal_gradient(canvas), (0, 0))
    tile.putalpha(mask)
    draw_s(tile, canvas, 0.42)
    return tile.resize((size, size), Image.LANCZOS)


def foreground(size):
    """The S alone, inside the adaptive safe zone.

    A launcher may crop the 108dp canvas to as little as 66dp, so anything
    outside that centre circle can be shaved off. The glyph is kept well within
    it rather than filling the tile the way the legacy icon does.
    """
    canvas = size * SS
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw_s(img, canvas, 0.30)
    return img.resize((size, size), Image.LANCZOS)


def write(path, image):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def main():
    for bucket, size in LEGACY.items():
        write(os.path.join(RES, f"mipmap-{bucket}", "ic_launcher.png"), legacy(size))

    for bucket, size in ADAPTIVE.items():
        write(
            os.path.join(RES, f"mipmap-{bucket}", "ic_launcher_foreground.png"),
            foreground(size),
        )

    def hexed(rgb):
        return "#%02X%02X%02X" % rgb

    background = os.path.join(RES, "drawable", "ic_launcher_background.xml")
    os.makedirs(os.path.dirname(background), exist_ok=True)
    with open(background, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by tool/generate_launcher_icon.py. -->\n'
            '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:shape="rectangle">\n'
            "    <gradient\n"
            f'        android:startColor="{hexed(TOP)}"\n'
            f'        android:endColor="{hexed(BOTTOM)}"\n'
            '        android:angle="315"\n'
            '        android:type="linear" />\n'
            "</shape>\n"
        )
    print("wrote", os.path.relpath(background, ROOT))

    adaptive = os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml")
    os.makedirs(os.path.dirname(adaptive), exist_ok=True)
    with open(adaptive, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by tool/generate_launcher_icon.py. -->\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n"
        )
    print("wrote", os.path.relpath(adaptive, ROOT))


if __name__ == "__main__":
    main()
