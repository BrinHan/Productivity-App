"""Turns the frames from capture_test.dart into the README's images and GIFs.

    python tool/readme/make_media.py <frames dir>

Writes docs/media/ at the repo root. Needs Pillow (pip install pillow).
"""

import sys
from pathlib import Path

from PIL import Image

FRAMES = Path(sys.argv[1])
OUT = Path(__file__).resolve().parents[3] / "docs" / "media"


def still(name, width, crop_h=None, out=None):
    """crop_h: keep the top part only, as a fraction of the height."""
    im = Image.open(FRAMES / f"{name}.png").convert("RGB")
    if crop_h:
        im = im.crop((0, 0, im.width, round(im.height * crop_h)))
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    path = OUT / f"{out or name}.png"
    im.save(path, optimize=True)
    return path


def gif(clip, width, crop_h=None, step=1, ms=40, out=None):
    """Every [step]th frame, [ms] apart on screen. [clip] may be a list of
    clips to play one after another."""
    clips = clip if isinstance(clip, list) else [clip]
    files = [f for c in clips for f in sorted((FRAMES / c).glob("*.png"))[::step]]
    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if crop_h:
            im = im.crop((0, 0, im.width, round(im.height * crop_h)))
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        frames.append(im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    path = OUT / f"{out or clip}.gif"
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=ms * step, loop=0, optimize=True, disposal=1)
    return path


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    made = [
        still("map", 1600),
        still("island_home", 1200, crop_h=0.42),
        still("island_today", 1200, crop_h=0.95),
        still("planner_home_dark", 1600),
        still("planner_home_light", 1600),
        still("planner_week_dark", 1600),
        still("planner_tasks_dark", 1600),
        gif("map_day", 640, ms=50),
        gif("island_tour", 760, step=2),
        gif("island_music", 640, crop_h=0.56, step=2),
        gif("picker", 640, crop_h=0.92, step=2),
        gif(["unlock_face", "unlock_fingerprint", "unlock_pin"], 420, crop_h=0.65, step=2, out="unlock"),
    ]
    for p in made:
        print(f"{p.name:28} {p.stat().st_size / 1024:8.0f} KB")


if __name__ == "__main__":
    main()
