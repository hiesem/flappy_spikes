#!/usr/bin/env python3
"""PRD-2.3 §16.3 step 8 / §16.6: the music loop seam check.

Only ffmpeg and the Python standard library (like the other tool/ scripts).

Two uses:

1. ``tool/make_music_loop.py`` imports :func:`check_file_seam` (step 8) to
   verify the generated OGG against the float cut it was made from.

2. A recording of the phone's own audio (scrcpy ``--audio-source=playback``,
   §16.6) is checked wrap by wrap:

       python3 -I tool/loop_seam_check.py music.wav \
           [--ref assets/audio/HappyBeat_loop_56bars.ogg] [--json out.json]

   For every wrap found in the recording it reports
   - ``offset_ms``: where the loop's new start lands against the 146 BPM grid
     continued from the loop end (target within ±5 ms; a player that adds a
     gap shows the gap here, since the next downbeat comes that much late);
   - ``extra_silence_ms``: the silence at the seam beyond the file's own
     lead-in before its first downbeat (target under 10 ms; see the note
     below);
   - ``click``: a neighbouring-sample jump above −20 dBFS within ±3 ms of the
     seam that is also larger than every jump in the 100 ms of music before it.

The maths (shared by both uses):
- the grid: 146 BPM, 1 bar = 240/146 s, the loop = 56 bars =
  ``round(56 × 240/146 × 44100)`` = 4 059 616 samples;
- silence: both channels below −50 dBFS (|x| ≤ 0.0031623);
- onset: the first sample after a silence where either channel is above
  −50 dBFS.

Note (build-run call, docs/p23/MUSIC.md): the approved cut (version 3 of
design/music_v23/loop_test.html) begins with the MP3's own lead-in, 1 012
samples (22.9 ms) of digital silence before the first downbeat, because the
MP3 ends 1 012 samples before bar 56 is complete. That silence is part of the
approved music, so the "no silence of 10 ms or more" rule is checked as
silence *beyond* the reference cut's own silence at the seam.
"""

from __future__ import annotations

import argparse
import array
import json
import math
import pathlib
import subprocess
import sys

SR = 44100
BPM = 146
BAR_S = 240 / BPM
BARS = 56
LOOP = round(BARS * BAR_S * SR)  # 4 059 616
LOOP_EXACT = BARS * BAR_S * SR  # 4 059 616.4
TH = 10 ** (-50 / 20)  # −50 dBFS
CLICK_TH = 10 ** (-20 / 20)  # −20 dBFS
MS = SR / 1000


