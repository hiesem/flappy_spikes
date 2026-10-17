import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection, TextAlign;

import '../../game/sound.dart';
import '../config/portal_config.dart';
import '../director/plans.dart';
import '../effects/particle_pool.dart';
import 'ride_path.dart';
import '../../game/paints.dart';

/// The phases of a portal ride (PRD-2 §3.12, §5.12b; `rides84.js`):
/// ride (≈ 9.6 s on the path) → exit moment → launch flight (1.7 s) →
/// glide home (2.5 s + 0.6 s settle).
enum RidePhase { ride, exit, fly, glide, done }

/// Sound cues of the rides; each theme maps them to its `Sfx` (§5.12b
/// sound column; `rides84.js` `RIDE_SFX`).
enum RideCue {
  thump,
  rocket,
  pop,
  rumble,
  boom,
  splash,
  bubble,
  whale,
  spout,
  bumper,
  flipper,
  jackpot,
  plunger,
  thunder,
  wind,
  umbrella,
  cannonAim,
  cannonShot,
}

/// Where the bird is drawn (screen) during the exit moment.
class BirdPose {
  const BirdPose(this.pos, {this.rot = 0, this.scale = 1, this.hidden = false});
  final Offset pos;
  final double rot;
  final double scale;
  final bool hidden;
}

/// A ride-only particle that the shared `ParticlePool` cannot draw (stroked
/// bubbles, glowing lava bombs, two-tone lava, "+500" texts).
enum RideBlobKind { bubble, bomb, lava, text }

class RideBlob {
  RideBlob(
    this.kind, {
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.r = 4,
    required this.life,
    this.gravity = 0,
    this.text = '',
    this.color = const Color(0xFFFFFFFF),
    this.scene = false,
  });
  final RideBlobKind kind;
  double x, y, vx, vy;
  final double r;
  double t = 0;
  final double life;
  final double gravity;
  final String text;
  final Color color;

  /// Moves with the launch scene (falls away during the flight).
  final bool scene;
}

/// Everything a theme reads and writes while the ride runs (the mock's `R`).
class RideView {
  RideView({
    required this.path,
    required this.h,
    required this.rnd,
    required this.cue,
    this.left = 0,
  });

  final RidePath path;

  /// Screen size (pt).
  final double w = 320;
  final double h;

  /// WP-TAB: the screen's left edge (pt; −extra on a wide screen: the
  /// view runs from [left] to [w]).
  final double left;

  /// WP-TAB: the whole visible screen (`left, 0` – `w, h`).
  Rect get full => Rect.fromLTRB(left, 0, w, h);

  /// WP-TAB: [x] wrapped into the visible width ([left] .. [w]); the same
  /// as a wrap into 0..[w] on a phone.
  double wrapX(double x) {
    final span = w - left;
    return ((x - left) % span + span) % span + left;
  }
  final math.Random rnd;
  void Function(RideCue cue) cue;

  RidePhase phase = RidePhase.ride;

  /// Time since the ride started; phase clocks.
  double t = 0, rt = 0, et = 0, ft = 0, gt = 0;

  /// Arc length of the bird on the path.
  double s = 0;

  /// The ride camera in path coordinates (screen = path point − cam).
  Vector2 cam = Vector2.zero();

  /// The camera when the path ended (exit / flight scenes hang off it).
  Vector2 camEnd = Vector2.zero();

  /// The launch flight's world offset (the scene falls away by −off).
  Offset off = Offset.zero;

  /// The bird's screen position / rotation when the path ended.
  Offset lastBird = Offset.zero;
  double lastRot = 0;

  /// The bird's screen position now.
  Offset bird = Offset.zero;

  /// The themed world's opacity (ride: fades in; way back: fades out).
  double envA = 0;

  /// Shared-master particles: [screen] (stays put) and [scene] (drawn at
  /// −[off]: falls away with the launch scene).
  final ParticlePool screen = ParticlePool(capacity: 160);
  final ParticlePool scenePool = ParticlePool(capacity: 160);
  final List<RideBlob> blobs = [];

  /// The theme may keep its own state here.
  final Map<String, Object> data = {};
  final Set<String> flags = {};

  /// True once (per [flag]) — the mock's `R.f1 …` one-shot flags.
  bool once(String flag) => flags.add(flag);

  double rand(double a, double b) => a + rnd.nextDouble() * (b - a);

  /// The mock bottom-anchored y at 711 pt (`H + v − 711`).
  double fromBottom(double y711) => h - (711 - y711);

