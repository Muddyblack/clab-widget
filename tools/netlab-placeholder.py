#!/usr/bin/env python3
"""Placeholder netlab icon until the real one exists: assets/icon.png with its
blue shifted to netlab purple (#aa66ff). Replace assets/icon-netlab.png with the
real artwork and run `make app-icons`."""

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
img = Image.open(os.path.join(ROOT, "assets", "icon.png")).convert("RGBA")
alpha = img.getchannel("A")
h, s, v = img.convert("RGB").convert("HSV").split()
# Blue (~215°) to purple (~270°): +55° of 360 on Pillow's 0-255 hue scale.
h = h.point(lambda x: (x + 39) % 256)
out = Image.merge("HSV", (h, s, v)).convert("RGB")
out.putalpha(alpha)
out.save(os.path.join(ROOT, "assets", "icon-netlab.png"), optimize=True)
print("wrote assets/icon-netlab.png (placeholder)")
