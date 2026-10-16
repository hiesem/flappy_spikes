import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 the shared parts of the older moves (seams 7–10) and the
/// Underwater scene: the water surface, the sea gradient, light rays and
/// the paper boat (`wave`, `waterPath`, `waterline`, `sea`, `rays`,
/// `paperBoat`, `LAG` / `ek`, `LIFT`).

/// `LAG`: an older move moves the ground first and the sky last.
double ek(Band b, double q) {
  final (a, z) = switch (b) {
    Band.sky => (.18, 0.0),
    Band.far => (.1, .06),
    Band.mid || Band.near || Band.front => (0.0, .16),
  };
  return smooth((q - a) / (1 - a - z));
}

/// `LIFT` (`VH + 150`) on this view: the extra height of a taller view is
/// added so the moves still clear the screen (PRD §3.3).
double lift(Ctx c) => kVH + 150 + c.ext;

/// `LIFT_NEST` (`VH + 560`): the nest's tree tops reach far above its screen.
double liftNest(Ctx c) => kVH + 560 + c.ext;

/// `wave(x, yw, t)`.
double wave(double x, double yw, double t) =>
    yw + math.sin(x / 34 + t * 1.8) * 4 + math.sin(x / 13 - t * 2.6) * 1.5;

/// `waterPath(c, yw, t)` (adds to the current path).
void waterPath(Ctx c, double yw, double t) {
  c.moveTo(c.xl, wave(c.xl, yw, t));
  for (var x = c.xl + 8; x <= c.xr + 8; x += 8) {
    c.lineTo(x, wave(x, yw, t));
  }
}

/// `waterline(c, yw, t)`.
void waterline(Ctx c, double yw, double t) {
  c.save();
  c.lineJoin = StrokeJoin.round;
  c.beginPath();
  waterPath(c, yw, t);
  c.strokeStyle = const Color.fromRGBO(255, 255, 255, .95);
  c.lineWidth = 3;
  c.stroke();
  c.translate(0, 4);
  c.strokeStyle = const Color(0xFFD6D6D6);
  c.lineWidth = 1;
  c.stroke();
  c.restore();
}

/// `sea(c, ys, t, lead)`: water below the line [ys] (clips the canvas to
/// it); it ends up as the sea stage's own gradient once the surface is
/// above the screen. On a taller view the gradient holds its middle colour
/// for the view's extra height ([flat], `c.ext`) above y 0, so it meets the
/// Underwater sky (whose gradient spans y 0–568 and holds its first colour
/// above 0) exactly where the move ends or starts (PRD-2.4 §3.3 tall
/// screens; at 568 pt this is the prototype's gradient).
void sea(Ctx c, double ys, double t, [double lead = 190]) {
  final flat = c.ext;
  c.beginPath();
  waterPath(c, ys, t);
  c.lineTo(c.xr + 8, kVH + 80);
  c.lineTo(c.xl, kVH + 80);
  c.closePath();
  c.clip();
  final span = lead + flat + kVH;
  c.fillShader = c.linearGradient(
    0,
    ys,
    0,
    ys + span,
    const [Color(0xFFE4E4E4), Color(0xFFF2F2F2), Color(0xFFF2F2F2), Color(0xFFE9E9E9)],
    [0, lead / span, (lead + flat) / span, 1],
  );
  c.fillRect(c.xl, ys - 10, c.xr - c.xl, kVH + 400 + flat);
}

/// One light ray's gradient (white at `.4·a` → clear over `VH·.8`), built
/// once: each ray is drawn translated to its top with the alpha as
/// `globalAlpha` (PRD-2.4 §3.4: no per-frame shader).
final Shader _ray = Gradient.linear(
  Offset.zero,
  const Offset(0, kVH * .8),
  const [Color(0xFFFFFFFF), Color.fromRGBO(255, 255, 255, 0)],
);

/// `rays(c, t, cam, par, top)`: light rays falling from the surface at
/// y = [top].
void rays(Ctx c, double t, double top) {
  final ga = c.globalAlpha;
  each(c, c.cam * .05, 68, 3001, (xr, r, i) {
    final x0 = xr + math.sin(t * .25 + i * 1.3) * 14;
    final a = .5 + .5 * math.sin(t * .5 + i * 2.1);
    c.globalAlpha = ga * (.4 * a * 1000).round() / 1000;
    c.save();
    c.translate(0, top);
    c.fillShader = _ray;
    c.beginPath();
    c.moveTo(x0, 0);
    c.lineTo(x0 + 20, 0);
    c.lineTo(x0 + 120, kVH * .8);
    c.lineTo(x0 + 66, kVH * .8);
    c.closePath();
    c.fill();
    c.restore();
  });
  c.globalAlpha = ga;
}

/// `paperBoat(c, x, y, a)`.
void paperBoat(Ctx c, double x, double y, double a) {
  c.save();
  c.translate(x, y);
  c.rotate(a);
  c.fillStyle = const Color(0xFFF5F5F5);
  c.beginPath();
  c.moveTo(-8, -6);
  c.lineTo(0, -24);
  c.lineTo(8, -6);
  c.closePath();
  c.fill();
  c.strokeStyle = const Color(0xFFDADADA);
  c.lineWidth = .8;
  c.beginPath();
  c.moveTo(0, -24);
  c.lineTo(0, -6);
  c.stroke();
  c.fillStyle = const Color(0xFFFAFAFA);
  c.beginPath();
  c.moveTo(-16, -6);
  c.lineTo(16, -6);
  c.lineTo(10, 4);
  c.lineTo(-10, 4);
  c.closePath();
  c.fill();
  c.fillStyle = const Color(0xFFDDDDDD);
  c.beginPath();
  c.moveTo(-16, -6);
  c.lineTo(-7, -6);
  c.lineTo(-10, 4);
  c.closePath();
  c.fill();
  c.restore();
}