def decode(path: str | pathlib.Path, sr: int = SR) -> tuple[array.array, array.array]:
    """Decodes [path] with ffmpeg to float stereo at [sr]: (left, right)."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2",
         "-ar", str(sr), "-"],
        check=True, capture_output=True,
    ).stdout
    a = array.array("f")
    a.frombytes(raw)
    if sys.byteorder != "little":
        a.byteswap()
    return a[0::2], a[1::2]


def peak(l, r, i: int) -> float:
    return max(abs(l[i]), abs(r[i]))


def silence_runs(l, r, i0: int, i1: int, th: float = TH) -> list[tuple[int, int]]:
    """Runs [a, b) inside [i0, i1) where both channels are at or below [th]."""
    runs = []
    a = None
    for i in range(max(0, i0), min(len(l), i1)):
        quiet = abs(l[i]) <= th and abs(r[i]) <= th
        if quiet and a is None:
            a = i
        elif not quiet and a is not None:
            runs.append((a, i))
            a = None
    if a is not None:
        runs.append((a, min(len(l), i1)))
    return runs


def longest_silence(l, r, i0: int, i1: int, th: float = TH) -> int:
    return max((b - a for a, b in silence_runs(l, r, i0, i1, th)), default=0)


def onset_after(l, r, i0: int, th: float = TH) -> int:
    """The first sample at or after [i0] above [th] (−1 when none)."""
    for i in range(max(0, i0), len(l)):
        if abs(l[i]) > th or abs(r[i]) > th:
            return i
    return -1


def max_jump(l, r, i0: int, i1: int) -> float:
    m = 0.0
    for i in range(max(1, i0), min(len(l), i1)):
        m = max(m, abs(l[i] - l[i - 1]), abs(r[i] - r[i - 1]))
    return m


def click_at(l, r, seam: int) -> tuple[bool, float]:
    """A jump above −20 dBFS within ±3 ms of [seam] that beats every jump in
    the 100 ms of music before it. Returns (click, jump dBFS)."""
    near = max_jump(l, r, seam - round(3 * MS), seam + round(3 * MS))
    before = max_jump(l, r, seam - round(103 * MS), seam - round(3 * MS))
    return near > CLICK_TH and near > before, 20 * math.log10(max(near, 1e-9))


def db(x: float) -> float:
    return 20 * math.log10(max(x, 1e-12))


def check_file_seam(ogg: tuple, cut: tuple, *, window_s: float = 2.0) -> dict:
    """§16.3 step 8 seam check of the decoded loop [ogg] (left, right) against
    the float [cut] it was encoded from. The wrap is played back to back:
    the last [window_s] then the first [window_s]."""
    ol, orr = ogg
    cl, cr = cut
    n = len(ol)
    w = round(window_s * SR)
    # Seam signal: … end of the loop | start of the loop …
    sl = ol[n - w:] + ol[:w]
    sr_ = orr[n - w:] + orr[:w]
    rl = cl[n - w:] + cl[:w]
    rr = cr[n - w:] + cr[:w]
    seam = w
    # The grid: the loop's first downbeat in the float cut is its anchor
    # (bar 1); bar 57 = the downbeat after the wrap lies 56 bars later.
    down0 = onset_after(cl, cr, 0)
    expected = seam + (down0 + LOOP_EXACT - LOOP)  # + 0.4 samples
    found = onset_after(sl, sr_, seam)
    offset_ms = (found - expected) / MS
    win = (seam - round(50 * MS), seam + round(50 * MS))
    sil = longest_silence(sl, sr_, *win)
    sil_ref = longest_silence(rl, rr, *win)
    click, jump_db = click_at(sl, sr_, seam)
    return {
        "first_downbeat_in_cut": down0,
        "downbeat_offset_ms": round(offset_ms, 3),
        "silence_at_seam_ms": round(sil / MS, 2),
        "silence_in_cut_ms": round(sil_ref / MS, 2),
        "extra_silence_ms": round((sil - sil_ref) / MS, 2),
        "click": click,
        "seam_jump_dbfs": round(jump_db, 1),
        "pass": abs(offset_ms) <= 2.0 and (sil - sil_ref) / MS < 10 and not click,
    }


# ---------------------------------------------------------------- recordings

def _ncc(a: list[float], b: list[float], off: int) -> float:
    """Normalised correlation of [a] with [b][off:off+len(a)]."""
    n = len(a)
    seg = b[off:off + n]
    if len(seg) < n:
        return -1.0
    ma = sum(a) / n
    mb = sum(seg) / n
    num = da = dbb = 0.0
    for x, y in zip(a, seg):
        x -= ma
        y -= mb
        num += x * y
        da += x * x
        dbb += y * y
    if da <= 0 or dbb <= 0:
        return -1.0
    return num / math.sqrt(da * dbb)


def _refine(ref_m: list[float], rec_m: list[float], ref_at: int, rec_guess: int,
            span: int, n: int) -> tuple[int, float]:
    """Sample-exact position in the recording of reference sample [ref_at]:
    maximises the correlation of [n] samples within ±[span] of [rec_guess].
    Returns (position, correlation)."""
    pat = ref_m[ref_at:ref_at + n]
    best, at = -2.0, rec_guess
    for off in range(max(0, rec_guess - span), rec_guess + span + 1):
        c = _ncc(pat, rec_m, off)
        if c > best:
            best, at = c, off
    return at, best


def _rms(x) -> float:
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def check_recording(rec_path: str, ref_path: str) -> dict:
    """§16.6: every wrap of the loop [ref_path] found in the recording.

    The loop starts with the only silence of 10 ms or more in the song (its
    23 ms lead-in), so every such silence in the recording is a candidate
    seam. It is a wrap when the audio before it is the loop's end and the
    audio after it the loop's start (sample-exact correlation ≥ 0.9); a pause
    (an ad, the background) is any other silence."""
    rl, rr = decode(rec_path)
    fl, fr = decode(ref_path)
    n_ref = len(fl)
    rec_m = [(a + b) * 0.5 for a, b in zip(rl, rr)]
    ref_m = [(a + b) * 0.5 for a, b in zip(fl, fr)]
    # Gain of the recording against the file (music volume, duck): the
    # silence threshold scales with it. Measured over the loud part.
    loud = [abs(v) for v in rec_m if abs(v) > 1e-4]
    g = _rms(loud) / max(1e-9, _rms(ref_m)) if loud else 0.0
    th = TH * max(g, 1e-3)
    down0 = onset_after(fl, fr, 0)
    head_sil = down0  # the file's own silence at the start of the loop
    tail_sil = 0
    while tail_sil < n_ref and abs(fl[n_ref - 1 - tail_sil]) <= TH and abs(fr[n_ref - 1 - tail_sil]) <= TH:
        tail_sil += 1
    n = round(0.25 * SR)
    span = round(15 * MS)
    holes = [h for h in silence_runs(rl, rr, 0, len(rl), th) if h[1] - h[0] >= round(10 * MS)]
    wraps, pauses = [], []
    for h0, h1 in holes:
        if h0 < n or h1 + n > len(rl):
            continue
        a, ca = _refine(ref_m, rec_m, n_ref - n, h0 + tail_sil - n, span, n)
        b, cb = _refine(ref_m, rec_m, 0, h1 - head_sil, span, n)
        if ca < 0.9 or cb < 0.9:
            pauses.append({"t_s": round(h0 / SR, 3), "silence_ms": round((h1 - h0) / MS, 1),
                           "match_end": round(ca, 3), "match_start": round(cb, 3)})
            continue
        loop_end = a + n  # where the old loop ended (recording samples)
        loop_start = b  # where the new loop starts
        offset_ms = (loop_start - loop_end - (LOOP_EXACT - LOOP)) / MS
        sil = h1 - h0
        sil_ref = head_sil + tail_sil
        click, jdb = click_at(rl, rr, loop_start)
        wraps.append({
            "t_s": round(loop_end / SR, 3),
            "match": round(min(ca, cb), 3),
            "offset_ms": round(offset_ms, 2),
            "silence_ms": round(sil / MS, 2),
            "extra_silence_ms": round((sil - sil_ref) / MS, 2),
            "click": click,
            "seam_jump_dbfs": round(jdb, 1),
            "pass": abs(offset_ms) <= 5 and (sil - sil_ref) / MS < 10 and not click,
        })
    return {
        "recording": rec_path,
        "seconds": round(len(rl) / SR, 1),
        "gain_db": round(db(g), 1),
        "peak_dbfs": round(db(max(max(map(abs, rl), default=0), max(map(abs, rr), default=0))), 1),
        "wraps": wraps,
        "pauses": pauses,
        "pass": bool(wraps) and all(w["pass"] for w in wraps),
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("recording")
    p.add_argument("--ref", default=str(pathlib.Path(__file__).resolve().parent.parent
                                        / "assets" / "audio" / "HappyBeat_loop_56bars.ogg"))
    p.add_argument("--json")
    a = p.parse_args()
    res = check_recording(a.recording, a.ref)
    print(f"{res['recording']}: {res['seconds']} s, peak {res['peak_dbfs']} dBFS, "
          f"gain {res['gain_db']} dB, {len(res['wraps'])} wraps, "
          f"{len(res['pauses'])} other silences")
    for q in res["pauses"]:
        print(f"  silence at {q['t_s']:8.3f} s, {q['silence_ms']} ms (not a wrap)")
    for i, w in enumerate(res["wraps"], 1):
        print(f"  wrap {i} at {w['t_s']:8.3f} s  match {w['match']:.2f}  "
              f"offset {w['offset_ms']:+7.2f} ms  silence {w['silence_ms']:6.2f} ms "
              f"(extra {w['extra_silence_ms']:+6.2f})  click {w['click']}  "
              f"{'PASS' if w['pass'] else 'FAIL'}")
    print("RESULT:", "PASS" if res["pass"] else "FAIL")
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(res, indent=2))
    return 0 if res["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
