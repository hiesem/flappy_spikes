import 'dart:ui';

import '../../game/sound.dart';
import '../director/plans.dart' show SwitchDesign;

/// Rings with an on/off switch — Lockdown, Laser Gate, Power Iris, Snoozer,
/// Gift Wrap (PRD-2 §3.20, §5.19; mock `screen_switch_rings.html`, builder
/// `build62.py`). The placement knobs (lead 1.0 s × scroll ≥ 150 pt,
/// offset 70–100 pt, ≤ 110 pt from the previous hoop) live in `RunConfig`
/// (the director places the switch). Every member's doc starts with its
/// PRD section (ARCH §4).
abstract final class SwitchConfig {
  /// §3.20 Touching the switch gives this many coins ("+1 ●", Q53).
  static const int coins = 1;

  /// §3.20 Every design's open animation ends within this time (s).
  static const double openMax = .8;

  /// §5.19 Switch pickups bob ±4 pt at 0.6 Hz.
  static const double bob = 4, bobHz = .6;

  /// §5.19 A white / pale-gold twinkle every ≈ 0.28 s.
  static const double twinkleEvery = .28;

  /// §5.19 The Laser button / Iris lever stay this long after the touch to
  /// show their ON state (s), then fade out over [fade] at scale ×1.4.
  static double stay(SwitchDesign d) => switch (d) {
    SwitchDesign.laserGate => .3,
    SwitchDesign.powerIris => 1.1,
    _ => 0,
  };

  /// §5.19 Fade of a touched switch (s) and its end scale.
  static const double fade = .35, fadeScale = 1.4;

  /// §5.19 Open word: Opificio 19 pt, white 5 pt outline, rises 1.1 s.
  static const double wordSize = 19, wordOutline = 5, wordLife = 1.1;

  /// §5.19 Crash banner colour (red, the design's word).
  static const Color crashRed = Color(0xFFFF3B5C);

  static const Color green = Color(0xFF21C46B);
  static const Color gold = Color(0xFFFFB529);
  static const Color goldDark = Color(0xFFD48A00);
  static const Color red = Color(0xFFFF3B5C);
  static const Color plum = Color(0xFF7A0044);
  static const Color pink = Color(0xFFEC008C);
  static const Color pinkBack = Color(0xFFB0006B);

  /// §5.19 The crash word of each design (red banner).
  static String crashWord(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => 'LOCKED!',
    SwitchDesign.laserGate => 'ZAPPED!',
    SwitchDesign.powerIris => 'SHUT!',
    SwitchDesign.snoozer => 'HMPF!',
    SwitchDesign.giftWrap => 'WRAPPED!',
  };

  /// §5.19 The open word and its colour (Lockdown uses its sign instead).
  static (String, Color)? openWord(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => null,
    SwitchDesign.laserGate => ('POWER OFF', green),
    SwitchDesign.powerIris => ('POWER ON', gold),
    SwitchDesign.snoozer => ('WAKE UP!', Color(0xFF8E44FF)),
    SwitchDesign.giftWrap => ('SNIP!', pink),
  };

  /// §5.19 The moment (s after the touch) the ring reads open: Lockdown
  /// unlock 0.5, Laser power-down 0.12 (+0.4 retract), Iris spins open
  /// 0.5–0.8, Snoozer yawns 0.38–0.73, Gift Wrap cut 0.5 (+0.3 tear).
  static double openAt(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => .5,
    SwitchDesign.laserGate => .12,
    SwitchDesign.powerIris => .5,
    SwitchDesign.snoozer => .38,
    SwitchDesign.giftWrap => .5,
  };

  /// §5.19 The open animation's end (s after the touch, ≤ [openMax]).
  static double openDone(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => .8,
    SwitchDesign.laserGate => .52,
    SwitchDesign.powerIris => .8,
    SwitchDesign.snoozer => .78,
    SwitchDesign.giftWrap => .8,
  };

  /// §5.19 Sounds: switch touched / opening / crash.
  static Sfx touchSound(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => Sfx.swLockTouch,
    SwitchDesign.laserGate => Sfx.swLaserTouch,
    SwitchDesign.powerIris => Sfx.swIrisTouch,
    SwitchDesign.snoozer => Sfx.swSnoozeTouch,
    SwitchDesign.giftWrap => Sfx.swGiftTouch,
  };

  static Sfx openSound(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => Sfx.swLockOpen,
    SwitchDesign.laserGate => Sfx.swLaserOpen,
    SwitchDesign.powerIris => Sfx.swIrisOpen,
    SwitchDesign.snoozer => Sfx.swSnoozeOpen,
    SwitchDesign.giftWrap => Sfx.swGiftOpen,
  };

  /// §5.19 When the opening sound starts (s after the touch): the lock
  /// click at 0.35, the laser power-down at 0.12, the iris zip at 0.1, the
  /// yawn at 0.38, the snips at 0.3 (each file carries the "clear" chord).
  static double openSoundAt(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => .35,
    SwitchDesign.laserGate => .12,
    SwitchDesign.powerIris => .1,
    SwitchDesign.snoozer => .38,
    SwitchDesign.giftWrap => .3,
  };

  static Sfx crashSound(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => Sfx.swLockCrash,
    SwitchDesign.laserGate => Sfx.swLaserCrash,
    SwitchDesign.powerIris => Sfx.swIrisCrash,
    SwitchDesign.snoozer => Sfx.swSnoozeCrash,
    SwitchDesign.giftWrap => Sfx.swGiftCrash,
  };

  /// §5.19 The design's colour (halo, cable glow).
  static Color halo(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => Color(0xFFFFD54A),
    SwitchDesign.laserGate => red,
    SwitchDesign.powerIris => Color(0xFFFFD54A),
    SwitchDesign.snoozer => red,
    SwitchDesign.giftWrap => Color(0xFFFF4FB7),
  };

  /// §5.19 Lockdown chains: X from (−25, −52) to (+25, +38), 13 links each.
  static const int chainLinks = 13;

  /// §5.19 Lockdown sign 34 pt above the ring (80 × 24 plate).
  static const double signAbove = 34;

  /// §5.19 Snoozer: "z" letters per second.
  static const double zzzRate = 1.6;

  /// §5.19 Gift Wrap confetti squares at the cut.
  static const int giftConfetti = 34;

  /// §5.19 Lockdown: chain links that burst off at the unlock.
  static const int lockLinks = 26;
}
