#!/usr/bin/env python3
"""dist/clab-widget.ico (Windows) and dist/clab-widget.icns (macOS) from
assets/icon.png, for the PyInstaller build and the installer. Needs Pillow."""

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
img = Image.open(os.path.join(ROOT, "assets", "icon.png")).convert("RGBA")
img.save(os.path.join(ROOT, "dist", "clab-widget.ico"), sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
img.resize((1024, 1024)).save(os.path.join(ROOT, "dist", "clab-widget.icns"))
print("wrote dist/clab-widget.ico and dist/clab-widget.icns")
