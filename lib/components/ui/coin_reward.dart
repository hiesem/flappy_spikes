import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../menu/free_coins_policy.dart';
import '../../services/iap_service.dart';
import '../home/home_screen.dart' show CoinPill;
import '../home/menu_primitives.dart';
import 'coin_fly.dart';
import 'confetti.dart';
import 'live_effects.dart' show WiggleEffect;

/// How the coins leave the source box.
enum _Flight {
  /// PRD-menu-v2 GET flight ([CoinFly] default constructor).
  button,

  /// PRD-home-v3 §5 burst ([CoinFly.burst]).
  burst,
}

/// The standard "coins added" feedback (PRD-home-v3 §5, Q-S9 answered):
/// coins fly from a source box into the coin pill's coin; from the first
/// landing the pill counts up (ease-out cubic) with `sk_tick` ticks while
/// it glows gold; at the end the pill pops (114 %), its coin spins and pops
/// (150 %), confetti bursts from the pill, "+amount" floats up under it, an
/// optional jingle and white flash, then `sk_progress` and [onDone].
///
/// Presets: [CoinRewardAnimation.pack], [CoinRewardAnimation.levelReward],
/// [CoinRewardAnimation.noAdsBonus] and [CoinRewardAnimation.freeCoins]
/// (the unchanged PRD-menu-v2 GET reward: coins first, then a 0.4 s
/// linear count with one `bn_coin`).
///
/// Started through [FlappySpikesGame.playCoinReward], which [prepare]s it
/// with the shared pill (held, so a wallet credited before or after the
/// start keeps its old number until the coins land). Lives in the world,
/// so a screen change mid-flight never strands the pill; removed early,
/// it still releases the pill and calls [onDone].
///
/// Reduce motion: no confetti and no flash; the fly and count-up stay.
/// Pitch: the mocks raise the pitch of each landing / tick; the
/// low-latency `AudioPool`s expose no playback rate, so all play at
/// normal pitch.
class CoinRewardAnimation extends Component
    with HasGameReference<FlappySpikesGame> {
  CoinRewardAnimation({
    required this.amount,
    required this.from,
    required this.coins,
    this.flyDuration = 0.7,
    this.stagger = 0.055,
    required this.countDuration,
    required this.ticks,
    this.confetti = 0,
    this.confettiSpeed = 220,
    this.confettiDriftX = -70,
    this.confettiStars = false,
    this.jingle,
    this.flash = false,
    this.progressDelay = 0.7,
    this.originDy = 0,
    this.originCentre = false,
    this.spreadX = 16,
    this.jitterY = (min: 0, max: 0),
    this.midSpreadX = 90,
    this.rise = (min: 40, range: 50),
    this.onDone,
    this.random,
    this.reservation,
    super.priority = 1000,
  }) : _flight = _Flight.burst;

  /// A coin pack (PRD-menu-v4 §2, PRD-home-v3 §5 table): 1 000 / 10 000 /
  /// 17 000 / 100 000 -> 6 / 9 / 12 / 16 coins, 0.9 / 1.2 / 1.5 / 1.9 s
  /// count, 40 / 70 / 100 / 150 confetti, `sk_buy_common` / `rare` /
  /// `epic` / `legendary`; 100 000 adds the white flash. [from] = the top
  /// of the pack art's heap (coins burst out of its top centre).
  factory CoinRewardAnimation.pack(
    IapProduct product, {
    required Rect from,
    void Function()? onDone,
    math.Random? random,
  }) {
    final (coins, count, confetti, jingle) = switch (product) {
      IapProduct.coins1000 => (6, 0.9, 40, Sfx.skBuyCommon),
      IapProduct.coins10000 ||
      IapProduct.giftCoins10000 => (9, 1.2, 70, Sfx.skBuyRare),
      IapProduct.coins17000 => (12, 1.5, 100, Sfx.skBuyEpic),
      IapProduct.coins100000 => (16, 1.9, 150, Sfx.skBuyLegendary),
      IapProduct.noAds || IapProduct.giftNoAdsCoins10000 => throw ArgumentError(
        'No ads is not a coin pack',
      ),
    };
    final big = product.coins >= 17000;
    return CoinRewardAnimation(
      amount: product.coins,
      from: from,
      coins: coins,
      countDuration: count,
      ticks: math.min(24, 8 + coins),
      confetti: confetti,
      confettiSpeed: big ? 300 : 220,
      confettiStars: big,
      jingle: jingle,
      flash: product == IapProduct.coins100000,
      progressDelay: 0.7,
      originCentre: true,
      spreadX: 16,
      jitterY: (min: -4, max: 16),
      midSpreadX: 90,
      rise: (min: 40, range: 50),
      onDone: onDone,
      random: random,
    );
  }

  /// The LEVEL UP reward (§4.3, build74 `claim`): min(14, 5 + 2 lg amount)
  /// coins from the CLAIM button's top centre (+10), a 0.8 + 0.3 lg amount
  /// s count with 16 ticks, 40 confetti. [from] null = screen centre
  /// (the ✕ close also claims).
  factory CoinRewardAnimation.levelReward(
    int amount,
    int level, {
    Rect? from,
    void Function()? onDone,
    math.Random? random,
  }) {
    final lg = math.log(math.max(amount, 1)) / math.ln10;
    return CoinRewardAnimation(
      amount: amount,
      from: from ?? const Rect.fromLTWH(160, 390, 0, 0),
      coins: math.min(14, 5 + (lg * 2).round()),
      countDuration: .8 + lg * .3,
      ticks: 16,
      confetti: 40,
      progressDelay: 0.6,
      originCentre: true,
      originDy: 10,
      spreadX: 60,
      midSpreadX: 80,
      rise: (min: 50, range: 40),
      onDone: onDone,
      random: random,
    )..level = level;
  }

  /// The No-ads +1 000 bonus (§7, build79 `coinReward`): 12 coins from the
  /// CLAIM button's top centre (+8), 0.75 s each, a 1.4 s count with 18
  /// ticks, 50 confetti with stars. The bonus was credited (and reserved
  /// on the pill) at purchase: [reservation] is what this count takes over
  /// (0 for the debug preview, which credits nothing).
  ///
  /// PRD-2.3 §22.2: the gift popup's CLAIM uses it too, with the gift's
  /// coins as [amount].
  factory CoinRewardAnimation.noAdsBonus({
    required Rect from,
    int amount = kNoAdsBonusCoins,
    int reservation = kNoAdsBonusCoins,
    void Function()? onDone,
    math.Random? random,
  }) => CoinRewardAnimation(
    amount: amount,
    from: from,
    coins: 12,
    flyDuration: 0.75,
    countDuration: 1.4,
    ticks: 18,
    confetti: 50,
    confettiSpeed: 300,
    confettiDriftX: 0,
    confettiStars: true,
    progressDelay: 0.65,
    originCentre: true,
    originDy: 8,
    spreadX: 70,
    midSpreadX: 80,
    rise: (min: 60, range: 50),
    onDone: onDone,
    random: random,
    reservation: reservation,
  );

  /// The Shop's GET reward exactly as before (PRD-menu-v2 §8.3): 6 coins,
  /// 0.65 s, 70 ms apart after 0.25 s; when the last lands `bn_coin`, the
  /// pill coin pops 135 %, the number counts up by the reward (75 by
  /// default, `shop_ad_coins`; PRD-2.3.1 §5) linearly in 0.4 s and
  /// `sk_progress` follows 0.18 s later. No ticks, glow or confetti.
  CoinRewardAnimation.freeCoins({
    required this.from,
    this.onDone,
    this.random,
    super.priority = 1000,
  }) : _flight = _Flight.button,
       reservation = null,
       amount = FreeCoinsPolicy.reward,
       coins = 6,
       flyDuration = 0.65,
       stagger = 0.07,
       countDuration = Config.coinRewardCountDuration,
       ticks = 0,
       confetti = 0,
       confettiSpeed = 220,
       confettiDriftX = -70,
       confettiStars = false,
       jingle = null,
       flash = false,
       progressDelay = Config.coinRewardProgressDelay,
       originDy = 0,
       originCentre = false,
       spreadX = 0,
       jitterY = (min: 0, max: 0),
       midSpreadX = 0,
       rise = (min: 0, range: 0);

  final _Flight _flight;

  /// Coins credited (the "+amount" label; the count runs to the wallet).
  final int amount;

  /// Source box in world coordinates.
  final Rect from;

  /// Flying coins.
  final int coins;
  final double flyDuration;
  final double stagger;

  /// Count-up length (s, ease-out cubic; the GET preset is linear).
  final double countDuration;

  /// `sk_tick`s over the count (0 = none).
  final int ticks;

  /// Confetti pieces from the pill at the end (0 = none).
  final int confetti;
  final double confettiSpeed;
  final double confettiDriftX;
  final bool confettiStars;

  /// Plays at the end of the count (null = none).
  final Sfx? jingle;

  /// White full-screen flash at the end (the 100 000 pack).
  final bool flash;

  /// End of the count -> `sk_progress` (and the glow off).
  final double progressDelay;

  /// Burst origin: [from]'s top-left, or its top centre ([originCentre]),
  /// moved down [originDy].
  final double originDy;
  final bool originCentre;
  final double spreadX;
  final ({double min, double max}) jitterY;
  final double midSpreadX;
  final ({double min, double range}) rise;

  /// The LEVEL UP preset's level (analytics / callers).
  int? level;

  void Function()? onDone;
  math.Random? random;

  /// Coins the caller already reserved on the pill for this reward (it
  /// takes them over and lets them count in at its first landing); null =
  /// [prepare] reserves [amount] itself. Either way the count-up covers
  /// only this reward, never another one still waiting (PRD-home-v3 §5).
  final int? reservation;
  int _reservedHere = 0;

  CoinPill? _pill;
  CoinFly? _fly;

  /// The coin flight (null until [prepare]).
  CoinFly? get fly => _fly;

  double _t = 0;
  double? _countStart;
  bool _countDone = false;
  int _lastTick = -1;
  double? _progressAt;
  bool _progressed = false;
  bool _finished = false;

  /// Whether the count-up has started / ended (tests).
  bool get counting => _countStart != null && !_countDone;
  bool get countDone => _countDone;

  /// True once `sk_progress` played and [onDone] ran.
  bool get finished => _finished;

  /// The end-of-count confetti while it falls (tests).
  ConfettiBurst? get confettiBurst => _confetti;
  ConfettiBurst? _confetti;

  /// Builds the flight into [pill]'s coin and holds the pill. Called by
  /// [FlappySpikesGame.playCoinReward] before the component is added.
  void prepare({required CoinPill pill, required Sprite coin}) {
    if (_fly != null) return;
    _pill = pill..hold();
    final own = reservation;
    if (own == null) pill.reserve(amount);
    _reservedHere = own ?? amount;
    final to = pill.coinFlyTarget;
    _fly = switch (_flight) {
      _Flight.button => CoinFly(
        coin: coin,
        from: from,
        to: to,
        count: coins,
        duration: flyDuration,
        stagger: stagger,
        random: random,
        onDone: _onLegacyLanded,
        priority: 2,
      ),
      _Flight.burst => CoinFly.burst(
        coin: coin,
        origin: Offset(
          originCentre ? from.center.dx : from.left,
          from.top + originDy,
        ),
        to: to,
        count: coins,
        duration: flyDuration,
        stagger: stagger,
        spreadX: spreadX,
        jitterY: jitterY,
        midSpreadX: midSpreadX,
        rise: rise,
        random: random,
        onLand: _onLand,
        priority: 2,
      ),
    };
    add(_fly!);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    prepare(
      pill: game.coinPill,
      coin: Sprite(await game.images.load('menu/coin.png')),
    );
  }

  /// §5 landing: `bn_coin` and a 125 % coin pop; the first starts the
  /// count-up.
  void _onLand(int index) {
    final pill = _pill!;
    game.sound.play(Sfx.bnCoin);
    pill.popCoin(
      scale: Config.coinRewardLandPopScale,
      duration: Config.coinRewardLandPopDuration,
    );
    if (_countStart != null) return;
    _countStart = _t;
    _unreserve();
    pill
      ..balance = game.menu.wallet.balance
      ..glow = true
      ..releaseHold(duration: countDuration);
    _tick(0);
  }

  /// GET: everything happens once the last coin is in.
  void _onLegacyLanded() {
    final pill = _pill;
    if (pill == null || _countStart != null) return;
    _countStart = _t;
    _countDone = true;
    _unreserve();
    game.sound.play(Sfx.bnCoin);
    pill
      ..balance = game.menu.wallet.balance
      ..releaseHold(duration: countDuration, linear: true)
      ..popCoin();
    _progressAt = _t + progressDelay;
  }

  void _unreserve() {
    _pill?.unreserve(_reservedHere);
    _reservedHere = 0;
  }

  void _tick(double k) {
    if (ticks <= 0 || k >= 1) return;
    final tick = (k * ticks).floor();
    if (tick == _lastTick) return;
    _lastTick = tick;
    game.sound.play(Sfx.skTick);
  }

  void _onCountEnd() {
    _countDone = true;
    final pill = _pill!;
    final jingle = this.jingle;
    if (jingle != null) game.sound.play(jingle);
    pill
      ..popPill()
      ..popCoin(
        scale: Config.coinRewardSpinPopScale,
        duration: Config.coinRewardSpinPopDuration,
        degrees: Config.coinRewardSpinPopDegrees,
      );
    final motion = !game.reduceMotion;
    if (motion && confetti > 0) {
      final target = pill.coinFlyTarget;
      add(
        _confetti = ConfettiBurst.burst(
          origin: Offset(target.dx + 8, target.dy + 10),
          count: confetti,
          speed: confettiSpeed,
          driftX: confettiDriftX,
          stars: confettiStars,
          random: random,
          priority: 1,
        ),
      );
    }
    add(_PlusLabel('+${formatCoins(amount)}', pill: pill));
    if (motion && flash) add(_Flash(game.viewHeight));
    _progressAt = _t + progressDelay;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final start = _countStart;
    if (start != null && !_countDone) {
      final k = (_t - start) / countDuration;
      if (k >= 1) {
        _onCountEnd();
      } else {
        _tick(k);
      }
    }
    final progressAt = _progressAt;
    if (progressAt != null && _t >= progressAt) {
      _progressAt = null;
      _progressed = true;
      _pill?.glow = false;
      game.sound.play(Sfx.skProgress);
    }
    if (_progressed && !_finished && (_fly?.done ?? true)) {
      _finish();
    }
    if (_finished && children.isEmpty) removeFromParent();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    onDone?.call();
  }

  @override
  void onRemove() {
    if (!_finished) {
      _unreserve();
      _pill
        ?..releaseHold()
        ..glow = false;
      _finish();
    }
    super.onRemove();
  }
}

