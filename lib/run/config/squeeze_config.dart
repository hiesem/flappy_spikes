import 'dart:math' as math;
import 'dart:ui';

import 'run_config.dart';

/// Spike squeeze (PRD-2 §3.17, §5.16; mock `screen_squeeze.html`, builder
/// `build56.py`). The schedule knobs (60–120 s, hold 10–20 s, the 3 s
/// window lead) live in [RunConfig] (WP-0b, the director rolls them).
/// Every member's doc starts with its PRD section.
abstract final class SqueezeConfig {
  // ----------------------------------------------------------- how far
  /// §3.17 Open space left (of the screen height) for squeeze 1, 2, 3 and
  /// 4+ (the last entry is the limit).
  static const List<double> openFractions = [.5, .45, .4, .35];

  /// §3.17 The open space between the tooth tips is never smaller (pt).
  static const double minOpen = 230;

  /// §3.17 Open space (pt between the tooth tips) of squeeze [index]
  /// (0-based) on a [viewHeight] pt screen.
  static double openFor(int index, double viewHeight) {
    final f = openFractions[math.min(index, openFractions.length - 1)];
    return math.max(minOpen, f * viewHeight);
  }

  /// §3.17 How far each wall moves in (pt): (band − open space) / 2, with
  /// the band between the un-squeezed tooth tips (44 pt strips: 623 pt at
  /// 711, 480 at 568). 134 / 152 / 170 / 187 at 711; 98 / 112 / 125 / 125
  /// at 568.
  static double insetFor(
    int index,
    double viewHeight, {
    double stripHeight = RunConfig.stripHeight,
  }) {
    final band = viewHeight - 2 * stripHeight;
    return math.max(0, (band - openFor(index, viewHeight)) / 2);
  }

  /// §3.17 A squeeze due during a ride / revive waits until it ends + this
  /// many seconds of runClock.
  static const double waitAfter = 2;

  // ----------------------------------------------------------- phases
  /// §3.17 Warning (shake build-up, red teeth, falling bits; no text) (s).
  static const double warning = 1.5;

  /// §3.17 Closing slide, ease-in-out (s).
  static const double closing = 3;

  /// §3.17 Opening slide, ease-in-out (s).
  static const double opening = 3;

  /// §3.17 The last this many seconds of the hold tick once per second.
  static const int lastTicks = 3;

  /// §3.17 / §5.16 ease-in-out of the slides (the mock's quadratic).
  static double ease(double u) {
    final x = u.clamp(0.0, 1.0);
    return x < .5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;
  }

  // ----------------------------------------------------------- shake
  /// §3.17 Warning shake builds up 0 → this (pt) …
  static const double warnShake = 2.6;

  /// §3.17 … over this many seconds (mock).
  static const double warnShakeRamp = .6;

  /// §3.17 Closing shake (pt).
  static const double closeShake = 2.2;

  /// §3.17 (DEVIATION 2.5.1) Lock thump: a vertical-only damped bounce of
  /// at most this many pt, the world moving down first (was a random 6 pt
  /// both-axes punch, which read as the spikes shifting sideways) …
  static const double lockThump = 3;

  /// §3.17 … ending (exactly 0) after this many seconds …
  static const double lockThumpTime = .3;

  /// §3.17 … bouncing at this frequency (Hz).
  static const double lockThumpFreq = 7;

  /// PRD 2.5.1 WP-SND: the squeeze cues are preloaded this many seconds of
  /// runClock before the warning can start (and the late hold cues this
  /// long before the first tick).
  static const double preloadLead = 3;

  /// §3.17 Opening shake (pt) at the start …
  static const double openShake = 1.4;

  /// §3.17 … decaying over this many seconds.
  static const double openShakeTime = .8;

  /// §3.17 Hold tick tremble: amplitude (pt) of the short wall tremble
  /// (mock: 0.18 s × 8) …
  static const double tickTremble = 1.44;

  /// §3.17 … decaying over this many seconds.
  static const double tickTrembleTime = .18;

  // ----------------------------------------------------------- flash
  /// §5.16 Warning flash colour of the teeth.
  static const Color flashColor = Color(0xFFFF3B5C);

  /// §5.16 The flash pulses every this many seconds.
  static const double flashPeriod = .5;

  /// §5.16 Peak blend toward [flashColor] (mock 0.85).
  static const double flashPeak = .85;

  /// §5.16 The flash runs into the first this many seconds of closing.
  static const double flashIntoClosing = .4;

  /// §5.16 Teeth flash blend at [t] s after the warning started (0..1):
  /// one sine pulse per [flashPeriod] (call: the mock's `max(0, sin)` only
  /// pulses every other half second and is dark in the first 0.4 s of
  /// closing; the PRD text — a pulse every 0.5 s, into the closing — wins).
  static double flashAt(double t) {
    if (t < 0 || t >= warning + flashIntoClosing) return 0;
    return math.sin(t / flashPeriod * math.pi).abs() * flashPeak;
  }

  // ----------------------------------------------------------- bits
  /// §5.16 Falling bits per second (warning, closing, opening).
  static const double bitsPerSecond = 28;

  /// §5.16 Bit size range (pt).
  static const double bitMin = 2, bitMax = 5;

  /// §5.16 Bits fade over this many seconds.
  static const double bitLife = .7;

  /// §5.16 Bit fall speed range away from the tooth line (pt/s, mock).
  static const double bitSpeedMin = 40, bitSpeedMax = 100;

  /// §5.16 Bit sideways speed (± pt/s, mock).
  static const double bitDrift = 10;

  /// §5.16 Bit start opacity (mock 0.9).
  static const double bitAlpha = .9;

  /// §5.16 Lock dust: this many squares from both tooth lines.
  static const int dustCount = 40;

  /// §5.16 Dust size range (pt).
  static const double dustMin = 3, dustMax = 7;

  /// §5.16 Dust life range (s, mock 0.6–1.0).
  static const double dustLifeMin = .6, dustLifeMax = 1;

  /// §5.16 Dust speed away from the line (pt/s) and sideways (± pt/s).
  static const double dustSpeedMin = 20, dustSpeedMax = 100, dustDrift = 40;

  /// §5.16 Dust is the wall grey this much darker (mix toward black).
  static const double dustDarken = .15;

  /// §5.16 Dust start opacity (mock 0.8).
  static const double dustAlpha = .8;

  /// §5.16 Particle pool capacity of the bits and dust.
  static const int poolCapacity = 120;

  // ----------------------------------------------------------- HUD
  /// §3.17 The score circle crossfades to white over the first this many pt
  /// of a wall covering it (mock: 30).
  static const double coverRamp = 30;

  // ----------------------------------------------------------- sound
  /// §5.16 Volume of the `sq_hold` loop (mock 0.6).
  static const double holdVolume = .6;
}