  void stepBlobs(double dt) {
    blobs.removeWhere((b) {
      b.t += dt;
      if (b.t >= b.life) return true;
      b.vy += b.gravity * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      return false;
    });
  }
}

/// One portal ride's look and choreography (PRD-2 §7 `RideTheme`): world
/// painter, path, exit choreography, launch point, tint and sounds. The
/// shared [PortalRide] engine runs the timeline (camera, rings, passes,
/// launch flight, glide home) for every theme.
abstract class RideTheme {
  RideId get id;

  /// The path in path coordinates (starts at the portal heading right).
  RidePath buildPath();

  /// Arc lengths of the [PortalConfig.rideRings] rings (equal arc length).
  List<double> ringStations(RidePath p) =>
      p.equalStations(PortalConfig.rideRings);

  /// §5.12b The way-back wash tint (top → bottom).
  (Color, Color) get washTint;

  // region WP-G3 — the score circle in the scene (PRD-2.2 §18.1)
  /// PRD-2.2 §18.1 The score circle's colour in this scene (drawn at
  /// `PortalConfig.sceneCircleOpacity`).
  Color get circleColor;

  /// PRD-2.2 §18.1 The score digits' colour in this scene (its dark tone).
  Color get circleDigits;
  // endregion WP-G3

  /// §5.12b sounds per cue.
  Map<RideCue, Sfx> get sounds;

  /// The exit moment's length (s).
  double get exitDuration;

  /// The launch point (screen) at the end of the exit moment.
  Offset launchPoint(RideView v);

  /// The world fades in over this (s) at the ride start.
  double get worldFadeIn;

  /// The exit replaces the ride world with its own full-screen scene.
  bool get exitFill => false;

  /// The bird spins like a ball (pinball).
  bool get spin => false;

  /// Rings and bird scale with the funnel depth (storm).
  bool get depth => false;

  /// A pink umbrella opens over the bird in the glide home (storm).
  bool get umbrella => false;

  /// Builds the theme's world (seeded art, path-anchored props).
  void init(RideView v) {}

  /// PRD-2.2 §18.5 The ride world's backdrop (sky, gradient, stars, grid,
  /// light shafts, clouds): drawn under the score circle and the banner.
  void paintBackdrop(Canvas c, RideView v, Vector2 cam) {}

  /// The ride world's objects (planets, rocks, crystals, lava, ship, fish,
  /// bumpers, the funnel, the ground …), path coordinates through [cam]:
  /// drawn over the score circle and the banner (PRD-2.2 §18.1).
  void paintWorld(Canvas c, RideView v, Vector2 cam);

  /// Drawn over the bird during the ride (the cannon).
  void paintWorldFront(Canvas c, RideView v) {}

  /// PRD-2.2 §18.5 The backdrop of an exit scene that fills the screen
  /// ([exitFill]: volcano, sea, pinball), under the score circle.
  void paintExitBackdrop(Canvas c, RideView v, double et, Offset off) {}

  /// The exit / launch scene's objects, behind the bird ([et] runs on
  /// through the flight; the scene is drawn at −[off]).
  void paintExit(Canvas c, RideView v, double et, Offset off) {}

  /// The exit / launch scene over the bird.
  void paintExitFront(Canvas c, RideView v, double et, Offset off) {}

  /// Where the bird is during the exit moment.
  BirdPose exitPose(RideView v, double et);

  /// The launch: particles and its sound.
  void onLaunch(RideView v) {}

  /// Draws the projectile instead of the bird early in the flight (the
  /// space rocket); returns true while the bird is hidden.
  bool paintProjectile(Canvas c, RideView v, double ft, Offset at, double ang) =>
      false;

  /// True while [paintProjectile] replaces the bird at flight time [ft].
  bool projectileActive(RideView v, double ft) => false;

  /// Per-frame rules (embers, bubbles, bumpers, lightning).
  void tick(RideView v, double dt) {}

  /// Over everything (texts, the peeled rocket).
  void paintExtra(Canvas c, RideView v) {}
}

// ------------------------------------------------------------- art helpers

final Paint _fill = Paint();
final Paint _stroke = Paint()..style = PaintingStyle.stroke;

Paint fillOf(Color c, [double alpha = 1]) =>
    _fill
      ..shader = null
      ..maskFilter = null
      ..color = c.withValues(alpha: c.a * alpha.clamp(0.0, 1.0));

