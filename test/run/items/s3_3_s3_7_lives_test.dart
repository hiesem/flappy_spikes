import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/lives_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/extra_life.dart';
import 'package:flappy_spikes/run/items/invulnerability.dart';
import 'package:flappy_spikes/run/items/shield.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/heart_pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/pickups/shield_pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2a: hearts, the extra life and the shield (PRD-2 §3.3, §3.7, §3.9,
/// §5.2, §5.5) in the real game.
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  T feature<T>(RunController r) => r.features.whereType<T>().single;

  void heart(RunController r) =>
      r.events.emit(const PickupCollected(ElementId.heart, null));

  /// Steps [seconds] keeping the bird level at the centre (no hoop is
  /// reached in the first ≈ 2 s of a run).
  void hold(FlappySpikesGame g, double seconds) {
    final h = g.viewHeight;
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      g.runBird!.setFlight(y: h / 2, vy: 0);
      g.update(1 / 60);
    }
  }

  test('§3.3 the real heart and shield kinds are registered (WP-2a)', () {
    expect(pickupKindFor(ElementId.heart), isA<HeartPickupKind>());
    expect(pickupKindFor(ElementId.shield), isA<ShieldPickupKind>());
    expect(
      registeredPickupElements(),
      containsAll([ElementId.heart, ElementId.shield]),
    );
  });

  test('§5.2 the heart pickup pulses 1.0 ↔ 1.14 over 1 s; hit radius 16', () {
    expect(HeartPickup.pulseAt(0), closeTo(1, 1e-9));
    expect(HeartPickup.pulseAt(.5), closeTo(1.14, 1e-9));
    expect(HeartPickup.pulseAt(1), closeTo(1, 1e-9));
    final p = HeartPickup(
      const GapItemPlan(kind: ElementId.heart, trackX: 0, y: 0),
    );
    expect(p.hitRadius, 16);
    final s = ShieldPickup(
      const GapItemPlan(kind: ElementId.shield, trackX: 0, y: 0),
    );
    expect(s.hitRadius, 18);
  });

  for (final h in [568.0, 711.0]) {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, services: spy),
      gameSize: Vector2(320, h),
    );

    tester.testGameWidget(
      '§3.3 ($h) three hearts give one extra life: 1/3, 2/3 (pu_heart_1), '
      'the 3rd (pu_heart_2) → extra life, hearts back to 0, the badge pops '
      'in over the bird; a 4th heart does not stack',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        final sfx = sfxLog(game);
        final badge = feature<ExtraLifeFeature>(run).badge!;
        heart(run);
        expect((run.state.hearts, run.state.extraLife), (1, false));
        heart(run);
        expect((run.state.hearts, run.state.extraLife), (2, false));
        expect(badge.shown, isFalse);
        heart(run);
        expect((run.state.hearts, run.state.extraLife), (0, true));
        expect(sfx, ['puHeart1', 'puHeart1', 'puHeart2']);
        // §5.5 the heart first flies to the indicator, then the badge pops
        // in over 0.35 s.
        game.update(1 / 60);
        expect(badge.born, 0);
        hold(game, LivesConfig.formDelay + LivesConfig.popIn + .05);
        expect(badge.born, 1);
        final bird = game.runBird!.body.position;
        expect(badge.centre!.dy, closeTo(bird.y - 41, 4.01));
        expect(badge.centre!.dx, bird.x);
        heart(run);
        expect((run.state.hearts, run.state.extraLife), (0, true));
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'heart_collected').length,
          4,
        );
      },
    );

    tester.testGameWidget(
      '§3.3 ($h) the extra life forgives one mistake: badge pops into '
      'hearts, indicator 0/3, pu_heart_use, 2 s invulnerability with the '
      'flash, keep playing; the next mistake after the 2 s ends the run',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.events.recordLog = true;
        final sfx = sfxLog(game);
        for (var i = 0; i < 3; i++) {
          heart(run);
        }
        hold(game, .8);
        final before = run.particles.alive;
        final out = run.mistake(const Mistake(MistakeCause.missedHoop));
        expect(out, MistakeOutcome.saved);
        expect(run.state.extraLife, isFalse);
        expect(run.state.hearts, 0);
        expect(run.state.invulnerable, LivesConfig.invulnerable);
        expect(run.state.saves, 1);
        expect(sfx.last, 'puHeartUse');
        final saved = run.events.log.whereType<MistakeSaved>().single;
        expect(saved.by, 'extra_life');
        expect(feature<ExtraLifeFeature>(run).badge!.shown, isFalse);
        // 1 flash disc + 12 small hearts.
        expect(run.particles.alive - before, 13);
        expect(
          run.particles.particles.where((p) => p.shape == ParticleShape.heart),
          hasLength(12),
        );
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'extra_life_used').single.$2,
          {'cause': 'missed_hoop'},
        );
        // §3.3 3: invulnerable — further mistakes do nothing.
        hold(game, .15);
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.ignored,
        );
        expect(game.state, GameState.playing);
        // §5.5 flash: 100 % ↔ 25 % every 0.1 s.
        final bird = game.runBird!;
        final seen = <double>{};
        for (var i = 0; i < 30; i++) {
          hold(game, 1 / 60);
          seen.add(bird.spriteOpacity);
        }
        expect(seen, containsAll([1.0, .25]));
        hold(game, 2);
        expect(run.state.invulnerable, 0);
        expect(bird.spriteOpacity, 1);
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.died,
        );
      },
    );

    tester.testGameWidget(
      '§3.3 / §3.0.5 ($h) a spike save bounces off the tooth line and the '
      'bird stays on screen through the 2 s',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        run.state.extraLife = true;
        final bird = game.runBird!;
        bird.setFlight(y: RunConfig.stripHeight + 10, vy: -300);
        game.update(1 / 60);
        expect(run.state.saves, 1);
        expect(run.state.extraLife, isFalse);
        expect(game.state, GameState.playing);
        // Free flight (no flaps) for the 2 s: the floor save bounce keeps it
        // on screen while invulnerable.
        var t = 0.0;
        var minY = 1e9, maxY = -1e9;
        while (t < LivesConfig.invulnerable - .05) {
          game.update(1 / 60);
          t += 1 / 60;
          final y = bird.body.position.y;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        expect(game.state, GameState.playing);
        expect(minY, greaterThan(0));
        expect(maxY, lessThan(h));
      },
    );

    tester.testGameWidget(
      '§3.7 ($h) the shield pickup arms the shield (pu_shield_get, '
      'shield_collected) and the circle forms over the bird',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        final sfx = sfxLog(game);
        final circle = feature<ShieldFeature>(run).circle!;
        expect(circle.shown, isFalse);
        run.events.emit(const PickupCollected(ElementId.shield, null));
        expect(run.state.shield, isTrue);
        expect(sfx, ['puShieldGet']);
        expect(
          analyticsLog(spy).map((e) => e.$1),
          contains('shield_collected'),
        );
        hold(game, LivesConfig.formDelay + LivesConfig.popIn + .05);
        expect(circle.born, 1);
        expect(circle.scaleNow, closeTo(1, LivesConfig.shieldPulse + 1e-9));
        expect(circle.centre!.dy, game.runBird!.body.position.y);
      },
    );

    tester.testGameWidget(
      '§3.7 / §3.3 ($h) save order: the shield (order 10) absorbs first, '
      'then the extra life (order 20); both give 2 s invulnerability; the '
      'third mistake ends the run',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.events.recordLog = true;
        final sfx = sfxLog(game);
        expect(
          [
            feature<ShieldFeature>(run).order,
            feature<ExtraLifeFeature>(run).order,
          ],
          [10, 20],
        );
        run.state
          ..shield = true
          ..extraLife = true;
        hold(game, .8);
        final before = run.particles.alive;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.saved,
        );
        expect((run.state.shield, run.state.extraLife), (false, true));
        expect(run.state.invulnerable, LivesConfig.invulnerable);
        expect(sfx.last, 'puShieldHit');
        expect(feature<ShieldFeature>(run).circle!.shown, isFalse);
        expect(
          run.particles.particles
              .skip(before)
              .where((p) => p.shape == ParticleShape.triangle),
          hasLength(12),
        );
        hold(game, LivesConfig.invulnerable + .05);
        expect(
          run.mistake(const Mistake(MistakeCause.saw)),
          MistakeOutcome.saved,
        );
        expect((run.state.shield, run.state.extraLife), (false, false));
        expect(sfx.last, 'puHeartUse');
        expect(run.events.log.whereType<MistakeSaved>().map((e) => e.by), [
          'shield',
          'extra_life',
        ]);
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'shield_used').single.$2,
          {'cause': 'spikes'},
        );
        hold(game, LivesConfig.invulnerable + .05);
        expect(
          run.mistake(const Mistake(MistakeCause.closedSwitch)),
          MistakeOutcome.died,
        );
        expect(run.state.saves, 2);
      },
    );

    tester.testGameWidget(
      '§5.2 ($h) a save shows the "SAVED!" element banner in the mounted '
      'banner host (master #7)',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        // PRD-2.2 §12: the run's banner host (in the banner layer).
        final host = RunHud.of(run)!.banners;
        await flushAndMount(game);
        run.state.shield = true;
        run.mistake(const Mistake(MistakeCause.missedHoop));
        final b = host.current;
        expect(b, isA<ElementBanner>());
        expect(b!.text, 'SAVED!');
      },
    );

    tester.testGameWidget(
      '§3.7 ($h) the home-slot shield is consumed at the start and active '
      'from the first frame',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game, starter: Powerup.shield);
        expect(game.storage.armedPowerup, 'none');
        expect(run.state.shield, isTrue);
        expect(analyticsLog(spy).map((e) => e.$1), contains('shield_armed'));
        expect(feature<ShieldFeature>(run).circle!.shown, isTrue);
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.saved,
        );
      },
    );

    tester.testGameWidget(
      '§3.3 ($h) a heart pickup on the bird is collected by touch (the '
      'spawner hit test) and counts',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        game.runDebug.god = true;
        final sfx = sfxLog(game);
        // Fly the hoop-aware bot until the director's first heart (PRD-2.2
        // §19.1: a random gap 5–27) is there, then steer into it.
        HeartPickup? p;
        await flyRun(
          game,
          maxSeconds: 60,
          onFrame: (r) {
            p ??= pickupsOf(game).whereType<HeartPickup>().firstOrNull;
          },
          untilHoops: run.director.heartAt + 3,
        );
        expect(p, isNotNull);
        for (var i = 0; i < 400 && !p!.collected && !p!.escaped; i++) {
          if (p!.position.x - run.state.camX < 140) {
            game.runBird!.setFlight(y: p!.position.y, vy: 0);
          }
          game.update(1 / 60);
        }
        expect(p!.collected, isTrue);
        expect(run.state.hearts, 1);
        expect(sfx, contains('puHeart1'));
        expect(p!.isRemoved || p!.isRemoving, isTrue);
      },
    );
  }

  test('§3.3 the invulnerability feature is one per run (WP-2a)', () {
    expect(InvulnerabilityFeature().flash.length, 2);
  });
}
