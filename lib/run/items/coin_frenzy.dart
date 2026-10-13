import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../config/capsule_config.dart';
import '../config/run_config.dart';
import '../effects/coin_icon.dart';
import '../effects/coin_popup.dart';
import '../effects/particle_pool.dart';
import '../effects/screen_edge_glow.dart';
import '../hoops/hoop.dart';
import '../hoops/hoop_kind.dart';
import '../hoops/ring_painter.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_state.dart';
import 'timed_powerup.dart';

/// Coin Frenzy (PRD-2 §3.32, §5.31): for 6 s every ring not yet passed is a
/// **coin ring**, and each ring passed pays **+5 coins on top of the normal
/// ring coins** (`coins_earned` source `frenzy`, Q72), with a "+5" popup
/// (master #8), five coins bursting up from the ring and the coin cascade.
///
/// Coin rings: the rings on screen that are not resolved yet when it
/// starts, and every ring spawned while it runs, draw gold (`#FFD54A`
/// front, `#D48A00` back, 8 pt; master #3's colour / stroke parameters,
/// swapped in only while painting so the streak tier and Big Hoops looks
/// underneath stay intact) with 10 coins (master #14) orbiting the rim.
/// Special rings with their own look (saw, switch, FEVER, pair, spring)
/// keep their colours and get only the orbiting coins; the portal gets
/// neither. A 10 pt gold border pulses round the screen and gold sparkles
/// drift across; the jackpot run on start and a short falling tone at the
/// end.
///
/// A portal ride pauses it: no coin rings, border or +5 during the ride.
class CoinFrenzyFeature extends TimedPowerupEffect {
  @override
  TimedPowerup get type => TimedPowerup.frenzy;

  static final Expando<bool> _marked = Expando('frenzyRing');
  static final Expando<bool> _wrapped = Expando('frenzyWrapped');

  /// [h] turned into a coin ring by this powerup.
  static bool isCoinRing(Hoop h) => _marked[h] ?? false;

  ScreenEdgeGlow? border;
  FrenzyCoinShower? shower;
  final EffectPool<CoinPopup> _popups = CoinPopup.newPool();

  /// Rings paid +5 this powerup (tests).
  int paid = 0;

  double _sparkAcc = 0;
  double _t = 0;

  /// Coin rings are drawn now.
  bool get showing => on;

  @override
  void attach(RunContext c) {
    super.attach(c);
    c.events
      ..on<HoopSpawned>(_onSpawned)
      ..on<HoopPassed>(_onPassed);
  }

  @override
  void onStart() {
    final ctx = c!;
    paid = 0;
    _sparkAcc = 0;
    ctx.sfx(Sfx.frenzyStart);
    for (final h in ctx.run.spawner.hoops) {
      if (!h.resolved) _mark(h);
    }
    _showBorder();
  }

  void _showBorder() {
    final ctx = c;
    if (ctx == null) return;
    final b = border;
    if (b != null && !b.isRemoved && !b.isRemoving) return;
    border =
        ScreenEdgeGlow.coinFrenzy(Vector2(Config.worldWidth, ctx.viewHeight))
          ..priority = CapsuleConfig.glowPriority
          ..edgeWidth = CapsuleConfig.frenzyBorder;
    ctx.game.world.add(border!);
  }

  void _hideBorder() {
    border?.removeFromParent();
    border = null;
  }

  void _onSpawned(HoopSpawned e) {
    if (on) _mark(e.hoop);
  }

  /// Turns [h] into a coin ring (painters wrapped once per hoop).
  void _mark(Hoop h) {
    if (h.kind.id == HoopKindId.portal) return;
    _marked[h] = true;
    if (_wrapped[h] ?? false) return;
    _wrapped[h] = true;
    final gold = h.kind.usesTierLook;
    final back = h.paintBack;
    h.paintBack = (canvas) {
      if (!_live(h)) {
        back?.call(canvas);
        return;
      }
      _withGold(h, gold, () => back?.call(canvas));
      _paintCoins(canvas, h, front: false);
    };
    final front = h.front.paintFront;
    h.front.paintFront = (canvas) {
      if (!_live(h)) {
        front?.call(canvas);
        return;
      }
      _withGold(h, gold, () => front?.call(canvas));
      _paintCoins(canvas, h, front: true);
    };
  }

