#!/usr/bin/env python3
"""iOS round 2: the same seamless 56-bar music loop as Android, for iOS.

    python3 -I tool/make_music_loop_ios.py [--report out.txt]

iOS has no OGG Vorbis decoder, so the loop that Android plays
(``assets/audio/HappyBeat_loop_56bars.ogg``, ``tool/make_music_loop.py``) is
encoded again for iOS from the SAME float cut (steps 1-6 of
make_music_loop.py: 56 bars at 146 BPM = 4 059 616 samples at 44 100 Hz,
5 ms equal-power crossfade at the seam) as AAC-LC 192 kbit/s in an MP4
(``ios/Runner/HappyBeat_loop_56bars.m4a``, a bundle resource of the Runner
target, so Android never ships it; ~2.3 MB).

Why AAC + a native player and not the MP3 / AVPlayer
----------------------------------------------------
- An MP3 or AAC file always starts with encoder priming and ends with
  padding to a whole frame. AVPlayer (audioplayers' ``FlameAudio.bgm``)
  loops by seeking back to 0 when the item ends: the padding, the seek and
  the priming are a gap at every wrap.
- The iOS player (``AppDelegate.swift`` ``LoopMusic``) schedules the file
  segment [priming, priming + L) back to back on an ``AVAudioPlayerNode``
  (``scheduleSegment``, always two segments queued). The node plays
  scheduled segments sample-exactly one after the other, so the wrap has no
  gap and no click; the seam itself is the crossfaded float cut.
- The priming is 1024 samples (ffmpeg's AAC encoder, written to the MP4 edit
  list ``elst``: media_time 1024, duration L; the sample table ``stts``
  already ends at priming + L, the last packet's 544 padding samples cut).
  Core Audio may or may not apply these when it opens the file, so
  ``LoopMusic`` reads ``AVAudioFile.length`` and picks the offset: L (edit
  list applied) -> 0; L + 544 (start only) -> 0; L + 1024 (sample table
  only) -> 1024; L + 1568 (whole packets) -> 1024. The four lengths differ,
  so the choice is exact. These numbers are checked here and are the
  constants ``LoopMusic`` uses (``kLoopFrames`` / ``kPrimingFrames``).
- ALAC (lossless, no priming) would also be exact but is 9.5 MB; AAC 192k
  is 2.3 MB, the same size class as the OGG.

Verification (fails the script on any mismatch): the MP4's sample count, the
edit list, a decode that honours the edit list is exactly L samples, the
raw decode's best alignment against the float cut is the declared priming,
head / tail RMS difference < -40 dBFS, and the shared seam check
(``loop_seam_check.check_file_seam``): the downbeat after the wrap within
+-2 ms of the 146 BPM grid, no extra silence, no click.
"""

from __future__ import annotations

import argparse
import array
import importlib.util
import json
import math
import pathlib
import struct
import subprocess
import sys

TOOL = pathlib.Path(__file__).resolve().parent
ROOT = TOOL.parent
OUT = ROOT / "ios" / "Runner" / "HappyBeat_loop_56bars.m4a"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, TOOL / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mml = _load("make_music_loop")
seam = mml.seam
check = mml.check
SR = seam.SR
L = mml.L
FADE = mml.FADE
PRIMING = 1024  # ffmpeg AAC encoder delay (also LoopMusic.kPrimingFrames)
FRAME = 1024  # AAC-LC samples per packet
PACKETS = math.ceil((L + PRIMING) / FRAME)
REMAINDER = PACKETS * FRAME - L - PRIMING  # 544


def boxes(data: bytes, start: int, end: int):
    i = start
    while i + 8 <= end:
        size, kind = struct.unpack(">I4s", data[i:i + 8])
        hdr = 8
        if size == 1:
            size = struct.unpack(">Q", data[i + 8:i + 16])[0]
            hdr = 16
        if size < hdr:
            break
        yield kind.decode("latin-1"), i + hdr, i + size
        i += size


def find(data: bytes, path: list[str], start: int = 0, end: int | None = None):
    end = len(data) if end is None else end
    for kind, a, b in boxes(data, start, end):
        if kind == path[0]:
            if len(path) == 1:
                return a, b
            return find(data, path[1:], a, b)
    return None


def mp4_info(path: pathlib.Path) -> dict:
    d = path.read_bytes()
    trak = ["moov", "trak"]
    elst = find(d, trak + ["edts", "elst"])
    check(elst is not None, "the MP4 has an edit list")
    a, _ = elst
    version = d[a]
    count = struct.unpack(">I", d[a + 4:a + 8])[0]
    check(count == 1, f"one edit list entry ({count})")
    if version == 1:
        dur, media = struct.unpack(">Qq", d[a + 8:a + 24])
    else:
        dur, media = struct.unpack(">Ii", d[a + 8:a + 16])
    mvhd = find(d, ["moov", "mvhd"])
    a2, _ = mvhd
    mv_scale = struct.unpack(">I", d[a2 + (20 if d[a2] == 1 else 12):][:4])[0]
    mdhd = find(d, trak + ["mdia", "mdhd"])
    a3, _ = mdhd
    if d[a3] == 1:
        md_scale, md_dur = struct.unpack(">IQ", d[a3 + 20:a3 + 32])
    else:
        md_scale, md_dur = struct.unpack(">II", d[a3 + 12:a3 + 20])
    stts = find(d, trak + ["mdia", "minf", "stbl", "stts"])
    a4, _ = stts
    n = struct.unpack(">I", d[a4 + 4:a4 + 8])[0]
    samples = 0
    packets = 0
    for k in range(n):
        c, delta = struct.unpack(">II", d[a4 + 8 + 8 * k:a4 + 16 + 8 * k])
        samples += c * delta
        packets += c
    return {
        "movie_timescale": mv_scale,
        "media_timescale": md_scale,
        "media_duration": md_dur,
        "edit_duration_movie": dur,
        "edit_media_time": media,
        "stts_samples": samples,
        "packets": packets,
    }


