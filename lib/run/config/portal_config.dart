import 'dart:ui';

import '../run_layers.dart';

/// Portal roller-coaster tuning (PRD-2 §3.12, §5.12b; mock engine
/// `design/menu_v2/rides84.js`, cannon ride `screen_portal.html`). Every
/// member's doc starts with its PRD section (ARCH §4). Ride paths and the
/// themed worlds' art live in `lib/run/rides/themes/` (data per ride).
abstract final class PortalConfig {
  // ------------------------------------------------------------ the ride

  /// §3.12 The bird accelerates from the live scroll speed to this (pt/s).
  static const double rideSpeed = 480;

  /// §3.12 …over this long (s), ease-out.
  static const double rideRamp = 2.2;

  /// §5.12b The bird moves to its ride position (offset [rideOffsetX],
  /// [rideOffsetY] from where it entered) over this long (s).
  static const double rideOffsetTime = 1.6;

  /// §5.12b Ride position offset (pt, screen): 66 right, 40 down.
  static const double rideOffsetX = 66;
  static const double rideOffsetY = 40;

  /// §3.12 The bird joins the path smoothly from where it crossed the
  /// portal plane over this long (s) (call: the portal opening is wider
  /// than the bird, so it rarely enters on the centre line).
  static const double joinTime = .5;

  /// §3.12 Ride rings per ride (+ the portal = 12 passes).
  static const int rideRings = 11;

  /// §3.12 Cannon ride: the first ring this far along the path (pt)…
  static const double firstRing = 190;

  /// §3.12 …then one every [cannonRingStep] (pt) (cannon ride).
  static const double cannonRingStep = 380;

  /// §5.12b Themed rides: 11 rings at equal arc length from [firstRing] to
  /// this far before the path end (pt) (`rides84.js`: `L − 260`).
  static const double themedRingEndMargin = 260;

  /// §3.12 Only rings within this far ahead on the path are shown (pt).
  static const double ringsAhead = 1500;

  /// §3.12 Hoops and items ahead of the bird fade out over this (s).
  static const double clearFade = .2;

  /// §3.12 / §5.12b The spike strips fade out over this at the ride start
  /// (s).
  static const double stripsFadeOut = .8;

  /// §5.12b Themed worlds fade in over this (s); the cannon ride's
  /// purple / cyan tint over [cannonTintIn] (s).
  static const double worldFadeIn = 1.2;
  static const double cannonTintIn = 2.4;

  /// §3.12 The portal ring fades out from [portalFadeFrom] over
  /// [portalFade] (s) after the ride start (mock).
  static const double portalFadeFrom = .4;
  static const double portalFade = .8;

  /// §3.12 Ride rings: the standard ring at full size (§3.0.1 ride = 118).
  static const double ringOpening = 118;

  /// §5.12b Storm: rings and bird scale ±12 % with the funnel depth.
  static const double depthScale = .12;

  /// §5.12b Pinball: the bird spins like a ball (rad per pt of path).
  static const double pinballSpinPerPt = 1 / 14;

  // ----------------------------------------------------------- way back

  /// §5.12b Launch flight (s), velocity (pt/s) and gravity (pt/s²).
  static const double flyTime = 1.7;
  static const double launchVx = 560;
  static const double launchVy = -640;
  static const double launchGravity = 520;

  /// §5.12b The flight ends (glide starts) this long before [flyTime] (s)
  /// (`rides84.js` FLY − 0.05).
  static const double flyEndEarly = .05;

  /// §5.12b Flight screen position: eases (over [flyEase] s) from the
  /// launch point to x 110 → 140, y (viewHeight / 2 − 25.5) → −20 (the
  /// mock's 330 → 310 at 711) over [flyDrift] s.
  static const double flyEase = .7;
  static const double flyDrift = 1.2;
  static const double flyX0 = 110;
  static const double flyX1 = 140;
  static const double flyYAboveCentre = 25.5;
  static const double flyYDrift = 20;

  /// §5.12b Flight: the bird swells by this (scale) over the first
  /// [flySwellTime] s.
  static const double flySwell = .1;
  static const double flySwellTime = .6;

  /// §5.12b Glide home (s) on the long smooth ease, then the settle (s).
  static const double glideTime = 2.5;
  static const double settleTime = .6;

