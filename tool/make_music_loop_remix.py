#!/usr/bin/env python3
"""The game music: the Flappy Spikes remix, looped as the owner's option E.

    python3 -I tool/make_music_loop_remix.py [--report out.json]

Reads ``tool/music_src/Flappy_spikes_remix.mp3`` (the remix, 48 kHz stereo,
not shipped) and writes the two loop files the game plays:

- ``assets/audio/FlappySpikesRemix_loopE.ogg`` (Android: just_audio
  ``LoopMode.one``; Linux desktop: ``FlameAudio.bgm``), OGG Vorbis q6 tagged
  ``ANDROID_LOOP=true``;
- ``ios/Runner/FlappySpikesRemix_loopE.m4a`` (iOS: the runner's
  ``LoopMusic``, an ``AVAudioPlayerNode`` that schedules the segment
  [offset, offset + L) back to back), AAC-LC 192 kbit/s in an MP4.

Option E (approved in ``design/music_loop_remix/remix_loop.html``, crossfade
select = 80 ms) and how the page plays it (``src.html``, ``play()`` /
``queue()``):
- the loop is [START, END) = [0.176 s, 176.954 s) of the decoded MP3;
- every segment is scheduled back to back on the audio clock (``when +=
  len``). With the crossfade on, each segment keeps playing XF = 80 ms PAST
  its end (``s.start(when, off, len + xf)``) with its gain held at 1 until
  ``when + len`` and then ramped LINEARLY to 0 at ``when + len + xf``; the
  next segment starts at ``when + len`` from START with its gain ramped
  LINEARLY from 0 to 1 over the same 80 ms (``linearRampToValueAtTime``).
  The two are summed (linear crossfade, gains add to 1).
So one period of what the page plays, from the seam on, is

    y[i] = x[START + i] * i/X + x[END + i] * (1 - i/X)   for 0 <= i < X
    y[i] = x[START + i]                                  for X <= i < L

with L = END - START samples and X = 80 ms in samples. That period is the
loop file: its last sample is x[END - 1] and the wrap continues with y[0],
exactly the page's jump. The file starts at the seam, so the very first play
also begins with those 80 ms of crossfade (the page's first lap starts on
the plain x[START]); every later wrap is identical to the page.

The MP3 has no Xing/LAME gapless header, so ffmpeg (like the browser's
decodeAudioData) decodes it without trimming: 8 815 104 samples at 48 kHz
(183.648 s). Positions are in that timeline at the MP3's own 48 kHz (no
resampling): START = 8 448, END = 8 493 792, X = 3 840, L = 8 485 344
(176.778 s). The page applies no gain, so neither does this script (the
loudness is reported, not matched).

Encoder priming / padding:
- Vorbis: the Ogg granule positions carry the exact sample count; the last
  page's granule must be L and ffmpeg must decode exactly L samples.
- AAC: ffmpeg's encoder writes 1024 priming samples and pads the last packet.
  An AAC stream that starts cold is inexact for its first frames (measured:
  the first 50 ms of the loop came out at -46 dBFS error, a step of -32 dBFS
  at the wrap), so the encoder gets PRE-ROLL first: the loop's own last 2048
  samples, which is what precedes the loop start at every wrap. The MP4 edit
  list is then set to skip the encoder delay and the pre-roll (media_time
  p = 1024 + 2048 = 3072, duration L) and the sample table holds p + L.
  ``LoopMusic`` reads ``AVAudioFile.length`` and picks the offset from
  L / L + r / L + p / L + p + r (r = the last packet's padding, 544); those
  are ``AppDelegate.swift``'s ``LoopMusic.loopFrames`` / ``primingFrames`` /
  ``remainderFrames``, checked here.

Verification (fails the script on any mismatch): decoded lengths, headers,
head / tail RMS difference against the float loop below -40 dBFS, the wrap
of each decoded file against the page's own rendering of the jump (rendered
from the MP3: x[END - w, END) then the crossfade then x[START + X, ...)), no
click at the wrap. Only ffmpeg and the Python standard library.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import pathlib
import re
import struct
import subprocess
import sys

TOOL = pathlib.Path(__file__).resolve().parent
ROOT = TOOL.parent
SRC = TOOL / "music_src" / "Flappy_spikes_remix.mp3"
SRC_SHA256 = "41ca64041ac6a48b5f1e4fdc8f2c88b56af88796908967aaa342b29a8d729d74"
OGG = ROOT / "assets" / "audio" / "FlappySpikesRemix_loopE.ogg"
M4A = ROOT / "ios" / "Runner" / "FlappySpikesRemix_loopE.m4a"
TITLE = "Flappy Spikes remix (loop E)"

SR = 48000
EXPECT_DECODED = 8_815_104
# Option E (remix_loop.html): start 0:00.176, jump at 2:56.954, 80 ms.
START_S, END_S, XF_S = 0.176, 176.954, 0.080
START = round(START_S * SR)  # 8 448
END = round(END_S * SR)  # 8 493 792
X = round(XF_S * SR)  # 3 840
L = END - START  # 8 485 344
EXPECT_L = 8_485_344

ENC_DELAY = 1024  # ffmpeg's AAC encoder delay
PREROLL = 2048  # the loop's own last samples, encoded before its start
PRIMING = ENC_DELAY + PREROLL  # skipped by the edit list (LoopMusic.primingFrames)
FRAME = 1024
PACKETS = math.ceil((L + PRIMING) / FRAME)
REMAINDER = PACKETS * FRAME - L - PRIMING  # LoopMusic.remainderFrames


def check(cond: bool, what: str) -> None:
    if not cond:
        raise SystemExit(f"FAILED: {what}")
    print(f"  ok  {what}")


def decode(path: pathlib.Path, *extra: str):
    """ffmpeg decode of the audio stream to float stereo at SR."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", *extra, "-i", str(path), "-map", "0:a:0",
         "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
        check=True, capture_output=True,
    ).stdout
    a = array.array("f")
    a.frombytes(raw)
    if sys.byteorder != "little":
        a.byteswap()
    return a[0::2], a[1::2]


