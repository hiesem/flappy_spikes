#!/usr/bin/env python3
"""PRD-2.3 §16.3: make the seamless 56-bar music loop.

    python3 -I tool/make_music_loop.py [--report out.txt] [--page ../design/music_v23]

Reads ``assets/audio/HappyBeat_8-Bit_Retro_Game_Loop.mp3`` and writes
``assets/audio/HappyBeat_loop_56bars.ogg``: exactly 56 bars at 146 BPM
(4 059 616 samples at 44 100 Hz), with a 5 ms equal-power crossfade at the
seam, as OGG Vorbis q6 tagged ``ANDROID_LOOP=true``. The maths is the one of
the approved version 3 of ``design/music_v23/loop_test_src.html``.

Only ffmpeg and the Python standard library. Every step asserts what the PRD
expects; the verification (step 8) fails the script on any mismatch. The
printed report goes into docs/p23/MUSIC.md.
"""

from __future__ import annotations

import argparse
import array
import base64
import importlib.util
import json
import math
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MP3 = ROOT / "assets" / "audio" / "HappyBeat_8-Bit_Retro_Game_Loop.mp3"
OGG = ROOT / "assets" / "audio" / "HappyBeat_loop_56bars.ogg"

_spec = importlib.util.spec_from_file_location(
    "loop_seam_check", pathlib.Path(__file__).resolve().parent / "loop_seam_check.py")
seam = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(seam)

SR = seam.SR
EXPECT_DECODED = 4_060_800
EXPECT_END = 4_060_800
L = seam.LOOP  # round(56 × 240 / 146 × 44100)
EXPECT_L = 4_059_616
FADE = 221  # 5 ms
TH = seam.TH


def check(cond: bool, what: str) -> None:
    if not cond:
        raise SystemExit(f"FAILED: {what}")
    print(f"  ok  {what}")


def last_granule(path: pathlib.Path) -> int:
    """Granule position of the last Ogg page (Vorbis: the sample count)."""
    data = path.read_bytes()
    i = data.rfind(b"OggS")
    check(i >= 0, "the OGG has pages")
    return int.from_bytes(data[i + 6:i + 14], "little", signed=True)


def vorbis_info(path: pathlib.Path) -> dict:
    """Sample rate / channels from the identification header, and the
    comments from the comment header."""
    data = path.read_bytes()
    i = data.find(b"\x01vorbis")
    channels = data[i + 11]
    rate = int.from_bytes(data[i + 12:i + 16], "little")
    j = data.find(b"\x03vorbis")
    k = j + 7
    vlen = int.from_bytes(data[k:k + 4], "little")
    k += 4 + vlen
    count = int.from_bytes(data[k:k + 4], "little")
    k += 4
    comments = []
    for _ in range(count):
        n = int.from_bytes(data[k:k + 4], "little")
        k += 4
        comments.append(data[k:k + n].decode("utf-8", "replace"))
        k += n
    return {"rate": rate, "channels": channels, "comments": comments}


