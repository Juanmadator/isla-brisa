#!/usr/bin/env python3
"""
Procedural audio generator for "Isla Brisa".

Synthesizes every music loop, ambience bed and sound effect from scratch (no
samples) and writes 16-bit PCM mono WAV files into assets/audio/.

Mood: a breezy sunny island -- airy, gentle wonder, a little nostalgic.  Music
is sparse and spacious (light piano / harp / flute phrases with room to
breathe).  Every instrument is synthesized: additive piano with inharmonic
partials and a hammer, additive harp, celesta and music box, Karplus-Strong
guitar / pizzicato / bass, breathy flute, wavetable pads, strings, a
formant-shaped "aah" choir, accordion, soft brass and light percussion.

Pure standard library (math / random / wave / array / struct):
    python tools/make_audio.py                      # everything
    python tools/make_audio.py music_day sfx_jump   # just some files
    python tools/make_audio.py sfx_step_grass       # a whole variant group

Everything is deterministic (seeded RNGs), so re-running gives identical files.
Footsteps come in loudness-matched sets of variants (sfx_step_<surface>_<k>).
Loops (music_*, amb_* and *_loop) are rendered circularly: note tails, reverb tails,
filter state and modulation curves wrap around from the end of the loop into
its start, so the loop point is seamless with looping enabled in Godot.

Music is mastered to a common RMS (MUSIC_RMS_DB) with a circular look-ahead
peak limiter at MUSIC_CEIL_DB, so all tracks have matching loudness.
"""

import array
import math
import os
import random
import struct  # noqa: F401  (kept for tooling that inspects headers)
import sys
import time
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio")

SR_SFX = 22050
SR_MUS = 32000
SR_AMB = 22050
TAU = 2.0 * math.pi

MUSIC_RMS_DB = -18.0      # every music loop is mastered to this RMS
MUSIC_CEIL_DB = -3.0      # ...with peaks limited to this ceiling
AMB_PEAK_DB = -8.0
SFX_PEAK_DB = -1.0
STEP_PEAK_DB = -6.0
RAW = "raw"               # marker: already mastered, write as-is


# --------------------------------------------------------------------------
# Basic helpers
# --------------------------------------------------------------------------

def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def zeros(n):
    return [0.0] * n


def smoothstep(x):
    x = clamp(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def mix_into(buf, sig, start, gain=1.0, wrap=False):
    """Add sig*gain into buf at sample offset start (optionally wrapping)."""
    n = len(buf)
    if not sig or gain == 0.0:
        return
    if wrap:
        s = start % n
        pos = 0
        total = len(sig)
        while pos < total:
            chunk = min(total - pos, n - s)
            buf[s:s + chunk] = [a + gain * b for a, b in
                                zip(buf[s:s + chunk], sig[pos:pos + chunk])]
            pos += chunk
            s = 0
        return
    if start < 0:
        sig = sig[-start:]
        start = 0
    end = min(n, start + len(sig))
    if end <= start:
        return
    buf[start:end] = [a + gain * b for a, b in zip(buf[start:end], sig)]


def scale(x, g):
    return [v * g for v in x]


def add(a, b):
    if len(a) < len(b):
        a, b = b, a
    out = a[:]
    out[:len(b)] = [p + q for p, q in zip(a, b)]
    return out


def peak_of(x):
    return max(abs(v) for v in x) if x else 0.0


def normalize(x, peak=1.0):
    pk = peak_of(x) or 1.0
    g = peak / pk
    return [v * g for v in x]


def rms_of(x):
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0


def fade(x, sr, fin=0.002, fout=0.012):
    """Raised-cosine fade in/out to avoid clicks."""
    n = len(x)
    ni = min(n, max(1, int(fin * sr)))
    no = min(n, max(1, int(fout * sr)))
    for i in range(ni):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / ni)
    for i in range(no):
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / no)
    return x


def additive(sr, n, f, plist, attack=0.002):
    """Sum of exponentially decaying sine partials: plist = [(ratio, amp, tau)]."""
    out = zeros(n)
    nyq = sr * 0.45
    for ratio, amp, tau in plist:
        fr = f * ratio
        if fr >= nyq or amp == 0.0:
            continue
        w = TAU * fr / sr
        k = 1.0 / (tau * sr)
        m = min(n, int(tau * sr * 7) + 1)
        out[:m] = [a + amp * math.sin(w * i) * math.exp(-k * i)
                   for i, a in zip(range(m), out[:m])]
    a = max(1, int(attack * sr))
    for i in range(min(a, n)):
        out[i] *= i / a
    return out


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def onepole_lp(x, fc, sr):
    a = math.exp(-TAU * fc / sr)
    b = 1.0 - a
    y = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y = b * v + a * y
        out[i] = y
    return out


def onepole_hp(x, fc, sr):
    lp = onepole_lp(x, fc, sr)
    return [a - b for a, b in zip(x, lp)]


def dc_block(x, r=0.9995):
    out = [0.0] * len(x)
    x1 = 0.0
    y1 = 0.0
    for i, v in enumerate(x):
        y1 = v - x1 + r * y1
        x1 = v
        out[i] = y1
    return out


def biquad(x, kind, f0, q, sr):
    """RBJ cookbook biquad. kind in ('lp', 'hp', 'bp')."""
    f0 = min(f0, sr * 0.45)
    w0 = TAU * f0 / sr
    cs = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cs) / 2, 1 - cs, (1 - cs) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cs) / 2, -(1 + cs), (1 + cs) / 2
    else:  # constant 0 dB peak band-pass
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cs, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, y
        out[i] = y
    return out


def svf_bp(x, fc_of_i, q, sr):
    """Chamberlin state-variable band-pass with a time-varying cutoff."""
    low = band = 0.0
    damp = 1.0 / q
    out = [0.0] * len(x)
    fmax = sr / 6.5
    for i, v in enumerate(x):
        f = 2.0 * math.sin(math.pi * min(fc_of_i(i), fmax) / sr)
        high = v - low - damp * band
        band += f * high
        low += f * band
        out[i] = band
    return out


def circ(fn, x, pre):
    """Apply a causal process to a loop as if it had been playing forever:
    prepend the loop's own tail, process, then drop the prepended part."""
    n = len(x)
    pre = min(pre, n)
    return fn(x[n - pre:] + x)[pre:]


def periodic_curve(n, rng, harmonics, step=64):
    """Smooth random curve in [-1, 1] that is exactly periodic over n samples."""
    comps = [(k, rng.uniform(0.4, 1.0) / k ** 0.7, rng.uniform(0, TAU)) for k in harmonics]
    norm = sum(a for _, a, _ in comps)
    m = n // step + 2
    pts = [sum(a * math.sin(TAU * k * (j * step) / n + p) for k, a, p in comps) / norm
           for j in range(m)]
    out = [0.0] * n
    inv = 1.0 / step
    for i in range(n):
        j = i // step
        fr = (i - j * step) * inv
        out[i] = pts[j] + (pts[j + 1] - pts[j]) * fr
    return out


def asr_env(n, sr, attack, dur, release):
    na = max(1, int(attack * sr))
    nr = int(dur * sr)
    k = 3.0 / (max(release, 0.01) * sr)
    env = [0.0] * n
    for i in range(n):
        e = math.sin(0.5 * math.pi * i / na) ** 2 if i < na else 1.0
        if i >= nr:
            e *= math.exp(-(i - nr) * k)
        env[i] = e
    return env


def damp(x, sr, t_off, rel=0.09):
    """Damper: exponential release from t_off on, then truncate."""
    n_off = int(t_off * sr)
    if n_off >= len(x):
        return x
    n_end = min(len(x), n_off + int(rel * 6 * sr))
    y = x[:n_end]
    k = 1.0 / (rel * sr)
    for i in range(n_off, n_end):
        y[i] *= math.exp(-(i - n_off) * k)
    return fade(y, sr, fin=0.0, fout=0.01)


# --------------------------------------------------------------------------
# Reverb (Freeverb-style comb/allpass network, computed block-wise)
# --------------------------------------------------------------------------

def comb_block(x, d, g):
    n = len(x)
    y = x[:]
    for s in range(d, n, d):
        e = min(n, s + d)
        y[s:e] = [a + g * b for a, b in zip(x[s:e], y[s - d:e - d])]
    return y


def allpass_block(x, d, g):
    n = len(x)
    y = [0.0] * n
    y[0:min(d, n)] = [-g * v for v in x[0:min(d, n)]]
    for s in range(d, n, d):
        e = min(n, s + d)
        y[s:e] = [-g * a + b + g * c for a, b, c in
                  zip(x[s:e], x[s - d:e - d], y[s - d:e - d])]
    return y


COMB_MS = [25.3, 26.9, 29.0, 30.7, 32.2, 33.8, 35.3, 36.7]
ALLPASS_MS = [12.6, 10.0, 7.7, 5.1]


def reverb(x, sr, rt60=1.4, wet=0.2, dry=1.0, damp_hz=4500.0,
           predelay=0.015, circular=False, size=1.0):
    """Returns dry+wet. circular=True keeps the length and wraps the tail
    (the loop's own end is prepended so the start hears the tail)."""
    n = len(x)
    if circular:
        m = min(n, int((rt60 * 1.7 + predelay + 0.1) * sr))
        src = x[n - m:] + x
    else:
        m = 0
        src = x + zeros(int(rt60 * sr * 0.8))
    inp = onepole_lp(src, damp_hz, sr)
    pd = int(predelay * sr)
    if pd:
        inp = zeros(pd) + inp[:len(inp) - pd]
    acc = zeros(len(src))
    norm = 0.0
    for ms in COMB_MS:
        d = max(1, int(ms * size * sr / 1000.0))
        g = 10.0 ** (-3.0 * d / (sr * rt60))
        norm += 1.0 / (1.0 - g * g)
        c = comb_block(inp, d, g)
        acc = [a + b for a, b in zip(acc, c)]
    for ms in ALLPASS_MS:
        acc = allpass_block(acc, max(1, int(ms * size * sr / 1000.0)), 0.5)
    k = wet / math.sqrt(norm)
    out = [dry * a + k * b for a, b in zip(src, acc)]
    return out[m:] if circular else out


def echo(x, sr, taps, extra=0.0):
    """Simple multi-tap echo: taps = [(delay_s, gain)]."""
    tail = max(d for d, _ in taps) + extra
    out = x + zeros(int(tail * sr))
    for d, g in taps:
        mix_into(out, x, int(d * sr), g)
    return out


class Cache:
    def __init__(self):
        self.d = {}

    def get(self, key, fn):
        v = self.d.get(key)
        if v is None:
            v = fn()
            self.d[key] = v
        return v


# --------------------------------------------------------------------------
# Mastering: circular look-ahead limiter + RMS matching
# --------------------------------------------------------------------------

def limiter_gain(x, ceil, sr, attack=0.005, release=0.22):
    """Gain curve g (<= 1) with |x*g| <= ceil everywhere; computed circularly."""
    n = len(x)
    req = [ceil / abs(v) if abs(v) > ceil else 1.0 for v in x]
    ka = 1.0 - math.exp(-1.0 / (attack * sr))
    kr = 1.0 - math.exp(-1.0 / (release * sr))
    a = [1.0] * n
    g = 1.0
    for _ in range(2):  # backward pass (look-ahead ramp), two laps = circular
        for i in range(n - 1, -1, -1):
            g += (1.0 - g) * ka
            r = req[i]
            if r < g:
                g = r
            a[i] = g
    out = [1.0] * n
    g = 1.0
    for _ in range(2):  # forward pass (release), two laps = circular
        for i in range(n):
            g += (1.0 - g) * kr
            v = a[i]
            if v < g:
                g = v
            out[i] = g
    return out


def master_music(buf, sr):
    target = 10.0 ** (MUSIC_RMS_DB / 20.0)
    ceil = 10.0 ** (MUSIC_CEIL_DB / 20.0)
    g = target / (rms_of(buf) or 1.0)
    crest = 20.0 * math.log10(peak_of(buf) / (rms_of(buf) or 1.0))
    print("    crest factor before limiting: %.2f dB (limiting needed: %.2f dB)"
          % (crest, max(0.0, crest + MUSIC_RMS_DB - MUSIC_CEIL_DB)), flush=True)
    y = buf
    for _ in range(3):
        y = [v * g for v in buf]
        if peak_of(y) > ceil:
            gc = limiter_gain(y, ceil, sr)
            y = [a * b for a, b in zip(y, gc)]
        r = rms_of(y)
        if abs(20.0 * math.log10(r / target)) < 0.05:
            break
        g *= target / r
    return y


def finish_loop(buf, sr, rt60, wet, damp_hz=4500.0, size=1.0, predelay=0.02):
    buf = reverb(buf, sr, rt60=rt60, wet=wet, circular=True, damp_hz=damp_hz,
                 size=size, predelay=predelay)
    return circ(dc_block, buf, int(2.0 * sr))


# --------------------------------------------------------------------------
# Instruments (each returns a peak-normalised waveform)
# --------------------------------------------------------------------------

def piano(midi, sr, vel=0.6, length=None):
    """Additive piano: stretched (inharmonic) partials, two-stage decay from a
    detuned unison pair, velocity-dependent brightness and a felt hammer."""
    f = mtof(midi)
    rng = random.Random(midi * 1009 + int(vel * 100))
    nyq = sr * 0.45
    tau1 = clamp(2.4 * (262.0 / f) ** 0.55, 0.6, 5.0)
    full = min(tau1 * 3.0 + 0.3, 6.5)
    n = int(min(length, full) * sr) if length else int(full * sr)
    B = 0.00028
    tilt = 1.85 - 0.8 * vel
    pl = []
    for k in range(1, 15):
        r = k * math.sqrt(1.0 + B * k * k)
        if f * r > nyq:
            break
        a = k ** -tilt * (abs(math.sin(math.pi * k * 0.12)) + 0.25)
        t = tau1 / (1.0 + 0.5 * (k - 1) ** 1.15)
        pl.append((r, 0.6 * a, t * 0.25))
        pl.append((r * 1.0006, 0.4 * a, t))
    x = additive(sr, n, f, pl, attack=0.0015)
    m = min(n, int(0.015 * sr))
    h = onepole_lp(noise(m, rng), min(900.0 + 2.5 * f, 6000.0), sr)
    kh = 1.0 / (0.0035 * sr)
    pk = peak_of(x) or 1.0
    for i in range(m):
        x[i] += 0.3 * vel * pk * h[i] * math.exp(-kh * i)
    x = onepole_lp(x, 2500.0 + 6000.0 * vel, sr)
    return normalize(fade(x, sr, fin=0.0, fout=0.05))


def ks_pluck(midi, sr, length=1.5, smooth=1, tau=0.6, body=0.25, decay=0.996, seed=None):
    """Karplus-Strong plucked string (guitar / bass) + sine body, pitch-corrected."""
    f = mtof(midi)
    rng = random.Random(seed if seed is not None else midi * 7 + smooth)
    N = max(2, int(sr / f - 0.5))
    buf = [rng.uniform(-1.0, 1.0) for _ in range(N)]
    for _ in range(smooth):  # softer pluck: low-pass the excitation
        buf = [(buf[i - 1] + 2 * buf[i] + buf[(i + 1) % N]) * 0.25 for i in range(N)]
    mean = sum(buf) / N
    buf = [v - mean for v in buf]
    pk = max(abs(v) for v in buf) or 1.0
    buf = [v / pk for v in buf]
    n_out = int(length * sr)
    actual = sr / (N + 0.5)
    ratio = f / actual
    n_raw = int(n_out * ratio) + 3
    raw = [0.0] * n_raw
    idx = 0
    for i in range(n_raw):
        v = buf[idx]
        nxt = buf[idx + 1] if idx + 1 < N else buf[0]
        buf[idx] = decay * 0.5 * (v + nxt)
        raw[i] = v
        idx += 1
        if idx == N:
            idx = 0
    out = [0.0] * n_out
    for i in range(n_out):
        p = i * ratio
        j = int(p)
        fr = p - j
        out[i] = raw[j] * (1.0 - fr) + raw[j + 1] * fr
    w = TAU * f / sr
    k = 1.0 / (tau * sr)
    kb = 1.0 / (tau * 1.3 * sr)
    a = max(1, int(0.0025 * sr))
    out = [(v * math.exp(-k * i) + body * math.sin(w * i) * math.exp(-kb * i))
           * (i / a if i < a else 1.0) for i, v in enumerate(out)]
    return fade(out, sr, fin=0.0, fout=0.05)


def guitar(midi, sr, length=1.4):
    return normalize(ks_pluck(midi, sr, length, smooth=1, tau=0.55, body=0.18, decay=0.997))


def soft_bass(midi, sr, length=1.6):
    return normalize(ks_pluck(midi, sr, length, smooth=5, tau=0.55, body=0.85, decay=0.998))


def pizz(midi, sr):
    x = ks_pluck(midi, sr, 0.9, smooth=3, tau=0.2, body=0.5, decay=0.994, seed=midi * 3 + 1)
    return normalize(onepole_lp(x, 2600.0, sr))


def harp(midi, sr, length=None, bright=1.0):
    """Additive harp: warm fundamental, quickly fading upper partials, tiny shimmer."""
    f = mtof(midi)
    tau = clamp(1.0 * (262.0 / f) ** 0.5, 0.35, 1.8)
    n = int((length if length else min(tau * 5.0, 3.5)) * sr)
    pl = [(1.0, 1.0, tau), (1.0015, 0.18, tau * 1.2),
          (2.0, 0.38 * bright, tau * 0.5), (3.0, 0.13 * bright, tau * 0.32),
          (4.0, 0.06 * bright, tau * 0.2), (5.0, 0.03 * bright, tau * 0.13),
          (6.0, 0.015 * bright, tau * 0.09)]
    x = additive(sr, n, f, pl, attack=0.004)
    return normalize(fade(x, sr, fin=0.0, fout=0.04))


def bell(f, sr, tau=0.8, length=None, bright=1.0):
    """Small chime with gently inharmonic partials (sweet, not spooky)."""
    n = int((length if length else tau * 5.0) * sr)
    pl = [(1.0, 1.0, tau), (1.002, 0.3, tau * 0.9), (2.0, 0.35 * bright, tau * 0.55),
          (3.01, 0.16 * bright, tau * 0.3), (4.2, 0.08 * bright, tau * 0.16),
          (5.4, 0.04 * bright, tau * 0.1)]
    return normalize(additive(sr, n, f, pl, attack=0.001))


