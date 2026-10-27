import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../game/flappy_game.dart';
import '../levels/levels.dart';
import '../run/mistakes.dart';

/// `--dart-define=FS_SOAK=true` (PRD-2.2 §33.3): the unattended soak run in
/// a **profile** build. Never active in a release build ([soakEnabled]).
const bool kSoakFlag = bool.fromEnvironment('FS_SOAK');

/// `--dart-define=FS_SOAK_GAMES=n`: games in a soak (§33.3: 20).
const int kSoakGames = int.fromEnvironment('FS_SOAK_GAMES', defaultValue: 20);

/// `--dart-define=FS_SOAK_HOLD=s`: seconds the soak idles on Home after a
/// measured game (the host script records meminfo / gfxinfo / 60 s idle CPU
/// / thermal in that window).
const int kSoakHold = int.fromEnvironment('FS_SOAK_HOLD', defaultValue: 100);

/// The §33.3 guard: the flag only counts outside release builds.
bool soakEnabled({required bool flag, required bool release}) =>
    flag && !release;

/// True in an FS_SOAK debug / profile build; always false in release.
const bool kSoak = kSoakFlag && !kReleaseMode;

/// `--dart-define=FS_SOAK_NO_BANNER=true` (S7-19 diagnosis only): a soak
/// build without the §7.5 gameplay banner, to measure what the banner's
/// platform view costs the run frames. Never in a release build.
const bool kSoakNoBanner =
    kSoak && bool.fromEnvironment('FS_SOAK_NO_BANNER');

/// After these games the soak holds on Home for the host's measurements.
const Set<int> kSoakMeasured = {1, 2, 5, 10, 20};

/// Every soak line in logcat starts with this tag (`adb logcat -s flutter`).
const String kSoakTag = 'FS_SOAK';

enum SoakPhase { home, playing, postRun, hold, done }

/// Plays [games] games in a row through the real game API (§33.3): Home →
/// START → autopilot (god mode) to [hoopsPerGame] hoops → death → revive
/// offer declined → (balloon bonus when forced: pop, NO THANKS, NEXT) →
/// results (CLAIM when a level-up is forced) → NEXT → Home. Driven from
/// `FlappySpikesGame.update`; every step is a guarded test hook that the
/// debug build already exposes.
class SoakDriver {
  SoakDriver(
    this.game, {
    this.games = kSoakGames,
    this.holdSeconds = kSoakHold,
    this.hoopsPerGame = 10,
    this.measured = kSoakMeasured,
    void Function(String line)? log,
  }) : _log = log ?? ((l) => debugPrint(l));

  /// PRD-2.2 §22 device check (`SoundService.debugOnStop`): long sounds must
  /// run to their full length (they were cut at 0.6 s); logs every play of
  /// > 0.6 s when its stop timer fires.
  void onSfxStop(String file, int ms) {
    if (ms > 600) _log('$kSoakTag sfx-stop file=$file ms=$ms');
  }

  final FlappySpikesGame game;
  final int games;
  final int holdSeconds;
  final int hoopsPerGame;
  final Set<int> measured;
  final void Function(String line) _log;

  SoakPhase phase = SoakPhase.home;

  /// Games finished (back on Home).
  int finished = 0;

  /// The game being played (1-based) while [phase] is not home / hold.
  int get current => finished + 1;

  double _t = 0;
  double _phaseT = 0;
  double _cooldown = 0;
  bool _dying = false;
  bool _forcedLevelUp = false;
  bool _started = false;

  final List<FrameTiming> _frames = [];
  bool _timingsOn = false;

  /// Game 3, 8, 13, 18: three feathers before the death → balloon bonus.
  bool forcesBonus(int g) => g % 5 == 3;

  /// Game 4, 9, 14, 19: the score is lifted to the next level threshold →
  /// LEVEL UP on the results page → CLAIM.
  bool forcesLevelUp(int g) => g % 5 == 4;

  void _line(String what) => _log(
    '$kSoakTag $what t=${_t.toStringAsFixed(1)} ${game.sound.debugStats()}',
  );

  void _enter(SoakPhase p) {
    phase = p;
    _phaseT = 0;
  }

  void _timings(List<FrameTiming> t) => _frames.addAll(t);

  /// Frame stats of the frames since the last call: p50 / p90 / max of the
  /// total span (vsync start → raster end) and jank = frames over 1.5×
  /// [budgetMs].
  String _frameStats({double budgetMs = 1000 / 120}) {
    if (_frames.isEmpty) return 'frames=0';
    final ms = [for (final f in _frames) f.totalSpan.inMicroseconds / 1000.0]
      ..sort();
    final build = [
      for (final f in _frames) f.buildDuration.inMicroseconds / 1000.0,
    ]..sort();
    final raster = [
      for (final f in _frames) f.rasterDuration.inMicroseconds / 1000.0,
    ]..sort();
    double q(List<double> l, double p) =>
        l[((l.length - 1) * p).round().clamp(0, l.length - 1)];
    final jank = ms.where((v) => v > budgetMs * 1.5).length;
    final s =
        'frames=${ms.length} p50=${q(ms, .5).toStringAsFixed(2)} '
        'p90=${q(ms, .9).toStringAsFixed(2)} p99=${q(ms, .99).toStringAsFixed(2)} '
        'max=${ms.last.toStringAsFixed(1)} '
        'build90=${q(build, .9).toStringAsFixed(2)} '
        'raster90=${q(raster, .9).toStringAsFixed(2)} '
        'jank=${(100 * jank / ms.length).toStringAsFixed(1)}%';
    _frames.clear();
    return s;
  }

