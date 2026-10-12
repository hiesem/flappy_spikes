// PRD-2.2 §7.5.7 performance gate (WP-7a): a profile build of the game with
// the REAL AdMob banner platform view (Google TEST unit: profile builds never
// use real IDs) under the playfield, flown by the hoop-aware autopilot.
//
//   flutter run --profile -d 38300DLJH004SD \
//     -t integration_test/ads_banner_perf_main.dart
//   adb -s 38300DLJH004SD logcat -s flutter | grep ADSPERF
//
// Phase 1 flies 120 s WITHOUT the banner (the 2.1 baseline: no strip, no
// platform view), phase 2 flies 120 s WITH it. Each phase prints build /
// raster percentiles, janky frames (> 16.7 ms) and janky bursts (≥ 3 in a
// row). Its own SharedPreferences prefix keeps the owner's game data
// untouched. No rewarded / interstitial ads, no services, no taps on ads.
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flappy_spikes/components/banner_slot.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _phase = Duration(seconds: 120);

/// `--dart-define=ADSPERF_INTERSTITIAL=true`: instead of the gate, one run
/// → results → NEXT with the real (TEST unit) interstitial (§7.12 device).
const bool _interstitialCheck = bool.fromEnvironment('ADSPERF_INTERSTITIAL');

class _SwitchBanner implements BannerAds {
  _SwitchBanner(this.inner);
  final BannerAds inner;
  bool off = true;

  @override
  Future<void> initialize() => inner.initialize();
  @override
  double? get heightDp => inner.heightDp;
  @override
  double get widthDp => inner.widthDp;
  @override
  bool get canShow => !off && inner.canShow;
  @override
  ValueListenable<bool> get loaded => inner.loaded;
  @override
  void preload() {
    if (!off) inner.preload();
  }

