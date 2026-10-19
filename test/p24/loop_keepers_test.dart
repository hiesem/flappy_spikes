import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

import '../p22/fake_audio.dart';

/// 2.4.0 (40) owner: at a portal ride the fire's crackle started only hoops
/// after the bird caught fire. Android's SoundPool unloaded the loop sample
/// with its last player and decoded it again on the next start, queued
/// behind the ride's preloaded cues. The session now holds every loop
/// sample (one idle keeper each), so a loop start reuses a loaded sample.
void main() {
  test('warmSession holds every loop sample; dispose releases them', () async {
    final audio = FakeAudio();
    final sound = audio.service();
    final kept = <SfxLoop>[];
    var released = 0;
    sound.loopKeeperFactory = (l) async {
      kept.add(l);
      return () async => released++;
    };
    await sound.warmSession();
    expect(kept, SfxLoop.values);
    expect(sound.keptLoops, SfxLoop.values.toSet());
    expect(kept, contains(SfxLoop.feverLoop));
    // Idempotent: a second warm-up creates nothing new.
    await sound.warmSession();
    expect(kept, hasLength(SfxLoop.values.length));
    // A loop that starts and stops never drops the held sample.
    final h = sound.loop(SfxLoop.feverLoop, volume: .25);
    await h.stop();
    expect(sound.keptLoops, contains(SfxLoop.feverLoop));
    await sound.dispose();
    expect(released, SfxLoop.values.length);
    expect(sound.keptLoops, isEmpty);
  });

  test('no keepers while muted or disabled', () async {
    for (final sound in [
      FakeAudio().service(muted: true),
      FakeAudio().service(enabled: false),
    ]) {
      var made = 0;
      sound.loopKeeperFactory = (l) async {
        made++;
        return () async {};
      };
      await sound.warmSession();
      expect(made, 0);
    }
  });

  test('a failed keeper is skipped, the others are kept', () async {
    final sound = FakeAudio().service();
    sound.loopKeeperFactory = (l) async =>
        l == SfxLoop.cometLoop ? null : () async {};
    await sound.warmSession();
    expect(sound.keptLoops, SfxLoop.values.toSet()..remove(SfxLoop.cometLoop));
  });
}
