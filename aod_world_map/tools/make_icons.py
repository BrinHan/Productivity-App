"""Draws the Meridian logo and writes every icon the app ships.

The mark is the AOD face in miniature: a red dot globe on black, lit past one
meridian and dark before it, with your location dot on that line.

    python tools/make_icons.py

Writes assets/brand/*, windows/runner/resources/app_icon.ico and
assets/tray_icon.ico. Needs Pillow (pip install pillow).
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent

RED = (255, 59, 48)
NIGHT = (74, 22, 18)
NIGHT_FILL = (96, 28, 22)
USER = (255, 214, 210)
BG_TOP = (28, 10, 9)
BG_BOTTOM = (4, 4, 5)

MERIDIAN_LON = -28.0  # degrees; everything east of it is in daylight
USER_LAT = 32.0
SS = 4  # supersampling factor


def _project(lat, lon, cx, cy, r):
    la, lo = math.radians(lat), math.radians(lon)
    return cx + r * math.cos(la) * math.sin(lo), cy - r * math.sin(la)


def _meridian_points(cx, cy, r, steps=180, reach=82):
    return [_project(-reach + 2 * reach * i / steps, MERIDIAN_LON, cx, cy, r) for i in range(steps + 1)]


def _lit_mask(size, cx, cy, r):
    """The globe east of the meridian: the right half plus the ellipse the meridian bounds."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    a = r * abs(math.sin(math.radians(MERIDIAN_LON)))
    d.pieslice((cx - r, cy - r, cx + r, cy + r), -90, 90, fill=255)
    d.ellipse((cx - a, cy - r, cx + a, cy + r), fill=255)
    return m


def _background(size, inset, radius):
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / (size - 1)
        gd.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, size - inset, size - inset), radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def _glow(img, layer, blur):
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(blur)))


def detailed(px, with_bg=True):
    """Full mark: lat/long dot globe, meridian line, location dot."""
    s = px * SS
    img = _background(s, s * 0.04, s * 0.22) if with_bg else Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cx = cy = s / 2
    r = s * 0.33

    # Faint rim so the night side still reads as a globe.
    rim = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse((cx - r, cy - r, cx + r, cy + r), outline=RED + (60,), width=max(1, round(r * 0.014)))
    img = Image.alpha_composite(img, rim)

    dots = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    step = 12
    base = r * 0.034
    for lat in range(-78, 79, step):
        for lon in range(-84, 85, step):
            x, y = _project(lat, lon + step / 2, cx, cy, r)
            depth = math.sqrt(max(0.0, 1 - ((x - cx) ** 2 + (y - cy) ** 2) / r**2))
            if depth < 0.3:
                continue
            rad = base * (0.45 + 0.55 * depth)
            lit = lon + step / 2 > MERIDIAN_LON
            dd.ellipse((x - rad, y - rad, x + rad, y + rad), fill=(RED + (255,)) if lit else (NIGHT + (255,)))
    img = _glow(img, dots, r * 0.03)
    img = Image.alpha_composite(img, dots)

    line = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(line).line(_meridian_points(cx, cy, r), fill=RED + (255,), width=round(r * 0.045), joint="curve")
    img = _glow(img, line, r * 0.06)
    img = Image.alpha_composite(img, line)

    ux, uy = _project(USER_LAT, MERIDIAN_LON, cx, cy, r)
    you = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    yd = ImageDraw.Draw(you)
    halo = r * 0.17
    yd.ellipse((ux - halo, uy - halo, ux + halo, uy + halo), fill=RED + (90,))
    core = r * 0.085
    yd.ellipse((ux - core, uy - core, ux + core, uy + core), fill=USER + (255,))
    img = _glow(img, you, r * 0.05)
    img = Image.alpha_composite(img, you)
    return img.resize((px, px), Image.LANCZOS)


def simple(px, with_bg=True):
    """Small sizes: solid day and night sides with the location dot, no dot grid."""
    s = px * SS
    img = _background(s, 0, s * 0.22) if with_bg else Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cx = cy = s / 2
    r = s * (0.36 if with_bg else 0.46)

    globe = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(globe).ellipse((cx - r, cy - r, cx + r, cy + r), fill=NIGHT_FILL + (255,))
    lit = Image.new("RGBA", (s, s), RED + (255,))
    globe.paste(lit, (0, 0), _lit_mask(s, cx, cy, r))
    ux, uy = _project(USER_LAT, MERIDIAN_LON, cx, cy, r)
    dot = r * 0.2
    ImageDraw.Draw(globe).ellipse((ux - dot, uy - dot, ux + dot, uy + dot), fill=USER + (255,))
    img = Image.alpha_composite(img, globe)
    return img.resize((px, px), Image.LANCZOS)


def icon_frames(sizes, with_bg=True):
    return [(simple if n <= 64 else detailed)(n, with_bg) for n in sizes]


def save_ico(path, frames):
    path.parent.mkdir(parents=True, exist_ok=True)
    big = max(frames, key=lambda f: f.width)
    big.save(path, format="ICO", sizes=[(f.width, f.height) for f in frames], append_images=[f for f in frames if f is not big])


def wordmark(height=360):
    mark = detailed(height)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Geist.ttf"), round(height * 0.34))
    try:
        font.set_variation_by_axes([600])
    except Exception:
        pass
    text = "Meridian"
    l, t, rr, b = font.getbbox(text)
    w = height + round(height * 0.08) + (rr - l) + round(height * 0.3)
    out = Image.new("RGBA", (w, height), BG_BOTTOM + (255,))
    out.alpha_composite(mark)
    ImageDraw.Draw(out).text((height + round(height * 0.08) - l, (height - (b - t)) / 2 - t), text, font=font, fill=(245, 245, 247))
    return out


def main():
    brand = ROOT / "assets/brand"
    brand.mkdir(parents=True, exist_ok=True)
    detailed(1024).save(brand / "meridian_logo.png")
    detailed(1024, with_bg=False).save(brand / "meridian_mark.png")
    wordmark().save(brand / "meridian_wordmark.png")
    save_ico(ROOT / "windows/runner/resources/app_icon.ico", icon_frames([16, 20, 24, 32, 40, 48, 64, 128, 256]))
    # Tray: no tile behind it, so it sits on the taskbar like the system icons.
    save_ico(ROOT / "assets/tray_icon.ico", icon_frames([16, 20, 24, 32, 48, 64], with_bg=False))
    print("wrote", brand, "and both .ico files")


if __name__ == "__main__":
    main()
