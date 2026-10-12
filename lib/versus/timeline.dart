import 'dart:convert';
import 'dart:typed_data';

import '../run/config/versus_config.dart';

/// Entry flags of a versus timeline (§3.13, ARCH §6.1; PRD-2.2 §13.5): one
/// byte per entry. Flagged entries are exempt from the server's 0.9 s gap
/// check.
abstract final class PointFlags {
  static const int none = 0;
  static const int ride = 1;
  static const int train = 2;
  static const int gift = 4;

  /// PRD-2.2 §13.6 a coin bonus paid as points (`RunContext.earn`); it can
  /// land right after a pass, so it is gap-exempt too.
  static const int bonus = 8;

  /// PRD-2.2 §13.1 / §13.5 (fix S7-05) the puzzle 4/4 completion payout —
  /// always together with [bonus]; its cap is the doubled 250 roll.
  static const int puzzle = 16;

  /// Flags exempt from the 0.9 s gap check (schema.ts GAP_EXEMPT).
  static const int gapExempt = ride | train | gift | bonus;
}

/// A run's score timeline on `runClock` — **format v2** (PRD-2 §3.13, ARCH
/// §1.13 / §6.1, PRD-2.2 §13.5): one **entry** per score change, each with
/// its time and its **value** (the points it added: 1, 2, the streak, a
/// bonus, …) and its flags.
///
/// Wire format (the rules' 11 `RunEntry` keys are unchanged):
/// - `tl`: base64 of little-endian uint16 centisecond deltas, one per entry
///   (as in v1);
/// - `fl`: base64 of the version byte [version] (2), then per entry the
///   flag byte and the value as a little-endian uint16 (3 bytes per entry);
/// - `end`: centiseconds from the last entry to the death.
///
/// The sum of the values is the score (the server checks it). v1 (one
/// flag byte per point, no values) is **not** read any more: [tryDecode]
/// rejects it (pool runs were converted by `functions/scripts`).
class RunTimeline {
  RunTimeline({
    List<int>? cs,
    List<int>? flags,
    List<int>? values,
    this.endCs = 0,
  }) : cs = cs ?? [],
       flags = flags ?? [],
       values =
           values ?? List.filled((cs ?? const []).length, 1, growable: true);

  factory RunTimeline.empty() => RunTimeline();

  /// PRD-2.2 §13.5 the `fl` version byte of timeline format v2.
  static const int version = 2;

  /// Centisecond deltas, one per entry.
  final List<int> cs;

  /// One flag byte per entry ([PointFlags]).
  final List<int> flags;

  /// The points each entry added (≥ 1).
  final List<int> values;

  /// Centiseconds from the last entry to the end of the run.
  int endCs;

  int _lastCs = 0;

  /// The number of entries.
  int get entries => cs.length;

  /// The total score (sum of the values).
  int get points => values.fold(0, (a, b) => a + b);

  static const int _maxDelta = 0xFFFF;
  static const int _maxValue = 0xFFFF;

  static int _toCs(double seconds) => (seconds * 100).round();

  /// Records one entry of [value] points scored at [runClock] seconds.
  void addEntry(double runClock, int value, {int flag = PointFlags.none}) {
    if (value <= 0) return;
    final now = _toCs(runClock);
    final delta = (now - _lastCs).clamp(0, _maxDelta);
    cs.add(delta);
    flags.add(flag & 0xFF);
    values.add(value.clamp(1, _maxValue));
    _lastCs = _lastCs + delta;
  }

  /// One point at [runClock] (an entry of value 1).
  void addPoint(double runClock, {int flag = PointFlags.none}) =>
      addEntry(runClock, 1, flag: flag);

  /// Marks the end of the run at [runClock] seconds.
  void end(double runClock) {
    endCs = (_toCs(runClock) - _lastCs).clamp(0, _maxDelta);
  }

  /// Total run length in seconds.
  double get lengthSeconds {
    var t = endCs;
    for (final d in cs) {
      t += d;
    }
    return t / 100;
  }

