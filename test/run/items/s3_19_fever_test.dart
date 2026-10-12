import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/fever_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/run_shake.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/fever_banner.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/fever.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c: the glowing ring (FEVER) and the fire (PRD-2 §3.19, §5.18).
void main() {
  test('§5.18 Gate Nova numbers: red rim 10 pt on a 14 pt dark-red outline, '
      'glow 16, 30 beads re-rolled 12×/s, 3 loops up to ≈ 54 pt, beam 125 pt '
      'with 8 streaks, halo +44; pass: 3 rings 0.09 s apart, 26 flames, '
      'flash ≈ 0.3 s, shake 6 pt; fire 115/s, 10–18 pt, 0.35–0.65 s', () {
    expect(FeverConfig.rimFront.toARGB32(), 0xFFE8141C);
    expect(FeverConfig.rimBack.toARGB32(), 0xFFA50E14);
    expect(FeverConfig.outline.toARGB32(), 0xFF5E000A);
    expect(FeverConfig.rimWidth, 10);
    expect(FeverConfig.outlineWidth, 14);
    expect(FeverConfig.glowBlur, 16);
    expect(FeverConfig.beads, 30);
    expect(FeverConfig.beadRerollPerSecond, 12);
    expect(FeverConfig.loops, 3);
    expect(10 + FeverConfig.loopHeight, 54);
    expect(FeverConfig.beamLength, 125);
    expect(FeverConfig.beamStreaks, 8);
    expect(FeverConfig.haloExtra, 44);
    expect(FeverConfig.passRingColors, hasLength(3));
    expect(FeverConfig.passRingGap, .09);
    expect(FeverConfig.passBurst, 26);
    expect(FeverConfig.passFlash / FeverConfig.passFlashDecay, closeTo(.2, .1));
    // The world shake preset is the one master (RunShake.feverPass).
    final shake = RunShake()..feverPass();
    expect(shake.amplitude, FeverConfig.passShake);
    expect(FeverConfig.fireRate, 115);
    expect(FeverConfig.fireSize, 10);
    expect(FeverConfig.fireSize + 8, 18);
    expect(FeverConfig.fireLifeMin, .35);
    expect(FeverConfig.fireLifeMin + FeverConfig.fireLifeRange, closeTo(.65, 1e-9));
    expect(FeverConfig.firePalette.map((c) => c.toARGB32()), [
      0xFFFFFFFF,
      0xFFFFF3B0,
      0xFFFF9100,
      0xFFD50000,
    ]);
  });

  test('§5.18 FEVER! banner: Opificio 44, gradient FFF59D → FF9800 → '
      'E64A19, plum 7 pt outline, pop 0.6 → 1.1 → 1, ≈ 1.6 s', () {
    final b = FeverBanner();
    expect(b.lane, BannerLane.fever);
    expect(b.text, 'FEVER!');
    expect(b.fontSize, 44);
    expect(b.duration, 1.6);
    expect(FeverConfig.bannerGradient.map((c) => c.toARGB32()), [
      0xFFFFF59D,
      0xFFFF9800,
      0xFFE64A19,
    ]);
    expect(FeverConfig.bannerOutline.toARGB32(), 0xFF7A0044);
    expect(FeverConfig.bannerOutlineWidth, 7);
    expect(b.popAt(0).$1, closeTo(.6, 1e-9));
    expect(b.popAt(.12).$1, closeTo(1.1, 1e-9));
    expect(b.popAt(.22).$1, closeTo(1, 1e-9));
    expect(b.popAt(1).$1, 1);
    expect(b.popAt(1.6).$2, 0);
    // Above the tier banner band (top 190).
    expect(FeverConfig.bannerCentreY, lessThan(190));
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

  Future<(RunController, Hoop, List<RunEvent>)> toFever(
    FlappySpikesGame game,
  ) async {
    final run = await startRun(
      game,
      startHoopIndex: 15,
      force: [ElementId.fever],
    );
    final events = <RunEvent>[];
    run.events.onAny(events.add);
    expect(
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.fever) != null),
      isTrue,
    );
    return (run, firstHoopOf(game, HoopKindId.fever)!, events);
  }

  List<Map<String, Object>?> paramsOf(String name) =>
      spy.events.where((e) => e.$1 == name).map((e) => e.$2).toList();

  tester.testGameWidget(
    '§3.19 a perfect FEVER pass: streak max(5, streak + 1), the bird '
    'catches fire, FEVER! over SOARING ×5, +1 score / +2 coins only, '
    'perfect_3 + the FEVER sound, the pass effect, analytics',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h, events) = await toFever(game);
      final sfx = sfxLog(game);
      final loops = <SfxLoop>[];
      game.sound.onLoop = (l, _) => loops.add(l);
      expect(h.kind.usesTierLook, isFalse);
      expect(h.plan.tiltDeg, 0);
      expect(h.plan.motion, isNull);
      expect(paramsOf('fever_ring_spawned').single, {
        'hoop_index': h.plan.index,
      });
      final score0 = run.state.score;
      expect(run.state.streak, lessThan(5));
      final before = run.state.streak;
      expect(await passHoopAt(game, h), isTrue);
      expect(h.takenRing, 0);
      expect(run.state.streak, 5);
      expect(run.state.onFire, isTrue);
      expect(run.state.score, score0 + 1);
      final coins = events.whereType<CoinsEarned>().toList();
      expect(coins.single.source, CoinSource.perfect);
      expect(coins.single.amount, 2);
      final host = RunHud.of(run)!.banners;
      expect(host.fever, isA<FeverBanner>());
      expect((host.current! as StreakBanner).text, 'SOARING ×5');
      expect(sfx, containsAll(['perfect3', 'feverPass']));
      expect(paramsOf('fever_ring_passed').single, {
        'perfect': 1,
        'streak_before': before,
        'streak_after': 5,
      });
      expect(FeverHoopKind.stateOf(h)!.flare, greaterThan(0));
      await flushAndMount(game);
      expect(game.world.children.whereType<FeverFlash>(), hasLength(1));
      expect(game.world.children.whereType<FeverShake>(), hasLength(1));
      await flyUntil(game, (_) => false, maxSeconds: .5);
      expect(loops, contains(SfxLoop.feverLoop));
      final feature = run.features.whereType<FeverFeature>().single;
      expect(feature.flames!.alive, greaterThan(20));
      // The shake is over and the camera is back.
      expect(game.world.children.whereType<FeverShake>(), isEmpty);
      expect(game.camera.viewfinder.position.length, lessThan(1e-3));
      // Burning: perfect passes keep it, count as burned.
      run.debugPass(perfect: true);
      run.debugPass(perfect: true);
      expect(run.state.onFire, isTrue);
      expect(run.state.hoopsBurned, 2);
      expect(run.state.streak, 7);
      // A graze puts it out: smoke, sizzle, fever_fire_out.
      run.debugPass(perfect: false);
      expect(run.state.onFire, isFalse);
      expect(sfx, contains('feverOut'));
      expect(paramsOf('fever_fire_out').single, {
        'streak': 7,
        'hoops_burned': 2,
        'cause': 'graze',
      });
      expect(game.storage.metElements, contains('fever'));
    },
  );

  tester.testGameWidget(
    '§3.19 a rim touch on the FEVER ring is a normal pass: no FEVER, no '
    'fire, the streak resets (Q50)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h, _) = await toFever(game);
      final sfx = sfxLog(game);
      h.touched = true;
      expect(await passHoopAt(game, h), isTrue);
      expect(run.state.onFire, isFalse);
      expect(run.state.streak, 0);
      expect(sfx, isNot(contains('feverPass')));
      expect(RunHud.of(run)!.banners.fever, isNull);
      expect(paramsOf('fever_ring_passed').single, {
        'perfect': 0,
        'streak_before': isA<int>(),
        'streak_after': 0,
      });
    },
  );

  tester.testGameWidget(
    '§3.19 reaching ×5 through normal passes does not light the fire (Q51)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (var i = 0; i < 7; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.state.streak, 7);
      expect(run.state.onFire, isFalse);
    },
  );

  for (final (by, label) in [
    ('extra_life', 'an extra life'),
    ('shield', 'a shield'),
  ]) {
    tester.testGameWidget(
      '§3.19 a mistake saved by $label puts the fire out (cause $by)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final run = await startRun(game);
        run.events.emit(const FeverIgnite('test'));
        run.debugPass(perfect: true);
        expect(run.state.onFire, isTrue);
        if (by == 'shield') {
          run.state.shield = true;
        } else {
          run.state.extraLife = true;
        }
        expect(
          run.mistake(Mistake(MistakeCause.spikes, normal: Vector2(0, 1))),
          MistakeOutcome.saved,
        );
        expect(run.state.onFire, isFalse);
        expect(paramsOf('fever_fire_out').single!['cause'], by);
      },
    );
  }

  tester.testGameWidget(
    '§3.19 a death puts the fire out (cause death); a ride keeps it burning',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      run.events.emit(const FeverIgnite('test'));
      expect(run.state.onFire, isTrue);
      expect(RunHud.of(run)!.banners.fever, isA<FeverBanner>());
      // A ride: every hoop is perfect, the fire keeps burning.
      run.state.ride = RideState(kind: RideKind.comet);
      run.debugPass(perfect: true);
      expect(run.state.onFire, isTrue);
      run.state.ride = null;
      killRun(game);
      expect(run.state.onFire, isFalse);
      expect(paramsOf('fever_fire_out').single!['cause'], 'death');
      expect(sfx, isNot(contains('feverOut')));
    },
  );
}
