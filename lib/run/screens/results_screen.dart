import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../components/home/menu_primitives.dart';
import '../../components/levels/emblem_view.dart';
import '../../components/look_component.dart';
import '../../components/ui/coin_fly.dart';
import '../../components/ui/confetti.dart';
import '../../components/ui/live_effects.dart' show WiggleEffect;
import '../../game/flappy_game.dart';
import '../../game/palettes.dart';
import '../../game/sound.dart';
import '../../levels/level_progress.dart';
import '../../levels/levels.dart';
import '../../skins/look.dart';
import '../config/results_config.dart';
import '../effects/coin_icon.dart';
import '../hud/fit_name.dart'; // PRD-2.3 §21.2
import '../effects/easing.dart';
import '../effects/fireworks.dart';
import '../effects/gold_sticker.dart';
import '../items/versus_recorder.dart' show duelOf; // WP-5b
import '../../versus/opponent.dart'; // WP-5b
import '../run_summary.dart';
import 'post_run_screens.dart';

/// Images the results page draws (under `assets/images/`).
const List<String> kResultsImages = [
  CoinIcon.asset,
  'menu/trophy.png',
  'menu/invite.png',
];

/// The level bar of the results page (§5.10; owner 2026-10-17, WP-L: the
/// level is stored and steps up one per run): the level, the fill of a
/// single run's [score] toward the next threshold and the label under the
/// bar ("70 TO FLEDGLING", "MAX LEVEL").
class LevelBar {
  const LevelBar(this.level, this.fraction, this.label);

  /// The bar at [level] for a run of [score] (0 = no run counted yet: an
  /// empty bar and the full threshold to reach).
  factory LevelBar.at(int level, {int score = 0}) {
    final next = nextLevel(level);
    if (next == null) return LevelBar(level, 1, 'MAX LEVEL');
    final left = math.max(0, next.threshold - score);
    return LevelBar(
      level,
      (score / next.threshold).clamp(0.0, 1.0),
      '${formatCoins(left)} TO ${next.name}',
    );
  }

  final int level;
  final double fraction;
  final String label;
}

/// "HAWK · LV 7", or "UNRANKED" below level 1 (§5.10 rank line).
String rankText(int level) {
  final def = levelDef(level);
  return def == null ? 'UNRANKED' : '${def.name} · LV $level';
}

/// What the results page shows (§3.14 / §5.10), pure data.
class ResultsModel {
  const ResultsModel({
    required this.score,
    required this.bestBefore,
    required this.bestAfter,
    required this.reward,
    this.levelReward = 0,
    this.levelBefore = 0,
    this.levelAfter = 0,
  });

  /// The page for [s]: YOUR REWARD is the run's coin total (`s.coins` =
  /// every in-run `ctx.earn`: hoops, perfects, elements, puzzle coins and
  /// the win / draw bonus; the balloon bonus is paid by the bonus screen
  /// straight into the wallet and is not part of it, Q36). [pending] is the
  /// owed level reward (rewards of every reached-but-unclaimed level).
  /// [levelBefore] / [levelAfter] are the stored level around the run
  /// (WP-L; `FlappySpikesGame.endRun`).
  factory ResultsModel.of(
    RunSummary s, {
    PendingLevelUp? pending,
    int? levelBefore,
    int? levelAfter,
  }) => ResultsModel(
    score: s.score,
    bestBefore: s.bestBefore,
    bestAfter: s.bestAfter,
    reward: s.coins,
    levelReward: pending?.reward ?? 0,
    levelBefore: levelBefore ?? 0,
    levelAfter: levelAfter ?? levelBefore ?? 0,
  );

  final int score;
  final int bestBefore;
  final int bestAfter;

  /// YOUR REWARD before any level reward is claimed.
  final int reward;

  /// The level reward(s) claimed on this page (all reached levels added).
  final int levelReward;

  /// The stored level shown at 0 s (before this run, WP-L).
  final int levelBefore;

  /// The stored level after this run (at most one step up, WP-L).
  final int levelAfter;

  bool get newBest => bestAfter > bestBefore;

  /// This run reached the next level (one step, WP-L).
  bool get levelUp => levelAfter > levelBefore;

  /// The page shows CLAIM (a level up with a reward still owed).
  bool get hasClaim => levelUp && levelReward > 0;
}

/// Pays the owed level rewards (§3.14): `menu.levels.claim()` (wallet
/// source `level_reward`, every reached level marked claimed), clears
/// `unclaimedLevelReward` and sends `level_up {from, to, reward, claim}`
/// with [how] = `tap` / `auto_next` / `app_start`. Returns what was paid; a
/// second call pays nothing. `claim()` also resumes a claim that a kill
/// interrupted between its claim writes and the credit (S6-22) and then
/// clears its `levelRewardPayout` record, so the reward lands exactly once.
Future<int> claimLevelRewards(FlappySpikesGame game, String how) async {
  final pending = game.menu.levels.pendingLevelUp;
  final paid = await game.menu.levels.claim();
  if (paid > 0 && pending != null) {
    game.services.track('level_up', {
      'from': pending.fromLevel,
      'to': pending.toLevel,
      'reward': paid,
      'claim': how,
    });
  }
  return paid;
}

/// The results page as the post-run flow's last screen (ARCH §1.11).
class ResultsPage implements ResultsScreenFactory {
  const ResultsPage();

  @override
  Future<void> show(FlappySpikesGame game, RunSummary s) async =>
      game.showResults(s);
}

/// The results page (PRD-2 §3.14 / §5.10, approved
/// `screen_results_levels.html`), replacing the 1.0 game-over panel: an
/// opaque stage-coloured page between the strips with (top to bottom) the
/// versus header (WP-5b), the card with your score (solo: you alone,
/// centred; versus: both, WP-5b), NEW BEST, your level (emblem + equipped
/// bird, rank line, progress bar), YOUR REWARD and NEXT; the kept
/// leaderboard and share buttons flank the reward pill (PRD-1 §3.7).
///
/// The page shows the level *before* the run first, then plays the §5.10
/// sequence on its own clock: count-ups, NEW BEST, the bar fill and — when
/// the run reached new levels — the LEVEL UP celebration and CLAIM. NEXT
/// claims a still-owed reward first (same animation), then `goHome()`.
///
/// Geometry is the 320 × 711 mock in [content]'s coordinates, scaled by
/// [ResultsConfig.scaleFor] about the top centre on shorter screens.
class ResultsScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity {
  ResultsScreen({required this.summary, required this.model})
    : super(priority: priorityOnTop);

