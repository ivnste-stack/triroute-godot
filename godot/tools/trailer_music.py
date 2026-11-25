#!/usr/bin/env python3
"""The trailer's music: an action cue synthesised from scratch (numpy + scipy), 120 BPM in A minor, laid
out on the trailer's timeline (tools/trailer.sh): a tense intro that rises to a drop at 8 s, a driving main
part with hits on the events (pirates, the closed border, the hurricane, the theft, the accident, payday),
a breakdown for the night, a last hit under the title and a tail.

    python3 tools/trailer_music.py out.wav [length_s]
"""
import sys
import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
LEN = float(sys.argv[2]) if len(sys.argv) > 2 else 61.0
N = int(LEN * SR) + SR
L = np.zeros(N)
R = np.zeros(N)
rng = np.random.default_rng(7)

DROP = 8.0          # the main part starts
BREAK = 49.0        # the night: a breakdown
FINAL = 55.0        # the title: the last hit
HITS = [20.4, 27.6, 34.2, 44.9, 46.2, 47.3]   # the events of the trailer
CRASH = [8.0, 18.0, 26.0, 33.0, 40.0]         # the cuts between the scenes


def t_arr(n):
    return np.arange(n) / SR


def add(sig, at, pan=0.0, gain=1.0):
    i = int(at * SR)
    if i >= N:
        return
    n = min(len(sig), N - i)
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    L[i:i + n] += sig[:n] * gain * l * 1.414
    R[i:i + n] += sig[:n] * gain * r * 1.414


def lp(sig, fc, order=2):
    sos = butter(order, min(fc, SR / 2 - 100) / (SR / 2), "low", output="sos")
    return sosfilt(sos, sig)


def hp(sig, fc, order=2):
    sos = butter(order, fc / (SR / 2), "high", output="sos")
    return sosfilt(sos, sig)


def bp(sig, lo, hi):
    sos = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos")
    return sosfilt(sos, sig)


def env(n, a, d, s=0.0, r=None):
    """attack, decay to sustain level s over the note, exponential"""
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    t = t_arr(n - na)
    e[na:] = s + (1 - s) * np.exp(-t / max(d, 1e-4))
    if r:
        nr = min(n, int(r * SR))
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, n, harm=None):
    t = t_arr(n)
    out = np.zeros(n)
    k = 1
    top = harm or int(min(40, 9000 / f))
    while k <= top:
        out += np.sin(2 * np.pi * f * k * t) / k
        k += 1
    return out * .6


def sq(f, n):
    t = t_arr(n)
    out = np.zeros(n)
    for k in range(1, int(min(30, 8000 / f)) + 1, 2):
        out += np.sin(2 * np.pi * f * k * t) / k
    return out * .8


def note(name):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    p, o = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[p] + (o - 4) * 12) / 12)


# ---------------------------------------------------------------- drums
def kick():
    n = int(.42 * SR)
    t = t_arr(n)
    f = 46 + 110 * np.exp(-t / .045)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / .2)
    click = rng.standard_normal(n) * np.exp(-t / .004) * .35
    return np.tanh((s + click) * 1.8) * .95


def snare():
    n = int(.28 * SR)
    t = t_arr(n)
    noise = bp(rng.standard_normal(n), 1200, 9000) * np.exp(-t / .09)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / .05)
    return (noise * .9 + tone * .6) * .75


def hat(open_=False):
    n = int((.32 if open_ else .06) * SR)
    t = t_arr(n)
    return hp(rng.standard_normal(n), 7500, 4) * np.exp(-t / (.11 if open_ else .018)) * .32


def crash():
    n = int(2.4 * SR)
    t = t_arr(n)
    return hp(rng.standard_normal(n), 4000, 2) * np.exp(-t / .7) * .42


def impact():
    """a cinematic hit: a deep boom, a body of noise and a metallic ring"""
    n = int(2.6 * SR)
    t = t_arr(n)
    f = 32 + 70 * np.exp(-t / .12)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .9)
    body = lp(rng.standard_normal(n), 900) * np.exp(-t / .25) * .9
    ring = sum(np.sin(2 * np.pi * fr * t) * np.exp(-t / dc) for fr, dc in [(523, .6), (1046, .4), (1567, .3), (311, .9)]) * .12
    return np.tanh((boom * 1.4 + body + ring) * 1.2) * .9


def riser(dur):
    n = int(dur * SR)
    t = t_arr(n)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    seg = SR // 20
    for i in range(0, n, seg):   # a band of noise that climbs
        k = i / n
        out[i:i + seg] = bp(x[i:i + seg + 2000], 300 + 6000 * k ** 2, 1200 + 9000 * k ** 2)[:len(out[i:i + seg])]
    return out * (t / dur) ** 2 * .5


# ---------------------------------------------------------------- harmony: Am - F - C - G, a bar each
PROG = [("A", ["A3", "C4", "E4"]), ("F", ["F3", "A3", "C4"]), ("C", ["C4", "E4", "G4"]), ("G", ["G3", "B3", "D4"])]
ROOT = {"A": "A1", "F": "F1", "C": "C2", "G": "G1"}


