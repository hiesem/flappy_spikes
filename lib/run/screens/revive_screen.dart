import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../components/ui/coin_fly.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../services/ads_service.dart';
import '../config/revive_config.dart';
import '../effects/coin_icon.dart';
import '../effects/easing.dart';
import '../effects/life_icons.dart';
import '../effects/screen_edge_glow.dart';
import '../hud/run_hud.dart';
import '../run_controller.dart';
import '../run_events.dart';
import '../run_summary.dart';
import 'phoenix_rise.dart';
import 'post_run_screens.dart';
import 'revive_ladder.dart';
import '../run_scaled_world.dart';

/// The WP-2d revive slot of the post-run flow (ARCH §1.11): shows the
/// [ReviveScreen] in the viewport and completes with its outcome.
class ReviveFlow implements ReviveScreenFactory {
  const ReviveFlow();

  @override
  Future<ReviveOutcome> show(FlappySpikesGame game, RunSummary s) async {
    final run = game.run;
    if (run == null) return ReviveOutcome.declined;
    final showcase = run.setup.showcase?.freeRevive ?? false;
    if (!showcase && run.state.hoopsPassed < ReviveConfig.minHoops) {
      return ReviveOutcome.declined;
    }
    final screen = ReviveScreen(run);
    game.camera.viewport.add(screen);
    return screen.outcome;
  }
}

/// Where the revive screen is.
enum RevivePhase { offer, ad, paying, shop, phoenix, closing, done }

