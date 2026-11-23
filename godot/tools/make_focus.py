"""Synthesises background loops for concentration into assets/music/focus-*.ogg: brighter (major keys) and
quicker than ambient.ogg, a soft pulse of plucked arpeggios over warm pads and a round bass, no drums and no
melody to hum along. Each loop is a whole number of bars and its tail is folded onto its start: no seam.
    python3 tools/make_focus.py   (needs numpy, scipy and ffmpeg)"""
import numpy as np, os, subprocess, wave
from scipy.signal import lfilter, butter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")

# name, tempo, chords ([pad notes], bass) a bar each, arpeggio patterns (indices into the chord, None = rest,
# eighths), bars, seed, a light tick (a hushed shaker on the off-beats)
VARIANTS = [
    ("focus-1", 96, [([62, 66, 69, 73, 76], 38), ([59, 62, 66, 69, 73], 35), ([55, 59, 62, 66, 69], 31), ([57, 61, 64, 66, 71], 33)],
     [[0, 2, 4, 2, 3, 2, 4, 2], [0, 2, 3, 4, 3, 2, 1, 2]], 72, 11, True),        # D major: Dmaj9 Bm9 Gmaj9 A6/9
    ("focus-2", 88, [([53, 57, 60, 64, 67], 29), ([55, 59, 62, 64, 69], 31), ([52, 55, 59, 62, 67], 28), ([57, 60, 64, 67, 71], 33)],
     [[0, 1, 2, 4, 2, 1, 3, 1], [0, None, 2, 4, None, 3, 2, 1]], 64, 23, False),  # F lydian: Fmaj9#11 G6 Em9 Am9
    ("focus-3", 104, [([60, 64, 67, 71, 74], 36), ([55, 59, 62, 67, 69], 31), ([57, 60, 64, 67, 71], 33), ([53, 57, 60, 65, 69], 29)],
     [[0, 2, 4, 3, 2, 4, 3, 1], [4, 3, 2, 0, 2, 3, 4, 2]], 80, 37, True),         # C major: Cmaj9 G6/9 Am9 Fadd9
]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def smooth_env(n, a, r):
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = (1 - np.cos(np.linspace(0, np.pi, na))) / 2
    e[-nr:] *= (1 + np.cos(np.linspace(0, np.pi, nr))) / 2
    return e


def reverb(x, seed):
    out = np.zeros_like(x)
    for d, g in ((1557, .82), (1617, .81), (1491, .83), (1422, .82)):
        d += seed
        b = np.zeros(d + 1); b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out += lfilter(b, a, x)
    for d, g in ((225, .5), (556, .5)):
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out = lfilter(b, a, out)
    return out / 4


def make(name, bpm, prog, pats, bars, seed, tick):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    L = int(SR * bar * bars)
    TAIL = int(SR * 6)
    mix = np.zeros((L + TAIL, 2))

    def place(sig, at, pan):
        i = int(at * SR)
        j = min(i + len(sig), len(mix))
        if j <= i:
            return
        sig = sig[: j - i]
        mix[i:j, 0] += sig * np.cos(pan * np.pi / 2)
        mix[i:j, 1] += sig * np.sin(pan * np.pi / 2)

    for b in range(bars):
        notes, bass = prog[b % len(prog)]
        t0 = b * bar
        # pads: a bar and a half, so neighbours overlap into a slow crossfade
        dur = bar * 1.5
        n = int(dur * SR)
        x = np.arange(n) / SR
        env = smooth_env(n, bar * .35, bar * .6)
        for i, m in enumerate(notes):
            f = hz(m)
            s = np.zeros(n)
            for d in (-5, 0, 5):
                fd = f * 2 ** (d / 1200)
                ph = rng.uniform(0, 6.28)
                s += np.sin(2 * np.pi * fd * x + ph) + .25 * np.sin(4 * np.pi * fd * x + ph) + .08 * np.sin(6 * np.pi * fd * x)
            place(s * env * .032, t0, .25 + .5 * i / (len(notes) - 1))
        # bass: on the one and softly on the three
        for at, v in ((0, 1.0), (2 * beat, .6)):
            nb = int(beat * 1.9 * SR)
            xb = np.arange(nb) / SR
            sb = (np.sin(2 * np.pi * hz(bass) * xb) + .2 * np.sin(4 * np.pi * hz(bass) * xb)) * np.exp(-xb / (beat * 1.1)) * np.minimum(1, xb / .01)
            place(sb * .16 * v, t0 + at, .5)
        # the pulse: plucked eighths an octave up, a soft accent on the beats, a little swing of loudness
        pat = pats[(b // 4) % len(pats)]
        up = sorted(notes)[1:] + [sorted(notes)[1] + 12]
        for k, idx in enumerate(pat):
            if idx is None:
                continue
            m = up[idx % len(up)] + 12
            at = t0 + k * beat / 2
            npk = int(beat * 1.6 * SR)
            xp = np.arange(npk) / SR
            f = hz(m)
            pl = (np.sin(2 * np.pi * f * xp) + .3 * np.sin(4 * np.pi * f * xp) + .1 * np.sin(6 * np.pi * f * xp))
            pl *= np.exp(-xp / (beat * .32)) * np.minimum(1, xp / .003)
            vel = (.95 if k % 2 == 0 else .7) * rng.uniform(.85, 1.0)
            place(pl * .055 * vel, at, .3 + .4 * ((k * 3) % 8) / 7)
        # a hushed shaker on the off-beats
        if tick:
            for k in range(8):
                if k % 2 == 1:
                    nn = int(.06 * SR)
                    w = rng.standard_normal(nn)
                    w = lfilter([1, -1], [1, -.6], w)                     # thin: only the hiss
                    w *= np.exp(-np.arange(nn) / SR / .012)
                    place(w * .012, t0 + k * beat / 2, .7 if k % 4 == 1 else .3)
        # now and then a high bell, so the loop never feels like a loop
        if rng.random() < .35:
            m = int(rng.choice([n + 24 for n in notes[1:]]))
            nn = int(2.5 * SR)
            xx = np.arange(nn) / SR
            g = sum(a * np.sin(2 * np.pi * hz(m) * h * xx) for h, a in ((1, 1), (2.76, .2), (5.4, .05)))
            place(g * np.exp(-xx / .7) * np.minimum(1, xx / .004) * .03, t0 + rng.integers(0, 8) * beat / 2, rng.uniform(.2, .8))

    bl, al = butter(2, 6500 / (SR / 2))
    mix = lfilter(bl, al, mix, axis=0)
    wet = np.stack([reverb(mix[:, 0], 0), reverb(mix[:, 1], 19)], axis=1)
    mix = mix * .8 + wet * .35
    mix[:TAIL] += mix[L:L + TAIL]
    mix = mix[:L]
    mix /= np.max(np.abs(mix)) + 1e-9
    mix *= .7
    tmp = os.path.join(OUT, "_%s.wav" % name)
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(tmp)
    print("%s.ogg: %d bpm, %.0f s" % (name, bpm, L / SR))


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    for v in VARIANTS:
        if not only or v[0] in only:
            make(*v)
