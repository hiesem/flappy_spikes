import 'dart:math' as math;

import 'package:flappy_spikes/run/backdrop/backdrop_ctx.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_helpers.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_scene.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_tables.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/seams/seam.dart';
import 'package:flappy_spikes/run/backdrop/seams/water.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';
import 'support/origami_fixture.dart';

/// PRD-2.4 §3.3 known issue + §4 test 9: the start of seam 7 (The dive)
/// had a small jump at the bottom where the paper river becomes water.
/// Checked here with the prototype's paper river (a fixture: the real
/// Paper Origami is WP-W2's) under the dive: the prototype's own dive jumps
/// at the window's start, the port does not.
void main() {
  const sc = kTotal + 7 * kE; // seam 7, loop 2
  List<BackdropScene> scenes() => [...kScenes]..[6] = const OrigamiFixture();
  BackdropPainter painter(Seam dive) {
    final seams = [...kSeams]..[6] = dive;
    return BackdropPainter(world: BackdropWorld(scenes: scenes(), seams: seams));
  }

  Future<int> step(BackdropPainter p, double cam, double h) async {
    final a = await renderBackdrop(cam: cam, viewHeight: h, painter: p);
    final b = await renderBackdrop(cam: cam + 1, viewHeight: h, painter: p);
    final n = diffPixels(await rgbaOf(a), await rgbaOf(b), threshold: 3);
    a.dispose();
    b.dispose();
    return n;
  }

  Future<(int, int)> jumpAndNormal(BackdropPainter p, double cam, double h) async {
    final n = await step(p, cam, h);
    final before = await step(p, cam - 3, h), after = await step(p, cam + 3, h);
    return (n, math.max(before, after));
  }

  for (final h in [568.0, 730.0]) {
    test('the prototype dive jumps at its start (the check sees it) @${h.round()}', () async {
      final (n, normal) = await jumpAndNormal(painter(const _PrototypeDive()), sc - kVWIN / 2, h);
      expect(n, greaterThan(normal * 2 + 300), reason: 'prototype dive: $n px, normal $normal');
    });
    for (final e in [-kVWIN / 2 - 1, -kVWIN / 2 - .5, -kVWIN / 2, -kVWIN * 13 / 30, -kVWIN * 11 / 30, -kVWIN * 9 / 30, 0.0,
      kVWIN / 2 - 1, kVWIN / 2]) {
      test('the dive has no jump at ${e.round()} @${h.round()}', () async {
        final p = painter(kSeams[6]);
        final (n, normal) = await jumpAndNormal(p, sc + e, h);
        expect(n, lessThanOrEqualTo(normal * 2 + 300),
            reason: 'dive at ${e.round()}: $n px changed, ordinary motion $normal');
      });
    }
    test('evidence: the dive start with the paper river @${h.round()}', () async {
      final p = painter(kSeams[6]);
      for (final e in [-kVWIN / 2 - 1, -kVWIN / 2, -kVWIN * 13 / 30, -kVWIN * 11 / 30, -kVWIN / 4]) {
        final img = await renderBackdrop(cam: sc + e, viewHeight: h, scale: 2, painter: p);
        await saveEvidence(img, 'wpW3/dart', 'seam7_fixture_${e.round()}_${h.round()}');
        img.dispose();
      }
    });
  }
}

/// The prototype's `dive`, unchanged (the jump the PRD reports), to show
/// the check catches it.
class _PrototypeDive extends OlderSeam {
  const _PrototypeDive();

  @override
  String get title => 'The dive (prototype)';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final t = c.t, lf = lift(c);
    final ys = 528 - ek(Band.near, q) * lf;
    w.group(c, ga, Band.layers, (b) => -ek(b, q) * lf);
    c.save();
    sea(c, ys, t);
    rays(c, t, ys + 190 * ek(Band.near, q));
    c.vert = true;
    w.group(c, gb, Band.layers, (b) => (1 - ek(b, q)) * lf);
    c.vert = false;
    c.restore();
    waterline(c, ys, t);
    wraps(c, 40 - c.cam * .3 + t * 10, 150, 0, (x) {
      paperBoat(c, x, wave(x, ys, t) - 1, math.sin(t * 1.4 + x * .01) * .08);
    });
  }
}

