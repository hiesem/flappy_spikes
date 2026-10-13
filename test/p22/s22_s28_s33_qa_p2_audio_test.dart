import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_audio.dart';

/// Models AudioWatch.otherMusicActive's `media || isMusicActive` fallback:
/// the music stream also contains the game's USAGE_GAME one-shots. No
/// Android/device assertion is made by this plugin-free regression.
class _AndroidMusicStreamFocus extends NoopAudioFocus {
  bool externalMedia = true;
  double now = 0;
  double ownSfxUntil = 0;
  int checks = 0;

  @override
  Future<bool> isOtherMusicActive() async {
    checks++;
    return externalMedia || now < ownSfxUntil;
  }
}

/// QA P2: exercise actual voice state, including asynchronous creation.
void main() {
  for (final ad in [true, false]) {
    test('§28 ${ad ? 'ad suspend' : 'transient interruption'} silences '
        'one-shots already ringing, including a stolen copy', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.preload([Sfx.perfect3]);
      await flushAudio();
      for (var i = 0; i < 4; i++) {
        sound.play(Sfx.perfect3);
      }
      await flushAudio();
      expect(sound.poolOf(Sfx.perfect3)!.steals, 1);
      expect(audio.of('perfect_3.mp3').where((v) => v.playing), hasLength(3));
      if (ad) {
        sound.suspend();
      } else {
        sound.setInterrupted(true);
      }
      await flushAudio();
      final ringing = audio.of('perfect_3.mp3').where((v) => v.playing).length;
      // Clean up before asserting, so the failure leaves no pending timer.
      await sound.dispose();
      expect(ringing, 0, reason: 'all game audio quiet under ads / calls');
    });
  }

  test('§33 dispose during first-voice load cannot publish new pools or '
      'leave native players alive afterwards', () async {
    final audio = FakeAudio();
    final ready = Completer<void>();
    audio.gates['flap.mp3'] = ready;
    audio.gates['lv_up.mp3'] = ready;
    final sound = audio.service();
    sound.preload([Sfx.lvUp]); // core flap + a lazy pool are both loading
    await flushAudio();
    expect(audio.created, 0);
    await sound.dispose();
    ready.complete();
    await flushAudio();
    final poolsAfterDispose = sound.poolCount;
    final liveAfterDispose = audio.live;
    await sound.dispose();
    expect(poolsAfterDispose, 0, reason: 'late creations must be disposed');
    expect(liveAfterDispose, 0);
  });

  test('§33 preload enforces the live-pool cap even when every newly '
      'created pool has never played', () async {
    final audio = FakeAudio();
    final sound = audio.service()..clockMs = () => 0;
    final rare = Sfx.values.where((s) => !SoundService.prewarmed.contains(s));
    sound.preload(rare.take(Config.sfxMaxLivePools + 1));
    // Preloading should not classify a never-played pool as ringing.
    for (var i = 0; i < 5; i++) {
      await flushAudio();
    }
    expect(audio.starts, 0);
    final peak = sound.poolCount;
    await sound.dispose();
    expect(peak, lessThanOrEqualTo(Config.sfxMaxLivePools));
  });

  test('§28 a lazy one-shot requested before suspend never plays late '
      'after its pool finishes loading', () async {
    final audio = FakeAudio();
    final ready = Completer<void>();
    audio.gates['egg_peep.mp3'] = ready;
    final sound = audio.service();
    sound.play(Sfx.eggPeep);
    await flushAudio();
    sound.suspend();
    ready.complete();
    await flushAudio();
    sound.resume();
    await flushAudio();
    expect(audio.of('egg_peep.mp3').every((v) => v.starts == 0), isTrue);
    await sound.dispose();
    expect(audio.live, 0);
  });

  group('S7-13', () {
    final focus = _AndroidMusicStreamFocus();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711)..audioFocus = focus,
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§28.3 run-start music resumes after external media stops even '
      'while the player keeps flapping (Android stream fallback model)',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        // PRD-2.3 §13.4: own music needs two yes answers 1 s apart.
        await settleMusicChecks(g);
        expect(g.sound.ownMusicSkipped, isTrue);
        focus.externalMedia = false;
        g.sound.onAudible = (sfx) {
          final length = SoundService.lengthOf(SoundService.audioFiles[sfx]!);
          focus.ownSfxUntil = focus.now + length.inMicroseconds / 1e6;
        };
        await startRun(g);
        g.runDebug.god = true;
        for (var i = 0; i < 60; i++) {
          focus.now += 1 / 60;
          if (i % 6 == 0) g.onScreenTap();
          g.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(g);
        }
        await flushAndMount(g);
        expect(focus.checks, greaterThan(1));
        expect(focus.externalMedia, isFalse);
        expect(g.sound.musicPlaying, isTrue);
        expect(g.sound.ownMusicSkipped, isFalse);
      },
    );
  });
}
