import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flappy_spikes/game/music_backend.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../p22/fake_audio.dart';

/// A just_audio stand-in: every call recorded.
class _FakePort implements MusicPlayerPort {
  final List<String> calls = [];
  final StreamController<ja.PlayerState> states =
      StreamController<ja.PlayerState>.broadcast();
  AndroidAudioAttributes? attributes;
  int stateListens = 0;

  @override
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes a) async {
    attributes = a;
    calls.add('attributes');
  }

  @override
  Future<void> setAsset(String asset) async => calls.add('asset $asset');

  @override
  Future<void> setLoopMode(ja.LoopMode mode) async =>
      calls.add('loop ${mode.name}');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume $volume');

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');

  @override
  Future<void> seekToStart() async => calls.add('seek 0');

  @override
  void play() => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Stream<ja.PlayerState> get playerStateStream {
    stateListens++;
    return states.stream;
  }
}

/// A music backend that records the SoundService's calls.
class _FakeBackend implements MusicBackend {
  final List<String> calls = [];
  String current = 'none';

  @override
  Future<void> start(
    String file, {
    required double volume,
    required double rate,
  }) async {
    calls.add('start $file $volume $rate');
    current = 'playing';
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    current = 'paused';
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    current = 'playing';
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    current = 'stopped';
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('volume $volume');

  @override
  Future<void> setRate(double rate) async => calls.add('rate $rate');

  @override
  String get state => current;
}

/// PRD-2.3 §16.5: the seamless 56-bar music loop.
void main() {
  const oggPath = 'assets/audio/HappyBeat_loop_56bars.ogg';

  int u32(Uint8List b, int i) =>
      b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24;

  int indexOf(Uint8List b, List<int> pat, {int from = 0, bool last = false}) {
    bool at(int i) {
      for (var k = 0; k < pat.length; k++) {
        if (b[i + k] != pat[k]) return false;
      }
      return true;
    }

    if (last) {
      for (var i = b.length - pat.length; i >= 0; i--) {
        if (at(i)) return i;
      }
      return -1;
    }
    for (var i = from; i <= b.length - pat.length; i++) {
      if (at(i)) return i;
    }
    return -1;
  }

  group('§16.5 the asset', () {
    final bytes = File(oggPath).readAsBytesSync();

    test('the last Ogg page: granule position = 4 059 616 samples '
        '(56 bars at 146 BPM, 44 100 Hz)', () {
      final i = indexOf(bytes, 'OggS'.codeUnits, last: true);
      expect(i, greaterThanOrEqualTo(0));
      var granule = 0;
      for (var k = 7; k >= 0; k--) {
        granule = granule * 256 + bytes[i + 6 + k];
      }
      expect(granule, 4059616);
      expect(granule, (56 * 240 / 146 * 44100).round());
      // The last page carries the end-of-stream flag.
      expect(bytes[i + 5] & 0x04, 0x04);
    });

    test('the Vorbis identification header says 44 100 Hz, 2 channels', () {
      final i = indexOf(bytes, [0x01, ...'vorbis'.codeUnits]);
      expect(i, greaterThanOrEqualTo(0));
      expect(u32(bytes, i + 7), 0, reason: 'vorbis_version');
      expect(bytes[i + 11], 2);
      expect(u32(bytes, i + 12), 44100);
    });

    test('the ANDROID_LOOP=true comment is present', () {
      var k = indexOf(bytes, [0x03, ...'vorbis'.codeUnits]) + 7;
      final vendor = u32(bytes, k);
      k += 4 + vendor;
      final count = u32(bytes, k);
      k += 4;
      final comments = <String>[];
      for (var c = 0; c < count; c++) {
        final n = u32(bytes, k);
        k += 4;
        comments.add(String.fromCharCodes(bytes.sublist(k, k + n)));
        k += n;
      }
      expect(
        comments.map((c) => c.toUpperCase()),
        contains('ANDROID_LOOP=TRUE'),
      );
    });
  });

  group('§16.3 the music file per platform', () {
    test('Android and Linux get the OGG asset, iOS the same loop as AAC in '
        'the Runner bundle (iOS round 2 §1)', () {
      expect(
        SoundService.musicFileFor(isIOS: false),
        'HappyBeat_loop_56bars.ogg',
      );
      expect(
        SoundService.musicFileFor(isIOS: true),
        'HappyBeat_loop_56bars.m4a',
      );
      expect(
        File(
          'assets/audio/${SoundService.musicFileFor(isIOS: false)}',
        ).existsSync(),
        isTrue,
      );
      // iOS: a Runner bundle resource (Android never ships it), listed in
      // the Runner target's resources.
      final m4a = File('ios/Runner/${SoundService.iosMusicFile}');
      expect(m4a.existsSync(), isTrue);
      expect(m4a.lengthSync(), lessThan(3 * 1024 * 1024));
      final pbx = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(pbx, contains('${SoundService.iosMusicFile} in Resources */,'));
    });

    test('the iOS loop: AAC in MP4, 44 100 Hz, edit list = 1024 priming '
        'samples + 4 059 616 (the LoopMusic offset table)', () {
      final b = File(
        'ios/Runner/${SoundService.iosMusicFile}',
      ).readAsBytesSync();
      int u32be(int i) =>
          b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3];
      final elst = indexOf(b, 'elst'.codeUnits);
      expect(elst, greaterThan(0));
      final v = b[elst + 4];
      expect(v, 0, reason: 'version 0 edit list (ffmpeg)');
      expect(u32be(elst + 8), 1, reason: 'one entry');
      final mvhd = indexOf(b, 'mvhd'.codeUnits);
      final movieScale = u32be(mvhd + 4 + 12);
      final duration = u32be(elst + 12);
      final mediaTime = u32be(elst + 16);
      expect(mediaTime, 1024);
      expect((duration * 44100 / movieScale).round(), 4059616);
      final mdhd = indexOf(b, 'mdhd'.codeUnits);
      expect(u32be(mdhd + 4 + 12), 44100);
      expect(indexOf(b, 'mp4a'.codeUnits), greaterThan(0));
    });
  });

