import 'dart:ui';

/// Golden feather + feather tray knobs (PRD-2 §3.15, §5.14; mock engine
/// `design/menu_v2/collect.js`, design `feather`). Times in seconds, sizes
/// in pt, angles in radians.
abstract final class FeatherConfig {
  /// §3.15 Feathers held at most (the set that unlocks the bonus screen).
  static const int maxHeld = 3;

  // ------------------------------------------------------------- art
  /// §5.14 Vane `#FFB529`.
  static const Color vane = Color(0xFFFFB529);

  /// §5.14 The vane's right half `#F09A0A`.
  static const Color vaneRight = Color(0xFFF09A0A);

  /// §5.14 Pink `#EC008C` quill.
  static const Color quill = Color(0xFFEC008C);

  /// §5.14 Pale gold `#FFD54A` (twinkles, sparkles).
  static const Color paleGold = Color(0xFFFFD54A);

  /// §5.14 White outline (pt, each side of the shape).
  static const double outline = 2;

  // ------------------------------------------------------------- pickup
  /// §5.14 Pickup scale (≈ 20 × 44 pt incl. the quill) and tilt (20°).
  static const double pickupScale = 1.05;
  static const double pickupTilt = .35;

  /// §5.14 Idle bob ±4 pt at 0.6 Hz.
  static const double bob = 4;
  static const double bobHz = .6;

  /// §5.14 Idle scale pulse ±6 % at 1 Hz.
  static const double pulse = .06;
  static const double pulseHz = 1;

  /// §5.14 Idle sway ±13° (0.22 rad) at 0.7 Hz, plus ±3 pt side drift.
  static const double sway = .22;
  static const double swayHz = .7;
  static const double drift = 3;

  /// §5.14 A twinkle every 0.28 s on a 24 pt radius (size 4–7 pt, 0.6 s).
  static const double twinkleEvery = .28;
  static const double twinkleRadius = 24;
  static const double twinkleMin = 4;
  static const double twinkleMax = 7;
  static const double twinkleLife = .6;

  // ------------------------------------------------------------- tray
  /// §5.14 Tray: 132 × 48 panel, `fg` 18 % over bg.
  static const double trayWidth = 132;
  static const double trayHeight = 48;
  static const double panelMix = .18;

  /// §5.14 Three 36 pt slots (`fg` 30 %) at x −42 / 0 / +42.
  static const double slotSize = 36;
  static const double slotStep = 42;
  static const double slotMix = .30;

  /// §5.14 Empty slot: feather silhouette in `fg` 32 %.
  static const double ghostMix = .32;

  /// §5.14 A feather in its slot: scale 0.82, turned 26° (0.45 rad); the
  /// held ones keep a 1.6 pt outline.
  static const double slotScale = .82;
  static const double slotTilt = .45;
  static const double slotOutline = 1.6;

  /// §5.14 The flight lands 0.14 s (swell) + 0.62 s (fly) after the touch.
  static const double landAt = .14 + .62;

  /// §5.14 Landing: slot punch up to ×1.38 over 0.35 s.
  static const double punch = .38;
  static const double punchLength = .35;

  /// §5.14 Landing ring 6 → 28 pt (2.5 pt, 0.4 s) and 6 sparkles.
  static const double landRingFrom = 6;
  static const double landRingTo = 28;

  /// §5.14 The tray fades out (0.3 s) ≈ 2.15 s after the touch; 3.4 s with
  /// the 3rd feather.
  static const double fadeAt = 2.15;
  static const double fadeAtComplete = 3.4;

  /// §5.14 3rd feather: 0.24 s after landing — gold flash, bounces 0.09 s
  /// apart, 26 confetti squares, gold ring 20 → 90 pt.
  static const double completeDelay = .24;
  static const double bounceGap = .09;
  static const int confetti = 26;
  static const double completeRingFrom = 20;
  static const double completeRingTo = 90;

  /// §5.14 / Q38 The sticker copy, popping in 0.15 s after the flash, 24 pt
  /// under the tray's bottom edge.
  static const String stickerText = 'BONUS UNLOCKED!';
  static const double stickerDelay = .15;
  static const double stickerGap = 24;
}

/// The shared collect slot on the run HUD (PRD-2 §3.15 / §3.16, Q37 / Q42;
/// ARCH §1.10 `collect_slot.dart`).
abstract final class CollectConfig {
  /// §3.15 / §3.16 Slot centre. **Call (WP-4a):** the PRD's y ≈ 206–254
  /// (centre 230) lies in the master banner band (y 190 → ≈ 252 with a
  /// subtitle), which shows on every perfect pass; the tray / pill sit just
  /// under it instead (feather tray 264–312, puzzle pill 256–320), clear of
  /// the WP-3f timer pill (y 145–167) above. Top-anchored on every height.
  static const double slotX = 160;
  static const double slotY = 288;

  /// §3.15 / §3.16 HUD priority of the collect layer (under the banners).
  static const int priority = 17;
}
