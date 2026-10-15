import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/native_loops.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p22/fake_audio.dart';

/// iOS round 2 §2: audio after the background / a lock / a media-services
/// reset.
void main() {
  final session = {...SoundService.prewarmed, ...SoundService.sessionWarm};

  group('SoundService.rebuildVoices', () {
    test('disposes every voice and creates the core + session set again; '
        'loops are kept', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      await sound.warmSession();
      await flushAudio();
      final before = audio.live;
      final loop = sound.loop(SfxLoop.values.first);
      await flushAudio();
      final firstVoices = List.of(audio.voices);
      await sound.rebuildVoices('test');
      await flushAudio();
      expect(sound.rebuilds, 1);
      expect(firstVoices.every((v) => v.disposed), isTrue);
      expect(audio.live, before, reason: 'the same set, fresh players');
      for (final s in session) {
        expect(sound.poolOf(s), isNotNull, reason: '$s');
      }
      expect(loop.stopped, isFalse);
      await sound.dispose();
    });

    test('a sound whose first voice failed tries again after '
        'Config.sfxRetryFailedMs (never on every play)', () async {
      var now = 0;
      final audio = FakeAudio()..failing.add('sk_close.mp3');
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.skClose);
      await flushAudio();
      expect(sound.poolOf(Sfx.skClose), isNull);
      audio.failing.clear();
      now = Config.sfxRetryFailedMs - 1;
      sound.play(Sfx.skClose);
      await flushAudio();
      expect(sound.poolOf(Sfx.skClose), isNull, reason: 'cool-down');
      now = Config.sfxRetryFailedMs + 1;
      sound.play(Sfx.skClose);
      await flushAudio();
      expect(sound.poolOf(Sfx.skClose), isNotNull);
      await sound.dispose();
    });
  });

  group('round 2b: nothing is created while the app is not active', () {
    test('a rebuild in the background only disposes; one rebuild on the '
        'return however many resets came', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      await sound.warmSession();
      await flushAudio();
      final live = audio.live;
      final created = audio.created;
      sound.setAppActive(false);
      for (var i = 0; i < 5; i++) {
        await sound.rebuildVoices('media-services-reset');
        await flushAudio();
      }
      expect(audio.live, 0, reason: 'dead players dropped');
      expect(audio.created, created, reason: 'none created in background');
      expect(sound.rebuilds, 0);
      expect(sound.deferredRebuilds, 5);
      expect(sound.rebuildPending, isTrue);
      // A play / preload in the background creates nothing either.
      sound.play(Sfx.skClose);
      sound.preload([Sfx.lvUp]);
      await flushAudio();
      expect(audio.created, created);
      sound.setAppActive(true);
      await sound.rebuildVoices('foreground');
      await flushAudio();
      expect(sound.rebuilds, 1);
      expect(sound.rebuildPending, isFalse);
      expect(audio.live, live);
      await sound.dispose();
    });

    test('a request while a rebuild runs folds into it', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      final a = sound.rebuildVoices('a');
      final b = sound.rebuildVoices('b');
      await Future.wait([a, b]);
      expect(sound.rebuilds, 1);
      await sound.dispose();
    });

    test('the failed-voice retry does not fire while not active', () async {
      var now = 0;
      final audio = FakeAudio()..failing.add('sk_close.mp3');
      final sound = audio.service()..clockMs = () => now;
      sound.play(Sfx.skClose);
      await flushAudio();
      audio.failing.clear();
      sound.setAppActive(false);
      now = Config.sfxRetryFailedMs + 1;
      sound.play(Sfx.skClose);
      await flushAudio();
      expect(sound.poolOf(Sfx.skClose), isNull);
      sound.setAppActive(true);
      sound.play(Sfx.skClose);
      await flushAudio();
      expect(sound.poolOf(Sfx.skClose), isNotNull);
      await sound.dispose();
    });
  });

  group('§3 seamless loops on the native player (iOS)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flappy_spikes/loops');
    final calls = <String>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add('${call.method} ${call.arguments}');
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('start / volume / interruption quiet / stop go to the runner; no '
        'AVPlayer loop', () async {
      final sound = SoundService()..nativeLoops = NativeSfxLoops();
      final h = sound.loop(SfxLoop.feverLoop, volume: .6);
      await h.setVolume(.3);
      sound.setInterrupted(true);
      sound.setInterrupted(false);
      await h.stop();
      await h.stop(); // idempotent
      await pumpEventQueue();
      expect(calls, [
        'start {id: 1, asset: assets/audio/fever_loop.wav, volume: 0.6}',
        'setVolume {id: 1, volume: 0.3}',
        'setVolume {id: 1, volume: 0.0}',
        'setVolume {id: 1, volume: 0.3}',
        'stop {id: 1}',
      ]);
    });

    test('muted: a silent recorder, nothing reaches the runner', () async {
      final sound = SoundService(muted: true)..nativeLoops = NativeSfxLoops();
      final h = sound.loop(SfxLoop.cometLoop);
      await h.stop();
      await pumpEventQueue();
      expect(calls, isEmpty);
    });
  });

  group('the game', () {
    var now = DateTime(2026, 10, 15, 12);
    final focus = FakeAudioFocus();
    final tester = FlameTester<FlappySpikesGame>(
      () =>
          createRunTestGame(worldHeight: 711, clock: () => now)
            ..audioFocus = focus,
      gameSize: Vector2(320, 711),
    );

    Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    }

    tester.testGameWidget(
      'a media-services reset (iOS AudioWatch `resets`) rebuilds the voices',
      setUp: boot,
      verify: (g, _) async {
        expect(g.sound.rebuilds, 0);
        focus.push(const AudioWatchState(resets: 1));
        await flushAndMount(g);
        expect(g.sound.rebuilds, 1);
        focus.push(const AudioWatchState(resets: 1));
        await flushAndMount(g);
        expect(g.sound.rebuilds, 1, reason: 'once per reset');
      },
    );

    tester.testGameWidget(
      'resets in the background: deferred, then ONE rebuild on resumed '
      '(also on Android-style short trips)',
      setUp: boot,
      verify: (g, _) async {
        g.lifecycleStateChange(AppLifecycleState.inactive);
        g.lifecycleStateChange(AppLifecycleState.hidden);
        g.lifecycleStateChange(AppLifecycleState.paused);
        for (var i = 1; i <= 4; i++) {
          focus.push(AudioWatchState(resets: i));
          await flushAndMount(g);
        }
        expect(g.sound.rebuilds, 0);
        expect(g.sound.rebuildPending, isTrue);
        g.lifecycleStateChange(AppLifecycleState.hidden);
        g.lifecycleStateChange(AppLifecycleState.inactive);
        expect(g.sound.rebuilds, 0, reason: 'inactive is not active');
        g.lifecycleStateChange(AppLifecycleState.resumed);
        await flushAndMount(g);
        expect(g.sound.rebuilds, 1);
        expect(g.sound.rebuildPending, isFalse);
      },
    );

    tester.testGameWidget(
      'iOS: back from >= 20 s in the background rebuilds the voices; a '
      'short trip or Android does not',
      setUp: boot,
      verify: (g, _) async {
        void away(Duration d) {
          g.lifecycleStateChange(AppLifecycleState.inactive);
          g.lifecycleStateChange(AppLifecycleState.hidden);
          g.lifecycleStateChange(AppLifecycleState.paused);
          now = now.add(d);
          g.lifecycleStateChange(AppLifecycleState.hidden);
          g.lifecycleStateChange(AppLifecycleState.inactive);
          g.lifecycleStateChange(AppLifecycleState.resumed);
        }

        away(const Duration(minutes: 5));
        expect(g.sound.rebuilds, 0, reason: 'not iOS');
        g.isIOS = () => true;
        away(const Duration(seconds: 5));
        expect(g.sound.rebuilds, 0, reason: 'short trip');
        away(Config.iosVoiceRebuildAfter);
        expect(g.sound.rebuilds, 1);
        expect(
          g.sound.musicLog.events.where(
            (e) => e.startsWith('foreground-check'),
          ),
          isNotEmpty,
        );
      },
    );
  });
}
