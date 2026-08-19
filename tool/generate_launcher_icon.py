"""Regenerates the Android launcher icon from the same shapes as the in-app mark.

The icon is not hand-drawn art: it is the `SelloraLogo` widget expressed as
PNGs, so the tile on the home screen and the mark inside the app cannot drift
apart. Both take the accent colour, the 28%-of-the-side squircle radius, and the
slip geometry — the fractions below are the same ones _SlipMarkPainter uses,
so the two cannot drift apart.

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

from PIL import Image, ImageDraw, ImageFilter

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


# The slip, in fractions of the tile. These must match _SlipMarkPainter in
# lib/core/sellora_ui.dart, or the icon on the home screen stops matching the
# mark inside the app.
LEFT, RIGHT = 0.31, 0.69
BODY_TOP, BODY_BOTTOM, TIP = 0.19, 0.655, 0.745
CORNER = 0.05
TEETH = 4
TILT = -8  # degrees

# Ruled lines: same left edge, growing right. That is the whole idea.
LINE_LEFT = 0.385
LINE_TOPS = (0.295, 0.405, 0.515)
LINE_WIDTHS = (0.110, 0.165, 0.230)
LINE_HEIGHT = 0.055

# Paper: white at the top, a whisper of the accent at the torn edge.
PAPER_TOP = (255, 255, 255)
PAPER_BOTTOM = (233, 232, 250)


def vertical_gradient(size, a, b):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        row = tuple(round(a[i] + (b[i] - a[i]) * y / (size - 1)) for i in range(3))
        for x in range(size):
            px[x, y] = row
    return img


def slip_masks(canvas, scale=1.0):
    """The slip silhouette, and the slip with its ruled lines punched out.

    Two masks because the shadow comes from the silhouette: light does not fall
    through the lines. `scale` shrinks the mark about the centre, for the
    adaptive foreground, where a launcher may crop to the middle 66 of 108dp.
    """

    def at(f):
        return (0.5 + (f - 0.5) * scale) * canvas

    solid = Image.new("L", (canvas, canvas), 0)
    d = ImageDraw.Draw(solid)
    radius = CORNER * scale * canvas
    d.rounded_rectangle(
        (at(LEFT), at(BODY_TOP), at(RIGHT), at(BODY_BOTTOM)),
        radius=radius,
        fill=255,
    )
    d.rectangle(
        (at(LEFT), at(BODY_TOP) + radius, at(RIGHT), at(BODY_BOTTOM)), fill=255
    )

    span = RIGHT - LEFT
    points = [(at(LEFT), at(BODY_BOTTOM))]
    for i in range(TEETH):
        points.append((at(LEFT + span * (i * 2 + 1) / (TEETH * 2)), at(TIP)))
        points.append((at(LEFT + span * (i * 2 + 2) / (TEETH * 2)), at(BODY_BOTTOM)))
    d.polygon(points, fill=255)

    punched = solid.copy()
    pd = ImageDraw.Draw(punched)
    for top, width in zip(LINE_TOPS, LINE_WIDTHS):
        pd.rounded_rectangle(
            (at(LINE_LEFT), at(top), at(LINE_LEFT + width), at(top + LINE_HEIGHT)),
            radius=LINE_HEIGHT * scale * canvas / 2,
            fill=0,
        )

    spin = dict(resample=Image.BICUBIC, center=(canvas / 2, canvas / 2))
    return solid.rotate(TILT, **spin), punched.rotate(TILT, **spin)


def blank(canvas):
    return Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))


def draw_mark(base, canvas, scale=1.0, shadow=True):
    """Casts the slip's shadow, then lays the tinted paper over it."""
    solid, punched = slip_masks(canvas, scale)

    if shadow:
        blurred = solid.filter(ImageFilter.GaussianBlur(canvas * 0.045))
        dropped = blank(canvas)
        dropped.paste(
            Image.composite(
                Image.new("RGBA", (canvas, canvas), (26, 20, 70, 87)),
                blank(canvas),
                blurred,
            ),
            (0, round(canvas * 0.028)),
        )
        base = Image.alpha_composite(base, dropped)

    paper = Image.new("RGBA", (canvas, canvas))
    paper.paste(vertical_gradient(canvas, PAPER_TOP, PAPER_BOTTOM), (0, 0))
    paper.putalpha(255)
    return Image.alpha_composite(base, Image.composite(paper, blank(canvas), punched))


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
    tile = tile.convert("RGBA")

    # The light, from the top left. Without it the tile is a flat swatch and the
    # whole mark reads as clip art on a colour.
    glow = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(glow).ellipse(
        (-canvas * 0.35, -canvas * 0.50, canvas * 0.80, canvas * 0.50), fill=78
    )
    glow = glow.filter(ImageFilter.GaussianBlur(canvas * 0.18))
    tile = Image.alpha_composite(
        tile,
        Image.composite(
            Image.new("RGBA", (canvas, canvas), (255, 255, 255, 255)),
            blank(canvas),
            glow,
        ),
    )

    tile = draw_mark(tile, canvas)
    tile.putalpha(Image.composite(mask, Image.new("L", (canvas, canvas), 0), mask))
    return tile.resize((size, size), Image.LANCZOS)


def foreground(size):
    """The mark alone, inside the adaptive safe zone.

    A launcher may crop the 108dp canvas to as little as 66dp, so anything
    outside that centre circle can be shaved off. The mark is kept well within
    it rather than filling the tile the way the legacy icon does.
    """
    canvas = size * SS
    # 0.72 keeps the whole mark inside the 66-of-108dp safe zone, so a launcher
    # cropping to a circle cannot clip the torn edge. No cast shadow here: the
    # foreground is composited over a background it cannot see.
    img = draw_mark(blank(canvas), canvas, scale=0.72, shadow=False)
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
