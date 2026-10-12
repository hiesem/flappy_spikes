import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/soak.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_audio.dart';

/// PRD-2.2 §33.6 / S7-19 (final fix round): the session sound set is
/// created once and kept, every other pool lives for one run, so the live
/// native player count on Home is the same after every game.
void main() {
  final session = {...SoundService.prewarmed, ...SoundService.sessionWarm};
  final runScoped = [
    for (final s in Sfx.values)
      if (!session.contains(s)) s,
  ];
  final sessionVoices = session.fold<int>(
    0,
    (n, s) => n + SoundService.voicesFor(s),
  );

  test('the session set fits the live-pool cap with room for a run', () {
    expect(
      SoundService.prewarmed.intersection(SoundService.sessionWarm),
      isEmpty,
    );
    expect(session.length, lessThanOrEqualTo(Config.sfxMaxLivePools - 20));
  });

  test('warmSession creates the core set and the session set once', () async {
    final audio = FakeAudio();
    final sound = audio.service();
    await sound.warmSession();
    await flushAudio();
    for (final s in session) {
      expect(sound.poolOf(s), isNotNull, reason: '$s');
    }
    expect(sound.poolCount, session.length);
    expect(audio.live, sessionVoices);
    await sound.warmSession(); // idempotent
    await flushAudio();
    expect(audio.live, sessionVoices);
    await sound.dispose();
    expect(audio.live, 0);
  });

  test('muted: warmSession creates nothing (pinned for later)', () async {
    final audio = FakeAudio();
    final sound = audio.service(muted: true);
    await sound.warmSession();
    await flushAudio();
    expect(audio.created, 0);
  });

  test('20 simulated games: the live players on Home are the same after '
      'every game (flat from game 1), the run pools are disposed', () async {
    final audio = FakeAudio();
    var now = 0;
    final sound = audio.service()..clockMs = () => now;
    await sound.warmSession();
    await flushAudio();
    final onHome = <int>[];
    var peak = 0;
    for (var game = 0; game < 20; game++) {
      // In-run: flaps, passes, a perfect streak, the star trail.
      for (var i = 0; i < 40; i++) {
        sound.play(Sfx.flap);
        if (i.isEven) sound.play(Sfx.point);
        if (i % 4 == 0) sound.play(Sfx.perfect3);
        if (i % 5 == 0) {
          sound.play(SoundService.sessionWarm.elementAt(15 + i % 8));
        }
        now += 120;
        await flushAudio();
        if (audio.live > peak) peak = audio.live;
      }
      // A different mix of run-scoped cues every game (rides, power-ups).
      sound.preload([
        for (var k = 0; k < 6; k++)
          runScoped[(game * 13 + k) % runScoped.length],
      ]);
      await flushAudio();
      for (var k = 0; k < 14; k++) {
        sound.play(runScoped[(game * 11 + k * 3) % runScoped.length]);
        now += 200;
        await flushAudio();
        if (audio.live > peak) peak = audio.live;
      }
      // Post-run: 16 coin landings, 24 ticks, a level-up + CLAIM, bonus.
      for (var i = 0; i < 24; i++) {
        if (i < 16) sound.play(Sfx.bnCoin);
        sound.play(Sfx.skTick);
        now += 55;
        await flushAudio();
      }
      if (game % 5 == 3) {
        sound.play(Sfx.lvUp);
        sound.play(Sfx.lvClaim);
      }
      if (game % 5 == 2) {
        sound.play(Sfx.bnBalloonOpen);
        sound.play(Sfx.bnPrizeM);
      }
      // A run cue still ringing when NEXT is tapped (perfect_3-long one).
      final ringing = runScoped[(game * 7) % runScoped.length];
      sound.play(ringing);
      await flushAudio();
      // NEXT → Home.
      sound.endRun();
      await flushAudio();
      expect(sound.poolCount, lessThanOrEqualTo(Config.sfxMaxLivePools));
      // Home: a few seconds pass, the game ticks maintain().
      now += 5000;
      sound.maintain();
      await flushAudio();
      expect(sound.runEndedPending, 0);
      onHome.add(audio.live);
      expect(sound.poolCount, session.length, reason: 'game $game');
      expect(audio.live, sound.pooledVoices, reason: 'no orphan players');
    }
    expect(onHome.toSet(), {sessionVoices}, reason: '$onHome');
    expect(peak, lessThanOrEqualTo(Config.sfxMaxLivePools * 6));
    expect(sound.evictions, greaterThan(0));
    await sound.dispose();
    expect(audio.live, 0);
  });

  test('endRun keeps a ringing run pool until its copy has finished', () async {
    final audio = FakeAudio();
    var now = 0;
    final sound = audio.service()..clockMs = () => now;
    await sound.warmSession();
    await flushAudio();
    const cue = Sfx.sawHoleRoar;
    sound.play(cue);
    await flushAudio();
    final pool = sound.poolOf(cue)!;
    now += 50;
    sound.endRun();
    expect(sound.poolOf(cue), same(pool), reason: 'still ringing');
    expect(sound.runEndedPending, 1);
    sound.maintain();
    expect(sound.poolOf(cue), same(pool));
    now += pool.length.inMilliseconds + Config.sfxStopMarginMs;
    sound.maintain();
    await flushAudio();
    expect(sound.poolOf(cue), isNull);
    expect(pool.disposed, isTrue);
    expect(audio.live, sessionVoices);
    await sound.dispose();
  });

  test('a run-ended pool played again in the next run is kept', () async {
    final audio = FakeAudio();
    var now = 0;
    final sound = audio.service()..clockMs = () => now;
    await sound.warmSession();
    await flushAudio();
    const cue = Sfx.sawHoleRoar;
    sound.play(cue);
    await flushAudio();
    sound.endRun();
    expect(sound.runEndedPending, 1);
    sound.play(cue); // the next run starts and plays it again
    expect(sound.runEndedPending, 0);
    now += 100000;
    sound.maintain();
    expect(sound.poolOf(cue), isNotNull);
    await sound.dispose();
  });

  test(
    'the session set is never evicted, also idle over the pool cap',
    () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      await sound.warmSession();
      await flushAudio();
      for (final s in runScoped.take(Config.sfxMaxLivePools + 10)) {
        sound.play(s);
        now += Config.sfxTrimIntervalMs;
        await flushAudio();
      }
      now += Config.sfxPoolIdleDisposeMs * 2;
      sound.play(Sfx.flap); // runs the idle check
      await flushAudio();
      for (final s in session) {
        expect(sound.poolOf(s), isNotNull, reason: '$s');
      }
      expect(sound.poolCount, session.length);
      sound.endRun();
      expect(sound.poolCount, session.length);
      await sound.dispose();
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'the game: 6 soak games (bonus, level-up CLAIM) with fake voices; every '
    'Home arrival holds exactly the session set (replay → endRun)',
    setUp: (g, _) async => preloadImages(g),
    verify: (g, _) async {
      final audio = FakeAudio();
      var now = 0;
      g.sound
        ..enabled = true
        ..voiceFactory = audio.create
        ..clockMs = () => now;
      await g.sound.warmSession();
      await flushAudio();
      expect(audio.live, sessionVoices);
      final onHome = <int>[];
      final d = SoakDriver(
        g,
        games: 6,
        holdSeconds: 2,
        hoopsPerGame: 10,
        measured: {1, 2, 3, 4, 5, 6},
        log: (line) {
          if (line.startsWith('$kSoakTag hold ')) {
            onHome.add(audio.live);
            for (final s in Sfx.values) {
              if (g.sound.poolOf(s) != null) {
                expect(session, contains(s), reason: '$s on Home: $line');
              }
            }
          }
        },
      );
      g.soak = d;
      var runPools = 0;
      for (var s = 0; s < 2400 && d.phase != SoakPhase.done; s++) {
        for (var f = 0; f < 4; f++) {
          now += 250;
          await stepSeconds(g, 0.25);
        }
        await flushAudio();
        runPools = max(runPools, g.sound.poolCount - session.length);
      }
      expect(runPools, greaterThan(0), reason: 'the runs made run pools');
      expect(d.phase, SoakPhase.done);
      expect(onHome, hasLength(6));
      expect(onHome.toSet(), {sessionVoices}, reason: '$onHome');
      expect(audio.live, g.sound.pooledVoices);
      await g.sound.dispose();
      expect(audio.live, 0);
    },
  );
}
