import 'dart:math' as math;

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/squeeze_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/run_shake.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p22/fake_audio.dart';

/// PRD 2.5.1: the squeeze cues are preloaded (WP-SND) and the lock is a
/// vertical-only thump (WP-THUMP).
void main() {
  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  SqueezeFeature feature(RunController r) =>
      r.features.whereType<SqueezeFeature>().single;

  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: {'gamesPlayed': 5}, worldHeight: 711),
    gameSize: Vector2(320, 711),
  );

  // ------------------------------------------------------------ WP-SND
  tester().testGameWidget(
    '2.5.1 WP-SND: the cues are preloaded once in the idle window 3 s before '
    'the warning (never twice for the same moment), touched again at the '
    'warning and the late cues once in the hold; again for the next squeeze',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      final s = run.state;
      final sq = s.squeeze;
      final f = feature(run);
      await flyUntil(
        game,
        (r) => r.director.allowsSqueezeWarning(r.state.hoopIndex),
      );
      expect(f.preloads, 0, reason: 'the first squeeze is far away');
      sq.nextAt = s.runClock + 5;
      final preloadAt = <double>[];
      final phaseAt = <SqueezePhase>[];
      var last = f.preloads;
      void watch() {
        while (f.preloads > last) {
          last++;
          preloadAt.add(s.runClock);
          phaseAt.add(sq.phase);
        }
      }

      await flyUntil(game, (_) {
        watch();
        return sq.phase == SqueezePhase.warning;
      });
      watch();
      expect(phaseAt, [SqueezePhase.idle, SqueezePhase.warning]);
      // The idle preload came 3 s (± a frame) before the warning.
      expect(
        preloadAt[1] - preloadAt[0],
        closeTo(SqueezeConfig.preloadLead, 1 / 30),
      );
      await flyUntil(game, (_) {
        watch();
        return sq.phase == SqueezePhase.idle;
      }, maxSeconds: 60);
      watch();
      expect(phaseAt, [
        SqueezePhase.idle,
        SqueezePhase.warning,
        SqueezePhase.hold,
      ]);
      // The late cues came 3 s before the first tick (holdS − 6 s in).
      final holdStart =
          preloadAt[1] + SqueezeConfig.warning + SqueezeConfig.closing;
      expect(
        preloadAt[2] - holdStart,
        closeTo(
          math.max(
            0,
            sq.holdS - SqueezeConfig.lastTicks - SqueezeConfig.preloadLead,
          ),
          1 / 20,
        ),
      );
      // Idle again: nothing until the next moment's window.
      await flyUntil(game, (_) => false, maxSeconds: 2);
      watch();
      expect(f.preloads, 3);
      sq.nextAt = s.runClock + 4;
      await flyUntil(game, (_) {
        watch();
        return sq.phase == SqueezePhase.warning;
      });
      watch();
      // One idle preload per warning moment (a ride on the way that moves
      // the moment preloads once more, after the ride), then the warning.
      final second = phaseAt.sublist(3);
      expect(second.last, SqueezePhase.warning);
      expect(second.length, greaterThanOrEqualTo(2));
      expect(
        second.sublist(0, second.length - 1),
        everyElement(SqueezePhase.idle),
      );
    },
  );

  tester().testGameWidget(
    '2.5.1 WP-SND: a forced squeeze preloads at least 3 s before its warning',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game, force: [ElementId.squeeze]);
      final s = run.state;
      final f = feature(run);
      double? first;
      await flyUntil(game, (_) {
        if (first == null && f.preloads > 0) first = s.runClock;
        return s.squeeze.phase == SqueezePhase.warning;
      });
      expect(first, isNotNull);
      expect(
        s.runClock - first!,
        greaterThanOrEqualTo(SqueezeConfig.preloadLead - 1 / 30),
      );
      expect(f.preloads, 2);
    },
  );

  tester().testGameWidget(
    '2.5.1 WP-SND: a squeeze delayed by a ride preloads again before its '
    'warning; never while a ride runs',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      final s = run.state;
      final sq = s.squeeze;
      final f = feature(run);
      await flyUntil(
        game,
        (r) => r.director.allowsSqueezeWarning(r.state.hoopIndex),
      );
      sq.nextAt = s.runClock + 2;
      game.update(1 / 60);
      expect(f.preloads, 1, reason: 'due is within the 3 s lead');
      // A ride starts: no preload, even when the moment moves.
      s.ride = RideState(kind: RideKind.comet);
      for (var i = 0; i < 180; i++) {
        if (i == 30) sq.nextAt = s.runClock + .5;
        game.update(1 / 60);
        expect(f.preloads, 1, reason: 'no preload in a ride');
      }
      expect(sq.phase, SqueezePhase.idle);
      s.ride = null;
      run.events.emit(const RideEnded(RideKind.comet));
      final endedAt = s.runClock;
      var before = -1;
      await flyUntil(game, (_) {
        if (sq.phase == SqueezePhase.idle) before = f.preloads;
        return sq.phase == SqueezePhase.warning;
      });
      expect(before, 2, reason: 'the delayed moment is preloaded again');
      expect(f.preloads, 3);
      expect(s.runClock - endedAt, closeTo(SqueezeConfig.waitAfter, 1 / 30));
    },
  );

  group('2.5.1 WP-SND with fake voices', () {
    setUpAll(() {
      AudioplayersPlatformInterface.instance = FakeAudioPlatform();
      GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioPlatform();
      FlameAudio.audioCache = FakeAudioCache();
    });

    tester().testGameWidget(
      '2.5.1 every squeeze cue of the first squeeze finds its pool ready '
      '(no first-play drop) and starts a voice',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final audio = FakeAudio();
          final sound = game.sound
            ..enabled = true
            ..muted = false
            ..voiceFactory = audio.create;
          final missing = <Sfx>[];
          final played = <Sfx>[];
          sound.onPlay = (sfx) {
            if (!SqueezeFeature.cues.contains(sfx)) return;
            played.add(sfx);
            if (sound.poolOf(sfx) == null) missing.add(sfx);
          };
          game.runDebug.god = true;
          final run = await startRun(game, startHoopIndex: 45);
          final s = run.state;
          final sq = s.squeeze;
          final bot = Autopilot(run);
          Future<void> step(bool Function() done, int maxFrames) async {
            for (var i = 0; i < maxFrames && !done(); i++) {
              if (bot.shouldFlap()) game.onScreenTap();
              game.update(1 / 60);
              if (i % 5 == 0) await flushAudio();
            }
            await flushAudio();
          }

          await step(() => s.hoopsPassed >= 1, 60 * 20);
          sq.nextAt = s.runClock + 5;
          await step(() => sq.phase == SqueezePhase.warning, 60 * 20);
          expect(sq.phase, SqueezePhase.warning);
          await step(() => sq.phase == SqueezePhase.idle, 60 * 60);
          expect(sq.index, 1, reason: 'the squeeze ran to the end');
          expect(played.toSet(), SqueezeFeature.cues);
          expect(played.where((c) => c == Sfx.sqTick), hasLength(3));
          expect(missing, isEmpty, reason: 'played before the pool existed');
          for (final cue in SqueezeFeature.cues) {
            final file = SoundService.audioFiles[cue]!;
            final starts = audio.of(file).fold<int>(0, (n, v) => n + v.starts);
            expect(starts, greaterThan(0), reason: '$cue was dropped');
          }
          sound.onPlay = null;
          await sound.dispose();
          sound
            ..enabled = false
            ..voiceFactory = null;
        });
      },
    );
  });

  test('2.5.1 WP-SND: the hold re-touch keeps / recreates the late cues '
      'under the LRU cap after another preload took the reservation', () async {
    final audio = FakeAudio();
    var now = 0;
    final sound = audio.service()..clockMs = () => now;
    await sound.warmSession();
    await flushAudio();
    sound.preload(SqueezeFeature.cues);
    await flushAudio();
    for (final c in SqueezeFeature.cues) {
      expect(sound.poolOf(c), isNotNull, reason: '$c');
    }
    now += 1000;
    // A portal / comet preload during the squeeze takes the reservation.
    sound.preload(const {Sfx.puCometGet, Sfx.puCometEnd});
    await flushAudio();
    // Fill the cap with plays of other run-scoped cues.
    final pinned = {...SoundService.prewarmed, ...SoundService.sessionWarm};
    final others = [
      for (final s in Sfx.values)
        if (!pinned.contains(s) &&
            !SqueezeFeature.cues.contains(s) &&
            s != Sfx.puCometGet &&
            s != Sfx.puCometEnd)
          s,
    ];
    for (final s in others.take(Config.sfxMaxLivePools)) {
      now += 2000; // each previous copy has finished ringing
      sound.play(s);
      await flushAudio();
    }
    expect(sound.poolCount, lessThanOrEqualTo(Config.sfxMaxLivePools));
    now += 2000;
    sound.preload(SqueezeFeature.lateCues);
    await flushAudio();
    for (final c in SqueezeFeature.lateCues) {
      expect(sound.poolOf(c), isNotNull, reason: '$c');
    }
    // The ticks and the open play on their pools.
    sound
      ..play(Sfx.sqTick)
      ..play(Sfx.sqOpen);
    await flushAudio();
    for (final c in SqueezeFeature.lateCues) {
      final file = SoundService.audioFiles[c]!;
      expect(audio.of(file).fold<int>(0, (n, v) => n + v.starts), 1);
    }
    await sound.dispose();
  });

  // ------------------------------------------------------------ WP-THUMP
  test('2.5.1 WP-THUMP: RunShake.thump is vertical only, ≤ A, world down '
      'first, no step > 3 pt, exactly 0 after its time', () {
    final shake = RunShake(random: math.Random(1))
      ..thump(
        SqueezeConfig.lockThump,
        time: SqueezeConfig.lockThumpTime,
        freq: SqueezeConfig.lockThumpFreq,
      );
    expect(shake.active, isTrue);
    expect(shake.thumping, isTrue);
    expect(shake.amplitude, 0, reason: 'the thump is not a random shake');
    var prev = 0.0;
    double? firstNonZero;
    var t = 0.0;
    while (t < SqueezeConfig.lockThumpTime - 1e-9) {
      shake.update(1 / 60);
      t += 1 / 60;
      final o = shake.offset;
      expect(o.dx, 0);
      expect(o.dy.abs(), lessThanOrEqualTo(SqueezeConfig.lockThump));
      expect((o.dy - prev).abs(), lessThanOrEqualTo(3));
      if (firstNonZero == null && o.dy != 0) firstNonZero = o.dy;
      prev = o.dy;
    }
    expect(firstNonZero, isNotNull);
    expect(firstNonZero, lessThan(0), reason: 'viewfinder up = world down');
    shake.update(1 / 60);
    expect(shake.offset, Offset.zero);
    expect(shake.thumping, isFalse);
    expect(shake.active, isFalse);
    // stop() clears a running thump.
    shake
      ..thump(3)
      ..update(1 / 60)
      ..stop();
    expect(shake.offset, Offset.zero);
    expect(shake.active, isFalse);
  });

  test('2.5.1 WP-THUMP: a kick during a thump (tick tremble) adds the only '
      'sideways movement; the vertical part is kick + thump', () {
    final a = RunShake(random: math.Random(7))..thump(3);
    final b = RunShake(random: math.Random(7));
    a.update(1 / 60); // thump alone
    expect(a.offset.dx, 0);
    a.kick(SqueezeConfig.tickTremble);
    b.kick(SqueezeConfig.tickTremble);
    var t = 1 / 60;
    for (var i = 0; i < 10; i++) {
      a.update(1 / 60);
      b.update(1 / 60);
      t += 1 / 60;
      expect(a.offset.dx, b.offset.dx);
      final dy = RunShake.thumpAt(t, amplitude: 3, time: .3, freq: 7);
      expect(a.offset.dy, closeTo(b.offset.dy + dy, 1e-9));
    }
  });

  tester().testGameWidget(
    '2.5.1 WP-THUMP: at the lock the camera moves only vertically (world '
    'down first, ≤ 3 pt) and is back at its base after the thump',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game, startHoopIndex: 45);
      final s = run.state;
      final sq = s.squeeze;
      final f = feature(run);
      final vf = game.camera.viewfinder;
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      final base = vf.position.clone();
      sq.nextAt = s.runClock + .02;
      await flyUntil(game, (_) => sq.phase == SqueezePhase.hold);
      expect(f.shake.thumping, isTrue);
      final dys = <double>[];
      var t = f.phaseT;
      dys.add(vf.position.y - base.y);
      expect(vf.position.x, closeTo(base.x, 1e-4));
      while (t < SqueezeConfig.lockThumpTime + 1 / 60) {
        game.update(1 / 60);
        t += 1 / 60;
        expect(vf.position.x, closeTo(base.x, 1e-4), reason: 'no sideways');
        dys.add(vf.position.y - base.y);
      }
      expect(dys.first, lessThan(0), reason: 'viewfinder up = world down');
      for (final dy in dys) {
        expect(dy.abs(), lessThanOrEqualTo(SqueezeConfig.lockThump + 1e-4));
      }
      for (var i = 1; i < dys.length; i++) {
        expect((dys[i] - dys[i - 1]).abs(), lessThanOrEqualTo(3));
      }
      expect(f.shake.thumping, isFalse);
      expect(vf.position.y, closeTo(base.y, 1e-4));
    },
  );
}
