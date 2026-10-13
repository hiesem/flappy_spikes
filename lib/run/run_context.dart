import 'dart:math';

import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../menu/wallet.dart';
import '../versus/timeline.dart' show PointFlags;
import 'director/run_director.dart';
import 'mistakes.dart';
import 'run_controller.dart';
import 'run_events.dart';
import 'run_geometry.dart';
import 'run_layers.dart';
import 'run_state.dart';

/// The facade handed to hoop kinds, pickups and features (ARCH §1.1): read
/// access to the run plus the only side-effect sinks (sound, rumble,
/// analytics, wallet / score, mistakes, events).
class RunContext {
  RunContext(this.run);

  final RunController run;

  FlappySpikesGame get game => run.game;
  RunState get s => run.state;
  RunEvents get events => run.events;
  RunDirector get director => run.director;
  RunLayers get layers => run.layers;
  RunGeometry get geo => run.geo;
  double get viewHeight => s.viewHeight;

  /// Visual variety only — never changes spawns (§3.0.3).
  Random get cosmetic => director.rng.cosmetic;

  void sfx(Sfx sfx) => game.sound.play(sfx);

  LoopHandle loop(SfxLoop l, {double volume = 1}) =>
      game.sound.loop(l, volume: volume);

  /// Only `rumble_router.dart` (WP-2c) should call these (ARCH §2.7).
  void knock() => game.rumble.knock();
  void shake() => game.rumble.shake();

  void track(String event, [Map<String, Object>? params]) =>
      game.services.track(event, params);

  /// The only in-run coin path (ARCH §2.7): the wallet at once (kept if
  /// the run ends), YOUR REWARD, [CoinsEarned]. PRD-2.3 §14.3: the chick
  /// no longer doubles any coins.
  ///
  /// PRD-2.2 §13.6 a **coin bonus** (every source but the hoop / perfect
  /// pass coins and the versus win / draw bonus) also adds the same amount
  /// in **points** ([PointFlags.bonus]) — one place, so every bonus is
  /// covered (PRD-2.3 §14.2: unchanged).
  void earn(int coins, CoinSource source) {
    if (coins <= 0) return;
    s.coinsThisRun += coins;
    game.menu.wallet.add(coins, source);
    emit(CoinsEarned(coins, source));
    if (paysPoints(source)) addScore(coins, flags: PointFlags.bonus);
  }

  /// PRD-2.2 §13.1 whether coins from [source] are a coin bonus that also
  /// pays points (not the pass coins, not the versus win / draw bonus).
  static bool paysPoints(CoinSource source) => switch (source) {
    CoinSource.hoop || CoinSource.perfect || CoinSource.winBonus => false,
    _ => true,
  };

  /// Score (points) + HUD; the versus timeline records from [ScoreChanged]
  /// (WP-5b). [flags] = `PointFlags` (ride / train / gift / bonus).
  /// PRD-2.3 §14.3: the chick no longer doubles points (it adds +1 per
  /// hoop passed, `ScoringFeature`).
  void addScore(int n, {int flags = 0}) {
    if (n <= 0) return;
    final old = s.score;
    s.score += n;
    game.showRunScore(s.score);
    emit(ScoreChanged(old, s.score, flags: flags));
  }

  void mistake(Mistake m) => run.mistake(m);

  void emit(RunEvent e) => events.emit(e);
}
