"""Regenerates the Android launcher icon from the same shapes as the in-app mark.

The icon is not hand-drawn art: it is the `SelloraLogo` widget expressed as
PNGs, so the tile on the home screen and the mark inside the app cannot drift
apart. Both take the accent colour, the 28%-of-the-side squircle radius, and the
receipt geometry — the fractions below are the same ones _ReceiptMarkPainter
uses, so the two cannot drift apart.

Run from the project root, after changing the accent or the mark:

    python tool/generate_launcher_icon.py

Writes, for every density:
  * mipmap-*/ic_launcher.png             legacy, full-bleed squircle
  * mipmap-*/ic_launcher_foreground.png  adaptive foreground, mark on transparency
and once:
  * drawable/ic_launcher_background.xml  adaptive background, the gradient
  * mipmap-anydpi-v26/ic_launcher.xml    ties the two together

Requires Pillow.
"""

import colorsys
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# lib/core/sellora_tokens.dart -> SelloraTokens.light.accent
ACCENT = (0x4F, 0x46, 0xE5)

# Legacy icon: the launcher scales one bitmap per bucket.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive icons are authored on a 108dp canvas whatever the density.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

# Drawn large and reduced, so the squircle and the torn edge get real
# antialiasing instead of the stair-stepping PIL leaves on a 48px shape.
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


# The receipt, in fractions of the tile. These must match
# _ReceiptMarkPainter in lib/core/sellora_ui.dart, or the icon on the home
# screen stops matching the mark inside the app.
LEFT, RIGHT = 0.29, 0.71
BODY_TOP, BODY_BOTTOM, TIP = 0.215, 0.665, 0.755
CORNER = 0.055
TEETH = 4
LINE_LEFT, LINE_RIGHT, SHORT_RIGHT = 0.365, 0.635, 0.545
LINE_HEIGHT = 0.058
LINE_TOPS = (0.305, 0.415, 0.525)


def receipt_mask(canvas, scale=1.0, offset=0.0):
    """A mask of the receipt with its ruled lines punched out.

    `scale` shrinks the mark about the centre, for the adaptive foreground,
    where a launcher may crop away everything outside the middle 66 of 108dp.
    """

    def at(f):
        return (0.5 + (f - 0.5) * scale + offset) * canvas

    mask = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(mask)

    # Body: a rectangle with two rounded top corners. Drawn as a rounded
    # rectangle with the bottom half squared off by a plain rectangle over it.
    radius = CORNER * scale * canvas
    draw.rounded_rectangle(
        (at(LEFT), at(BODY_TOP), at(RIGHT), at(BODY_BOTTOM)),
        radius=radius,
        fill=255,
    )
    draw.rectangle(
        (at(LEFT), at(BODY_TOP) + radius, at(RIGHT), at(BODY_BOTTOM)), fill=255
    )

    # Torn bottom edge.
    span = RIGHT - LEFT
    points = [(at(LEFT), at(BODY_BOTTOM))]
    for i in range(TEETH):
        points.append((at(LEFT + span * (i * 2 + 1) / (TEETH * 2)), at(TIP)))
        points.append((at(LEFT + span * (i * 2 + 2) / (TEETH * 2)), at(BODY_BOTTOM)))
    draw.polygon(points, fill=255)

    # Ruled lines, cut back out of the shape.
    for i, top in enumerate(LINE_TOPS):
        right = SHORT_RIGHT if i == len(LINE_TOPS) - 1 else LINE_RIGHT
        draw.rounded_rectangle(
            (at(LINE_LEFT), at(top), at(right), at(top + LINE_HEIGHT)),
            radius=LINE_HEIGHT * scale * canvas / 2,
            fill=0,
        )

    return mask


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
    white = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 255))
    tile = Image.alpha_composite(tile, Image.composite(
        white, Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0)),
        receipt_mask(canvas)))
    return tile.resize((size, size), Image.LANCZOS)


def foreground(size):
    """The mark alone, inside the adaptive safe zone.

    A launcher may crop the 108dp canvas to as little as 66dp, so anything
    outside that centre circle can be shaved off. The mark is kept well within
    it rather than filling the tile the way the legacy icon does.
    """
    canvas = size * SS
    white = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 255))
    img = Image.composite(
        white,
        Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0)),
        # 0.72 keeps the whole mark inside the 66-of-108dp safe zone, so a
        # launcher cropping to a circle cannot clip the torn edge.
        receipt_mask(canvas, scale=0.72),
    )
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
