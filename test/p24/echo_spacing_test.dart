// Owner feedback 2026-10-19: in a run the Afterimage copies sat about 68 art
// units apart (20 frames at full scroll) against the shop preview's 25, so
// they no longer overlapped like the shop. Run copies are now spaced by path
// distance at the shop's spacing, along the real path, with 6 copies.
import 'dart:math' as math;

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1 / 60;

/// Flies [frames] frames with the head at [head] while the world scrolls
/// left at [scroll] pt/s, like TierTrail in a run (emit with vx 0, then shift).
List<Offset> _fly(
  TrailEmitter e,
  int frames,
  Offset Function(int f) head, {
  double scroll = 200,
  double k = Config.lookScale,
}) {
  for (var f = 0; f < frames; f++) {
    e.shift(-scroll * _dt, 0);
    e.emit(head(f), _dt, k: k, vx: 0);
    e.step(_dt);
  }
  return e.echoPathPoints;
}

TrailEmitter _run() =>
    TrailEmitter('echo', random: math.Random(1))..worldLocked = true;

void main() {
  test('the shop preview spacing is 25 art units (20 frames of its drift)', () {
    // 20 frames at |skinShopTrailScroll| * k / 2 px/s, in art units.
    final shop = 20 * _dt * -Config.skinShopTrailScroll / 2;
    expect(shop, closeTo(TrailEmitter.echoSpacing, 1e-9));
  });

  test('level flight at full scroll: 6 copies, 25 art units apart', () {
    final pts = _fly(_run(), 120, (_) => const Offset(100, 300));
    expect(pts, hasLength(TrailEmitter.echoRunCopies));
    var prev = const Offset(100, 300);
    for (final p in pts) {
      final d = (prev - p).distance / Config.lookScale;
      expect(d, closeTo(TrailEmitter.echoSpacing, .6));
      prev = p;
    }
  });

  test('a steep climb keeps the same spacing along the path', () {
    final pts = _fly(_run(), 120, (f) => Offset(100, 500 - f * 4.0));
    expect(pts, hasLength(TrailEmitter.echoRunCopies));
    final head = Offset(100, 500 - 119 * 4.0);
    var prev = head;
    for (final p in pts) {
      final d = (prev - p).distance / Config.lookScale;
      expect(d, closeTo(TrailEmitter.echoSpacing, .6));
      prev = p;
    }
  });

  test('a smaller bird (Mini) spaces its copies at its own scale', () {
    const k = Config.lookScale * .5;
    final pts = _fly(_run(), 120, (_) => const Offset(100, 300), k: k);
    expect(((const Offset(100, 300) - pts.first).distance) / k,
        closeTo(TrailEmitter.echoSpacing, .6));
  });

  test('copies appear one by one as the path grows', () {
    final e = _run();
    expect(_fly(e, 3, (_) => const Offset(100, 300)), isEmpty);
    expect(_fly(e, 10, (_) => const Offset(100, 300)), hasLength(1));
  });
}
