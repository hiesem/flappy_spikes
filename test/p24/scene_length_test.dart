import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_ctx.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_helpers.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_scene.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_tables.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/run_backdrop.dart';
import 'package:flappy_spikes/run/backdrop/seams/seam.dart';
import 'package:flappy_spikes/run/backdrop/world_distance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Owner 2026-10-19 (2.4.0+38): a background scene lasts 20 hoops, at the
/// 1× scroll and clock of 2.4.0 (36). The seam window, the linger and the
/// landmarks are scaled with the scene; no seam overruns its scene.
void main() {
  group('20-hoop scenes', () {
    test('a scene is 20 hoops: kE = 20 · kPerHoop, the loop 200 hoops', () {
      expect(kHoopsPerScene, 20);
      expect(kPerHoop, 300);
      expect(kE, 6000);
      expect(kTotal / kPerHoop, 200);
    });

    test('seam k is centred on hoop 20·k (k = 1 … 25)', () {
      for (var k = 1; k <= 25; k++) {
        final s = BackdropWorld.seamAt(20 * k * kPerHoop);
        expect(s.j, k, reason: 'hoop ${20 * k}');
        expect(s.d, 0);
      }
    });

    test('the seam window is a quarter of the scene (5 hoops), the linger scaled with it', () {
      expect(kVWIN, kE / 4);
      expect(kVWIN / kPerHoop, 5);
      expect(kLinger, closeTo(1750, 1e-9));
    });

    test('no seam (window + lingering pieces) overruns its scene', () {
      // a floor move draws its pieces over ±(kVWIN / 2 + kLinger); an older
      // move over ±kVWIN / 2. Both must end well before the next seam's
      // range begins: at least 3 hoops of the plain scene in between.
      for (final seam in kSeams) {
        final reach = seam is FloorSeam ? kVWIN / 2 + kLinger : kVWIN / 2;
        final gap = kE - 2 * reach;
        expect(gap, greaterThanOrEqualTo(3 * kPerHoop), reason: seam.title);
        // the switch to the plain stage (±kE / 2) is outside the reach
        expect(reach, lessThan(kE / 2), reason: seam.title);
      }
    });

    test('a seam ends before the next one starts: world distances between seams draw a plain scene', () {
      // between two seams' ranges the world paints just the scene
      final w = _RecWorld();
      for (var j = 1; j <= 12; j++) {
        final seam = kSeams[(j - 1) % kNST];
        final reach = seam is FloorSeam ? kVWIN / 2 + kLinger : kVWIN / 2;
        for (final d in [reach + 1, kE / 2 - 1, kE / 2 + 1]) {
          final cam = j * kE + d;
          final next = kSeams[j % kNST];
          final nextReach = next is FloorSeam ? kVWIN / 2 + kLinger : kVWIN / 2;
          if ((j + 1) * kE - cam <= nextReach) continue;
          w.groups.clear();
          final c = Ctx()
            ..canvas = Canvas(PictureRecorder())
            ..cam = cam
            ..t = 3;
          w.paint(c);
          expect(w.groups.toSet(), {j}, reason: 'seam $j d $d: only scene $j');
        }
      }
    });

    test('a landmark is where the prototype has it at the same share of its scene', () {
      // the prototype: mark = 160 + ((env + .5) · 12 000 − cam) · .04 + dx;
      // now the same at the same share of the (shorter) stage.
      final c = Ctx()..env = 3;
      for (final f in [0.0, .125, .25, .5, .75, .875, 1.0]) {
        c.cam = (3 + f) * kE;
        final proto = 160 + ((3 + .5) * 12000 - (3 + f) * 12000) * .04;
        expect(mark(c, 0), closeTo(proto, 1e-9), reason: 'f $f');
      }
    });
  });

  group('1× in a run', () {
    FlameTester<FlappySpikesGame> tester() => FlameTester(
          () => createRunTestGame(prefs: {'firstRunHintSeen': true}),
          gameSize: Vector2(320, 568),
        );

    tester().testGameWidget(
      'the backdrop paints the world distance and the run clock unscaled',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        await startRun(g);
        await flyUntil(g, (r) => r.state.runClock > 3);
        final b = RunBackdrop.of(g)!;
        final rec = PictureRecorder();
        b.render(Canvas(rec));
        rec.endRecording().dispose();
        expect(b.painter.ctx.cam, b.worldDistance, reason: 'layers scroll at 1×');
        expect(b.painter.ctx.t, g.run!.state.runClock, reason: 'ambient clock at 1×');
      },
    );

    test('the world reaches seam k exactly when hoop 20·k reaches the centre (310 spacing)', () {
      final planes = [for (var i = 0; i < 90; i++) 290.0 + 310 * i];
      final a = _Planes(planes);
      final w = WorldDistance()..start(160, 0, planes[0], 310);
      var c = 160.0;
      final landed = <int>[];
      for (final k in [1, 2, 3, 4]) {
        final x = planes[20 * k];
        while (c < x) {
          a.c = c;
          final next = c + 2.5 > x ? x : c + 2.5;
          w.advance(next, a);
          c = next;
        }
        expect(w.w, closeTo(k * kE, 1e-6), reason: 'hoop ${20 * k}');
        landed.add(k);
      }
      expect(landed, [1, 2, 3, 4]);
    });
  });
}

/// Records the stages a world paint draws (a whole group = a plain scene).
class _RecWorld extends BackdropWorld {
  final groups = <int>[];

  @override
  void group(Ctx c, int env, List<Band> bands, [BandOffset? dy]) => groups.add(env);
}

class _Planes implements HoopAnchors {
  _Planes(this.planes);
  final List<double> planes;
  double c = 0;

  @override
  int get nextIndex {
    var i = 0;
    while (i < planes.length - 1 && planes[i] < c + 700) {
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