def chime(f, sr, tau=0.4, length=None):
    """Harmonic chime (pitch-shift friendly)."""
    n = int((length if length else tau * 5.0) * sr)
    pl = [(1.0, 1.0, tau), (1.0008, 0.25, tau * 1.2), (2.0, 0.3, tau * 0.5),
          (3.0, 0.12, tau * 0.3), (4.0, 0.05, tau * 0.18)]
    return normalize(additive(sr, n, f, pl, attack=0.0015))


def celesta(midi, sr, length=None):
    f = mtof(midi)
    tau = clamp(1.1 * (523.0 / f) ** 0.5, 0.35, 2.0)
    n = int((length if length else tau * 4.5) * sr)
    pl = [(1.0, 1.0, tau), (1.0007, 0.3, tau * 1.4), (2.0, 0.12, tau * 0.35),
          (3.0, 0.05, tau * 0.2), (4.0, 0.2, tau * 0.1), (7.1, 0.04, tau * 0.04)]
    x = additive(sr, n, f, pl, attack=0.0012)
    rng = random.Random(midi * 17)
    m = int(0.006 * sr)
    th = onepole_lp(noise(m, rng), 2000.0, sr)
    for i in range(m):
        x[i] += 0.15 * th[i] * math.exp(-i / (0.0025 * sr))
    return normalize(fade(x, sr, fin=0.0, fout=0.05))


def musicbox(midi, sr, length=None):
    f = mtof(midi)
    tau = clamp(1.5 * (784.0 / f) ** 0.4, 0.6, 2.2)
    n = int((length if length else tau * 4.5) * sr)
    pl = [(1.0, 1.0, tau), (1.0012, 0.15, tau * 0.8), (2.0, 0.10, tau * 0.4),
          (5.95, 0.22, tau * 0.08), (9.8, 0.07, tau * 0.035)]
    x = additive(sr, n, f, pl, attack=0.0008)
    rng = random.Random(midi * 19)
    m = int(0.003 * sr)
    for i in range(m):
        x[i] += 0.2 * rng.uniform(-1, 1) * math.exp(-i / (0.0008 * sr))
    return normalize(fade(x, sr, fin=0.0, fout=0.05))


def flute(midi, dur, sr, release=0.13, vib_cents=16.0, vib_rate=5.1,
          bright=1.0, breath=1.0, grace=0.0, seed=None):
    """Breathy flute: sine-dominant tone, attack chiff, pitched breath noise and
    a delayed vibrato. grace > 0 adds a quick upper-neighbour cut."""
    f = mtof(midi)
    rng = random.Random(seed if seed is not None else midi * 131 + int(dur * 997))
    n = int((dur + release) * sr)
    n_on = int(dur * sr)
    kr = 1.0 / (release * 0.33 * sr)
    vr = TAU * vib_rate * rng.uniform(0.96, 1.04) / sr
    vph = rng.uniform(0, TAU)
    grace_n = int(0.045 * sr) if grace else 0
    gmul = 2.0 ** (grace / 12.0)
    out = [0.0] * n
    env = [0.0] * n
    ph = 0.0
    b2 = 0.2 * bright
    b3 = 0.06 * bright
    for i in range(n):
        t = i / sr
        e = 1.0 - math.exp(-t / 0.022)
        e *= 1.0 - 0.08 * min(1.0, t / 0.8)
        if i >= n_on:
            e *= math.exp(-(i - n_on) * kr)
        vd = smoothstep((t - 0.12) / 0.3) * vib_cents
        vph += vr
        cents = vd * math.sin(vph) - 18.0 * math.exp(-t / 0.02)
        mul = 2.0 ** (cents / 1200.0)
        if i < grace_n:
            mul *= gmul
        e *= 1.0 + 0.05 * (vd / max(vib_cents, 1e-6)) * math.sin(vph + 0.6)
        ph += TAU * f * mul / sr
        out[i] = (math.sin(ph) + b2 * math.sin(2 * ph) + b3 * math.sin(3 * ph)
                  + 0.02 * math.sin(4 * ph)) * e
        env[i] = e
    if breath > 0:
        wn = noise(n, rng)
        tonal = biquad(wn, "bp", f, 7.0, sr)
        air = biquad(wn, "bp", min(3200.0, sr * 0.3), 0.7, sr)
        chiff = biquad(wn, "bp", min(f * 3.0, sr * 0.4), 2.0, sr)
        kc = 1.0 / (0.014 * sr)
        out = [o + breath * ((0.9 * tn + 0.035 * a) * ev + 0.22 * c * math.exp(-kc * i))
               for i, (o, tn, a, c, ev) in enumerate(zip(out, tonal, air, chiff, env))]
    a = max(1, int(0.003 * sr))
    for i in range(min(a, n)):
        out[i] *= i / a
    out[-1] = 0.0
    return normalize(out)


def _make_table(harmonics, size=4096):
    t = [sum(a * math.sin(TAU * h * i / size) for h, a in harmonics) for i in range(size)]
    pk = max(abs(v) for v in t)
    return [v / pk for v in t]


PAD_TABLE = _make_table([(1, 1.0), (2, 0.4), (3, 0.2), (4, 0.1), (5, 0.06), (6, 0.04),
                         (7, 0.02)])
STR_TABLE = _make_table([(k, 1.0 / k) for k in range(1, 15)])
BRASS_TABLE = _make_table([(k, 1.0 / k ** 1.15) for k in range(1, 13)])
ACCORDION_TABLE = _make_table([(1, 1.0), (2, 0.55), (3, 0.38), (4, 0.24), (5, 0.17),
                               (6, 0.11), (7, 0.07), (8, 0.045), (9, 0.03), (10, 0.02)])

VOWELS = {
    "ah": [(800, 110, 1.0), (1150, 130, 0.55), (2900, 220, 0.18), (3900, 300, 0.08)],
    "oh": [(480, 90, 1.0), (850, 110, 0.5), (2700, 200, 0.08), (3600, 300, 0.04)],
}


def formant_table(f, vowel, sr, size=2048, tilt=0.45):
    hmax = int(min(sr * 0.42, 7000.0) / f)
    fm = VOWELS[vowel]
    harms = []
    for h in range(1, max(2, hmax) + 1):
        fh = h * f
        r = 0.02
        for F, B, G in fm:
            d = (fh - F) / B
            r += G / (1.0 + d * d)
        harms.append((h, r * h ** -tilt))
    return _make_table(harms, size)


def table_voice(tbl, f, n, sr, detunes, vib_depth=0.0, vib_rate=5.0, seed=0):
    """Sum of detuned wavetable oscillators; vibrato via closed-form phase."""
    size = len(tbl)
    mask = size - 1
    rng = random.Random(seed)
    out = [0.0] * n
    for d in detunes:
        p = f * (1.0 + d) * size / sr
        off = rng.uniform(0, size) + size * 256
        if vib_depth:
            wv = TAU * vib_rate * rng.uniform(0.9, 1.1) / sr
            A = p * vib_depth / wv
            ph0 = rng.uniform(0, TAU)
            out = [o + tbl[int(off + p * i + A * math.sin(wv * i + ph0)) & mask]
                   for i, o in enumerate(out)]
        else:
            out = [o + tbl[int(off + p * i) & mask] for i, o in enumerate(out)]
    return out


def tpad(midi, dur, sr, kind="pad", attack=0.8, release=1.2, lp=None):
    """Sustained wavetable voices: pad / str (strings) / acc (accordion) /
    brass / ah, oh (choir vowels)."""
    f = mtof(midi)
    n = int((dur + release) * sr)
    seed = midi * 31 + int(dur * 100) + len(kind) * 7
    if kind == "pad":
        x = table_voice(PAD_TABLE, f, n, sr, (-0.0035, 0.0, 0.004), 0.0015, 0.3, seed)
        lp = lp or 1500.0
    elif kind == "str":
        x = table_voice(STR_TABLE, f, n, sr, (-0.003, 0.0015, 0.0045), 0.0035, 5.2, seed)
        lp = lp or 2600.0
    elif kind == "acc":
        x = table_voice(ACCORDION_TABLE, f, n, sr, (0.0, 0.0045), 0.0, 1.0, seed)
        lp = lp or 2400.0
    elif kind == "brass":
        x = table_voice(BRASS_TABLE, f, n, sr, (-0.002, 0.002), 0.004, 5.5, seed)
        lp = lp or 2200.0
    else:  # choir
        tbl = formant_table(f, kind, sr)
        x = table_voice(tbl, f, n, sr, (-0.006, -0.002, 0.002, 0.006), 0.006, 5.0, seed)
        lp = lp or 4200.0
    env = asr_env(n, sr, attack, dur, release)
    if kind == "acc":
        bel = TAU * 0.35 / sr
        env = [e * (1.0 + 0.06 * math.sin(bel * i)) for i, e in enumerate(env)]
    x = [a * b for a, b in zip(x, env)]
    x = onepole_lp(onepole_lp(x, lp, sr), lp * 1.6, sr)
    return normalize(fade(x, sr, fin=0.0, fout=0.03))


def brass(midi, dur, sr, release=0.25):
    """Soft horn: wavetable with a brightness envelope (filter opens on attack)."""
    f = mtof(midi)
    n = int((dur + release) * sr)
    x = table_voice(BRASS_TABLE, f, n, sr, (-0.002, 0.002), 0.004, 5.5, midi * 13)
    env = asr_env(n, sr, 0.04, dur, release)
    y = 0.0
    out = [0.0] * n
    for i in range(n):
        t = i / sr
        e = env[i]
        scoop = 1.0 - 0.6 * math.exp(-t / 0.05)
        fc = 500.0 + 2600.0 * e * scoop
        a = 1.0 - math.exp(-TAU * fc / sr)
        y += a * (x[i] * e - y)
        out[i] = y
    return normalize(fade(out, sr, fin=0.0, fout=0.02))


def shaker(sr, seed, accent=1.0):
    rng = random.Random(seed)
    n = int(0.07 * sr)
    x = biquad(biquad(noise(n, rng), "hp", 4500, 0.7, sr), "bp", min(7500, sr * 0.3), 0.8, sr)
    out = [0.0] * n
    for i in range(n):
        t = i / sr
        e = (1.0 - math.exp(-t / 0.004)) * math.exp(-t / (0.016 + 0.006 * accent))
        out[i] = x[i] * e * accent
    return fade(out, sr, fin=0.001, fout=0.01)


def woodblock(sr, f=900.0, seed=3):
    rng = random.Random(seed)
    n = int(0.08 * sr)
    x = additive(sr, n, f, [(1.0, 1.0, 0.018), (2.71, 0.25, 0.006), (4.6, 0.08, 0.003)],
                 attack=0.0008)
    kn = 1.0 / (0.0012 * sr)
    x = [v + 0.15 * rng.uniform(-1, 1) * math.exp(-kn * i) for i, v in enumerate(x)]
    return normalize(fade(onepole_lp(x, 5000, sr), sr, fin=0.0003, fout=0.015))


def modal_hit(sr, length, modes, pitch_drop=0.0, drop_time=0.01):
    """Damped resonant modes [(freq, amp, tau)] with an optional initial pitch drop."""
    n = int(length * sr)
    out = zeros(n)
    kd = 1.0 / (drop_time * sr)
    for f, amp, tau in modes:
        k = 1.0 / (tau * sr)
        ph = 0.0
        seg = [0.0] * n
        for i in range(n):
            fi = f * (1.0 + pitch_drop * math.exp(-kd * i))
            ph += TAU * fi / sr
            seg[i] = amp * math.sin(ph) * math.exp(-k * i)
        out = [a + b for a, b in zip(out, seg)]
    return out


def frame_drum(sr, seed=5):
    rng = random.Random(seed)
    x = modal_hit(sr, 0.35, [(82, 1.0, 0.09), (165, 0.35, 0.04), (290, 0.12, 0.02)],
                  pitch_drop=0.3, drop_time=0.012)
    th = onepole_lp(noise(len(x), rng), 600, sr)
    kt = 1.0 / (0.012 * sr)
    x = [v + 1.2 * h * math.exp(-kt * i) for i, (v, h) in enumerate(zip(x, th))]
    return normalize(fade(x, sr, fin=0.0005, fout=0.05))


def timpani(midi, sr, length=1.8):
    f = mtof(midi)
    rng = random.Random(midi)
    x = modal_hit(sr, length, [(f, 1.0, 0.55), (f * 1.505, 0.45, 0.35),
                               (f * 1.99, 0.3, 0.25), (f * 2.44, 0.15, 0.15)],
                  pitch_drop=0.04, drop_time=0.03)
    th = onepole_lp(noise(int(0.05 * sr), rng), 700, sr)
    mix_into(x, [v * math.exp(-i / (0.01 * sr)) for i, v in enumerate(th)], 0, 1.5)
    return normalize(fade(x, sr, fin=0.0005, fout=0.1))


def cymbal_swell(sr, dur, seed=9):
    rng = random.Random(seed)
    n = int((dur + 0.6) * sr)
    x = biquad(biquad(noise(n, rng), "hp", 5000, 0.7, sr), "bp", min(8500, sr * 0.4), 0.6, sr)
    nd = int(dur * sr)
    for i in range(n):
        if i < nd:
            x[i] *= (i / nd) ** 2.5
        else:
            x[i] *= math.exp(-(i - nd) / (0.12 * sr))
    return normalize(fade(x, sr, 0.0, 0.05))


def bird_phrase(sr, rng):
    """A short songbird phrase: tweets with pitch sweeps and a little trill."""
    kind = rng.choice(("tweet", "tweet", "trill", "whistle"))
    parts = []
    if kind == "tweet":
        f0 = rng.uniform(2800, 4200)
        for _ in range(rng.randint(2, 5)):
            parts.append((rng.uniform(0.045, 0.1), f0 * rng.uniform(0.92, 1.08),
                          rng.choice((1.35, 1.5, 0.7, 1.25)), 0.0, rng.uniform(0.03, 0.08)))
    elif kind == "trill":
        f0 = rng.uniform(3200, 4600)
        parts.append((rng.uniform(0.07, 0.1), f0 * 0.8, 1.3, 0.0, 0.03))
        parts.append((rng.uniform(0.25, 0.4), f0, 0.95, 28.0, 0.0))
    else:  # two-note "fee-bee" whistle
        f0 = rng.uniform(2600, 3400)
        parts.append((0.22, f0, 1.02, 0.0, 0.07))
        parts.append((0.2, f0 * 0.8, 0.97, 0.0, 0.0))
    out = []
    for dur, f, sweep, trill, gap in parts:
        n = int(dur * sr)
        ph = 0.0
        seg = [0.0] * n
        for i in range(n):
            x = i / n
            fi = f * (sweep ** x)
            am = 1.0
            if trill:
                am = 0.5 + 0.5 * math.sin(TAU * trill * i / sr)
            ph += TAU * fi / sr
            e = math.sin(math.pi * x) ** 2
            seg[i] = (math.sin(ph) + 0.08 * math.sin(2 * ph)) * e * am
        out += seg + zeros(int(gap * sr))
    out = onepole_lp(out, 7000, sr)
    return fade(out, sr, fin=0.002, fout=0.01)


def wind_bed(n, sr, seed, base=500.0, depth=2.4, q=0.8, rumble=0.5, whistle=0.0,
             gust_harm=(1, 2, 3, 4, 6, 9), gust_pow=1.6, floor=0.2):
    """Seamless filtered-noise wind with slow periodic gusts (period = n)."""
    rng = random.Random(seed)
    wn = noise(n, rng)
    g = [0.5 + 0.5 * v for v in periodic_curve(n, rng, gust_harm)]
    w2 = periodic_curve(n, rng, (5, 7, 11, 13))
    env = [floor + (1.0 - floor) * v ** gust_pow for v in g]
    fc = [base * depth ** (1.2 * v + 0.25 * u) for v, u in zip(g, w2)]
    pre = int(0.4 * sr)
    src = wn[n - pre:] + wn
    bp = normalize(svf_bp(src, lambda i: fc[(i - pre) % n], q, sr)[pre:])
    lo = normalize(circ(lambda s: onepole_lp(onepole_lp(s, 200.0, sr), 200.0, sr), wn, pre))
    out = [(b + rumble * lw) * e for b, lw, e in zip(bp, lo, env)]
    if whistle:
        wh = normalize(svf_bp(src, lambda i: fc[(i - pre) % n] * 2.2, 16.0, sr)[pre:])
        out = [o + whistle * w * e * e for o, w, e in zip(out, wh, env)]
    return normalize(out)


# --------------------------------------------------------------------------
# Song helper
# --------------------------------------------------------------------------

class Track:
    def __init__(self, sr, bpm, beats, seed):
        self.sr = sr
        self.spb = 60.0 / bpm
        self.L = int(round(beats * self.spb * sr))
        self.buf = zeros(self.L)
        self.cache = Cache()
        self.rng = random.Random(seed)

    def at(self, beat):
        return int(round(beat * self.spb * self.sr))

    def put(self, key, fn, beat, gain, jitter=0.004, delay=0.0):
        sig = self.cache.get(key, fn)
        j = self.rng.uniform(-jitter, jitter) if jitter else 0.0
        mix_into(self.buf, sig, self.at(beat) + int((delay + j) * self.sr), gain, wrap=True)

    # -- instrument shortcuts (durations in beats) --
    def piano(self, beat, m, gain, vel=0.6, dur=None, delay=0.0):
        sr = self.sr
        ds = round(dur * self.spb, 2) if dur else None

        def mk():
            x = piano(m, sr, vel, length=(ds + 0.6) if ds else None)
            return damp(x, sr, ds, 0.1) if ds else x
        self.put(("pno", m, vel, ds), mk, beat, gain, delay=delay)

    def harp(self, beat, m, gain, bright=1.0, length=None, delay=0.0):
        self.put(("harp", m, bright, length), lambda: harp(m, self.sr, length, bright),
                 beat, gain, delay=delay)

    def pizz(self, beat, m, gain):
        self.put(("pizz", m), lambda: pizz(m, self.sr), beat, gain)

    def celesta(self, beat, m, gain, delay=0.0):
        self.put(("cel", m), lambda: celesta(m, self.sr), beat, gain, delay=delay)

    def musicbox(self, beat, m, gain, delay=0.0):
        self.put(("mbox", m), lambda: musicbox(m, self.sr), beat, gain, delay=delay)

    def bass(self, beat, m, gain, length=1.8):
        self.put(("bass", m, length), lambda: soft_bass(m, self.sr, length), beat, gain)

    def guitar(self, beat, m, gain, delay=0.0, length=1.0):
        self.put(("gtr", m, length), lambda: guitar(m, self.sr, length), beat, gain, delay=delay)

    def flute(self, beat, m, beats, gain, **kw):
        ds = round(beats * self.spb * 0.95, 3)
        key = ("fl", m, ds, tuple(sorted(kw.items())))
        self.put(key, lambda: flute(m, ds, self.sr, **kw), beat, gain)

    def brass(self, beat, m, beats, gain):
        ds = round(beats * self.spb * 0.95, 3)
        self.put(("brass", m, ds), lambda: brass(m, ds, self.sr), beat, gain)

    def pad(self, beat, notes, beats, gain, kind="pad", attack=0.8, release=1.2, lp=None):
        ds = round(beats * self.spb, 3)
        for m in notes:
            key = (kind, m, ds, attack, release, lp)
            self.put(key, lambda m=m: tpad(m, ds, self.sr, kind, attack, release, lp),
                     beat, gain, jitter=0.0)