  /// Above the run (hoop fronts 12, fx 15, banners 18, HUD 19 / 21 under
  /// the strips that the game lifts to 21 while the page is up).
  static const int priorityOnTop = 20;

  /// The fx layer (confetti, fireworks, coin fly, white flash) — above the
  /// strips like the mock's canvas.
  static const int fxPriority = 30;

  final RunSummary summary;
  final ResultsModel model;

  /// The scaled 320 × 711 column.
  late final PositionComponent content;

  /// Confetti, fireworks, coins and the white flash (world child, same
  /// transform as [content]).
  late final ResultsFx fx;

  late final ResultsPlayerColumn you;

  // region WP-5b — versus parts
  /// The opponent's column (null = solo).
  ResultsPlayerColumn? them;

  /// WIN / LOSE / DRAW header (null = solo).
  ResultsHeader? header;

  /// WIN / LOSE / DRAW of this run (null = solo).
  DuelResult? get duel {
    final opp = summary.opponent;
    if (opp == null) return null;
    return summary.duel ?? duelOf(summary.score, opp.score);
  }
  // endregion WP-5b
  late final MenuText rank;
  late final ResultsBar bar;
  late final MenuText barLabel;
  late final ResultsClaimButton claimButton;
  late final MenuText rewardText;
  late final PositionComponent rewardPill;
  late final MenuButton nextButton;
  late final MenuButton leaderboardButton;
  late final MenuButton shareButton;
  late final ResultsLevelStage stage;
  late final ResultsLevelUpBanner levelUpBanner;
  GoldSticker? newBestSticker;

  late final Sprite _coin;
  late final WiggleEffect _pillBump;
  late final WiggleEffect _labelBump;
  late final WiggleEffect _rankBounce;
  late final WiggleEffect _stickerOut;

  double _t = 0;
  bool _built = false;
  final List<(double, void Function())> _schedule = [];

  // Animated values.
  int _shownReward = 0;
  int _countFrom = 0, _countTo = 0;
  double? _countStart;
  double _countLength = ResultsConfig.countDuration;
  double? _scoreCountStart;
  double _barFrom = 0, _barTo = 0;
  double? _barStart;
  double _barLength = 0;
  double? _labelBumpStart;
  double? _rankBounceStart;
  double? _pillBumpStart;
  double? _stickerOutStart;
  double? _barFadeStart;
  double _barFadeFrom = 1, _barFadeTo = 1;
  double _barFadeLength = .2;

  bool _claimShowing = false;
  bool _claimed = false;
  bool _leaving = false;
  double? _claimEnd;

  // region PRD-2.2 §14 — one `sk_tick` stream for the count-ups
  /// The running tick stream (null = none): its start, length and total.
  double? _tickStart;
  double _tickLength = ResultsConfig.countDuration;
  int _tickTotal = 0;
  int _tickPlayed = 0;

  /// PRD-2.2 §14.1 the tick count for a count of [amount]: the home
  /// coin-pill rule min(24, 8 + amount); a count of 0 plays none.
  static int ticksFor(int amount) =>
      amount <= 0 ? 0 : math.min(24, 8 + amount);

  /// PRD-2.2 §14 starts the one tick stream for a count of [amount] over
  /// [length] s (replaces a running one, so counts that run together never
  /// double the ticks).
  void _startTicks(int amount, double length) {
    _tickTotal = ticksFor(amount);
    _tickPlayed = 0;
    _tickLength = length;
    _tickStart = _tickTotal > 0 ? _t : null;
  }

  /// PRD-2.2 §14.1 the ticks follow the eased count (ease-out cubic, like
  /// the numbers): tick i is due once the count passed i / total, at most
  /// one per frame, so they come quickly and slow down with the numbers.
  void _stepTicks() {
    final ts = _tickStart;
    if (ts == null) return;
    final u = ((_t - ts) / _tickLength).clamp(0.0, 1.0);
    final e = 1 - math.pow(1 - u, 3).toDouble();
    final due = u >= 1
        ? _tickTotal
        : math.min(_tickTotal, (e * _tickTotal).floor() + 1);
    if (_tickPlayed < due) {
      _tickPlayed++;
      game.sound.play(Sfx.skTick);
    }
    if (_tickPlayed >= _tickTotal) _tickStart = null;
  }

  /// NEXT / skip: no more ticks.
  void _stopTicks() => _tickStart = null;
  // endregion PRD-2.2 §14

  /// Seconds since the page opened.
  double get time => _t;

  /// YOUR REWARD as shown now.
  int get shownReward => _shownReward;

  /// CLAIM is up and takes taps.
  bool get claimShowing => _claimShowing;

  /// The level reward has been claimed on this page (tap or NEXT).
  bool get claimed => _claimed;

  /// NEXT was pressed (the page is on its way home).
  bool get leaving => _leaving;

  /// Buttons take taps (and the keyboard continues) once the page has
  /// faded in, so a flap tap at the moment of death never lands on them.
  bool get canContinue => _built && _t >= ResultsConfig.pageFadeIn;

  /// PRD-2.3 §23.2 "settled": the §5.10 sequence has played out (every
  /// scheduled step ran, the count-ups and the bar with its fades have
  /// finished) and no CLAIM waits. The rating sheet's 1.5 s count starts here.
  bool get settled {
    if (!canContinue || _leaving || _claimShowing || _schedule.isNotEmpty) {
      return false;
    }
    bool done(double? start, double length) =>
        start == null || _t >= start + length;
    return done(_countStart, _countLength) &&
        done(_barStart, _barLength) &&
        done(_barFadeStart, _barFadeLength);
  }

  bool _active() => canContinue && !_leaving;

  void _at(double time, void Function() f) => _schedule.add((time, f));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(320, h);
    final loaded = await Future.wait(kResultsImages.map(game.images.load));
    _coin = Sprite(loaded[0]);
    final trophy = Sprite(loaded[1]);
    final invite = Sprite(loaded[2]);

    final k = ResultsConfig.scaleFor(h);
    final top = ResultsConfig.topFor(h);
    final transform = (
      Vector2(160 * (1 - k), top - ResultsConfig.contentTop * k),
      Vector2.all(k),
    );
    content = PositionComponent(
      position: transform.$1.clone(),
      scale: transform.$2.clone(),
      size: Vector2(320, ResultsConfig.referenceHeight),
    );
    fx = ResultsFx(this)
      ..position = transform.$1.clone()
      ..scale = transform.$2.clone();

    final before = LevelBar.at(model.levelBefore);