def chord_at(t):
    return PROG[int(t // BAR) % 4]


def pad(t0, t1, gain=.16):
    """a wide chord pad from t0 to t1, bar by bar"""
    b = int(t0 // BAR)
    while b * BAR < t1:
        st = max(t0, b * BAR)
        en = min(t1, (b + 1) * BAR)
        n = int((en - st + .4) * SR)
        root, notes = chord_at(st + .01)
        s = np.zeros(n)
        for nm in notes:
            for det in (-0.12, 0.0, 0.11):
                s += saw(note(nm) * 2 ** (det / 12), n, harm=12)
        s = lp(s, 1400) * env(n, .25, 9, 1, .4)
        add(s, st, -.3, gain / 3)
        add(s, st + .011, .3, gain / 3)
        b += 1


def bassline(t0, t1, cut=600, gain=.5):
    t = t0
    step = BEAT / 2
    i = 0
    while t < t1 - 1e-6:
        root, _ = chord_at(t + .01)
        f = note(ROOT[root]) * (2 if i % 4 == 3 else 1)
        n = int(step * .95 * SR)
        s = lp(sq(f, n) * .5 + saw(f, n) * .5, cut) * env(n, .003, .14, .35, .02)
        add(np.tanh(s * 2.0) * .8, t, 0, gain)
        t += step
        i += 1


def arp(t0, t1, cut=3200, gain=.2, rate=4):
    t = t0
    step = BEAT / rate
    i = 0
    pat = [0, 1, 2, 1, 2, 0, 1, 2]
    while t < t1 - 1e-6:
        _, notes = chord_at(t + .01)
        nm = notes[pat[i % len(pat)]]
        f = note(nm) * 2
        n = int(step * 1.6 * SR)
        s = lp(saw(f, n) + saw(f * 1.006, n), cut) * env(n, .002, .09, 0, .02)
        add(s, t, .35 if i % 2 else -.35, gain)
        t += step
        i += 1


def drums(t0, t1, kick_on=True, fill_last=False):
    t = t0
    i = 0
    K = kick()
    S = snare()
    H = hat()
    O = hat(True)
    while t < t1 - 1e-6:
        beat = i // 4
        sub = i % 4
        if kick_on and sub == 0:
            add(K, t, 0, .95)
        if kick_on and sub == 0 and beat % 2 == 1:
            add(S, t, .05, .85)
        add(H, t, .25, .9 if sub % 2 == 0 else .55)
        if sub == 2:
            add(O, t, -.2, .45)
        t += BEAT / 4
        i += 1


def roll(t0, t1):
    S = snare()
    t = t0
    while t < t1 - 1e-6:
        k = (t - t0) / (t1 - t0)
        add(S, t, 0, .25 + .7 * k)
        t += BEAT / (4 if k < .5 else 8)


# ---------------------------------------------------------------- the timeline
# intro: a dark pad, the bass pulsing behind a closed filter, ticking hats, a riser and a roll into the drop
pad(0, DROP, .2)
bassline(0, DROP, cut=260, gain=.4)
H = hat()
t = BAR * 1
while t < DROP:
    add(H, t, .3, .6)
    t += BEAT / 2
add(riser(4.0), DROP - 4.0, 0, .9)
roll(DROP - BAR, DROP)
arp(BAR * 2, DROP, cut=1200, gain=.12)

# the main part
pad(DROP, BREAK, .1)
bassline(DROP, BREAK, cut=900, gain=.55)
arp(DROP, BREAK, cut=3800, gain=.17)
drums(DROP, BREAK)
for c in CRASH:
    add(crash(), c, -.4, 1)
for h in HITS:
    add(impact(), h, 0, .9)
add(riser(2.5), 40.0 - 2.5, .2, .5)
roll(BREAK - BAR / 2, BREAK)

# the night: no kick, the arp soft, the pad wide, a riser into the title
pad(BREAK, FINAL, .2)
arp(BREAK, FINAL, cut=1600, gain=.12, rate=2)
bassline(BREAK, FINAL, cut=300, gain=.3)
add(riser(FINAL - BREAK), BREAK, 0, .8)

# the title: the last hit and a long chord
add(impact(), FINAL, 0, 1.2)
add(crash(), FINAL, 0, 1.2)
n = int((LEN - FINAL + 1) * SR)
s = np.zeros(n)
for nm in ["A2", "E3", "A3", "C4", "E4"]:
    for det in (-0.1, 0.1):
        s += saw(note(nm) * 2 ** (det / 12), n, harm=10)
s = lp(s, 1800) * env(n, .05, 3.0, 0)
add(s, FINAL, -.2, .08)
add(s, FINAL + .013, .2, .08)

# a short reverb (a few fading echoes), the mix glued, faded at the very end
def verb(x):
    y = x.copy()
    for d, g in [(.031, .35), (.047, .3), (.071, .25), (.113, .2), (.167, .15), (.239, .1)]:
        k = int(d * SR)
        y[k:] += lp(x[:-k], 4000) * g
    return y


L = verb(L)
R = verb(R[::1])
mix = np.stack([L, R], 1)[: int(LEN * SR)]
mix = hp(mix.T, 28).T
peak = np.max(np.abs(mix))
mix = np.tanh(mix / peak * 1.6) / np.tanh(1.6)
fade = int(1.2 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
fin = int(.02 * SR)
mix[:fin] *= np.linspace(0, 1, fin)[:, None]
out = (mix * .92 * 32767).astype(np.int16)

import wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(out.tobytes())
print("wrote", sys.argv[1], f"{LEN:.1f} s")