# --------------------------------------------------------------------------
# Music: title (D major, 66 bpm) -- wistful solo piano, soft pad, distant wind
# --------------------------------------------------------------------------

# name: (left-hand voicing [bass, ...], pad voicing)
TITLE_CH = {
    "G": ([43, 50, 55, 59], [59, 62, 67]),
    "D/F#": ([42, 50, 57, 62], [57, 62, 66]),
    "Em": ([40, 47, 55, 59], [59, 64, 67]),
    "A": ([45, 52, 57, 61], [57, 61, 64]),
    "Asus": ([45, 52, 57, 62], [57, 62, 64]),
    "Bm": ([47, 54, 59, 62], [59, 62, 66]),
    "D": ([38, 45, 54, 57], [57, 62, 66]),
    "Em7": ([40, 47, 50, 55], [59, 62, 67]),
    "Gm": ([43, 50, 55, 58], [58, 62, 67]),
}

TITLE_PROG = ["G", "D/F#", "Em", "A", "G", "D/F#", "Bm", "A",
              "Bm", "G", "D", "A", "Bm", "G", "Em7", "Asus",
              "D", "G", "Gm", "A"]

# per bar: [(beat, midi, beats)]
TITLE_MEL = [
    [(0, 78, 1.5), (1.5, 76, 0.5), (2, 74, 2)],
    [(0, 69, 3), (3, 71, 1)],
    [(0, 74, 1.5), (1.5, 76, 0.5), (2, 78, 1), (3, 79, 1)],
    [(0, 76, 4)],
    [(0, 78, 1.5), (1.5, 76, 0.5), (2, 74, 2)],
    [(0, 69, 2), (2, 71, 1), (3, 74, 1)],
    [(0, 74, 1.5), (1.5, 73, 0.5), (2, 71, 2)],
    [(0, 69, 4)],
    [(0, 81, 1.5), (1.5, 78, 0.5), (2, 74, 2)],
    [(0, 79, 1.5), (1.5, 78, 0.5), (2, 76, 1), (3, 74, 1)],
    [(0, 78, 3), (3, 74, 1)],
    [(0, 76, 4)],
    [(0, 81, 1.5), (1.5, 78, 0.5), (2, 74, 1), (3, 76, 1)],
    [(0, 79, 2), (2, 78, 1), (3, 76, 1)],
    [(0, 74, 1.5), (1.5, 76, 0.5), (2, 71, 2)],
    [(0, 74, 2), (2, 73, 2)],
    [(0, 74, 4)],
    [],
    [(1, 70, 3)],
    [(0, 69, 2), (2, 73, 1), (3, 76, 1)],
]

LH_PAT_A = [(0, 0), (1, 1), (2, 2), (3, 3)]
LH_PAT_B = [(0, 0), (1, 1), (1.5, 2), (2, 3), (3, 2)]


def piano_lh(t, b0, lh, pat, gain_bass=0.30, gain=0.16, vel=0.4):
    for beat, idx in pat:
        g = gain_bass if idx == 0 else gain
        t.piano(b0 + beat, lh[idx], g * t.rng.uniform(0.9, 1.05), vel=vel,
                dur=4 - beat + 0.4)


def make_title():
    sr = SR_MUS
    t = Track(sr, 66.0, 80, seed=11)
    for bar, name in enumerate(TITLE_PROG):
        b0 = bar * 4
        lh, padv = TITLE_CH[name]
        pat = LH_PAT_B if 8 <= bar < 16 else LH_PAT_A
        if bar in (17, 18):
            pat = [(0, 0), (2, 2), (3, 3)]
        piano_lh(t, b0, lh, pat)
        pg = 0.055 if 8 <= bar < 16 else 0.04
        t.pad(b0, padv, 4, pg, attack=1.6, release=2.2)
        for k, (beat, m, d) in enumerate(TITLE_MEL[bar]):
            acc = 1.06 if k == 0 else 0.95
            t.piano(b0 + beat, m, 0.44 * acc * t.rng.uniform(0.95, 1.03), vel=0.62,
                    dur=d + 0.5)
            if bar == 16:
                t.piano(b0 + beat, m - 12, 0.22, vel=0.5, dur=d + 0.5)
    # a soft high sparkle in the quiet bar
    for beat, m in ((1.5, 79), (2.0, 83), (2.5, 86), (3.0, 91)):
        t.piano(17 * 4 + beat, m, 0.16, vel=0.45, dur=2.5)

    buf = finish_loop(t.buf, sr, rt60=2.4, wet=0.3)
    wind = wind_bed(t.L, sr, seed=707, base=380.0, depth=2.6, q=0.7, rumble=0.35,
                    whistle=0.08, gust_harm=(1, 2, 3, 5, 7), floor=0.12)
    pk = peak_of(buf)
    mix_into(buf, wind, 0, 0.07 * pk)
    return master_music(buf, sr), sr


# --------------------------------------------------------------------------
# Music: day field (C lydian, 84 bpm) -- sparse piano/harp, flute, pizzicato
# --------------------------------------------------------------------------

# name: (bass, harp tones (6, low->high), pad voicing)
DAY_CH = {
    "Cmaj7": (36, [48, 55, 59, 64, 67, 71], [55, 59, 64]),
    "D/C": (36, [48, 54, 57, 62, 66, 69], [54, 57, 62]),
    "Am9": (45, [45, 52, 59, 60, 64, 71], [55, 59, 64]),
    "Fmaj7#11": (41, [41, 48, 57, 59, 64, 69], [57, 59, 64]),
    "C/E": (40, [40, 47, 55, 60, 64, 67], [55, 60, 64]),
    "Gsus": (43, [43, 50, 55, 60, 62, 67], [55, 60, 62]),
    "Fmaj7": (41, [41, 48, 53, 57, 60, 64], [57, 60, 64]),
    "G/F": (41, [41, 50, 55, 59, 62, 67], [55, 59, 62]),
    "Em7": (40, [40, 47, 52, 55, 59, 62], [55, 59, 62]),
    "Am7": (45, [45, 52, 55, 60, 64, 67], [55, 60, 64]),
    "Dm9": (38, [38, 45, 52, 53, 57, 60], [53, 57, 64]),
}

DAY_PROG = ["Cmaj7", "D/C", "Cmaj7", "D/C", "Am9", "Fmaj7#11", "C/E", "Gsus",
            "Fmaj7", "G/F", "Em7", "Am7", "Dm9", "Gsus", "Cmaj7", "D/C"]

DAY_PIANO = {
    0: [(0, 76, 1), (1, 79, 1), (2, 83, 2)],
    2: [(0, 81, 0.5), (0.5, 78, 0.5), (1, 76, 3)],
    6: [(0, 74, 0.5), (0.5, 76, 0.5), (1, 78, 1), (2, 81, 2)],
    8: [(0, 72, 1), (1, 71, 0.5), (1.5, 69, 2.5)],
    10: [(0, 69, 0.5), (0.5, 71, 0.5), (1, 72, 1), (2, 76, 2)],
    12: [(0, 79, 2), (2, 76, 1), (3, 74, 1)],
    13: [(0, 72, 4)],
    14: [(2, 74, 1), (3, 72, 0.5), (3.5, 74, 0.5)],
    15: [(0, 74, 3)],
    24: [(0, 77, 1), (1, 76, 1), (2, 72, 2)],
    26: [(0, 74, 1), (1, 72, 0.5), (1.5, 74, 2.5)],
    28: [(0, 83, 1), (1, 79, 1), (2, 76, 2)],
    30: [(0, 78, 1), (1, 79, 1), (2, 81, 2)],
}

DAY_FLUTE = {
    16: [(0, 81, 3), (3, 79, 1)],
    17: [(0, 76, 4)],
    18: [(0, 74, 2), (2, 79, 2)],
    19: [(0, 74, 4)],
    20: [(0, 79, 3), (3, 76, 1)],
    21: [(0, 71, 4)],
    22: [(0, 72, 2), (2, 76, 2)],
    23: [(0, 74, 4)],
}


def make_day():
    sr = SR_MUS
    t = Track(sr, 84.0, 128, seed=84)
    for ci, name in enumerate(DAY_PROG):
        bar0 = ci * 2
        b0 = bar0 * 4
        sec = bar0 // 8
        bass, tones, padv = DAY_CH[name]
        # soft low pluck at each chord change
        t.bass(b0, bass, 0.34, length=2.4)
        if sec in (1, 3):
            t.bass(b0 + 6, bass + 7, 0.18, length=1.6)
        # very soft string pad for glue
        pg = (0.022, 0.034, 0.036, 0.03)[sec]
        t.pad(b0, padv, 8, pg, kind="str", attack=1.8, release=2.0, lp=1800.0)
        t.pad(b0, [padv[1] + 12], 8, pg * 0.5, kind="pad", attack=2.0, release=2.0)
        # rolled harp chord on each chord change (lighter where the piano talks)
        hg = 0.09 if (bar0 in DAY_PIANO) else 0.13
        for j, m in enumerate(tones[1:5]):
            t.harp(b0, m, hg * (0.8 + 0.1 * j), delay=j * 0.07)
        # harp arpeggio figure on the third chord of each section
        if ci % 4 == 2 or ci == 15:
            seq = tones[1:6] + [tones[3] + 12, tones[4] + 12, tones[5] + 12]
            if ci == 15:
                seq = list(reversed(seq))
            for k, m in enumerate(seq):
                t.harp(b0 + 4 + k * 0.5, m, 0.12 * (1.0 - 0.04 * k), bright=0.9)
        # gentle pizzicato in sections B and D
        if sec in (1, 3):
            for bb in range(2):
                bar = bar0 + bb
                if bar % 4 == 3:
                    continue
                for beat, idx in ((0, 2), (1.5, 4), (2.5, 3)):
                    t.pizz(bar * 4 + beat, tones[idx] + 12, 0.15 * t.rng.uniform(0.85, 1.05))
    for bar, notes in DAY_PIANO.items():
        for k, (beat, m, d) in enumerate(notes):
            t.piano(bar * 4 + beat, m, 0.42 * (1.05 if k == 0 else 0.95), vel=0.55,
                    dur=d + 0.8)
    for bar, notes in DAY_FLUTE.items():
        for beat, m, d in notes:
            t.flute(bar * 4 + beat, m, d, 0.19, release=0.35, vib_cents=13.0,
                    vib_rate=4.8, bright=0.7, breath=0.8)
    buf = finish_loop(t.buf, sr, rt60=2.3, wet=0.32)
    return master_music(buf, sr), sr


# --------------------------------------------------------------------------
# Music: night (F major, 3/4, 72 bpm) -- music box, celesta, warm pad
# --------------------------------------------------------------------------

NIGHT_CH = {
    "Fmaj7": (41, [53, 57, 60, 64], [57, 60, 64]),
    "Bbmaj7": (46, [50, 53, 57, 62], [57, 62, 65]),
    "Gm7": (43, [50, 53, 58, 62], [58, 62, 65]),
    "C9sus": (48, [55, 58, 62, 65], [58, 62, 65]),
    "Am7": (45, [52, 55, 60, 64], [55, 60, 64]),
    "Dm7": (38, [50, 53, 57, 60], [57, 60, 65]),
    "C": (48, [52, 55, 60, 64], [55, 60, 64]),
}

NIGHT_PROG = ["Fmaj7", "Bbmaj7", "Gm7", "C9sus", "Am7", "Dm7", "Bbmaj7", "C"] * 2

NIGHT_MEL = [
    [(0, 81, 2), (2, 79, 1)], [(0, 77, 3)],
    [(0, 74, 1), (1, 77, 1), (2, 81, 1)], [(0, 79, 3)],
    [(0, 77, 2), (2, 74, 1)], [(0, 70, 3)],
    [(0, 72, 1), (1, 74, 1), (2, 77, 1)], [(0, 79, 3)],
    [(0, 76, 2), (2, 72, 1)], [(0, 69, 3)],
    [(0, 77, 1), (1, 76, 1), (2, 74, 1)], [(0, 72, 3)],
    [(0, 74, 2), (2, 77, 1)], [(0, 81, 3)],
    [(0, 79, 3)], [],
]


def make_night():
    sr = SR_MUS
    t = Track(sr, 72.0, 96, seed=72)
    for ci, name in enumerate(NIGHT_PROG):
        bar0 = ci * 2
        b0 = bar0 * 3
        half = bar0 // 16
        bass, arp, padv = NIGHT_CH[name]
        t.pad(b0, padv, 6, 0.05, kind="pad", attack=1.6, release=2.4, lp=1200.0)
        t.pad(b0, [bass + 12], 6, 0.05, kind="pad", attack=1.0, release=2.0, lp=500.0)
        for bb in range(2):
            bar = bar0 + bb
            s = bar * 3
            t.harp(s, bass + 12, 0.16, bright=0.5)
            if half == 0:
                pair = (arp[1], arp[2]) if bb == 0 else (arp[3], arp[2])
                t.celesta(s + 1, pair[0], 0.075 * t.rng.uniform(0.85, 1.05))
                t.celesta(s + 2, pair[1], 0.07 * t.rng.uniform(0.85, 1.05))
            else:
                t.celesta(s + 2, arp[2 + bb], 0.075 * t.rng.uniform(0.85, 1.05))
        if half == 1:  # music-box sparkle rolls in the second half
            for j, m in enumerate((arp[1] + 24, arp[2] + 24, arp[3] + 24)):
                t.musicbox(b0 + 1.5, m, 0.06, delay=j * 0.12)
    for bar in range(32):
        mel = NIGHT_MEL[bar % 16]
        for k, (beat, m, d) in enumerate(mel):
            if bar < 16:
                t.musicbox(bar * 3 + beat, m, 0.3 * (1.04 if k == 0 else 0.96))
            else:
                t.celesta(bar * 3 + beat, m - 12, 0.34 * (1.04 if k == 0 else 0.96))
    buf = finish_loop(t.buf, sr, rt60=2.7, wet=0.36, damp_hz=3800.0)
    return master_music(buf, sr), sr


# --------------------------------------------------------------------------
# Music: village (G major, 96 bpm) -- accordion, guitar, flute, light percussion
# --------------------------------------------------------------------------

VILLAGE_CH = {
    "G": (43, [55, 59, 62, 67], [62, 67, 71]),
    "Em": (40, [52, 55, 59, 64], [64, 67, 71]),
    "C": (48, [52, 55, 60, 64], [64, 67, 72]),
    "D": (50, [54, 57, 62, 66], [62, 66, 69]),
    "Am": (45, [52, 57, 60, 64], [64, 69, 72]),
    "D7": (50, [54, 57, 60, 66], [62, 66, 72]),
    "Bm": (47, [54, 59, 62, 66], [62, 66, 71]),
}

_VA = [["G"], ["Em"], ["C"], ["D"], ["G"], ["Em"], ["Am", "D7"], ["G"]]
_VB = [["C"], ["D"], ["Bm"], ["Em"], ["C"], ["D"], ["Am"], ["D7"]]
VILLAGE_PROG = _VA + _VA + _VB + _VA

VILLAGE_MEL_A = [
    [(0, 74, 1), (1, 79, 1), (2, 78, 0.5), (2.5, 79, 0.5), (3, 81, 1)],
    [(0, 79, 2), (2, 76, 1), (3, 71, 1)],
    [(0, 72, 1), (1, 76, 1), (2, 79, 1), (3, 76, 1)],
    [(0, 81, 2), (2, 78, 1), (3, 74, 1)],
    [(0, 74, 1), (1, 79, 1), (2, 78, 0.5), (2.5, 79, 0.5), (3, 83, 1)],
    [(0, 81, 1.5), (1.5, 79, 0.5), (2, 76, 2)],
    [(0, 72, 1), (1, 76, 1), (2, 78, 1), (3, 81, 1)],
    [(0, 79, 3)],
]
VILLAGE_MEL_A2_END = [(0, 79, 2), (2, 83, 0.5), (2.5, 81, 0.5), (3, 79, 1)]
VILLAGE_MEL_B = [
    [(0, 76, 1.5), (1.5, 74, 0.5), (2, 72, 2)],
    [(0, 74, 1.5), (1.5, 72, 0.5), (2, 69, 2)],
    [(0, 71, 1), (1, 74, 1), (2, 78, 2)],
    [(0, 76, 3), (3, 74, 1)],
    [(0, 72, 1), (1, 76, 1), (2, 79, 1.5), (3.5, 78, 0.5)],
    [(0, 76, 1), (1, 74, 1), (2, 78, 2)],
    [(0, 72, 1), (1, 76, 1), (2, 74, 1), (3, 72, 1)],
    [(0, 74, 2), (2, 78, 1), (3, 72, 1)],
]