    // --- card ------------------------------------------------------------
    final card = ResultsCard();
    // region WP-5b — versus parts of §5.10 (header WIN / LOSE / DRAW, the
    // opponent column with VS, WINNER tags, the +10 / +5 in the reward via
    // the run's coins). Solo (no opponent): you alone, centred.
    final opp = summary.opponent;
    final duel = this.duel;
    final versusParts = <PositionComponent>[];
    if (opp == null || duel == null) {
      you = ResultsPlayerColumn(
        name: game.myVersusName,
        score: model.score,
        centreX: ResultsConfig.soloColumnX,
        mine: true,
        look: game.menu.items.look, // WP-AV your sticker avatar
      );
    } else {
      you = ResultsPlayerColumn(
        name: game.myVersusName,
        score: model.score,
        centreX: ResultsConfig.youColumnX,
        mine: true,
        look: game.menu.items.look, // WP-AV your sticker avatar
        lower: duel == DuelResult.lose,
        winner: duel == DuelResult.win,
      );
      final column = ResultsPlayerColumn(
        name: opp.name,
        score: opp.score,
        centreX: ResultsConfig.opponentColumnX,
        mine: false,
        look: opp.look,
        lower: duel == DuelResult.win,
        winner: duel == DuelResult.lose,
      );
      them = column;
      final head = ResultsHeader(duel);
      header = head;
      versusParts.addAll([
        head,
        column,
        MenuText(
          'VS',
          fontSize: ResultsConfig.nameFontSize,
          color: ResultsConfig.plum,
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          lineHeight: 1,
          position: Vector2(160, ResultsConfig.vsCentreY),
          anchor: Anchor.center,
        ),
      ]);
    }
    // endregion WP-5b

    // --- level stage -----------------------------------------------------
    stage = ResultsLevelStage(this, level: before.level);
    rank = MenuText(
      rankText(before.level),
      fontSize: ResultsConfig.rankFontSize,
      color: ResultsConfig.plum,
      fontFamily: 'Fredoka',
      fontWeight: FontWeight.w600,
      lineHeight: 1.2,
      position: Vector2(160, ResultsConfig.rankTop),
      anchor: Anchor.topCenter,
    );
    _rankBounce = WiggleEffect(rank);
    rank.decorator.addLast(_rankBounce);
    bar = ResultsBar(this)..fraction = before.fraction;
    barLabel = MenuText(
      before.label,
      fontSize: ResultsConfig.barLabelFontSize,
      color: kPostRunPalette.foreground,
      letterSpacingEm: ResultsConfig.barLabelLetterSpacing,
      position: Vector2(160, ResultsConfig.barLabelTop),
      anchor: Anchor.topCenter,
    );
    _labelBump = WiggleEffect(barLabel);
    barLabel.decorator.addLast(_labelBump);
    claimButton = ResultsClaimButton(
      reward: model.levelReward,
      coin: _coin,
      onPressed: () => _claim(auto: false),
      isActive: () => _active() && _claimShowing,
    );

    // --- reward ------------------------------------------------------------
    final rewardLabel = MenuText(
      'YOUR REWARD',
      fontSize: ResultsConfig.rewardLabelFontSize,
      color: kPostRunPalette.foreground,
      letterSpacingEm: ResultsConfig.rewardLabelLetterSpacing,
      position: Vector2(160, ResultsConfig.rewardLabelTop),
      anchor: Anchor.topCenter,
    );
    const pill = ResultsConfig.rewardPill;
    rewardText = MenuText(
      '0',
      fontSize: ResultsConfig.rewardFontSize,
      color: ResultsConfig.plum,
      lineHeight: 1,
    );
    final rewardCoin = MenuIcon(
      _coin,
      size: Vector2.all(ResultsConfig.rewardCoinSize),
    );
    rewardPill = _Box(
      color: const Color(0xFFFFFFFF),
      position: pill.topLeft.toVector2(),
      size: pill.size.toVector2(),
      children: [rewardText, rewardCoin],
    );
    _pillBump = WiggleEffect(rewardPill);
    rewardPill.decorator.addLast(_pillBump);

    // --- buttons -------------------------------------------------------------
    // §3.0.1 (S6-23): NEXT is a bottom button — it keeps the reference
    // 65 pt gap to the screen's bottom edge and its §5.10 292 × 50 size
    // while the column above it scales. Its box (and label font) are
    // pre-divided by the page scale, so the rendered button is the
    // reference size again on every screen height.
    final inv = 1 / content.scale.y;
    final nextBox = Rect.fromLTWH(
      (ResultsConfig.next.left - content.position.x) * inv,
      (ResultsConfig.nextTopFor(h) - content.position.y) * inv,
      ResultsConfig.next.width * inv,
      ResultsConfig.next.height * inv,
    );
    nextButton = MenuButton(
      color: ResultsConfig.pink,
      position: nextBox.topLeft.toVector2(),
      size: nextBox.size.toVector2(),
      onPressed: next,
      isActive: _active,
    );
    layoutRow(nextButton, [
      MenuText(
        'NEXT',
        fontSize: ResultsConfig.nextFontSize * inv,
        color: ResultsConfig.soft,
        letterSpacingEm: ResultsConfig.nextLetterSpacing,
      ),
    ], gap: 0);
    MenuButton side(Rect r, Sprite icon, void Function() action) => MenuButton(
      color: ResultsConfig.pink,
      position: r.topLeft.toVector2(),
      size: r.size.toVector2(),
      onPressed: action,
      isActive: _active,
      children: [
        MenuIcon(
          icon,
          size: Vector2.all(ResultsConfig.sideIconSize),
          position: r.size.toVector2() / 2,
          anchor: Anchor.center,
        ),
      ],
    );
    // Gated on the fade-in also when pressed directly (1.0 Fix E: a flap
    // tap at the moment of death must never open Play Games).
    leaderboardButton = side(ResultsConfig.leaderboardButton, trophy, () {
      if (_active()) unawaited(game.showLeaderboard(sfx: Sfx.skTap));
    });
    shareButton = side(ResultsConfig.shareButton, invite, () {
      if (_active()) game.shareScore();
    });

    levelUpBanner = ResultsLevelUpBanner()..opacity = 0;

