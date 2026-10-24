import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.4 §4 test 4 (§2 no jumps): fly 120 hoops with the autopilot and
/// forced comets and portals. Leaving out the portals and the saws, the
/// sequence of normal openings never grows from one hoop to the next. With
/// Big Hoops on, each opening is divided by the multiplier it was planned
/// with (the multiplier eases over the last 8 s; the planning frame can be
/// one frame off, hence the 1 % slack).
void _noJumps({required bool bigHoops}) {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§2 no jumps: over 120 hoops with forced comets and portals, the normal '
    'openings never grow from one hoop to the next'
    '${bigHoops ? ' (Big Hoops, divided by the multiplier)' : ''}',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        force: [ElementId.comet, ElementId.portal],
        starter: bigHoops ? Powerup.bigHoops : Powerup.none,
      );
      // Big Hoops: 1.5 from the start, eased back over the last 8 s of 60.
      final big = BigHoopsState(duration: 60, start: 0);
      if (bigHoops) run.state.bigHoops = big;
      // Fly (autopilot) until hoops 0–119 are planned. The clock of each
      // slot's planning frame is kept for the multiplier.
      final planned = <int, double>{};
      final bot = Autopilot(run);
      for (var f = 0; f < 400 * 60 && run.state.hoopIndex < 120; f++) {
        for (final p in run.spawner.slotLog) {
          planned.putIfAbsent(p.index, () => run.state.runClock);
        }
        if (bot.shouldFlap()) game.onScreenTap();
        game.update(1 / 60);
        if (f % 10 == 0) await flushAndMount(game);
      }
      expect(run.state.hoopIndex, greaterThanOrEqualTo(120));
      expect(run.ended, isFalse, reason: 'god mode: the run keeps going');
      final plans = run.spawner.slotLog.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(plans.any((p) => p.kind == HoopKindId.portal), isTrue);
      expect(
        plans.any((p) => p.kind == HoopKindId.saw),
        isTrue,
        reason: 'the saw is left out, but it is in the run',
      );
      expect(plans.any((p) => p.duringRide), isTrue, reason: 'a comet came');
      final normal = [
        for (final p in plans)
          if (p.index > 0 &&
              p.kind != HoopKindId.portal &&
              p.kind != HoopKindId.saw &&
              p.kind != HoopKindId.rideRing)
            p,
      ];
      expect(normal.length, greaterThan(100));
      double normalised(SlotPlan p) {
        final m = bigHoops ? big.mult(planned[p.index] ?? 0) : 1.0;
        final tilt45Extra = p.tiltDeg.abs() == 45
            ? TuningValues.current.i('tilt45_extra_opening')
            : 0;
        return (p.opening - tilt45Extra) / m;
      }

      final slack = bigHoops ? 0.01 : 0.0;
      for (var k = 1; k < normal.length; k++) {
        final prev = normal[k - 1], cur = normal[k];
        expect(
          normalised(cur),
          lessThanOrEqualTo(normalised(prev) * (1 + slack) + 1e-9),
          reason:
              'the opening grows from hoop ${prev.index} (${prev.kind.name}, '
              '${prev.duringRide ? 'ride' : 'normal'}) to hoop ${cur.index} '
              '(${cur.kind.name}, ${cur.duringRide ? 'ride' : 'normal'})',
        );
      }
    },
  );
}

void main() {
  group('PRD-2.4 §2 no jumps', () {
    _noJumps(bigHoops: false); // test 4
    _noJumps(bigHoops: true); // test 4 with Big Hoops
  });
}
