import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

import '../p22/fake_audio.dart';

/// 2.4.0 (23) device bug (Pixel 8, 2026-10-16): many sound effects stayed
/// silent for the whole session. The iOS round-2b gate creates no player
/// while the app is not active; on Android the app is briefly `inactive`
/// at launch (the consent form, a Play Games banner, the notification
/// shade). A core sound skipped by the one-time warm-up was never created
/// afterwards, and the session warm-up stopped for good. A sound must
/// heal on its own once the app is active again.
void main() {
  final session = {...SoundService.prewarmed, ...SoundService.sessionWarm};

  test('the warm-up interrupted by an inactive app finishes on the return '
      '(core + session set)', () async {
    final audio = FakeAudio();
    final sound = audio.service();
    sound.setAppActive(false);
    await sound.warmSession();
    await flushAudio();
    for (final s in session) {
      expect(sound.poolOf(s), isNull, reason: '$s: nothing while inactive');
    }
    sound.setAppActive(true);
    // the whole set loads one pool after another
    for (var i = 0; i < 10; i++) {
      await flushAudio();
    }
    for (final s in session) {
      expect(sound.poolOf(s), isNotNull, reason: '$s after the return');
    }
    await sound.dispose();
  });

  test('a core sound the interrupted warm-up skipped is created by its '
      'next play (it is never silent for the session)', () async {
    final audio = FakeAudio();
    final sound = audio.service();
    final warm = sound.warmSession();
    sound.setAppActive(false); // inactive right after the warm-up started
    await warm;
    await flushAudio();
    final missing = [
      for (final s in SoundService.prewarmed)
        if (sound.poolOf(s) == null) s,
    ];
    expect(missing, isNotEmpty, reason: 'the warm-up was cut short');
    sound.setAppActive(true);
    for (final s in missing) {
      sound.play(s);
    }
    await flushAudio();
    for (final s in SoundService.prewarmed) {
      expect(sound.poolOf(s), isNotNull, reason: '$s');
    }
    await sound.dispose();
  });

  test('pools left short of voices while inactive are topped up on the '
      'return', () async {
    final audio = FakeAudio();
    final sound = audio.service();
    sound.play(Sfx.skTick); // a multi-voice burst pool
    sound.setAppActive(false); // goes inactive while its voices load
    await flushAudio();
    final pool = sound.poolOf(Sfx.skTick);
    expect(pool, isNotNull);
    sound.setAppActive(true);
    await flushAudio();
    expect(pool!.voiceCount, pool.capacity);
    await sound.dispose();
  });
}