    content.addAll([
      card,
      you,
      stage,
      rank,
      bar,
      barLabel,
      claimButton,
      rewardLabel,
      rewardPill,
      leaderboardButton,
      shareButton,
      nextButton,
      levelUpBanner,
    ]);
    // region WP-5b — header, opponent column, VS
    content.addAll(versusParts);
    // endregion WP-5b
    add(content);
    _built = true;
    _layoutReward();
    _plan(before);
    opacity = 0;
  }

  @override
  void onMount() {
    super.onMount();
    parent?.add(fx);
  }

  @override
  void onRemove() {
    fx.removeFromParent();
    super.onRemove();
  }

  /// Schedules the §5.10 sequence for this run.
  void _plan(LevelBar before) {
    const c = ResultsConfig.countStart;
    _at(c, () {
      _scoreCountStart = _t;
      _countTo = model.reward;
      _countFrom = 0;
      _countLength = ResultsConfig.countDuration;
      _countStart = _t;
      // PRD-2.2 §14 one tick stream for the points (both columns) and
      // YOUR REWARD: min(24, 8 + the largest count).
      _startTicks(
        math.max(
          math.max(model.score, model.reward),
          summary.opponent?.score ?? 0,
        ),
        ResultsConfig.countDuration,
      );
    });
    // WP-L the bar is this run's progress toward the next level: it fills
    // after every run (a level up no longer needs a new best).
    if (model.newBest) _planNewBest();
    _planBar();
  }

  void _planNewBest() {
    _at(ResultsConfig.newBestAt, () {
      final sticker = GoldSticker.newBest(
        text: 'NEW BEST · ${model.score}',
        position: Vector2(160, 0),
      )..priority = 5;
      newBestSticker = sticker;
      _stickerOut = WiggleEffect(sticker);
      sticker.decorator.addLast(_stickerOut);
      content.add(sticker);
      // Its top on the card's bottom edge (§5.10 y ≈ 238).
      sticker.position.y = ResultsConfig.newBestTop + sticker.box.height / 2;
      game.sound.play(Sfx.perfect1);
    });
  }

  void _planBar() {
    final after = LevelBar.at(model.levelAfter, score: model.score);
    const b = ResultsConfig.barAt;
    if (!model.levelUp) {
      _at(b, () {
        game.sound.play(Sfx.lvBar);
        _animateBar(after.fraction, ResultsConfig.barFill);
      });
      _at(b + ResultsConfig.barFill, () {
        barLabel.text = after.label;
        _labelBumpStart = _t;
      });
      return;
    }
    // --- LEVEL UP ------------------------------------------------------------
    _at(b, () {
      game.sound.play(Sfx.lvBar);
      barLabel.text = '';
      _animateBar(1, ResultsConfig.barToLevel);
    });
    const up = b + ResultsConfig.barToLevel;
    _at(up, () {
      bar.flashStart = _t;
      stage.shakeStart = _t;
    });
    const pop = up + ResultsConfig.shake;
    _at(pop, () {
      final level = model.levelAfter;
      fx.flashStart = _t;
      stage
        ..level = level
        ..popStart = _t
        ..rays = 1;
      game.sound.play(level >= 9 ? Sfx.lvUpBig : Sfx.lvUp);
      if (newBestSticker != null) _stickerOutStart = _t;
      levelUpBanner.start = _t;
      rank.text = rankText(level);
      _rankBounceStart = _t;
      if (!game.reduceMotion) {
        final big = level >= 9;
        fx.confetti(
          ResultsConfig.plateCentre,
          ResultsConfig.confettiFor(level),
          speed: big ? 275 : 220,
        );
        for (final r in ResultsConfig.rockets) {
          fx.fireworks.launch(r.$1, r.$2, r.$3, delay: r.$4);
        }
      }
    });
    if (model.levelAfter >= 9) {
      _at(pop + ResultsConfig.secondWave, () {
        if (game.reduceMotion) return;
        fx
          ..confetti(const Offset(60, 300), ResultsConfig.secondWaveConfetti)
          ..confetti(const Offset(260, 300), ResultsConfig.secondWaveConfetti);
        for (final r in ResultsConfig.secondWaveRockets) {
          fx.fireworks.launch(r.$1, r.$2, r.$3, delay: r.$4);
        }
      });
    }
    _at(pop + ResultsConfig.claimAfter, () {
      if (_claimed) return;
      _fadeBar(1, 0, ResultsConfig.barFadeOut);
      if (model.hasClaim) {
        claimButton.show(_t);
        _claimShowing = true;
      } else {
        // Nothing owed (claimed before): straight to the new progress.
        _barBack();
      }
    });
  }

  void _animateBar(double to, double length) {
    _barFrom = bar.fraction;
    _barTo = to;
    _barStart = _t;
    _barLength = length;
  }

  void _fadeBar(double from, double to, double length) {
    _barFadeFrom = from;
    _barFadeTo = to;
    _barFadeStart = _t;
    _barFadeLength = length;
  }

  /// After the claim: the bar comes back empty and fills to the progress in
  /// the new level.
  void _barBack() {
    // WP-L the run is spent on the step: the new level's bar starts empty.
    final after = LevelBar.at(model.levelAfter);
    bar.fraction = 0;
    barLabel.text = after.label;
    _fadeBar(0, 1, ResultsConfig.barBackFade);
    _animateBar(after.fraction, ResultsConfig.barBackFill);
  }

  /// CLAIM (or NEXT while CLAIM shows, [auto]): pays the reward now, then
  /// the §5.10 animation — coins fly into YOUR REWARD, the count-up, the
  /// pill bump, small confetti, the rays end, the bar comes back.
  void _claim({required bool auto}) {
    if (!_claimShowing || _claimed) return;
    _claimShowing = false;
    _claimed = true;
    unawaited(claimLevelRewards(game, auto ? 'auto_next' : 'tap'));
    game.sound.play(Sfx.lvClaim);
    claimButton.hide(_t);
    fx.flyCoins(_coin, onLand: () => game.sound.play(Sfx.bnCoin));
    final start = _t;
    _at(start + ResultsConfig.claimCountDelay, () {
      _countFrom = _shownReward;
      _countTo = model.reward + model.levelReward;
      _countLength = ResultsConfig.claimCount;
      _countStart = _t;
      // PRD-2.2 §14.1 the claimed amount ticks too (under lv_claim and the
      // bn_coin landings).
      _startTicks(model.levelReward, ResultsConfig.claimCount);
    });
    _at(
      start + ResultsConfig.claimCountDelay + ResultsConfig.pillBumpAt,
      () => _pillBumpStart = _t,
    );
    final end =
        start + ResultsConfig.claimCountDelay + ResultsConfig.claimConfettiAt;
    _claimEnd = end;
    _at(end, () {
      if (!game.reduceMotion) {
        fx.confetti(
          Offset(160, ResultsConfig.rewardPill.center.dy),
          ResultsConfig.claimConfetti,
          speed: 130,
        );
      }
      stage.rays = 0;
      _barBack();
    });
  }

  /// NEXT (button, Space / Enter / Esc): a CLAIM still showing is claimed
  /// first with its animation, then home; a level reward owed before CLAIM
  /// came up is paid at once (no reward is ever lost); otherwise straight
  /// home (`goHome()`, a new home arrival).
  void next() {
    if (!canContinue || _leaving) return;
    _leaving = true;
    _stopTicks(); // PRD-2.2 §14.1 NEXT mid-count stops the ticks
    if (_claimShowing) {
      _claim(auto: true);
      _at(_claimEnd! + ResultsConfig.nextAfterClaim, game.goHome);
      return;
    }
    if (model.hasClaim && !_claimed) {
      _claimed = true;
      unawaited(claimLevelRewards(game, 'auto_next'));
    }
    game.goHome();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_built) return;
    _t += dt;
    opacity = (_t / ResultsConfig.pageFadeIn).clamp(0.0, 1.0);
    // Run due actions (in time order; an action may schedule more).
    _schedule.sort((a, b) => a.$1.compareTo(b.$1));
    while (_schedule.isNotEmpty && _schedule.first.$1 <= _t + 1e-9) {
      _schedule.removeAt(0).$2();
    }
    _animate();
    _stepTicks();
  }

  void _animate() {
    final fg = kPostRunPalette.foreground;
    // Count-ups (ease-out cubic).
    final cs = _countStart;
    if (cs != null) {
      final u = ((_t - cs) / _countLength).clamp(0.0, 1.0);
      final e = 1 - math.pow(1 - u, 3).toDouble();
      final v = (_countFrom + (_countTo - _countFrom) * e).round();
      if (v != _shownReward) {
        _shownReward = v;
        _layoutReward();
      }
    }
    final ss = _scoreCountStart;
    if (ss != null) {
      final u = ((_t - ss) / ResultsConfig.countDuration).clamp(0.0, 1.0);
      final e = 1 - math.pow(1 - u, 3).toDouble();
      you.shownScore = (model.score * e).round();
      // region WP-5b — both scores count up (§5.10)
      final opp = summary.opponent;
      final col = them;
      if (opp != null && col != null && col.isLoaded) {
        col.shownScore = (opp.score * e).round();
      }
      // endregion WP-5b
    }
    // Bar fill (ease-in-out).
    final bs = _barStart;
    if (bs != null) {
      final u = ((_t - bs) / _barLength).clamp(0.0, 1.0);
      bar.fraction = _barFrom + (_barTo - _barFrom) * Ease.cubicInOut(u);
    }
    final fs = _barFadeStart;
    if (fs != null) {
      final u = ((_t - fs) / _barFadeLength).clamp(0.0, 1.0);
      final o = _barFadeFrom + (_barFadeTo - _barFadeFrom) * u;
      bar.opacity = o;
      _barLabelOpacity = o;
    }
    // Label bump 1.25 → 1.
    final lb = _labelBumpStart;
    _labelBump.scale = lb == null
        ? 1
        : 1.25 - .25 * ((_t - lb) / ResultsConfig.barLabelBump).clamp(0.0, 1.0);
    // Rank bounce .6 → 1.3 (60 %) → 1, pink → plum.
    final rb = _rankBounceStart;
    if (rb != null) {
      final u = ((_t - rb) / ResultsConfig.rankBounce).clamp(0.0, 1.0);
      _rankBounce.scale = u < .6
          ? .6 + .7 * Ease.cssOut(u / .6)
          : 1.3 - .3 * Ease.cssOut((u - .6) / .4);
      rank.color = Color.lerp(ResultsConfig.pink, ResultsConfig.plum, u)!;
    }
    // Pill bump 1 → 1.12 (30 %) → 1.
    final pb = _pillBumpStart;
    if (pb != null) {
      final u = ((_t - pb) / ResultsConfig.pillBump).clamp(0.0, 1.0);
      _pillBump.scale = u < .3
          ? 1 + (ResultsConfig.pillBumpScale - 1) * (u / .3)
          : ResultsConfig.pillBumpScale -
                (ResultsConfig.pillBumpScale - 1) * ((u - .3) / .7);
    }
    barLabel.color = fg.withValues(alpha: _barLabelOpacity);
    // NEW BEST pops out (scale → .2, +10°, fades) at the level up.
    final so = _stickerOutStart;
    final sticker = newBestSticker;
    if (so != null && sticker != null) {
      final u = ((_t - so) / ResultsConfig.newBestOut).clamp(0.0, 1.0);
      _stickerOut
        ..scale = 1 - .8 * u
        ..angle = u * 10 * math.pi / 180;
      sticker.opacity = 1 - u;
      if (u >= 1 && sticker.isMounted) sticker.removeFromParent();
    }
  }

  double _barLabelOpacity = 1;

  /// Centres "1 234 ●" in the white pill.
  void _layoutReward() {
    if (!_built) return;
    rewardText.text = formatCoins(_shownReward);
    const pill = ResultsConfig.rewardPill;
    final w =
        rewardText.width +
        ResultsConfig.rewardGap +
        ResultsConfig.rewardCoinSize;
    var x = (pill.width - w) / 2;
    rewardText.position = Vector2(x, (pill.height - rewardText.height) / 2);
    x += rewardText.width + ResultsConfig.rewardGap;
    final coin = rewardPill.children.whereType<MenuIcon>().first;
    coin.position = Vector2(
      x,
      (pill.height - ResultsConfig.rewardCoinSize) / 2,
    );
  }

  // region PRD-2.2 §31.3 — the level-up rays, drawn by the page
  static final Paint _rayGold = Paint();
  static final Paint _rayLight = Paint();

  /// The ray's alpha at [u] (0 at the emblem, 1 at the tip) as a share of
  /// [ResultsConfig.rayAlpha]: 1 at the emblem, `rayAlphaMid / rayAlpha` at
  /// [ResultsConfig.rayFadeMid] of the length, 0 at the tip.
  static double rayFade(double u) {
    if (u <= 0) return 1;
    if (u >= 1) return 0;
    const m = ResultsConfig.rayFadeMid;
    const mid = ResultsConfig.rayAlphaMid / ResultsConfig.rayAlpha;
    if (u <= m) return 1 + (mid - 1) * (u / m);
    return mid * (1 - (u - m) / (1 - m));
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      bleedRectFor(this, size.y), // WP-TAB: the whole screen
      Paint()..color = kPostRunPalette.background,
    );
    // Right above the background: the card, banners, rank, bar, CLAIM, the
    // reward row and NEXT are all drawn after it and stay on top.
    _paintRays(canvas);
  }

  /// The 12 gold wedges around the emblem (`ResultsLevelStage.rays` drives
  /// the strength): unclipped, [ResultsConfig.rayRadius] × the page scale,
  /// with a radial fade per colour.
  void _paintRays(Canvas canvas) {
    final strength = stage.rays;
    if (strength <= 0) return;
    final k = content.scale.y;
    final plate = content.position.toOffset() + ResultsConfig.plateCentre * k;
    final radius = ResultsConfig.rayRadius * k;
    final a = strength.clamp(0.0, 1.0) * ResultsConfig.rayAlpha;
    final mid = a * ResultsConfig.rayAlphaMid / ResultsConfig.rayAlpha;
    const stops = [0.0, ResultsConfig.rayFadeMid, 1.0];
    _rayGold.shader = Gradient.radial(Offset.zero, radius, [
      ResultsConfig.gold.withValues(alpha: a),
      ResultsConfig.gold.withValues(alpha: mid),
      ResultsConfig.gold.withValues(alpha: 0),
    ], stops);
    _rayLight.shader = Gradient.radial(Offset.zero, radius, [
      ResultsConfig.goldLight.withValues(alpha: a),
      ResultsConfig.goldLight.withValues(alpha: mid),
      ResultsConfig.goldLight.withValues(alpha: 0),
    ], stops);
    final box = Rect.fromCircle(center: Offset.zero, radius: radius);
    final t = game.reduceMotion ? 0.0 : time;
    canvas.save();
    canvas.translate(plate.dx, plate.dy);
    canvas.rotate(t * ResultsConfig.raySpeed);
    const n = ResultsConfig.rays;
    const step = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..arcTo(box, i * step, step / 2, false)
          ..close(),
        i.isOdd ? _rayLight : _rayGold,
      );
    }
    canvas.restore();
  }
  // endregion PRD-2.2 §31.3
}

