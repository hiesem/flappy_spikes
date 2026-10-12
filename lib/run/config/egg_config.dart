import 'dart:ui';

import 'hud_config.dart';

/// Egg / chick (PRD-2 §3.27, §5.26; `design/menu_v2/lab2_collect.js`
/// `IDEAS.egg2` + `lab3_collect.js` `IDEAS.egg3`). Every member's doc starts
/// with its PRD section.
abstract final class EggConfig {
  // --- §3.27 the carry ------------------------------------------------------

  /// §3.27 Five rings passed while carrying hatch the egg.
  static const int rings = 5;

  /// §5.26 A cracked egg wobbles for this long after each ring (mock `wob=.4`).
  static const double wobbleSeconds = .4;

  /// §5.26 Wobble rotation: `sin(wob · 40) · 0.25` rad.
  static const double wobbleOmega = 40;
  static const double wobbleAmp = .25;

  /// §5.26 The pops ("EGG!…", the countdown, "n / 8") are `#B87F00`.
  static const Color popColor = Color(0xFFB87F00);

  /// §3.27 "EGG! hatches in 5 rings" pop at the bird (mock BX+70, y−36).
  static const String pickupPop = 'EGG! hatches in 5 rings';
  static const double popDx = 70;
  static const double popDy = -36;
  static const double popSize = 15;

  /// §5.26 Countdown pops "4"…"1" (18 pt) at BX (mock y−40).
  static const double countdownDy = -40;
  static const double countdownSize = 18;

  // --- §5.26 the egg (8 × 10 pt oval × 1.3 as a pickup, on the bird at 1.0) -

  /// §5.26 Cream `#FFF3D6` oval radii (pt): rx 8, ry 10.
  static const double ovalRx = 8;
  static const double ovalRy = 10;
  static const Color oval = Color(0xFFFFF3D6);

  /// §5.26 The floating egg bobs ±3 pt at 3 rad/s (mock `sin(t·3)·3`).
  static const double bobAmp = 3;
  static const double bobOmega = 3;

  /// §5.26 The floating pickup draws it at 1.3×.
  static const double pickupScale = 1.3;

  /// §5.26 Three tan `#E8C58A` speckles r 1.3 at these offsets (pt).
  static const Color speckle = Color(0xFFE8C58A);
  static const double speckleR = 1.3;
  static const List<Offset> speckles = [
    Offset(-3, -3),
    Offset(3, 1),
    Offset(-1, 5),
  ];

  /// §5.26 Zig-zag crack lines `#8D6E3F` 1.2 pt: line i at y −6 + 3i.
  static const Color crackColor = Color(0xFF8D6E3F);
  static const double crackWidth = 1.2;
  static const double crackStartY = -6;
  static const double crackStep = 3;

  /// §5.26 Warm halo r 22, `rgba(255,220,140,·)` at α 0.6.
  static const Color haloColor = Color(0xFFFFDC8C);
  static const double haloR = 22;
  static const double haloAlpha = .6;

  /// §5.26 On the bird it sits ≈ 22 pt above the centre, 2 pt behind.
  static const double onBirdDx = -2;
  static const double onBirdDy = -22;

  // --- §5.26 the chick ------------------------------------------------------

  /// §5.26 The `golden` bird skin at 48 % size.
  static const double chickScale = .48;

  /// §5.26 The "bye!" the chick leaves behind (12 pt `#B87F00`, 16 pt up).
  static const String byeText = 'bye!';
  static const double byeSize = 12;
  static const double byeDy = -16;

  /// §5.26 It follows ≈ 36 pt behind and 10 pt below, bobbing ±6 pt (5 rad/s).
  static const double chickBehind = 36;
  static const double chickBelow = 10;
  static const double chickBobAmp = 6;
  static const double chickBobOmega = 5;

  /// §5.26 Soft lag: `min(1, dt · 4)` toward x, `min(1, dt · 3)` toward y.
  static const double chickLagX = 4;
  static const double chickLagY = 3;

  /// §5.26 Art clock `t · 1.6`; the wing flaps when `sin(14 t) > 0`.
  static const double chickArtRate = 1.6;
  static const double chickFlapOmega = 14;

  // --- §3.27 sounds & colours ----------------------------------------------

  /// §5.26 HATCHED! banner and the ×2 pill are gold `#F2A900`.
  static const Color gold = Color(0xFFF2A900);

  /// §5.26 ×2 LOST banner is grey `#9E9E9E`.
  static const Color lostGrey = Color(0xFF9E9E9E);

  /// §5.26 The hatch burst: 12 cream / white pieces 140 pt/s (mock `burst`).
  static const int hatchPieces = 12;
  static const double hatchSpeed = 140;
  static const List<Color> hatchColors = [Color(0xFFFFF3D6), Color(0xFFFFFFFF)];

  /// PRD-2.2 §23 A rim touch breaks the egg: the hatch's shell triangles
  /// plus a few yolk-yellow pieces fall away from the egg on the bird's
  /// back (≈ 0.6 s, with gravity). Same shell master as the hatch
  /// (`CollectBursts.burst`, triangle shape).
  static const int breakPieces = 10;
  static const double breakSpeed = 110;
  static const double breakGravity = 900;
  static const double breakLife = .6;
  static const List<Color> breakColors = [
    Color(0xFFFFF3D6),
    Color(0xFFFFFFFF),
    Color(0xFFFFF3D6),
    Color(0xFFFFD54A),
  ];

  /// §5.26 The chick sits 36 pt behind and 10 pt below the bird and bobs.
  /// (see the chick block below).

  /// §5.26 The chick peeps now and then (the mock's `p.snd('peepSmall')`;
  /// ≈ 0.9 peeps/s on average).
  static const double peepEvery = 1.1;

  /// §5.26 "HATCHED!" (gold) with the ×2 explanation.
  static const String hatchText = 'HATCHED!';
  static const String hatchSub =
      '×2 on every coin while the chick flies with you';

  /// §5.26 "×2 LOST" (grey) after a rim touch.
  static const String lostText = '×2 LOST';
  static const String lostSub = 'you touched a rim · the chick flew off';

  /// §5.26 The chick's leave: it flies up and away (190 / 150 pt/s) with a
  /// "bye!" for 1.6 s before it is gone (mock `ch.leave`).
  static const double byeOutX = 190;
  static const double byeOutY = 150;
  static const double byeSeconds = 1.6;

  // --- §5.26 the HUD ×2 pill (mock `rr(c,128,202,64,24,12)`) ----------------

  static const double hudX = 128;
  static const double hudY = 202 - HudConfig.collectLift;
  static const double hudW = 64;
  static const double hudH = 24;
  static const double hudRadius = 12;

  /// §5.26 The chick inside the pill (centre 144,214, 36 %) and "×2" at 172,215.
  static const double hudChickX = 144;
  static const double hudChickY = 214 - HudConfig.collectLift;
  static const double hudChickScale = .36;
  static const double hudTextX = 172;
  static const double hudTextY = 215 - HudConfig.collectLift;
  static const double hudTextSize = 17;
}