def make_village():
    sr = SR_MUS
    t = Track(sr, 96.0, 128, seed=96)
    swing = 0.56

    def chord_at(bar, beat):
        cs = VILLAGE_PROG[bar]
        return cs[0] if (len(cs) == 1 or beat < 2) else cs[1]

    for bar in range(32):
        b0 = bar * 4
        sec = bar // 8
        # bass: root on 1, fifth (or new root) on 3
        for half in (0, 1):
            name = chord_at(bar, half * 2)
            root = VILLAGE_CH[name][0]
            if half == 1 and len(VILLAGE_PROG[bar]) == 1:
                root = root + 7 if root + 7 <= 52 else root - 5
            t.bass(b0 + half * 2, root, 0.5 if half == 0 else 0.38, length=1.3)
        # guitar: chick on 2 and 4 (down), light up-strums on the "and"s
        for slot, down, v in ((1, True, 0.11), (1 + swing, False, 0.06),
                              (3, True, 0.11), (3 + swing, False, 0.06)):
            if sec == 2 and not down:
                continue
            name = chord_at(bar, slot)
            notes = VILLAGE_CH[name][1]
            order = notes if down else list(reversed(notes))
            for j, m in enumerate(order):
                t.guitar(b0 + slot, m, v * t.rng.uniform(0.85, 1.1), delay=j * 0.011,
                         length=0.7)
        # accordion pad (merged per chord)
        pg = 0.032 if sec != 2 else 0.022
        cs = VILLAGE_PROG[bar]
        for k, name in enumerate(cs):
            span = 4 if len(cs) == 1 else 2
            t.pad(b0 + 2 * k, VILLAGE_CH[name][2], span, pg, kind="acc", attack=0.12,
                  release=0.35)
        # percussion
        for e in range(8):
            beat = e // 2 + (swing if e % 2 else 0.0)
            acc = 1.0 if e % 2 == 0 else 0.6
            t.put(("sh", e % 2), lambda a=acc, e=e: shaker(sr, 60 + e % 2, a), b0 + beat,
                  0.05 * t.rng.uniform(0.85, 1.1))
        if sec >= 1:
            for beat in (1, 3):
                t.put("wb", lambda: woodblock(sr, 820.0), b0 + beat, 0.07)
        t.put("kick", lambda: frame_drum(sr), b0, 0.22)
        if sec == 2:
            t.put("kick", lambda: frame_drum(sr), b0 + 2, 0.14)
        # melody
        if sec == 2:
            for beat, m, d in VILLAGE_MEL_B[bar - 16]:
                t.pad(b0 + beat, [m], d * 0.92, 0.3, kind="acc", attack=0.03, release=0.12)
        else:
            mel = VILLAGE_MEL_A[bar % 8]
            if bar == 15:
                mel = VILLAGE_MEL_A2_END
            for k, (beat, m, d) in enumerate(mel):
                grace = 2 if (d >= 2 and k == 0 and bar % 2 == 1) else 0
                t.flute(b0 + beat, m, d, 0.36 * (1.05 if beat in (0, 2) else 0.95),
                        grace=grace)
                if sec == 3:
                    t.pad(b0 + beat, [m - 12], d * 0.9, 0.06, kind="acc", attack=0.03,
                          release=0.12)
            if sec == 3:  # harp ripple
                for e in range(8):
                    name = chord_at(bar, e / 2)
                    pcs = [x % 12 for x in VILLAGE_CH[name][1]]
                    pool = [x for x in range(74, 92) if x % 12 in pcs]
                    seq = pool if bar % 2 == 0 else list(reversed(pool))
                    t.harp(b0 + e * 0.5, seq[e % len(seq)], 0.06 if e % 2 else 0.08,
                           bright=0.8, length=1.2)
    buf = finish_loop(t.buf, sr, rt60=1.4, wet=0.2)
    return master_music(buf, sr), sr


# --------------------------------------------------------------------------
# Music: ending (D major, 72 bpm) -- title theme, full ensemble swell
# --------------------------------------------------------------------------

def make_ending():
    sr = SR_MUS
    t = Track(sr, 72.0, 96, seed=73)
    chords = [[(0, c)] for c in TITLE_PROG[:16]]
    chords += [[(0, "G")], [(0, "D/F#")], [(0, "Em")], [(0, "A")], [(0, "G")],
               [(0, "D/F#")], [(0, "G"), (2, "A")], [(0, "D")]]
    melody = TITLE_MEL[:16] + TITLE_MEL[:6] + [[(0, 71, 1), (1, 73, 1), (2, 76, 2)],
                                               [(0, 74, 4)]]
    dyn = [0.55] * 8 + [0.6 + 0.04 * k for k in range(8)] + [1.0] * 6 + [0.95, 0.85]

    for bar in range(24):
        b0 = bar * 4
        sec = bar // 8
        d = dyn[bar]
        segs = chords[bar]
        for k, (cb, name) in enumerate(segs):
            span = (segs[k + 1][0] if k + 1 < len(segs) else 4) - cb
            lh, padv = TITLE_CH[name]
            last = bar == 23
            rel = 2.6 if last else 1.0
            t.pad(b0 + cb, padv, span, 0.05 * d, kind="str", attack=0.5 if sec else 1.2,
                  release=rel)
            if sec >= 1:
                t.pad(b0 + cb, [lh[0], lh[0] + 12], span, 0.05 * d, kind="str",
                      attack=0.4, release=rel, lp=1400.0)
                t.bass(b0 + cb, lh[0], 0.3 * d, length=2.0)
            if bar >= 12:
                cg = 0.04 if bar < 16 else 0.055
                t.pad(b0 + cb, [padv[0] - 12, padv[0], padv[1], padv[2]], span, cg * d,
                      kind="ah", attack=0.7, release=rel)
            if sec >= 1:  # harp eighths
                arp = [lh[1], lh[2], lh[3], padv[1] + 12, padv[2] + 12, padv[1] + 12,
                       lh[3] + 12, lh[3]]
                for e in range(int(span * 2)):
                    m = arp[(e + int(cb * 2)) % 8]
                    t.harp(b0 + cb + e * 0.5, m, (0.09 if sec == 1 else 0.11) * d,
                           bright=0.9, length=1.4)
        if sec == 0:
            piano_lh(t, b0, TITLE_CH[segs[0][1]][0], LH_PAT_A, gain_bass=0.26, gain=0.14)
        if bar >= 12:
            t.put(("timp", 38), lambda: timpani(38, sr), b0, (0.18 if bar < 16 else 0.24) * d)
        if bar >= 16 and bar < 22:
            t.put(("timp", 45), lambda: timpani(45, sr), b0 + 2, 0.14)
        # melody
        for k, (beat, m, dd) in enumerate(melody[bar]):
            acc = 1.05 if k == 0 else 0.95
            if sec == 0:
                t.piano(b0 + beat, m, 0.44 * acc, vel=0.62, dur=dd + 0.5)
            elif sec == 1:
                t.flute(b0 + beat, m, dd, 0.3 * acc, release=0.3, vib_cents=14.0,
                        bright=0.8)
            else:
                t.flute(b0 + beat, m, dd, 0.34 * acc, release=0.3, vib_cents=15.0)
                t.brass(b0 + beat, m - 12, dd, 0.13 * acc)
                if dd >= 2:
                    t.put(("bell", m), lambda m=m: bell(mtof(m + 12), sr, 0.6, 2.2, 0.5),
                          b0 + beat, 0.07)
    t.put("cym", lambda: cymbal_swell(sr, 4 * t.spb), 15 * 4, 0.06, jitter=0.0)
    for j, m in enumerate((74, 78, 81, 86, 90, 93)):  # final sparkle
        t.harp(23 * 4 + j * 0.25, m, 0.1, bright=1.0)
    buf = finish_loop(t.buf, sr, rt60=2.4, wet=0.3)
    return master_music(buf, sr), sr


# --------------------------------------------------------------------------
# Ambience loops
# --------------------------------------------------------------------------

def amb_wind():
    sr = SR_AMB
    n = int(32.0 * sr)
    x = wind_bed(n, sr, seed=1201, base=520.0, depth=2.8, q=0.75, rumble=0.55,
                 whistle=0.12, gust_harm=(1, 2, 3, 4, 5, 7, 9), floor=0.18)
    x = circ(lambda s: onepole_lp(s, 6000.0, sr), x, int(0.1 * sr))
    return circ(dc_block, x, int(1.0 * sr)), sr, AMB_PEAK_DB


def sea_wave(sr, rng, size):
    """One wave: swell, crash, foamy wash and backwash."""
    dur = 7.5
    n = int(dur * sr)
    wn = noise(n, rng)
    t_crash = rng.uniform(1.3, 1.8)
    fc = lambda i: (350.0 + 1500.0 * smoothstep(i / (t_crash * sr))
                    * math.exp(-max(0.0, i / sr - t_crash) / 1.2))
    body = svf_bp(wn, fc, 0.6, sr)
    body = normalize(onepole_lp(body, 2500.0, sr))
    fizz = normalize(biquad(wn, "hp", 3000.0, 0.7, sr))
    flick = [0.5 + 0.5 * v for v in onepole_lp(noise(n, rng), 30.0, sr)]
    fk = peak_of(flick) or 1.0
    out = [0.0] * n
    for i in range(n):
        tt = i / sr
        if tt < t_crash:
            e = smoothstep(tt / t_crash) ** 1.6
        else:
            e = math.exp(-(tt - t_crash) / (1.4 * size))
        ef = smoothstep((tt - t_crash + 0.1) / 0.3) * math.exp(-max(0.0, tt - t_crash) / 1.6)
        back = smoothstep((tt - t_crash - 1.2) / 1.0) * math.exp(-max(0.0, tt - t_crash - 2.2) / 1.2)
        out[i] = (body[i] * (e * size + 0.25 * back)
                  + 0.22 * fizz[i] * ef * (flick[i] / fk) * size)
    return fade(out, sr, 0.01, 0.5)


def amb_sea():
    sr = SR_AMB
    rng = random.Random(1301)
    n = int(36.0 * sr)
    buf = zeros(n)
    # continuous low surf bed (periodic swell)
    wn = noise(n, rng)
    surf = normalize(circ(lambda s: onepole_lp(onepole_lp(s, 380.0, sr), 600.0, sr), wn,
                          int(0.3 * sr)))
    sw = periodic_curve(n, rng, (6, 12, 1, 2))
    mix_into(buf, [s * (0.55 + 0.25 * v) for s, v in zip(surf, sw)], 0, 0.35)
    # six waves (period ~6 s), wrapped
    for k in range(6):
        size = rng.uniform(0.7, 1.0)
        w = sea_wave(sr, rng, size)
        start = int((k * 6.0 + rng.uniform(-0.4, 0.4)) * sr)
        mix_into(buf, w, start, 0.8, wrap=True)
    buf = reverb(buf, sr, rt60=1.0, wet=0.12, circular=True, size=0.8)
    return circ(dc_block, buf, int(1.0 * sr)), sr, AMB_PEAK_DB


def cricket_chirp(sr, f, pulses, rng):
    pulse = 0.016
    gap = 0.012
    n = int(pulses * (pulse + gap) * sr) + 10
    out = [0.0] * n
    for p in range(pulses):
        s = int(p * (pulse + gap) * sr)
        m = int(pulse * sr)
        ff = f * rng.uniform(0.995, 1.005)
        amp = 0.8 + 0.2 * rng.random()
        for i in range(m):
            x = i / m
            e = math.sin(math.pi * x) ** 2
            out[s + i] += amp * e * (math.sin(TAU * ff * i / sr)
                                     + 0.15 * math.sin(TAU * 2 * ff * i / sr))
    return out


def amb_night():
    sr = SR_AMB
    rng = random.Random(1401)
    n = int(30.0 * sr)
    buf = scale(wind_bed(n, sr, seed=1402, base=300.0, depth=2.0, q=0.6, rumble=0.8,
                         gust_harm=(1, 2, 3, 5), floor=0.35), 0.18)
    # three nearby crickets with steady periods that tile the loop
    for f, period, pulses, gain in ((4300.0, 0.82, 3, 0.16), (4750.0, 1.07, 4, 0.11),
                                    (5150.0, 0.63, 2, 0.07)):
        count = max(1, round(30.0 / period))
        per = n / count
        crng = random.Random(int(f))
        variants = [cricket_chirp(sr, f, pulses, crng) for _ in range(3)]
        off = crng.uniform(0, per)
        for k in range(count):
            if crng.random() < 0.12:
                continue  # an occasional pause
            pos = int(off + k * per + crng.uniform(-0.01, 0.01) * sr)
            mix_into(buf, variants[k % 3], pos, gain * crng.uniform(0.8, 1.05), wrap=True)
    # distant chorus: many faint chirps
    for k in range(160):
        f = rng.uniform(3800, 5600)
        ch = cricket_chirp(sr, f, rng.randint(2, 4), rng)
        mix_into(buf, ch, int(rng.uniform(0, n)), 0.025 * rng.uniform(0.5, 1.0), wrap=True)
    # a distant owl, twice
    for start in (7.5, 21.0):
        for j, (dt, f, d) in enumerate(((0.0, 372.0, 0.3), (0.45, 360.0, 0.55))):
            m = int(d * sr)
            hoot = [math.sin(TAU * f * (1.0 - 0.03 * i / m) * i / sr)
                    * math.sin(math.pi * i / m) ** 1.5 for i in range(m)]
            hoot = onepole_lp(hoot, 900.0, sr)
            mix_into(buf, hoot, int((start + dt) * sr), 0.07, wrap=True)
    buf = reverb(buf, sr, rt60=1.6, wet=0.25, circular=True, damp_hz=3500.0)
    return circ(dc_block, buf, int(1.0 * sr)), sr, AMB_PEAK_DB


def amb_birds():
    sr = SR_AMB
    rng = random.Random(1501)
    n = int(34.0 * sr)
    breeze = scale(wind_bed(n, sr, seed=1502, base=650.0, depth=2.2, q=0.7, rumble=0.3,
                            gust_harm=(1, 2, 3, 4, 6), floor=0.3), 0.22)
    birds = zeros(n)
    for k in range(16):
        ph = bird_phrase(sr, rng)
        start = int((k / 16.0 + rng.uniform(0.0, 0.045)) * n)
        dist = rng.uniform(0.0, 1.0)
        ph = onepole_lp(ph, 7000.0 - 3500.0 * dist, sr)
        mix_into(birds, ph, start, (0.5 - 0.35 * dist), wrap=True)
    birds = reverb(birds, sr, rt60=1.3, wet=0.35, circular=True)
    buf = [a + b for a, b in zip(breeze, birds)]
    return circ(dc_block, buf, int(1.0 * sr)), sr, AMB_PEAK_DB


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------

def grains(out, sr, rng, count, t0, t1, flo, fhi, glo, ghi, gain, q=1.3, decay=1.0):
    """Sprinkle tiny band-passed noise grains (rustle / grit / crunch)."""
    for j in range(count):
        gl = int(rng.uniform(glo, ghi) * sr)
        g = biquad(noise(gl, rng), "bp", rng.uniform(flo, fhi), q, sr)
        g = fade(g, sr, fin=0.0008, fout=gl / sr * 0.6)
        pos = rng.uniform(t0, t1)
        w = 1.0 - decay * (pos - t0) / max(1e-6, t1 - t0) * 0.7
        mix_into(out, g, int(pos * sr), gain * w * rng.uniform(0.6, 1.0))


def thud(sr, rng, n, fc, tau, gain=1.0):
    th = onepole_lp(onepole_lp(noise(n, rng), fc, sr), fc, sr)
    pk = peak_of(th) or 1.0
    k = 1.0 / (tau * sr)
    return [gain * v / pk * math.exp(-k * i) for i, v in enumerate(th)]


def swept_noise(sr, rng, dur, fc_fn, q, env_fn):
    n = int(dur * sr)
    wn = noise(n, rng)
    x = normalize(svf_bp(wn, lambda i: fc_fn(i / sr), q, sr))
    return [v * env_fn(i / sr) for i, v in enumerate(x)]


def bubble(sr, f0, dur, rise=1.8):
    n = int(dur * sr)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / sr
        f = f0 * (1.0 + (rise - 1.0) * t / dur)
        ph += TAU * f / sr
        out[i] = math.sin(ph) * math.exp(-t / (dur * 0.35)) * min(1.0, t / 0.001)
    return out


def voiced(sr, dur, f0_fn, formant_fn, amp_fn, tilt=0.7, every=8):
    """Formant-shaped harmonic source (glide-friendly, no filter artifacts)."""
    n = int(dur * sr)
    out = [0.0] * n
    ph = 0.0
    nyq = sr * 0.45
    amps = []
    for i in range(n):
        t = i / sr
        f0 = f0_fn(t)
        ph += TAU * f0 / sr
        if i % every == 0:
            fm = formant_fn(t)
            H = int(nyq / f0)
            amps = []
            for h in range(1, H + 1):
                fh = h * f0
                r = 0.015
                for F, B, G in fm:
                    d = (fh - F) / B
                    r += G / (1.0 + d * d)
                amps.append(r * h ** -tilt)
        s = 0.0
        for h, a in enumerate(amps, 1):
            s += a * math.sin(h * ph)
        out[i] = s * amp_fn(t)
    return out


def sparkle(out, sr, rng, count, t0, t1, gain, flo=4500, fhi=8500):
    for _ in range(count):
        f = rng.uniform(flo, fhi)
        s = additive(sr, int(0.07 * sr), f, [(1.0, 1.0, 0.016)], attack=0.001)
        mix_into(out, s, int(rng.uniform(t0, t1) * sr), gain * rng.uniform(0.5, 1.0))


# ---- footsteps -----------------------------------------------------------
#
# Footsteps fire every ~0.35 s while running, so they are deliberately soft,
# textured and non-tonal (no sine modes): filtered noise, noise grains and
# noise-excited, heavily damped resonators.  Each surface has STEP_VARIANTS
# takes that differ in heel->toe timing, spectral tilt and length; the set is
# loudness-matched (common RMS) by match_loudness() so no take pops out.

STEP_VARIANTS = 6


def ad_env(t, att, dec):
    """Smooth (sin^2) attack then exponential decay; 0 before t = 0."""
    if t <= 0.0:
        return 0.0
    if t < att:
        return math.sin(0.5 * math.pi * t / att) ** 2
    return math.exp(-(t - att) / dec)


def _spread(k, lo, hi, order):
    """k-th take's value: STEP_VARIANTS values evenly spread over [lo, hi],
    handed out in `order` so the parameters don't all move together."""
    return lo + (hi - lo) * order[k] / (len(order) - 1)