/// A flat filled box with children.
class _Box extends PositionComponent {
  _Box({
    required this.color,
    super.position,
    super.size,
    super.children,
  });

  final Color color;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    _paint.color = color;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// The versus card's soft panel (`fg` 14 % over the stage background).
class ResultsCard extends PositionComponent {
  ResultsCard()
    : super(
        position: ResultsConfig.card.topLeft.toVector2(),
        size: ResultsConfig.card.size.toVector2(),
      );

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    _paint.color = Color.lerp(
      kPostRunPalette.background,
      kPostRunPalette.foreground,
      ResultsConfig.cardTint,
    )!;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// One player in the card (§5.10): 40 pt avatar square (yours pink, the
/// opponent's stage grey) with the player's sticker avatar (WP-AV), the
/// name in Fredoka SemiBold 15 plum and the score (42 pt, 36 from four
/// digits; plum, or stage grey for the lower score in versus). WP-5b adds
/// the opponent's column and the WINNER tag ([winner]).
class ResultsPlayerColumn extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  ResultsPlayerColumn({
    required this.name,
    required this.score,
    required this.centreX,
    required this.mine,
    this.lower = false,
    this.winner = false,
    this.look = Look.defaults,
  });

  final String name;
  final int score;

  /// WP-AV the player's look: their sticker avatar (bird, gear, hat).
  final Look look;
  final double centreX;

