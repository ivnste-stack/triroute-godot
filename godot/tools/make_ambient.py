"""Synthesises a calm background loop for the game into assets/music/ambient.ogg: slow pads on
Cmaj7 - Am9 - Fmaj7 - G6, a soft bass, sparse glassy notes of the pentatonic scale here and there in the
stereo field, a reverb. No drums, no melody to hum along: it can run for hours without wearing on you.
The end is folded onto the start, so it loops without a seam.
    python3 tools/make_ambient.py   (needs numpy, scipy and ffmpeg)"""
import numpy as np, os, subprocess, wave
from scipy.signal import lfilter, butter

SR = 44100
CH = 12.0                      # seconds a chord
PROG = [  # MIDI notes of each chord (voiced low and wide), its bass
    ([60, 64, 67, 71, 74], 36),     # Cmaj9
    ([57, 60, 64, 67, 71], 33),     # Am9
    ([53, 57, 60, 64, 67], 29),     # Fmaj9
    ([55, 59, 62, 64, 69], 31),     # G6/9
]
PASSES = 4                       # 4 × 4 chords × 12 s = 192 s
PENT = [72, 74, 76, 79, 81, 84, 86, 88]   # C major pentatonic, high
rng = np.random.default_rng(20261123)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")
L = int(SR * CH * len(PROG) * PASSES)
TAIL = int(SR * 8)
mix = np.zeros((L + TAIL, 2))


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def adsr(n, a, r):
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    e[:na] = (1 - np.cos(np.linspace(0, np.pi, na))) / 2
    e[-nr:] *= (1 + np.cos(np.linspace(0, np.pi, nr))) / 2
    return e


def pad_voice(f, dur, detune_c=6):
    n = int(dur * SR)
    x = np.arange(n) / SR
    s = np.zeros(n)
    for d in (-detune_c, 0, detune_c):          # three slightly detuned voices: a slow chorus
        fd = f * 2 ** (d / 1200)
        ph = rng.uniform(0, 2 * np.pi)
        for k, a in ((1, 1.0), (2, .32), (3, .12), (4, .05)):
            s += a * np.sin(2 * np.pi * fd * k * x + ph * k)
    s *= 1 + .12 * np.sin(2 * np.pi * .13 * x + rng.uniform(0, 6))   # a slow swell
    return s


def place(sig, at, pan):
    i = int(at * SR)
    j = min(i + len(sig), len(mix))
    sig = sig[: j - i]
    mix[i:j, 0] += sig * np.cos(pan * np.pi / 2)
    mix[i:j, 1] += sig * np.sin(pan * np.pi / 2)


for p in range(PASSES):
    for c, (notes, bass) in enumerate(PROG):
        t0 = (p * len(PROG) + c) * CH
        dur = CH + 4.0                            # overlaps the next chord: a slow crossfade
        env = adsr(int(dur * SR), 3.5, 4.5)
        for i, m in enumerate(notes):
            place(pad_voice(hz(m), dur) * env * .055, t0, .25 + .5 * i / (len(notes) - 1))
        x = np.arange(int(dur * SR)) / SR
        b = (np.sin(2 * np.pi * hz(bass) * x) + .15 * np.sin(2 * np.pi * 2 * hz(bass) * x)) * env * .11
        place(b, t0, .5)
        # sparse glassy notes: 2–4 a chord, from the chord's own tones and the pentatonic
        k = rng.integers(2, 5)
        for _ in range(k):
            at = t0 + rng.uniform(.5, CH - .5)
            m = int(rng.choice(PENT))
            f = hz(m)
            n = int(3.2 * SR)
            xx = np.arange(n) / SR
            g = sum(a * np.sin(2 * np.pi * f * h * xx) for h, a in ((1, 1), (2.76, .25), (5.4, .07)))
            g *= np.exp(-xx / .9) * np.minimum(1, xx / .004)
            place(g * .05 * rng.uniform(.6, 1.0), at, rng.uniform(.15, .85))

# a soft low-pass over everything (warm, no fizz)
bl, al = butter(2, 5200 / (SR / 2))
mix = lfilter(bl, al, mix, axis=0)

# a reverb: four combs and two all-passes per channel (Schroeder), mixed in softly
def reverb(x, seed):
    out = np.zeros_like(x)
    for d, g in ((1557, .84), (1617, .83), (1491, .85), (1422, .84)):
        d += seed
        b = np.zeros(d + 1); b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out += lfilter(b, a, x)
    for d, g in ((225, .5), (556, .5)):
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out = lfilter(b, a, out)
    return out / 4

wet = np.stack([reverb(mix[:, 0], 0), reverb(mix[:, 1], 23)], axis=1)
mix = mix * .75 + wet * .45

# the seam: the tail after the loop's end is laid over its start
mix[:TAIL] += mix[L:L + TAIL]
mix = mix[:L]
mix /= np.max(np.abs(mix)) + 1e-9
mix *= .7

os.makedirs(OUT, exist_ok=True)
tmp = os.path.join(OUT, "_ambient.wav")
with wave.open(tmp, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, "ambient.ogg")], check=True)
os.remove(tmp)
print("ambient.ogg: %.0f s" % (L / SR))
