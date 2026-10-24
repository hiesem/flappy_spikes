import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/perfect_burst.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/normal.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2b: the perfect-pass streak (PRD-2 §3.4), the ring field's tier
/// reactions (§3.5), the banner sequence (§3.0.9 #7 / §5.4), the burst
/// counts (#9), the gold bird (#5), the trail (#10), a graze (§5.3; no text
/// since PRD-2.3.1 §8) and "no screen flash" (#13).
void main() {
  late AnalyticsSpy spy;

  Future<void> prepare(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  Future<RunController> boot(FlappySpikesGame game) async {
    final run = await startRun(game);
    run.events.recordLog = true;
    return run;
  }

  StreakFeature streakOf(RunController run) =>
      run.features.whereType<StreakFeature>().single;

  /// One perfect / graze pass of no particular hoop, then a frame.
  void pass(FlappySpikesGame g, {bool perfect = true}) {
    g.run!.debugPass(perfect: perfect);
    g.update(1 / 60);
  }

  Iterable<Hoop> tierHoops(RunController run) =>
      run.spawner.hoops.where((h) => h.kind.usesTierLook && !h.look.missed);

  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy);
  }, gameSize: Vector2(320, 711));

  tester.testGameWidget(
    '§3.4 perfect passes build the streak; 10 tiers (effects) capped at 10; '
    'banner sequence (PRD-2.2 §29 names), tier sounds and analytics per pass',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final sfx = sfxLog(game);
      final streak = streakOf(run);
      final names = <String>[];
      for (var i = 0; i < 12; i++) {
        pass(game);
        final b = streak.banners!.current;
        expect(b, isA<StreakBanner>());
        names.add((b! as StreakBanner).text);
      }
      expect(names, [
        'PERFECT',
        'GREAT ×2',
        'ON FIRE ×3',
        'AMAZING ×4',
        'SOARING ×5',
        'SKY HIGH ×6',
        'HIGH FLYER ×7',
        'FEATHERLIGHT ×8',
        'EAGLE EYE ×9',
        'FREE BIRD ×10',
        'TAILWIND ×11',
        'SKYLARK ×12',
      ]);
      expect(run.state.streak, 12);
      expect(run.state.tier, 10);
      expect(run.state.bestStreak, 12);
      // §3.4 sounds: perfect_1, perfect_2, then perfect_3 for every higher
      // tier; a perfect pass never plays `point`.
      final tierSfx = sfx.where((s) => s.startsWith('perfect')).toList();
      expect(tierSfx, [
        'perfect1',
        'perfect2',
        for (var i = 0; i < 10; i++) 'perfect3',
      ]);
      expect(sfx, isNot(contains('point')));
      // PRD-2.6 WP-A1: no per-pass perfect_pass event any more; its tier
      // counts are sent once in run_extra at run end.
      expect(spy.events.where((e) => e.$1 == 'perfect_pass'), isEmpty);
      // §2.4 StreakChanged per pass, TierChanged up to the cap only.
      final log = run.events.log;
      expect(log.whereType<StreakChanged>(), hasLength(12));
      expect(log.whereType<TierChanged>().map((e) => e.newTier), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
    },
  );

  tester.testGameWidget(
    '§3.0.9 #9 perfect burst at the bird: 11 / 14 / 17 squares, then 17',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final pool = streakOf(run).burstPool!;
      final counts = <int>[];
      for (var i = 0; i < 5; i++) {
        // Fade the previous burst out (the pool steps itself; no hoop is
        // reached meanwhile).
        for (var f = 0; f < 45; f++) {
          pool.update(1 / 60);
        }
        expect(pool.alive, 0);
        run.debugPass(perfect: true);
        counts.add(pool.alive);
        // Centred on the bird (screen space, §5.3 `pop`).
        final bird = game.runBirdPosition!;
        for (final p in pool.particles) {
          expect(p.x, closeTo(bird.x, 1e-6));
          expect(p.y, closeTo(bird.y, 1e-6));
          expect(p.spin, 0, reason: 'no rotation');
        }
        game.update(1 / 60);
      }
      expect(counts, [11, 14, 17, 17, 17]);
      expect(PerfectBurst.countFor(10), 17);
    },
  );

  tester.testGameWidget(
    '§3.4 / PRD-2.3.1 §8 a graze resets the streak: point + pulse stay, no '
    'text, streak_broken (length)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final sfx = sfxLog(game);
      for (var i = 0; i < 4; i++) {
        pass(game);
      }
      sfx.clear();
      pass(game, perfect: false);
      expect(run.state.streak, 0);
      expect(run.state.tier, 0);
      expect(run.state.bestStreak, 4);
      expect(sfx, contains('point'));
      expect(sfx.where((s) => s.startsWith('perfect')), isEmpty);
      final changed = run.events.log.whereType<StreakChanged>().last;
      expect(changed.cause, StreakCause.graze);
      expect(changed.oldStreak, 4);
      final broken = spy.events.where((e) => e.$1 == 'streak_broken').single;
      expect(broken.$2, {'length': 4, 'cause': 'graze'});
      await flushAndMount(game);
      // PRD-2.3.1 §8: a graze adds no text to the HUD (the notice is gone).
      expect(
        game.runHud!.descendants().whereType<TextComponent>().map(
          (t) => t.text,
        ),
        isNot(contains('GRAZE · streak lost')),
      );
      // A graze with no streak running: no streak_broken.
      pass(game, perfect: false);
      await flushAndMount(game);
      expect(spy.events.where((e) => e.$1 == 'streak_broken'), hasLength(1));
    },
  );

  tester.testGameWidget(
    '§3.5 the whole ring field shows the tier (passed, ahead, newly '
    'spawned): sparkles, gold, bright gold + glow; a break resets at once',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final streak = streakOf(run);
      expect(tierHoops(run), isNotEmpty);
      Hoop first() => tierHoops(run).first;

      // Tier 0: skin colours, no fx.
      expect(first().look.colors, isNull);
      expect(streak.fxOf(first())!.single.tier, 0);

      pass(game); // tier 1: sparkles, ring stays pink
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      for (final h in tierHoops(run)) {
        expect(h.look.colors, isNull);
        final fx = streak.fxOf(h)!.single;
        expect(fx.tier, 1);
        expect(fx.pool.alive, greaterThan(0), reason: 'sparkles twinkle');
        expect(fx.glow, 0);
      }
      expect(game.runBird!.lookComponent.goldTier, isFalse);
      expect(streak.trailActive, isFalse);

      pass(game); // tier 2: gold rings + gold bird
      for (final h in tierHoops(run)) {
        expect(h.look.colors, RingColors.gold);
      }
      expect(game.runBird!.lookComponent.goldTier, isTrue);
      expect(streak.trailActive, isFalse);

      pass(game); // tier 3: bright gold, glow, flames, trail
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      for (final h in tierHoops(run)) {
        expect(h.look.colors, RingColors.brightGold);
        final fx = streak.fxOf(h)!.single;
        expect(fx.level, 3);
        expect(fx.glow, 1, reason: 'glow faded in over 0.25 s');
      }
      expect(streak.trailActive, isTrue);
      // The equipped trail (default Classic flame) is emitting.
      expect(streak.trail!.usesBlocks, isFalse);
      expect(streak.trail!.emitter.particleCount, greaterThan(0));

      // A ring spawned now appears in the current tier's look.
      final before = run.spawner.hoops.toSet();
      for (var i = 0; i < 600; i++) {
        game.runBird!.setFlight(y: game.viewHeight / 2, vy: 0);
        game.update(1 / 60);
        if (run.spawner.hoops.any((h) => !before.contains(h))) break;
      }
      final fresh = run.spawner.hoops.firstWhere((h) => !before.contains(h));
      if (fresh.kind.usesTierLook && !fresh.look.missed) {
        expect(fresh.look.colors, RingColors.brightGold);
        expect(streak.fxOf(fresh)!.single.tier, run.state.tier);
      }

      // §3.5 streak break: every ring back to pink, every effect gone.
      expect(run.state.streak, greaterThan(0));
      pass(game, perfect: false);
      for (final h in tierHoops(run)) {
        expect(h.look.colors, isNull);
        final fx = streak.fxOf(h)!.single;
        expect(fx.tier, 0);
        expect(fx.pool.alive, 0);
        expect(fx.glow, 0);
      }
      expect(game.runBird!.lookComponent.goldTier, isFalse);
      expect(streak.trailActive, isFalse);
    },
  );

  tester.testGameWidget(
    '§3.5 the streak keeps another owner\'s ring colours; a missed hoop '
    'stays out of the tier look (§5.13)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final streak = streakOf(run);
      final h = tierHoops(run).first;
      // Another owner (Big Hoops gold) set the colours.
      h.look.colors = const RingColors(Color(0xFF123456), Color(0xFF654321));
      pass(game);
      pass(game);
      expect(h.look.colors!.front, const Color(0xFF123456));
      // A missed hoop: no sparkles, no tier colours.
      h.look
        ..colors = null
        ..missed = true;
      game.update(1 / 60);
      pass(game);
      expect(streak.fxOf(h)!.single.tier, 0);
      expect(h.look.colors, isNull);
    },
  );

  tester.testGameWidget(
    '§3.4 a save or a death breaks the streak (MistakeSaved / RunDied); '
    'the dead bird is not gold',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      pass(game);
      pass(game);
      run.events.emit(
        const MistakeSaved(Mistake(MistakeCause.spikes), 'shield'),
      );
      expect(run.state.streak, 0);
      expect(
        run.events.log.whereType<StreakChanged>().last.cause,
        StreakCause.save,
      );
      expect(spy.events.where((e) => e.$1 == 'streak_broken').single.$2, {
        'length': 2,
        'cause': 'save',
      });
      pass(game);
      pass(game);
      expect(game.runBird!.lookComponent.goldTier, isTrue);
      killRun(game);
      expect(run.state.streak, 0);
      expect(game.runBird!.lookComponent.goldTier, isFalse);
      expect(
        run.events.log.whereType<StreakChanged>().last.cause,
        StreakCause.death,
      );
    },
  );

  tester.testGameWidget(
    '§3.19 a perfect FEVER pass sets the streak to max(5, streak + 1); a '
    'grazed FEVER pass resets it',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      Hoop fever() => Hoop(
        plan: const SlotPlan(
          index: 99,
          kind: HoopKindId.fever,
          element: ElementId.fever,
          trackX: 0,
          centreY: 355,
          opening: 118,
          advance: 310,
        ),
        kind: NormalHoopKind(),
      );
      pass(game);
      run.events.emit(HoopPassed(fever(), perfect: true));
      expect(run.state.streak, 5);
      expect(
        run.events.log.whereType<StreakChanged>().last.cause,
        StreakCause.fever,
      );
      run.events.emit(HoopPassed(fever(), perfect: true));
      expect(run.state.streak, 6);
      run.events.emit(HoopPassed(fever(), rimTouched: true));
      expect(run.state.streak, 0);
    },
  );

  tester.testGameWidget(
    '§3.0.9 #13 no screen flash on a perfect pass at any tier',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      await boot(game);
      for (var i = 0; i < 10; i++) {
        pass(game);
        await flushAndMount(game);
        expect(game.world.children.whereType<ScreenFlash>(), isEmpty);
      }
    },
  );
}