  /// Yours (pink avatar) or the opponent's (stage grey).
  final bool mine;

  /// Versus: this score is the lower one (drawn in stage grey).
  final bool lower;
  final bool winner;

  late final MenuText scoreText;

  /// PRD-2.3 §21.2 the fitted name (tests).
  late final MenuText nameText;
  int _shown = 0;

  /// The score as counted up so far.
  int get shownScore => _shown;
  set shownScore(int value) {
    if (value == _shown) return;
    _shown = value;
    scoreText.text = '$value';
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // PRD-2.3 §21.2 the one name rule (shrink to 70 %, then "…").
    final fitted = fitName(
      name,
      centreX == ResultsConfig.soloColumnX
          ? ResultsConfig.nameRoomSolo
          : ResultsConfig.nameRoomVersus,
      ResultsConfig.nameFontSize,
      measureName(fontFamily: 'Fredoka', fontWeight: FontWeight.w600),
    );
    nameText = MenuText(
      fitted.text,
      fontSize: fitted.size,
      color: ResultsConfig.plum,
      fontFamily: 'Fredoka',
      fontWeight: FontWeight.w600,
      lineHeight: 1,
      position: Vector2(
        centreX,
        ResultsConfig.nameTop + (ResultsConfig.nameFontSize - fitted.size) / 2,
      ),
      anchor: Anchor.topCenter,
    );
    add(nameText);
    scoreText = MenuText(
      '0',
      fontSize: '$score'.length >= 4
          ? ResultsConfig.scoreFontSizeLong
          : ResultsConfig.scoreFontSize,
      color: lower ? kPostRunPalette.foreground : ResultsConfig.plum,
      lineHeight: 1.05,
      position: Vector2(centreX, ResultsConfig.scoreTop),
      anchor: Anchor.topCenter,
    );
    add(scoreText);
    if (winner) {
      // region WP-5b — §5.10 WINNER: gold tag, plum 11 pt, 0.1 em, 2 × 8
      add(
        ResultsWinnerTag(
          position: Vector2(centreX, ResultsConfig.winnerTagTop),
        ),
      );
      // endregion WP-5b
    }
  }

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    const s = ResultsConfig.avatarSize;
    final left = centreX - s / 2;
    final top = ResultsConfig.avatarTop;
    _paint.color = mine ? ResultsConfig.pink : kPostRunPalette.foreground;
    canvas.drawRect(Rect.fromLTWH(left, top, s, s), _paint);
    // WP-AV the sticker avatar; the opponent's faces left.
    game.avatars.paint(
      canvas,
      Rect.fromLTWH(left, top, s, s),
      look,
      mirror: !mine,
    );
  }
}

/// The level stage (§5.10, y 262, 148 tall, clipped like the mock canvas):
/// rotating gold rays during the celebration, the emblem (0.62) with the
/// equipped bird (× 1.4 in emblem units) flapping now and then; the old
/// emblem shakes and the new one pops in (0.2 → 1.3 → 0.92 → 1, 0.5 s).
class ResultsLevelStage extends PositionComponent {
  ResultsLevelStage(this._page, {required int level})
    : _level = level, // ignore: prefer_initializing_formals
      super(
        position: ResultsConfig.stage.topLeft.toVector2(),
        size: ResultsConfig.stage.size.toVector2(),
      );

  final ResultsScreen _page;
  int _level;

  /// The emblem drawn (switches to the new level at the pop).
  int get level => _level;
  set level(int value) {
    _level = value;
    if (isLoaded) emblem.level = value;
  }

  late final EmblemView emblem;
  late final LookComponent bird;
  late final PositionComponent _holder;

