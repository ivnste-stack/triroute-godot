"""Synthesises the interface sounds of the game into assets/sfx/*.wav (44.1 kHz, mono, 16-bit).
Soft and short, made of sine partials with smooth envelopes: no samples, no licences.
    python3 tools/make_sfx.py"""
import numpy as np, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, a=0.004, d=0.1, shape=1.0):
    """attack a seconds, then an exponential decay with time constant d"""
    x = np.arange(n) / SR
    e = np.minimum(1.0, x / max(a, 1e-6)) * np.exp(-np.maximum(0, x - a) / d) ** shape
    # a short fade at the very end: no click
    f = min(n, int(SR * 0.006))
    e[-f:] *= np.linspace(1, 0, f)
    return e


def tone(freq, dur, a=0.004, d=0.1, partials=((1, 1.0),), detune=0.0):
    x = t(dur)
    s = np.zeros_like(x)
    for k, amp in partials:
        s += amp * np.sin(2 * np.pi * freq * k * (1 + detune * k) * x)
    return s * env(len(x), a, d)


def chirp(f0, f1, dur, a=0.01, d=0.08):
    x = t(dur)
    f = f0 + (f1 - f0) * (x / dur) ** 0.7
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env(len(x), a, d)


def noise(dur, a=0.001, d=0.01, lp=0.3):
    x = np.random.default_rng(7).standard_normal(int(SR * dur))
    y = np.zeros_like(x)
    for i in range(1, len(x)):   # a one-pole low-pass: a softer hiss
        y[i] = y[i - 1] + lp * (x[i] - y[i - 1])
    return y * env(len(x), a, d)


def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts)
    out = np.zeros(n)
    for at, s in parts:
        i = int(at * SR)
        out[i:i + len(s)] += s
    return out


def save(name, s, peak=0.55):
    s = s / (np.max(np.abs(s)) + 1e-9) * peak
    data = (s * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


BELL = ((1, 1.0), (2.01, 0.35), (3.02, 0.18), (4.2, 0.08))
SOFT = ((1, 1.0), (2, 0.18), (3, 0.06))

os.makedirs(OUT, exist_ok=True)
# a button: a tiny wooden tick
save("click", mix((0, noise(0.03, d=0.004, lp=0.5) * 0.35), (0, tone(1850, 0.05, a=0.001, d=0.012, partials=SOFT))), 0.32)
# a window opens / closes: a soft rising / falling sweep
save("open", chirp(420, 820, 0.16, a=0.012, d=0.07), 0.28)
save("close", chirp(760, 380, 0.14, a=0.008, d=0.06), 0.24)
# a trip is sent: two rising notes (G5, D6)
save("send", mix((0, tone(784, 0.25, d=0.09, partials=BELL)), (0.075, tone(1175, 0.35, d=0.14, partials=BELL))), 0.4)
# a delivery: a coin (two bright bell strikes close together)
save("coin", mix((0, tone(1976, 0.3, a=0.001, d=0.07, partials=BELL)), (0.06, tone(2637, 0.45, a=0.001, d=0.16, partials=BELL))), 0.36)
# good news: a soft major third (E5, G#5)
save("good", mix((0, tone(659, 0.3, d=0.12, partials=SOFT)), (0.05, tone(831, 0.35, d=0.14, partials=SOFT))), 0.34)
# a warning: a single soft mid ping
save("warn", tone(587, 0.35, a=0.003, d=0.12, partials=BELL), 0.36)
# an incident: two falling notes (A4, F4), a little rough
save("alert", mix((0, tone(440, 0.22, d=0.08, partials=((1, 1), (3, .25), (5, .1)))), (0.13, tone(349, 0.32, d=0.12, partials=((1, 1), (3, .25), (5, .1))))), 0.42)
# refused: a short low buzz
save("deny", tone(196, 0.16, a=0.004, d=0.05, partials=((1, 1), (2, .5), (3, .35), (4, .2))), 0.3)
# a new grade or licence: a rising arpeggio C-E-G-C with a held top
arp = [(0, 523), (0.09, 659), (0.18, 784), (0.27, 1047)]
save("level", mix(*[(a, tone(f, 0.9 if i == 3 else 0.35, d=0.3 if i == 3 else 0.1, partials=BELL)) for i, (a, f) in enumerate(arp)]), 0.42)
print("done:", sorted(os.listdir(OUT)))