def decode_raw(path: pathlib.Path):
    """ffmpeg decode WITHOUT the edit list (all decoded samples)."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-ignore_editlist", "1", "-i", str(path),
         "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
        check=True, capture_output=True,
    ).stdout
    a = array.array("f")
    a.frombytes(raw)
    if sys.byteorder != "little":
        a.byteswap()
    return a[0::2], a[1::2]


def best_lag(dl, cl, lo: int, hi: int, n: int = 8192, at: int = 44100) -> int:
    """The lag of the decode against the cut with the smallest error."""
    best, best_e = lo, float("inf")
    for lag in range(lo, hi + 1):
        e = 0.0
        for i in range(at, at + n, 4):
            v = dl[i + lag] - cl[i]
            e += v * v
            if e >= best_e:
                break
        if e < best_e:
            best, best_e = lag, e
    return best


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--report", help="also write the report to this file")
    args = ap.parse_args()

    start, end, (ol, orr) = mml.make_cut()

    print("7. encode AAC-LC 192 kbit/s (MP4)")
    inter = array.array("f", bytes(8 * L))
    inter[0::2] = ol
    inter[1::2] = orr
    if sys.byteorder != "little":
        inter.byteswap()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
         "-i", "-", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
         "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
         "-metadata", "title=HappyBeat loop (56 bars)", str(OUT)],
        input=inter.tobytes(), check=True,
    )

    print("8. verify")
    info = mp4_info(OUT)
    check(info["media_timescale"] == SR, f"media timescale {info['media_timescale']} == {SR}")
    check(info["packets"] == PACKETS, f"{info['packets']} AAC packets == {PACKETS}")
    # ffmpeg shortens the last packet's stts delta by the padding: the
    # sample table ends exactly at the end of the cut.
    check(info["stts_samples"] == L + PRIMING,
          f"stts {info['stts_samples']} samples == priming + L ({L + PRIMING})")
    check(info["edit_media_time"] == PRIMING,
          f"edit list media_time {info['edit_media_time']} == priming {PRIMING}")
    edit = info["edit_duration_movie"] * SR / info["movie_timescale"]
    check(abs(edit - L) < 1, f"edit list duration {edit:.1f} samples == L {L}")
    check(REMAINDER == 544, f"remainder {REMAINDER} == 544 (LoopMusic's length table)")

    dl, dr = seam.decode(OUT)
    check(len(dl) == L, f"decode with the edit list: {len(dl)} samples == L")
    rl, rr = decode_raw(OUT)
    check(len(rl) in (L + PRIMING, PACKETS * FRAME),
          f"raw decode {len(rl)} == priming + L (or whole packets)")
    lag = best_lag(rl, ol, 0, 3000)
    check(lag == PRIMING, f"raw decode aligns with the cut at {lag} == priming {PRIMING}")
    check(all(abs(rl[PRIMING + i] - dl[i]) < 1e-6 for i in range(0, L, 9973)),
          "the raw decode from the priming == the edit-list decode")

    head = max(mml.rms_db(dl[:FADE], ol[:FADE]), mml.rms_db(dr[:FADE], orr[:FADE]))
    tail = max(mml.rms_db(dl[-FADE:], ol[-FADE:]), mml.rms_db(dr[-FADE:], orr[-FADE:]))
    check(head < -40, f"first {FADE} samples RMS difference {head:.1f} dBFS < -40")
    check(tail < -40, f"last {FADE} samples RMS difference {tail:.1f} dBFS < -40")
    lu_mp3, lu_out = mml.lufs(mml.MP3), mml.lufs(OUT)
    check(abs(lu_mp3 - lu_out) <= 0.5,
          f"loudness {lu_out:.1f} LUFS vs MP3 {lu_mp3:.1f} LUFS (within 0.5 dB)")
    s = seam.check_file_seam((dl, dr), (ol, orr))
    check(abs(s["downbeat_offset_ms"]) <= 2.0,
          f"downbeat after the wrap {s['downbeat_offset_ms']:+.3f} ms from the "
          "146 BPM grid (±2 ms)")
    check(s["extra_silence_ms"] < 10,
          f"seam silence {s['silence_at_seam_ms']} ms = the cut's own lead-in "
          f"{s['silence_in_cut_ms']} ms + {s['extra_silence_ms']} ms (< 10 ms extra)")
    check(not s["click"], f"no click at the seam (jump {s['seam_jump_dbfs']} dBFS)")

    size = OUT.stat().st_size
    report = {
        "file": str(OUT.relative_to(ROOT)),
        "start": start, "end": end, "L": L,
        "priming": PRIMING, "remainder": REMAINDER, "packets": PACKETS,
        "lengths_for_loopmusic": {
            "edit_list_applied": L,
            "nothing_applied": L + PRIMING + REMAINDER,
            "edit_start_only": L + REMAINDER,
            "sample_table_only": L + PRIMING,
        },
        "duration_s": round(L / SR, 6),
        "size_bytes": size,
        "bitrate_kbps": round(size * 8 / (L / SR) / 1000, 1),
        "lufs_mp3": lu_mp3, "lufs_m4a": lu_out,
        "head_rms_diff_dbfs": round(head, 1), "tail_rms_diff_dbfs": round(tail, 1),
        "seam": s,
    }
    text = "make_music_loop_ios.py report\n" + json.dumps(report, indent=2)
    print(text)
    if args.report:
        pathlib.Path(args.report).write_text(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