  /// Rays opacity (0 = none; 1 during the celebration).
  double rays = 0;
  double? shakeStart;
  double? popStart;
  final math.Random _rnd = math.Random();

  /// The mock's pop curve at [k] = t / 0.5.
  static double popScale(double k) {
    if (k >= 1) return 1;
    if (k < .6) return .2 + 1.1 * (k / .6);
    if (k < .8) return 1.3 - .38 * ((k - .6) / .2);
    return .92 + .08 * ((k - .8) / .2);
  }

  Offset get _plate => ResultsConfig.plateCentre - ResultsConfig.stage.topLeft;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final g = _page.game;
    emblem = EmblemView(level: _level, artScale: ResultsConfig.emblemScale);
    bird = LookComponent(
      look: g.menu.items.look,
      artScale: ResultsConfig.emblemScale * ResultsConfig.birdOnEmblem,
      anchor: Anchor.center,
    );
    _holder = PositionComponent(
      position: _plate.toVector2(),
      children: [emblem, bird],
    );
    add(_holder);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final t = _page.time;
    final still = _page.game.reduceMotion;
    emblem
      ..t = still ? 0 : t + 1
      ..shine = !still;
    bird.flapOverride =
        (t * ResultsConfig.birdFlapRate) % 1 < ResultsConfig.birdFlapShare;
    final ps = popStart;
    final s = ps == null ? 1.0 : popScale((t - ps) / ResultsConfig.emblemPop);
    _holder.scale = Vector2.all(s);
    var off = Vector2.zero();
    final sh = shakeStart;
    if (sh != null && t - sh < ResultsConfig.shake && !still) {
      off = Vector2(
        (_rnd.nextDouble() - .5) * 6,
        (_rnd.nextDouble() - .5) * 4,
      );
    }
    _holder.position = _plate.toVector2() + off;
  }

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x, y, width, height));
    super.renderTree(canvas);
    canvas.restore();
  }

}

/// The progress bar (§5.10): soft-pink track, pink fill, a white flash on
/// the level threshold; fades out when CLAIM takes its place.
class ResultsBar extends PositionComponent {
  ResultsBar(this._page)
    : super(
        position: ResultsConfig.bar.topLeft.toVector2(),
        size: ResultsConfig.bar.size.toVector2(),
      );

  final ResultsScreen _page;

  /// 0..1 fill.
  double fraction = 0;
  double opacity = 1;
  double? flashStart;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    if (opacity <= 0) return;
    final a = opacity.clamp(0.0, 1.0);
    _paint.color = ResultsConfig.soft.withValues(alpha: a);
    canvas.drawRect(size.toRect(), _paint);
    _paint.color = ResultsConfig.pink.withValues(alpha: a);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * fraction.clamp(0.0, 1.0), height),
      _paint,
    );
    final fs = flashStart;
    if (fs != null) {
      final u = (_page.time - fs) / ResultsConfig.barFlash;
      if (u < 1) {
        _paint.color = Color.fromRGBO(255, 255, 255, .95 * (1 - u) * a);
        canvas.drawRect(size.toRect(), _paint);
      }
    }
  }
}

/// The gold CLAIM ● +800 button (§5.10): 210 × 38 with a 3 pt gold-dark
/// edge, pops in (0.4 → 1.08 → 1, 0.38 s), then pulses 1 ↔ 1.06 every
/// 0.52 s; fades out (→ 0.6, 0.25 s) when claimed.
class ResultsClaimButton extends PositionComponent with GroupOpacity {
  ResultsClaimButton({
    required this.reward,
    required this.coin,
    required this.onPressed,
    required this.isActive,
  }) : super(
         position: ResultsConfig.claim.center.toVector2(),
         size: ResultsConfig.claim.size.toVector2(),
         anchor: Anchor.center,
       );

  final int reward;
  final Sprite coin;
  final void Function() onPressed;
  final bool Function() isActive;

  late final MenuButton button;
  late final WiggleEffect _pose;
  double? _shownAt;
  double? _hiddenAt;
  double _now = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    opacity = 0;
    _pose = WiggleEffect(this);
    decorator.addLast(_pose);
    add(
      RectangleComponent(
        position: Vector2(0, ResultsConfig.claimEdge),
        size: size.clone(),
        paint: Paint()..color = ResultsConfig.goldDark,
      ),
    );
    button = MenuButton(
      color: ResultsConfig.gold,
      size: size.clone(),
      onPressed: onPressed,
      isActive: isActive,
    );
    MenuText label(String s) => MenuText(
      s,
      fontSize: ResultsConfig.claimFontSize,
      color: ResultsConfig.plum,
    );
    layoutRow(button, [
      label('CLAIM'),
      // §3.0.6 / §3.0.9 #14 (S6-24): the CLAIM coin is the one shared gold
      // sprite with its pale inner ring — never a recoloured variant.
      MenuIcon(coin, size: Vector2.all(ResultsConfig.claimCoinSize)),
      label('+${formatCoins(reward)}'),
    ], gap: 8);
    add(button);
  }

  void show(double now) {
    _shownAt = now;
    _now = now;
  }

  void hide(double now) => _hiddenAt = now;

  /// Called by the page each frame with its clock.
  void tick(double now) {
    _now = now;
    final s = _shownAt;
    if (s == null) return;
    final h = _hiddenAt;
    if (h != null) {
      final u = ((now - h) / ResultsConfig.claimFadeOut).clamp(0.0, 1.0);
      opacity = 1 - u;
      _pose.scale = 1 - .4 * u;
      return;
    }
    final u = (now - s) / ResultsConfig.claimPop;
    if (u < 1) {
      opacity = u < .7 ? u / .7 : 1;
      _pose.scale = u < .7
          ? .4 + (1.08 - .4) * (u / .7)
          : 1.08 - .08 * ((u - .7) / .3);
      return;
    }
    opacity = 1;
    final p = (now - s - ResultsConfig.claimPop) / ResultsConfig.claimPulse;
    final tri = p % 2 < 1 ? p % 1 : 1 - p % 1; // alternate
    _pose.scale = 1 + (ResultsConfig.claimPulseScale - 1) * Ease.cubicInOut(tri);
  }

  /// Seconds the page clock last told this button.
  double get now => _now;

  @override
  void update(double dt) {
    super.update(dt);
    final page = findParent<ResultsScreen>();
    if (page != null) tick(page.time);
  }
}

