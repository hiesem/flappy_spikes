import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All sprite assets the game may load, so that component onLoads complete
/// on cache hits (microtasks) instead of real async decodes.
const kAllImages = [
  'bird.png',
  'bird_flap.png',
  'bird_dead.png',
  'pipe_top.png',
  'pipe_bottom.png',
  'ground_spikes.png',
  'background_score.png',
  'title.png',
  'gameover_title.png',
  'pointsfield.png',
  'replaybutton.png',
  'sharebutton.png',
  'soundbutton.png',
  'mutebutton.png',
  'gamcenter.png',
  'gamecenter_gameover.png',
];

/// Creates a [FlappySpikesGame] with mocked SharedPreferences.
///
/// Must be called inside a testWidgets binding (e.g. via [FlameTester]'s
/// createGame callback) so the mock is installed before the game's onLoad
/// reads persistence. [worldHeight] overrides the playfield height (default:
/// the 568 pt design height).
FlappySpikesGame createTestGame(
  [Map<String, Object> initialPrefs = const {},
  double? worldHeight,
]) {
  SharedPreferences.setMockInitialValues(initialPrefs);
  return FlappySpikesGame(worldHeight: worldHeight);
}

/// Pre-decodes every sprite into the game's image cache. Call in setUp
/// (which runs inside runAsync, where real image decoding works).
Future<void> preloadImages(FlappySpikesGame game) =>
    game.images.loadAll(kAllImages);

/// Lets components that were added during fixed-stepping finish mounting:
/// flushes pending microtasks (their onLoads only need cache hits after
/// [preloadImages]) and processes queued lifecycle events via a zero-dt
/// update (which does not advance game time).
Future<void> flushAndMount(FlappySpikesGame game) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
    game.update(0);
  }
}

/// Fixed-steps the game (and its Forge2D world) for [seconds] of game time.
///
/// When [flapBelow] is provided, taps the screen whenever the bird drops
/// below that y coordinate while playing. This keeps the bird airborne in a
/// safe altitude band (unlike a fixed flap interval, which can staircase the
/// bird into the ceiling spikes).
void stepGame(
  FlappySpikesGame game,
  double seconds, {
  double dt = 1 / 60,
  double? flapBelow,
}) {
  var elapsed = 0.0;
  while (elapsed < seconds - 1e-9) {
    game.update(dt);
    elapsed += dt;
    if (flapBelow != null && game.state == GameState.playing) {
      final birds = game.world.children.query<Bird>();
      if (birds.isNotEmpty && birds.first.body.position.y > flapBelow) {
        game.onScreenTap();
      }
    }
  }
}
