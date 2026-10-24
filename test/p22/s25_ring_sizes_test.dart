import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/fever_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/saw_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/black_hole.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p231/tuning_23.dart';

/// PRD-2.2 §25 Special rings shrink like normal rings: saw rings have the
/// normal opening, the saw / FEVER decoration scales with the ring
/// (`ry / ryDesign`), the portal ring stays 118 pt.
void main() {
  // PRD-2.3.1 §0: the forced saw slots are measured on the 2.3 spawn set
  // (test/p231/tuning_23.dart); the live set has its own checks.
  setUp(() => useTuning(tuning23Spawn()));
  tearDown(resetTuning);
  const hoops = [30, 45, 70];

  RunDirector director(int start, List<ElementId> forced, {RideId? ride}) =>
      RunDirector(
        seed: 7,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
        startHoopIndex: start,
        forced: forced,
        forcedRide: ride,
      );

  group('§25 openings (pure)', () {
    test('§25 sawExtraOpening = 0; decoration designed at 146 (saw) / 118 '
        '(FEVER) pt', () {
      expect(RunConfig.sawExtraOpening, 0);
      expect(SawConfig.ryDesign, RingPainter.ryFor(146));
      expect(FeverConfig.ryDesign, RingPainter.ryFor(118));
      expect(SawHoopKind.decorScaleFor(146), closeTo(1, 1e-12));
      expect(FeverRingPainter.decorScaleFor(118), closeTo(1, 1e-12));
    });

    for (final mult in [1.0, RunConfig.bigHoopsMult]) {
      test('§25 at hoops 30 / 45 / 70 a saw ring\'s opening equals a normal '
          'ring\'s (± 0.5 pt), Big Hoops ×$mult', () {
        for (final i in hoops) {
          final ctx = DirectorContext.open(711, bigHoopsMult: mult);
          final saw = director(i, [ElementId.saw]).nextSlot(ctx);
          expect(saw.kind, HoopKindId.saw, reason: 'hoop $i');
          expect(saw.index, i);
          // The unforced slot at the same index (a normal ring or a special
          // that uses the normal opening).
          final normal = director(i, const []).nextSlot(ctx);
          expect(normal.index, i);
          expect(saw.opening, closeTo(normal.opening, .5), reason: 'hoop $i');
          expect(
            saw.opening,
            closeTo(RunConfig.openingFor(i) * mult, .5),
            reason: 'hoop $i',
          );
        }
      });
    }

    test('§25 the portal ring stays 118 pt at every hoop', () {
      expect(RunConfig.portalOpening, 118);
      for (final i in [30, 45, 70, 120]) {
        final d = director(i, const [], ride: RideId.space);
        final s = d.nextSlot(DirectorContext.open(711));
        expect(s.kind, HoopKindId.portal, reason: 'hoop $i');
        expect(
          s.opening,
          closeTo(RunConfig.portalOpening, .5),
          reason: 'hoop $i',
        );
      }
    });

    test('PRD-2.4 §2.3 the portal keeps 118 pt × Big Hoops, unchanged from '
        '2.3.1', () {
      for (final i in [30, 45, 70, 120]) {
        final d = director(i, const [], ride: RideId.space);
        final s = d.nextSlot(
          DirectorContext.open(711, bigHoopsMult: RunConfig.bigHoopsMult),
        );
        expect(s.kind, HoopKindId.portal, reason: 'hoop $i');
        expect(
          s.opening,
          closeTo(RunConfig.portalOpening * RunConfig.bigHoopsMult, .5),
          reason: 'hoop $i',
        );
      }
    });
  });

  group('§25 decoration scales with the ring (drawn bounds)', () {
    final o20 = RunConfig.openingFor(20), o70 = RunConfig.openingFor(70);

    test('§25 FEVER: the hoop-70 decoration bounds are ry70 / ry20 of the '
        'hoop-20 bounds (± 5 %)', () async {
      Future<double> extent(double opening) => _drawnHalfHeight((c) {
        FeverRingPainter.paint(c, opening, 1.3, 5, 0, front: false);
        FeverRingPainter.paint(c, opening, 1.3, 5, 0, front: true);
      });
      final e20 = await extent(o20), e70 = await extent(o70);
      final want = RingPainter.ryFor(o70) / RingPainter.ryFor(o20);
      expect(e70 / e20, closeTo(want, want * .05));
      // The fixed (PRD-2) sizes would not shrink in step.
      final fixed =
          (RingPainter.ryFor(o70) + FeverConfig.haloExtra) /
          (RingPainter.ryFor(o20) + FeverConfig.haloExtra);
      expect((e70 / e20 - want).abs(), lessThan((e70 / e20 - fixed).abs()));
      // The helper agrees with the scale.
      expect(
        FeverRingPainter.decorExtent(o70) / FeverRingPainter.decorExtent(o20),
        closeTo(want, 1e-9),
      );
    });

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 9),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§25 Black Hole: the hoop-70 decoration bounds are ry70 / ry20 of the '
      'hoop-20 bounds (± 5 %)',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, tester) async {
        final RunController run = await startRun(game);
        run.state.runClock = 0; // outside the inhale for seed 3
        expect(SawHoopKind.hunger(0, 3), 0);
        SawRingState ring(double opening) {
          final h = Hoop(
            plan: SlotPlan(
              index: 20,
              kind: HoopKindId.saw,
              element: ElementId.saw,
              trackX: 9000,
              centreY: 300,
              opening: opening,
              advance: 310,
              extra: SawDesign.blackHole,
            ),
            kind: SawHoopKind(),
          );
          return SawRingState(h, run.ctx, const BlackHoleArt(), seed: 3);
        }

        final s20 = ring(o20), s70 = ring(o70);
        expect(
          s70.decor / s20.decor,
          closeTo(RingPainter.ryFor(o70) / RingPainter.ryFor(o20), 1e-9),
        );
        late double e20, e70;
        await tester.runAsync(() async {
          e20 = await _drawnHalfHeight((c) {
            const BlackHoleArt().paintBack(c, s20);
            const BlackHoleArt().paintFront(c, s20);
          });
          e70 = await _drawnHalfHeight((c) {
            const BlackHoleArt().paintBack(c, s70);
            const BlackHoleArt().paintFront(c, s70);
          });
        });
        final want = s70.ry / s20.ry;
        expect(e70 / e20, closeTo(want, want * .05));
        final fixed =
            (s70.ry + SawConfig.holeVoid) / (s20.ry + SawConfig.holeVoid);
        expect((e70 / e20 - want).abs(), lessThan((e70 / e20 - fixed).abs()));
      },
    );
  });
}

/// Paints [draw] centred in a 480 × 480 picture and returns the half height
/// (pt) of the rows holding a pixel with alpha ≥ 24 / 255.
Future<double> _drawnHalfHeight(void Function(ui.Canvas) draw) async {
  const size = 480;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.translate(size / 2, size / 2);
  draw(c);
  final img = await rec.endRecording().toImage(size, size);
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  final px = data.buffer.asUint8List();
  int? top, bottom;
  for (var y = 0; y < size; y++) {
    if (_rowHas(px, y, size)) {
      top ??= y;
      bottom = y;
    }
  }
  expect(top, isNotNull);
  expect(top, greaterThan(0), reason: 'clipped');
  expect(bottom, lessThan(size - 1), reason: 'clipped');
  return (bottom! - top! + 1) / 2;
}

bool _rowHas(Uint8List px, int y, int w) {
  for (var x = 0; x < w; x++) {
    if (px[(y * w + x) * 4 + 3] >= 24) return true;
  }
  return false;
}
