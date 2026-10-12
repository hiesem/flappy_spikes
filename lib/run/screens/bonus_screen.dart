import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/flappy_game.dart';
import '../../game/palettes.dart';
import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../../services/ads_service.dart';
import '../config/bonus_config.dart';
import '../effects/coin_icon.dart';
import '../effects/easing.dart';
import '../effects/particle_pool.dart';
import '../effects/pickup_touch_fx.dart';
import '../effects/shock_ring.dart';
import '../effects/twinkle.dart';
import '../hud/collect_layer.dart' show CollectText;
import '../pickups/feather_pickup.dart';
import '../run_summary.dart';
import 'post_run_screens.dart';
import '../../game/paints.dart';

/// The balloon bonus slot of the post-run flow (PRD-2 §3.15, ARCH §1.11):
/// registered by the game (region WP-4a), shown by `PostRunFlow.run` when
/// 3 feathers are held, between the revive offer and the results page.
class BonusPage implements BonusScreenFactory {
  const BonusPage();

  @override
  Future<void> show(FlappySpikesGame game, RunSummary s) => game.showBonus(s);
}

/// What the out-of-feathers offer is (§3.15).
enum BonusOffer {
  /// No offer: NEXT (the ad was used, or no ad can be shown).
  none,

  /// The gold ▶ feather ×3 rewarded-ad button.
  ad,

  /// No-ads owners: the same button without the video icon, no ad (Q2).
  free,
}

/// The pure rules of the bonus screen (§3.15), unit-tested without Flame.
abstract final class BonusRules {
  /// §3.15 / Q35 the nine prizes, shuffled per screen.
  static List<int> shuffledPrizes(math.Random r) =>
      List.of(BonusConfig.prizes)..shuffle(r);

  /// §5.14 3–8 coins fly into the pill (by amount).
  static int coinsFor(int prize) => math.min(8, 3 + prize ~/ 50);

  /// The coin values of those coins (they add up to [prize]).
  static List<int> coinSplit(int prize) {
    final n = coinsFor(prize);
    final each = prize ~/ n;
    return [for (var k = 0; k < n; k++) k < n - 1 ? each : prize - each * (n - 1)];
  }

  /// §3.15 the offer when the feathers run out: once per screen; no-ads
  /// owners get it free; without an ad to show it is skipped.
  static BonusOffer offerFor({
    required bool adUsed,
    required bool noAds,
    required bool adAvailable,
  }) {
    if (adUsed) return BonusOffer.none;
    if (noAds) return BonusOffer.free;
    return adAvailable ? BonusOffer.ad : BonusOffer.none;
  }

  /// §5.14 the reference → screen transform of the column above the
  /// bottom band for a [h] pt tall screen: the 711 pt mock between the two
  /// 44 pt strips, scaled about the top centre so the reference band top
  /// ([BonusConfig.bandTop]) meets the bottom-anchored band on shorter
  /// screens, and centred on taller ones (§3.0.1, S6-63).
  static (double scale, Offset offset) layoutFor(double h) {
    const strips = 44.0;
    const band = BonusConfig.referenceHeight - BonusConfig.bandTop;
    final k = math.min(
      1.0,
      (h - band - strips) / (BonusConfig.bandTop - strips),
    );
    final dy = strips - strips * k + math.max(0.0, (h - 711) / 2);
    return (k, Offset(160 * (1 - k), dy));
  }

  /// §3.0.1 (S6-63) the bottom band's screen shift for a [h] pt tall
  /// screen: unscaled, its reference bottom distance kept (the feather
  /// row, the ad button, NO THANKS and NEXT).
  static double bandShiftFor(double h) => h - BonusConfig.referenceHeight;

  /// §5.14 tile [i]'s rect and centre (reference coordinates).
  static Rect tileRect(int i) => Rect.fromLTWH(
    BonusConfig.gridOrigin.dx + (i % 3) * BonusConfig.tileStep,
    BonusConfig.gridOrigin.dy + (i ~/ 3) * BonusConfig.tileStep,
    BonusConfig.tile,
    BonusConfig.tile,
  );

  /// §5.14 feather [k] of the row.
  static Offset rowSlot(int k) =>
      Offset(BonusConfig.rowX + BonusConfig.rowStep * k, BonusConfig.rowY);
}

/// Where the screen is in its flow.
enum BonusPhase { pick, offer, ad, done, leaving }

class _Tile {
  _Tile(this.prize);
  final int prize;

  /// Seconds since the feather arrived (−1 = idle).
  double o = -1;
  bool pending = false;
  bool get opened => o >= 0 || pending;
}

class _Flight {
  _Flight({
    required this.from,
    required this.to,
    required this.t0,
    required this.dur,
    this.tile,
    this.n = 0,
    this.refill = false,
  });
  final Offset from, to;
  final double t0, dur;
  final int? tile;
  final int n;
  final bool refill;
  double trail = 0;
  bool done = false;
}

