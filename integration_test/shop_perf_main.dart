// Audit A1 (2026-10-17): frame-time check of the skin shop preview with each
// heavy trail tried on (the owner saw the preview slow down with Galaxy
// dust) and of the LEVELS list. Opens the skin shop on the TRAILS tab, tries every listed trail on
// for [_seconds] s (its tile scrolled into view) and prints build / raster
// percentiles. Own SharedPreferences prefix; no ads, no services.
//
//   flutter run --profile -d linux -t integration_test/shop_perf_main.dart
//   flutter run --profile --no-uninstall -d <device> \
//     -t integration_test/shop_perf_main.dart   # then: logcat | grep SHOPPERF
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _seconds = int.fromEnvironment('SHOPPERF_SECONDS', defaultValue: 10);

const List<String> _trails = [
  'flame',
  'galaxy',
  'supernova',
  'bolt',
  'prism',
  'echo',
  'flame',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('shopperf.');
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final worldHeight = 320 * view.physicalSize.height / view.physicalSize.width;
  final game = FlappySpikesGame(worldHeight: worldHeight);
  runApp(RepaintBoundary(child: GameWidget(game: game)));
  await game.loaded;
  await Future<void>.delayed(const Duration(seconds: 2));
  // The LEVELS list (locked rows draw greyed emblems).
  game.openLevels();
  await Future<void>.delayed(const Duration(seconds: 1));
  await _measure('levels', Duration(seconds: _seconds));
  game.handleBack();
  await Future<void>.delayed(const Duration(seconds: 1));
  game.openSkins(layer: SkinLayer.trail);
  await Future<void>.delayed(const Duration(seconds: 1));
  debugPrint('SHOPPERF start: ${worldHeight.toStringAsFixed(1)} pt');
  for (final (i, id) in _trails.indexed) {
    final shop = game.skinShop;
    if (shop == null) break;
    game.tapItem(SkinLayer.trail, id, fromTile: true);
    shop.scrollToItem(id);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _measure('$i:$id', Duration(seconds: _seconds));
  }
  debugPrint('SHOPPERF done');
  if (Platform.isLinux) exit(0);
}

Future<void> _measure(String phase, Duration length) async {
  final timings = <ui.FrameTiming>[];
  void cb(List<ui.FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(cb);
  await Future<void>.delayed(length);
  SchedulerBinding.instance.removeTimingsCallback(cb);
  double ms(Duration d) => d.inMicroseconds / 1000;
  List<double> sorted(Iterable<double> v) => v.toList()..sort();
  double pct(List<double> s, double p) =>
      s.isEmpty ? 0 : s[min(s.length - 1, (s.length * p).floor())];
  final build = sorted(timings.map((t) => ms(t.buildDuration)));
  final raster = sorted(timings.map((t) => ms(t.rasterDuration)));
  String f(double v) => v.toStringAsFixed(2);
  debugPrint(
    'SHOPPERF $phase: ${timings.length} frames; '
    'build p50 ${f(pct(build, .5))} p90 ${f(pct(build, .9))}; '
    'raster p50 ${f(pct(raster, .5))} p90 ${f(pct(raster, .9))} '
    'p99 ${f(pct(raster, .99))}',
  );
}
