import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flappy_spikes/game/audio_counter.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_audio.dart';

/// PRD-2.2 §33.4 items 1–3 / §33.7: sound players never grow (hard cap,
/// oldest-copy steal, dispose never release), no position polling, bounded
/// lazy pools with the core run set kept.
void main() {
  /// Every cue a run may play (not the prewarmed set), for pool churn.
  final rare = [
    for (final s in Sfx.values)
      if (!SoundService.prewarmed.contains(s)) s,
  ];

  group('§33.7 20 simulated runs with heavy overlap (fake audio)', () {
    test('created players never exceed the caps; evicted pools are '
        'disposed; the pool count stays within its cap', () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.flap); // core warm-up
      await flushAudio();
      final perRunLive = <int>[];
      for (var run = 0; run < 20; run++) {
        // In-run: rapid flaps, passes, rim tonks, a perfect streak.
        for (var i = 0; i < 30; i++) {
          sound.play(Sfx.flap);
          if (i.isEven) sound.play(Sfx.point);
          if (i % 3 == 0) sound.play(Sfx.rimTonk);
          if (i % 4 == 0) sound.play(Sfx.perfect3);
          sound.play(Sfx.perfect1);
          now += 120;
          await flushAudio();
        }
        // 12 different rare cues per run (power-ups, rides, rings …).
        for (var k = 0; k < 12; k++) {
          sound.play(rare[(run * 12 + k) % rare.length]);
          now += 300;
          await flushAudio();
        }
        // Results: 16 coin landings 55 ms apart, 24 ticks, a level-up.
        for (var i = 0; i < 24; i++) {
          if (i < 16) sound.play(Sfx.bnCoin);
          sound.play(Sfx.skTick);
          sound.play(Sfx.piggyCoin);
          now += 55;
          await flushAudio();
        }
        sound.play(Sfx.lvUp);
        sound.play(Sfx.lvClaim);
        now += 60000; // ≈ a minute per game
        await flushAudio();
        perRunLive.add(audio.live);

        // The caps hold at every point.
        expect(sound.poolCount, lessThanOrEqualTo(Config.sfxMaxLivePools));
        final byFile = <String, int>{};
        for (final v in audio.voices.where((v) => !v.disposed)) {
          byFile[v.file] = (byFile[v.file] ?? 0) + 1;
        }
        for (final e in SoundService.audioFiles.entries) {
          expect(
            byFile[e.value] ?? 0,
            lessThanOrEqualTo(SoundService.voicesFor(e.key)),
            reason: '${e.key} over its cap in run $run',
          );
        }
        expect(audio.live, sound.pooledVoices, reason: 'no orphan players');
      }
      // Overlap really happened (the steal path ran) and nothing leaked.
      final steals = [
        for (final s in [Sfx.bnCoin, Sfx.skTick, Sfx.flap, Sfx.perfect3])
          sound.poolOf(s)?.steals ?? 0,
      ];
      expect(steals.reduce((a, b) => a + b), greaterThan(0));
      expect(sound.evictions, greaterThan(0), reason: 'idle pools evicted');
      // Bounded: the live players never exceed the worst case of the caps.
      for (final n in perRunLive) {
        expect(n, lessThanOrEqualTo(Config.sfxMaxLivePools * 6));
      }
      // Players flat from game 2: idle eviction keeps the live set to
      // the core set plus the cues of the last few games.
      final tail = perRunLive.skip(5);
      expect(
        tail.reduce((a, b) => a > b ? a : b) -
            tail.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(20),
      );
      await sound.dispose();
      expect(audio.live, 0, reason: 'teardown disposes every player');
    });

    test('the core run set is never evicted, also over the pool cap', () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.flap);
      await flushAudio();
      for (final s in rare.take(Config.sfxMaxLivePools + 10)) {
        sound.play(s);
        now += Config.sfxTrimIntervalMs;
        await flushAudio();
      }
      now += Config.sfxPoolIdleDisposeMs * 2;
      sound.play(Sfx.flap); // runs the idle check
      await flushAudio();
      for (final s in SoundService.prewarmed) {
        expect(sound.poolOf(s), isNotNull, reason: '$s');
      }
      expect(sound.poolCount, SoundService.prewarmed.length);
      expect(audio.live, sound.pooledVoices);
      await sound.dispose();
    });

    test('an evicted cue is created again on its next play', () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.eggHatch);
      await flushAudio();
      expect(sound.poolOf(Sfx.eggHatch), isNotNull);
      now += Config.sfxPoolIdleDisposeMs + Config.sfxTrimIntervalMs;
      sound.play(Sfx.flap);
      await flushAudio();
      expect(sound.poolOf(Sfx.eggHatch), isNull);
      expect(audio.of('egg_hatch.mp3').every((v) => v.disposed), isTrue);
      sound.play(Sfx.eggHatch); // lazily created again, first play heard
      await flushAudio();
      expect(sound.poolOf(Sfx.eggHatch), isNotNull);
      expect(
        audio.of('egg_hatch.mp3').where((v) => !v.disposed).first.starts,
        1,
      );
      await sound.dispose();
    });

    test('a pool still ringing is not evicted by the pool cap', () async {
      final audio = FakeAudio();
      var now = 0;
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.lvUpBig); // 3.4 s, the least recently used pool
      await flushAudio();
      now = 1000;
      for (final s in rare.where((s) => s != Sfx.lvUpBig).take(45)) {
        sound.play(s); // each new pool runs the cap check
        await flushAudio();
      }
      expect(sound.poolOf(Sfx.lvUpBig), isNotNull, reason: 'still ringing');
      now = 1000 + Config.sfxTrimIntervalMs; // lv_up_big has ended
      sound.play(Sfx.flap);
      await flushAudio();
      expect(sound.poolOf(Sfx.lvUpBig), isNull, reason: 'LRU, now idle');
      expect(sound.poolCount, lessThanOrEqualTo(Config.sfxMaxLivePools));
      await sound.dispose();
    });

    test('preload creates pools without playing and marks them used', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.preload([Sfx.puPortal, Sfx.rdSeaWhale]);
      await flushAudio();
      expect(sound.poolOf(Sfx.puPortal), isNotNull);
      expect(sound.poolOf(Sfx.rdSeaWhale), isNotNull);
      expect(audio.starts, 0, reason: 'preload never plays');
      sound.play(Sfx.rdSeaWhale);
      await flushAudio();
      expect(audio.starts, 1, reason: 'the first play after preload is heard');
      await sound.dispose();
    });
  });

  group('§33.4 the real players (fake audioplayers platform)', () {
    late FakeAudioPlatform platform;
    late FakeGlobalAudioPlatform global;
    late CountingAudioPlatform counter;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      platform = FakeAudioPlatform();
      global = FakeGlobalAudioPlatform();
      counter = CountingAudioPlatform(platform);
      AudioplayersPlatformInterface.instance = counter;
      GlobalAudioplayersPlatformInterface.instance = global;
      FlameAudio.audioCache = FakeAudioCache();
    });

    test('SFX, loops and music never poll their position; the voice set is '
        'created once, low-latency, under one global context', () async {
      final sound = SoundService();
      sound.play(Sfx.flap); // core warm-up
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final core = SoundService.prewarmed.fold<int>(
        0,
        (n, s) => n + SoundService.voicesFor(s),
      );
      expect(counter.creates, core);
      expect(
        platform.modes.values.every((m) => m == PlayerMode.lowLatency),
        isTrue,
      );
      expect(global.contexts, hasLength(1), reason: 'one global context');
      // PRD-2.2 §28.3: mixWithOthers (no focus request) with the Android
      // usage GAME, so the game's players can be told from other apps'.
      expect(global.contexts.single, SoundService.gameAudioContext());
      expect(
        global.contexts.single.android.audioFocus,
        AndroidAudioFocus.none,
      );
      expect(
        global.contexts.single.android.usageType,
        AndroidUsageType.game,
      );
      expect(platform.contextWrites, isEmpty, reason: 'no per-player context');

      // Heavy overlap: more plays than players.
      for (var i = 0; i < 12; i++) {
        sound.play(Sfx.flap);
        sound.play(Sfx.perfect3);
        sound.play(Sfx.point);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final loop = sound.loop(SfxLoop.cometLoop);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await loop.stop();
      await sound.startMusic();
      await FlameAudio.bgm.stop();
      // Let every stop timer fire (perfect_3: 2.4 s).
      await Future<void>.delayed(const Duration(milliseconds: 2600));

      expect(counter.starts, greaterThan(12));
      expect(
        counter.positionPolls,
        0,
        reason: 'stop / stopAndUpdate would poll with a position updater',
      );
      expect(counter.creates, core + 1 + 1, reason: '+ the loop + the music');
      // The loop's dispose + Bgm.play's own release before its setSource;
      // never an SFX player.
      expect(counter.releases, 2);
      expect(counter.disposes, 1, reason: 'the stopped loop');
      expect(counter.live, core + 1, reason: 'the core set + the music');

      await sound.dispose();
      expect(counter.live, 1, reason: 'only the music player is left');
      expect(counter.positionPolls, 0);
    });
  });
}
