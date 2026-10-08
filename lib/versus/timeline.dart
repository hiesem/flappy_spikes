import 'dart:convert';
import 'dart:typed_data';

/// Point flags of a versus timeline entry (§3.13, ARCH §6.1): one byte per
/// point. Flagged points are exempt from the server's 0.9 s gap check.
abstract final class PointFlags {
  static const int none = 0;
  static const int ride = 1;
  static const int train = 2;
  static const int gift = 4;
}

/// A run's score timeline on `runClock` (PRD-2 §3.13, ARCH §1.13 / §6.1):
/// one entry per point as a uint16 centisecond delta from the previous point
/// (base64, little endian), one flag byte per point, and [endCs] from the
/// last point to the death.
///
/// The codec lives in WP-0b so the recorder contract is fixed early; the
/// recorder itself is WP-5b.
class RunTimeline {
  RunTimeline({List<int>? cs, List<int>? flags, this.endCs = 0})
    : cs = cs ?? [],
      flags = flags ?? [];

  factory RunTimeline.empty() => RunTimeline();

  /// Centisecond deltas, one per point.
  final List<int> cs;

  /// One flag byte per point ([PointFlags]).
  final List<int> flags;

  /// Centiseconds from the last point to the end of the run.
  int endCs;

  int _lastCs = 0;

  int get points => cs.length;

  static const int _maxDelta = 0xFFFF;

  static int _toCs(double seconds) => (seconds * 100).round();

  /// Records one point scored at [runClock] seconds.
  void addPoint(double runClock, {int flag = PointFlags.none}) {
    final now = _toCs(runClock);
    final delta = (now - _lastCs).clamp(0, _maxDelta);
    cs.add(delta);
    flags.add(flag & 0xFF);
    _lastCs = _lastCs + delta;
  }

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

  String encodeFlags() => base64Encode(Uint8List.fromList(flags));

  static RunTimeline decode(String tl, String fl, int end) {
    final bytes = base64Decode(tl);
    final view = ByteData.sublistView(bytes);
    final cs = [
      for (var i = 0; i + 1 < bytes.length; i += 2)
        view.getUint16(i, Endian.little),
    ];
    final flags = base64Decode(fl).toList();
    final t = RunTimeline(cs: cs, flags: flags, endCs: end);
    t._lastCs = cs.fold(0, (a, b) => a + b);
    return t;
  }

  /// The score at [runClock] seconds (points whose time is ≤ it).
  int scoreAt(double runClock) {
    final now = _toCs(runClock);
    var t = 0;
    var n = 0;
    for (final d in cs) {
      t += d;
      if (t > now) break;
      n++;
    }
    return n;
  }

  /// True once [runClock] is past the end of this timeline.
  bool outAt(double runClock) =>
      _toCs(runClock) > _lastCs + endCs && (cs.isNotEmpty || endCs > 0);
}