class _Coin {
  _Coin(this.from, this.t0, this.value);
  final Offset from;
  final double t0;
  final int value;
  bool done = false;
}

/// The balloon bonus screen (PRD-2 §3.15 / §5.14, approved
/// `screen_feather_balloon.html`, engine `bonus.js` with the final flow):
/// the total pill, the hero (coin heap with golden-feather wings and the
/// POP THE JACKPOT! banner), the 3 × 3 balloon grid, the prompt, the
/// feather row and the out-of-feathers ad offer / NO THANKS / NEXT. Each
/// pop credits its prize to the menu wallet at once (`bonus`); the
/// results' YOUR REWARD does not include it (Q36).
///
/// Drawn in the 320 × 711 reference, transformed by [BonusRules.layoutFor];
/// a stage-coloured page between the strips (lifted over it by the game).
class BonusScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  BonusScreen({required this.summary, required List<int> prizes, int? seed})
    : _r = math.Random(seed),
      _tiles = [for (final p in prizes) _Tile(p)],
      super(priority: priorityOnTop);

  /// Above the run (as the results page; strips lifted to 21).
  static const int priorityOnTop = 20;

  final RunSummary summary;
  final List<_Tile> _tiles;
  final math.Random _r;

  final Completer<void> _finished = Completer<void>();

  /// Completes on NO THANKS / NEXT.
  Future<void> get finished => _finished.future;

  double _t = 0;
  double get time => _t;

  BonusPhase phase = BonusPhase.pick;
  double _ph0 = 0;

  /// Feathers in the row.
  int feathers = BonusConfig.feathers;

  /// Pops so far (1–6).
  int pops = 0;
  bool adUsed = false;

  /// The offer shown in [BonusPhase.offer].
  BonusOffer offer = BonusOffer.none;

  /// Coins credited on this screen / shown in the pill.
  int credited = 0;
  int shown = 0;

  double _busy = 0;
  double _punch = -9;
  double _coinSound = -9;
  double _flash = -9;

  final List<_Flight> _flights = [];
  final List<_Coin> _coins = [];

  late final PositionComponent content;
  final ParticlePool pool = ParticlePool(capacity: 220, priority: 1);
  static final EffectPool<ShockRing> _rings = ShockRing.newPool();
  static final EffectPool<PickupTouchFx> _flashes = PickupTouchFx.newPool();
  static const PickupTouchSpec _popFlash = PickupTouchSpec(
    flashFrom: 10,
    flashTo: 40,
    flashLength: .18,
  );

  Image? _coin;
  double _k = 1;
  Offset _offset = Offset.zero;
  double _band = 0;

  /// §3.0.1 (S6-63) a bottom-band reference point in [content]'s
  /// (scaled) reference coordinates.
  Offset _bandToContent(Offset p) => Offset(
    (p.dx - _offset.dx) / _k,
    (p.dy + _band - _offset.dy) / _k,
  );

  /// NEXT's rect on the screen (tests): 292 × 50 at the reference bottom
  /// distance on every height (§5.14, §3.0.1).
  Rect get nextRect => BonusConfig.nextButton.shift(Offset(0, _band));

  /// The ad button's rect on the screen (tests).
  Rect get adRect => BonusConfig.adButton.shift(Offset(0, _band));

  /// The prizes in grid order (tests).
  List<int> get prizes => [for (final t in _tiles) t.prize];

  /// Tile [i] has been chosen.
  bool isOpened(int i) => _tiles[i].opened;

  /// The prize card of tile [i] is visible (never for unpopped tiles).
  bool isRevealed(int i) => _tiles[i].o >= BonusConfig.cardAt;

  /// Seconds since the current phase began.
  double get phaseTime => _t - _ph0;

  /// NO THANKS takes taps (3 s into the offer).
  bool get noThanksShown =>
      phase == BonusPhase.offer && phaseTime > BonusConfig.noThanksDelay;

  /// NEXT takes taps.
  bool get nextShown =>
      phase == BonusPhase.done && phaseTime > BonusConfig.nextDelay;

  /// Everything opened has finished its timeline.
  bool get settled =>
      _flights.isEmpty &&
      _coins.isEmpty &&
      _tiles.every((tl) => !tl.pending && (tl.o < 0 || tl.o > BonusConfig.settled));

  @override
  Future<void> onLoad() async {
    final h = game.viewHeight;
    size = Vector2(320, h);
    final (k, off) = BonusRules.layoutFor(h);
    _k = k;
    _offset = off;
    _band = BonusRules.bandShiftFor(h);
    content = PositionComponent(
      position: Vector2(off.dx, off.dy),
      scale: Vector2.all(k),
      size: Vector2(320, BonusConfig.referenceHeight),
    );
    content.addAll([
      _Painter(_paintBody, priority: 0),
      pool,
      _Painter(_paintTop, priority: 10),
    ]);
    add(content);
    try {
      _coin = await CoinIcon.load(game.images);
    } catch (_) {
      _coin = null;
    }
  }

  // --------------------------------------------------------------- input

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) {
    final p = event.localPosition;
    tapAt(Offset(p.x, p.y));
  }

  /// A tap at [s] (screen coordinates): the grid is hit-tested in the
  /// scaled column, the buttons in the bottom-anchored band (S6-63).
  void tapAt(Offset s) {
    final c = Offset((s.dx - _offset.dx) / _k, (s.dy - _offset.dy) / _k);
    final p = Offset(s.dx, s.dy - _band);
    if (phase == BonusPhase.pick) {
      for (var i = 0; i < _tiles.length; i++) {
        if (BonusRules.tileRect(i).contains(c)) {
          tapTile(i);
          return;
        }
      }
    }
    if (BonusConfig.adButton.contains(p)) {
      if (phase == BonusPhase.offer) {
        unawaited(tapOffer());
        return;
      }
    }
    if (phase == BonusPhase.done && BonusConfig.nextButton.contains(p)) {
      tapNext();
      return;
    }
    if (phase == BonusPhase.offer && p.dy > 622 && p.dy < 660) tapNoThanks();
  }

  /// §3.15 choose balloon [i]: one feather flies in; taps are ignored while
  /// a balloon opens (≈ 1.1 s). The prize is credited at once.
  bool tapTile(int i) {
    if (phase != BonusPhase.pick || _t < _busy || feathers <= 0) return false;
    if (_flights.any((f) => f.refill)) return false;
    final tl = _tiles[i];
    if (tl.opened) return false;
    final k = feathers - 1;
    feathers--;
    tl.pending = true;
    _busy = _t + BonusConfig.busy;
    pops++;
    final c = BonusRules.tileRect(i).center;
    _flights.add(
      _Flight(
        from: _bandToContent(BonusRules.rowSlot(k)),
        to: c,
        t0: _t,
        dur: BonusConfig.featherFly,
        tile: i,
      ),
    );
    game.sound.play(Sfx.colFeatherGet);
    credited += tl.prize;
    game.menu.wallet.add(tl.prize, CoinSource.bonus);
    game.services.track('bonus_pop', {'prize': tl.prize, 'pop': pops});
    return true;
  }

  /// §3.15 the ▶ feather ×3 button (once per screen).
  Future<void> tapOffer() async {
    if (phase != BonusPhase.offer) return;
    adUsed = true;
    if (offer == BonusOffer.free) {
      _refill();
      return;
    }
    phase = BonusPhase.ad;
    _ph0 = _t;
    final result = await game.showRewardedAd(AdPlacement.bonusFeathers);
    if (isRemoved || phase != BonusPhase.ad) return;
    if (result == AdResult.completed) {
      game.services.track('bonus_ad_completed');
      _refill();
    } else {
      // No reward: no extra feathers — NEXT (call).
      phase = BonusPhase.done;
      _ph0 = _t - (BonusConfig.nextDelay - BonusConfig.nextFadeIn);
    }
  }

  /// NO THANKS → straight to the results; unpopped balloons stay hidden.
  void tapNoThanks() {
    if (!noThanksShown) return;
    game.services.track('bonus_declined', {'pops': pops});
    _leave();
  }

  /// NEXT → results.
  void tapNext() {
    if (!nextShown) return;
    _leave();
  }

  void _leave() {
    if (phase == BonusPhase.leaving) return;
    phase = BonusPhase.leaving;
    _ph0 = _t;
    game.sound.play(Sfx.click);
    if (!_finished.isCompleted) _finished.complete();
  }

  void _refill() {
    phase = BonusPhase.pick;
    _ph0 = _t;
    final from = _bandToContent(BonusConfig.adButton.center);
    for (var k = 0; k < BonusConfig.feathers; k++) {
      _flights.add(
        _Flight(
          from: from,
          to: _bandToContent(BonusRules.rowSlot(k)),
          t0: _t + k * BonusConfig.refillGap,
          dur: BonusConfig.refillFly,
          n: k + 1,
          refill: true,
        ),
      );
    }
  }

  // --------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final t = _t;
    for (final f in _flights) {
      final u = (t - f.t0) / f.dur;
      if (u >= 0 && u < 1) {
        f.trail -= dt;
        if (f.trail <= 0) {
          f.trail = .03;
          final p = _flightPos(f, u);
          pool.spawn(
            x: p.dx + (_r.nextDouble() * 6 - 3),
            y: p.dy + (_r.nextDouble() * 6 - 3),
            w: 5 + _r.nextDouble() * 4,
            color: _r.nextBool() ? BonusConfig.gold : BonusConfig.pink,
            life: .35,
            fadePow: 2,
          );
        }
      }
      if (u >= 1 && !f.done) {
        f.done = true;
        final i = f.tile;
        if (i != null) {
          _tiles[i]
            ..o = 0
            ..pending = false;
          game.sound.play(Sfx.bnBalloonOpen);
          _ring(f.to, from: 4, to: 22, stroke: 2, length: .3, color: const Color(0xFFFFFFFF));
        } else {
          feathers++;
          game.sound.play(switch (f.n) {
            1 => Sfx.colFeatherSlot1,
            2 => Sfx.colFeatherSlot2,
            _ => Sfx.colFeatherSlot3,
          });
          // In the unscaled band: the ring keeps its reference size.
          _ring(f.to, from: 6 / _k, to: 28 / _k, stroke: 2.5 / _k, length: .4);
        }
      }
    }
    _flights.removeWhere((f) => f.done);
    for (var i = 0; i < _tiles.length; i++) {
      final tl = _tiles[i];
      if (tl.o < 0) continue;
      final o0 = tl.o;
      tl.o += dt;
      if (o0 < BonusConfig.popAt && tl.o >= BonusConfig.popAt) _burst(i);
      if (o0 < BonusConfig.cardAt && tl.o >= BonusConfig.cardAt) _reveal(i);
    }
    for (final c in _coins) {
      if (!c.done && t >= c.t0 + BonusConfig.coinFly) {
        c.done = true;
        shown += c.value;
        _punch = t;
        if (t - _coinSound > BonusConfig.coinSoundGap) {
          _coinSound = t;
          game.sound.play(Sfx.bnCoin);
        }
      }
    }
    _coins.removeWhere((c) => c.done);

    if (phase == BonusPhase.pick && feathers == 0 && settled) {
      offer = BonusRules.offerFor(
        adUsed: adUsed,
        noAds: game.menu.noAds,
        adAvailable: game.monetization.ads.isAvailable,
      );
      if (offer != BonusOffer.none) {
        phase = BonusPhase.offer;
        _ph0 = t;
        game.sound.play(Sfx.bnAdBtn);
        if (offer == BonusOffer.ad) game.services.track('bonus_ad_offered');
      } else {
        // §5.14 NEXT fades in ≈ 0.3 s after the last coin lands.
        phase = BonusPhase.done;
        _ph0 = t - (BonusConfig.nextDelay - BonusConfig.nextFadeIn);
      }
    }
    if (phase == BonusPhase.leaving && t - _ph0 > .6) removeFromParent();
  }

  void _ring(
    Offset at, {
    required double from,
    required double to,
    double stroke = 3,
    double length = .45,
    Color color = BonusConfig.gold,
  }) {
    content.add(
      _rings.obtain().play(
        at,
        rx: to,
        color: color,
        length: length,
        scaleFrom: from / to,
        scaleTo: 1,
        strokeFrom: stroke,
      )..priority = 5,
    );
  }

  void _confetti(Offset at, int n) {
    const cols = [
      BonusConfig.pink,
      BonusConfig.gold,
      BonusConfig.soft,
      BonusConfig.lightPink,
    ];
    for (var i = 0; i < n; i++) {
      final a = -math.pi * (.08 + .84 * _r.nextDouble());
      final v = 120 + _r.nextDouble() * 220;
      pool.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 4 + _r.nextDouble() * 5,
        color: cols[i % 4],
        life: .5 + _r.nextDouble() * .5,
        gravity: 620,
        drag: 1.8,
        spin: (_r.nextDouble() * 2 - 1) * 10,
        fadePow: 2,
      );
    }
  }

  /// §5.14 the pop at 0.32 s: white flash, 11 pink / dark-pink scraps.
  void _burst(int i) {
    final c = BonusRules.tileRect(i).center + const Offset(0, -10);
    content.add(_flashes.obtain().play(c, _popFlash)..priority = 5);
    for (var k = 0; k < BonusConfig.scraps; k++) {
      final a = _r.nextDouble() * math.pi * 2;
      final v = 120 + _r.nextDouble() * 120;
      final s = 4 + _r.nextDouble() * 4;
      pool.spawn(
        shape: ParticleShape.triangle,
        x: c.dx,
        y: c.dy,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 2 * s,
        h: 1.6 * s,
        color: k % 3 == 0 ? BonusConfig.darkPink : BonusConfig.pink,
        life: .55,
        gravity: 300,
        damp: 1.8,
        spin: (_r.nextDouble() * 2 - 1) * 12,
        fadePow: 2,
      );
    }
  }

  /// §5.14 the prize card at 0.6 s: sound by amount, ring, confetti, the
  /// coins into the pill; the jackpot: bigger ring and confetti, the gold
  /// screen flash and the big fanfare.
  void _reveal(int i) {
    final c = BonusRules.tileRect(i).center;
    final p = _tiles[i].prize;
    final big = p == BonusConfig.jackpot;
    game.sound.play(
      big ? Sfx.bnPrizeBig : (p >= 75 ? Sfx.bnPrizeM : Sfx.bnPrizeS),
    );
    _ring(
      c,
      from: 20,
      to: big ? 120 : 56,
      stroke: big ? 5 : 3,
      length: big ? .7 : .45,
    );
    _confetti(c, big ? BonusConfig.jackpotConfetti : BonusConfig.confetti);
    if (big) _flash = _t;
    final split = BonusRules.coinSplit(p);
    for (var k = 0; k < split.length; k++) {
      _coins.add(
        _Coin(c, _t + BonusConfig.coinDelay + k * BonusConfig.coinGap, split[k]),
      );
    }
  }

  Offset _flightPos(_Flight f, double u) {
    final e = Ease.cubicInOut(u.clamp(0.0, 1.0)), w = 1 - e;
    final c = Offset(
      (f.from.dx + f.to.dx) / 2 + (f.refill ? 0 : -40),
      math.min(f.from.dy, f.to.dy) - 50,
    );
    return Offset(
      w * w * f.from.dx + 2 * w * e * c.dx + e * e * f.to.dx,
      w * w * f.from.dy + 2 * w * e * c.dy + e * e * f.to.dy,
    );
  }

  // --------------------------------------------------------------- paint

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // PRD-2.2 §31.1: always the approved grey, whatever stage the run ended on.
  Color get _fg => kPostRunPalette.foreground;
  Color get _bg => kPostRunPalette.background;
  Color _mix(double p) => Color.lerp(_bg, _fg, p)!;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), _fill..color = _bg);
  }

  void _text(
    Canvas canvas,
    String s,
    Offset centre,
    double size,
    Color color, {
    double spacing = 0,
    bool right = false,
  }) {
    final tp = CollectText.of(s, size, color, spacing: spacing);
    final w = tp.width - spacing;
    final x = right ? centre.dx - w : centre.dx - w / 2;
    tp.paint(canvas, Offset(x, centre.dy - tp.height / 2));
  }

  static const Map<int, List<Offset>> _heaps = {
    25: [Offset.zero],
    50: [Offset(-7, 3), Offset(7, -3)],
    75: [Offset(-9, 5), Offset(9, 5), Offset(0, -6)],
    100: [Offset(-10, 6), Offset(10, 6), Offset(0, 6), Offset(-5, -5), Offset(5, -5)],
    150: [
      Offset(-12, 7), Offset(0, 7), Offset(12, 7), //
      Offset(-6, -3), Offset(6, -3), Offset(0, -12),
    ],
    250: [
      Offset(-16, 9), Offset(-5, 9), Offset(6, 9), Offset(17, 9), //
      Offset(-11, -1), Offset(0, -1), Offset(11, -1), //
      Offset(-5, -11), Offset(6, -11), Offset(0, -20),
    ],
  };

  /// §5.14 a coin heap that grows with the amount (1 coin at 25 … 10 at
  /// 250), drawn with the shared coin sprite (master #14).
  void _heap(Canvas canvas, int amount, Offset at, double scale) {
    final coin = _coin;
    if (coin == null) return;
    final pts = _heaps[amount] ?? _heaps[25]!;
    final r = amount >= BonusConfig.jackpot ? 7.5 : 8.5;
    for (final p in pts) {
      CoinIcon.paint(canvas, coin, at + p * scale, 2 * r * scale);
    }
  }

  void _paintBody(Canvas canvas) {
    final t = _t;
    // --- total pill
    final pu = t - _punch;
    final ps = pu < BonusConfig.pillPunchLength
        ? 1 + BonusConfig.pillPunch * math.sin(math.pi * pu / BonusConfig.pillPunchLength)
        : 1.0;
    final pc = BonusConfig.pill.center;
    canvas.save();
    canvas.translate(pc.dx, pc.dy);
    canvas.scale(ps);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: BonusConfig.pill.width, height: BonusConfig.pill.height),
      _fill..color = const Color(0xFFFFFFFF),
    );
    _text(canvas, '$shown', const Offset(18, 2), BonusConfig.pillFont, BonusConfig.plum, right: true);
    final coin = _coin;
    if (coin != null) {
      CoinIcon.paint(canvas, coin, Offset(BonusConfig.pillCoin.dx - pc.dx, 0), BonusConfig.pillCoinSize);
    }
    canvas.restore();

    // --- hero: wings, circle with rays and the coin heap, sparkles
    const hero = BonusConfig.hero;
    final flap = .1 * math.sin(t * 2 * math.pi * BonusConfig.wingHz);
    for (final s in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(hero.dx + s * 36, hero.dy);
      canvas.scale(s, 1);
      for (final (fx, fy, r) in const [(16.0, 12.0, 1.5), (14.0, 2.0, 1.05), (8.0, -8.0, .6)]) {
        FeatherArt.paintAt(canvas, Offset(fx, fy), 1.15, r + flap * (1 + r), outline: 1.5);
      }
      canvas.restore();
    }
    canvas.save();
    canvas.translate(hero.dx, hero.dy);
    canvas.drawCircle(Offset.zero, BonusConfig.heroRadius, _fill..color = const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: BonusConfig.heroRadius)));
    canvas.rotate(t * BonusConfig.heroRayOmega);
    _fill.color = const Color(0x4DFFB529);
    final ray = Path()
      ..moveTo(0, 0)
      ..lineTo(-10, -50)
      ..lineTo(10, -50)
      ..close();
    for (var i = 0; i < 8; i++) {
      canvas.rotate(math.pi / 4);
      canvas.drawPath(ray, _fill);
    }
    canvas.restore();
    canvas.drawCircle(
      Offset.zero,
      BonusConfig.heroRadius,
      _stroke
        ..color = BonusConfig.gold
        ..strokeWidth = BonusConfig.heroRim,
    );
    _heap(canvas, BonusConfig.jackpot, const Offset(0, 4), 1.15);
    canvas.restore();

    // --- banner
    final bs = 1 + BonusConfig.bannerPulse * math.sin(t * 2 * math.pi * BonusConfig.bannerHz);
    const by = BonusConfig.bannerTop + BonusConfig.bannerHeight / 2;
    canvas.save();
    canvas.translate(160, by);
    canvas.scale(bs);
    canvas.translate(-160, -by);
    final label = CollectText.of(
      BonusConfig.bannerText,
      BonusConfig.bannerFont,
      BonusConfig.plum,
      spacing: BonusConfig.bannerSpacing,
    );
    final hw = math.max(BonusConfig.bannerMinHalf, label.width / 2 + 16);
    const top = BonusConfig.bannerTop, bot = top + BonusConfig.bannerHeight + 2;
    _fill.color = BonusConfig.goldDark;
    canvas.drawPath(
      Path()
        ..moveTo(160 - hw - 12, top + 4)
        ..lineTo(160 - hw + 6, top + 4)
        ..lineTo(160 - hw + 6, bot)
        ..lineTo(160 - hw - 12, bot)
        ..lineTo(160 - hw - 5, (top + 4 + bot) / 2)
        ..close(),
      _fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(160 + hw + 12, top + 4)
        ..lineTo(160 + hw - 6, top + 4)
        ..lineTo(160 + hw - 6, bot)
        ..lineTo(160 + hw + 12, bot)
        ..lineTo(160 + hw + 5, (top + 4 + bot) / 2)
        ..close(),
      _fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(160 - hw, top, 2 * hw, BonusConfig.bannerHeight),
      _fill..color = BonusConfig.gold,
    );
    _text(canvas, BonusConfig.bannerText, const Offset(160, top + 13), BonusConfig.bannerFont, BonusConfig.plum,
        spacing: BonusConfig.bannerSpacing);
    canvas.restore();
    for (var i = 0; i < 4; i++) {
      final ph = (t * .9 + i * .25) % 1;
      final a = i * 1.7 + (t * .9 + i * .25).floorToDouble() * 2.3;
      Twinkle.paint(
        canvas,
        Offset(hero.dx + math.cos(a) * 50, hero.dy + math.sin(a) * 50),
        14 * math.sin(math.pi * ph),
        i.isOdd ? const Color(0xFFFFFFFF) : BonusConfig.paleGold,
        rotation: ph * 2,
        waist: Twinkle.pickupWaist,
      );
    }

    // --- grid
    canvas.drawRect(BonusConfig.panel, _fill..color = _mix(BonusConfig.panelMix));
    for (var i = 0; i < _tiles.length; i++) {
      final tl = _tiles[i];
      final r = BonusRules.tileRect(i);
      canvas.drawRect(r, _fill..color = _mix(BonusConfig.tileMix));
      final o = tl.o;
      if (o < BonusConfig.balloonGone) {
        _balloon(canvas, r.center, o, t + i * .37);
      }
      if (o >= BonusConfig.cardAt) {
        _prizeCard(
          canvas,
          i,
          ((o - BonusConfig.cardAt) / BonusConfig.cardFade).clamp(0.0, 1.0),
          Ease.outBack(((o - BonusConfig.cardAt) / BonusConfig.cardPop).clamp(0.0, 1.0)),
        );
      }
    }

    // --- prompt, feather row, offer, NEXT
    final prompt = switch (phase) {
      BonusPhase.pick when feathers > 0 => BonusConfig.promptPick,
      BonusPhase.offer || BonusPhase.ad => BonusConfig.promptMore,
      _ => '',
    };
    if (prompt.isNotEmpty) {
      _text(canvas, prompt, const Offset(160, BonusConfig.promptY), BonusConfig.promptFont, BonusConfig.plum,
          spacing: BonusConfig.promptSpacing);
    }
    // §3.0.1 (S6-63) the bottom band: unscaled, bottom-anchored.
    canvas.save();
    canvas.scale(1 / _k);
    canvas.translate(-_offset.dx, _band - _offset.dy);
    if (phase == BonusPhase.pick) {
      for (var s = 0; s < 3; s++) {
        final has = s < feathers;
        FeatherArt.paintAt(
          canvas,
          BonusRules.rowSlot(s),
          BonusConfig.rowScale * (has ? 1 + .04 * math.sin(t * 3 + s) : 1),
          BonusConfig.rowTilt,
          ghost: has ? null : _mix(BonusConfig.ghostMix),
          outline: 1.6,
        );
      }
    }
    if (phase == BonusPhase.offer || phase == BonusPhase.ad) _offerButton(canvas, t);
    if (phase == BonusPhase.done || phase == BonusPhase.leaving) {
      final a = phase == BonusPhase.leaving
          ? 1.0
          : ((phaseTime - BonusConfig.nextDelay + BonusConfig.nextFadeIn) / BonusConfig.nextFadeIn).clamp(0.0, 1.0);
      if (a > 0) {
        canvas.drawRect(BonusConfig.nextButton, _fill..color = BonusConfig.pink.withValues(alpha: a));
        _text(
          canvas,
          'NEXT',
          BonusConfig.nextButton.center + const Offset(0, 1),
          BonusConfig.nextFont,
          BonusConfig.soft.withValues(alpha: a),
          spacing: BonusConfig.nextSpacing,
        );
      }
    }
    canvas.restore();
  }

  void _offerButton(Canvas canvas, double t) {
    final u = phaseTime;
    final s = Ease.outBack((u / BonusConfig.adPop).clamp(0.0, 1.0)) *
        (1 + BonusConfig.adPulse * math.sin(t * 2 * math.pi * BonusConfig.adHz));
    const b = BonusConfig.adButton;
    canvas.save();
    canvas.translate(b.center.dx, b.center.dy);
    canvas.scale(s);
    final box = Rect.fromCenter(center: Offset.zero, width: b.width, height: b.height);
    canvas.drawRect(box, _fill..color = BonusConfig.gold);
    canvas.save();
    canvas.clipRect(box);
    final sx = ((u % BonusConfig.shineEvery) / BonusConfig.shineEvery) * 360 - 180;
    canvas.drawPath(
      Path()
        ..moveTo(sx - 14, -30)
        ..lineTo(sx + 6, -30)
        ..lineTo(sx - 14, 30)
        ..lineTo(sx - 34, 30)
        ..close(),
      _fill..color = const Color(0x59FFFFFF),
    );
    canvas.restore();
    final video = offer != BonusOffer.free;
    final dx = video ? 0.0 : -16.0;
    if (video) {
      _fill.color = BonusConfig.plum;
      canvas.drawRect(const Rect.fromLTWH(-72, -9, 20, 18), _fill);
      canvas.drawPath(
        Path()
          ..moveTo(-52, 0)
          ..lineTo(-43, -8)
          ..lineTo(-43, 8)
          ..close(),
        _fill,
      );
    }
    FeatherArt.paintAt(canvas, Offset(-8 + dx, 0), .95, BonusConfig.rowTilt, outline: 1.5);
    final x3 = CollectText.of('×3', 30, BonusConfig.plum);
    x3.paint(canvas, Offset(18 + dx, 2 - x3.height / 2));
    canvas.restore();
    if (phase == BonusPhase.offer && u > BonusConfig.noThanksDelay) {
      final a = ((u - BonusConfig.noThanksDelay) / BonusConfig.noThanksFade).clamp(0.0, 1.0) * BonusConfig.noThanksAlpha;
      _text(
        canvas,
        BonusConfig.noThanksText,
        const Offset(160, BonusConfig.noThanksY),
        BonusConfig.promptFont,
        _fg.withValues(alpha: a),
        spacing: BonusConfig.promptSpacing,
      );
    }
  }

  static final Path _string = Path()
    ..moveTo(0, 20)
    ..quadraticBezierTo(-5, 27, 0, 32)
    ..quadraticBezierTo(5, 37, 0, 42);
  static final Path _knot = Path()
    ..moveTo(-4, 28)
    ..lineTo(4, 28)
    ..lineTo(0, 23)
    ..close();

  /// §5.14 balloon: pink 42 × 50 with a white 55 % highlight, dark-pink
  /// knot and a wavy gold string; idle bob ±2.5 and sway ±4°; stretches
  /// with a jitter until the pop, then the string drops and fades.
  void _balloon(Canvas canvas, Offset c, double o, double ti) {
    final sw = math.sin(ti * 1.7) * .07, bob = math.sin(ti * 2.2) * 2.5;
    canvas.save();
    canvas.translate(c.dx, c.dy + bob - 2);
    _stroke
      ..color = BonusConfig.gold
      ..strokeWidth = 1.6;
    if (o < BonusConfig.popAt) {
      canvas.rotate(sw);
      var s = 1.0;
      if (o >= 0) {
        s = 1 + BonusConfig.stretch * (o / BonusConfig.popAt) + math.sin(o * 90) * .025;
      }
      canvas.save();
      canvas.translate(0, -8);
      canvas.scale(s);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 42, height: 50),
        _fill..color = BonusConfig.pink,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(-8, -10), width: 9, height: 16),
        _fill..color = const Color(0x8CFFFFFF),
      );
      canvas.drawPath(_knot, _fill..color = BonusConfig.darkPink);
      canvas.restore();
      canvas.drawPath(_string, _stroke);
    } else {
      final u = o - BonusConfig.popAt;
      final a = (1 - u / BonusConfig.stringFade).clamp(0.0, 1.0);
      if (a > 0) {
        canvas.translate(0, 300 * u * u);
        _stroke.color = BonusConfig.gold.withValues(alpha: a);
        canvas.drawPath(_string, _stroke);
      }
    }
    canvas.restore();
  }

  void _prizeCard(Canvas canvas, int i, double a, double s) {
    if (a <= 0) return;
    final p = _tiles[i].prize;
    final big = p == BonusConfig.jackpot;
    final r = BonusRules.tileRect(i);
    const ts = BonusConfig.tile;
    canvas.saveLayer(null, layerPaint(a));
    canvas.translate(r.center.dx, r.center.dy);
    canvas.scale(s);
    final box = Rect.fromCenter(center: Offset.zero, width: ts, height: ts);
    canvas.drawRect(box, _fill..color = big ? BonusConfig.gold : const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipRect(box);
    canvas.rotate(_t * .6);
    _fill.color = big ? const Color(0x80FFFFFF) : const Color(0x38FFB529);
    final ray = Path()
      ..moveTo(0, 0)
      ..lineTo(-9, -70)
      ..lineTo(9, -70)
      ..close();
    for (var k = 0; k < 10; k++) {
      canvas.rotate(math.pi / 5);
      canvas.drawPath(ray, _fill);
    }
    canvas.restore();
    _heap(canvas, p, const Offset(0, -8), big ? 1.05 : 1);
    _text(canvas, '$p', const Offset(0, 30), 22, BonusConfig.plum);
    canvas.restore();
  }

  void _paintTop(Canvas canvas) {
    final t = _t;
    for (final f in _flights) {
      final u = (t - f.t0) / f.dur;
      if (u < 0) continue;
      final p = _flightPos(f, u);
      final e = Ease.cubicInOut(u.clamp(0.0, 1.0));
      // The row lives in the unscaled band (S6-63): a feather keeps the
      // row's size there and shrinks to the column's scale at a tile.
      final band = 1 / _k;
      final s = BonusConfig.rowScale *
          (f.refill
              ? (.7 + .3 * e) * band
              : (1 + .25 * math.sin(math.pi * e)) * (band + (1 - band) * e));
      FeatherArt.paintAt(
        canvas,
        p,
        s,
        BonusConfig.rowTilt + (f.refill ? 0 : e * .6),
        outline: 1.6,
      );
    }
    final coin = _coin;
    if (coin != null) {
      const to = BonusConfig.pillCoin;
      for (final c in _coins) {
        final u = (t - c.t0) / BonusConfig.coinFly;
        if (u < 0) continue;
        final e = u * u, w = 1 - e;
        final cx = (c.from.dx + to.dx) / 2 + 30;
        final cy = math.min(c.from.dy, to.dy) - 30;
        final p = Offset(
          w * w * c.from.dx + 2 * w * e * cx + e * e * to.dx,
          w * w * c.from.dy + 2 * w * e * cy + e * e * to.dy,
        );
        CoinIcon.paint(canvas, coin, p, 2 * (9 - 2 * e));
      }
    }
    final fu = (t - _flash) / BonusConfig.flashLength;
    if (fu >= 0 && fu < 1) {
      canvas.drawRect(
        const Rect.fromLTWH(-400, -400, 1120, 1600),
        _fill..color = BonusConfig.gold.withValues(alpha: (1 - fu) * BonusConfig.flashAlpha),
      );
    }
  }
}

/// A child that paints through a callback (keeps the screen's z-order:
/// body, particles, rings, flights).
class _Painter extends Component {
  _Painter(this._paint, {super.priority});
  final void Function(Canvas) _paint;

  @override
  void render(Canvas canvas) => _paint(canvas);
}
