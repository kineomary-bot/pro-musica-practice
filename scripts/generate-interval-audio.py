#!/usr/bin/env python3
"""Create clear, short piano-style interval reference recordings for Pro Musica."""
from __future__ import annotations

import hashlib
import math
import pathlib
import struct
import subprocess
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent / "site" / "audio" / "pitch-intervals"
SAMPLE_RATE = 44_100
NOTE_SECONDS = 0.72
GAP_SECONDS = 0.16
TAIL_SECONDS = 0.12
AMPLITUDE = 0.72

# C-major reference scale: Do is middle C (C4); the final Do is C5.
NOTES = {
    "Do": 261.625565,
    "Re": 293.664768,
    "Me": 311.126984,
    "Mi": 329.627557,
    "Fa": 349.228231,
    "Sol": 391.995436,
    "La": 440.000000,
    "Le": 415.304698,
    "Ti": 493.883301,
    "Te": 466.163762,
    "Do_high": 523.251131,
}

FILES = {
    "do-re.mp3": ("Do", "Re"),
    "re-do.mp3": ("Re", "Do"),
    "do-mi.mp3": ("Do", "Mi"),
    "mi-do.mp3": ("Mi", "Do"),
    "do-fa.mp3": ("Do", "Fa"),
    "fa-do.mp3": ("Fa", "Do"),
    "do-sol.mp3": ("Do", "Sol"),
    "sol-do.mp3": ("Sol", "Do"),
    "do-la.mp3": ("Do", "La"),
    "la-do.mp3": ("La", "Do"),
    "do-ti.mp3": ("Do", "Ti"),
    "ti-do.mp3": ("Ti", "Do"),
    "do-high-do.mp3": ("Do", "Do_high"),
    "high-do-low-do.mp3": ("Do_high", "Do"),
}

# Natural minor additions: Me, Le and Te are lowered by one semitone.
MINOR_FILES = {
    "do-me.mp3": ("Do", "Me"),
    "me-do.mp3": ("Me", "Do"),
    "do-le.mp3": ("Do", "Le"),
    "le-do.mp3": ("Le", "Do"),
    "do-te.mp3": ("Do", "Te"),
    "te-do.mp3": ("Te", "Do"),
}

# Partial balance and decay give a gentle, plucked piano-like timbre rather
# than a pure sine wave. Each harmonic fades at a different rate.
PARTIALS = (
    (1, 1.00, 1.45),
    (2, 0.48, 0.92),
    (3, 0.25, 0.62),
    (4, 0.14, 0.46),
    (5, 0.085, 0.34),
    (6, 0.055, 0.27),
    (7, 0.035, 0.22),
    (8, 0.022, 0.18),
)


def make_note(frequency: float, seconds: float) -> list[float]:
    count = int(SAMPLE_RATE * seconds)
    result: list[float] = []
    for n in range(count):
        t = n / SAMPLE_RATE
        attack = min(1.0, t / 0.009)
        value = 0.0
        for harmonic, level, decay in PARTIALS:
            # Slight inharmonicity adds a piano-string character.
            stretch = 1.0 + 0.000018 * (harmonic ** 2)
            phase = 2.0 * math.pi * frequency * harmonic * stretch * t
            value += level * math.exp(-t / decay) * math.sin(phase)
        # A very soft hammer transient gives the note a defined beginning.
        hammer = 0.018 * math.exp(-t / 0.012) * math.sin(2.0 * math.pi * 2850.0 * t)
        fade = min(1.0, max(0.0, (seconds - t) / 0.025))
        result.append(AMPLITUDE * attack * fade * (value / 2.0 + hammer))
    return result


def make_recording(first: str, second: str) -> list[float]:
    first_note = make_note(NOTES[first], NOTE_SECONDS)
    second_note = make_note(NOTES[second], NOTE_SECONDS + TAIL_SECONDS)
    silence = [0.0] * int(SAMPLE_RATE * GAP_SECONDS)
    return first_note + silence + second_note


def write_wav(path: pathlib.Path, samples: list[float]) -> None:
    # Slightly narrow the right channel level for a subtle stereo image while
    # keeping the pitch centred and compatible with mono phone speakers.
    frames = bytearray()
    for sample in samples:
        left = max(-1.0, min(1.0, sample))
        right = max(-1.0, min(1.0, sample * 0.985))
        frames.extend(struct.pack("<hh", int(left * 32767), int(right * 32767)))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(frames)


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pro-musica-intervals-") as tmp:
        tmpdir = pathlib.Path(tmp)
        for filename, pair in {**FILES, **MINOR_FILES}.items():
            wav_path = tmpdir / (filename + ".wav")
            mp3_path = ROOT / filename
            write_wav(wav_path, make_recording(*pair))
            subprocess.run(
                [
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(wav_path), "-codec:a", "libmp3lame",
                    "-b:a", "96k", "-ar", str(SAMPLE_RATE), "-ac", "2",
                    str(mp3_path),
                ],
                check=True,
            )
            if not mp3_path.is_file() or mp3_path.stat().st_size < 1000:
                raise RuntimeError(f"Audio export failed or is unexpectedly small: {mp3_path}")
            print(f"Created {filename}: {pair[0]} -> {pair[1]} ({mp3_path.stat().st_size:,} bytes)")

    hashes = {hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in {**FILES, **MINOR_FILES}}
    if len(hashes) != len({**FILES, **MINOR_FILES}):
        raise RuntimeError("Generated recordings are not all distinct; refusing to continue.")
    print(f"Successfully generated {len(FILES) + len(MINOR_FILES)} unique interval recordings in {ROOT}")


if __name__ == "__main__":
    main()