def lufs(path: pathlib.Path) -> float:
    err = subprocess.run(
        ["ffmpeg", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
    check(bool(m), f"ebur128 loudness of {path.name}")
    return float(m[-1])


def rms_db(a, b) -> float:
    s = sum((x - y) ** 2 for x, y in zip(a, b))
    return seam.db(math.sqrt(s / max(1, len(a))))


def make_cut():
    """Steps 1-6 (shared with tool/make_music_loop_ios.py): decode the MP3 and
    return (start, end, (left, right)) — the float cut of exactly L samples
    with the 5 ms seam crossfade."""
    print("1. decode", MP3.relative_to(ROOT))
    xl, xr = seam.decode(MP3)
    check(len(xl) == EXPECT_DECODED, f"decoded length {len(xl)} == {EXPECT_DECODED}")

    print("2. find the end")
    last = len(xl) - 1
    while last > 0 and abs(xl[last]) <= TH and abs(xr[last]) <= TH:
        last -= 1
    end = last + 1
    check(end == EXPECT_END, f"end {end} == {EXPECT_END}")

    print("3. loop length")
    check(L == EXPECT_L, f"L = round(56 × 240/146 × 44100) = {L} == {EXPECT_L}")

    print("4. start")
    start = end - L
    check(start >= FADE, f"start {start} >= {FADE}")
    check(all(abs(xl[i]) <= TH and abs(xr[i]) <= TH for i in range(start)),
          f"samples [0, {start}) are below -50 dBFS (only lead-in silence is cut)")

    print("5. cut, 6. crossfade the last 5 ms into what led into the first beat")
    outs = []
    for x in (xl, xr):
        o = x[start:end]
        for i in range(FADE):
            t = (i + 0.5) / FADE
            j = L - FADE + i
            o[j] = (x[start + L - FADE + i] * math.cos(t * math.pi / 2)
                    + x[start - FADE + i] * math.sin(t * math.pi / 2))
        outs.append(o)
    ol, orr = outs
    check(len(ol) == L, f"cut length {len(ol)} == L")

    return start, end, (ol, orr)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--report", help="also write the report to this file")
    ap.add_argument("--page", help="design/music_v23 folder: rebuild loop_test.html "
                    "from loop_test_src.html with both files embedded (card 4)")
    args = ap.parse_args()

    start, end, (ol, orr) = make_cut()

    print("7. encode OGG Vorbis q6")
    inter = array.array("f", bytes(8 * L))
    inter[0::2] = ol
    inter[1::2] = orr
    if sys.byteorder != "little":
        inter.byteswap()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
         "-i", "-", "-c:a", "libvorbis", "-q:a", "6",
         "-metadata", "ANDROID_LOOP=true",
         "-metadata", "title=HappyBeat loop (56 bars)", str(OGG)],
        input=inter.tobytes(), check=True,
    )

    print("8. verify")
    granule = last_granule(OGG)
    check(granule == L, f"last Ogg page granule {granule} == {L}")
    info = vorbis_info(OGG)
    check(info["rate"] == SR and info["channels"] == 2,
          f"Vorbis header {info['rate']} Hz, {info['channels']} channels")
    check(any(c.upper() == "ANDROID_LOOP=TRUE" for c in info["comments"]),
          "ANDROID_LOOP=true comment present")
    dl, dr = seam.decode(OGG)
    check(len(dl) == L, f"decoded OGG length {len(dl)} == {L}")
    # First / last 221 samples against the float cut. The PRD's "RMS
    # difference below −40 dB" is read as dBFS (an absolute error level).
    head = max(rms_db(dl[:FADE], ol[:FADE]), rms_db(dr[:FADE], orr[:FADE]))
    tail = max(rms_db(dl[-FADE:], ol[-FADE:]), rms_db(dr[-FADE:], orr[-FADE:]))
    check(head < -40, f"first {FADE} samples RMS difference {head:.1f} dBFS < -40")
    check(tail < -40, f"last {FADE} samples RMS difference {tail:.1f} dBFS < -40")
    lu_mp3, lu_ogg = lufs(MP3), lufs(OGG)
    check(abs(lu_mp3 - lu_ogg) <= 0.5,
          f"loudness {lu_ogg:.1f} LUFS vs MP3 {lu_mp3:.1f} LUFS (within 0.5 dB)")
    s = seam.check_file_seam((dl, dr), (ol, orr))
    check(abs(s["downbeat_offset_ms"]) <= 2.0,
          f"downbeat after the wrap {s['downbeat_offset_ms']:+.3f} ms from the "
          "146 BPM grid (±2 ms)")
    check(s["extra_silence_ms"] < 10,
          f"seam silence {s['silence_at_seam_ms']} ms = the cut's own lead-in "
          f"{s['silence_in_cut_ms']} ms + {s['extra_silence_ms']} ms (< 10 ms extra)")
    check(not s["click"], f"no click at the seam (jump {s['seam_jump_dbfs']} dBFS)")

    size = OGG.stat().st_size
    report = {
        "start": start, "end": end, "L": L,
        "duration_s": round(L / SR, 6),
        "granule": granule,
        "size_bytes": size,
        "bitrate_kbps": round(size * 8 / (L / SR) / 1000, 1),
        "lufs_mp3": lu_mp3, "lufs_ogg": lu_ogg,
        "head_rms_diff_dbfs": round(head, 1), "tail_rms_diff_dbfs": round(tail, 1),
        "seam": s,
    }
    text = "make_music_loop.py report\n" + json.dumps(report, indent=2)
    print(text)
    if args.report:
        pathlib.Path(args.report).write_text(text + "\n")
    if args.page:
        d = pathlib.Path(args.page)
        src = (d / "loop_test_src.html").read_text()
        page = (src.replace("__MP3__", base64.b64encode(MP3.read_bytes()).decode())
                .replace("__OGG__", base64.b64encode(OGG.read_bytes()).decode()))
        (d / "loop_test.html").write_text(page)
        print(f"wrote {d / 'loop_test.html'} ({len(page)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
