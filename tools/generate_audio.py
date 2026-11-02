#!/usr/bin/env python3
"""Generate every audio asset ATHAR ships.

Why this exists
---------------
The project has no licensed audio library and the owner's brief forbids using
copyrighted material or inventing assets. Every sound in `assets/audio/` is
therefore *synthesised here*, from sine waves and filtered noise, by this script.
Nothing is sampled from a recording, so the output is original project work with
no third-party rights attached — see assets/audio/LICENSE.txt.

Re-running the script regenerates the exact same files: all randomness uses a
fixed seed, so the repository stays reproducible.

Looping sounds are made seamless by construction rather than by cross-fading:

* noise beds are shaped in the frequency domain, so the buffer is circular and
  the last sample joins the first with no click;
* every tonal element (music pad, crickets, chirps, snorts) has its frequency
  snapped to a whole number of cycles over the loop, so it too wraps cleanly.

Usage:  python3 tools/generate_audio.py
"""

from __future__ import annotations

import math
import os
import wave

import numpy as np

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
SEED = 20261101


# --------------------------------------------------------------- helpers ----
def _rng() -> np.random.Generator:
    return np.random.default_rng(SEED)


def _write(name: str, samples: np.ndarray, rate: int, peak: float) -> float:
    """Normalises to `peak`, writes 16-bit mono PCM, returns the byte size."""
    data = np.asarray(samples, dtype=np.float64)
    top = float(np.max(np.abs(data))) if data.size else 0.0
    if top > 0.0:
        data = data / top * peak
    data = np.clip(data, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")

    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(rate)
        fh.writeframes(pcm.tobytes())
    return os.path.getsize(path) / 1024.0


def _snap(freq: float, loop_seconds: float) -> float:
    """Nearest frequency that completes whole cycles over the loop."""
    grid = 1.0 / loop_seconds
    return max(grid, round(freq / grid) * grid)


def _tone(freq: float, seconds: float, rate: int, phase: float = 0.0) -> np.ndarray:
    t = np.arange(int(seconds * rate)) / rate
    return np.sin(2.0 * math.pi * freq * t + phase)


def _circular_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    """White noise of exactly n samples: periodic by definition."""
    return rng.standard_normal(n)


def _spectral_shape(x: np.ndarray, rate: int, curve) -> np.ndarray:
    """Filters `x` in the frequency domain with `curve(freq_hz) -> gain`.

    Working in the frequency domain keeps the buffer circular, which is what
    makes the result loop without a seam.
    """
    n = x.size
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    spec *= curve(freqs)
    out = np.fft.irfft(spec, n)
    return out


def _lowpass_curve(cutoff: float, order: float = 2.0):
    def curve(freqs: np.ndarray) -> np.ndarray:
        return 1.0 / np.sqrt(1.0 + (freqs / cutoff) ** (2.0 * order))

    return curve


def _bandpass_curve(low: float, high: float):
    def curve(freqs: np.ndarray) -> np.ndarray:
        lo = 1.0 / np.sqrt(1.0 + (low / np.maximum(freqs, 1e-6)) ** 4.0)
        hi = 1.0 / np.sqrt(1.0 + (freqs / high) ** 4.0)
        return lo * hi

    return curve


def _periodic_envelope(n: int, loop_seconds: float, parts, rate: int) -> np.ndarray:
    """Sum of sines whose periods divide the loop, so the envelope also loops."""
    t = np.arange(n) / rate
    env = np.zeros(n)
    for freq, depth, phase in parts:
        env += depth * np.sin(2.0 * math.pi * _snap(freq, loop_seconds) * t + phase)
    return env


def _decay(n: int, rate: int, attack: float, tau: float) -> np.ndarray:
    t = np.arange(n) / rate
    rise = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return rise * np.exp(-t / max(tau, 1e-5))


# ----------------------------------------------------------------- beds -----
def ambience_day() -> None:
    """Wind in leaves, with a few distant birds."""
    loop = 8.0
    rate = 16000
    n = int(loop * rate)
    rng = _rng()

    # Circular wind: low-passed noise, gently breathing.
    wind = _spectral_shape(_circular_noise(n, rng), rate, _lowpass_curve(320.0, 1.6))
    wind *= 0.55 + 0.45 * _periodic_envelope(n, loop, [(0.125, 1.0, 0.0), (0.37, 0.4, 1.1)], rate)
    wind *= 0.5

    # Leaves: band-passed noise, rustled by a faster envelope.
    leaves = _spectral_shape(_circular_noise(n, rng), rate, _bandpass_curve(1200.0, 5200.0))
    rustle = 0.35 + 0.65 * np.maximum(
        0.0, _periodic_envelope(n, loop, [(0.5, 0.6, 0.0), (1.25, 0.35, 2.0), (2.5, 0.2, 0.7)], rate)
    )
    leaves *= rustle
    leaves *= 0.28

    mix = wind + leaves

    # Distant birds: short FM chirps, kept away from the loop seam.
    for start, base, glide in ((1.35, 2800.0, 900.0), (3.1, 3200.0, -700.0), (5.6, 2600.0, 1100.0), (6.9, 3000.0, -600.0)):
        length = 0.16
        m = int(length * rate)
        t = np.arange(m) / rate
        freq = _snap(base, loop) + glide * t / length
        chirp = np.sin(2.0 * math.pi * freq * t)
        # A touch of vibrato, typical of a small bird.
        chirp *= 1.0 + 0.25 * np.sin(2.0 * math.pi * 38.0 * t)
        chirp *= _decay(m, rate, 0.012, 0.055)
        i = int(start * rate)
        mix[i:i + m] += chirp * 0.12
        # Repeat faintly, as if further away.
        j = i + int(0.22 * rate)
        if j + m <= n:
            mix[j:j + m] += chirp * 0.06

    print("ambience_day.wav        %6.1f KB" % _write("ambience_day.wav", mix, rate, 0.45))


def ambience_night() -> None:
    """Crickets and a still, cold air bed."""
    loop = 8.0
    rate = 16000
    n = int(loop * rate)
    rng = _rng()

    air = _spectral_shape(_circular_noise(n, rng), rate, _lowpass_curve(240.0, 1.4))
    air *= 0.20 + 0.12 * _periodic_envelope(n, loop, [(0.25, 1.0, 0.3)], rate)

    crickets = np.zeros(n)
    # Two cricket voices: a fast pulse train inside a slow chirp envelope.
    for base, pulse_hz, offset, level in ((4200.0, 26.0, 0.0, 1.0), (3650.0, 31.0, 0.9, 0.7)):
        t = np.arange(n) / rate
        carrier = np.sin(2.0 * math.pi * _snap(base, loop) * t)
        pulse = 0.5 + 0.5 * np.sign(np.sin(2.0 * math.pi * _snap(pulse_hz, loop) * (t + offset)))
        group = np.maximum(
            0.0,
            0.5 + 0.5 * np.sin(2.0 * math.pi * _snap(0.5, loop) * t + offset * 3.0)
            + 0.35 * np.sin(2.0 * math.pi * _snap(0.17, loop) * t),
        )
        crickets += carrier * pulse * group * level * 0.12

    mix = air + crickets
    print("ambience_night.wav      %6.1f KB" % _write("ambience_night.wav", mix, rate, 0.42))


def rain_loop() -> None:
    """A steady shower: broadband hiss plus individual droplets."""
    loop = 6.0
    rate = 16000
    n = int(loop * rate)
    rng = _rng()

    body = _spectral_shape(_circular_noise(n, rng), rate, _bandpass_curve(600.0, 7000.0))
    body *= 0.85 + 0.15 * _periodic_envelope(n, loop, [(0.33, 1.0, 0.0)], rate)
    mix = body * 0.7

    # Droplets: short high bursts, wrapped around the seam so the loop stays even.
    for _ in range(90):
        m = int(0.012 * rate)
        start = int(rng.integers(0, n))
        burst = rng.standard_normal(m) * _decay(m, rate, 0.0015, 0.004)
        idx = (np.arange(m) + start) % n
        mix[idx] += burst * 0.25

    print("rain_loop.wav           %6.1f KB" % _write("rain_loop.wav", mix, rate, 0.5))


def music_ambient() -> None:
    """A slow, quiet drone pad: three chords, no percussion, no melody."""
    loop = 12.0
    rate = 12000
    n = int(loop * rate)
    t = np.arange(n) / rate

    # Am - F - G, voiced low and wide, with a soft top octave.
    chords = [
        [110.0, 164.81, 220.0, 329.63],
        [87.31, 130.81, 174.61, 261.63],
        [98.0, 146.83, 196.0, 293.66],
    ]
    pad = np.zeros(n)
    chord_len = n // len(chords)
    fade = int(0.9 * rate)
    for index, chord in enumerate(chords):
        start = index * chord_len
        end = min(n, start + chord_len)
        segment = np.zeros(end - start)
        for voice_index, freq in enumerate(chord):
            f = _snap(freq, loop)
            detune = _snap(freq * 1.004, loop)
            segment += np.sin(2.0 * math.pi * f * t[:end - start] + voice_index)
            segment += 0.6 * np.sin(2.0 * math.pi * detune * t[:end - start])
        # Cross-fade the chord in and out so the pad breathes between chords.
        window = np.ones(end - start)
        if start > 0:
            ramp = min(fade, end - start)
            window[:ramp] = np.linspace(0.0, 1.0, ramp)
        if end < n:
            ramp = min(fade, end - start)
            window[-ramp:] = np.linspace(1.0, 0.0, ramp)
        pad[start:end] += segment * window
        pad[start:end] *= 1.0

    # A very slow swell, and one quiet high shimmer.
    pad *= 0.75 + 0.25 * _periodic_envelope(n, loop, [(1.0 / 12.0, 1.0, 0.0)], rate)
    shimmer = np.sin(2.0 * math.pi * _snap(880.0, loop) * t) * (0.5 + 0.5 * np.sin(2.0 * math.pi * _snap(1.0 / 12.0, loop) * t))
    pad += shimmer * 0.06

    print("music_ambient.wav       %6.1f KB" % _write("music_ambient.wav", pad, rate, 0.30))


# ----------------------------------------------------------------- steps ----
def steps() -> None:
    """Footsteps: three grass, two soil, two hooves. Short, dry, low-level."""
    rate = 22050
    rng = _rng()

    for i in range(3):
        m = int(0.16 * rate)
        body = np.random.default_rng(SEED + i).standard_normal(m)
        body = _spectral_shape(body, rate, _bandpass_curve(320.0, 3400.0))
        step = body * _decay(m, rate, 0.004, 0.035 - i * 0.005)
        scratch = np.random.default_rng(SEED + 40 + i).standard_normal(m)
        scratch = _spectral_shape(scratch, rate, _bandpass_curve(1800.0, 6000.0))
        step += scratch * _decay(m, rate, 0.002, 0.018) * 0.35
        print("step_grass_%d.wav       %6.1f KB" % (i + 1, _write("step_grass_%d.wav" % (i + 1), step, rate, 0.55)))

    for i in range(2):
        m = int(0.14 * rate)
        # Stone: brighter and shorter, with a faint ring from the slab.
        body = np.random.default_rng(SEED + 120 + i).standard_normal(m)
        body = _spectral_shape(body, rate, _bandpass_curve(700.0, 5200.0))
        click = body * _decay(m, rate, 0.0015, 0.014)
        ring = _tone(1760.0 + i * 90.0, m / rate, rate) * _decay(m, rate, 0.001, 0.02)
        stone = click + ring * 0.22
        print("step_stone_%d.wav       %6.1f KB" % (i + 1, _write("step_stone_%d.wav" % (i + 1), stone, rate, 0.55)))

    for i in range(2):
        m = int(0.18 * rate)
        body = np.random.default_rng(SEED + 60 + i).standard_normal(m)
        # Dirt: duller, with a little more weight.
        body = _spectral_shape(body, rate, _bandpass_curve(120.0, 1400.0))
        thump = _tone(70.0 + i * 6.0, m / rate, rate) * _decay(m, rate, 0.003, 0.05)
        step = body * _decay(m, rate, 0.005, 0.045) + thump * 0.4
        print("step_soil_%d.wav        %6.1f KB" % (i + 1, _write("step_soil_%d.wav" % (i + 1), step, rate, 0.6)))

    for i in range(2):
        m = int(0.12 * rate)
        body = np.random.default_rng(SEED + 80 + i).standard_normal(m)
        body = _spectral_shape(body, rate, _bandpass_curve(90.0, 900.0))
        hoof = body * _decay(m, rate, 0.002, 0.028)
        hoof += _tone(120.0 - i * 15.0, m / rate, rate) * _decay(m, rate, 0.002, 0.03) * 0.5
        print("hoof_%d.wav             %6.1f KB" % (i + 1, _write("hoof_%d.wav" % (i + 1), hoof, rate, 0.5)))


# ------------------------------------------------------------------ deer ----
def deer_calls() -> None:
    """A warning snort and a short flight of hooves."""
    rate = 22050
    rng = _rng()

    # Snort: a nasal bark, then a breathy tail.
    m = int(0.42 * rate)
    t = np.arange(m) / rate
    bark = np.sin(2.0 * math.pi * (340.0 - 120.0 * t) * t)
    bark *= _decay(m, rate, 0.01, 0.09)
    air = _spectral_shape(rng.standard_normal(m), rate, _bandpass_curve(600.0, 2600.0))
    air *= _decay(m, rate, 0.006, 0.11)
    snort = bark * 0.7 + air * 0.8
    print("deer_alert.wav          %6.1f KB" % _write("deer_alert.wav", snort, rate, 0.75))

    # Flight: the snort, then four fading hoofbeats.
    total = int(1.1 * rate)
    flight = np.zeros(total)
    flight[:m] += snort * 0.8
    for i in range(4):
        hm = int(0.1 * rate)
        body = np.random.default_rng(SEED + 100 + i).standard_normal(hm)
        body = _spectral_shape(body, rate, _bandpass_curve(100.0, 800.0))
        hoof = body * _decay(hm, rate, 0.0015, 0.024)
        start = int((0.28 + i * 0.19) * rate)
        level = 0.9 - i * 0.16
        flight[start:start + hm] += hoof * level
    print("deer_flee.wav           %6.1f KB" % _write("deer_flee.wav", flight, rate, 0.7))


def ui_and_capture() -> None:
    rate = 22050
    rng = _rng()

    m = int(0.05 * rate)
    tap = _spectral_shape(rng.standard_normal(m), rate, _bandpass_curve(900.0, 5000.0))
    tap *= _decay(m, rate, 0.001, 0.008)
    print("ui_tap.wav              %6.1f KB" % _write("ui_tap.wav", tap, rate, 0.42))

    # Capture: a soft two-note confirmation, no fanfare.
    m = int(1.1 * rate)
    t = np.arange(m) / rate
    chime = np.zeros(m)
    for freq, level, delay in ((587.33, 1.0, 0.0), (880.0, 0.7, 0.10), (1174.66, 0.35, 0.20)):
        shifted = np.zeros(m)
        start = int(delay * rate)
        length = m - start
        tt = np.arange(length) / rate
        shifted[start:] = np.sin(2.0 * math.pi * freq * tt) * np.exp(-tt / 0.42)
        chime += shifted * level
    print("capture.wav             %6.1f KB" % _write("capture.wav", chime, rate, 0.6))


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print("generating original audio into %s" % OUT_DIR)
    print("")
    ambience_day()
    ambience_night()
    rain_loop()
    music_ambient()
    steps()
    deer_calls()
    ui_and_capture()
    total = sum(
        os.path.getsize(os.path.join(OUT_DIR, name)) for name in os.listdir(OUT_DIR) if name.endswith(".wav")
    )
    print("")
    print("total %.2f MB" % (total / (1024.0 * 1024.0)))


if __name__ == "__main__":
    main()
