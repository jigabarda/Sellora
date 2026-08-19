"""Regenerates the Android launcher icon from the same curve as the in-app mark.

The icon is not separate artwork: it is `SelloraLogo` expressed as PNGs, drawn
from the same bezier control points and the same accent colour, so the tile on
the home screen and the mark inside the app cannot drift apart. The only thing
the icon adds is a white ground — the app does not need one, because its canvas
is already near-white, but an icon needs something to sit on.

Run from the project root, after changing the accent or the curve:

    python tool/generate_launcher_icon.py

Writes, for every density:
  * mipmap-*/ic_launcher.png             legacy, white squircle + mark
  * mipmap-*/ic_launcher_foreground.png  adaptive foreground, mark on transparency
and once:
  * drawable/ic_launcher_background.xml  adaptive background, white
  * mipmap-anydpi-v26/ic_launcher.xml    ties the two together

Requires Pillow.
"""

import colorsys
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# lib/core/sellora_tokens.dart -> SelloraTokens.light.accent
ACCENT = (0x4F, 0x46, 0xE5)

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive icons are authored on a 108dp canvas whatever the density.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

# Drawn large and reduced, because a swept curve needs real antialiasing.
SS = 8


def shifted(rgb, d_light):
    """The accent moved in HSL, matching _SwooshPainter's gradient stops."""
    r, g, b = (c / 255 for c in rgb)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    r, g, b = colorsys.hls_to_rgb(h, min(1.0, max(0.0, l + d_light)), s)
    return tuple(round(c * 255) for c in (r, g, b))


LIGHT = shifted(ACCENT, +0.16)
DEEP = shifted(ACCENT, -0.14)

# The curve. These control points must match _SwooshPainter in
# lib/core/sellora_ui.dart, or the home screen stops matching the app.
BODY = ((0.145, 0.760), (0.345, 0.760), (0.420, 0.285), (0.700, 0.208))
TAIL = ((0.645, 0.230), (0.780, 0.192), (0.822, 0.320), (0.752, 0.430))
BODY_WIDTH = 0.205
TAIL_WIDTH = 0.090


def bezier(control, steps=240):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u**3 * control[0][0] + 3 * u * u * t * control[1][0]
            + 3 * u * t * t * control[2][0] + t**3 * control[3][0],
            u**3 * control[0][1] + 3 * u * u * t * control[1][1]
            + 3 * u * t * t * control[2][1] + t**3 * control[3][1],
        ))
    return out


def sweep(control, width_at, canvas, scale=1.0):
    """Offset a spine either side by a varying half-width -> a closed outline.

    This is the whole technique: the stroke is full where the curve turns and
    lifts away to nothing at the tip, which is what a fixed-width line cannot
    do and what makes the mark look drawn rather than assembled.
    """
    spine = bezier(control)
    n = len(spine)

    def at(a, b):
        # Scaled about the centre, for the adaptive safe zone.
        return ((0.5 + (a - 0.5) * scale) * canvas,
                (0.5 + (b - 0.5) * scale) * canvas)

    left, right = [], []
    for i, (x, y) in enumerate(spine):
        px, py = spine[max(0, i - 1)]
        nx, ny = spine[min(n - 1, i + 1)]
        dx, dy = nx - px, ny - py
        length = math.hypot(dx, dy) or 1e-6
        ox, oy = -dy / length, dx / length
        half = width_at(i / (n - 1)) / 2
        left.append(at(x + ox * half, y + oy * half))
        right.append(at(x - ox * half, y - oy * half))
    return left + right[::-1]


def body_width(t):
    """Full at the start, lifting away to a point."""
    return BODY_WIDTH * (1 - 0.84 * t)


def tail_width(t):
    """Fat in the middle, nothing at either end."""
    return TAIL_WIDTH * (0.05 + 0.95 * math.sin(math.pi * t) ** 0.7)


def blank(canvas):
    return Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))


def mask_of(canvas, points):
    m = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return m


def diagonal_gradient(canvas, a, b):
    """Top-right to bottom-left, the same direction as the widget's shader."""
    img = Image.new("RGB", (canvas, canvas))
    px = img.load()
    for y in range(canvas):
        for x in range(canvas):
            t = min(1.0, max(0.0, ((canvas - 1 - x) + y) / (2 * (canvas - 1))))
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return img


def paint(mask, canvas, alpha=255):
    g = Image.new("RGBA", (canvas, canvas))
    g.paste(diagonal_gradient(canvas, LIGHT, DEEP), (0, 0))
    g.putalpha(Image.composite(Image.new("L", (canvas, canvas), alpha),
                               Image.new("L", (canvas, canvas), 0), mask))
    return g


def draw_mark(base, canvas, scale=1.0, shadow=True):
    body = mask_of(canvas, sweep(BODY, body_width, canvas, scale))
    tail = mask_of(canvas, sweep(TAIL, tail_width, canvas, scale))

    if shadow:
        blurred = body.filter(ImageFilter.GaussianBlur(canvas * 0.038))
        dropped = blank(canvas)
        dropped.paste(
            Image.composite(
                Image.new("RGBA", (canvas, canvas), DEEP + (72,)), blank(canvas), blurred
            ),
            (0, round(canvas * 0.024)),
        )
        base = Image.alpha_composite(base, dropped)

    base = Image.alpha_composite(base, paint(body, canvas))
    # Lighter, so the hook reads as a second plane rather than a lump on the end
    # of the first.
    return Image.alpha_composite(base, paint(tail, canvas, alpha=158))


def legacy(size):
    canvas = size * SS
    tile = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 255))
    tile = draw_mark(tile, canvas)
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1), radius=canvas * 0.235, fill=255
    )
    tile.putalpha(mask)
    return tile.resize((size, size), Image.LANCZOS)


def foreground(size):
    """The mark alone, inside the adaptive safe zone.

    A launcher may crop the 108dp canvas to as little as 66dp. No cast shadow:
    the foreground is composited over a background it cannot see.
    """
    canvas = size * SS
    return draw_mark(blank(canvas), canvas, scale=0.74, shadow=False).resize(
        (size, size), Image.LANCZOS
    )


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

    background = os.path.join(RES, "drawable", "ic_launcher_background.xml")
    os.makedirs(os.path.dirname(background), exist_ok=True)
    with open(background, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tool/generate_launcher_icon.py. -->\n"
            '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:shape="rectangle">\n'
            '    <solid android:color="#FFFFFF" />\n'
            "</shape>\n"
        )
    print("wrote", os.path.relpath(background, ROOT))

    adaptive = os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml")
    os.makedirs(os.path.dirname(adaptive), exist_ok=True)
    with open(adaptive, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tool/generate_launcher_icon.py. -->\n"
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n"
        )
    print("wrote", os.path.relpath(adaptive, ROOT))


if __name__ == "__main__":
    main()
