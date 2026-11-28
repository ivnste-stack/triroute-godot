#!/usr/bin/env python3
"""Subtitles of the trailer studio over recorded frames.

The studio (the key left of 1 → «Субтитри» → «Копіювати код») copies a list like
    {"subtitles": [{"title": "…", "text": "…", "t0": 1.5, "dur": 5, "color": "#ffffff", "size": 44, "font": "display", "x": 0.5, "y": 0.8, "drift": 1, "box": true, "align": "left",
                    "anim": "up"}, …]}
and this draws it over a video (or a folder of frames) the way the studio's preview shows it
(TrailerStudio.sub_sizes / sub_state): a card of dark glass with a thin border (or bare text with a shadow:
"box": false), the title in the game's display (Unbounded) or body (Onest) font at
weight 600, the line under it in Onest 500; sizes in pixels at 1080p (scaled to the video); centred on x, y (parts
of the width and the height), the lines aligned on the card ("align": left / center / right), coming in by an animation ("anim": fade, up,
side, pop, wipe, type), drifting 2% of the width to one side and on (drift -1 / 1) or still (0); a fade
over 0.4 s at each end.

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


def font(kind, px, weight=600):
    key = (kind, px, weight)
    if key not in _font_cache:
        f = ImageFont.truetype(FONTS.get(kind, FONTS["body"]), px)
        try:   # both are variable fonts: the weight as in the game (Ui.font(…, weight))
            axes = f.get_variation_axes()
            f.set_variation_by_axes([weight if a.get("name") in (b"Weight", "Weight") else a.get("default", 0) for a in axes])
        except Exception:
            pass
        _font_cache[key] = f
    return _font_cache[key]


def hex_rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def norm(it):
    """an older line (text crawling across) read as a card's title"""
    if "title" not in it:
        it = dict(it, title=it.get("text", ""), text="", box=it.get("box", False),
                  drift={"ltr": 1, "rtl": -1}.get(it.get("dir"), 0))
    return it


def sizes(it, H):
    """TrailerStudio.sub_sizes"""
    k = H / 1080
    ts = max(8, round(float(it.get("size", 44)) * k))
    box = it.get("box", True)
    return {"ts": ts, "xs": max(round(14 * k), round(ts * .5)), "pad": round(ts * .55) if box else 0,
            "padv": round(ts * .4) if box else 0, "gap": round(ts * .25), "bar": 0}


def state(it, t, W, H, w, h):
    """where a subtitle is and how it shows, t seconds into it — TrailerStudio.sub_state: x, y, alpha, scale,
    reveal (the part of the width shown: the wipe), chars (the part of the letters shown: the typing)"""
    dur = float(it.get("dur", 5))
    clamp = lambda v: min(max(v, 0.0), 1.0)
    p = clamp(t / dur)
    dr = float(it.get("drift", 0))
    d = dr * W * .02 * (p * 2 - 1)
    ein = 1 - (1 - clamp(t / .6)) ** 3
    out = clamp((dur - t) / .4)
    a = min(clamp(t / .4), out)
    x = float(it.get("x", .5)) * W - w / 2 + d
    y = float(it.get("y", .8)) * H - h / 2
    sc, rv, ch = 1.0, 1.0, 1.0
    an = it.get("anim", "fade")
    if an == "up":
        y += (1 - ein) * H * .04
        a = min(clamp(t / .35), out)
    elif an == "side":
        x -= (1 - ein) * W * .06 * (1.0 if dr >= 0 else -1.0)
        a = min(clamp(t / .35), out)
    elif an == "pop":
        sc = .85 + .15 * ein
        a = min(clamp(t / .25), out)
    elif an == "wipe":
        rv = ein
        a = out
    elif an == "type":
        n = len(str(it.get("title", ""))) + len(str(it.get("text", "")))
        ch = clamp(t / max(.2, n / 28.0))
        a = min(clamp(t / .15), out)
    if t < 0:
        a = 0.0
    return x, y, a, sc, rv, ch


def card(it, H, chars):
    """the card alone (RGBA, its own size): glass and border, the title and the line, aligned; with chars < 1
    only that part of the letters (the title's first) — the card keeps its full size"""
    z = sizes(it, H)
    box = it.get("box", True)
    ft = font(it.get("font", "display"), z["ts"], 600)
    title, text = str(it.get("title", "")), str(it.get("text", ""))
    a1, d1 = ft.getmetrics()
    tw, th = ft.getlength(title), a1 + d1
    fx = font("body", z["xs"], 500)
    a2, d2 = fx.getmetrics()
    xw, xh = (fx.getlength(text), a2 + d2) if text else (0, 0)
    w = int(round(z["bar"] + z["pad"] * 2 + max(tw, xw)))
    h = int(round(z["padv"] * 2 + th + ((z["gap"] + xh) if text else 0)))
    im = Image.new("RGBA", (w + 4, h + 4), (0, 0, 0, 0))   # room for the shadow
    d = ImageDraw.Draw(im)
    if box:
        d.rectangle([0, 0, w - 1, h - 1], fill=(8, 18, 28, 219), outline=(255, 255, 255, 36), width=1)
    n0, n1 = len(title), len(text)
    shown = int(chars * (n0 + n1)) if chars < 1 else n0 + n1
    cw = max(tw, xw)   # the lines on the card: left, centred or right ("align")
    al = {"center": .5, "right": 1.0}.get(it.get("align", "left"), 0.0)
    tx = z["bar"] + z["pad"]
    rows = [(title[:min(n0, shown)], ft, hex_rgb(it.get("color", "#ffffff")), z["padv"], z["ts"], tw)]
    if text:
        rows.append((text[:max(0, shown - n0)], fx, (201, 212, 222), z["padv"] + th + z["gap"], z["xs"], xw))
    for s_, f_, c_, yy, px, lw in rows:
        lx = tx + (cw - lw) * al   # placed by the whole line's width: typing does not move it
        if not box:
            o = max(1, px // 18)
            d.text((lx + o, yy + o), s_, font=f_, fill=(0, 0, 0, 140))
        d.text((lx, yy), s_, font=f_, fill=c_ + (255,))
    return im, w, h


def draw(img, subs, T):
    """the subtitles of the second T over an RGB image"""
    W, H = img.size
    over = None
    for it in subs:
        it = norm(it)
        t = T - float(it.get("t0", 0))
        if t < 0 or t > float(it.get("dur", 5)):
            continue
        _, w, h = card(it, H, 1.0)
        x, y, a, sc, rv, ch = state(it, t, W, H, w, h)
        if a <= 0 or rv <= 0:
            continue
        im, w, h = card(it, H, ch)
        if rv < 1:   # the wipe: only the left part so far
            cut = Image.new("RGBA", im.size, (0, 0, 0, 0))
            cut.paste(im.crop((0, 0, max(1, int(w * rv)), im.size[1])), (0, 0))
            im = cut
        if sc != 1:   # the pop: scaled about its centre
            nw, nh = max(1, int(im.size[0] * sc)), max(1, int(im.size[1] * sc))
            x += (im.size[0] - nw) / 2
            y += (im.size[1] - nh) / 2
            im = im.resize((nw, nh), Image.LANCZOS)
        if a < 1:   # faded as one, as the preview's modulate
            im.putalpha(im.getchannel("A").point(lambda v: int(v * a)))
        if over is None:
            over = Image.new("RGBA", img.size, (0, 0, 0, 0))
        over.alpha_composite(im, (int(round(x)), int(round(y))))
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
