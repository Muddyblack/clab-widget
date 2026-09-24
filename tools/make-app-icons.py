#!/usr/bin/env python3
"""Build the app icon sizes from a source PNG (a rounded tile like assets/icon.png).

    python3 tools/make-app-icons.py                 # every assets/icon*.png
    python3 tools/make-app-icons.py assets/icon-netlab.png

assets/icon.png        -> icons/app/org.muddyblack.clabWidget-<n>.png  (the "clab" icon)
assets/icon-<name>.png -> icons/app/<name>-<n>.png                     (e.g. "netlab")

The tiles carry no text, just the emblem filling the glass, so every size is
the whole tile scaled down. Needs Pillow.
"""

import glob
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "package", "contents", "icons", "app")
SIZES = (16, 22, 32, 48, 64, 128, 256)


def prefix_for(path):
    base = os.path.splitext(os.path.basename(path))[0]
    return "org.muddyblack.clabWidget" if base == "icon" else base.removeprefix("icon-")


def build(path):
    img = Image.open(path).convert("RGBA")
    prefix = prefix_for(path)
    for n in SIZES:
        img.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, f"{prefix}-{n}.png"), optimize=True)
    print(f"{os.path.relpath(path, ROOT)} -> icons/app/{prefix}-{{{','.join(map(str, SIZES))}}}.png")


def main(args):
    os.makedirs(OUT, exist_ok=True)
    for path in args or sorted(glob.glob(os.path.join(ROOT, "assets", "icon*.png"))):
        build(path)


if __name__ == "__main__":
    main(sys.argv[1:])