  group('iOS round 2 §1: the native loop backend (fake channel)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flappy_spikes/music');
    final calls = <String>[];
    var answer = 'playing';
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(
              call.arguments == null
                  ? call.method
                  : '${call.method} ${call.arguments}',
            );
            return answer;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('start / pause / resume / stop / volume / rate reach the runner; '
        'the state is the runner\'s last answer', () async {
      final music = NativeLoopMusic();
      expect(music.state, 'none');
      await music.start(SoundService.iosMusicFile, volume: .35, rate: .72);
      await music.setVolume(.5);
      await music.setRate(1);
      await music.pause();
      await music.resume();
      answer = 'stopped';
      await music.stop();
      expect(calls, [
        'state',
        'start {file: HappyBeat_loop_56bars.m4a, volume: 0.35, rate: 0.72}',
        'setVolume {volume: 0.5}',
        'setRate {rate: 1.0}',
        'pause',
        'resume',
        'stop',
      ]);
      expect(music.state, 'stopped');
    });
  });

  group('§16.4 step 2: the music on just_audio (fake music backend)', () {
    test('start sets the GAME attributes before the source, loop mode one, '
        'the volume and the speed, then plays', () async {
      final port = _FakePort();
      final music = JustAudioMusic(port: () => port);
      await music.start('HappyBeat_loop_56bars.ogg', volume: .35, rate: .72);
      expect(port.calls, [
        'attributes',
        'asset assets/audio/HappyBeat_loop_56bars.ogg',
        'loop one',
        'volume 0.35',
        'speed 0.72',
        'play',
      ]);
      // Rate 1 is not sent.
      final port2 = _FakePort();
      await JustAudioMusic(
        port: () => port2,
      ).start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
      expect(port2.calls.where((c) => c.startsWith('speed')), isEmpty);
    });

    test('pause and resume keep the position (no seek, no reload)', () async {
      final port = _FakePort();
      final music = JustAudioMusic(port: () => port);
      await music.start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
      port.calls.clear();
      await music.pause();
      await music.resume();
      expect(port.calls, ['pause', 'play']);
    });

    test(
      'a watchdog restart (stop, start) plays from the start of the loop',
      () async {
        final port = _FakePort();
        final music = JustAudioMusic(port: () => port);
        await music.start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
        port.calls.clear();
        await music.stop();
        await music.start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
        expect(port.calls, [
          'stop',
          'attributes',
          'asset assets/audio/HappyBeat_loop_56bars.ogg',
          'loop one',
          'volume 1.0',
          'play',
        ]);
      },
    );

    test('no audio-focus request, no session activation, attributes '
        'USAGE_GAME / CONTENT_TYPE_MUSIC', () async {
      expect(JustAudioMusic.handleInterruptions, isFalse);
      expect(JustAudioMusic.handleAudioSessionActivation, isFalse);
      expect(JustAudioMusic.applySessionAttributes, isFalse);
      final port = _FakePort();
      await JustAudioMusic(
        port: () => port,
      ).start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
      expect(port.attributes!.usage, AndroidAudioUsage.game);
      expect(port.attributes!.usage.value, 14);
      expect(port.attributes!.contentType, AndroidAudioContentType.music);
    });

    test('no position stream: only the player state stream is used, once '
        '(the watchdog state)', () async {
      final port = _FakePort();
      final music = JustAudioMusic(port: () => port);
      expect(music.state, 'none');
      await music.start('HappyBeat_loop_56bars.ogg', volume: 1, rate: 1);
      await music.pause();
      await music.resume();
      expect(port.stateListens, 1);
      port.states.add(ja.PlayerState(true, ja.ProcessingState.ready));
      await Future<void>.value();
      expect(music.state, 'playing');
      port.states.add(ja.PlayerState(false, ja.ProcessingState.ready));
      await Future<void>.value();
      expect(music.state, 'paused');
      port.states.add(ja.PlayerState(false, ja.ProcessingState.idle));
      await Future<void>.value();
      expect(music.state, 'stopped');
    });

    test(
      'SoundService keeps its music API: start / pause / resume, volume = '
      'musicVolume x duck, the Hourglass rate, the watchdog restart',
      () async {
        final audio = FakeAudio();
        final backend = _FakeBackend();
        final sound = audio.service()..musicBackend = backend;
        await sound.setMusicVolume(.5);
        await sound.duckMusic(.4);
        await sound.setMusicRate(.72);
        await sound.startMusic();
        await flushAudio();
        expect(backend.calls, ['start HappyBeat_loop_56bars.ogg 0.2 0.72']);
        backend.calls.clear();
        await sound.duckMusic(1);
        await sound.setMusicRate(1);
        sound.suspend();
        sound.resume();
        await flushAudio();
        expect(backend.calls, ['volume 0.5', 'rate 1.0', 'pause', 'resume']);
        backend.calls.clear();
        expect(sound.musicPlayerState, 'playing');
        await sound.restartMusic();
        await flushAudio();
        expect(backend.calls, [
          'stop',
          'start HappyBeat_loop_56bars.ogg 0.5 1.0',
        ]);
        await sound.dispose();
      },
    );
  });
}