def rustle_texture(n, sr, rng, rate, floor=0.35):
    """Random crackly amplitude modulation in [floor, 1] (leaves / blades)."""
    tx = onepole_lp([abs(v) ** 3 for v in noise(n, rng)], rate, sr)
    pk = peak_of(tx) or 1.0
    return [floor + (1.0 - floor) * v / pk for v in tx]


def foot_pat(sr, rng, fc, tau, attack=0.004):
    """Very soft low 'pat' of the foot: double-lowpassed noise, smooth onset."""
    p = thud(sr, rng, int((tau * 5 + attack) * sr), fc, tau)
    na = attack * sr
    return [v * smoothstep(i / na) for i, v in enumerate(p)]


def match_loudness(sigs, sr, peak_db, rms_tol_db=0.5, over_db=0.8):
    """Master a set of takes to one loudness: each take's gain puts its peak at
    peak_db, but is clamped so its RMS stays within +-rms_tol_db of the group's
    mean RMS (equal loudness first, peaks as close to peak_db as that allows);
    a stray grain poking more than over_db above peak_db is gently limited."""
    pk = 10.0 ** (peak_db / 20.0)
    ceil = 10.0 ** ((peak_db + over_db) / 20.0)
    sigs = [biquad(x, "hp", 45.0, 0.7, sr) for x in sigs]   # no sub-bass / DC drift
    sigs = [normalize(fade(dc_block(x, 0.999), sr, fin=0.0003, fout=0.004), pk) for x in sigs]
    rms = [rms_of(x) for x in sigs]
    target = math.exp(sum(math.log(r) for r in rms) / len(rms))
    tol = 10.0 ** (rms_tol_db / 20.0)
    out = []
    for x, r in zip(sigs, rms):
        g = clamp(1.0, target / r / tol, target / r * tol)
        want = r * g
        y = scale(x, g)
        for _ in range(4):  # limit, then make up the RMS the limiter took away
            if peak_of(y) <= ceil * 1.0001:
                break
            y = [a * b for a, b in zip(y, limiter_gain(y, ceil, sr, attack=0.002, release=0.03))]
            g *= want / rms_of(y)
            y = scale(x, g)
        if peak_of(y) > ceil:
            y = [a * b for a, b in zip(y, limiter_gain(y, ceil, sr, attack=0.002, release=0.03))]
        out.append(y)
    return out


def step_grass(k):
    """Soft grass rustle: heel + toe noise swells (1.5-6 kHz) with crackly
    texture, a few blade grains and a barely-there low pat."""
    sr = SR_SFX
    rng = random.Random(1200 + 31 * k)
    dur = _spread(k, 0.125, 0.195, (2, 5, 0, 4, 1, 3))
    gap = _spread(k, 0.026, 0.044, (0, 3, 5, 1, 4, 2))
    lpc = _spread(k, 4200.0, 6600.0, (4, 1, 3, 0, 5, 2))
    att = _spread(k, 0.004, 0.009, (1, 4, 2, 5, 0, 3))
    toe = rng.uniform(0.5, 0.85)
    t_h = rng.uniform(0.002, 0.007)
    dec_h = rng.uniform(0.016, 0.028)
    dec_t = rng.uniform(0.02, 0.036)
    tail = rng.uniform(0.035, 0.06)
    n = int(dur * sr)
    band = normalize(biquad(biquad(noise(n, rng), "hp", 1500.0, 0.6, sr), "lp", lpc, 0.6, sr))
    tex = rustle_texture(n, sr, rng, rng.uniform(90.0, 170.0))
    out = zeros(n)
    for i in range(n):
        t = i / sr - t_h
        e = (ad_env(t, att, dec_h) + toe * ad_env(t - gap, att * 0.8, dec_t)
             + 0.2 * ad_env(t - 0.01, 0.02, tail))
        out[i] = band[i] * e * tex[i]
    grains(out, sr, rng, rng.randint(8, 14), t_h, dur * 0.75, 1800.0, min(lpc, 5200.0),
           0.003, 0.008, 0.16, q=0.9)
    pat = foot_pat(sr, rng, rng.uniform(90.0, 140.0), rng.uniform(0.012, 0.02))
    mix_into(out, pat, int(t_h * sr), 0.2 * peak_of(out))
    out = onepole_lp(out, lpc * 1.3, sr)
    return fade(out, sr, fin=0.003, fout=0.03)


def step_sand(k):
    """Soft granular crunch: clusters of tiny noise grains (heel, then toe),
    a compressing 'shff' bed, lowpassed around 3 kHz (broadband = no squeak)."""
    sr = SR_SFX
    rng = random.Random(1300 + 31 * k)
    dur = _spread(k, 0.15, 0.215, (3, 0, 5, 2, 4, 1))
    gap = _spread(k, 0.028, 0.045, (5, 2, 0, 4, 1, 3))
    lpc = _spread(k, 2600.0, 3400.0, (1, 5, 2, 0, 3, 4))
    toe = rng.uniform(0.55, 0.85)
    t_h = rng.uniform(0.003, 0.008)
    n = int(dur * sr)
    gr = zeros(n)
    for t_ev, amp, spr, count in ((t_h, 1.0, rng.uniform(0.05, 0.075), rng.randint(45, 70)),
                                  (t_h + gap, toe, rng.uniform(0.06, 0.09), rng.randint(40, 65))):
        for _ in range(count):
            u = rng.random() ** 1.6
            pos = t_ev + spr * u
            gl = int(rng.uniform(0.0006, 0.0025) * sr) + 2
            tau = rng.uniform(0.0002, 0.0007) * sr
            a = amp * (0.15 + 0.85 * rng.random() ** 2) * (1.0 - 0.6 * u)
            mix_into(gr, [rng.uniform(-1, 1) * math.exp(-i / tau) for i in range(gl)],
                     int(pos * sr), a)
    gr = normalize(gr)
    bed = normalize(onepole_lp(noise(n, rng), 1500.0, sr))
    out = zeros(n)
    for i in range(n):
        t = i / sr - t_h
        e = ad_env(t, 0.008, 0.035) + toe * ad_env(t - gap, 0.008, 0.045)
        out[i] = gr[i] + 0.3 * bed[i] * e
    pat = foot_pat(sr, rng, rng.uniform(85.0, 130.0), rng.uniform(0.014, 0.022))
    mix_into(out, pat, int(t_h * sr), 0.22 * peak_of(out))
    out = biquad(out, "hp", 180.0, 0.7, sr)
    out = onepole_lp(biquad(out, "lp", lpc, 0.6, sr), lpc * 1.5, sr)
    return fade(out, sr, fin=0.002, fout=0.035)


def step_stone(k):
    """Muted scuff on rock: soft contact transient, low noise thud, a sole
    scuff toward the toe and a tiny gritty tail (no modes -> no ringing)."""
    sr = SR_SFX
    rng = random.Random(1400 + 31 * k)
    dur = _spread(k, 0.09, 0.15, (4, 1, 3, 0, 5, 2))
    gap = _spread(k, 0.022, 0.04, (2, 4, 0, 5, 3, 1))
    lpc = _spread(k, 3800.0, 6200.0, (0, 3, 5, 2, 1, 4))
    t_h = rng.uniform(0.002, 0.006)
    n = int(dur * sr)
    out = zeros(n)
    m = int(0.007 * sr)
    tr = biquad(biquad(noise(m, rng), "hp", 1500.0, 0.7, sr), "lp", lpc, 0.7, sr)
    dk = rng.uniform(0.0018, 0.003)
    mix_into(out, [v * ad_env(i / sr, 0.0008, dk) for i, v in enumerate(normalize(tr))],
             int(t_h * sr), 0.55)
    mix_into(out, foot_pat(sr, rng, rng.uniform(150.0, 230.0), rng.uniform(0.009, 0.015),
                           attack=0.0015), int(t_h * sr), 1.0)
    sc = normalize(biquad(biquad(noise(n, rng), "hp", 900.0, 0.6, sr), "lp", 3500.0, 0.6, sr))
    t_s = gap * rng.uniform(0.5, 0.8)
    toe = rng.uniform(0.2, 0.4)
    dec_s = rng.uniform(0.014, 0.024)
    for i in range(n):
        t = i / sr - t_h
        out[i] += sc[i] * (0.3 * ad_env(t - t_s, 0.004, dec_s)
                           + toe * ad_env(t - gap, 0.001, 0.006))
    grains(out, sr, rng, rng.randint(5, 9), t_h + 0.012, dur * 0.85, 2500.0, 5000.0,
           0.0015, 0.004, 0.12, q=0.8)
    out = onepole_lp(out, lpc, sr)
    return fade(out, sr, fin=0.0015, fout=0.025)


def wood_knock(sr, rng, n, f1, q):
    """Noise-excited, heavily damped plank body (hollow, decays in ~10 ms)."""
    m = int(0.004 * sr)
    exc = onepole_lp(noise(m, rng), 2500.0, sr)
    exc = [v * ad_env(i / sr, 0.0006, 0.0012) for i, v in enumerate(exc)] + zeros(n - m)
    body = normalize(biquad(exc, "bp", f1, q, sr))
    b2 = normalize(biquad(exc, "bp", f1 * rng.uniform(2.05, 2.3), q * 0.9, sr))
    b3 = normalize(biquad(exc, "bp", f1 * rng.uniform(3.4, 3.9), 4.0, sr))
    th = thud(sr, rng, n, 320.0, 0.008)
    ce = normalize(exc)
    return [a + 0.4 * b + 0.15 * c + 0.3 * d + 0.2 * e
            for a, b, c, d, e in zip(body, b2, b3, th, ce)]


def step_wood(k):
    """Hollow, muted knock on planks: heel + toe noise-excited body around
    150-300 Hz decaying fast, plus (on some takes) a faint board creak."""
    sr = SR_SFX
    rng = random.Random(1500 + 31 * k)
    dur = _spread(k, 0.12, 0.195, (1, 4, 2, 5, 0, 3))
    gap = _spread(k, 0.025, 0.042, (3, 0, 4, 1, 5, 2))
    f1 = _spread(k, 160.0, 280.0, (5, 2, 0, 3, 1, 4))
    lpc = _spread(k, 3200.0, 5000.0, (2, 5, 3, 0, 4, 1))
    q = rng.uniform(4.0, 5.5)
    toe = rng.uniform(0.45, 0.7)
    t_h = rng.uniform(0.002, 0.005)
    n = int(dur * sr)
    out = zeros(n)
    mix_into(out, wood_knock(sr, rng, n, f1, q), int(t_h * sr), 1.0)
    mix_into(out, wood_knock(sr, rng, n, f1 * rng.uniform(1.03, 1.1), q * 0.9),
             int((t_h + gap) * sr), toe)
    if k in (1, 3, 4):
        mix_into(out, creak(sr, rng, rng.uniform(0.05, 0.08)),
                 int((t_h + gap + 0.01) * sr), 0.035 * peak_of(out))
    out = onepole_lp(onepole_lp(out, lpc, sr), lpc * 1.5, sr)
    return fade(out, sr, fin=0.0015, fout=0.035)


def step_water(k):
    """Shallow-water step: falling band of splash noise (heel, toe), a low
    slosh, a few small bubbles and a little fizz."""
    sr = SR_SFX
    rng = random.Random(1600 + 31 * k)
    dur = _spread(k, 0.15, 0.245, (0, 3, 5, 1, 4, 2))
    gap = _spread(k, 0.03, 0.05, (4, 1, 2, 5, 0, 3))
    fc0 = _spread(k, 1800.0, 3000.0, (2, 0, 4, 1, 3, 5))
    toe = rng.uniform(0.5, 0.8)
    t_h = rng.uniform(0.003, 0.007)
    dh = rng.uniform(0.028, 0.042)
    dt = rng.uniform(0.04, 0.06)
    n = int(dur * sr)
    wn = noise(n, rng)
    sp = normalize(svf_bp(wn, lambda i: fc0 * 0.4 ** smoothstep((i / sr - t_h) / 0.1), 0.9, sr))
    sl = normalize(onepole_lp(onepole_lp(noise(n, rng), 500.0, sr), 500.0, sr))
    out = zeros(n)
    for i in range(n):
        t = i / sr - t_h
        out[i] = (sp[i] * (ad_env(t, 0.004, dh) + toe * ad_env(t - gap, 0.005, dt))
                  + 0.45 * sl[i] * ad_env(t - 0.005, 0.012, 0.06))
    for _ in range(rng.randint(3, 6)):
        mix_into(out, bubble(sr, rng.uniform(600.0, 1600.0), rng.uniform(0.015, 0.035),
                             rng.uniform(1.4, 2.0)),
                 int(rng.uniform(t_h + 0.02, dur - 0.04) * sr), rng.uniform(0.1, 0.2))
    grains(out, sr, rng, rng.randint(6, 10), t_h + 0.01, dur * 0.8, 3000.0, 5500.0,
           0.002, 0.005, 0.08, q=0.9)
    out = onepole_lp(out, 6000.0, sr)
    return fade(out, sr, fin=0.003, fout=0.04)


STEP_SURFACES = {"grass": step_grass, "sand": step_sand, "stone": step_stone,
                 "wood": step_wood, "water": step_water}
FOOTSTEP_PEAK_DB = -12.0
_STEP_SETS = Cache()


def step_variant(surface, k):
    sets = _STEP_SETS.get(surface, lambda: match_loudness(
        [STEP_SURFACES[surface](j) for j in range(STEP_VARIANTS)], SR_SFX, FOOTSTEP_PEAK_DB))
    return sets[k][:], SR_SFX, RAW


# ---- movement --------------------------------------------------------------

def sfx_jump():
    sr = SR_SFX
    rng = random.Random(110)
    dur = 0.32
    n = int(dur * sr)
    out = zeros(n)
    ph = 0.0
    tone = [0.0] * n
    for i in range(n):
        t = i / sr
        f = 250.0 * (2.4 ** smoothstep(t / 0.12))
        ph += TAU * f / sr
        tone[i] = (math.sin(ph) + 0.15 * math.sin(2 * ph)) * min(1.0, t / 0.004) \
            * math.exp(-t / 0.06)
    mix_into(out, tone, 0, 0.35)
    wh = swept_noise(sr, rng, dur, lambda t: 600.0 * 3.5 ** smoothstep(t / 0.25), 1.4,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.3)) ** 2)
    mix_into(out, wh, 0, 0.5)
    mix_into(out, modal_hit(sr, 0.06, [(120, 1.0, 0.012)], 0.2, 0.005), 0, 0.35)
    grains(out, sr, rng, 4, 0.0, 0.1, 1500, 3000, 0.008, 0.015, 0.15)
    return fade(out, sr, 0.001, 0.05), sr, SFX_PEAK_DB


def body_pulse(sr, width):
    """One smooth raised-cosine push: body weight without any ringing."""
    m = max(2, int(width * sr))
    p = [0.5 - 0.5 * math.cos(TAU * i / m) for i in range(m)]
    return normalize(dc_block(p + zeros(int(0.05 * sr)), 0.995))


def sfx_land():
    """Soft body thump (noise + one smooth push, no modes) and a grass/dust
    rustle kicked up by both feet."""
    sr = SR_SFX
    rng = random.Random(111)
    n = int(0.34 * sr)
    out = zeros(n)
    t0 = 0.004
    mix_into(out, foot_pat(sr, rng, 120.0, 0.03, attack=0.004), int(t0 * sr), 1.0)
    mix_into(out, body_pulse(sr, 0.016), int(t0 * sr), 0.45)
    band = normalize(biquad(biquad(noise(n, rng), "hp", 1200.0, 0.6, sr), "lp", 5000.0, 0.6, sr))
    tex = rustle_texture(n, sr, rng, 130.0)
    dust = normalize(biquad(noise(n, rng), "bp", 900.0, 0.7, sr))
    for i in range(n):
        t = i / sr - t0
        out[i] += (0.3 * band[i] * tex[i] * (ad_env(t, 0.006, 0.03) + 0.7 * ad_env(t - 0.03, 0.006, 0.035)
                                             + 0.25 * ad_env(t - 0.02, 0.03, 0.08))
                   + 0.15 * dust[i] * ad_env(t, 0.012, 0.07))
    grains(out, sr, rng, 14, t0 + 0.005, 0.2, 1800.0, 4500.0, 0.003, 0.008, 0.1, q=0.9)
    out = onepole_lp(out, 6000.0, sr)
    return fade(out, sr, 0.003, 0.08), sr, -8.0


def sfx_land_heavy():
    """Deeper thump with a dust cloud swelling and settling, some debris grit."""
    sr = SR_SFX
    rng = random.Random(112)
    n = int(0.7 * sr)
    out = zeros(n)
    t0 = 0.004
    mix_into(out, foot_pat(sr, rng, 75.0, 0.06, attack=0.006), int(t0 * sr), 1.0)
    mix_into(out, body_pulse(sr, 0.026), int(t0 * sr), 0.55)
    mix_into(out, foot_pat(sr, rng, 170.0, 0.02, attack=0.003), int(t0 * sr), 0.35)
    puff = swept_noise(sr, rng, 0.62, lambda t: 1800.0 * 0.3 ** smoothstep(t / 0.35), 0.7,
                       lambda t: ad_env(t, 0.015, 0.16))
    mix_into(out, puff, int(t0 * sr), 0.32)
    band = normalize(biquad(biquad(noise(n, rng), "hp", 1200.0, 0.6, sr), "lp", 4500.0, 0.6, sr))
    tex = rustle_texture(n, sr, rng, 110.0)
    for i in range(n):
        t = i / sr - t0
        out[i] += 0.26 * band[i] * tex[i] * (ad_env(t, 0.006, 0.04) + 0.6 * ad_env(t - 0.035, 0.008, 0.05))
    grains(out, sr, rng, 22, 0.05, 0.45, 1500.0, 4000.0, 0.003, 0.008, 0.08, q=0.9)
    out = onepole_lp(out, 4500.0, sr)
    out = reverb(out, sr, rt60=0.5, wet=0.1, size=0.6)[:n]
    return fade(out, sr, 0.003, 0.15), sr, -5.0


def cloth_flap(sr, rng, fc, decay):
    n = int((decay * 6) * sr)
    x = biquad(noise(n, rng), "bp", fc, 1.0, sr)
    k = 1.0 / (decay * sr)
    return [v * math.exp(-k * i) * min(1.0, i / (0.001 * sr)) for i, v in enumerate(x)]


