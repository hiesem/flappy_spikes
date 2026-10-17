import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Audit A3-3: the app goes to the background while the launch "own
/// music?" check is still pending. The check (and the music start with it)
/// was dropped, and the foreground check only cleared the background: the
/// game music stayed off for the whole session.
void main() {
  Future<void> advance(FlappySpikesGame g, double seconds) async {
    var t = 0.0;
    while (t < seconds - 1e-9) {
      stepGame(g, .1);
      t += .1;
      await flushAndMount(g);
    }
  }

  final focus = FakeAudioFocus()..otherMusic = true;
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711)..audioFocus = focus,
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'A3-3 backgrounded during the launch music check: the music still '
    'starts after the return',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      expect(g.musicGuard.confirming, isTrue, reason: 'first yes: waits 1 s');
      expect(g.sound.musicWanted, isFalse);
      await advance(g, .3);
      g.lifecycleStateChange(AppLifecycleState.paused);
      await flushAndMount(g);
      focus.otherMusic = false; // the player's own music stops meanwhile
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await flushAndMount(g);
      await advance(g, 4);
      expect(g.sound.background, isFalse);
      expect(g.sound.musicWanted, isTrue);
      expect(g.sound.musicPlaying, isTrue);
    },
  );
}
