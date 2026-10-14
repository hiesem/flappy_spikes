import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/switch/switch_kind.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot;
import '../p231/tuning_23.dart';

/// WP-G2 visual checks (written to `build/menu_shots/p22/`, never
/// committed): the §27.3 reward rings losing their reward parts, the §23
/// egg break, the §15.1 pop-in and the §15 Power Iris cable drawn from the
/// planned-ahead ring.
Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

final Map<String, Object> _allMet = {
  'metElements': [for (final e in ElementId.values) e.storageId],
};

FlameTester<FlappySpikesGame> _tester() => FlameTester<FlappySpikesGame>(
  () => createRunTestGame(worldHeight: 711, seed: 5, prefs: _allMet),
  gameSize: Vector2(320, 711),
);

void _step(FlappySpikesGame g, double s) {
  for (var t = 0.0; t < s - 1e-9; t += 1 / 60) {
    g.update(1 / 60);
  }
}

/// Flies (god mode) until a [kind] hoop is fully on screen ahead.
Future<Hoop> _onScreen(
  FlappySpikesGame game,
  RunController run,
  HoopKindId kind,
  ElementId force,
) async {
  Hoop? found;
  await flyUntil(game, (r) {
    for (final h in r.spawner.hoops) {
      final x = h.planeX - r.state.camX;
      if (h.plan.kind == kind && x > 150 && x < 260) found = h;
    }
    if (found == null && !r.director.forcedQueue.contains(force)) {
      r.debugForce(force);
    }
    return found != null;
  }, maxSeconds: 30);
  return found!;
}

void main() {
  for (final (kind, force) in [
    (HoopKindId.pair, ElementId.pair),
    (HoopKindId.fever, ElementId.fever),
    (HoopKindId.luckySpin, ElementId.luckySpin),
  ]) {
    _tester().testGameWidget(
      '§27.3 shot: a ${kind.name} ring loses its reward parts',
      setUp: (g, _) => _boot(g),
      verify: (game, tester) async {
        game.runDebug.god = true;
        final run = await startRun(game, startHoopIndex: 20, force: [force]);
        final h = await _onScreen(game, run, kind, force);
        await flushAndMount(game);
        await tester.runAsync(() => captureShot(game, 1.5, 'p22/s27_${kind.name}_0_before'));
        h.stripReward();
        _step(game, .1);
        await tester.runAsync(() => captureShot(game, 1.5, 'p22/s27_${kind.name}_1_fading'));
        _step(game, .2);
        await tester.runAsync(() => captureShot(game, 1.5, 'p22/s27_${kind.name}_2_plain'));
        expect(h.rewardAlpha, 0);
      },
    );
  }

  _tester().testGameWidget(
    '§23 shot: the egg breaks on a rim',
    setUp: (g, _) => _boot(g),
    verify: (game, tester) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      run.events.emit(const PickupCollected(ElementId.egg, null));
      _step(game, .3);
      await flushAndMount(game);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s23_egg_0_carried'));
      final h = run.spawner.hoops.first;
      run.events.emit(RimTouched(h, Vector2(h.planeX, 300), Vector2(0, 1)));
      _step(game, .12);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s23_egg_1_break'));
      _step(game, .2);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s23_egg_2_falling'));
      expect(run.state.egg, isNull);
    },
  );

  _tester().testGameWidget(
    '§15.1 shot: a follow-up created inside the screen pops in',
    setUp: (g, _) => _boot(g),
    verify: (game, tester) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      final b = run.birdTrackPosition()!;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: b.x + 70,
          toTrackX: b.x + 205,
          y: b.y,
          toY: b.y - 20,
          extra: 4,
        ),
      );
      await flushAndMount(game);
      _step(game, .08);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s15_popin_0_growing'));
      _step(game, .08);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s15_popin_1_overshoot'));
      _step(game, .2);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s15_popin_2_done'));
    },
  );

  _tester().testGameWidget(
    '§15 shot: a Power Iris switch on screen before its ring spawns draws '
    'its cable toward the planned ring',
    setUp: (g, _) {
      // PRD-2.3.1 §0: framed on the 2.3 spawn set (the live portal sits at
      // hoop 12–25, right where this run starts).
      useTuning(tuning23Spawn());
      addTearDown(resetTuning);
      return _boot(g);
    },
    verify: (game, tester) async {
      game.runDebug.god = true;
      final run = await startRun(game, startHoopIndex: 14);
      run.director.debugForceSwitchDesign(SwitchDesign.powerIris);
      run.debugForce(ElementId.switchRing);
      SwitchPickup? sw;
      await flyUntil(game, (r) {
        sw = r.spawner.pickups.whereType<SwitchPickup>().firstOrNull;
        final p = sw;
        return p != null &&
            p.ring == null &&
            p.position.x - r.state.camX < 290;
      }, maxSeconds: 20);
      expect(sw?.ringPlan, isNotNull);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s15_iris_cable_planned'));
      await flyUntil(game, (_) => sw!.ring != null, maxSeconds: 3);
      _step(game, .1);
      await tester.runAsync(() => captureShot(game, 1.5, 'p22/s15_iris_cable_linked'));
      expect(RunConfig.worldWidth, 320);
    },
  );
}