  /// §5.12b Glide: up-arc (pt) and squash (scale).
  static const double glideArc = 70;
  static const double glideSquash = .08;

  /// §5.12b Settle wobble: amplitude (pt), decay (1/s), frequency (rad/s).
  static const double settleAmp = 5;
  static const double settleDecay = 4;
  static const double settleFreq = 13;

  /// §5.12b The theme tint fades into the game over this (s) of the glide.
  static const double tintFadeOut = 2;

  /// §5.12b The spike strips fade back in over this (s) of the glide…
  static const double stripsFadeIn = .3;

  /// §3.12 …with their teeth scrolling right-to-left at this (pt/s),
  /// decaying by exp(−[teethDecay]·t) (stop below 4 pt/s).
  static const double teethScroll = 1300;
  static const double teethDecay = 1.35;

  /// §5.12b Speed lines thin out over this (s) of the glide.
  static const double linesThinOut = 1.4;

  /// PRD-2.2 §18.3 Normal hoops resume: the first ring's plane reaches the
  /// bird this long after control returns (end of the glide + settle), at
  /// cruise (s; supersedes PRD-2 §3.12 "≈ 1 s after the landing").
  static const double firstRingAfterControl = 2.0;

  // ------------------------------------------- PRD-2.2 §18.1 circle in scene

  /// PRD-2.2 §18.1 In a ride scene the score circle (in the theme's
  /// `circleColor`, digits `circleDigits`) and the banners draw at this
  /// opacity.
  static const double sceneCircleOpacity = .5;

  // ------------------------------------------------------------- art / z

  /// §5.12b Portal ring: half width of the ellipse (pt), inner cyan rim
  /// half width, stroke widths, beam length (pt).
  static const double portalRx = 18;
  static const double portalInnerRx = 13;
  static const double portalInnerInset = 6;
  static const double portalStroke = 9;
  static const double portalInnerStroke = 3;
  static const double portalBeam = 66;

  /// §5.12b Portal colours.
  static const Color portalFront = Color(0xFF7C4DFF);
  static const Color portalBack = Color(0xFF4B2BB8);
  static const Color portalCyan = Color(0xFF22E6FF);

  /// §5.12b The beam pulses 75–100 % (rad/s).
  static const double beamPulse = 10;

  /// §3.12 Cyan sparkles drift off the portal (per s).
  static const double portalSparkles = 30;

  /// §5.12b Cannon colours.
  static const Color pink = Color(0xFFEC008C);
  static const Color pinkLight = Color(0xFFFF4FB7);
  static const Color gold = Color(0xFFFFB529);
  static const Color goldLight = Color(0xFFFFD98A);
  static const Color band = Color(0xFFB0006B);
  static const Color plum = Color(0xFF7A0044);
  static const Color ground = Color(0xFF5A3FB5);

  /// §3.12 Cannon: barrel tilt (°) to the right, aim time (s), entry (s).
  static const double cannonTilt = 38;
  static const double cannonAim = .85;
  static const double cannonEntry = .22;

  /// §3.12 Cannon ride tint (`#3b2a8a55` → `#22E6FF33`, top → bottom).
  static const Color cannonTintTop = Color(0x553B2A8A);
  static const Color cannonTintBottom = Color(0x3322E6FF);

  /// §5.12b Z-order; PRD-2.2 §18.1 / §18.5: the scene's backdrop under the
  /// score circle (−100), the scene banner layer just over the circle, the
  /// scene's objects over both (all below the guides −20 and the hoop
  /// backs −10); cannon 11; the bird is raised to 12 after the shot;
  /// effects over the hoop fronts.
  static const int backdropPriority = RunLayer.scoreCircle - 50;
  static const int sceneBannerPriority = RunLayer.scoreCircle + 1;
  static const int worldPriority = RunLayer.scoreCircle + 40;

  /// PRD-2.2 §18.1 on the way back (launch flight, glide) the circle and
  /// the banner draw above the wash (the objects layer).
  static const int circleOverWashPriority = worldPriority + 1;
  static const int bannerOverWashPriority = worldPriority + 2;
  static const int underBirdPriority = RunLayer.bird - 1;
  static const int frontPriority = RunLayer.rideCannon;
  static const int birdAfterShot = RunLayer.hoopFront;
  static const int fxPriority = RunLayer.fx + 1;
}