  @override
  Widget? buildAd() => inner.buildAd();
  @override
  void dispose() => inner.dispose();
  @override
  set onImpression(void Function()? callback) => inner.onImpression = callback;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('adsperf.');
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  } catch (_) {}
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final widthDp = view.physicalSize.width / view.devicePixelRatio;
  final worldHeight = 320 * view.physicalSize.height / view.physicalSize.width;

  final consent = AdMobAdsConsent();
  final banner = _SwitchBanner(AdMobBannerAds(consent: consent, widthDp: widthDp));
  final monetization = Monetization(
    ads: NoopRewardedAds(),
    interstitial: _interstitialCheck
        ? AdMobInterstitialAds(consent: consent)
        : NoopInterstitialAds(),
    banner: banner,
    consent: consent,
    iap: FakeIapService(),
  );
  final game = FlappySpikesGame(
    worldHeight: worldHeight,
    monetization: monetization,
  );
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: RepaintBoundary(child: GameWidget(game: game))),
          BannerSlot(game: game),
        ],
      ),
    ),
  );
  await monetization.initialize();
  await game.loaded;
  debugPrint(
    'ADSPERF start: width ${widthDp.toStringAsFixed(1)} dp, screen '
    '${worldHeight.toStringAsFixed(1)} pt, banner ${banner.heightDp} dp, '
    'consent ${consent.canRequestAds.value}',
  );

  if (_interstitialCheck) {
    banner.off = false;
    for (var i = 0; i < 5; i++) {
      await game.storage.incrementGamesPlayed();
    }
    await _interstitialRun(game);
    return;
  }
  for (final withBanner in [false, true]) {
    banner.off = !withBanner;
    if (withBanner) {
      banner.preload();
      for (var i = 0; i < 100 && !banner.loaded.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    await _fly(game, withBanner ? 'banner' : 'baseline');
  }
  debugPrint('ADSPERF done');
}

Future<void> _fly(FlappySpikesGame game, String phase) async {
  final timings = <ui.FrameTiming>[];
  void cb(List<ui.FrameTiming> t) => timings.addAll(t);
  Autopilot? bot;
  Object? botRun;
  var runs = 0;
  var bannerFrames = 0;
  final done = Completer<void>();
  final sw = Stopwatch();
  // A phase starts with a fresh run (the banner flag is read at START):
  // end a run still flying from the previous phase first.
  var restart = game.state != GameState.start;
  var counting = false;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    if (!counting && !restart && game.state == GameState.playing) {
      counting = true;
      sw.start();
      SchedulerBinding.instance.addTimingsCallback(cb);
    }
    if (sw.elapsed >= _phase) {
      if (!done.isCompleted) done.complete();
      return;
    }
    if (game.bannerState.value == BannerState.showing) bannerFrames++;
    switch (game.state) {
      case GameState.start:
        restart = false;
        if (game.handleBack()) return;
        if (game.homeScreen != null) {
          game.onScreenTap();
          runs++;
        }
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
  final total = timings.map((t) => ms(t.totalSpan)).toList();
  var janky = 0, bursts = 0, streak = 0, worst = 0.0;
  for (final t in timings) {
    final slow = ms(t.buildDuration) > 16.7 || ms(t.rasterDuration) > 16.7;
    worst = max(worst, max(ms(t.buildDuration), ms(t.rasterDuration)));
    if (slow) {
      janky++;
      streak++;
      if (streak == 3) bursts++;
    } else {
      streak = 0;
    }
  }
  String f(double v) => v.toStringAsFixed(2);
  debugPrint(
    'ADSPERF $phase: ${timings.length} frames in ${_phase.inSeconds} s, '
    'runs $runs, banner-showing ticks $bannerFrames; '
    'build p50 ${f(pct(build, .5))} p90 ${f(pct(build, .9))} '
    'p99 ${f(pct(build, .99))}; raster p50 ${f(pct(raster, .5))} '
    'p90 ${f(pct(raster, .9))} p99 ${f(pct(raster, .99))}; '
    'span p99 ${f(pct(sorted(total), .99))}; worst ${f(worst)} ms; '
    'janky $janky (${f(100 * janky / max(1, timings.length))} %), '
    'bursts>=3 $bursts',
  );
}

/// One short run → results → NEXT: the interstitial must play (test unit),
/// the banner stays up under it, and Home arrives at full height after it.
Future<void> _interstitialRun(FlappySpikesGame game) async {
  Autopilot? bot;
  Object? botRun;
  var stage = 0;
  final done = Completer<void>();
  final sw = Stopwatch()..start();
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    switch (game.state) {
      case GameState.start:
        if (stage == 0) {
          if (game.handleBack()) return;
          if (game.homeScreen != null) game.onScreenTap();
        } else if (stage == 2 && !done.isCompleted) {
          debugPrint(
            'ADSPERF interstitial: home after the ad, banner '
            '${game.bannerState.value.name}, visible ${game.visibleHeight}, '
            'closedAt ${game.lastFullScreenAdClosedAt}',
          );
          done.complete();
        }
      case GameState.playing:
        final run = game.run;
        if (run == null) return;
        stage = 1;
        if (!identical(botRun, run)) {
          bot = Autopilot(run);
          botRun = run;
        }
        if (sw.elapsed > const Duration(seconds: 8)) {
          run.state.invulnerable = 0;
          game.onBirdHit(MistakeCause.missedHoop);
          return;
        }
        if (bot!.shouldFlap()) game.onScreenTap();
      case GameState.reviving:
        game.reviveScreen?.tapNoThanks();
      case GameState.bonus:
        game.bonusScreen?.tapNoThanks();
      case GameState.results:
        if (game.interstitialShowing) {
          if (stage != 2) {
            stage = 2;
            debugPrint(
              'ADSPERF interstitial: showing, banner '
              '${game.bannerState.value.name}, skip ${game.interstitialSkipReason()}',
            );
          }
          return;
        }
        if (stage == 1 && game.monetization.interstitial.isAvailable) {
          game.resultsScreen?.next();
        }
      case GameState.versusIntro || GameState.paused || GameState.dying:
        break;
    }
  });
  await done.future.timeout(const Duration(minutes: 3), onTimeout: () {
    debugPrint('ADSPERF interstitial: TIMEOUT stage $stage state ${game.state}');
  });
  timer.cancel();
}