/// Thousands separated by a space (§5.9: "1 000"; the approved mock's
/// gap — a U+2009 thin space all but vanishes in Opificio).
String formatCoins(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// §3.14 / §5.9 the revive offer ("v2 — price ladder + phoenix rise"), in
/// the viewport over the frozen game (the dead bird lying on the floor
/// spikes; the [ReviveDim] overlay sits in the world so the phoenix can
/// rise above it).
///
/// One option per death from the [ReviveLadder]: the pink ad heart, the
/// gold coin heart (250, 500, 1 000 …), the grey locked heart with
/// GET COINS › (PRD-2.3.1 §14: no FREE heart for NO ADS owners any more). The
/// whole heart is the button; it drains from the top over 5 s (urgency
/// from 3 s: shake, faster beat, red edge glow). PRD-2.2 §7.15: it never
/// times out — the empty heart keeps pulsing until the player presses it
/// or No thanks (the only way to decline, §24). A watched ad or a payment starts the [PhoenixRise];
/// at 1.65 s the game resumes the run and this completes with
/// [ReviveOutcome.revived].
class ReviveScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  ReviveScreen(this.run) : super(priority: 20);

  final RunController run;
  final Completer<ReviveOutcome> _outcome = Completer();

  Future<ReviveOutcome> get outcome => _outcome.future;

  late ReviveOffer offer;
  RevivePhase phase = RevivePhase.offer;

  /// Offer clock (s): runs only while the offer is up (not during the ad,
  /// the payment or the Shop).
  double countdown = 0;

  /// Opacity of the offer UI.
  double ui = 0;
  double _uiTarget = 1;
  double _uiSpeed = 1 / ReviveConfig.fadeOut;

  late final ReviveDim dim;
  late final ScreenEdgeGlow glow;
  Image? _coin;
  PhoenixRise? phoenix;

  double _clock = 0;
  final List<(double, void Function())> _later = [];

  // Animation timers (s since they started; < 0 = idle).
  double _popT = -1, _shakeT = -1, _bumpT = -1, _flashT = -1, _squeezeT = -1;
  double _countT = -1;
  int _balanceFrom = 0, _balanceTo = 0;
  double _beatPhase = 0;

  /// The balance the pill shows.
  int shownBalance = 0;

  int get balance => game.menu.wallet.balance;

  /// §5.9 the grey locked heart: a coin offer the wallet cannot pay.
  bool get locked =>
      offer.isCoins && phase == RevivePhase.offer && balance < offer.price;

  /// "need N more".
  int get need => math.max(0, offer.price - balance);

  /// 0..1 drained from the top.
  double get drain => (countdown / ReviveConfig.offerSeconds).clamp(0.0, 1.0);

  /// The heart box on screen.
  Rect get heartRect {
    final cy = game.viewHeight / 2 + ReviveConfig.heartCentreOffset;
    return Rect.fromCenter(
      center: Offset(ReviveConfig.heartLeft + ReviveConfig.heartWidth / 2, cy),
      width: ReviveConfig.heartWidth,
      height: ReviveConfig.heartHeight,
    );
  }

  Rect get _heartTarget {
    final r = heartRect;
    final m = ReviveConfig.minTarget;
    return Rect.fromCenter(
      center: r.center,
      width: math.max(r.width, m),
      height: math.max(r.height, m),
    );
  }

  late final HudText _noAd = HudText(
    ReviveConfig.noAdText,
    size: ReviveConfig.noAdSize,
    color: const Color(0xCCFFFFFF),
    spacing: .1,
  );
  late final HudText _getCoins = HudText(
    ReviveConfig.getCoinsText,
    size: ReviveConfig.getCoinsSize,
    color: ReviveConfig.plum,
    spacing: .1,
  );
  late final HudText _noThanks = HudText(
    ReviveConfig.noThanksText,
    size: ReviveConfig.noThanksSize,
    color: const Color(0xBFFFFFFF),
    spacing: .06,
  );
  late final HudText _adRevive = HudText(
    'REVIVE',
    size: ReviveConfig.adReviveSize,
    color: const Color(0xFFFFFFFF),
    spacing: ReviveConfig.adReviveSpacing,
  );
  late final HudText _coinRevive = HudText(
    'REVIVE',
    size: ReviveConfig.coinReviveSize,
    color: ReviveConfig.plum,
    spacing: ReviveConfig.coinReviveSpacing,
  );
  late final HudText _freeRevive = HudText(
    'FREE',
    size: ReviveConfig.adReviveSize,
    color: const Color(0xFFFFFFFF),
    spacing: ReviveConfig.adReviveSpacing,
  );
  late final HudText _lockRevive = HudText(
    'REVIVE',
    size: ReviveConfig.lockReviveSize,
    color: const Color(0xFFFFFFFF),
    spacing: .1,
  );
  final Map<String, HudText> _texts = {};

  HudText _text(String s, double size, Color c, [double spacing = 0]) =>
      _texts.putIfAbsent(
        '$s|$size|${c.toARGB32()}|$spacing',
        () => HudText(s, size: size, color: c, spacing: spacing),
      );

  @override
  Future<void> onLoad() async {
    size = Vector2(320, game.viewHeight);
    // WP-TAB: a 320 pt column centred on a wide screen.
    position.x = game.extraWidth / 2;
    try {
      _coin = await game.images.load(CoinIcon.asset);
    } catch (_) {
      _coin = null; // a missing asset never blocks the offer
    }
    // PRD-2.3.1 §14: NO ADS owners skip the ad step (no free revive, no
    // "NO AD AVAILABLE" label); the ladder decides.
    offer = ReviveLadder.offer(
      run.state,
      adReady: game.monetization.ads.isAvailable,
      noAds: game.menu.noAds,
      showcase: run.setup.showcase?.freeRevive ?? false,
    );
    shownBalance = balance;
    dim = ReviveDim();
    game.world.addRun(dim);
    dim.fadeTo(ReviveConfig.dim, ReviveConfig.fadeOut);
    // WP-TAB: the glow follows the true screen edges.
    glow = ScreenEdgeGlow.reviveUrgency(Vector2(game.viewWidth, size.y))
      ..position.x = -game.extraWidth / 2
      ..intensity = 0;
    add(glow);
    _fadeUi(1);
    _track('revive_offered', {
      'offer': offer.kind.name,
      'price': offer.price,
      'revive_index': run.state.revivesThisGame + 1,
    });
  }

  void _track(String name, [Map<String, Object>? p]) =>
      game.services.track(name, p);

  void _after(double seconds, void Function() f) =>
      _later.add((_clock + seconds, f));

  void _fadeUi(double to, [double seconds = ReviveConfig.fadeOut]) {
    _uiTarget = to;
    _uiSpeed = seconds <= 0 ? double.infinity : 1 / seconds;
  }

  // ------------------------------------------------------------------ taps

  bool get _blocking =>
      phase == RevivePhase.offer ||
      phase == RevivePhase.paying ||
      phase == RevivePhase.closing;

  @override
  bool containsLocalPoint(Vector2 point) => _blocking;

  Rect get _getCoinsRect {
    final h = _getCoins.height + 2 * ReviveConfig.getCoinsPadY;
    final w = _getCoins.width + 2 * ReviveConfig.getCoinsPadX;
    return Rect.fromLTWH(
      160 - w / 2,
      heartRect.bottom + ReviveConfig.getCoinsGap,
      w,
      h,
    );
  }

  Rect get _noThanksRect {
    final top = heartRect.bottom + ReviveConfig.noThanksGap;
    return Rect.fromLTWH(160 - 80, top - 12, 160, _noThanks.height + 24);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (phase != RevivePhase.offer || ui < .5) return;
    final p = event.localPosition.toOffset();
    if (_heartTarget.contains(p)) {
      tapHeart();
    } else if (locked && _getCoinsRect.inflate(8).contains(p)) {
      tapGetCoins();
    } else if (_noThanksRect.contains(p)) {
      tapNoThanks();
    }
  }

  /// The heart (tests call it directly).
  void tapHeart() {
    if (phase != RevivePhase.offer) return;
    if (locked) {
      game.sound.play(Sfx.rvLocked);
      _shakeT = 0;
      _bumpT = 0;
      _track('revive_locked_tap', {'price': offer.price});
      return;
    }
    _popT = 0;
    _trackWaited();
    if (offer.isFree) {
      phase = RevivePhase.paying;
      _track('revive_free_used', {
        'revive_index': run.state.revivesThisGame + 1,
      });
      ReviveLadder.record(run.state, offer);
      _after(ReviveConfig.adHideDelay, () => _fadeUi(0));
      _after(
        ReviveConfig.adHideDelay + ReviveConfig.phoenixDelay,
        () => _startPhoenix(ReviveKind.coins, 0),
      );
    } else if (offer.isAd) {
      phase = RevivePhase.ad;
      _track('revive_ad_started');
      _after(ReviveConfig.adHideDelay, () {
        _fadeUi(0);
        unawaited(_playAd());
      });
    } else {
      unawaited(_pay());
    }
  }

  Future<void> _playAd() async {
    final result = await game.showRewardedAd(AdPlacement.revive);
    if (phase != RevivePhase.ad || isRemoved) return;
    if (result == AdResult.completed) {
      _track('revive_ad_completed');
      ReviveLadder.record(run.state, offer);
      _after(ReviveConfig.phoenixDelay, () => _startPhoenix(ReviveKind.ad, 0));
    } else {
      // §3.14 closed early / failed: the offer comes back with the time
      // that was left.
      phase = RevivePhase.offer;
      _fadeUi(1);
    }
  }

  Future<void> _pay() async {
    phase = RevivePhase.paying;
    final price = offer.price;
    final before = balance;
    final ok = await game.menu.wallet.spend(price, 'revive');
    if (isRemoved) return;
    if (!ok) {
      phase = RevivePhase.offer;
      return;
    }
    _track('revive_coins', {
      'price': price,
      'revive_index': run.state.revivesThisGame + 1,
    });
    ReviveLadder.record(run.state, offer);
    game.sound.play(Sfx.rvPay);
    final coin = _coin;
    if (coin != null) {
      final c = heartRect.center;
      add(
        CoinFly(
          coin: Sprite(coin),
          from: pillRect,
          to: Offset(c.dx - 9, c.dy - 9),
          count: ReviveConfig.payCoins,
          duration: ReviveConfig.payCoinLength,
          stagger: ReviveConfig.payCoinStagger,
          delay: 0,
          onLand: (_) => game.sound.play(Sfx.bnCoin),
          priority: 5,
        ),
      );
    }
    _balanceFrom = before;
    _balanceTo = before - price;
    _countT = 0;
    _squeezeT = 0;
    _after(ReviveConfig.payFlashAt, () => _flashT = 0);
    _after(ReviveConfig.payHideAt, () => _fadeUi(0));
    _after(
      ReviveConfig.payHideAt + ReviveConfig.phoenixDelay,
      () => _startPhoenix(ReviveKind.coins, price),
    );
  }

  /// GET COINS › (locked only): the Shop over the paused game.
  void tapGetCoins() {
    if (phase != RevivePhase.offer || !locked) return;
    _track('revive_get_coins', {'price': offer.price});
    phase = RevivePhase.shop;
    game.openReviveShop(onClose: _shopClosed);
  }

  void _shopClosed() {
    if (phase != RevivePhase.shop) return;
    phase = RevivePhase.offer;
    shownBalance = balance;
  }

  void tapNoThanks() {
    if (phase != RevivePhase.offer) return;
    _trackWaited();
    _track('revive_declined');
    _decline();
  }

  bool _waitedTracked = false;

  /// PRD-2.2 §7.15 `revive_offer_waited {seconds}`: the player answered
  /// after the heart was empty (seconds since it emptied, whole).
  void _trackWaited() {
    if (_waitedTracked || countdown < ReviveConfig.offerSeconds) return;
    _waitedTracked = true;
    _track('revive_offer_waited', {
      'seconds': (countdown - ReviveConfig.offerSeconds).round(),
    });
  }

  void _decline() {
    phase = RevivePhase.closing;
    _fadeUi(0);
    dim.fadeTo(0, ReviveConfig.fadeOut, remove: true);
    _after(ReviveConfig.fadeOut, () => _finish(ReviveOutcome.declined));
  }

  void _startPhoenix(ReviveKind kind, int price) {
    if (phase == RevivePhase.done || isRemoved) return;
    phase = RevivePhase.phoenix;
    run.beginRevive(kind, price);
    final p = PhoenixRise(
      run: run,
      dim: dim,
      onDone: (y) {
        game.finishRevive(run, kind, price, y);
        dim.fadeTo(0, ReviveConfig.endDimFade, remove: true);
        _finish(ReviveOutcome.revived);
      },
    );
    phoenix = p;
    game.world.addRun(p);
  }

  void _finish(ReviveOutcome o) {
    if (phase == RevivePhase.done && _outcome.isCompleted) return;
    phase = RevivePhase.done;
    if (!_outcome.isCompleted) _outcome.complete(o);
    removeFromParent();
  }

  // ---------------------------------------------------------------- update

  /// The heart's beat scale now (§5.9: idle 1.035 at 1.25 Hz; urgent up to
  /// 1.06 with the rate rising 1.2 → 3 Hz).
  double beat = 1;

  /// The heart's urgency shake (pt) now.
  double shake = 0;

  /// The urgency envelope (0..1).
  double urgency = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (!identical(game.run, run) || run.isRemoved) {
      if (!_outcome.isCompleted) _outcome.complete(ReviveOutcome.declined);
      phase = RevivePhase.done;
      if (dim.isMounted) dim.removeFromParent();
      removeFromParent();
      return;
    }
    _clock += dt;
    for (final e in List.of(_later)) {
      if (_clock >= e.$1) {
        _later.remove(e);
        e.$2();
      }
    }
    if (ui != _uiTarget) {
      final s = _uiSpeed.isInfinite ? 1.0 : dt * _uiSpeed;
      ui = ui < _uiTarget
          ? math.min(_uiTarget, ui + s)
          : math.max(_uiTarget, ui - s);
    }
    if (phase == RevivePhase.offer) {
      // PRD-2.2 §7.15: no auto-decline; the clock only drives the drain
      // and the urgency envelope.
      countdown += dt;
    }
    final t = countdown;
    double sm(double x) => Ease.smooth(x.clamp(0.0, 1.0));
    final offerUp = phase == RevivePhase.offer;
    // The shake eases out as the heart empties (§5.9) ...
    urgency = offerUp
        ? sm((t - ReviveConfig.urgencyStart) / ReviveConfig.urgencyRise) *
              (1 -
                  sm(
                    (t - ReviveConfig.urgencyOutStart) /
                        ReviveConfig.urgencyOutLength,
                  ))
        : 0;
    // ... but PRD-2.2 §7.15 the empty heart keeps pulsing at the urgent beat.
    final beatEnv = offerUp
        ? sm((t - ReviveConfig.urgencyStart) / ReviveConfig.urgencyRise)
        : 0.0;
    final hz =
        ReviveConfig.beatHzFrom +
        (ReviveConfig.beatHzTo - ReviveConfig.beatHzFrom) *
            sm((t - ReviveConfig.urgencyStart) / ReviveConfig.beatRise);
    if (offerUp) _beatPhase += dt * hz * 2 * math.pi;
    // §5.9 S6-21: the two amplitudes are the peaks themselves (idle 1.035,
    // urgent 1.06), so neither may be doubled by its waveform.
    final idle = t < ReviveConfig.urgencyStart
        ? ReviveConfig.idleBeatScale *
              math.pow(
                math.sin(_clock * 2 * math.pi * ReviveConfig.idleBeatHz),
                2,
              )
        : 0.0;
    beat = offerUp
        ? 1 +
              idle +
              ReviveConfig.beatAmplitude *
                  beatEnv *
                  (1 - math.cos(_beatPhase)) /
                  2
        : 1;
    shake =
        math.sin(_clock * 2 * math.pi * ReviveConfig.shakeHz) *
        ReviveConfig.shakeAmplitude *
        urgency;
    // PRD-2.2 §7.15: the red edge glow settles to a steady level.
    glow.intensity = offerUp
        ? sm((t - ReviveConfig.urgencyStart) / ReviveConfig.glowIn) *
              (1 -
                  (1 - ReviveConfig.waitGlow) *
                      sm(
                        (t - ReviveConfig.glowOutStart) /
                            ReviveConfig.glowOutLength,
                      ))
        : 0;
    void tick(double v, void Function(double) set, double len) {
      if (v < 0) return;
      v += dt;
      set(v > len ? -1 : v);
    }

    tick(_popT, (v) => _popT = v, ReviveConfig.popLength);
    tick(_shakeT, (v) => _shakeT = v, ReviveConfig.lockShakeLength);
    tick(_bumpT, (v) => _bumpT = v, ReviveConfig.getCoinsBumpLength);
    tick(_flashT, (v) => _flashT = v, ReviveConfig.payFlashLength);
    tick(_squeezeT, (v) => _squeezeT = v, .3);
    if (_countT >= 0) {
      _countT += dt;
      final k = (_countT / ReviveConfig.countDown).clamp(0.0, 1.0);
      shownBalance = (_balanceFrom + (_balanceTo - _balanceFrom) * k).round();
      if (k >= 1) _countT = -1;
    } else if (phase == RevivePhase.offer || phase == RevivePhase.shop) {
      shownBalance = balance;
    }
  }

  // ---------------------------------------------------------------- render

  /// The balance pill (right edge 306, top 58).
  Rect get pillRect {
    final t = _text(
      formatCoins(shownBalance),
      ReviveConfig.pillFont,
      ReviveConfig.soft,
    );
    final w = ReviveConfig.pillPad * 2 + t.width + 8 + ReviveConfig.pillCoin;
    return Rect.fromLTWH(
      ReviveConfig.pillRight - w,
      ReviveConfig.pillTop,
      w,
      ReviveConfig.pillHeight,
    );
  }

  final Paint _p = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    if (phase == RevivePhase.shop || phase == RevivePhase.done) return;
    final a = ui;
    if (a <= 0) return;
    _renderPill(canvas, a);
    final hr = heartRect;
    if (offer.noAdLabel) {
      _noAd.paintCentred(
        canvas,
        Offset(160, hr.top - ReviveConfig.noAdGap + _noAd.height / 2),
        opacity: a,
      );
    }
    _renderHeart(canvas, hr, a);
    if (locked) {
      final r = _getCoinsRect;
      final bump = _bumpT < 0
          ? 1.0
          : 1 +
                (ReviveConfig.getCoinsBump - 1) *
                    math.sin(
                      math.pi * _bumpT / ReviveConfig.getCoinsBumpLength,
                    );
      canvas
        ..save()
        ..translate(r.center.dx, r.center.dy)
        ..scale(bump)
        ..translate(-r.center.dx, -r.center.dy);
      _p.color = ReviveConfig.gold.withValues(alpha: a);
      canvas.drawRect(r, _p);
      _getCoins.paintCentred(canvas, r.center, opacity: a);
      canvas.restore();
    }
    _noThanks.paintCentred(
      canvas,
      Offset(160, hr.bottom + ReviveConfig.noThanksGap + _noThanks.height / 2),
      opacity: a,
    );
  }

  void _renderPill(Canvas canvas, double a) {
    final r = pillRect;
    final sq = _squeezeT < 0
        ? 1.0
        : 1 -
              (1 - ReviveConfig.pillSqueeze) *
                  math.sin(math.pi * _squeezeT / .3);
    canvas
      ..save()
      ..translate(r.center.dx, r.center.dy)
      ..scale(sq)
      ..translate(-r.center.dx, -r.center.dy);
    _p.color = ReviveConfig.plum.withValues(alpha: a);
    canvas.drawRect(r, _p);
    final t = _text(
      formatCoins(shownBalance),
      ReviveConfig.pillFont,
      ReviveConfig.soft,
    );
    t.paintCentred(
      canvas,
      Offset(r.left + ReviveConfig.pillPad + t.width / 2, r.center.dy),
      opacity: a,
    );
    _paintCoin(
      canvas,
      Offset(
        r.right - ReviveConfig.pillPad - ReviveConfig.pillCoin / 2,
        r.center.dy,
      ),
      ReviveConfig.pillCoin,
      a,
    );
    canvas.restore();
  }

  void _paintCoin(Canvas canvas, Offset c, double size, double a) {
    final img = _coin;
    if (img != null) {
      CoinIcon.paint(canvas, img, c, size, opacity: a);
      return;
    }
    _p.color = ReviveConfig.gold.withValues(alpha: a);
    canvas.drawCircle(c, size / 2, _p);
  }

  (Color, Color) get _colors {
    if (offer.isAd || offer.isFree) {
      return (ReviveConfig.adFill, ReviveConfig.adBorder);
    }
    if (locked) return (ReviveConfig.lockFill, ReviveConfig.lockBorder);
    return (ReviveConfig.coinFill, ReviveConfig.coinBorder);
  }

  void _renderHeart(Canvas canvas, Rect hr, double a) {
    final c = hr.center;
    final pop = _popT < 0 ? 1.0 : _popScale(_popT / ReviveConfig.popLength);
    final lockShake = _shakeT < 0
        ? 0.0
        : ReviveConfig.lockShake *
              math.sin(_shakeT / ReviveConfig.lockShakeLength * 5 * math.pi);
    canvas
      ..save()
      ..translate(c.dx + shake + lockShake, c.dy)
      ..scale(beat * pop)
      ..translate(-c.dx, -c.dy);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(1, hr.height / hr.width)
      ..translate(-c.dx, -c.dy);
    LifeIcons.paintHeart(
      canvas,
      c,
      hr.width,
      fill: ReviveConfig.emptyFill,
      outline: ReviveConfig.heartStroke,
      outlineColor: ReviveConfig.emptyBorder,
      opacity: a,
    );
    final d = drain;
    if (d < 1) {
      var (fill, border) = _colors;
      if (_flashT >= 0) {
        final f =
            math.sin(math.pi * _flashT / ReviveConfig.payFlashLength) * .45;
        fill = Color.lerp(fill, const Color(0xFFFFFFFF), f)!;
      }
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            hr.left - 4,
            hr.top + d * hr.height - 2,
            hr.right + 4,
            hr.bottom + 4,
          ),
        );
      LifeIcons.paintHeart(
        canvas,
        c,
        hr.width,
        fill: fill,
        outline: ReviveConfig.heartStroke,
        outlineColor: border,
        opacity: a,
      );
      canvas.restore();
    }
    canvas.restore();
    _renderLabels(canvas, c, a);
    canvas.restore();
  }

  /// 1 → 1.12 (40 %) → 0.92.
  static double _popScale(double k) {
    if (k < .4) return 1 + .12 * (k / .4);
    return 1.12 + (.92 - 1.12) * ((k - .4) / .6);
  }

  void _renderLabels(Canvas canvas, Offset c, double a) {
    const white = Color(0xFFFFFFFF);
    if (offer.isAd) {
      _videoIcon(
        canvas,
        Offset(c.dx, c.dy + ReviveConfig.videoIconTop + 15),
        a,
      );
      _adRevive.paintCentred(canvas, Offset(c.dx, c.dy + 2), opacity: a);
      return;
    }
    if (offer.isFree) {
      _freeRevive.paintCentred(canvas, Offset(c.dx, c.dy - 6), opacity: a);
      return;
    }
    final price = formatCoins(offer.price);
    if (locked) {
      // "🔒 REVIVE": padlock + text, centred together.
      const lockW = 18.0, gap = 9.0;
      final w = lockW + gap + _lockRevive.width;
      final y = c.dy - 38.5;
      _padlock(canvas, Offset(c.dx - w / 2 + lockW / 2, y), a);
      _lockRevive.paintCentred(
        canvas,
        Offset(c.dx - w / 2 + lockW + gap + _lockRevive.width / 2, y),
        opacity: a,
      );
      _priceRow(
        canvas,
        Offset(c.dx, c.dy + 2.5),
        price,
        ReviveConfig.lockPriceSize,
        ReviveConfig.lockCoinSize,
        white,
        a,
      );
      _text(
        'need ${formatCoins(need)} more',
        ReviveConfig.needSize,
        const Color(0xE6FFFFFF),
        .06,
      ).paintCentred(canvas, Offset(c.dx, c.dy + 32.5), opacity: a);
      return;
    }
    _coinRevive.paintCentred(canvas, Offset(c.dx, c.dy - 38), opacity: a);
    _priceRow(
      canvas,
      Offset(c.dx, c.dy + 4),
      price,
      ReviveConfig.priceSize,
      ReviveConfig.priceCoinSize,
      ReviveConfig.plum,
      a,
    );
  }

  void _priceRow(
    Canvas canvas,
    Offset c,
    String price,
    double size,
    double coin,
    Color color,
    double a,
  ) {
    final t = _text(price, size, color);
    final w = coin + 8 + t.width;
    _paintCoin(canvas, Offset(c.dx - w / 2 + coin / 2, c.dy), coin, a);
    t.paintCentred(
      canvas,
      Offset(c.dx - w / 2 + coin + 8 + t.width / 2, c.dy),
      opacity: a,
    );
  }

  /// The mock's 30 pt video glyph (24-unit box): rect 1,4 15×16 r2 + the
  /// lens triangle 16,10 → 23,6 → 23,18 → 16,14.
  void _videoIcon(Canvas canvas, Offset c, double a) {
    final k = ReviveConfig.videoIconSize / 24;
    canvas
      ..save()
      ..translate(c.dx - 12 * k, c.dy - 12 * k)
      ..scale(k);
    _p.color = Color.fromRGBO(255, 255, 255, a);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1, 4, 15, 16),
          const Radius.circular(2),
        ),
        _p,
      )
      ..drawPath(
        Path()
          ..moveTo(16, 10)
          ..lineTo(23, 6)
          ..lineTo(23, 18)
          ..lineTo(16, 14)
          ..close(),
        _p,
      )
      ..restore();
  }

  /// A small gold padlock (the mock's 🔒), 18 pt wide.
  void _padlock(Canvas canvas, Offset c, double a) {
    _stroke
      ..strokeWidth = 2.6
      ..color = const Color(0xFF9E9E9E).withValues(alpha: a);
    canvas.drawArc(
      Rect.fromCenter(center: c.translate(0, -3), width: 11, height: 13),
      math.pi,
      math.pi,
      false,
      _stroke,
    );
    canvas.drawLine(c.translate(-5.5, -3), c.translate(-5.5, 1), _stroke);
    canvas.drawLine(c.translate(5.5, -3), c.translate(5.5, 1), _stroke);
    _p.color = const Color(0xFFF2B01E).withValues(alpha: a);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c.translate(0, 5), width: 17, height: 13),
        const Radius.circular(2.5),
      ),
      _p,
    );
    _p.color = const Color(0xFF6B4A00).withValues(alpha: a);
    canvas.drawCircle(c.translate(0, 4.5), 1.8, _p);
  }
}