  bool _live(Hoop h) => showing && isCoinRing(h) && !h.look.missed;

  static const RingColors _gold = RingColors(
    CapsuleConfig.frenzyRingFront,
    CapsuleConfig.frenzyRingBack,
  );

  void _withGold(Hoop h, bool gold, void Function() paint) {
    if (!gold) {
      paint();
      return;
    }
    final look = h.look;
    final colors = look.colors, stroke = look.strokeWidth;
    look
      ..colors = _gold
      ..strokeWidth = CapsuleConfig.frenzyRingStroke;
    try {
      paint();
    } finally {
      look
        ..colors = colors
        ..strokeWidth = stroke;
    }
  }

  final Paint _coinPaint = Paint()..filterQuality = FilterQuality.medium;

  /// §5.31 10 coins orbiting each ring's rim; the ones on the left (front)
  /// half are drawn over the bird.
  void _paintCoins(Canvas canvas, Hoop h, {required bool front}) {
    final ctx = c;
    if (ctx == null) return;
    final image = _coinImage();
    if (image == null) return;
    final ry = RingPainter.ryFor(h.opening);
    const rx = RingPainter.rx;
    const n = CapsuleConfig.orbitCoins;
    for (final o in h.rings) {
      for (var i = 0; i < n; i++) {
        final a = 2 * math.pi * ((i / n + _t * CapsuleConfig.orbitSpeed) % 1);
        final x = rx * math.cos(a);
        if ((x < 0) != front) continue;
        final y = o + ry * math.sin(a);
        final spin = math.cos(_t * 6 + i).abs().clamp(.15, 1.0);
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(spin, 1);
        _coinPaint.color = const Color(0xFFFFFFFF);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromCircle(
            center: Offset.zero,
            radius: CapsuleConfig.orbitCoinSize / 2,
          ),
          _coinPaint,
        );
        canvas.restore();
      }
    }
  }

  Image? _coinImage() {
    final images = c?.game.images;
    if (images == null || !images.containsKey(CoinIcon.asset)) return null;
    return images.fromCache(CoinIcon.asset);
  }

  void _onPassed(HoopPassed e) {
    final ctx = c;
    if (ctx == null || !on || e.duringRide) return;
    ctx.earn(CapsuleConfig.frenzyCoins, CoinSource.frenzy);
    paid++;
    ctx.sfx(Sfx.frenzyRing);
    final hoop = e.hoop;
    Vector2 at;
    if (hoop != null) {
      final ring = e.ring.clamp(0, hoop.rings.length - 1);
      at = hoop.frame().toWorld(Vector2(0, hoop.rings[ring]));
    } else {
      at =
          ctx.run.birdTrackPosition() ??
          Vector2(ctx.s.camX + RunConfig.birdX, ctx.viewHeight / 2);
    }
    final shift = CapsuleConfig.frenzyPopupShift;
    ctx.layers.fx.add(
      _popups.obtain()..play(
        Offset(at.x + shift.dx, at.y + shift.dy),
        CapsuleConfig.frenzyCoins,
        delay: CapsuleConfig.frenzyPopupDelay,
      ),
    );
    var s = shower;
    if (s == null || s.isRemoved || s.isRemoving) {
      shower = s = FrenzyCoinShower(this);
      ctx.layers.fx.add(s);
    }
    final bird = ctx.run.birdTrackPosition();
    s.burst(at.x, bird?.y ?? at.y);
  }

  @override
  void onPause() => _hideBorder();

  @override
  void onResume() {
    _showBorder();
    final ctx = c;
    if (ctx == null) return;
    for (final h in ctx.run.spawner.hoops) {
      if (!h.resolved) _mark(h);
    }
  }

  @override
  void onEnd({required bool death}) {
    if (!death) c?.sfx(Sfx.frenzyEnd);
    _hideBorder();
  }

  @override
  void step(double gameDt, double realDt) {
    final ctx = c;
    if (ctx == null) return;
    _t += realDt;
    if (!on) return;
    // §5.31 gold sparkles drifting across the screen.
    _sparkAcc += realDt * CapsuleConfig.sparkleRate;
    final r = ctx.cosmetic;
    final h = ctx.viewHeight;
    while (_sparkAcc >= 1) {
      _sparkAcc -= 1;
      ctx.run.particles.spawn(
        shape: ParticleShape.twinkle,
        x: ctx.s.camX + r.nextDouble() * Config.worldWidth,
        y:
            h *
            (CapsuleConfig.sparkleTop +
                r.nextDouble() *
                    (CapsuleConfig.sparkleBottom - CapsuleConfig.sparkleTop)),
        vx: ctx.s.forwardSpeed + CapsuleConfig.sparkleVx,
        vy: CapsuleConfig.sparkleVy,
        w: CapsuleConfig.sparkleSize,
        color: CapsuleConfig.sparkle,
        life: CapsuleConfig.sparkleLife,
      );
    }
  }

  @override
  void reset() {
    _hideBorder();
    shower?.removeFromParent();
    shower = null;
  }

  @override
  void detach() {
    final ctx = c;
    if (ctx != null) {
      ctx.events
        ..off<HoopSpawned>(_onSpawned)
        ..off<HoopPassed>(_onPassed);
    }
    super.detach();
  }
}

