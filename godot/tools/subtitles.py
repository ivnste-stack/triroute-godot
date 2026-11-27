#!/usr/bin/env python3
"""Subtitles of the trailer studio over recorded frames.

The studio (F8 → «Субтитри» → «Копіювати код») copies a list like
    {"subtitles": [{"text": "…", "t0": 1.5, "dur": 6, "color": "#ffffff", "size": 64, "font": "display",
                    "y": 0.82, "dir": "ltr", "shadow": true}, …]}
and this draws it over a video (or a folder of frames) the way the studio's preview shows it: the game's fonts
(display — Unbounded, body — Onest, both at weight 600), the size in pixels at 1080p (scaled to the video), a
steady crawl across the whole width (ltr / rtl) or still in the middle (center), a fade over the first and the
last 0.35 s (TrailerStudio.sub_state).

    python3 tools/subtitles.py IN OUT SPEC.json            IN, OUT: video files, or folders of frames
    python3 tools/subtitles.py IN OUT SPEC.json --fps 60   the frames' rate (a folder of frames: 60 by default)
    python3 tools/subtitles.py IN preview.png SPEC.json --at 3.2   one frame at 3.2 s, to check

A video keeps its sound. Needs ffmpeg / ffprobe and Pillow.
"""
import argparse
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = {"display": os.path.join(HERE, "..", "assets", "fonts", "Unbounded.ttf"),
         "body": os.path.join(HERE, "..", "assets", "fonts", "Onest.ttf")}
_font_cache = {}


def font(kind, px):
    key = (kind, px)
    if key not in _font_cache:
        f = ImageFont.truetype(FONTS.get(kind, FONTS["body"]), px)
        try:   # both are variable fonts: weight 600, as in the game (Ui.font(…, 600))
            axes = f.get_variation_axes()
            f.set_variation_by_axes([600 if a.get("name") in (b"Weight", "Weight") else a.get("default", 0) for a in axes])
        except Exception:
            pass
        _font_cache[key] = f
    return _font_cache[key]


def hex_rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def state(it, t, W, H, tw, th):
    """where a subtitle is and how visible, t seconds into it — TrailerStudio.sub_state"""
    dur = float(it.get("dur", 5))
    p = min(max(t / dur, 0.0), 1.0)
    x = (W - tw) / 2
    if it.get("dir") == "ltr":
        x = -tw + (W + tw) * p
    elif it.get("dir") == "rtl":
        x = W + (-tw - W) * p
    a = min(max(min(t / 0.35, (dur - t) / 0.35), 0.0), 1.0) if t >= 0 else 0.0
    return x, float(it.get("y", 0.82)) * H - th / 2, a


def draw(img, subs, T):
    """the subtitles of the second T over an RGB image"""
    W, H = img.size
    over = None
    for it in subs:
        t = T - float(it.get("t0", 0))
        if t < 0 or t > float(it.get("dur", 5)):
            continue
        px = max(8, int(round(float(it.get("size", 64)) * H / 1080)))
        f = font(it.get("font", "display"), px)
        text = str(it.get("text", ""))
        l, tp, r, b = f.getbbox(text)
        tw, th = r - l, b - tp
        x, y, a = state(it, t, W, H, tw, th)
        if a <= 0:
            continue
        if over is None:
            over = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(over)
        if it.get("shadow", True):
            o = max(1, px // 18)
            d.text((x - l + o, y - tp + o), text, font=f, fill=(0, 0, 0, int(140 * a)))
        d.text((x - l, y - tp), text, font=f, fill=hex_rgb(it.get("color", "#ffffff")) + (int(255 * a),))
    if over is None:
        return img
    return Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate",
                          "-of", "json", path], capture_output=True, text=True, check=True).stdout
    s = json.loads(out)["streams"][0]
    n, d = s["r_frame_rate"].split("/")
    return int(s["width"]), int(s["height"]), float(n) / float(d)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("spec")
    ap.add_argument("--fps", type=float, default=0)
    ap.add_argument("--at", type=float, default=None, help="only one frame at this second, into OUT (an image)")
    ap.add_argument("--crf", type=int, default=16)
    a = ap.parse_args()
    spec = json.load(open(a.spec, encoding="utf-8"))
    subs = spec["subtitles"] if isinstance(spec, dict) else spec

    if os.path.isdir(a.inp):   # a folder of frames
        files = sorted(f for f in os.listdir(a.inp) if f.lower().endswith((".png", ".jpg", ".jpeg")))
        fps = a.fps or 60.0
        if a.at is not None:
            i = min(len(files) - 1, int(a.at * fps))
            draw(Image.open(os.path.join(a.inp, files[i])).convert("RGB"), subs, a.at).save(a.out)
            return
        os.makedirs(a.out, exist_ok=True)
        for i, f in enumerate(files):
            draw(Image.open(os.path.join(a.inp, f)).convert("RGB"), subs, i / fps).save(os.path.join(a.out, f))
        print("done: %d frames → %s" % (len(files), a.out))
        return

    W, H, fps = probe(a.inp)
    fps = a.fps or fps
    if a.at is not None:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(a.at), "-i", a.inp, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                             capture_output=True, check=True).stdout
        draw(Image.frombytes("RGB", (W, H), raw[:W * H * 3]), subs, a.at).save(a.out)
        return
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.inp, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(fps), "-i", "-",
                            "-i", a.inp, "-map", "0:v", "-map", "1:a?", "-c:v", "libx264", "-preset", "slow", "-crf", str(a.crf), "-pix_fmt", "yuv420p",
                            "-c:a", "copy", "-shortest", a.out], stdin=subprocess.PIPE)
    n = W * H * 3
    i = 0
    while True:
        buf = dec.stdout.read(n)
        if len(buf) < n:
            break
        enc.stdin.write(draw(Image.frombytes("RGB", (W, H), buf), subs, i / fps).tobytes())
        i += 1
    enc.stdin.close()
    enc.wait()
    dec.wait()
    print("done: %d frames → %s" % (i, a.out))
    return 0 if enc.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main() or 0)