  void update(double dt) {
    _t += dt;
    _phaseT += dt;
    if (_cooldown > 0) _cooldown -= dt;
    if (!_timingsOn) {
      _timingsOn = true;
      try {
        SchedulerBinding.instance.addTimingsCallback(_timings);
      } catch (_) {}
    }
    try {
      switch (phase) {
        case SoakPhase.home:
          _home();
        case SoakPhase.playing:
          _playing();
        case SoakPhase.postRun:
          _postRun();
        case SoakPhase.hold:
          if (_phaseT >= holdSeconds) {
            _line('hold-end game=$finished idle ${_frameStats()}');
            _enter(finished >= games ? SoakPhase.done : SoakPhase.home);
            if (phase == SoakPhase.done) _line('done games=$finished');
          }
        case SoakPhase.done:
          break;
      }
    } catch (e) {
      _log('$kSoakTag error $e');
    }
  }

  void _home() {
    if (!_started) {
      // Let the app settle (launch popups, prewarm) before game 1.
      if (_phaseT < 6) return;
      _started = true;
      _line('begin games=$games hold=$holdSeconds');
    }
    if (_cooldown > 0) return;
    if (game.state == GameState.start) {
      if (game.modalPopupOpen || game.menuScene != MenuScene.home) {
        game.handleBack();
        _cooldown = .8;
        return;
      }
      if (game.homeScreen?.isLoaded != true) return;
      final g = current;
      if (forcesBonus(g)) unawaited(game.storage.saveFeathers(3));
      game.runDebug
        ..bot = true
        ..god = true;
      _frames.clear();
      unawaited(game.startRun());
      _cooldown = 1;
      return;
    }
    if (game.state == GameState.playing && game.run != null) {
      _dying = false;
      _forcedLevelUp = false;
      _line(
        'start game=$current bonus=${forcesBonus(current)} '
        'levelup=${forcesLevelUp(current)}',
      );
      _enter(SoakPhase.playing);
    }
  }

  void _playing() {
    final run = game.run;
    if (game.state != GameState.playing &&
        game.state != GameState.paused &&
        game.state != GameState.versusIntro) {
      if (game.state == GameState.dying ||
          game.state == GameState.reviving ||
          game.state == GameState.bonus ||
          game.state == GameState.results) {
        _line(
          'death game=$current hoops=${run?.state.hoopsPassed} '
          'score=${run?.state.score} ${_frameStats()}',
        );
        _enter(SoakPhase.postRun);
      }
      return;
    }
    if (run == null) return;
    final reached = run.state.hoopsPassed >= hoopsPerGame || _phaseT > 90;
    if (!reached) return;
    if (!_dying) {
      _dying = true;
      if (forcesLevelUp(current) && !_forcedLevelUp) {
        _forcedLevelUp = true;
        final next = trackLevelDef(game.menu.levels.level + 1);
        if (next != null && next.points > run.state.score) {
          run.ctx.addScore(next.points - run.state.score);
        }
      }
      // Death: god mode ends and a spikes hit is forced (repeated while a
      // shield / extra life keeps the run going), as the release e2e does.
      game.runDebug.god = false;
    }
    if (_cooldown <= 0) {
      run.state.invulnerable = 0;
      game.onBirdHit(MistakeCause.spikes);
      _cooldown = .3;
    }
  }

  void _postRun() {
    if (_cooldown > 0) return;
    switch (game.state) {
      case GameState.reviving:
        final s = game.reviveScreen;
        if (s != null && s.ui >= 1) {
          s.tapNoThanks();
          _line('revive-declined game=$current');
          _cooldown = .5;
        }
      case GameState.bonus:
        final b = game.bonusScreen;
        if (b == null) return;
        if (b.nextShown) {
          b.tapNext();
          _line('bonus-done game=$current pops=${b.pops}');
        } else if (b.noThanksShown) {
          b.tapNoThanks();
          _line('bonus-done game=$current pops=${b.pops}');
        } else {
          for (var i = 0; i < b.prizes.length; i++) {
            if (!b.isOpened(i) && b.tapTile(i)) break;
          }
        }
        _cooldown = .4;
      case GameState.results:
        final r = game.resultsScreen;
        if (r == null || !r.canContinue) return;
        if (r.claimShowing) {
          r.claimButton.onPressed();
          _line('claim game=$current');
          _cooldown = 3;
          return;
        }
        // Let the count-up (ticks, coin landings) finish first.
        if (_phaseT < 8) return;
        r.nextButton.onPressed();
        _cooldown = 1;
      case GameState.start:
        if (game.homeScreen?.isLoaded != true) return;
        finished++;
        _line('game-end game=$finished postrun ${_frameStats()}');
        if (measured.contains(finished) || finished >= games) {
          _line('hold game=$finished secs=$holdSeconds');
          _enter(SoakPhase.hold);
        } else {
          _enter(SoakPhase.home);
        }
      default:
        break;
    }
  }
}