/// LEVEL UP! (§5.10): Fredoka 22 plum on gold with a gold-dark drop edge,
/// dropping in at the NEW BEST spot (−40 pt, 0.5, −10° → 1.15, 3° at 70 %
/// → 1, −2°; 0.52 s).
class ResultsLevelUpBanner extends PositionComponent with GroupOpacity {
  ResultsLevelUpBanner() : super(anchor: Anchor.center, priority: 6);

  double? start;
  late final WiggleEffect _pose;
  late final MenuText _text;

  static const double _padH = 16, _padV = 4, _edge = 3;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _text = MenuText(
      'LEVEL UP!',
      fontSize: ResultsConfig.levelUpFontSize,
      color: ResultsConfig.plum,
      letterSpacingEm: .08,
      fontFamily: 'Fredoka',
      fontWeight: FontWeight.w600,
      lineHeight: 1.2,
      position: Vector2(_padH, _padV),
    );
    size = Vector2(_text.width + 2 * _padH, _text.height + 2 * _padV);
    position = Vector2(160, ResultsConfig.levelUpTop + size.y / 2);
    add(_text);
    _pose = WiggleEffect(this);
    decorator.addLast(_pose);
  }

  final Paint _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    final s = start;
    final page = findParent<ResultsScreen>();
    if (s == null || page == null) return;
    final u = ((page.time - s) / ResultsConfig.levelUpDrop).clamp(0.0, 1.0);
    final e = Ease.outQuad(u);
    double dy, sc, rot;
    if (e < .7) {
      final k = e / .7;
      dy = -40 * (1 - k);
      sc = .5 + .65 * k;
      rot = -10 + 13 * k;
      opacity = k;
    } else {
      final k = (e - .7) / .3;
      dy = 0;
      sc = 1.15 - .15 * k;
      rot = 3 - 5 * k;
      opacity = 1;
    }
    position.y = ResultsConfig.levelUpTop + size.y / 2 + dy;
    _pose
      ..scale = sc
      ..angle = rot * math.pi / 180;
  }

  @override
  void render(Canvas canvas) {
    _paint.color = ResultsConfig.goldDark;
    canvas.drawRect(Rect.fromLTWH(0, _edge, width, height), _paint);
    _paint.color = ResultsConfig.gold;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// The page's fx layer (world child above the strips, same transform as the
/// content column): confetti, fireworks, the claim coins and the white
/// screen flash.
class ResultsFx extends PositionComponent {
  ResultsFx(this._page) : super(priority: ResultsScreen.fxPriority);

  final ResultsScreen _page;

  /// The shared fireworks (rockets start below the page).
  late final Fireworks fireworks = Fireworks(launchY: 700);

  /// The white screen flash start (0.85 → 0 over 0.45 s).
  double? flashStart;

  /// Confetti bursts started (tests).
  final List<ConfettiBurst> bursts = [];

  /// The claim coin flight (tests).
  CoinFly? coins;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(fireworks);
  }

  void confetti(Offset at, int count, {double speed = 220}) {
    final burst = ConfettiBurst.burst(
      origin: at,
      count: count,
      speed: speed,
      driftX: 0,
      stars: true,
    );
    bursts.add(burst);
    add(burst);
  }

  /// §5.10 12 coins from the CLAIM button into YOUR REWARD.
  void flyCoins(Sprite coin, {void Function()? onLand}) {
    const from = ResultsConfig.claim;
    const pill = ResultsConfig.rewardPill;
    const size = 16.0;
    final fly = CoinFly.burst(
      coin: coin,
      origin: Offset(from.center.dx - size / 2, from.top + 19 - size / 2),
      to: Offset(pill.center.dx - size / 2, pill.center.dy - size / 2),
      count: ResultsConfig.claimCoins,
      duration: ResultsConfig.coinFlight,
      stagger: ResultsConfig.coinStagger,
      spreadX: 120,
      midSpreadX: 60,
      rise: (min: ResultsConfig.coinArc - 20, range: 20),
      coinSize: size,
      onLand: (_) => onLand?.call(),
    );
    coins = fly;
    add(fly);
  }

  final Paint _flash = Paint();

  @override
  void render(Canvas canvas) {
    final fs = flashStart;
    if (fs == null) return;
    final u = (_page.time - fs) / ResultsConfig.screenFlash;
    if (u >= 1 || u < 0) return;
    _flash.color = Color.fromRGBO(
      255,
      255,
      255,
      ResultsConfig.screenFlashAlpha * (1 - u),
    );
    // Cover the whole screen whatever the column's scale.
    canvas.drawRect(const Rect.fromLTWH(-400, -200, 1120, 1400), _flash);
  }
}

// region WP-5b — versus parts of §5.10

/// §5.10 the header (x 14 → 306, y 70, 48 tall, 28 pt, 0.12 em): pink
/// "YOU WIN!" (soft-pink text) or, on the stage foreground, "YOU LOSE" /
/// "DRAW" in the stage background colour.
class ResultsHeader extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  ResultsHeader(this.result)
    : super(
        position: ResultsConfig.header.topLeft.toVector2(),
        size: ResultsConfig.header.size.toVector2(),
      );

  final DuelResult result;
  late final MenuText label;
  final Paint _paint = Paint();

  String get text => switch (result) {
    DuelResult.win => 'YOU WIN!',
    DuelResult.lose => 'YOU LOSE',
    DuelResult.draw => 'DRAW',
  };

  bool get pink => result == DuelResult.win;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    label = MenuText(
      text,
      fontSize: ResultsConfig.headerFontSize,
      color: pink ? ResultsConfig.soft : kPostRunPalette.background,
      letterSpacingEm: ResultsConfig.headerLetterSpacing,
      lineHeight: 1,
      position: size / 2,
      anchor: Anchor.center,
    );
    add(label);
  }

  @override
  void render(Canvas canvas) {
    _paint.color = pink ? ResultsConfig.pink : kPostRunPalette.foreground;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// §5.10 the gold WINNER tag above the winner's avatar (plum 11 pt, 0.1 em,
/// padding 2 × 8), centred on [position].
class ResultsWinnerTag extends PositionComponent {
  ResultsWinnerTag({super.position}) : super(anchor: Anchor.topCenter);

  final Paint _paint = Paint()..color = ResultsConfig.gold;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final label = MenuText(
      'WINNER',
      fontSize: ResultsConfig.winnerTagFontSize,
      color: ResultsConfig.plum,
      letterSpacingEm: .1,
      lineHeight: 1.2,
      position: Vector2(ResultsConfig.winnerTagPadX, ResultsConfig.winnerTagPadY),
    );
    add(label);
    size = Vector2(
      label.width + 2 * ResultsConfig.winnerTagPadX,
      label.height + 2 * ResultsConfig.winnerTagPadY,
    );
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}
// endregion WP-5b