def db(x: float) -> float:
    return 20 * math.log10(max(x, 1e-12))


def rms_db(a, b) -> float:
    s = sum((x - y) ** 2 for x, y in zip(a, b))
    return db(math.sqrt(s / max(1, len(a))))


def lufs(path: pathlib.Path) -> float:
    err = subprocess.run(
        ["ffmpeg", "-nostats", "-i", str(path), "-map", "0:a:0", "-af", "ebur128",
         "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
    check(bool(m), f"ebur128 loudness of {path.name}")
    return float(m[-1])


def make_loop():
    """The float loop (left, right): one period of the page's playback."""
    print("1. decode", SRC.relative_to(ROOT))
    check(hashlib.sha256(SRC.read_bytes()).hexdigest() == SRC_SHA256,
          "source MP3 sha256 (the approved remix)")
    xl, xr = decode(SRC)
    check(len(xl) == EXPECT_DECODED, f"decoded length {len(xl)} == {EXPECT_DECODED}")
    print("2. option E")
    check(L == EXPECT_L, f"START {START}, END {END}, L = {L} samples "
          f"({L / SR:.6f} s), crossfade X = {X}")
    check(END + X <= len(xl), "the outgoing 80 ms after END exist in the MP3")
    print("3. cut + the page's 80 ms linear crossfade at the seam")
    outs = []
    for x in (xl, xr):
        o = x[START:END]
        for i in range(X):
            g = i / X
            o[i] = x[START + i] * g + x[END + i] * (1 - g)
        outs.append(o)
    check(len(outs[0]) == L, "loop length == L")
    peak = max(max(map(abs, outs[0])), max(map(abs, outs[1])))
    check(peak <= 1.0, f"float loop peak {db(peak):.2f} dBFS <= 0 (no clipping)")
    return (xl, xr), tuple(outs)


def encode(loop, out: pathlib.Path, codec: list[str], preroll: int = 0) -> None:
    """Encodes the loop; with [preroll], the loop's last [preroll] samples
    go first (the wrap's own lead-in, so the codec starts warmed up)."""
    ol, orr = loop
    if preroll:
        ol, orr = ol[L - preroll:] + ol, orr[L - preroll:] + orr
    n = len(ol)
    inter = array.array("f", bytes(8 * n))
    inter[0::2] = ol
    inter[1::2] = orr
    if sys.byteorder != "little":
        inter.byteswap()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
         "-i", "-", *codec, "-metadata", f"title={TITLE}", str(out)],
        input=inter.tobytes(), check=True,
    )