def sfx_glide_open():
    sr = SR_SFX
    rng = random.Random(120)
    n = int(0.85 * sr)
    out = zeros(n)
    for t0, g, fc, dk in ((0.0, 0.35, 1300, 0.012), (0.035, 0.55, 1500, 0.012),
                          (0.07, 1.0, 2100, 0.022)):
        mix_into(out, cloth_flap(sr, rng, fc, dk), int(t0 * sr), g)
    mix_into(out, modal_hit(sr, 0.12, [(160, 1.0, 0.025), (320, 0.3, 0.01)], 0.3, 0.006),
             int(0.07 * sr), 0.45)
    mix_into(out, thud(sr, rng, int(0.4 * sr), 350, 0.12, 1.0), int(0.07 * sr), 0.45)
    wh = swept_noise(sr, rng, 0.8,
                     lambda t: 500.0 + 2100.0 * smoothstep(t / 0.3) - 1100.0 * smoothstep((t - 0.3) / 0.5),
                     1.2, lambda t: smoothstep((t - 0.03) / 0.2) * (1.0 - smoothstep((t - 0.35) / 0.45)))
    mix_into(out, wh, int(0.03 * sr), 0.45)
    out = reverb(out, sr, rt60=0.5, wet=0.1, size=0.6)[:n]
    return fade(out, sr, 0.0008, 0.1), sr, SFX_PEAK_DB


def sfx_glide_close():
    sr = SR_SFX
    rng = random.Random(121)
    n = int(0.5 * sr)
    out = zeros(n)
    wh = swept_noise(sr, rng, 0.42, lambda t: 2200.0 * (0.23 ** smoothstep(t / 0.35)), 1.2,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.42)) ** 2)
    mix_into(out, wh, 0, 0.5)
    fl = biquad(noise(n, rng), "bp", 1300, 1.0, sr)
    for i in range(n):
        t = i / sr
        am = (0.5 + 0.5 * math.sin(TAU * 28.0 * t)) ** 2
        out[i] += 0.35 * fl[i] * am * smoothstep((t - 0.03) / 0.05) * math.exp(-max(0.0, t - 0.08) / 0.08)
    tap = modal_hit(sr, 0.08, [(300, 1.0, 0.015), (700, 0.3, 0.006)], 0.1, 0.005)
    mix_into(out, tap, int(0.27 * sr), 0.3)
    out = onepole_lp(out, 6000, sr)
    return fade(out, sr, 0.003, 0.06), sr, SFX_PEAK_DB


def sfx_climb():
    sr = SR_SFX
    rng = random.Random(130)
    n = int(0.13 * sr)
    x = zeros(n)
    sc = biquad(noise(n, rng), "bp", 2400, 0.9, sr)
    for i in range(n):
        t = i / sr
        x[i] = 0.5 * sc[i] * min(1.0, t / 0.002) * math.exp(-t / 0.022)
    grains(x, sr, rng, 4, 0.0, 0.04, 3000, 5000, 0.002, 0.004, 0.25)
    mix_into(x, modal_hit(sr, 0.1, [(190, 1.0, 0.018), (420, 0.4, 0.008)], 0.15, 0.004), 0, 0.7)
    x = onepole_lp(x, 7000, sr)
    return fade(x, sr, 0.0008, 0.03), sr, STEP_PEAK_DB


def sfx_mantle():
    sr = SR_SFX
    rng = random.Random(131)
    n = int(0.6 * sr)
    out = zeros(n)
    wh = swept_noise(sr, rng, 0.48, lambda t: 400.0 * 4.5 ** smoothstep(t / 0.4), 1.3,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.48)) ** 1.5)
    mix_into(out, wh, 0, 0.6)
    grains(out, sr, rng, 7, 0.04, 0.32, 1500, 3200, 0.01, 0.025, 0.18)
    grab = modal_hit(sr, 0.08, [(200, 1.0, 0.015), (450, 0.3, 0.006)], 0.15, 0.004)
    mix_into(out, grab, 0, 0.3)
    mix_into(out, modal_hit(sr, 0.15, [(150, 1.0, 0.03), (330, 0.3, 0.012)], 0.25, 0.008),
             int(0.42 * sr), 0.45)
    mix_into(out, thud(sr, rng, int(0.12 * sr), 600, 0.015, 0.5), int(0.42 * sr))
    out = onepole_lp(out, 6500, sr)
    return fade(out, sr, 0.002, 0.05), sr, SFX_PEAK_DB


# ---- water ---------------------------------------------------------------

def sfx_splash():
    sr = SR_SFX
    rng = random.Random(140)
    n = int(1.2 * sr)
    out = zeros(n)
    wn = noise(n, rng)
    imp = onepole_lp(wn, 3000, sr)
    body = svf_bp(wn, lambda i: 2800.0 * 0.22 ** smoothstep(i / (0.5 * sr)), 0.7, sr)
    body = normalize(body)
    pk = peak_of(imp) or 1.0
    for i in range(n):
        t = i / sr
        out[i] = (0.5 * imp[i] / pk * math.exp(-t / 0.05)
                  + 0.8 * body[i] * smoothstep(t / 0.01) * math.exp(-t / 0.28))
    mix_into(out, modal_hit(sr, 0.2, [(90, 1.0, 0.05)], 0.4, 0.01), 0, 0.5)
    for _ in range(22):
        f0 = rng.uniform(450, 1500)
        d = rng.uniform(0.02, 0.05)
        mix_into(out, bubble(sr, f0, d, rng.uniform(1.4, 2.0)),
                 int(rng.uniform(0.08, 0.85) * sr), 0.14 * rng.uniform(0.4, 1.0))
    for _ in range(10):
        f0 = rng.uniform(1600, 3200)
        mix_into(out, bubble(sr, f0, 0.025, 1.3), int(rng.uniform(0.25, 1.0) * sr),
                 0.08 * rng.uniform(0.4, 1.0))
    out = onepole_lp(out, 7000, sr)
    out = reverb(out, sr, rt60=0.6, wet=0.12, size=0.7)[:n]
    return fade(out, sr, 0.001, 0.2), sr, SFX_PEAK_DB


def sfx_swim():
    sr = SR_SFX
    rng = random.Random(141)
    n = int(0.65 * sr)
    out = zeros(n)
    sw = swept_noise(sr, rng, 0.5,
                     lambda t: 500.0 + 800.0 * math.sin(math.pi * min(1.0, t / 0.45)),
                     0.8, lambda t: math.sin(math.pi * min(1.0, t / 0.45)) ** 2)
    mix_into(out, sw, 0, 0.6)
    sl = thud(sr, rng, int(0.5 * sr), 600, 0.15, 1.0)
    sl = [v * smoothstep(i / (0.12 * sr)) for i, v in enumerate(sl)]
    mix_into(out, sl, int(0.05 * sr), 0.35)
    for _ in range(6):
        mix_into(out, bubble(sr, rng.uniform(600, 1400), rng.uniform(0.02, 0.04), 1.7),
                 int(rng.uniform(0.15, 0.5) * sr), 0.12 * rng.uniform(0.5, 1.0))
    out = onepole_lp(out, 6000, sr)
    out = reverb(out, sr, rt60=0.4, wet=0.1, size=0.6)[:n]
    return fade(out, sr, 0.01, 0.1), sr, SFX_PEAK_DB


# ---- stamina ---------------------------------------------------------------

def sfx_stamina_low():
    sr = SR_SFX
    rng = random.Random(150)
    n = int(0.6 * sr)
    out = zeros(n)
    lub = modal_hit(sr, 0.3, [(78, 1.0, 0.06), (156, 0.35, 0.03)], 0.25, 0.01)
    lub = add(lub, thud(sr, rng, int(0.06 * sr), 200, 0.015, 0.6))
    dub = modal_hit(sr, 0.3, [(92, 0.7, 0.05), (184, 0.25, 0.025)], 0.25, 0.01)
    mix_into(out, lub, 0, 1.0)
    mix_into(out, dub, int(0.2 * sr), 0.85)
    tone = additive(sr, int(0.5 * sr), mtof(76), [(1.0, 1.0, 0.12), (2.0, 0.15, 0.06)], 0.01)
    mix_into(out, tone, 0, 0.12)
    out = onepole_lp(out, 3000, sr)
    return fade(out, sr, 0.001, 0.08), sr, SFX_PEAK_DB


def sfx_stamina_up():
    sr = SR_SFX
    rng = random.Random(151)
    n = int(1.7 * sr)
    out = zeros(n)
    wh = swept_noise(sr, rng, 0.9, lambda t: 400.0 * 7.0 ** smoothstep(t / 0.8), 2.0,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.9)) ** 2)
    mix_into(out, wh, 0, 0.12)
    for k, m in enumerate((76, 80, 83, 88, 92, 95)):
        mix_into(out, celesta(m, sr, 1.2), int(k * 0.07 * sr), 0.35 + 0.03 * k)
        mix_into(out, bell(mtof(m), sr, 0.35, 0.9, 0.5), int(k * 0.07 * sr), 0.12)
    for m in (64, 68, 71, 76):
        mix_into(out, tpad(m, 0.8, sr, "ah", attack=0.3, release=0.6), int(0.05 * sr), 0.12)
    sparkle(out, sr, rng, 12, 0.3, 1.1, 0.08)
    out = reverb(out, sr, rt60=1.2, wet=0.25, size=0.7)[:n]
    return fade(out, sr, 0.003, 0.35), sr, SFX_PEAK_DB


# ---- pickups ---------------------------------------------------------------

def sfx_shell():
    sr = SR_SFX
    rng = random.Random(160)
    out = zeros(int(0.6 * sr))
    for t, m, v in ((0.0, 91, 0.6), (0.055, 98, 0.85)):
        mix_into(out, bell(mtof(m), sr, tau=0.18, length=0.5, bright=0.35), int(t * sr), v)
        mix_into(out, harp(m - 12, sr, 0.5, bright=0.6), int(t * sr), v * 0.4)
    sparkle(out, sr, rng, 3, 0.04, 0.15, 0.08)
    out = reverb(out, sr, rt60=0.6, wet=0.12, size=0.5)[:int(0.55 * sr)]
    return fade(out, sr, fin=0.0006, fout=0.15), sr, SFX_PEAK_DB


def sfx_feather():
    sr = SR_SFX
    rng = random.Random(161)
    n = int(1.6 * sr)
    out = zeros(n)
    arp = [79, 83, 86, 90, 93, 95, 98, 102]
    for k, m in enumerate(arp):
        mix_into(out, musicbox(m, sr, 1.0), int(k * 0.065 * sr), 0.3 + 0.03 * k)
    for k, m in enumerate((98, 95, 91)):
        mix_into(out, musicbox(m, sr, 1.0), int((0.58 + k * 0.08) * sr), 0.22)
    for m in (91, 98):
        mix_into(out, bell(mtof(m), sr, 0.5, 1.0, 0.4), int(0.55 * sr), 0.18)
    for m in (67, 74, 79, 83):
        mix_into(out, harp(m, sr, 1.0), int(0.55 * sr), 0.12)
    sh = swept_noise(sr, rng, 1.2, lambda t: 2000.0 * 1.6 ** smoothstep(t / 1.0), 3.0,
                     lambda t: math.sin(math.pi * min(1.0, t / 1.2)) ** 2)
    mix_into(out, sh, 0, 0.06)
    sparkle(out, sr, rng, 16, 0.05, 1.2, 0.09)
    out = reverb(out, sr, rt60=1.3, wet=0.3, size=0.7)[:n]
    return fade(out, sr, 0.001, 0.4), sr, SFX_PEAK_DB


def sfx_item():
    sr = SR_SFX
    rng = random.Random(162)
    n = int(1.6 * sr)
    out = zeros(n)
    for t, m, d in ((0.0, 67, 0.08), (0.1, 72, 0.08), (0.2, 76, 0.08), (0.3, 79, 0.85)):
        mix_into(out, brass(m - 12, d, sr), int(t * sr), 0.45)
        mix_into(out, flute(m + 12 if m < 79 else m, d, sr, release=0.2, breath=0.6),
                 int(t * sr), 0.35)
    for m in (60, 64, 67):
        mix_into(out, brass(m, 0.85, sr), int(0.3 * sr), 0.28)
    for j, m in enumerate((72, 76, 79, 84, 88)):
        mix_into(out, harp(m, sr, 1.0), int((0.3 + j * 0.03) * sr), 0.16)
    for m in (91, 96):
        mix_into(out, bell(mtof(m), sr, 0.5, 1.1, 0.5), int(0.3 * sr), 0.14)
    mix_into(out, timpani(48, sr, 0.8), int(0.3 * sr), 0.35)
    sparkle(out, sr, rng, 8, 0.35, 1.0, 0.06)
    out = reverb(out, sr, rt60=1.1, wet=0.22, size=0.7)[:n]
    return fade(out, sr, 0.001, 0.35), sr, SFX_PEAK_DB


def creak(sr, rng, dur):
    n = int(dur * sr)
    imp = [0.0] * n
    t = 0.0
    while t < dur:
        x = t / dur
        rate = 70.0 + 120.0 * math.sin(math.pi * x) + 20.0 * math.sin(TAU * 3.0 * x)
        imp[min(n - 1, int(t * sr))] = rng.uniform(0.6, 1.0)
        t += (1.0 / rate) * rng.uniform(0.85, 1.15)
    cr = add(add(biquad(imp, "bp", 600, 9.0, sr), scale(biquad(imp, "bp", 1250, 11.0, sr), 0.7)),
             scale(biquad(imp, "bp", 2200, 9.0, sr), 0.3))
    for i in range(n):
        cr[i] *= math.sin(math.pi * i / n) ** 0.8
    return normalize(cr)


def sfx_chest():
    sr = SR_SFX
    rng = random.Random(163)
    n = int(1.7 * sr)
    out = zeros(n)
    mix_into(out, creak(sr, rng, 0.36), 0, 0.4)
    lid = modal_hit(sr, 0.2, [(140, 1.0, 0.05), (330, 0.5, 0.03), (760, 0.2, 0.012)], 0.2, 0.008)
    lid = add(lid, thud(sr, rng, int(0.1 * sr), 800, 0.015, 0.8))
    mix_into(out, normalize(lid), int(0.37 * sr), 0.7)
    for k, m in enumerate((72, 76, 79, 84, 88, 91)):
        mix_into(out, harp(m, sr, 1.0), int((0.45 + k * 0.06) * sr), 0.22)
        mix_into(out, bell(mtof(m + 12), sr, 0.25, 0.6, 0.4), int((0.45 + k * 0.06) * sr), 0.08)
    for m in (84, 88, 91, 96):
        mix_into(out, bell(mtof(m), sr, 0.45, 1.0, 0.4), int(0.85 * sr), 0.1)
    sparkle(out, sr, rng, 12, 0.5, 1.3, 0.08)
    out = reverb(out, sr, rt60=1.0, wet=0.2, size=0.7)[:n]
    return fade(out, sr, 0.002, 0.35), sr, SFX_PEAK_DB


def sfx_spark():
    sr = SR_SFX
    rng = random.Random(164)
    n = int(0.9 * sr)
    out = zeros(n)
    fire = thud(sr, rng, n, 900, 10.0, 1.0)
    for i in range(n):
        t = i / sr
        fire[i] *= smoothstep(t / 0.08) * math.exp(-t / 0.25)
    mix_into(out, fire, 0, 0.35)
    for _ in range(28):
        pos = rng.random() ** 1.6 * 0.6
        m = int(rng.uniform(0.001, 0.003) * sr)
        c = biquad(noise(m + 20, rng), "bp", rng.uniform(1500, 4000), 1.2, sr)
        c = [v * math.exp(-i / (0.0006 * sr)) for i, v in enumerate(c)]
        mix_into(out, c, int(pos * sr), rng.uniform(0.2, 0.6))
    mix_into(out, bell(mtof(81), sr, 0.3, 0.8, 0.6), int(0.02 * sr), 0.45)
    mix_into(out, bell(mtof(88), sr, 0.25, 0.7, 0.5), int(0.09 * sr), 0.35)
    out = reverb(out, sr, rt60=0.7, wet=0.15, size=0.6)[:n]
    return fade(out, sr, 0.001, 0.25), sr, SFX_PEAK_DB


# ---- voices ----------------------------------------------------------------

def sfx_talk():
    sr = SR_SFX
    dur = 0.065

    def f0_fn(t):
        return 235.0 * (1.0 + 0.06 * (1.0 - t / dur))

    def formant_fn(t):
        o = smoothstep(t / 0.015)  # "b" -> "a"
        return [(350 + 450 * o, 110, 1.0), (900 + 350 * o, 140, 0.6), (2600, 250, 0.2)]

    def amp_fn(t):
        return smoothstep(t / 0.005) * (1.0 - smoothstep((t - (dur - 0.022)) / 0.022))

    x = voiced(sr, dur, f0_fn, formant_fn, amp_fn, tilt=0.6, every=4)
    x = onepole_lp(x, 5000, sr)
    return fade(x, sr, 0.001, 0.005), sr, -3.0


def sfx_kitten():
    sr = SR_SFX
    rng = random.Random(171)
    dur = 0.6

    def f0_fn(t):
        x = t / dur
        rise = smoothstep(x / 0.32)
        fall = smoothstep((x - 0.4) / 0.6)
        return (530.0 + 330.0 * rise - 220.0 * fall) * (1.0 + 0.012 * math.sin(TAU * 7.0 * t))

    def formant_fn(t):
        x = t / dur
        o = smoothstep(x / 0.12)            # "m" -> open "ee-a"
        w = smoothstep((x - 0.45) / 0.45)   # -> "ow"
        f1 = 350 + 650 * o - 400 * w
        f2 = 1700 + 300 * o - 900 * w
        return [(f1, 160, 1.0), (f2, 220, 0.6), (3500, 400, 0.15)]

    def amp_fn(t):
        return smoothstep(t / 0.04) * (1.0 - smoothstep((t - (dur - 0.16)) / 0.16)) \
            * (0.6 + 0.4 * smoothstep(t / 0.12))

    x = voiced(sr, dur, f0_fn, formant_fn, amp_fn, tilt=0.55)
    n = len(x)
    br = biquad(noise(n, rng), "bp", 2500, 1.0, sr)
    pk = peak_of(x) or 1.0
    for i in range(n):
        x[i] += pk * 0.04 * br[i] * amp_fn(i / sr)
    x = biquad(x, "lp", 5500, 0.7, sr)
    x = reverb(x, sr, rt60=0.3, wet=0.06, size=0.4)[:int(0.7 * sr)]
    return fade(x, sr, 0.002, 0.05), sr, SFX_PEAK_DB


