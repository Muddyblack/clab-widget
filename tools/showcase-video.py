#!/usr/bin/env python3
"""Short showcase video (docs/readme/showcase.mp4) from the README screenshots.

    python3 tests/render/screenshots.py && python3 tools/showcase-video.py [OUT.mp4]

Needs Pillow and an ffmpeg (on PATH, or `pip install imageio-ffmpeg`).
"""

import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "readme")
ICON = os.path.join(ROOT, "package", "contents", "icons", "app", "org.muddyblack.clabWidget-256.png")
W, H, FPS = 1280, 720, 30
SCENE, FADE = 2.4, 0.4  # seconds per scene, crossfade

# (screenshot, headline, sub line)
SCENES = [
    ("labs.png", "Every lab at a glance", "containerlab & netlab: running, partial, stopped"),
    ("map.png", "Live topology map", "down links in red, traffic per link"),
    ("menu.png", "One right-click away", "redeploy, save configs, stop, clean up"),
    ("search-down.png", "Find what's broken", "search `down` lists every stopped node"),
    ("map-large.png", "Scales to big fabrics", "a 102-node data centre, laid out by tier"),
    ("hosts.png", "Remote hosts too", "ssh, WSL, clab-api-server, netlab-ui, clabernetes"),
    ("info.png", "Knows your tools", "installed versions vs. what it needs"),
]


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF", "/Library/Fonts"):
        if os.path.exists(os.path.join(d, name)):
            return ImageFont.truetype(os.path.join(d, name), size)
    return ImageFont.load_default(size)


def background():
    """Dark violet → teal gradient with two soft glows."""
    top, bottom = (24, 16, 48), (8, 36, 48)
    bg = Image.new("RGB", (W, H))
    px = bg.load()
    for y in range(H):
        t = y / H
        row = tuple(int(a + (b - a) * t) for a, b in zip(top, bottom, strict=True))
        for x in range(W):
            px[x, y] = row
    glow = Image.new("RGB", (W, H))
    g = ImageDraw.Draw(glow)
    g.ellipse((-200, -250, 600, 450), fill=(90, 50, 160))
    g.ellipse((800, 350, 1500, 1000), fill=(20, 120, 130))
    return Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(160)), 0.35)


BG = background()
ease = lambda t: t * t * (3 - 2 * t)  # noqa: E731


def title_frame(t):
    """Opening card: icon + name, fading/rising in."""
    img = BG.copy()
    a = ease(min(1, t / 0.6))
    icon = Image.open(ICON).convert("RGBA").resize((160, 160))
    layer = Image.new("RGBA", (W, H))
    layer.alpha_composite(icon, (W // 2 - 80, int(170 + 20 * (1 - a))))
    d = ImageDraw.Draw(layer)
    d.text((W // 2, 385), "CLAB Widget", font=font(64, True), fill=(255, 255, 255), anchor="mm")
    d.text((W // 2, 450), "containerlab & netlab on your desktop", font=font(26), fill=(170, 180, 210), anchor="mm")
    d.text(
        (W // 2, 500),
        "Plasma · Quickshell · Windows · macOS · Linux tray",
        font=font(20),
        fill=(110, 200, 190),
        anchor="mm",
    )
    layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
    img.paste(layer, (0, 0), layer)
    return img


def scene_frame(shot, head, sub, t):
    """Screenshot on the right with a slow zoom (and a pan for tall ones),
    caption on the left sliding in."""
    img = BG.copy()
    p = t / SCENE
    shot = Image.open(os.path.join(SHOTS, shot)).convert("RGBA")
    box_h = 640
    scale = min(box_h / shot.height, 560 / shot.width) * (1.0 + 0.05 * p)
    if shot.height * (560 / shot.width) > box_h * 1.4:  # tall: fit width, pan down
        scale = 560 / shot.width * (1.0 + 0.03 * p)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x = 1280 - 80 - 560 + (560 - sw) // 2
    y = (H - sh) // 2 if sh <= box_h else int(40 - (sh - box_h) * ease(p))
    shadow = Image.new("RGBA", (W, H))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 6, y + 14, x + sw + 6, y + sh + 14), 18, fill=(0, 0, 0, 150))
    img.paste(shadow.filter(ImageFilter.GaussianBlur(18)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(18)))
    if sh > box_h:  # clip to the frame
        shot = shot.crop((0, max(0, 40 - y), sw, max(0, 40 - y) + box_h))
        y = 40
    img.paste(shot, (x, y), shot)

    a = ease(min(1, t / 0.5))
    d = ImageDraw.Draw(img)
    dx = int(-30 * (1 - a))
    c = lambda rgb: tuple(int(v * a + b * (1 - a)) for v, b in zip(rgb, (20, 26, 48), strict=True))  # noqa: E731
    d.rounded_rectangle((80 + dx, 300, 86 + dx, 390), 3, fill=c((110, 200, 190)))
    d.text((110 + dx, 300), head, font=font(44, True), fill=c((255, 255, 255)))
    d.text((110 + dx, 362), sub, font=font(22), fill=c((170, 180, 210)))
    return img


def outro_frame(t):
    img = title_frame(10)
    d = ImageDraw.Draw(img)
    a = ease(min(1, t / 0.5))
    col = tuple(int(v * a) for v in (255, 255, 255))
    d.text((W // 2, 580), "KDE Store · github.com/Muddyblack/clab-widget", font=font(24, True), fill=col, anchor="mm")
    return img


def frames():
    parts = [lambda t: title_frame(t)]
    parts += [lambda t, s=s: scene_frame(*s, t) for s in SCENES]
    parts += [lambda t: outro_frame(t)]
    n = int(SCENE * FPS)
    fade = int(FADE * FPS)
    for i, part in enumerate(parts):
        for f in range(n):
            frame = part(f / FPS)
            if i + 1 < len(parts) and f >= n - fade:  # crossfade into the next part
                k = (f - (n - fade) + 1) / (fade + 1)
                frame = Image.blend(frame, parts[i + 1](0), ease(k))
            yield frame


def ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg  # pip install imageio-ffmpeg

    return imageio_ffmpeg.get_ffmpeg_exe()


def main(out):
    cmd = [ffmpeg(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}"]
    cmd += ["-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22"]
    cmd += ["-preset", "slow", "-movflags", "+faststart", out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for frame in frames():
        proc.stdin.write(frame.convert("RGB").tobytes())
    proc.stdin.close()
    sys.exit(proc.wait())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(SHOTS, "showcase.mp4"))
