#!/usr/bin/env python3
"""Build the app icon sizes from a source PNG (a rounded tile like assets/icon.png).

    python3 tools/make-app-icons.py                 # every assets/icon*.png
    python3 tools/make-app-icons.py assets/icon-netlab.png

assets/icon.png        -> icons/app/org.muddyblack.clabWidget-<n>.png  (the "clab" icon)
assets/icon-<name>.png -> icons/app/<name>-<n>.png                     (e.g. "netlab")

16-128 px use the symbol (the tile's centre, no text, rounded again);
256 px is the full tile. Needs Pillow. The symbol crop assumes the layout of
assets/icon.png (emblem centred slightly above middle, text at the bottom), so
a new icon in the same style needs no tweaking.
"""

import glob
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "package", "contents", "icons", "app")
SMALL = (16, 22, 32, 48, 64, 128)
FULL = (256,)
# Symbol crop as fractions of the source (measured on the 1254 px assets/icon.png).
CROP_X, CROP_Y, CROP_SIZE, CORNER = 208 / 1254, 100 / 1254, 840 / 1254, 160 / 840


def prefix_for(path):
    base = os.path.splitext(os.path.basename(path))[0]
    return "org.muddyblack.clabWidget" if base == "icon" else base.removeprefix("icon-")


def symbol(img):
    w, h = img.size
    s = round(CROP_SIZE * min(w, h))
    x, y = round(CROP_X * w), round(CROP_Y * h)
    tile = img.crop((x, y, x + s, y + s))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=round(CORNER * s), fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    return out


def build(path):
    img = Image.open(path).convert("RGBA")
    prefix = prefix_for(path)
    sym = symbol(img)
    for n in SMALL:
        sym.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, f"{prefix}-{n}.png"), optimize=True)
    for n in FULL:
        img.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, f"{prefix}-{n}.png"), optimize=True)
    print(f"{os.path.relpath(path, ROOT)} -> icons/app/{prefix}-{{{','.join(map(str, SMALL + FULL))}}}.png")


def main(args):
    os.makedirs(OUT, exist_ok=True)
    sources = args or sorted(glob.glob(os.path.join(ROOT, "assets", "icon*.png")))
    sources = [s for s in sources if not os.path.basename(s).startswith("icon-symbol")]
    for path in sources:
        build(path)


if __name__ == "__main__":
    main(sys.argv[1:])
