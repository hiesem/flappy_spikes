import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/world_distance.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.4 §3.3 pacing (WP-W1 brief 4): the camera → world distance
/// mapping is monotonic and continuous and lands seam k on hoop 40·k, also
/// when the hoop spacing changes (trains, comets) or the camera runs on
/// without hoops (a ride).
class _Course implements HoopAnchors {
  _Course(this.planes);

  /// planes[i] = track x of hoop i's plane.
  final List<double> planes;

  /// How far ahead of the camera centre hoops are known (planned).
  double horizon = 700;
  double c = 0;

  @override
  int get nextIndex {
    var i = 0;
    while (i < planes.length - 1 && planes[i] < c + horizon) {
      i++;
    }
    return i;
  }

  @override
  double get nextX => planes[nextIndex];

  @override
  double? planeOf(int index) => index < nextIndex ? planes[index] : null;

  @override
  double get spacing => 310;
}

void main() {
  void fly(List<double> planes, {double step = 2.5, double from = 160}) {
    final course = _Course(planes)..c = from;
    final w = WorldDistance()..start(from, 0, planes[0], 310);
    var prev = w.w;
    var landed = 0;
    for (var c = from + step; c < planes[planes.length - 12]; c += step) {
      course.c = c - step;
      w.advance(c, course);
      final dw = w.w - prev;
      expect(dw, greaterThanOrEqualTo(0), reason: 'monotonic at $c');
      expect(dw, lessThanOrEqualTo(step * w.rMax + 1e-9), reason: 'continuous at $c');
      prev = w.w;
      for (var k = 1; 40 * k < planes.length; k++) {
        final x = planes[40 * k];
        if (c - step < x && c >= x) {
          // the step that crosses hoop 40k's plane ends within one step of W*
          expect((w.w - k * kE).abs(), lessThanOrEqualTo(step * 1.2 + 1e-6),
              reason: 'seam $k at hoop ${40 * k}');
          landed++;
        }
      }
    }
    expect(landed, greaterThanOrEqualTo(2));
  }

  List<double> course(double Function(int i) gap, int n) {
    final p = <double>[290];
    for (var i = 1; i < n; i++) {
      p.add(p.last + gap(i));
    }
    return p;
  }

  test('regular 310 spacing: rate 300/310, seams on hoops 40, 80, 120', () {
    fly(course((_) => 310, 130));
  });

  test('trains and comets change the spacing: still lands', () {
    fly(course((i) => i % 17 == 0 ? 422 : (i > 60 && i < 70 ? 520 : 310), 130));
  });

  test('a long ride (no hoops for 4 000 pt) right before a seam', () {
    fly(course((i) => i == 38 ? 4000 : 310, 130));
  });

  test('exactly W* when hoop 40 reaches the centre (landing step)', () {
    final planes = course((_) => 310, 60);
    final course0 = _Course(planes)..c = 160;
    final w = WorldDistance()..start(160, 0, planes[0], 310);
    var c = 160.0;
    while (c < planes[40]) {
      course0.c = c;
      final next = c + 3 > planes[40] ? planes[40] : c + 3;
      w.advance(next, course0);
      c = next;
    }
    expect(w.w, closeTo(40 * kPerHoop, 1e-6));
    expect(w.target, 80);
  });

  test('a knock-back moves the world back a little, no jump', () {
    final planes = course((_) => 310, 60);
    final a = _Course(planes)..c = 160;
    final w = WorldDistance()..start(160, 0, planes[0], 310);
    w.advance(1000, a);
    final at = w.w;
    a.c = 1000;
    w.advance(990, a);
    expect(w.w, lessThan(at));
    expect(at - w.w, lessThan(10 * w.rMax));
  });
}
