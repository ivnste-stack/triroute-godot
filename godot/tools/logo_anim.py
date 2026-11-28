#!/usr/bin/env python3
"""The TryRoute logo animated: its parts (assets/brand/*.png: plane, ship, train, truck, title) put together as
the logo pulled tight, then the vehicles move a little outwards from the centre, quick at first and slowing down —
first the truck right and the ship slowly left, right after them the plane up to the top right corner and the train
left — and a gleam runs across the word.

    python3 tools/logo_anim.py OUT.mp4                    on the game's dark blue
    python3 tools/logo_anim.py OUT.mov --alpha            with transparency (ProRes 4444, for editing)
    python3 tools/logo_anim.py OUT.webm --alpha           with transparency (VP9)
    python3 tools/logo_anim.py frame.png --at 2.5         one frame, to check
    options: --size 1920x1080, --fps 60, --dur 4.5, --bg "#0b1826"
"""
import argparse
import math
import os
import subprocess

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.join(HERE, "..", "assets", "brand")

# the logo as drawn (the reference picture, 1523 × 482): each part's scale and its top left corner there;
# drawn back to front, the word last
LAYOUT = [("ship", .80, 244, 98), ("plane", .79, 650, 104), ("truck", .70, 1108, 214), ("train", .75, 28, 243), ("title", .795, 268, 249)]
REF = (1523, 482)
# each part: where it starts (pulled in towards the centre: a tight logo) and where it ends (a little out), in the
# reference's pixels from its place in LAYOUT, when it starts moving and for how long; the truck and the ship first,
# the plane and the train right after (0.08 s: one movement, no pause) — quick at first, slowing down to a stop
MOVE = {"truck": ((-46, 0), (26, 0), .30, 1.6), "ship": ((34, 6), (-24, 0), .30, 1.8),
	"plane": ((-44, 30), (30, -22), .38, 1.6), "train": ((46, 0), (-26, 0), .38, 1.6), "title": ((0, 0), (0, 0), 0, 1)}
GLEAM = (2.2, 3.2)   # the gleam across the word, once everything has settled


def ease(f):
    """quick at first, slowing down to a stop (an exponential ease-out: no overshoot)"""
    f = min(max(f, 0.0), 1.0)
    return (1 - 2 ** (-8 * f)) / (1 - 2 ** -8)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--fps", type=float, default=60)
    ap.add_argument("--dur", type=float, default=4.5)
    ap.add_argument("--bg", default="#0b1826")
    ap.add_argument("--alpha", action="store_true")
    ap.add_argument("--at", type=float, default=None)
    ap.add_argument("--width", type=float, default=.78, help="the logo's width as a part of the frame's")
    a = ap.parse_args()
    W, H = map(int, a.size.split("x"))
    K = W * a.width / REF[0]                     # the reference's pixels → the frame's
    ox, oy = (W - REF[0] * K) / 2, (H - REF[1] * K) / 2
    parts = {}
    for name, s, x, y in LAYOUT:
        im = Image.open(os.path.join(BRAND, name + ".png")).convert("RGBA")
        im = im.resize((max(1, round(im.width * s * K)), max(1, round(im.height * s * K))), Image.LANCZOS)
        parts[name] = (im, ox + x * K, oy + y * K)
    title, tx, ty = parts["title"]
    # the gleam only on the letters' light faces, not the dark outline
    lum = title.convert("L").point(lambda v: 255 if v > 95 else 0)
    face = ImageChops.multiply(lum, title.getchannel("A")).filter(ImageFilter.GaussianBlur(.6 * K))

    def frame(t):
        bg = (0, 0, 0, 0) if a.alpha else tuple(int(a.bg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        F = Image.new("RGBA", (W, H), bg)
        for name, _, _, _ in LAYOUT:
            im, x, y = parts[name]
            (ax, ay), (bx, by), t0, d = MOVE[name]
            e = ease((t - t0) / d)
            dx, dy = ax + (bx - ax) * e, ay + (by - ay) * e
            F.alpha_composite(im, (round(x + dx * K), round(y + dy * K)))
        g = (t - GLEAM[0]) / (GLEAM[1] - GLEAM[0])
        if 0 < g < 1:   # a slanted band of light across the word, left to right: a bright core in a soft glow
            hgt = title.height
            sk = hgt * .45
            cx = -hgt * 1.2 + (title.width + hgt * 2.4) * (1 - (1 - g) ** 1.6)
            m = Image.new("L", title.size, 0)
            for bw, blur, k in ((hgt * .9, .45, .45), (hgt * .22, .18, 1.0)):
                band = Image.new("L", title.size, 0)
                ImageDraw.Draw(band).polygon([(cx - bw / 2 + sk, 0), (cx + bw / 2 + sk, 0), (cx + bw / 2 - sk, hgt), (cx - bw / 2 - sk, hgt)], fill=int(255 * k))
                m = ImageChops.lighter(m, band.filter(ImageFilter.GaussianBlur(bw * blur)))
            fade = min(1.0, math.sin(math.pi * g) * 1.6)
            m = ImageChops.multiply(m, face).point(lambda v: int(v * fade))
            white = Image.new("RGBA", title.size, (255, 255, 255, 0))
            white.putalpha(m)
            F.alpha_composite(white, (round(tx), round(ty)))
        return F

    if a.at is not None:
        frame(a.at).save(a.out)
        return
    n = int(round(a.dur * a.fps))
    if a.alpha and a.out.lower().endswith(".mov"):
        enc = ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le"]
    elif a.alpha:
        enc = ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "20", "-row-mt", "1"]
    else:
        enc = ["-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}", "-r", str(a.fps), "-i", "-"] + enc + [a.out],
                         stdin=subprocess.PIPE)
    for i in range(n):
        p.stdin.write(frame(i / a.fps).tobytes())
    p.stdin.close()
    p.wait()
    print(f"done: {a.out} ({n} frames)")


if __name__ == "__main__":
    main()
