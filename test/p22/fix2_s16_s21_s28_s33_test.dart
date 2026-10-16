import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_audio.dart';

/// Fix round P2-R1 (QA P2 S7-07 … S7-13): the sides of each fix the QA
/// regressions do not pin down.
void main() {
  final all = ElementId.values.toSet();

  group('S7-08 §21 / PRD-2 §3.19 only FEVER itself blocks FEVER', () {
    test('a running FEVER still keeps the FEVER ring away', () {
      final d = RunDirector(
        seed: 5,
        enabled: all,
        met: all,
        startHoopIndex: 20,
        forced: [ElementId.fever],
      );
      final plan = d.nextSlot(
        DirectorContext.open(711, onFire: true, fever: true),
      );
      expect(plan.kind, isNot(HoopKindId.fever));
    });

    test('pair gifts: FEVER offered under ×3 fire, never during FEVER', () {
      var feverOnFire = 0;
      for (var seed = 1; seed <= 60; seed++) {
        for (final fever in [false, true]) {
          final d = RunDirector(seed: seed, enabled: all, met: all);
          for (var k = 0; k < 150; k++) {
            final ctx = DirectorContext.open(711, onFire: true, fever: fever);
            final s = d.nextSlot(ctx);
            d.nextGap(ctx, s);
            if (s.kind != HoopKindId.pair) continue;
            final r = s.extra! as PairRewards;
            final hasFever =
                r.top == PairReward.fever || r.bottom == PairReward.fever;
            if (fever) {
              expect(hasFever, isFalse);
            } else if (hasFever) {
              feverOnFire++;
            }
          }
        }
      }
      expect(feverOnFire, greaterThan(0));
    });
  });

  group('S7-12 §16.1 / §27 comet over a planned-ahead reward ring', () {
    final prefs = {
      'metElements': [for (final e in all) e.storageId],
    };
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 5, prefs: prefs),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      // PRD-2.3.1 §16.1 A (supersedes "the height stays"): the slot moves
      // into the comet layout — a comet station at the zigzag height.
      'the reward goes (plain kind), it moves to a comet station, the curve size',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g, startHoopIndex: 20);
        run.debugForce(ElementId.fever);
        await flyUntil(
          g,
          (r) => r.spawner.plannedAhead?.kind == HoopKindId.fever,
          maxSeconds: 8,
        );
        final planned = run.spawner.plannedAhead!;
        expect(run.features.whereType<CometFeature>().single.start(), isTrue);
        await flyUntil(
          g,
          (r) => r.spawner.hoops.any((h) => h.plan.index == planned.index),
          maxSeconds: 4,
        );
        final spawned = run.spawner.hoops.singleWhere(
          (h) => h.plan.index == planned.index,
        );
        expect(spawned.plan.kind, HoopKindId.normal);
        expect(spawned.plan.duringRide, isTrue);
        expect(
          run.director.cometStations.any(
            (x) => (x - spawned.plan.trackX).abs() < 1e-6,
          ),
          isTrue,
        );
        expect((spawned.plan.centreY - 711 / 2).abs(), closeTo(70, 1e-6));
        // PRD-2.4 §2: a comet ride hoop takes the curve size of its index.
        expect(
          spawned.plan.opening,
          closeTo(RunConfig.openingFor(spawned.plan.index), 1e-9),
        );
      },
    );
  });

  group('S7-11 §33.4 item 3 / §18.4 preload and the pool cap', () {
    test('the latest preload (the ride) survives lazy pools over the cap; '
        'older unplayed preloads are evicted first', () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      final rare = Sfx.values
          .where((s) => !SoundService.prewarmed.contains(s))
          .toList();
      final old = rare.take(20).toList();
      final ride = rare.skip(20).take(6).toList();
      sound.preload(old);
      await flushAudio();
      now += 10;
      sound.preload(ride);
      await flushAudio();
      for (final s in rare.skip(26).take(Config.sfxMaxLivePools)) {
        now += 10;
        sound.play(s);
        await flushAudio();
      }
      now += Config.sfxTrimIntervalMs;
      sound.play(Sfx.flap);
      await flushAudio();
      for (final s in ride) {
        expect(sound.poolOf(s), isNotNull, reason: '$s reserved');
      }
      for (final s in SoundService.prewarmed) {
        expect(sound.poolOf(s), isNotNull, reason: '$s core');
      }
      expect(old.every((s) => sound.poolOf(s) == null), isTrue);
      expect(sound.poolCount, lessThanOrEqualTo(Config.sfxMaxLivePools));
      await sound.dispose();
      expect(audio.live, 0);
    });

    test('the service works again after a dispose (new generation)', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.play(Sfx.flap);
      await flushAudio();
      await sound.dispose();
      expect(sound.poolCount, 0);
      sound.play(Sfx.flap);
      await flushAudio();
      expect(sound.poolOf(Sfx.flap), isNotNull);
      sound.play(Sfx.flap);
      await flushAudio();
      expect(audio.of('flap.mp3').where((v) => v.playing), isNotEmpty);
      await sound.dispose();
      expect(audio.live, 0);
    });
  });

  group('S7-09 §28 the hold is not a late burst', () {
    test('one-shots stopped by an ad stay stopped after it; new plays are '
        'heard again', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.preload([Sfx.lvUpBig]);
      await flushAudio();
      sound.play(Sfx.lvUpBig);
      sound.suspend(); // the start is still queued on the voice's chain
      await flushAudio();
      sound.resume();
      await flushAudio();
      expect(audio.of('lv_up_big.mp3').where((v) => v.playing), isEmpty);
      sound.play(Sfx.lvUpBig);
      await flushAudio();
      expect(audio.of('lv_up_big.mp3').where((v) => v.playing), hasLength(1));
      await sound.dispose();
    });
  });

  group('S7-13 §28.3 own sound vs other music', () {
    test('ownSoundRecent: a one-shot for its length + margin + 0.6 s, and '
        'any running loop', () {
      var now = 0;
      final sound = SoundService(enabled: false)..clockMs = () => now;
      expect(sound.ownSoundRecent, isFalse);
      sound.play(Sfx.flap);
      expect(sound.ownSoundRecent, isTrue);
      now = 5000;
      expect(sound.ownSoundRecent, isFalse);
      final l = sound.loop(SfxLoop.feverLoop);
      expect(sound.ownSoundRecent, isTrue);
      l.stop();
      expect(sound.ownSoundRecent, isFalse);
    });

    final focus = FakeAudioFocus()..otherMusic = true;
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711)..audioFocus = focus,
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'listed external music keeps the game music off at a flapping run '
      'start',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        // PRD-2.3 §13.4: own music needs two yes answers 1 s apart.
        await settleMusicChecks(g);
        expect(g.sound.ownMusicSkipped, isTrue);
        await startRun(g);
        g.runDebug.god = true;
        for (var i = 0; i < 60; i++) {
          if (i % 6 == 0) g.onScreenTap();
          g.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(g);
        }
        await flushAndMount(g);
        expect(focus.checks, greaterThan(1));
        expect(g.sound.ownMusicSkipped, isTrue);
        expect(g.sound.musicPlaying, isFalse);
      },
    );
  });
}