/// §5.31 the coins bursting up from a ring on every coin-ring pass: 5
/// coins (master #14, 14 pt) thrown up within ±0.7 rad at 180–300 pt/s,
/// falling at 600 pt/s², spinning, fading (1 − u²) over 0.9 s. Track
/// coordinates (`RunTrack.fx`).
class FrenzyCoinShower extends Component {
  FrenzyCoinShower(this.owner);

  final CoinFrenzyFeature owner;
  final List<FrenzyCoin> coins = [];

  void burst(double x, double y) {
    final r = owner.c?.cosmetic ?? math.Random();
    for (var i = 0; i < CapsuleConfig.showerCoins; i++) {
      final a =
          -math.pi / 2 + (r.nextDouble() - .5) * CapsuleConfig.showerSpread;
      final v =
          CapsuleConfig.showerSpeed +
          r.nextDouble() * CapsuleConfig.showerSpeedRandom;
      // The ring scrolls with the world; the coins burst from it.
      coins.add(FrenzyCoin(x, y, math.cos(a) * v, math.sin(a) * v));
    }
  }

  @override
  void update(double dt) {
    for (final k in coins) {
      k
        ..t += dt
        ..x += k.vx * dt
        ..y += k.vy * dt
        ..vy += CapsuleConfig.showerGravity * dt;
    }
    coins.removeWhere((k) => k.t >= CapsuleConfig.showerLife);
  }

  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void render(Canvas canvas) {
    if (coins.isEmpty) return;
    final image = owner._coinImage();
    if (image == null) return;
    for (final k in coins) {
      final u = (k.t / CapsuleConfig.showerLife).clamp(0.0, 1.0);
      final a = 1 - u * u;
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(k.x, k.y);
      canvas.scale(math.cos(k.t * 12).abs().clamp(.15, 1.0), 1);
      _paint.color = Color.fromRGBO(255, 255, 255, a);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCircle(
          center: Offset.zero,
          radius: CapsuleConfig.showerCoinSize / 2,
        ),
        _paint,
      );
      canvas.restore();
    }
  }
}

/// One coin of a [FrenzyCoinShower] (track coordinates).
class FrenzyCoin {
  FrenzyCoin(this.x, this.y, this.vx, this.vy);
  double x, y, vx, vy;
  double t = 0;
}
