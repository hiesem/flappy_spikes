// PRD-2.3 §19.4 / §19.6 performance check of the 60 new skin items: a
// profile build flown by the hoop-aware autopilot with the trail forced on
// (streak held at 5, so the equipped trail emits all the time).
//
//   flutter run --profile --no-uninstall -d 24191FDF6008ZD \
//     -t integration_test/skins_perf_main.dart
//   adb -s 24191FDF6008ZD logcat -s flutter | grep SKINPERF
//
// Phases: the 2.2 look (Classic flame, Classic hoop, no gear / hat) as the
// baseline, the heaviest 2.3 combination (Sunburst + Disco ball + Aurora +
// Supernova), then every 2.3 legendary on its own. Each phase prints build /
// raster percentiles and the frames over 16.7 ms. Its own SharedPreferences
// prefix keeps the owner's game data untouched. No ads, no services.
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _heavySeconds = int.fromEnvironment('SKINPERF_HEAVY', defaultValue: 120);
const int _shortSeconds = int.fromEnvironment('SKINPERF_SHORT', defaultValue: 30);

const List<(String, Look, int)> _phases = [
  ('baseline', Look.defaults, _shortSeconds * 2),
  (
    'heavy',
    Look(
      bird: 'classic',
      hat: 'sunburst',
      gear: 'disco',
      hoop: 'aurora',
      trail: 'supernova',
    ),
    _heavySeconds,
  ),
  ('planet', Look(bird: 'classic', hat: 'planet'), _shortSeconds),
  ('sunburst', Look(bird: 'classic', hat: 'sunburst'), _shortSeconds),
  ('crystal', Look(bird: 'classic', gear: 'crystal'), _shortSeconds),
  ('atom', Look(bird: 'classic', gear: 'atom'), _shortSeconds),
  ('disco', Look(bird: 'classic', gear: 'disco'), _shortSeconds),
  ('aurora', Look(bird: 'classic', hoop: 'aurora'), _shortSeconds),
  ('supernova', Look(bird: 'classic', trail: 'supernova'), _shortSeconds),
  ('paint', Look(bird: 'classic', trail: 'paint'), _shortSeconds),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('skinperf.');
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  } catch (_) {}
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final worldHeight = 320 * view.physicalSize.height / view.physicalSize.width;
  final game = FlappySpikesGame(worldHeight: worldHeight);
  runApp(RepaintBoundary(child: GameWidget(game: game)));
  await game.loaded;
  await game.storage.saveOwnedItems({for (final i in allItems) i.key});
  debugPrint('SKINPERF start: ${worldHeight.toStringAsFixed(1)} pt');
  for (final (name, look, seconds) in _phases) {
    for (final layer in SkinLayer.values) {
      await game.storage.saveEquippedItem(layer, look.idFor(layer));
    }
    await _fly(game, name, Duration(seconds: seconds));
  }
  debugPrint('SKINPERF done');
}

Future<void> _fly(FlappySpikesGame game, String phase, Duration length) async {
  final timings = <ui.FrameTiming>[];
  void cb(List<ui.FrameTiming> t) => timings.addAll(t);
  Autopilot? bot;
  Object? botRun;
  final done = Completer<void>();
  final sw = Stopwatch();
  // Each phase starts with a fresh run (the look is read at START).
  var restart = game.state != GameState.start;
  var counting = false;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    if (!counting && !restart && game.state == GameState.playing) {
      counting = true;
      sw.start();
      SchedulerBinding.instance.addTimingsCallback(cb);
    }
    if (sw.elapsed >= length) {
      if (!done.isCompleted) done.complete();
      return;
    }
    switch (game.state) {
      case GameState.start:
        restart = false;
        if (game.handleBack()) return;
        if (game.homeScreen != null) game.onScreenTap();
      case GameState.playing:
        final run = game.run;
        if (run == null) return;
        if (!identical(botRun, run)) {
          bot = Autopilot(run);
          botRun = run;
        }
        if (restart) {
          run.state.invulnerable = 0;
          game.onBirdHit(MistakeCause.missedHoop);
          return;
        }
        run.state.invulnerable = max(run.state.invulnerable, 2);
        run.state.streak = max(run.state.streak, 5);
        if (bot!.shouldFlap()) game.onScreenTap();
      case GameState.reviving:
        game.reviveScreen?.tapNoThanks();
      case GameState.bonus:
        game.bonusScreen?.tapNoThanks();
      case GameState.results:
        game.resultsScreen?.next();
      case GameState.versusIntro || GameState.paused || GameState.dying:
        break;
    }
  });
  await done.future;
  timer.cancel();
  SchedulerBinding.instance.removeTimingsCallback(cb);
  double ms(Duration d) => d.inMicroseconds / 1000;
  List<double> sorted(Iterable<double> v) => v.toList()..sort();
  double pct(List<double> s, double p) =>
      s.isEmpty ? 0 : s[min(s.length - 1, (s.length * p).floor())];
  final build = sorted(timings.map((t) => ms(t.buildDuration)));
  final raster = sorted(timings.map((t) => ms(t.rasterDuration)));
  var janky = 0, worst = 0.0;
  for (final t in timings) {
    final b = ms(t.buildDuration), r = ms(t.rasterDuration);
    if (b > 16.7 || r > 16.7) janky++;
    worst = max(worst, max(b, r));
  }
  String f(double v) => v.toStringAsFixed(2);
  debugPrint(
    'SKINPERF $phase: ${timings.length} frames in ${length.inSeconds} s; '
    'build p50 ${f(pct(build, .5))} p90 ${f(pct(build, .9))} '
    'p99 ${f(pct(build, .99))}; raster p50 ${f(pct(raster, .5))} '
    'p90 ${f(pct(raster, .9))} p99 ${f(pct(raster, .99))}; '
    'worst ${f(worst)} ms; over 16.7 ms: $janky '
    '(${f(100 * janky / max(1, timings.length))} %)',
  );
}
