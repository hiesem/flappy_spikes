import 'dart:math';

import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../menu/wallet.dart';
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

  /// The only in-run coin path (ARCH §2.7): the chick's ×2, the wallet at
  /// once (kept if the run ends), YOUR REWARD, [CoinsEarned].
  void earn(int coins, CoinSource source) {
    if (coins <= 0) return;
    final x2 = s.egg?.stage == EggStage.chick;
    final amount = x2 ? coins * 2 : coins;
    s.coinsThisRun += amount;
    game.menu.wallet.add(amount, source);
    emit(CoinsEarned(amount, source, eggX2: x2));
  }

  /// Score + HUD; the versus timeline records from [ScoreChanged] (WP-5b).
  /// [flags] = `PointFlags` (ride / train / gift).
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
