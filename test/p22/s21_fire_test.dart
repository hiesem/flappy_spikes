import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/fever_config.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/config/trail_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/block_trail.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/effects/tier_trail.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/fever.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §21: the bird catches fire at ×3, with a thicker trail.
void main() {
  group('§21.1 config', () {
    test('size table: ×3–×4 55/s 70 %, ×5–×6 95/s 85 %, ×7+ 150/s 100 %; '
        'halo 34/22 %, 42/30 %, 52/38 %; teardrops 9–16 pt at 100 %', () {
      expect(FeverConfig.fireStreak, 3);
      expect(FeverConfig.fireLevelStreaks, [3, 5, 7]);
      expect(FeverConfig.fireRates, [55, 95, 150]);
      expect(FeverConfig.fireScales, [.7, .85, 1]);
      expect(FeverConfig.fireHaloRadii, [34, 42, 52]);
      expect(FeverConfig.fireHaloAlphas, [.22, .30, .38]);
      expect(FeverConfig.fireSizeMin, 9);
      expect(FeverConfig.fireSizeMax, 16);
      // ≈ 6–11 pt at 70 %.
      expect(FeverConfig.fireSizeMin * .7, closeTo(6, .5));
      expect(FeverConfig.fireSizeMax * .7, closeTo(11, .5));
      expect(FeverConfig.fireLifeMin, .3);
      expect(FeverConfig.fireLifeMax, .55);
      expect(FeverConfig.firePalette.map((c) => c.toARGB32()), [
        0xFFFFFFFF,
        0xFFFFF3B0,
        0xFFFF9100,
        0xFFD50000,
      ]);
      for (final (n, l) in [
        (0, 0),
        (2, 0),
        (3, 1),
        (4, 1),
        (5, 2),
        (6, 2),
        (7, 3),
        (12, 3),
      ]) {
        expect(FireLevel.of(n), l, reason: '×$n');
      }
      expect(FeverConfig.crackleVolume, closeTo(.25, 1e-9));
      expect(FeverConfig.loopVolume, .35); // today's FEVER volume
      expect(FeverConfig.loopRamp, closeTo(.3, 1e-9));
    });

    test('colours: a flame trail gives its four colours, others the classic '
        'orange fire', () {
      expect(
        FeverFeature.fireColorsFor('flame'),
        TrailEmitter.flameColors('flame'),
      );
      // Classic flame is orange (light yellow → deep red).
      expect(
        FeverFeature.fireColorsFor('flame').map((c) => c.toARGB32()),
        [0xFFFFF59D, 0xFFFFB529, 0xFFFF5722, 0xFFB71C1C],
      );
      expect(
        FeverFeature.fireColorsFor('blue').map((c) => c.toARGB32()),
        [0xFFFFFFFF, 0xFF80DEEA, 0xFF039BE5, 0xFF01579B],
      );
      for (final id in ['toxic', 'hot', 'shadow']) {
        expect(FeverFeature.fireColorsFor(id), hasLength(4));
        expect(
          FeverFeature.fireColorsFor(id),
          isNot(FeverConfig.firePalette),
        );
      }
      for (final id in ['sparkle', 'bubbles', 'blocks', 'rainbow', '??']) {
        expect(FeverFeature.fireColorsFor(id), FeverConfig.firePalette);
      }
    });

    test('trail: every trail at 2× the old scale, 18 pt behind the bird', () {
      expect(TrailConfig.runScale, closeTo(2 * Config.lookScale, 1e-12));
      expect(TrailConfig.runBack, 18);
      for (final id in TrailEmitter.ids) {
        final t = TierTrail(trailId: id);
        expect(t.k, closeTo(2 * Config.lookScale, 1e-12), reason: id);
      }
      // The block trail (Pixel blocks): 2× its 8–13 pt master size.
      final pool = ParticlePool(capacity: 64);
      final t = TierTrail(trailId: TierTrail.blocksId);
      t.update(pool, 1, const Offset(70, 300), 0, active: true);
      expect(pool.alive, greaterThan(10));
      for (final p in pool.particles) {
        expect(p.w, inInclusiveRange(16, 26));
        expect(p.x, closeTo(70 - 18, PartsConfig.trailSide + 1e-9));
      }
      // The master itself keeps its size outside the run trail.
      final master = ParticlePool(capacity: 64);
      BlockTrail().update(master, 1, const Offset(70, 300), 0);
      for (final p in master.particles) {
        expect(p.w, inInclusiveRange(8, 13));
      }
    });

    test('the equipped trail particles are 2× today\'s size (painted '
        'bounds, every particle kind)', () async {
      Future<double> height(String id, double k) async {
        final e = TrailEmitter(id, random: _Fixed());
        for (var i = 0; i < 6; i++) {
          e.emit(const Offset(160, 160), 1 / 60, k: k);
          e.step(1 / 60);
        }
        final rec = PictureRecorder();
        final canvas = Canvas(rec);
        e.paint(canvas, k: k);
        final img = await rec.endRecording().toImage(320, 320);
        final data = (await img.toByteData())!;
        var top = 320, bottom = -1;
        for (var y = 0; y < 320; y++) {
          for (var x = 0; x < 320; x++) {
            if (data.getUint8((y * 320 + x) * 4 + 3) > 0) {
              if (y < top) top = y;
              if (y > bottom) bottom = y;
              break;
            }
          }
        }
        return bottom < 0 ? 0 : (bottom - top + 1).toDouble();
      }

      for (final id in ['flame', 'blue', 'sparkle', 'bubbles', 'hearts']) {
        final old = await height(id, Config.lookScale);
        final now = await height(id, TrailConfig.runScale);
        expect(old, greaterThan(0), reason: id);
        expect(now / old, closeTo(2, .35), reason: id);
      }
    });
  });

  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 6);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  FeverFeature feverOf(RunController run) =>
      run.features.whereType<FeverFeature>().single;

  List<Map<String, Object>?> outs() => spy.events
      .where((e) => e.$1 == 'fever_fire_out')
      .map((e) => e.$2)
      .toList();

  tester.testGameWidget(
    '§21.1 the 3rd perfect pass lights the fire; a graze, a clean pass and '
    'a saved mistake each put it out once (smoke + fever_out); the 3rd '
    'perfect after that lights it again',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      final fire = feverOf(run).fire!;
      Future<void> lightAgain() async {
        run.debugPass(perfect: true);
        run.debugPass(perfect: true);
        expect(run.state.onFire, isFalse);
        run.debugPass(perfect: true);
        expect(run.state.onFire, isTrue);
        expect(run.state.fever, isFalse);
      }

      run.debugPass(perfect: true);
      expect(run.state.onFire, isFalse);
      run.debugPass(perfect: true);
      expect(run.state.onFire, isFalse);
      run.debugPass(perfect: true);
      expect(run.state.onFire, isTrue);
      // No FEVER banner for a streak fire.
      expect(RunHud.of(run)!.banners.fever, isNull);

      void expectOutOnce(String cause, int n) {
        expect(run.state.onFire, isFalse);
        expect(sfx.where((s) => s == 'feverOut'), hasLength(n));
        expect(outs(), hasLength(n));
        expect(outs().last!['cause'], cause);
        expect(fire.smokePool.alive, FeverConfig.smokePuffs);
        fire.smokePool.clear();
      }

      // A graze.
      run.debugPass(perfect: false);
      expectOutOnce('graze', 1);
      await lightAgain();
      // A clean off-centre pass (§11).
      run.debugPass(clean: true);
      expectOutOnce('clean', 2);
      await lightAgain();
      // A saved mistake.
      run.state.shield = true;
      expect(
        run.mistake(Mistake(MistakeCause.spikes, normal: Vector2(0, 1))),
        MistakeOutcome.saved,
      );
      expectOutOnce('shield', 3);
      // Breaking an already broken streak does nothing more.
      run.debugPass(perfect: false);
      expect(outs(), hasLength(3));
      expect(sfx.where((s) => s == 'feverOut'), hasLength(3));
      await lightAgain();
    },
  );

  tester.testGameWidget(
    '§21.1 size levels: emission rate and particle size at ×3, ×5, ×7, ×12',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final fire = feverOf(run).fire!;
      for (final (n, rate, scale) in [
        (3, 55.0, .7),
        (5, 95.0, .85),
        (7, 150.0, 1.0),
        (12, 150.0, 1.0),
      ]) {
        while (run.state.streak < n) {
          run.debugPass(perfect: true);
        }
        expect(run.state.onFire, isTrue);
        expect(fire.rate, rate, reason: '×$n');
        expect(fire.scale, scale, reason: '×$n');
        fire.pool.clear();
        // 0.25 s: no flame dies yet (shortest life 0.3 × 0.94).
        for (var i = 0; i < 25; i++) {
          fire.update(.01);
        }
        expect(fire.pool.alive, closeTo(rate * .25, 1.01), reason: '×$n');
        for (final p in fire.pool.particles) {
          expect(
            p.w / FeverConfig.fireDropWidth,
            inInclusiveRange(
              FeverConfig.fireSizeMin * scale - 1e-9,
              FeverConfig.fireSizeMax * scale + 1e-9,
            ),
          );
          expect(p.shape, ParticleShape.flame);
          // Streaming back and up.
          expect(p.vx, inInclusiveRange(-130, -60));
          expect(p.vy, inInclusiveRange(-80, -10));
        }
      }
    },
  );

  tester.testGameWidget(
    '§21.1 flames rise from the back, top and bottom edges of the bird',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final fire = feverOf(run).fire!;
      for (var i = 0; i < 7; i++) {
        run.debugPass(perfect: true);
      }
      fire.pool.clear();
      fire.update(.3);
      final b = game.runBirdPosition!;
      var back = 0, top = 0, bottom = 0;
      for (final p in fire.pool.particles) {
        // Undo the motion since the spawn.
        final dx = p.x - p.vx * p.t - b.x;
        final dy = p.y - p.vy * p.t - b.y;
        final inBack = dx >= -24 - 1e-6 && dx <= -18 + 1e-6 && dy.abs() <= 14;
        final inTop = dy >= -18 - 1e-6 && dy <= -13 + 1e-6 && dx <= 16;
        final inBottom = dy >= 13 - 1e-6 && dy <= 18 + 1e-6 && dx <= 10;
        // Never in front of the bird's middle.
        expect(inBack || inTop || inBottom, isTrue, reason: '($dx, $dy)');
        if (dx < -20) back++;
        if (dy < -14) top++;
        if (dy > 14) bottom++;
      }
      expect(back, greaterThan(0));
      expect(top, greaterThan(0));
      expect(bottom, greaterThan(0));
    },
  );

  tester.testGameWidget(
    '§21.1 colours: Blue flame equipped → its blue set; Sparkles → orange',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      await game.storage.saveOwnedItems({
        ...game.storage.ownedItems,
        'trail:blue',
        'trail:sparkle',
      });
      await game.menu.items.equip(SkinLayer.trail, 'blue');
      expect(game.menu.items.look.trail, 'blue');
      var run = await startRun(game);
      final blue = TrailEmitter.flameColors('blue')!;
      expect(feverOf(run).fire!.colors, blue);
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      feverOf(run).fire!.update(.2);
      expect(feverOf(run).flames!.particles.first.ramp, blue);
      killRunThroughSaves(game);
      await declineRevive(game);
      await game.menu.items.equip(SkinLayer.trail, 'sparkle');
      game.replay();
      await stepSeconds(game, .5);
      run = await startRun(game);
      expect(feverOf(run).fire!.colors, FeverConfig.firePalette);
    },
  );

  tester.testGameWidget(
    '§21.1 layer: the fire paints below the bird and above the trail; one '
    'fire component',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final fire = feverOf(run).fire!;
      final bird = game.world.children.whereType<Bird>().single;
      expect(fire.parent, same(bird.parent));
      expect(fire.priority, lessThan(bird.priority));
      expect(StreakConfig.trailPriority, lessThan(fire.priority));
      final order = game.world.children.toList();
      expect(order.indexOf(fire), lessThan(order.indexOf(bird)));
      final trail = order.where(
        (c) => c.priority == StreakConfig.trailPriority,
      );
      expect(trail, isNotEmpty);
      for (final t in trail) {
        expect(order.indexOf(t), lessThan(order.indexOf(fire)));
      }
      expect(game.world.children.whereType<FireMaster>(), hasLength(1));
      // The streak feature's trail draws at the run scale.
      final streak = run.features.whereType<StreakFeature>().single;
      expect(streak.trail!.k, TrailConfig.runScale);
    },
  );

  tester.testGameWidget(
    '§21.1 FEVER: a FEVER ignite shows the same fire at the ×5 size, no '
    'second fire component; the gift at ×0 → ×5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final fire = feverOf(run).fire!;
      run.events.emit(const FeverIgnite('test'));
      expect(run.state.onFire, isTrue);
      expect(run.state.fever, isTrue);
      expect(fire.level, 2);
      expect(fire.rate, 95);
      expect(RunHud.of(run)!.banners.fever, isNotNull);
      expect(game.world.children.whereType<FireMaster>(), hasLength(1));
      // At ×7 the streak size wins.
      for (var i = 0; i < 7; i++) {
        run.debugPass(perfect: true);
      }
      expect(fire.level, 3);
    },
  );

  tester.testGameWidget(
    '§21.1 rides: the fire burns on through a portal ride; hidden in the '
    'comet and back after it while the streak is ≥ 3',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final fire = feverOf(run).fire!;
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      // Portal ride: passes keep it burning and visible.
      run.state.ride = RideState(kind: RideKind.portal);
      run.debugPass(perfect: true);
      expect(run.state.onFire, isTrue);
      expect(fire.hidden, isFalse);
      fire.pool.clear();
      fire.update(.1);
      expect(fire.pool.alive, greaterThan(0));
      // The bird hidden in the barrel: no flames for that moment.
      run.state.ride!.birdHidden = true;
      expect(fire.hidden, isTrue);
      run.state.ride = null;
      // A forced comet ride: hidden inside the fireball.
      final comet = run.features.whereType<CometFeature>().single;
      expect(comet.start(), isTrue);
      expect(run.state.ride?.kind, RideKind.comet);
      expect(run.state.onFire, isTrue);
      expect(fire.showing, isFalse);
      fire.pool.clear();
      fire.update(.2);
      expect(fire.pool.alive, 0);
      // After the comet: shows again (streak still ≥ 3).
      await flyUntil(game, (_) => run.state.ride == null, maxSeconds: 20);
      expect(run.state.ride, isNull);
      expect(run.state.streak, greaterThanOrEqualTo(3));
      expect(fire.showing, isTrue);
      fire.update(.1);
      expect(fire.pool.alive, greaterThan(0));
    },
  );

  tester.testGameWidget(
    '§21.1 sound: one fever_loop player, quiet crackle → FEVER volume → '
    'FEVER until the streak breaks; stops on out / pause / death',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final loops = <(SfxLoop, double)>[];
      game.sound.onLoop = (l, v) => loops.add((l, v));
      final fever = feverOf(run);
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      game.update(1 / 60);
      expect(loops, [(SfxLoop.feverLoop, FeverConfig.crackleVolume)]);
      final handle = fever.loop!;
      expect(handle.volume, FeverConfig.crackleVolume);
      // FEVER: ramps up to the FEVER volume on the same player.
      run.events.emit(const FeverIgnite('test'));
      for (var i = 0; i < 6; i++) {
        game.update(1 / 60);
      }
      expect(fever.loopVolume, greaterThan(FeverConfig.crackleVolume));
      expect(fever.loopVolume, lessThan(FeverConfig.loopVolume));
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(fever.loopVolume, FeverConfig.loopVolume);
      expect(handle.volume, FeverConfig.loopVolume);
      expect(identical(fever.loop, handle), isTrue);
      // FEVER is unchanged (S7-07): it runs until the streak breaks, at the
      // FEVER volume, however many perfect passes follow.
      for (var i = 0; i < 8; i++) {
        expect(run.state.fever, isTrue);
        run.debugPass(perfect: true);
      }
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect(run.state.fever, isTrue);
      expect(handle.volume, FeverConfig.loopVolume);
      expect(identical(fever.loop, handle), isTrue);
      expect(loops, hasLength(1));
      expect(handle.stopped, isFalse);
      // Pause stops it; resume starts it again (still FEVER).
      game.pause();
      game.update(1 / 60);
      expect(handle.stopped, isTrue);
      game.resume();
      game.update(1 / 60);
      expect(loops, hasLength(2));
      expect(loops.last.$2, FeverConfig.loopVolume);
      // Out: stops.
      final h2 = fever.loop!;
      run.debugPass(perfect: false);
      expect(h2.stopped, isTrue);
      game.update(1 / 60);
      expect(loops, hasLength(2));
      // Death: stops.
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      game.update(1 / 60);
      final h3 = fever.loop!;
      expect(loops, hasLength(3));
      killRunThroughSaves(game);
      expect(h3.stopped, isTrue);
    },
  );

  test('§21.1 the loop follows the SFX switch: muted → a silent recorder', () {
    final muted = SoundService(muted: true);
    final h = muted.loop(SfxLoop.feverLoop, volume: FeverConfig.crackleVolume);
    expect(h.audible, isFalse);
    expect(h.volume, FeverConfig.crackleVolume);
    h.stop();
    final off = SoundService(enabled: false);
    expect(off.loop(SfxLoop.feverLoop).audible, isFalse);
  });

  tester.testGameWidget(
    '§21.1 a death puts the fire out without the sizzle; a revive starts '
    'with no fire',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      for (var i = 0; i < 4; i++) {
        run.debugPass(perfect: true);
      }
      run.events.emit(const FeverIgnite('test'));
      expect(run.state.fever, isTrue);
      killRunThroughSaves(game);
      expect(run.state.onFire, isFalse);
      expect(run.state.fever, isFalse);
      expect(run.state.feverLit, isFalse);
      expect(sfx, isNot(contains('feverOut')));
      expect(outs().last!['cause'], 'death');
    },
  );
}

/// A fixed "random" (0.5 everywhere) so two emitters spawn the same
/// particles at different scales.
class _Fixed implements math.Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => .5;

  @override
  int nextInt(int max) => 0;
}