/// "+10 000" under the pill (§5): gold 26 pt with a 1 pt gold outline and
/// a plum 25 % drop shadow (0, 2); 1.5 s ease-out: in from 10 pt lower at
/// 60 %, 115 % at 20 %, 6 pt up at 70 %, then 22 pt up fading out.
class _PlusLabel extends PositionComponent with GroupOpacity {
  _PlusLabel(this.text, {required this.pill}) : super(priority: 3) {
    decorator.addLast(_pose = WiggleEffect(this));
  }

  final String text;
  final CoinPill pill;
  late final WiggleEffect _pose;
  double _t = 0;
  late final Vector2 _rest;

  static const Color _shadow = Color(0x407A0044);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final label = MenuText(
      text,
      fontSize: Config.coinRewardLabelFontSize,
      color: Config.menuGold,
      strokeWidth: 1,
    );
    final shadow = MenuText(
      text,
      fontSize: Config.coinRewardLabelFontSize,
      color: _shadow,
      strokeWidth: 1,
      position: Vector2(0, 2),
    );
    size = label.size.clone();
    final p = pill.absolutePosition;
    _rest = Vector2(
      p.x + pill.width - Config.coinRewardLabelInset - size.x,
      p.y + pill.height + Config.coinRewardLabelGap,
    );
    addAll([shadow, label]);
    _apply();
  }

  void _apply() {
    final u = Curves.easeOut.transform(
      (_t / Config.coinRewardLabelDuration).clamp(0.0, 1.0),
    );
    double dy, scale, alpha;
    if (u < .2) {
      final k = u / .2;
      dy = 10 - 10 * k;
      scale = .6 + (1.15 - .6) * k;
      alpha = k;
    } else if (u < .7) {
      final k = (u - .2) / .5;
      dy = -6 * k;
      scale = 1.15 - .15 * k;
      alpha = 1;
    } else {
      final k = (u - .7) / .3;
      dy = -6 - 16 * k;
      scale = 1;
      alpha = 1 - k;
    }
    position = _rest + Vector2(0, dy);
    _pose.scale = scale;
    opacity = alpha;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= Config.coinRewardLabelDuration) {
      removeFromParent();
      return;
    }
    _apply();
  }
}

/// The 100 000 pack's white flash over the whole screen.
class _Flash extends Component {
  _Flash(this.height) : super(priority: 4);

  final double height;
  double _t = 0;
  final Paint _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= Config.coinRewardFlashDuration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = 1 - (_t / Config.coinRewardFlashDuration).clamp(0.0, 1.0);
    _paint.color = Color.fromRGBO(
      255,
      255,
      255,
      Config.coinRewardFlashOpacity * k,
    );
    canvas.drawRect(bleedRectFor(this, height), _paint); // WP-TAB
  }
}
