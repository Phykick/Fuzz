#!/usr/bin/env python3
"""Synthesise Underhaven's sound effects and ambience into ONE audio atlas.

    python3 tools/make_sounds.py

Writes audio/underhaven_sounds.ogg (upload this once; see README) and
src/ReplicatedStorage/Shared/SoundAtlas.lua (where each sound sits in the file). Every sound is
generated from scratch here (oscillators, filtered noise, plucked strings, bell partials), so
the game owns all of its audio. Deterministic: the same script always produces the same file.

Needs numpy and ffmpeg (with libvorbis).
"""
import os
import subprocess
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
SR = 44100
GAP = 0.2  # silence between sounds in the atlas (keeps regions from bleeding)
rng = np.random.default_rng(1977)


# --- building blocks -------------------------------------------------------------------------
def n_(dur):
    return int(round(dur * SR))


def tt(dur):
    return np.arange(n_(dur)) / SR


def silence(dur):
    return np.zeros(n_(dur))


def osc(freq, dur, shape='sine', phase=0.0):
    """freq: number or per-sample array. shape: sine | saw | square | tri (band-limited-ish)."""
    n = n_(dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)) if np.ndim(freq) else np.full(n, float(freq))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if shape == 'sine':
        return np.sin(ph)
    out = np.zeros(n)
    fmax = float(np.max(f))
    k_max = max(1, int(16000 / max(fmax, 1)))
    for k in range(1, min(k_max, 40) + 1):
        if shape == 'saw':
            out += np.sin(k * ph) / k
        elif shape == 'square' and k % 2 == 1:
            out += np.sin(k * ph) / k
        elif shape == 'tri' and k % 2 == 1:
            out += ((-1) ** ((k - 1) // 2)) * np.sin(k * ph) / (k * k)
    return out


def sweep(f0, f1, dur, curve='exp'):
    x = np.linspace(0, 1, n_(dur))
    return f0 * (f1 / f0) ** x if curve == 'exp' else f0 + (f1 - f0) * x


def noise(dur):
    return rng.standard_normal(n_(dur))


def brown(dur):
    x = np.cumsum(rng.standard_normal(n_(dur)))
    x -= np.linspace(x[0], x[-1], len(x))  # remove drift
    return x / (np.max(np.abs(x)) + 1e-9)


def decay(dur, tau, attack=0.002):
    t = tt(dur)
    e = np.exp(-t / tau)
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def adsr(dur, a, d, s, r):
    n = n_(dur)
    e = np.full(n, s)
    na, nd, nr = n_(a), n_(d), n_(r)
    e[:na] = np.linspace(0, 1, na, endpoint=False)
    e[na:na + nd] = np.linspace(1, s, nd, endpoint=False)[:max(0, min(nd, n - na))]
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def spectral(x, response):
    """Zero-phase filter: multiply the spectrum by response(freqs)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * response(f), len(x))


def lp(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def hp(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bp(x, lo, hi, order=2):
    return lp(hp(x, lo, order), hi, order)


def sweep_filter(x, fc0, fc1, kind='lp', frame=1024):
    """Time-varying filter by overlap-add of windowed frames (cutoff glides fc0 -> fc1)."""
    hop = frame // 2
    win = np.hanning(frame)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    out = np.zeros_like(pad)
    norm = np.zeros_like(pad)
    starts = range(0, len(pad) - frame, hop)
    total = max(1, len(starts) - 1)
    f = np.fft.rfftfreq(frame, 1 / SR)
    for k, s in enumerate(starts):
        fc = fc0 * (fc1 / fc0) ** (k / total)
        resp = 1 / np.sqrt(1 + (f / fc) ** 4) if kind == 'lp' else 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** 4)
        seg = np.fft.irfft(np.fft.rfft(pad[s:s + frame] * win) * resp, frame)
        out[s:s + frame] += seg * win
        norm[s:s + frame] += win * win
    out = out / np.maximum(norm, 1e-6)
    return out[frame:frame + len(x)]


def bell(freq, dur, partials=((1, 1, 1.0), (2.0, 0.5, 0.6), (3.01, 0.25, 0.4), (4.2, 0.12, 0.25)), tau=0.5):
    out = np.zeros(n_(dur))
    for ratio, amp, tscale in partials:
        out += amp * osc(freq * ratio, dur) * decay(dur, tau * tscale)
    return out


def pluck(freq, dur, damp=0.996, bright=0.5):
    """Karplus-Strong plucked string."""
    n = n_(dur)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    buf = bright * buf + (1 - bright) * np.convolve(buf, [0.5, 0.5], 'same')
    out = np.zeros(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = damp * 0.5 * (buf[j] + buf[(j + 1) % period])
    return out


def place(dst, src, at, gain=1.0):
    i = n_(at)
    j = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:j] += gain * src[:j - i]
    return dst


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def edges(x, fade_in=0.002, fade_out=0.012):
    x = x.copy()
    a, b = n_(fade_in), n_(fade_out)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def make_loop(fn, length, xfade=0.25, power=True):
    """Render length + xfade seconds and fold the tail over the head: a seamless loop.
    power=True: equal-power fade (noise-like content); False: linear (tonal content that
    already repeats, where an equal-power fade would bump the level)."""
    x = fn(length + xfade)
    L, X = n_(length), n_(xfade)
    y = x[:L].copy()
    if power:
        w = np.linspace(0, np.pi / 2, X)
        a, b = np.sin(w), np.cos(w)
    else:
        a = np.linspace(0, 1, X)
        b = 1 - a
    y[:X] = x[:X] * a + x[L:L + X] * b
    return y


def note(name):
    names = {'C': -9, 'C#': -8, 'D': -7, 'Eb': -6, 'E': -5, 'F': -4, 'F#': -3, 'G': -2, 'Ab': -1, 'A': 0, 'Bb': 1, 'B': 2}
    octave = int(name[-1])
    return 440.0 * 2 ** ((names[name[:-1]] + 12 * (octave - 4)) / 12)


# --- the sounds ------------------------------------------------------------------------------
def s_click():
    d = 0.05
    tone = osc(sweep(1900, 1200, d), d) * decay(d, 0.007)
    tick = hp(noise(d), 3000) * decay(d, 0.0025) * 0.3
    return tone + tick


def s_open():
    d = 0.18
    tone = osc(sweep(480, 1100, d), d) * adsr(d, 0.012, 0.05, 0.5, 0.1)
    air = bp(noise(d), 1500, 5000) * np.sin(np.linspace(0, np.pi, n_(d))) * 0.25
    return tone + air


def s_close():
    d = 0.16
    tone = osc(sweep(900, 420, d), d) * adsr(d, 0.008, 0.05, 0.45, 0.09)
    air = bp(noise(d), 1200, 4000) * np.sin(np.linspace(0, np.pi, n_(d))) * 0.2
    return tone + air


def s_error():
    out = silence(0.3)
    for at in (0.0, 0.14):
        b = lp(osc(196, 0.09, 'square'), 1400) * adsr(0.09, 0.005, 0.02, 0.8, 0.02)
        place(out, b, at)
    return out


def s_collect():
    d = 0.45
    out = osc(sweep(300, 950, 0.05), 0.05) * decay(0.05, 0.03) * 0.8
    out = np.concatenate([out, silence(d - 0.05)])
    place(out, pluck(note('C6'), 0.38, 0.993, 0.7) * 0.8, 0.02)
    place(out, pluck(note('G6'), 0.33, 0.992, 0.7) * 0.55, 0.08)
    return out


def s_bolts():
    out = silence(0.5)
    coin = lambda k: sum(a * osc(f * k, 0.4) * decay(0.4, tau) for f, a, tau in
                         ((2093, 1.0, 0.22), (3170, 0.6, 0.16), (4270, 0.45, 0.11), (5274, 0.3, 0.07)))
    place(out, coin(1.0), 0.0)
    place(out, coin(1.12), 0.075, 0.8)
    return out


def s_build():
    out = silence(1.05)
    for i, at in enumerate((0.0, 0.2, 0.4)):
        g = 0.85 if i < 2 else 1.0
        thud = osc(sweep(150, 70, 0.12), 0.12) * decay(0.12, 0.05)
        click = hp(noise(0.03), 2000) * decay(0.03, 0.006) * 0.5
        ring = sum(a * osc(f, 0.3) * decay(0.3, 0.1) for f, a in ((1210, 0.22), (1873, 0.15), (2650, 0.1)))
        place(out, thud + np.pad(click, (0, len(thud) - len(click))), at, g)
        place(out, ring, at, g)
    for k in range(9):
        c = bp(noise(0.02), 2000, 6500) * decay(0.02, 0.003) * 0.35
        place(out, c, 0.64 + k * 0.035)
    return out


def s_upgrade():
    out = silence(1.0)
    for i, nm in enumerate(('C5', 'E5', 'G5', 'C6')):
        place(out, bell(note(nm), 0.7, tau=0.35), i * 0.09, 0.7)
    place(out, bp(noise(0.6), 6000, 11000) * decay(0.6, 0.18) * 0.12, 0.27)
    return out


def s_demolish():
    d = 1.1
    out = lp(brown(d), 260) * decay(d, 0.35, 0.02) * 1.2
    out += osc(sweep(70, 40, d), d) * decay(d, 0.15) * 0.9
    for _ in range(45):
        at = rng.uniform(0.02, 0.8)
        seg = bp(noise(0.05), rng.uniform(300, 900), rng.uniform(1500, 3000)) * decay(0.05, rng.uniform(0.006, 0.02))
        place(out, seg, at, rng.uniform(0.15, 0.5) * (1 - at))
    return out


def s_rush():
    d = 0.65
    f = np.concatenate([sweep(55, 150, 0.45), np.full(n_(0.2), 150.0)])
    eng = sweep_filter(osc(f, d, 'saw'), 350, 2600)
    env = adsr(d, 0.08, 0.2, 0.8, 0.25)
    whoosh = sweep_filter(noise(d), 600, 3500) * np.sin(np.linspace(0, np.pi, n_(d))) * 0.3
    return (eng + whoosh) * env


def s_levelup():
    out = silence(1.0)
    for i, nm in enumerate(('G5', 'B5', 'D6', 'G6')):
        place(out, bell(note(nm), 0.6, tau=0.3), i * 0.07, 0.65)
    for _ in range(12):
        ping = osc(rng.uniform(3000, 6500), 0.12) * decay(0.12, 0.03)
        place(out, ping, rng.uniform(0.25, 0.65), 0.15)
    return out


def s_heal():
    d = 0.45
    e = adsr(d, 0.04, 0.1, 0.6, 0.25)
    return (osc(sweep(560, 660, d), d) + 0.6 * osc(sweep(840, 990, d), d)) * e * 0.7 + bp(noise(d), 4000, 9000) * e * 0.08


def s_revive():
    out = silence(1.2)
    for i, nm in enumerate(('C4', 'G4', 'C5', 'E5')):
        place(out, bell(note(nm), 1.0, tau=0.6), i * 0.06, 0.6)
    place(out, bp(noise(0.8), 5000, 10000) * decay(0.8, 0.25) * 0.1, 0.2)
    return out


def s_doorbell():
    out = silence(1.15)
    partials = ((1, 1, 1.0), (2.0, 0.35, 0.5), (2.76, 0.2, 0.35), (5.4, 0.08, 0.2))
    place(out, bell(note('E5'), 0.8, partials, tau=0.45), 0.0, 0.8)
    place(out, bell(note('C5'), 0.8, partials, tau=0.55), 0.33, 0.8)
    return out


def s_welcome():
    out = silence(0.75)
    for i, nm in enumerate(('G4', 'B4', 'D5')):
        place(out, pluck(note(nm), 0.6, 0.995, 0.5), i * 0.06, 0.6)
    return out


def s_birth():
    out = silence(1.2)
    for i, nm in enumerate(('C6', 'E6', 'G6', 'E6', 'C7')):
        d = 0.45
        tone = (osc(note(nm), d) + 0.3 * osc(note(nm) * 4, d) * decay(d, 0.05)) * decay(d, 0.22)
        place(out, tone, i * 0.14, 0.55)
    return out


def s_romance():
    out = silence(0.7)
    for i, nm in enumerate(('A5', 'C#6')):
        d = 0.5
        vib = note(nm) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * tt(d)))
        place(out, osc(vib, d) * adsr(d, 0.03, 0.1, 0.6, 0.3), i * 0.16, 0.6)
    return out


def s_death():
    d = 1.7
    pad = sum(osc(note(nm) * dt, d, 'saw') for nm in ('A2', 'C3', 'E3') for dt in (1.0, 1.004))
    pad = lp(pad, 650) * adsr(d, 0.18, 0.4, 0.6, 0.9)
    toll = bell(note('A3'), d, tau=0.7) * 0.5
    return pad + toll


def alarm_loop(d):
    out = np.zeros(n_(d))
    seg = 0.4
    for k in range(int(round(d / seg))):
        f = 660 if k % 2 == 0 else 520
        tone = lp(osc(f, seg, 'square'), 2600) * adsr(seg, 0.01, 0.0, 1.0, 0.012)
        place(out, tone, k * seg)
    return out


def s_fire_start():
    d = 0.75
    whoosh = sweep_filter(noise(d), 280, 3200) * adsr(d, 0.15, 0.2, 0.55, 0.35)
    thump = osc(sweep(90, 55, 0.25), 0.25) * decay(0.25, 0.08)
    return whoosh + np.pad(thump, (0, n_(d) - len(thump))) * 0.8


def fire_loop(d):
    roar = lp(brown(d), 480) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.7 * tt(d)))
    out = roar * 0.9
    out += bp(noise(d), 2000, 6000) * 0.04
    count = int(26 * d)
    for _ in range(count):
        at = rng.uniform(0, d - 0.03)
        c = hp(noise(0.03), rng.uniform(1200, 3000)) * decay(0.03, rng.uniform(0.002, 0.008))
        place(out, c, at, rng.uniform(0.1, 0.55))
    return out


def s_extinguish():
    d = 0.9
    hiss = hp(noise(d), 2200) * adsr(d, 0.02, 0.15, 0.5, 0.6)
    steam = bp(noise(d), 4500, 9000) * decay(d, 0.3, 0.05) * 0.4
    return hiss + steam


def s_breakdown():
    out = silence(1.1)
    clank = sum(a * osc(f, 0.6) * decay(0.6, tau) for f, a, tau in
                ((310, 1.0, 0.25), (742, 0.6, 0.18), (1131, 0.45, 0.12), (1687, 0.3, 0.08)))
    knock = osc(sweep(120, 60, 0.15), 0.15) * decay(0.15, 0.05)
    clank += np.pad(knock, (0, len(clank) - len(knock)))
    place(out, clank, 0.0)
    for k in range(6):
        burst = bp(noise(0.05), 200, 1100) * decay(0.05, 0.015)
        place(out, burst, 0.25 + k * (0.09 - k * 0.008), 0.6 * (1 - k / 7))
    for k in range(3):
        zap = (osc(sweep(3000, 8000, 0.03), 0.03) * 0.5 + hp(noise(0.03), 4000)) * decay(0.03, 0.008)
        place(out, zap, 0.62 + k * 0.11, 0.45)
    return out


def s_repair_done():
    out = silence(0.85)
    for k in range(6):
        c = bp(noise(0.02), 2000, 6500) * decay(0.02, 0.003) * 0.4
        place(out, c, k * 0.04)
    place(out, bell(note('G6'), 0.6, tau=0.3), 0.28, 0.6)
    return out


def s_creature():
    out = silence(0.5)
    for k in range(3):
        d = 0.07
        f = sweep(2300 + 300 * k, 3400 + 200 * k, d / 2)
        f = np.concatenate([f, f[::-1]])
        sq = osc(f, len(f) / SR) * adsr(len(f) / SR, 0.005, 0.02, 0.6, 0.02)
        place(out, sq, k * 0.12, 0.7)
    for _ in range(9):
        c = bp(noise(0.012), 3000, 7000) * decay(0.012, 0.002)
        place(out, c, rng.uniform(0.0, 0.42), 0.25)
    return out


def s_gunshot():
    d = 0.45
    crack = hp(noise(d), 900) * decay(d, 0.018, 0.0005)
    body = lp(noise(d), 1600) * decay(d, 0.07, 0.001) * 0.8
    thump = osc(sweep(80, 45, d), d) * decay(d, 0.07) * 0.9
    tail = lp(noise(d), 700) * decay(d, 0.2, 0.01) * 0.18
    return crack + body + thump + tail


def s_punch():
    d = 0.2
    return osc(sweep(120, 60, d), d) * decay(d, 0.05) + lp(noise(d), 1100) * decay(d, 0.02) * 0.5


def s_door_hit():
    d = 0.8
    thump = osc(sweep(85, 60, d), d) * decay(d, 0.12)
    metal = sum(a * osc(f, d) * decay(d, tau) for f, a, tau in
                ((182, 0.8, 0.45), (421, 0.5, 0.3), (693, 0.35, 0.22), (1130, 0.2, 0.14)))
    click = hp(noise(d), 1500) * decay(d, 0.006) * 0.4
    return thump + metal * 0.7 + click


def s_door_breach():
    d = 1.6
    boom = osc(sweep(55, 32, d), d) * decay(d, 0.5) + lp(noise(d), 380) * decay(d, 0.45, 0.005) * 0.9
    screech = sum(a * osc(sweep(f, f * 0.6, d), d) * decay(d, 0.4) for f, a in ((1200, 0.15), (1740, 0.1)))
    out = boom + screech
    for _ in range(30):
        at = rng.uniform(0.05, 1.0)
        c = bp(noise(0.04), 400, 2500) * decay(0.04, 0.01)
        place(out, c, at, rng.uniform(0.1, 0.4) * (1.1 - at))
    return out


def brass(freq, dur):
    return lp(osc(freq, dur, 'saw') + 0.5 * osc(freq * 1.003, dur, 'saw'), 2200) * adsr(dur, 0.04, 0.1, 0.75, 0.15)


def s_raid_win():
    out = silence(1.5)
    for i, nm in enumerate(('G4', 'C5', 'E5')):
        place(out, brass(note(nm), 0.2), i * 0.12, 0.5)
    for nm in ('C5', 'E5', 'G5', 'C6'):
        place(out, brass(note(nm), 0.9), 0.38, 0.32)
    return out


def s_raid_lose():
    out = silence(1.3)
    for i, nm in enumerate(('G4', 'Eb4', 'C4')):
        place(out, lp(brass(note(nm), 0.45 if i < 2 else 0.8), 1300), i * 0.25, 0.55)
    return out


def amb_vault(d):
    t = tt(d)
    # every tone has a whole number of cycles over the loop length (8 s), so it repeats cleanly
    drone = (np.sin(2 * np.pi * 55 * t) + np.sin(2 * np.pi * 55.125 * t)) * 0.5
    drone += 0.5 * (np.sin(2 * np.pi * 82.5 * t) + np.sin(2 * np.pi * 82.625 * t)) * 0.5
    drone += 0.25 * np.sin(2 * np.pi * 110.25 * t)
    air = lp(brown(d), 320) * 0.8 + bp(noise(d), 500, 1500) * 0.025
    return drone * 0.35 + air


def hum_power(d):
    t = tt(d)
    hum = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((50, 1.0), (100, 0.6), (150, 0.35), (200, 0.2), (300, 0.12)))
    whine = 0.12 * np.sin(2 * np.pi * 1200 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * t))
    return hum * 0.5 + whine + lp(noise(d), 1800) * 0.03


def hum_water(d):
    out = lp(brown(d), 900) * 0.3
    for k in range(int(d)):
        pulse = osc(sweep(70, 55, 0.35), 0.35) * adsr(0.35, 0.03, 0.1, 0.5, 0.2)
        place(out, pulse, k * 1.0, 0.55)
    for _ in range(int(12 * d)):
        bd = rng.uniform(0.02, 0.06)
        bub = osc(sweep(rng.uniform(300, 600), rng.uniform(800, 1500), bd), bd) * decay(bd, bd / 2.5)
        place(out, bub, rng.uniform(0, d - bd), rng.uniform(0.05, 0.15))
    trickle = bp(noise(d), 1000, 3000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 3 * tt(d)))) * 0.05
    return out + trickle


ONE_SHOTS = [
    ('ui_click', s_click), ('ui_open', s_open), ('ui_close', s_close), ('ui_error', s_error),
    ('collect', s_collect), ('bolts', s_bolts), ('build', s_build), ('upgrade', s_upgrade),
    ('demolish', s_demolish), ('rush', s_rush), ('levelup', s_levelup), ('heal', s_heal),
    ('revive', s_revive), ('doorbell', s_doorbell), ('welcome', s_welcome), ('birth', s_birth),
    ('romance', s_romance), ('death', s_death), ('fire_start', s_fire_start), ('extinguish', s_extinguish),
    ('breakdown', s_breakdown), ('repair_done', s_repair_done), ('creature', s_creature),
    ('gunshot', s_gunshot), ('punch', s_punch), ('door_hit', s_door_hit), ('door_breach', s_door_breach),
    ('raid_win', s_raid_win), ('raid_lose', s_raid_lose),
]
# (name, render, loop seconds, crossfade seconds, equal-power crossfade)
LOOPS = [
    ('alarm', alarm_loop, 1.6, 0.0, False), ('fire', fire_loop, 3.0, 0.25, True),
    ('amb_vault', amb_vault, 8.0, 0.4, False), ('hum_power', hum_power, 4.0, 0.3, False),
    ('hum_water', hum_water, 4.0, 0.3, True),
]


def render():
    parts, regions = [silence(GAP)], []
    pos = GAP
    for name, fn in ONE_SHOTS:
        x = edges(norm(fn(), 0.9))
        regions.append((name, pos, len(x) / SR, False))
        parts += [x, silence(GAP)]
        pos += len(x) / SR + GAP
    for name, fn, length, xfade, power in LOOPS:
        x = make_loop(fn, length, xfade, power) if xfade > 0 else fn(length)
        x = norm(x, 0.9)
        # wrap padding: the loop's own tail before it and head after it, so the encoder (which
        # smears a little across region edges) sees continuous sound across the loop point
        pad = n_(0.1)
        regions.append((name, pos + pad / SR, len(x) / SR, True))
        parts += [x[-pad:], x, x[:pad], silence(GAP)]
        pos += (len(x) + 2 * pad) / SR + GAP
    return np.concatenate(parts), regions


def check(audio, regions):
    assert np.all(np.isfinite(audio)), 'non-finite samples'
    assert np.max(np.abs(audio)) <= 0.95, 'clipping'
    for name, start, length, loop in regions:
        a, b = n_(start), n_(start) + n_(length)
        seg = audio[a:b]
        assert np.max(np.abs(seg)) > 0.5, name + ' is silent'
        if loop:
            # wrapping from the last sample to the first must look like any ordinary step
            jump = abs(seg[-1] - seg[0])
            step = np.percentile(np.abs(np.diff(seg)), 99)
            assert jump <= step * 1.2 + 1e-3, '%s loop seam jumps %.4f (99th pct step %.4f)' % (name, jump, step)


def main():
    audio, regions = render()
    check(audio, regions)
    os.makedirs(os.path.join(ROOT, 'audio'), exist_ok=True)
    wav = os.path.join(ROOT, 'audio', 'underhaven_sounds.wav')
    ogg = os.path.join(ROOT, 'audio', 'underhaven_sounds.ogg')
    pcm = (np.clip(audio, -1, 1) * 32767).astype('<i2')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '6', ogg], check=True)
    os.remove(wav)
    lines = [
        '--!strict',
        '-- GENERATED by tools/make_sounds.py - do not edit by hand.',
        '-- Where each sound sits in the audio atlas (audio/underhaven_sounds.ogg):',
        '-- name = { start seconds, length seconds, loops }',
        'return {',
    ]
    for name, start, length, loop in regions:
        lines.append('\t%s = { %.4f, %.4f, %s },' % (name, start, length, 'true' if loop else 'false'))
    lines.append('}')
    out = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'Shared', 'SoundAtlas.lua')
    with open(out, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    total = len(audio) / SR
    print('%d sounds, %.1f s, %s (%d KB); regions -> %s' % (len(regions), total, ogg, os.path.getsize(ogg) // 1024, out))


if __name__ == '__main__':
    main()
