import 'dart:math' as math;
import 'dart:ui';

import 'backdrop_ctx.dart';
import 'backdrop_math.dart';

/// PRD-2.4 §3 — the prototype's shared drawing helpers
/// (`docs/p24/endless_vertical.html`, "the endless world" and "helpers"),
/// used by every scene and seam painter.
///
/// `presence()` — how much of a stage exists at a panorama point — only
/// differs from 1 next to a side-by-side (`'h'`) seam. The approved world
/// has none (all ten seams are camera moves), so it is identically 1 and the
/// prototype's thinning in `each`, the sinking in `ridgeY` / `gfill` and the
/// fading in `pa()` never apply; the ports below leave them out.

/// `presence(p, f)`: identically 1 (see above).
double presence(double p, double f) => 1;

/// `pa(x)`: identically 1 (see above).
double pa(double x) => 1;

/// `mark(dx)`: a landmark in the middle of its stage (moves at 0.04×).
double mark(Ctx c, double dx) =>
    kANCH + ((c.env + .5) * c.stage - c.cam) * .04 + dx;

/// `early(x, f, span)`: 1 at the start of the current stage, easing to 0
/// over [span] of it; for leftovers from the stage before.
double early(Ctx c, double x, double f, double span) {
  final seg = c.stage * f, p = x + c.cam * f, p0 = c.env * c.stage * f + kANCH;
  return 1 - smooth((p - p0 - seg * .06) / (seg * span));
}

/// `each(off, spacing, seed, fn)`: tiles an infinite layer; fn(screenX,
/// rand, index) for every slot that touches the drawn range.
void each(
  Ctx c,
  double off,
  double spacing,
  int seed,
  void Function(double x, Rng r, int k) fn,
) {
  final k0 = ((off + c.xl) / spacing).floor() - 1;
  final k1 = ((off + c.xr) / spacing).floor() + 1;
  final r = c.takeRng();
  for (var k = k0; k <= k1; k++) {
    r.reset(k, seed);
    fn(k * spacing - off, r, k);
  }
  c.releaseRng();
}

/// `wraps(v, period, ofs)`: every copy of a wrapping sprite in range.
void wraps(Ctx c, double v, double period, double ofs, void Function(double x) fn) {
  final b = modD(v, period) - ofs;
  for (var x = b - ((b - c.xl + ofs) / period).ceil() * period;
      x < c.xr + ofs;
      x += period) {
    fn(x);
  }
}

/// `ridgeY(off, x, base, amp, f1, f2, ph)`.
double ridgeY(double off, double x, double base, double amp, double f1,
    double f2, double ph) {
  final w = x + off;
  return base - amp * (0.62 * math.sin(w / f1 + ph) + 0.38 * math.sin(w / f2 + ph * 2.1));
}

/// `ridgeAt(env, f, off, x, …)`: a ground height as the given stage draws
/// it (no sinking, see [presence]).
double ridgeAt(double off, double x, double base, double amp, double f1,
        double f2, double ph) =>
    ridgeY(off, x, base, amp, f1, f2, ph);

/// `ridgePath(c, off, base, amp, f1, f2, ph)` (into the current path).
void ridgePath(Ctx c, double off, double base, double amp, double f1,
    double f2, double ph) {
  c.beginPath();
  c.moveTo(c.xl, kVH + 60);
  for (var x = c.xl; x <= c.xr + 4; x += 4) {
    c.lineTo(x, ridgeY(off, x, base, amp, f1, f2, ph));
  }
  c.lineTo(c.xr + 4, kVH + 60);
  c.closePath();
}

/// `ridge(c, off, base, amp, f1, f2, col, ph)`.
void ridge(Ctx c, double off, double base, double amp, double f1, double f2,
    Color col, double ph) {
  ridgePath(c, off, base, amp, f1, f2, ph);
  c.fillStyle = col;
  c.fill();
}

/// `gfill(c, y, 'sink')`: a full-width ground strip from [y] down.
void gfillSink(Ctx c, double y) =>
    c.fillRect(c.xl, y, c.xr + 4 - c.xl, kVH + 60 - y);

/// `gfill(c, y, 'cut', h)`: a full-width strip [h] tall at [y].
void gfillCut(Ctx c, double y, double h) =>
    c.fillRect(c.xl, y, c.xr - c.xl + 2, h);

/// `flatCloud(c, x, y, s, col)`.
void flatCloud(Ctx c, double x, double y, double s, Color col) {
  c.fillStyle = col;
  c.beginPath();
  c.roundRect(x, y, 66 * s, 18 * s, 9 * s);
  c.fill();
  c.circ(x + 22 * s, y + 4 * s, 13 * s);
  c.circ(x + 42 * s, y + 2 * s, 17 * s);
}

/// `pill(c, x, y, w, h, col)`.
void pill(Ctx c, double x, double y, double w, double h, Color col) {
  c.fillStyle = col;
  c.beginPath();
  c.roundRect(x, y, w, h, h / 2);
  c.fill();
}

/// `vgrad(c, stops, force)`: a full-height gradient, only when [force] and
/// not while an older move draws the arriving stage. On taller views it
/// reaches up to the top of the screen (its first colour above 0).
void vgrad(Ctx c, List<Color> colors, List<double> stops, {bool force = false}) {
  if (!force || c.vert) return;
  c.fillShader = c.linearGradient(0, 0, 0, kVH, colors, stops);
  c.fillRect(c.xl, c.yTop, c.xr - c.xl, kVH - c.yTop);
}