# ---- jingles ---------------------------------------------------------------

def sfx_quest_new():
    sr = SR_SFX
    rng = random.Random(180)
    n = int(1.25 * sr)
    out = zeros(n)
    for t, m, v in ((0.0, 74, 0.5), (0.11, 79, 0.55), (0.22, 83, 0.6), (0.36, 81, 0.75)):
        mix_into(out, harp(m, sr, 1.0), int(t * sr), v)
        mix_into(out, bell(mtof(m + 12), sr, 0.3, 0.8, 0.4), int(t * sr), v * 0.3)
    mix_into(out, flute(81, 0.55, sr, release=0.25, breath=0.6), int(0.36 * sr), 0.3)
    for m in (62, 66, 69):
        mix_into(out, tpad(m, 0.55, sr, "pad", attack=0.15, release=0.4), int(0.3 * sr), 0.12)
    sparkle(out, sr, rng, 6, 0.36, 0.9, 0.06)
    out = reverb(out, sr, rt60=1.0, wet=0.2, size=0.7)[:n]
    return fade(out, sr, 0.001, 0.3), sr, SFX_PEAK_DB


def sfx_quest_done():
    sr = SR_SFX
    n = int(2.1 * sr)
    out = zeros(n)
    tune = [(0.00, 74, 0.12), (0.13, 79, 0.12), (0.26, 83, 0.12), (0.39, 86, 0.26),
            (0.68, 83, 0.12), (0.81, 86, 0.85)]
    for t, m, d in tune:
        mix_into(out, flute(m, d, sr, release=0.15, vib_cents=14.0, vib_rate=5.6,
                            breath=0.7), int(t * sr), 0.5)
    strums = [(0.0, [43], 0.6), (0.0, [55, 59, 62, 67], 0.22), (0.39, [50], 0.5),
              (0.39, [54, 57, 62], 0.2), (0.81, [43], 0.65), (0.81, [55, 59, 62, 67, 71], 0.24)]
    for t, notes, v in strums:
        for j, m in enumerate(notes):
            s = soft_bass(m, sr, 1.2) if m < 50 else guitar(m, sr, 1.1)
            mix_into(out, s, int((t + j * 0.012) * sr), v)
    for m, v in ((91, 0.3), (95, 0.2), (98, 0.16)):
        mix_into(out, bell(mtof(m), sr, tau=0.45, length=1.1, bright=0.6), int(0.81 * sr), v)
    for k, m in enumerate((79, 83, 86, 91)):
        mix_into(out, harp(m, sr, 1.0), int((0.84 + 0.05 * k) * sr), 0.16)
    out = reverb(out, sr, rt60=1.2, wet=0.2, size=0.8)[:n]
    return fade(out, sr, fin=0.002, fout=0.45), sr, SFX_PEAK_DB


def sfx_discover():
    sr = SR_SFX
    rng = random.Random(182)
    n = int(2.2 * sr)
    out = zeros(n)
    gl = [60, 62, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79, 81, 83, 84]
    for j, m in enumerate(gl):
        mix_into(out, harp(m, sr, 1.0, bright=1.1), int(j * 0.04 * sr), 0.16 + 0.12 * j / len(gl))
    t0 = 0.62
    for m in (48, 60, 67, 76, 83):
        mix_into(out, harp(m, sr, 1.8), int(t0 * sr), 0.2)
    for m in (84, 88, 91, 90):
        mix_into(out, bell(mtof(m), sr, 0.6, 1.5, 0.4), int(t0 * sr), 0.1)
    for m in (60, 64, 67, 71):
        mix_into(out, tpad(m, 0.9, sr, "ah", attack=0.35, release=0.8), int(0.5 * sr), 0.1)
    wh = swept_noise(sr, rng, 1.4, lambda t: 600.0 * 6.0 ** smoothstep(t / 1.0), 2.5,
                     lambda t: math.sin(math.pi * min(1.0, t / 1.4)) ** 2)
    mix_into(out, wh, 0, 0.07)
    sparkle(out, sr, rng, 14, 0.6, 1.6, 0.06)
    out = reverb(out, sr, rt60=1.5, wet=0.3, size=0.8)[:n]
    return fade(out, sr, 0.002, 0.5), sr, SFX_PEAK_DB


def sfx_beacon():
    sr = SR_SFX
    rng = random.Random(190)
    T = 4.3
    n = int(T * sr)
    out = zeros(n)
    t_ign = 0.85
    # 1. rising whoosh building into the ignition
    wh = swept_noise(sr, rng, 2.0, lambda t: 250.0 * 14.0 ** smoothstep(t / t_ign), 1.4,
                     lambda t: (t / t_ign) ** 2 if t < t_ign else math.exp(-(t - t_ign) / 0.3))
    mix_into(out, wh, 0, 0.45)
    # 2. ignition "fwoomp": opening-then-closing low noise + sub thump
    fw = swept_noise(sr, rng, 1.6, lambda t: 3000.0 * 0.15 ** smoothstep(t / 0.8), 0.7,
                     lambda t: smoothstep(t / 0.015) * math.exp(-t / 0.45))
    mix_into(out, fw, int(t_ign * sr), 0.8)
    mix_into(out, modal_hit(sr, 1.0, [(55, 1.0, 0.25), (82, 0.5, 0.15), (130, 0.2, 0.06)],
                            0.5, 0.03), int(t_ign * sr), 0.8)
    # 3. sustained airy roar with crackle
    roar = thud(sr, rng, int(3.2 * sr), 700, 10.0, 1.0)
    for i in range(len(roar)):
        t = i / sr
        roar[i] *= smoothstep(t / 0.2) * math.exp(-t / 1.0)
    mix_into(out, roar, int(t_ign * sr), 0.22)
    for _ in range(30):
        m = int(0.002 * sr)
        c = biquad(noise(m + 20, rng), "bp", rng.uniform(1500, 3500), 1.2, sr)
        c = [v * math.exp(-i / (0.0006 * sr)) for i, v in enumerate(c)]
        mix_into(out, c, int((t_ign + rng.random() ** 1.5 * 2.0) * sr), rng.uniform(0.1, 0.3))
    # 4. harp gliss on ignition
    for j, m in enumerate((62, 64, 66, 69, 71, 74, 76, 78, 81, 83, 86)):
        mix_into(out, harp(m, sr, 1.5), int((t_ign + j * 0.035) * sr), 0.16 + 0.01 * j)
    # 5. choir chord swell (D add9)
    for m in (50, 57, 62, 66, 69, 76):
        mix_into(out, tpad(m, 2.3, sr, "ah", attack=0.9, release=1.0), int(0.7 * sr), 0.14)
    for m in (62, 69, 74):
        mix_into(out, tpad(m, 2.3, sr, "str", attack=0.8, release=1.0), int(0.8 * sr), 0.06)
    # 6. bells and sparkles
    for m in (86, 90, 93):
        mix_into(out, bell(mtof(m), sr, 0.7, 2.5, 0.5), int((t_ign + 0.05) * sr), 0.14)
    sparkle(out, sr, rng, 22, t_ign, 3.2, 0.07)
    out = reverb(out, sr, rt60=2.0, wet=0.3, size=0.9)[:n]
    return fade(out, sr, 0.003, 0.7), sr, SFX_PEAK_DB


# ---- race ----------------------------------------------------------------

def sfx_ring():
    sr = SR_SFX
    rng = random.Random(200)
    n = int(0.75 * sr)
    out = zeros(n)
    mix_into(out, chime(mtof(84), sr, 0.32, 0.75), 0, 0.75)
    mix_into(out, chime(mtof(96), sr, 0.18, 0.5), 0, 0.15)
    wh = swept_noise(sr, rng, 0.3, lambda t: 800.0 * 3.5 ** smoothstep(t / 0.25), 1.5,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.3)) ** 2)
    mix_into(out, wh, 0, 0.25)
    out = reverb(out, sr, rt60=0.7, wet=0.15, size=0.6)[:n]
    return fade(out, sr, 0.001, 0.2), sr, SFX_PEAK_DB


def beep(sr, f, dur, release=0.04):
    n = int((dur + release * 3) * sr)
    out = [0.0] * n
    env = asr_env(n, sr, 0.005, dur, release)
    for i in range(n):
        p = TAU * f * i / sr
        out[i] = (math.sin(p) + 0.15 * math.sin(2 * p) + 0.05 * math.sin(3 * p)) * env[i]
    return out


def sfx_countdown():
    sr = SR_SFX
    x = beep(sr, 880.0, 0.13)
    return fade(x, sr, 0.001, 0.02), sr, SFX_PEAK_DB


def sfx_go():
    sr = SR_SFX
    rng = random.Random(202)
    n = int(0.6 * sr)
    out = zeros(n)
    mix_into(out, beep(sr, 1760.0, 0.35, 0.06), 0, 0.6)
    mix_into(out, beep(sr, 880.0, 0.35, 0.06), 0, 0.45)
    mix_into(out, chime(mtof(93 + 7), sr, 0.2, 0.5), 0, 0.12)
    sparkle(out, sr, rng, 5, 0.0, 0.3, 0.05)
    out = reverb(out, sr, rt60=0.6, wet=0.12, size=0.5)[:n]
    return fade(out, sr, 0.001, 0.12), sr, SFX_PEAK_DB


def sfx_fail():
    sr = SR_SFX
    rng = random.Random(203)
    dur = 1.0

    def f0_fn(t):
        vib = 1.0 + 0.012 * smoothstep((t - 0.25) / 0.2) * math.sin(TAU * 5.5 * t)
        return (420.0 - 120.0 * smoothstep(t / dur)) * vib

    def formant_fn(t):
        x = smoothstep(t / dur)
        return [(780 - 180 * x, 120, 1.0), (1150 - 250 * x, 150, 0.5), (2700, 250, 0.12)]

    def amp_fn(t):
        return smoothstep(t / 0.06) * (1.0 - smoothstep((t - (dur - 0.32)) / 0.32))

    v = voiced(sr, dur, f0_fn, formant_fn, amp_fn, tilt=0.85)
    n = int(1.3 * sr)
    out = zeros(n)
    mix_into(out, normalize(v), int(0.04 * sr), 0.5)
    for t, m in ((0.0, 76), (0.2, 72), (0.4, 69)):
        mix_into(out, harp(m, sr, 0.9, bright=0.7), int(t * sr), 0.28)
    br = biquad(noise(n, rng), "bp", 1500, 1.0, sr)
    for i in range(int(0.04 * sr), int(1.04 * sr)):
        out[i] += 0.01 * br[i] * amp_fn(i / sr - 0.04)
    out = onepole_lp(out, 5000, sr)
    out = reverb(out, sr, rt60=0.8, wet=0.15, size=0.6)[:n]
    return fade(out, sr, 0.003, 0.2), sr, SFX_PEAK_DB


# ---- UI ------------------------------------------------------------------

def sfx_ui_click():
    sr = SR_SFX
    n = int(0.08 * sr)
    ph = 0.0
    x = [0.0] * n
    for i in range(n):
        t = i / sr
        f = 330.0 + 700.0 * math.exp(-t / 0.01)
        ph += TAU * f / sr
        x[i] = (math.sin(ph) + 0.12 * math.sin(2 * ph)) * min(1.0, t / 0.0015) * math.exp(-t / 0.02)
    x = add(x, scale(additive(sr, n, 1800, [(1.0, 1.0, 0.005)]), 0.1))
    return fade(x, sr, fin=0.0008, fout=0.02), sr, SFX_PEAK_DB


def sfx_ui_hover():
    sr = SR_SFX
    x = modal_hit(sr, 0.035, [(2400, 1.0, 0.004), (1200, 0.4, 0.006), (4300, 0.15, 0.002)])
    x = onepole_lp(x, 6000, sr)
    return fade(x, sr, fin=0.0008, fout=0.01), sr, -10.0


def _ui_two(notes, rise, seed):
    sr = SR_SFX
    rng = random.Random(seed)
    n = int(0.35 * sr)
    out = zeros(n)
    for t, m in notes:
        mix_into(out, harp(m, sr, 0.3, bright=0.9), int(t * sr), 0.5)
        mix_into(out, chime(mtof(m + 12), sr, 0.06, 0.25), int(t * sr), 0.12)
    if rise:
        fc = lambda t: 800.0 * 3.0 ** smoothstep(t / 0.15)
    else:
        fc = lambda t: 2400.0 * 0.33 ** smoothstep(t / 0.15)
    wh = swept_noise(sr, rng, 0.18, fc, 1.5, lambda t: math.sin(math.pi * min(1.0, t / 0.18)) ** 2)
    mix_into(out, wh, 0, 0.12)
    return fade(out, sr, 0.001, 0.12), sr, SFX_PEAK_DB


def sfx_ui_open():
    return _ui_two(((0.0, 76), (0.06, 81)), True, 210)


def sfx_ui_close():
    return _ui_two(((0.0, 81), (0.06, 76)), False, 211)


def sfx_buy():
    sr = SR_SFX
    rng = random.Random(212)
    n = int(0.75 * sr)
    out = zeros(n)
    for t, f in ((0.0, 2600.0), (0.045, 3100.0), (0.075, 2850.0)):
        cl = additive(sr, int(0.12 * sr), f, [(1.0, 1.0, 0.03), (2.76, 0.5, 0.015),
                                             (5.4, 0.25, 0.008)], 0.0005)
        mix_into(out, cl, int(t * sr), 0.25 * rng.uniform(0.8, 1.0))
    for m, v in ((88, 0.5), (95, 0.4)):
        mix_into(out, bell(mtof(m), sr, 0.32, 0.6, 0.4), int(0.11 * sr), v)
        mix_into(out, harp(m - 12, sr, 0.5), int(0.11 * sr), v * 0.4)
    out = reverb(out, sr, rt60=0.6, wet=0.12, size=0.5)[:n]
    return fade(out, sr, 0.0006, 0.18), sr, SFX_PEAK_DB


def sfx_error():
    sr = SR_SFX
    rng = random.Random(214)
    n = int(0.45 * sr)
    out = zeros(n)
    for t, f, g in ((0.0, 230.0, 0.8), (0.13, 175.0, 1.0)):
        x = modal_hit(sr, 0.3, [(f, 1.0, 0.06), (f * 2.58, 0.3, 0.025), (f * 5.4, 0.06, 0.01)],
                      pitch_drop=0.15, drop_time=0.015)
        kn = 1.0 / (0.002 * sr)
        x = [v + 0.12 * rng.uniform(-1, 1) * math.exp(-kn * i) for i, v in enumerate(x)]
        mix_into(out, x, int(t * sr), g)
    out = biquad(out, "lp", 1600, 0.7, sr)
    return fade(out, sr, fin=0.0015, fout=0.06), sr, SFX_PEAK_DB


def sfx_updraft():
    sr = SR_SFX
    rng = random.Random(220)
    T = 1.6
    n = int(T * sr)
    env = lambda t: smoothstep(t / 0.3) * (1.0 - smoothstep((t - 0.7) / 0.85))
    fc = lambda t: 300.0 * 11.0 ** smoothstep(t / 1.3)
    out = swept_noise(sr, rng, T, fc, 0.9, env)
    wn = noise(n, rng)
    wh = normalize(svf_bp(wn, lambda i: fc(i / sr) * 1.3, 14.0, sr))
    rum = thud(sr, rng, n, 180, 10.0, 1.0)
    for i in range(n):
        t = i / sr
        out[i] += 0.12 * wh[i] * env(t) + 0.5 * rum[i] * smoothstep(t / 0.1) * math.exp(-t / 0.35)
    for k in range(5):  # little rising glints near the top
        mix_into(out, chime(mtof(84 + 3 * k), sr, 0.12, 0.3), int((0.5 + 0.12 * k) * sr), 0.04)
    out = onepole_lp(out, 7000, sr)
    out = reverb(out, sr, rt60=0.8, wet=0.12, size=0.7)[:n]
    return fade(out, sr, 0.005, 0.2), sr, SFX_PEAK_DB


# ---- discovery / characters -----------------------------------------------

def sfx_showcase():
    """'You found something new!': a bright harp + celesta arpeggio climbing
    over IV -> V and opening into a warm G major chord with a shimmer tail."""
    sr = SR_SFX
    rng = random.Random(230)
    n = int(2.2 * sr)
    out = zeros(n)
    arp = [(0.00, 72), (0.055, 76), (0.11, 79), (0.165, 83),     # Cmaj7
           (0.24, 74), (0.295, 78), (0.35, 81), (0.405, 86)]     # D
    for j, (t, m) in enumerate(arp):
        v = 0.26 + 0.025 * j
        mix_into(out, harp(m, sr, 1.0, bright=1.2), int(t * sr), v)
        mix_into(out, celesta(m + 12, sr, 0.8), int(t * sr), v * 0.45)
    t0 = 0.5
    for j, m in enumerate((43, 55, 62, 67, 71, 74, 79)):     # G major harp roll
        mix_into(out, harp(m, sr, 1.7), int((t0 + j * 0.016) * sr), 0.2)
    mix_into(out, soft_bass(43, sr, 1.6), int(t0 * sr), 0.35)
    for m in (55, 62, 67, 71, 74):
        mix_into(out, tpad(m, 1.0, sr, "str", attack=0.1, release=0.7), int(t0 * sr), 0.07)
    for m in (67, 71, 74):
        mix_into(out, tpad(m, 0.9, sr, "ah", attack=0.15, release=0.7), int(t0 * sr), 0.06)
    mix_into(out, celesta(91, sr, 1.6), int(t0 * sr), 0.4)
    mix_into(out, bell(mtof(91), sr, 0.6, 1.6, 0.5), int(t0 * sr), 0.16)
    for k, m in enumerate((95, 98, 103)):
        mix_into(out, musicbox(m, sr, 1.0), int((t0 + 0.22 + 0.09 * k) * sr), 0.13 - 0.02 * k)
    sh = swept_noise(sr, rng, 1.6, lambda t: 2200.0 * 1.5 ** smoothstep(t / 1.2), 3.0,
                     lambda t: smoothstep(t / 0.2) * math.exp(-t / 0.5))
    mix_into(out, sh, int(t0 * sr), 0.05)
    sparkle(out, sr, rng, 20, t0, 1.9, 0.06)
    out = reverb(out, sr, rt60=1.5, wet=0.28, size=0.8)[:n]
    return fade(out, sr, 0.002, 0.5), sr, -2.0