  String encodeTl() {
    final b = ByteData(cs.length * 2);
    for (var i = 0; i < cs.length; i++) {
      b.setUint16(i * 2, cs[i], Endian.little);
    }
    return base64Encode(b.buffer.asUint8List());
  }

  /// `fl` v2: the version byte, then (flag, value lo, value hi) per entry.
  String encodeFlags() {
    final b = ByteData(1 + cs.length * 3);
    b.setUint8(0, version);
    for (var i = 0; i < cs.length; i++) {
      b.setUint8(1 + i * 3, flags[i] & 0xFF);
      b.setUint16(2 + i * 3, values[i], Endian.little);
    }
    return base64Encode(b.buffer.asUint8List());
  }

  /// Decodes a v2 timeline; null for v1 or a malformed one.
  static RunTimeline? tryDecode(String tl, String fl, int end) {
    try {
      final bytes = base64Decode(tl);
      if (bytes.length.isOdd) return null;
      final view = ByteData.sublistView(bytes);
      final cs = [
        for (var i = 0; i + 1 < bytes.length; i += 2)
          view.getUint16(i, Endian.little),
      ];
      final f = base64Decode(fl);
      if (f.length != 1 + cs.length * 3 || f[0] != version) return null;
      final fv = ByteData.sublistView(f);
      final flags = <int>[];
      final values = <int>[];
      for (var i = 0; i < cs.length; i++) {
        flags.add(f[1 + i * 3]);
        final v = fv.getUint16(2 + i * 3, Endian.little);
        if (v < 1) return null;
        values.add(v);
      }
      final t = RunTimeline(cs: cs, flags: flags, values: values, endCs: end);
      t._lastCs = cs.fold(0, (a, b) => a + b);
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Decodes a v2 timeline (an empty one for v1 / malformed data).
  static RunTimeline decode(String tl, String fl, int end) =>
      tryDecode(tl, fl, end) ?? RunTimeline(endCs: end);

  /// The score at [runClock] seconds (values of the entries whose time is
  /// ≤ it).
  int scoreAt(double runClock) {
    final now = _toCs(runClock);
    var t = 0;
    var n = 0;
    for (var i = 0; i < cs.length; i++) {
      t += cs[i];
      if (t > now) break;
      n += values[i];
    }
    return n;
  }

  /// PRD-2.2 §13.5 the server's timeline rules (`functions/src/timeline.ts`
  /// `plausibleValues` + `gapOk`), mirrored for the shared fixtures: `count`
  /// when an entry's value is above its cap, `gap` when a plain entry comes
  /// under 0.9 s after the previous entry that is not a bonus (fix S7-02: a
  /// bonus does not restart the interval), else null.
  String? check() {
    var passes = 0;
    for (var i = 0; i < values.length; i++) {
      final f = flags[i], v = values[i];
      if (f & PointFlags.bonus != 0) {
        final cap = f & PointFlags.puzzle != 0
            ? VersusConfig.puzzleBonusCap
            : VersusConfig.bonusCap;
        if (v > cap) return 'count';
      } else if (f & PointFlags.gift != 0) {
        if (v > VersusConfig.giftCap) return 'count';
      } else {
        passes++;
        if (v >
            VersusConfig.passCapMult * (passes + VersusConfig.passCapExtra)) {
          return 'count';
        }
      }
    }
    var t = 0;
    int? anchor;
    for (var i = 0; i < cs.length; i++) {
      t += cs[i];
      final f = flags[i];
      if (f & PointFlags.gapExempt == 0 &&
          anchor != null &&
          t - anchor < VersusConfig.minGapCs) {
        return 'gap';
      }
      if (f & PointFlags.bonus == 0) anchor = t;
    }
    return null;
  }

  /// True once [runClock] is past the end of this timeline.
  bool outAt(double runClock) =>
      _toCs(runClock) > _lastCs + endCs && (cs.isNotEmpty || endCs > 0);
}