Paint strokeOf(Color c, double width, [double alpha = 1]) =>
    _stroke
      ..shader = null
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..color = c.withValues(alpha: c.a * alpha.clamp(0.0, 1.0));

/// A vertical gradient over [r] (top → bottom).
void vGradient(Canvas c, Rect r, Color top, Color bottom, [double alpha = 1]) {
  final p = Paint()
    ..shader = Gradient.linear(r.topCenter, r.bottomCenter, [
      top.withValues(alpha: top.a * alpha),
      bottom.withValues(alpha: bottom.a * alpha),
    ]);
  c.drawRect(r, p);
}

/// A radial glow from [colour] at the centre to transparent at [r].
void radialGlow(
  Canvas c,
  Rect area,
  Offset centre,
  double r,
  Color colour, {
  double r0 = 0,
}) {
  final p = Paint()
    ..shader = Gradient.radial(
      centre,
      r,
      [colour, colour.withValues(alpha: 0)],
      [r <= 0 ? 0 : (r0 / r).clamp(0.0, 1.0), 1],
    );
  c.drawRect(area, p);
}

Path poly(List<double> xy) {
  final p = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  return p..close();
}

/// The mock's 4-point star (24 × 24 polygon scaled to [size]).
void paintStar(Canvas c, Offset at, double size, Color col, double rot) {
  c
    ..save()
    ..translate(at.dx, at.dy)
    ..rotate(rot)
    ..scale(size / 24);
  c.drawPath(
    poly([0, -12, 3, -3, 12, 0, 3, 3, 0, 12, -3, 3, -12, 0, -3, -3]),
    fillOf(col),
  );
  c.restore();
}

final Map<String, TextPainter> _texts = {};

/// Centred text (cached layouts).
void paintText(
  Canvas c,
  String text,
  Offset centre, {
  required double size,
  required Color color,
  String family = 'Opificio Neue',
  double alpha = 1,
}) {
  final key = '$text|$size|${color.toARGB32()}|$family';
  final tp = _texts[key] ??= (TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: size, color: color),
    ),
    textAlign: p.TextAlign.center,
    textDirection: p.TextDirection.ltr,
  )..layout());
  if (alpha < 1) {
    c.saveLayer(
      Rect.fromCenter(center: centre, width: tp.width + 4, height: tp.height + 4),
      layerPaint(alpha.clamp(0.0, 1.0)),
    );
  }
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
  if (alpha < 1) c.restore();
}

/// Draws the ride blobs (bubbles, bombs, lava, texts); [scene] selects the
/// scene-anchored ones (already translated by the caller).
void paintBlobs(Canvas c, RideView v, {required bool scene}) {
  for (final b in v.blobs) {
    if (b.scene != scene) continue;
    final k = 1 - b.t / b.life;
    switch (b.kind) {
      case RideBlobKind.bubble:
        c.drawCircle(
          Offset(b.x, b.y),
          b.r,
          strokeOf(const Color(0xD9FFFFFF), 1.4, k),
        );
      case RideBlobKind.lava:
        c.drawCircle(
          Offset(b.x, b.y),
          b.r,
          fillOf(k > .5 ? const Color(0xFFFFD54A) : const Color(0xFFFF5A1A), k),
        );
      case RideBlobKind.bomb:
        final glow = Paint()
          ..color = const Color(0xAAFF5A1A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
        c
          ..drawCircle(Offset(b.x, b.y), b.r + 3, glow)
          ..drawCircle(Offset(b.x, b.y), b.r, fillOf(const Color(0xFF3A1A10)))
          ..drawCircle(
            Offset(b.x - 2, b.y - 2),
            b.r * .5,
            fillOf(const Color(0xFFFF7A1A)),
          );
      case RideBlobKind.text:
        paintText(
          c,
          b.text,
          Offset(b.x, b.y),
          size: 16,
          color: b.color,
          family: 'Fredoka',
          alpha: k,
        );
    }
  }
}

/// Smoothstep / eases of the mock engine.
double sm(double x) {
  final k = x.clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}

double easeOut(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();
double easeIn(double x) => math.pow(x.clamp(0.0, 1.0), 2.2).toDouble();
double smoother(double k) => k * k * k * (k * (k * 6 - 15) + 10);
double lerpD(double a, double b, double k) => a + (b - a) * k;
Offset lerpO(Offset a, Offset b, double k) =>
    Offset(lerpD(a.dx, b.dx, k), lerpD(a.dy, b.dy, k));
