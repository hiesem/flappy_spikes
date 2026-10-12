import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/saw_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/features.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_death.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/items/scoring.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3d: saw rings (PRD-2 §3.18, §5.17, §3.0.5 themed deaths).
void main() {
  group('§3.18 rules (pure)', () {
    test('§3.18 rim-end collider r = half the rim: 5 (Live Wire / Frost), 6 '
        '(Black Hole); PRD-2.2 §25: no extra opening; only the rim is the '
        'hitbox', () {
      expect(SawConfig.rimRadius(SawDesign.liveWire), 5);
      expect(SawConfig.rimRadius(SawDesign.frostRing), 5);
      expect(SawConfig.rimRadius(SawDesign.blackHole), 6);
      expect(RunConfig.sawExtraOpening, 0); // PRD-2.2 §25 (PRD-2: 28)
      final kind = SawHoopKind();
      expect(kind.usesTierLook, isFalse);
      for (final d in SawDesign.values) {
        final h = Hoop(plan: _plan(d), kind: kind);
        final f = h.frame();
        expect(f.rimR, SawConfig.rimRadius(d));
        expect(f.reach, h.opening / 2 + SawConfig.rimRadius(d));
        expect(f.rimEnd(0, -1).y, 300 - (h.opening / 2 + f.rimR));
      }
    });

    test('§3.18 the rim is deadly (no bounce); rides (comet / portal) fly '
        'through it', () {
      final kind = SawHoopKind();
      final h = Hoop(plan: _plan(SawDesign.frostRing), kind: kind);
      final s = RunState(seed: 1, viewHeight: 711, metElements: {});
      expect(kind.rimMode(h, s), RimMode.deadly);
      s.ride = RideState(kind: RideKind.comet);
      expect(kind.rimMode(h, s), RimMode.ignored);
      s.ride = RideState(kind: RideKind.portal);
      expect(kind.rimMode(h, s), RimMode.ignored);
    });

    test('§3.0.5 / §5.17 themed deaths: Live Wire held 0.6 s, Frost Ring '
        '0.4 s, Black Hole 0.8 s and no body', () {
      final kind = SawHoopKind();
      ThemedDeath td(SawDesign d) =>
          kind.themedDeath(Hoop(plan: _plan(d), kind: kind))!;
      expect(td(SawDesign.liveWire).holdSeconds, .6);
      expect(td(SawDesign.liveWire).noBody, isFalse);
      expect(td(SawDesign.frostRing).holdSeconds, SawConfig.frostHold);
      expect(td(SawDesign.blackHole).holdSeconds, .8);
      expect(td(SawDesign.blackHole).noBody, isTrue);
    });

    test('§3.18 Black Hole pull: within 34 pt of the rim (bird edge) 260 '
        'pt/s² toward the rim; 570 at the inhale peak (0.9 s every 3.4 s)', () {
      final f = HoopFrame(centre: Vector2(400, 300), opening: 146, rimR: 6);
      final end = f.rimEnd(0, -1); // top end, y = 221
      const r = RunConfig.birdRadius;
      // Find a clock outside the inhale for seed 0.
      expect(SawHoopKind.hunger(0, 0), 0);
      // Just inside the range, below the top end: pulled up (toward it).
      final inside = Vector2(end.x, end.y + 34 + r - 1);
      expect(SawHoopKind.pullAt(f, inside, r, 0, 0), -260);
      // Above the bottom end: pulled down.
      final bot = f.rimEnd(0, 1);
      expect(SawHoopKind.pullAt(f, Vector2(bot.x, bot.y - 30), r, 0, 0), 260);
      // Outside the range: nothing (the centre of the opening is clear).
      expect(
        SawHoopKind.pullAt(f, Vector2(end.x, end.y + 34 + r + 1), r, 0, 0),
        0,
      );
      expect(SawHoopKind.pullAt(f, Vector2(400, 300), r, 0, 0), 0);
      // The inhale: 0.9 s every 3.4 s, peaking at 570.
      const peak = 3.4 - .9 / 2;
      expect(SawHoopKind.hunger(peak, 0), closeTo(1, 1e-9));
      expect(SawHoopKind.pullStrength(peak, 0), closeTo(570, 1e-6));
      expect(SawHoopKind.hunger(2.49, 0), 0);
      expect(SawHoopKind.hunger(2.6, 0), greaterThan(0));
      expect(SawHoopKind.hunger(3.4 + 1, 0), 0, reason: 'periodic');
      var inhale = 0.0;
      for (var t = 0.0; t < 3.4; t += .001) {
        if (SawHoopKind.hunger(t, 0) > 0) inhale += .001;
      }
      expect(inhale, closeTo(.9, .01));
    });

    test('§3.18 designs: each spawn picks one at random (all three used, '
        'about equally), never the same twice in a row within a run', () {
      final counts = <SawDesign, int>{};
      for (final seed in [1, 2, 3, 4, 5]) {
        final d = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet(),
          startHoopIndex: 20,
        );
        SawDesign? last;
        for (var i = 0; i < 300; i++) {
          d.debugForce(ElementId.saw);
          final s = d.nextSlot(DirectorContext.open(711));
          d.nextGap(DirectorContext.open(711), s);
          if (s.kind != HoopKindId.saw) continue;
          final design = s.extra! as SawDesign;
          expect(design, isNot(last), reason: 'seed $seed slot $i');
          last = design;
          counts[design] = (counts[design] ?? 0) + 1;
        }
      }
      expect(counts.keys.toSet(), SawDesign.values.toSet());
      final total = counts.values.fold(0, (a, b) => a + b);
      for (final c in counts.values) {
        expect(c / total, closeTo(1 / 3, .06));
      }
    });
  });

  group('§3.18 in a run', () {
    late AnalyticsSpy spy;
    FlameTester<FlappySpikesGame> tester({
      double h = 711,
      Map<String, Object> prefs = const {},
    }) => FlameTester<FlappySpikesGame>(() {
      spy = AnalyticsSpy();
      return createRunTestGame(
        worldHeight: h,
        services: spy,
        seed: 9,
        prefs: prefs,
      );
    }, gameSize: Vector2(320, h));

    Future<void> prepare(FlappySpikesGame g) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    }

    Future<(RunController, Hoop)> sawRun(
      FlappySpikesGame game, {
      SawDesign? design,
      Powerup starter = Powerup.none,
    }) async {
      final run = await startRun(
        game,
        startHoopIndex: 20,
        force: [ElementId.saw],
        starter: starter,
      );
      final h = await flyToHoop(
        game,
        HoopKindId.saw,
        ElementId.saw,
        where: design == null ? null : (h) => SawHoopKind.designOf(h) == design,
      );
      expect(h, isNotNull);
      return (run, h!);
    }

    tester().testGameWidget(
      '§3.18 a clean pass is an ordinary, always-perfect hoop: +1, +2 coins, '
      'streak +1, sawring_spawned / sawring_passed {design}; the opening is '
      'a normal hoop\'s at the same index (PRD-2.2 §25)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await sawRun(game);
        expect(
          h.opening,
          closeTo(
            run.director.openingFor(h.plan.index, ride: false),
            1e-9,
          ),
        );
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final score = run.state.score, streak = run.state.streak;
        expect(await passHoopAt(game, h), isTrue);
        expect(h.takenRing, 0);
        // PRD-2.2 §13.1 a perfect pass: max(2, streak) points.
        expect(
          run.state.score,
          score + ScoringFeature.pointsFor(perfect: true, streak: streak + 1),
        );
        expect(run.state.streak, streak + 1);
        final passed = events.whereType<HoopPassed>().single;
        expect(passed.perfect, isTrue);
        expect(
          events.whereType<CoinsEarned>().single.source,
          CoinSource.perfect,
        );
        final names = spy.events.map((e) => e.$1).toList();
        expect(names, containsAll(['sawring_spawned', 'sawring_passed']));
        final design = SawHoopKind.storageName(SawHoopKind.designOf(h));
        expect(spy.events.firstWhere((e) => e.$1 == 'sawring_passed').$2, {
          'design': design,
        });
        // §3.18 / §5.17 its own look: no tier fx, no gold.
        expect(h.look.colors, isNull);
        expect(game.storage.metElements, contains('saw'));
      },
    );

    for (final design in SawDesign.values) {
      tester().testGameWidget(
        '§3.18 / §3.0.5 touching the ${design.name} rim kills (no bounce, no '
        'miss flash): the design moment holds the bird, then '
        '${design == SawDesign.blackHole ? 'it is swallowed' : 'the tumble'}; '
        'sawring_death {used: none}',
        setUp: (g, _) => prepare(g),
        verify: (game, _) async {
          final (run, h) = await sawRun(game, design: design);
          final events = <RunEvent>[];
          run.events.onAny(events.add);
          final ry = h.opening / 2 + h.kind.rimRadius(h);
          final score = run.state.score;
          await glideInto(
            game,
            h,
            h.position.y + ry,
            seconds: .2,
            until: (r) => r.dying,
          );
          expect(run.dying, isTrue);
          final died = events.whereType<RunDied>().single;
          expect(died.mistake.cause, MistakeCause.saw);
          expect(died.mistake.themed, isNotNull);
          expect(events.whereType<RimTouched>(), isEmpty, reason: 'no bounce');
          expect(events.whereType<HoopMissed>(), isEmpty, reason: 'no flash');
          expect(h.look.missed, isFalse);
          expect(run.state.score, score, reason: 'no score');
          expect(h.resolved, isTrue);
          final saw = run.features.whereType<SawFeature>().single;
          expect(saw.death, isNotNull);
          expect(spy.events.lastWhere((e) => e.$1 == 'sawring_death').$2, {
            'design': SawHoopKind.storageName(design),
            'used': 'none',
          });
          // The held moment: the bird stays where it was hit (± the jitter
          // / the pull), the world eases to a stop.
          final bird = game.runBird!;
          final hitY = bird.body.position.y;
          final hold = died.mistake.themed!.holdSeconds;
          var t = 0.0;
          while (t < hold - .05) {
            game.update(1 / 60);
            t += 1 / 60;
          }
          if (design == SawDesign.liveWire) {
            expect((bird.body.position.y - hitY).abs(), lessThanOrEqualTo(3.5));
            expect(bird.deathTint, isNotNull);
          }
          if (design == SawDesign.frostRing) {
            expect(bird.body.position.y, closeTo(hitY, .01));
            expect(bird.deathTint, SawConfig.frostTint);
          }
          expect(
            run.tumble!.time,
            0,
            reason: 'the tumble waits for the moment',
          );
          // After the moment.
          for (var i = 0; i < 30; i++) {
            game.update(1 / 60);
          }
          if (design == SawDesign.blackHole) {
            expect(saw.death!.swallowed, isTrue);
            expect(bird.spriteOpacity, 0, reason: 'no body');
            expect(run.tumble!.time, 0, reason: 'no tumble');
          } else {
            expect(run.tumble!.time, greaterThan(0));
          }
          // The revive offer / results come at most 2.2 s after the hit.
          var after = hold + 30 / 60;
          while (game.state == GameState.dying && after < 3) {
            game.update(1 / 60);
            after += 1 / 60;
          }
          expect(game.state, isNot(GameState.dying));
          expect(after, lessThanOrEqualTo(2.2 + 1e-6));
          if (design == SawDesign.frostRing) {
            expect(
              saw.death!.shattered,
              isTrue,
              reason: 'the ice block shatters on the floor spikes',
            );
          }
        },
      );
    }

    tester().testGameWidget(
      '§3.18 with an armed shield the touch is saved: the ring counts as '
      'passed (no score), the bird flies on; sawring_death {used: shield}',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await sawRun(game, starter: Powerup.shield);
        expect(run.state.shield, isTrue);
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final score = run.state.score;
        final ry = h.opening / 2 + h.kind.rimRadius(h);
        await glideInto(game, h, h.position.y - ry, seconds: .3);
        expect(run.dying, isFalse);
        expect(
          events.whereType<MistakeSaved>().single.mistake.cause,
          MistakeCause.saw,
        );
        expect(h.resolved, isTrue);
        expect(h.takenRing, isNull, reason: 'treated as passed, no score');
        expect(run.state.score, score);
        expect(run.state.shield, isFalse);
        expect(spy.events.lastWhere((e) => e.$1 == 'sawring_death').$2, {
          'design': SawHoopKind.storageName(SawHoopKind.designOf(h)),
          'used': 'shield',
        });
      },
    );

    tester(prefs: const {'coins': 5000}).testGameWidget(
      '§3.14 / §3.0.5 a revive after a Black Hole death: the phoenix re-forms '
      'the swallowed bird (look restored); after a Live Wire death the '
      'charred tint is gone',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        for (final design in [SawDesign.blackHole, SawDesign.liveWire]) {
          final (run, h) = game.run == null
              ? await sawRun(game, design: design)
              : (
                  game.run!,
                  (await flyToHoop(
                    game,
                    HoopKindId.saw,
                    ElementId.saw,
                    where: (x) => SawHoopKind.designOf(x) == design,
                  ))!,
                );
          run.state.invulnerable = 0;
          for (var i = 0; i < 6; i++) {
            run.debugPass(perfect: true);
          }
          final ry = h.opening / 2 + h.kind.rimRadius(h);
          await glideInto(
            game,
            h,
            h.position.y + ry,
            seconds: .3,
            until: (r) => r.dying,
          );
          expect(run.lastDeath!.themed!.noBody, design == SawDesign.blackHole);
          var t = 0.0;
          while (game.state == GameState.dying && t < 3) {
            game.update(1 / 60);
            t += 1 / 60;
          }
          await flushAndMount(game);
          expect(game.state, GameState.reviving);
          final screen = game.reviveScreen!;
          for (var i = 0; i < 30; i++) {
            game.update(1 / 60);
          }
          screen.tapHeart();
          for (var i = 0; i < 400 && game.state == GameState.reviving; i++) {
            game.update(1 / 60);
            await flushAndMount(game);
          }
          expect(game.state, GameState.playing);
          final bird = game.runBird!;
          expect(bird.spriteOpacity, closeTo(1, 1e-9));
          expect(bird.lookComponent.scale, Vector2.all(1));
          expect(bird.deathTint, isNull);
          expect(run.themedPose, isNull);
          expect(run.features.whereType<SawFeature>().single.death, isNull);
        }
      },
    );

    tester().testGameWidget(
      '§3.18 the Black Hole pulls a bird near its rim toward it',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await sawRun(game, design: SawDesign.blackHole);
        await flyUntil(game, (r) {
          final b = r.birdTrackPosition();
          return b != null && h.planeX - b.x <= 30;
        });
        final ry = h.opening / 2 + h.kind.rimRadius(h);
        // 20 pt under the top rim end, still: the pull speeds it upward.
        game.runBird!.setFlight(y: h.position.y - ry + 30, vy: 0);
        final v0 = game.runBird!.body.linearVelocity.y;
        game.update(1 / 60);
        final v1 = game.runBird!.body.linearVelocity.y;
        // Gravity alone would add +20.8 pt/s; the pull (≥ 260 pt/s²) makes
        // it at least 4.3 pt/s smaller.
        expect(v1 - v0, lessThan(RunConfig.gravity / 60 - 4));
        expect(
          run.features.whereType<SawFeature>().single.lensOn(game),
          isTrue,
          reason: '§5.17 the strips bend toward it',
        );
      },
    );

    tester().testGameWidget(
      '§5.17 the danger hum fades in with the approach (volume ∝ '
      'closeness²) and is gone after the death',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await sawRun(game);
        final saw = run.features.whereType<SawFeature>().single;
        final d = SawHoopKind.designOf(h);
        await flyUntil(game, (r) => h.planeX - r.state.camX <= 200);
        final far = saw.humVolumes[d] ?? 0;
        await flyUntil(game, (r) => h.planeX - r.state.camX <= 110);
        final near = saw.humVolumes[d] ?? 0;
        expect(far, greaterThan(0));
        expect(near, greaterThan(far));
        const span =
            RunConfig.worldWidth - RunConfig.birdX + SawConfig.humAhead;
        final k = 1 - (h.planeX - run.state.camX - RunConfig.birdX) / span;
        expect(near, closeTo(k * k * SawConfig.humGain, .06));
        killRun(game);
        game.update(1 / 60);
        expect(saw.humVolumes, isEmpty);
      },
    );
  });

  test('§3.18 the feature list carries the saw feature', () {
    expect(buildRunFeatures().whereType<SawFeature>(), hasLength(1));
  });
}

SlotPlan _plan(SawDesign d) => SlotPlan(
  index: 20,
  kind: HoopKindId.saw,
  element: ElementId.saw,
  trackX: 400,
  centreY: 300,
  opening: 146,
  advance: 310,
  extra: d,
);
