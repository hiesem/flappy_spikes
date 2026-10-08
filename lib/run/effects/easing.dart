import 'dart:math' as math;

/// The easing curves the mocks use (`eio`, `eob`, `sm`, CSS `OUT`), shared by
/// every effect so timings match the approved animations.
abstract final class Ease {
  /// Cubic in-out (`eio`).
  static double cubicInOut(double u) {
    final x = u.clamp(0.0, 1.0);
    return x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
  }

  /// Ease-out-back (`eob`, c = 1.70158): overshoots ≈ 10 % then settles.
  static double outBack(double u) {
    const c1 = 1.70158, c3 = c1 + 1;
    final x = u.clamp(0.0, 1.0) - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  /// Smoothstep (`sm`).
  static double smooth(double u) {
    final x = u.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Quadratic out.
  static double outQuad(double u) {
    final x = u.clamp(0.0, 1.0);
    return 1 - (1 - x) * (1 - x);
  }

  /// CSS `cubic-bezier(.34, 1.56, .64, 1)` (the mocks' `OUT`).
  static double cssOut(double u) => _bezier(u.clamp(0.0, 1.0), .34, 1.56, .64, 1);

  /// Any CSS `cubic-bezier(x1, y1, x2, y2)` (WP-5b: the VS intro's
  /// `ease-out` / `ease-in` / panel and fly-in curves).
  static double bezier(double u, double x1, double y1, double x2, double y2) =>
      _bezier(u.clamp(0.0, 1.0), x1, y1, x2, y2);

  static double _bezier(double x, double x1, double y1, double x2, double y2) {
    // Solve x(t) = x by Newton iterations, then return y(t).
    double bx(double t) =>
        3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t;
    double by(double t) =>
        3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t;
    var t = x;
    for (var i = 0; i < 8; i++) {
      final d =
          3 * (1 - t) * (1 - t) * x1 +
          6 * (1 - t) * t * (x2 - x1) +
          3 * t * t * (1 - x2);
      if (d.abs() < 1e-6) break;
      t -= (bx(t) - x) / d;
      t = t.clamp(0.0, 1.0);
    }
    return by(t);
  }
}