# ---------------------------------------------------------------- OGG

def last_granule(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    i = data.rfind(b"OggS")
    check(i >= 0, "the OGG has pages")
    return int.from_bytes(data[i + 6:i + 14], "little", signed=True), data[i + 5]


def vorbis_info(path: pathlib.Path) -> dict:
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


# ---------------------------------------------------------------- MP4

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
    count = struct.unpack(">I", d[a + 4:a + 8])[0]
    check(count == 1, f"one edit list entry ({count})")
    if d[a] == 1:
        dur, media = struct.unpack(">Qq", d[a + 8:a + 24])
    else:
        dur, media = struct.unpack(">Ii", d[a + 8:a + 16])
    a2, _ = find(d, ["moov", "mvhd"])
    mv_scale = struct.unpack(">I", d[a2 + (20 if d[a2] == 1 else 12):][:4])[0]
    a3, _ = find(d, trak + ["mdia", "mdhd"])
    md_scale = struct.unpack(">I", d[a3 + (20 if d[a3] == 1 else 12):][:4])[0]
    a4, _ = find(d, trak + ["mdia", "minf", "stbl", "stts"])
    n = struct.unpack(">I", d[a4 + 4:a4 + 8])[0]
    samples = packets = 0
    for k in range(n):
        c, delta = struct.unpack(">II", d[a4 + 8 + 8 * k:a4 + 16 + 8 * k])
        samples += c * delta
        packets += c
    return {"movie_timescale": mv_scale, "media_timescale": md_scale,
            "edit_duration_movie": dur, "edit_media_time": media,
            "stts_samples": samples, "packets": packets}


def set_edit(path: pathlib.Path) -> None:
    """Points the MP4's presentation at the loop only: the edit list skips
    the encoder delay AND the pre-roll (media_time = PRIMING, duration = L),
    and the movie / track durations say L. Patched in place (same sizes)."""
    d = bytearray(path.read_bytes())
    trak = ["moov", "trak"]
    a, _ = find(d, trak + ["edts", "elst"])
    check(d[a] == 0, "version 0 edit list")
    dur, media = struct.unpack(">Ii", d[a + 8:a + 16])
    check(media == ENC_DELAY and dur == L + PREROLL,
          f"ffmpeg's edit list: media_time {media}, duration {dur} (= pre-roll + L)")
    struct.pack_into(">Ii", d, a + 8, L, PRIMING)
    for box, off in ((["moov", "mvhd"], 16), (trak + ["tkhd"], 20)):
        b, _ = find(d, box)
        check(d[b] == 0, f"version 0 {box[-1]}")
        struct.pack_into(">I", d, b + off, L)
    path.write_bytes(bytes(d))


def best_lag(dl, cl, lo: int, hi: int, n: int = 8192, at: int = SR) -> int:
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


# ---------------------------------------------------------------- the wrap

def page_wrap(src, w: int):
    """The page's own playback around the jump, rendered from the MP3:
    w samples before the seam, then w samples after it."""
    out = []
    for x in src:
        before = x[END - w:END]
        after = array.array("f", (x[START + i] * (i / X) + x[END + i] * (1 - i / X)
                                  for i in range(X)))
        after += x[START + X:START + w]
        out.append(before + after)
    return out


def max_jump(x, i0: int, i1: int) -> float:
    return max(abs(x[i] - x[i - 1]) for i in range(max(1, i0), min(len(x), i1)))


def check_wrap(dec, ref_wrap, label: str, w: int) -> dict:
    """The decoded file played across its wrap (last w, first w) against the
    page's rendering of the jump."""
    dl, dr = dec
    wl = dl[len(dl) - w:] + dl[:w]
    wr = dr[len(dr) - w:] + dr[:w]
    ms = SR // 1000
    near = slice(w - 50 * ms, w + 50 * ms)
    diff = max(rms_db(wl[near], ref_wrap[0][near]), rms_db(wr[near], ref_wrap[1][near]))
    seam_jump = max(abs(wl[w] - wl[w - 1]), abs(wr[w] - wr[w - 1]))
    jump3 = max(max_jump(wl, w - 3 * ms, w + 3 * ms), max_jump(wr, w - 3 * ms, w + 3 * ms))
    before = max(max_jump(wl, w - 103 * ms, w - 3 * ms), max_jump(wr, w - 103 * ms, w - 3 * ms))
    check(diff < -40, f"{label}: wrap ±50 ms vs the page's jump, RMS diff {diff:.1f} dBFS < -40")
    check(jump3 <= before,
          f"{label}: no click (largest step ±3 ms {db(jump3):.1f} dBFS <= the 100 ms "
          f"before {db(before):.1f} dBFS; at the wrap {db(seam_jump):.1f} dBFS)")
    return {"wrap_rms_diff_vs_page_dbfs": round(diff, 1),
            "step_at_wrap_dbfs": round(db(seam_jump), 1),
            "max_step_3ms_dbfs": round(db(jump3), 1),
            "max_step_100ms_before_dbfs": round(db(before), 1)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--report", help="also write the JSON report to this file")
    args = ap.parse_args()

    src, (ol, orr) = make_loop()
    w = 2 * SR
    ref = page_wrap(src, w)
    cut_wrap = (ol[L - w:] + ol[:w], orr[L - w:] + orr[:w])
    check(all(abs(cut_wrap[c][i] - ref[c][i]) < 1e-6 for c in (0, 1) for i in range(2 * w)),
          "the float loop's wrap == the page's jump, sample for sample")

    print("4. encode OGG Vorbis q6 ->", OGG.relative_to(ROOT))
    encode((ol, orr), OGG, ["-c:a", "libvorbis", "-q:a", "6",
                            "-metadata", "ANDROID_LOOP=true",
                            "-fflags", "+bitexact", "-flags:a", "+bitexact"])
    print("5. encode AAC-LC 192 kbit/s ->", M4A.relative_to(ROOT))
    encode((ol, orr), M4A, ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
                            "-map_metadata", "-1", "-fflags", "+bitexact",
                            "-flags:a", "+bitexact"], preroll=PREROLL)
    set_edit(M4A)

    print("6. verify the OGG")
    granule, flags = last_granule(OGG)
    check(granule == L, f"last Ogg page granule {granule} == L")
    check(flags & 0x04 == 0x04, "last page has the end-of-stream flag")
    info = vorbis_info(OGG)
    check(info["rate"] == SR and info["channels"] == 2,
          f"Vorbis header {info['rate']} Hz, {info['channels']} channels")
    check(any(c.upper() == "ANDROID_LOOP=TRUE" for c in info["comments"]),
          "ANDROID_LOOP=true comment present")
    gl, gr = decode(OGG)
    check(len(gl) == L, f"decoded OGG length {len(gl)} == L")
    ogg_head = max(rms_db(gl[:X], ol[:X]), rms_db(gr[:X], orr[:X]))
    ogg_tail = max(rms_db(gl[-X:], ol[-X:]), rms_db(gr[-X:], orr[-X:]))
    check(ogg_head < -40 and ogg_tail < -40,
          f"first / last {X} samples vs the float loop: {ogg_head:.1f} / {ogg_tail:.1f} dBFS")
    ogg_wrap = check_wrap((gl, gr), ref, "OGG", w)

    print("7. verify the M4A")
    mi = mp4_info(M4A)
    check(mi["media_timescale"] == SR, f"media timescale {mi['media_timescale']} == {SR}")
    check(mi["packets"] == PACKETS, f"{mi['packets']} AAC packets == {PACKETS}")
    check(mi["stts_samples"] == L + PRIMING,
          f"stts {mi['stts_samples']} samples == priming + L ({L + PRIMING})")
    check(mi["edit_media_time"] == PRIMING,
          f"edit list media_time {mi['edit_media_time']} == priming {PRIMING}")
    edit = mi["edit_duration_movie"] * SR / mi["movie_timescale"]
    check(abs(edit - L) < 1, f"edit list duration {edit:.1f} samples == L")
    lengths = sorted({L, L + REMAINDER, L + PRIMING, L + PRIMING + REMAINDER})
    check(len(lengths) == 4, f"LoopMusic's four lengths differ (r = {REMAINDER})")
    ml, mr = decode(M4A)
    check(len(ml) == L, f"decode with the edit list: {len(ml)} samples == L")
    check(all(abs(ml[i] - gl[i]) < 0.05 for i in range(0, L, 104729)),
          "the M4A and the OGG decode to the same loop (spot check)")
    rl, _ = decode(M4A, "-ignore_editlist", "1")
    check(len(rl) in (L + PRIMING, PACKETS * FRAME),
          f"raw decode {len(rl)} == priming + L (or whole packets)")
    lag = best_lag(rl, ol, 0, 4000)
    check(lag == PRIMING, f"raw decode aligns with the loop at {lag} == priming")
    m4a_head = max(rms_db(ml[:X], ol[:X]), rms_db(mr[:X], orr[:X]))
    m4a_tail = max(rms_db(ml[-X:], ol[-X:]), rms_db(mr[-X:], orr[-X:]))
    check(m4a_head < -40 and m4a_tail < -40,
          f"first / last {X} samples vs the float loop: {m4a_head:.1f} / {m4a_tail:.1f} dBFS")
    m4a_wrap = check_wrap((ml, mr), ref, "M4A", w)

    print("8. loudness (no gain applied: the page applies none)")
    lu_src, lu_ogg, lu_m4a = lufs(SRC), lufs(OGG), lufs(M4A)
    check(abs(lu_ogg - lu_src) <= 0.5 and abs(lu_m4a - lu_src) <= 0.5,
          f"loop {lu_ogg:.1f} / {lu_m4a:.1f} LUFS vs MP3 {lu_src:.1f} LUFS (within 0.5 dB)")

    report = {
        "source": str(SRC.relative_to(ROOT)), "sample_rate": SR,
        "start": START, "end": END, "crossfade": X, "L": L,
        "duration_s": round(L / SR, 6),
        "ogg": {"file": str(OGG.relative_to(ROOT)), "size_bytes": OGG.stat().st_size,
                "granule": granule, "head_rms_diff_dbfs": round(ogg_head, 1),
                "tail_rms_diff_dbfs": round(ogg_tail, 1), **ogg_wrap},
        "m4a": {"file": str(M4A.relative_to(ROOT)), "size_bytes": M4A.stat().st_size,
                "priming": PRIMING, "encoder_delay": ENC_DELAY, "preroll": PREROLL,
                "remainder": REMAINDER, "packets": PACKETS,
                "lengths_for_loopmusic": {
                    "edit_list_applied": L, "edit_start_only": L + REMAINDER,
                    "sample_table_only": L + PRIMING,
                    "nothing_applied": L + PRIMING + REMAINDER},
                "head_rms_diff_dbfs": round(m4a_head, 1),
                "tail_rms_diff_dbfs": round(m4a_tail, 1), **m4a_wrap},
        "lufs": {"mp3": lu_src, "ogg": lu_ogg, "m4a": lu_m4a},
    }
    text = json.dumps(report, indent=2)
    print(text)
    if args.report:
        pathlib.Path(args.report).write_text(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
