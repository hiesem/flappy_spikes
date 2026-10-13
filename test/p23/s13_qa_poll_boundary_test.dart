import 'package:flappy_spikes/game/music_guard.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S8-04 §13.4 a MEDIA ding ending before 2 s resumes mid-run '
      'even without a stop callback', () async {
    final focus = FakeAudioFocus();
    final sound = SoundService(enabled: false);
    final guard = MusicGuard(
      sound: sound,
      focus: focus,
      onMenu: () => false,
      adShowing: () => false,
      adJustEnded: () => false,
      otherMusicNow: () async => focus.otherMusic,
      track: (_, _) {},
    );
    await sound.startMusic();
    focus.otherMusic = true;
    focus.push(
      const AudioWatchState(media: true, players: ['1:1']),
      notify: false,
    );
    guard.apply(focus.state);
    for (var i = 0; i < 30; i++) {
      if (i == 19) {
        // A 1.9 s notification; the finished player stays listed. The
        // next half-second poll must observe its inactive state.
        focus.otherMusic = false;
        focus.push(const AudioWatchState(players: ['1:0']), notify: false);
      }
      guard.update(.1);
      await Future<void>.value();
      await Future<void>.value();
    }
    expect(sound.ownMusicSkipped, isFalse);
    expect(sound.musicPlaying, isTrue);
  });
}