def sfx_meet():
    """Meeting someone new: a friendly F major pizzicato pattern and guitar
    strum under a soft, breathy flute 'hello there' phrase."""
    sr = SR_SFX
    rng = random.Random(231)
    n = int(1.6 * sr)
    out = zeros(n)
    tune = [(0.08, 72, 0.11), (0.21, 77, 0.11), (0.34, 81, 0.2), (0.58, 79, 0.1), (0.71, 81, 0.5)]
    for t, m, d in tune:
        mix_into(out, flute(m, d, sr, release=0.18, vib_cents=12.0, vib_rate=5.4, breath=0.8),
                 int(t * sr), 0.36)
    plucks = [(0.0, 41, 0.42), (0.0, 65, 0.2), (0.13, 69, 0.2), (0.26, 72, 0.2),
              (0.39, 69, 0.18), (0.58, 48, 0.36), (0.58, 67, 0.18), (0.71, 41, 0.45)]
    for t, m, v in plucks:
        mix_into(out, soft_bass(m, sr, 1.0) if m < 50 else pizz(m, sr), int(t * sr), v)
    for j, m in enumerate((53, 57, 60, 65, 69)):
        mix_into(out, guitar(m, sr, 0.9), int((0.71 + j * 0.014) * sr), 0.13)
    mix_into(out, bell(mtof(93), sr, 0.4, 0.8, 0.4), int(0.71 * sr), 0.07)
    sparkle(out, sr, rng, 4, 0.72, 1.1, 0.03)
    out = reverb(out, sr, rt60=1.0, wet=0.2, size=0.7)[:n]
    return fade(out, sr, 0.002, 0.35), sr, -3.0


def sfx_hint():
    """Tiny 'something is near' twinkle: three soft celesta notes and a breath
    of shimmer (played rarely, so short and quiet)."""
    sr = SR_SFX
    rng = random.Random(232)
    n = int(0.5 * sr)
    out = zeros(n)
    for t, m, v in ((0.0, 88, 0.32), (0.045, 95, 0.26), (0.09, 92, 0.22), (0.16, 100, 0.1)):
        mix_into(out, celesta(m, sr, 0.45), int(t * sr), v)
    mix_into(out, chime(mtof(100), sr, 0.12, 0.4), int(0.09 * sr), 0.05)
    sh = swept_noise(sr, rng, 0.4, lambda t: 2200.0 * 1.5 ** smoothstep(t / 0.3), 2.5,
                     lambda t: math.sin(math.pi * min(1.0, t / 0.4)) ** 2)
    mix_into(out, sh, 0, 0.04)
    sparkle(out, sr, rng, 6, 0.02, 0.3, 0.05)
    out = reverb(out, sr, rt60=0.8, wet=0.28, size=0.6)[:n]
    return fade(out, sr, 0.001, 0.15), sr, -6.0


def meow(seed, dur, f_start, f_peak, f_end, t_peak, vow, trill=0.0, trill_t=0.0, tilt=0.55):
    """Kitten meow: formant-shaped voiced source with a pitch glide.
    vow = [(time_frac, F1, F2)] vowel keyframes; trill > 0 adds a purring
    'rr' amplitude flutter until trill_t."""
    sr = SR_SFX
    rng = random.Random(seed)
    jr = rng.uniform(6.0, 8.0)
    jp = rng.uniform(0, TAU)

    def f0_fn(t):
        x = t / dur
        if x < t_peak:
            f = f_start + (f_peak - f_start) * smoothstep(x / t_peak)
        else:
            f = f_peak + (f_end - f_peak) * smoothstep((x - t_peak) / (1.0 - t_peak))
        return f * (1.0 + 0.012 * math.sin(TAU * jr * t + jp))

    def formant_fn(t):
        x = t / dur
        f1, f2 = vow[-1][1], vow[-1][2]
        for (x0, a1, a2), (x1, b1, b2) in zip(vow, vow[1:]):
            if x <= x1:
                u = smoothstep((x - x0) / (x1 - x0))
                f1, f2 = a1 + (b1 - a1) * u, a2 + (b2 - a2) * u
                break
        return [(f1, 160, 1.0), (f2, 240, 0.6), (3600, 400, 0.15)]

    def amp_fn(t):
        a = smoothstep(t / 0.035) * (1.0 - smoothstep((t - (dur - 0.14)) / 0.14)) \
            * (0.6 + 0.4 * smoothstep(t / 0.1))
        if trill:
            a *= 1.0 - 0.55 * (1.0 - smoothstep((t - trill_t) / 0.04)) \
                * (0.5 + 0.5 * math.cos(TAU * trill * t))
        return a

    x = voiced(sr, dur, f0_fn, formant_fn, amp_fn, tilt=tilt)
    n = len(x)
    br = biquad(noise(n, rng), "bp", 2500, 1.0, sr)
    pk = peak_of(x) or 1.0
    for i in range(n):
        x[i] += pk * 0.04 * br[i] * amp_fn(i / sr)
    x = biquad(x, "lp", 5500, 0.7, sr)
    x = reverb(x, sr, rt60=0.3, wet=0.06, size=0.4)[:int((dur + 0.08) * sr)]
    return fade(x, sr, 0.002, 0.05), sr, -3.0


def sfx_meow_1():  # short, bright "mew"
    return meow(241, 0.42, 760.0, 1000.0, 720.0, 0.35,
                [(0.0, 400, 2000), (0.15, 700, 2300), (1.0, 750, 1900)])


def sfx_meow_2():  # classic "mee-ow", falling at the end
    return meow(242, 0.62, 560.0, 860.0, 470.0, 0.33,
                [(0.0, 350, 1700), (0.12, 1000, 2000), (0.5, 950, 1500), (1.0, 600, 950)])


def sfx_meow_3():  # trilled "mrrp-ew?", rising like a question
    return meow(243, 0.55, 520.0, 560.0, 880.0, 0.3,
                [(0.0, 380, 1500), (0.3, 600, 1600), (0.6, 900, 2100), (1.0, 850, 2200)],
                trill=26.0, trill_t=0.13)


def sfx_crackle_loop():
    """Seamless 4 s loop of a small magical fire: warm breathing hiss, clustered
    soft crackles, a few rounder sap pops and faint glints (all wrapped)."""
    sr = SR_SFX
    rng = random.Random(250)
    T = 4.0
    n = int(T * sr)
    pre = int(0.2 * sr)
    hiss = normalize(circ(lambda s: biquad(biquad(s, "hp", 350.0, 0.7, sr), "lp", 2200.0, 0.6, sr),
                          noise(n, rng), pre))
    roar = normalize(circ(lambda s: onepole_lp(onepole_lp(s, 180.0, sr), 180.0, sr),
                          noise(n, rng), pre))
    flick = [0.5 + 0.5 * v for v in periodic_curve(n, rng, (2, 3, 5, 7, 11, 13, 17, 23))]
    slow = [0.5 + 0.5 * v for v in periodic_curve(n, rng, (1, 2, 3))]
    out = [0.2 * h * (0.45 + 0.55 * f) * (0.7 + 0.3 * s) + 0.3 * r * (0.6 + 0.4 * s)
           for h, r, f, s in zip(hiss, roar, flick, slow)]

    def crackle():
        gl = int(rng.uniform(0.001, 0.003) * sr) + 8
        c = biquad(noise(gl, rng), "bp", rng.uniform(1500.0, 5000.0), 0.9, sr)
        tau = rng.uniform(0.0003, 0.0008) * sr
        return [v * math.exp(-i / tau) for i, v in enumerate(c)]

    for _ in range(26):     # little clusters
        c0 = rng.uniform(0.0, T)
        for _ in range(rng.randint(2, 7)):
            g = rng.uniform(0.12, 0.4) * (0.3 + 0.7 * rng.random())
            mix_into(out, crackle(), int((c0 + rng.uniform(0.0, 0.08)) * sr), g, wrap=True)
    for _ in range(40):     # lone ticks
        g = rng.uniform(0.08, 0.3)
        mix_into(out, crackle(), int(rng.uniform(0.0, T) * sr), g, wrap=True)
    for _ in range(8):      # rounder sap pops
        dk = rng.uniform(0.0015, 0.0035)
        p = onepole_lp(noise(int(0.014 * sr), rng), rng.uniform(900.0, 1600.0), sr)
        p = normalize([v * ad_env(i / sr, 0.0003, dk) for i, v in enumerate(p)])
        mix_into(out, p, int(rng.uniform(0.0, T) * sr), rng.uniform(0.22, 0.38), wrap=True)
    for _ in range(7):      # faint magical glints
        f = rng.uniform(3000.0, 6000.0)
        s = additive(sr, int(0.12 * sr), f, [(1.0, 1.0, 0.03), (2.0, 0.2, 0.015)], attack=0.002)
        mix_into(out, s, int(rng.uniform(0.0, T) * sr), 0.04 * rng.uniform(0.6, 1.0), wrap=True)
    out = circ(lambda s: onepole_lp(s, 6500.0, sr), out, pre)
    out = reverb(out, sr, rt60=0.5, wet=0.1, circular=True, size=0.5)
    out = circ(dc_block, out, int(1.0 * sr))
    return out, sr, -8.0


def sfx_page():
    """Soft paper page turn: a lifting air swish, papery crinkle grains and a
    gentle flap as the page settles."""
    sr = SR_SFX
    rng = random.Random(260)
    n = int(0.4 * sr)
    out = zeros(n)
    sl = swept_noise(sr, rng, 0.34, lambda t: 1300.0 + 2000.0 * math.sin(math.pi * min(1.0, t / 0.3)),
                     0.8, lambda t: smoothstep(t / 0.07) * (1.0 - smoothstep((t - 0.1) / 0.22)))
    mix_into(out, sl, 0, 0.45)
    grains(out, sr, rng, 26, 0.01, 0.27, 2500.0, 6000.0, 0.002, 0.006, 0.18, q=1.0, decay=0.5)
    mix_into(out, cloth_flap(sr, rng, 650.0, 0.025), int(0.25 * sr), 0.4)
    mix_into(out, foot_pat(sr, rng, 300.0, 0.015), int(0.26 * sr), 0.15)
    out = onepole_lp(out, 7000.0, sr)
    out = reverb(out, sr, rt60=0.35, wet=0.08, size=0.4)[:n]
    return fade(out, sr, 0.004, 0.08), sr, -6.0


def sfx_dust():
    """Very soft 'poof' of dust (skids / landings): closing band of noise
    over a low air puff, a few specks of grit."""
    sr = SR_SFX
    rng = random.Random(270)
    n = int(0.3 * sr)
    out = zeros(n)
    puff = swept_noise(sr, rng, 0.3, lambda t: 1600.0 * 0.35 ** smoothstep(t / 0.2), 0.7,
                       lambda t: ad_env(t, 0.018, 0.075))
    mix_into(out, puff, 0, 0.7)
    mix_into(out, foot_pat(sr, rng, 260.0, 0.05, attack=0.012), 0, 0.35)
    grains(out, sr, rng, 8, 0.01, 0.18, 1500.0, 3500.0, 0.003, 0.007, 0.08, q=0.9)
    out = onepole_lp(out, 4000.0, sr)
    return fade(out, sr, 0.004, 0.08), sr, -12.0


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def write_wav(path, x, sr, peak_db):
    if peak_db == RAW:
        g = 1.0
    else:
        peak = peak_of(x) or 1.0
        g = 10.0 ** (peak_db / 20.0) / peak
    data = array.array("h", [int(round(clamp(v * g, -1.0, 1.0) * 32767.0)) for v in x])
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def analyze(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        n = w.getnframes()
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        data = array.array("h")
        data.frombytes(w.readframes(n))
    if sys.byteorder == "big":
        data.byteswap()
    peak = max(abs(v) for v in data) if n else 0
    peak_db = 20 * math.log10(peak / 32767.0) if peak else -999.0
    rms = math.sqrt(sum(v * v for v in data) / n) if n else 0.0
    rms_db = 20 * math.log10(rms / 32767.0) if rms else -999.0
    dc = sum(data) / n / 32767.0 if n else 0.0
    clips = sum(1 for v in data if v >= 32767 or v <= -32767)
    # loop continuity: jump across the seam vs. the typical sample-to-sample step
    step = sum(abs(data[i + 1] - data[i]) for i in range(0, n - 1, 7)) / max(1, (n - 1) // 7 + 1)
    seam = abs(data[0] - data[-1]) / (step or 1.0)
    w = min(n // 2, int(0.25 * sr))

    def seg_rms(s):
        return math.sqrt(sum(v * v for v in s) / len(s)) if s else 0.0
    a = seg_rms(data[n - w:])
    b = seg_rms(data[:w])
    edge_db = 20 * math.log10(b / a) if a and b else 0.0
    return dict(sr=sr, dur=n / sr, peak=peak_db, rms=rms_db, dc=dc, clips=clips,
                seam=seam, edge_db=edge_db)


JOBS = [
    ("music_title.wav", make_title),
    ("music_day.wav", make_day),
    ("music_night.wav", make_night),
    ("music_village.wav", make_village),
    ("music_ending.wav", make_ending),
    ("amb_wind.wav", amb_wind),
    ("amb_sea.wav", amb_sea),
    ("amb_night.wav", amb_night),
    ("amb_birds.wav", amb_birds),
    *[("sfx_step_%s_%d.wav" % (s, k + 1), (lambda s=s, k=k: step_variant(s, k)))
      for s in STEP_SURFACES for k in range(STEP_VARIANTS)],
    ("sfx_jump.wav", sfx_jump),
    ("sfx_land.wav", sfx_land),
    ("sfx_land_heavy.wav", sfx_land_heavy),
    ("sfx_glide_open.wav", sfx_glide_open),
    ("sfx_glide_close.wav", sfx_glide_close),
    ("sfx_climb.wav", sfx_climb),
    ("sfx_mantle.wav", sfx_mantle),
    ("sfx_splash.wav", sfx_splash),
    ("sfx_swim.wav", sfx_swim),
    ("sfx_stamina_low.wav", sfx_stamina_low),
    ("sfx_stamina_up.wav", sfx_stamina_up),
    ("sfx_shell.wav", sfx_shell),
    ("sfx_feather.wav", sfx_feather),
    ("sfx_item.wav", sfx_item),
    ("sfx_chest.wav", sfx_chest),
    ("sfx_talk.wav", sfx_talk),
    ("sfx_quest_new.wav", sfx_quest_new),
    ("sfx_quest_done.wav", sfx_quest_done),
    ("sfx_discover.wav", sfx_discover),
    ("sfx_beacon.wav", sfx_beacon),
    ("sfx_ring.wav", sfx_ring),
    ("sfx_countdown.wav", sfx_countdown),
    ("sfx_go.wav", sfx_go),
    ("sfx_fail.wav", sfx_fail),
    ("sfx_spark.wav", sfx_spark),
    ("sfx_kitten.wav", sfx_kitten),
    ("sfx_ui_click.wav", sfx_ui_click),
    ("sfx_ui_hover.wav", sfx_ui_hover),
    ("sfx_ui_open.wav", sfx_ui_open),
    ("sfx_ui_close.wav", sfx_ui_close),
    ("sfx_buy.wav", sfx_buy),
    ("sfx_error.wav", sfx_error),
    ("sfx_updraft.wav", sfx_updraft),
    ("sfx_showcase.wav", sfx_showcase),
    ("sfx_meet.wav", sfx_meet),
    ("sfx_hint.wav", sfx_hint),
    ("sfx_meow_1.wav", sfx_meow_1),
    ("sfx_meow_2.wav", sfx_meow_2),
    ("sfx_meow_3.wav", sfx_meow_3),
    ("sfx_crackle_loop.wav", sfx_crackle_loop),
    ("sfx_page.wav", sfx_page),
    ("sfx_dust.wav", sfx_dust),
]


def is_loop(name):
    base = name[:-4] if name.endswith(".wav") else name
    return base.startswith(("music_", "amb_")) or base.endswith("_loop")


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    only = set(a[:-4] if a.endswith(".wav") else a for a in argv[1:])
    known = set(name[:-4] for name, _ in JOBS)
    for a in list(only - known):  # a group prefix (e.g. sfx_step_grass, sfx_meow)
        group = set(k for k in known if k.startswith(a + "_"))
        if group:
            only.discard(a)
            only |= group
    unknown = only - known
    if unknown:
        print("unknown names: %s" % ", ".join(sorted(unknown)))
        return 1
    for name, fn in JOBS:
        if only and name[:-4] not in only:
            continue
        t0 = time.time()
        res = fn()
        if len(res) == 2:
            x, sr = res
            peak_db = RAW
        else:
            x, sr, peak_db = res
        if not is_loop(name):
            x = fade(dc_block(x, 0.999), sr, fin=0.0003, fout=0.004)
        write_wav(os.path.join(OUT_DIR, name), x, sr, peak_db)
        print("  rendered %-22s in %6.1f s" % (name, time.time() - t0), flush=True)

    print()
    print("%-22s %6s %7s %7s %7s %8s %5s %6s %7s" % (
        "file", "rate", "dur s", "peak", "RMS", "DC", "clip", "seam", "edge dB"))
    total = 0
    for name, _ in JOBS:
        if only and name[:-4] not in only:
            continue
        p = os.path.join(OUT_DIR, name)
        if not os.path.exists(p):
            print("%-22s MISSING" % name)
            continue
        a = analyze(p)
        total += os.path.getsize(p)
        loop = is_loop(name)
        print("%-22s %6d %7.2f %7.2f %7.2f %8.5f %5d %6s %7s" % (
            name, a["sr"], a["dur"], a["peak"], a["rms"], a["dc"], a["clips"],
            "%.2f" % a["seam"] if loop else "-", "%+.2f" % a["edge_db"] if loop else "-"))
    print("total size: %.2f MB" % (total / (1024.0 * 1024.0)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
