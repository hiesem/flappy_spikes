import 'package:flame_audio/flame_audio.dart';

/// Sound effects used by the game (files live in assets/audio/).
enum Sfx { flap, point, gameover, click }

class SoundService {
  SoundService({this.muted = false, this.enabled = true});

  static const Map<Sfx, String> _files = {
    Sfx.flap: 'flap.mp3',
    Sfx.point: 'point.mp3',
    Sfx.gameover: 'gameover.mp3',
    Sfx.click: 'click.mp3',
  };

  bool muted;

  /// Master switch for audio output. Headless tests set this to false so no
  /// calls reach the audioplayers platform channel (which has no test
  /// backend and would throw [MissingPluginException]).
  bool enabled;

  void play(Sfx sfx) {
    if (muted || !enabled) {
      return;
    }
    FlameAudio.play(_files[sfx]!);
  }
}
