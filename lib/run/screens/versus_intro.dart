import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../components/home/menu_primitives.dart';
import '../../components/levels/emblem_view.dart';
import '../../components/look_component.dart';
import '../../components/ui/confetti.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../skins/art/bird_art.dart';
import '../../skins/look.dart';
import '../../versus/opponent.dart';
import '../config/versus_config.dart';
import '../effects/easing.dart';
import '../effects/fireworks.dart';
import '../effects/particle_pool.dart';
import '../hud/run_hud.dart' show HudText;

const Color _pink = Color(0xFFEC008C);
const Color _soft = Color(0xFFFCD9EE);
const Color _plum = Color(0xFF7A0044);
const Color _gold = Color(0xFFFFB529);
const Color _white = Color(0xFFFFFFFF);

/// CSS easing curves of the mock.
double _easeOut(double u) => Ease.bezier(u, 0, 0, .58, 1);
double _easeIn(double u) => Ease.bezier(u, .42, 0, 1, 1);
double _easeInOut(double u) => Ease.bezier(u, .42, 0, .58, 1);
double _panelEase(double u) => Ease.bezier(u, .2, .8, .3, 1);
double _flyEase(double u) => Ease.bezier(u, .25, .7, .35, 1);

/// Piecewise-linear keyframes `(offset, value)` at the eased progress [u]
/// (WAAPI semantics: the easing applies to the whole animation).
double _kf(double u, List<(double, double)> stops) {
  if (u <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (o1, v1) = stops[i];
    if (u <= o1) {
      final (o0, v0) = stops[i - 1];
      final k = o1 == o0 ? 1.0 : (u - o0) / (o1 - o0);
      return v0 + (v1 - v0) * k;
    }
  }
  return stops.last.$2;
}

/// Progress of an animation that started at [start] and lasts [length]
/// at time [t]: null before it starts, then 0..1 (held at 1 after).
double? _prog(double t, double? start, double length) {
  if (start == null || t < start) return null;
  return length <= 0 ? 1 : ((t - start) / length).clamp(0.0, 1.0);
}

/// The VS intro (PRD-2 §5.8, approved `screen_versus_levels.html` "V2 Spike
/// divider" with the stripes background and level emblems): two panels
/// slide over the home screen, your bird flies in and your emblem pops, a
/// slot-machine reel of names lands on the **real, prefetched** opponent
/// (§3.13: the reel only presents the match as a draw — filler names and
/// random emblems while spinning, always ending on their real name and
/// level), MATCH FOUND! with confetti and three fireworks, the opponent
/// flies in, VS punches onto the seam with a shake, both birds taunt, then a
/// 0.3 s white fade into the run. Not skippable (Q23): it takes no taps.
///
/// One clock ([time]) drives everything; the game awaits [done] and then
/// starts the run under the white ([whiteOpacity] reaches 1).
///
/// Layout: the 320 × 711 mock; every y maps through [yFor] (the band
/// between the 44 pt strips scales with the screen height, call), so
/// 568 … 730 pt screens keep every part between the strips, unoverlapped.
class VersusIntro extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  VersusIntro({
    required this.opponent,
    required this.myName,
    required this.myLook,
    required this.myLevel,
    this.onCovered,
    math.Random? random,
  }) : _rnd = random ?? math.Random(),
       super(priority: priorityOnTop);

  /// Above the home screen (menus 20 live in the world too; the strips are
  /// lifted to 21 over it, as over the results page).
  static const int priorityOnTop = 20;

  final OpponentRun opponent;
  final String myName;
  final Look myLook;
  final int myLevel;
  final math.Random _rnd;

  /// Called once the panels have landed and cover the home screen.
  final void Function()? onCovered;

  final Completer<void> _done = Completer<void>();

  /// Completes when the white fade has covered the screen.
  Future<void> get done => _done.future;

  /// Seconds since START.
  double time = 0;

  /// Frozen for screenshot tests ([debugFreeze]).
  bool _frozen = false;

  late final double h;
  late final double seam;

  /// §5.8 (call) A y of the 711 mock on this screen: the band between the
  /// 44 pt strips scales with the screen height (568 … 730), so the birds,
  /// plates and VS never overlap on short screens.
  double yFor(double y) => 44 + (y - 44) * (h - 88) / (711 - 88);

  /// Filler names of the reel (random display names, §5.8 honesty).
  static const List<String> fillers = [
    'Kiwi', 'Zap', 'Ace', 'Pip', 'Tofu', 'Rex', 'Luna', 'Fizz', 'Gizmo', //
    'Bean', 'Echo', 'Juno', 'Spike', 'Dash', 'Bubbles', 'Taco', 'Ziggy',
    'Nugget', 'Wren', 'Sky',
  ];

  /// Avatar colours cycling with the reel.
  static const List<Color> avatarColors = [
    Color(0xFF29B6F6), Color(0xFF66BB6A), Color(0xFFFF7043), //
    Color(0xFFAB47BC), Color(0xFFFFD54F), Color(0xFF26A69A),
    Color(0xFFEF5350), Color(0xFF5C6BC0), Color(0xFF8D6E63),
  ];

  // ---- schedule (s) --------------------------------------------------
  late final List<double> _reelAt; // start of each name
  late final List<String> _reelNames;
  late final List<int> _reelLevels;
  late final double lockAt;
  late final double oppFlyAt;
  late final double vsAt;
  late final double fadeAt;
  late final double endAt;

  final List<(double, void Function())> _cues = [];
  int _nextCue = 0;

  // ---- parts ----------------------------------------------------------
  late final VersusIntroPanel _top;
  late final VersusIntroPanel _bottom;
  late final VersusIntroPlate oppPlate;
  late final VersusIntroPlate youPlate;
  late final VersusIntroBird youBird;
  late final VersusIntroBird oppBird;
  late final VersusIntroVs vs;
  late final VersusIntroFoundTag found;
  late final PositionComponent _shake;
  late final ParticlePool particles;
  late final Fireworks fireworks;

  double? _findingIn, _findingOut, _qIn, _qOut, _shakeAt;

  /// Reel index shown now (−1 before the reel).
  int get reelIndex {
    var i = -1;
    for (var k = 0; k < _reelAt.length; k++) {
      if (time >= _reelAt[k]) i = k;
    }
    return i;
  }

  /// The name the reel shows now ('' before it starts).
  String get reelName {
    final i = reelIndex;
    return i < 0 ? '' : _reelNames[i];
  }

  /// The white fade over everything (0..1; the run starts at 1).
  double get whiteOpacity =>
      ((time - fadeAt) / VersusConfig.whiteFade).clamp(0.0, 1.0);

  /// The intro has locked on the opponent.
  bool get locked => time >= lockAt;

  bool get finished => _done.isCompleted;

  /// Freezes the clock at [t] (screenshot tests, like the mocks' frames).
  void debugFreeze(double t) {
    while (time < t) {
      updateTree(math.min(1 / 60, t - time + 1e-9));
    }
    _frozen = true;
  }

  /// Lets the clock run again after [debugFreeze].
  void unfreeze() => _frozen = false;

  /// Plays the rest at once (`E2EHooks.skipVersusIntroWait`).
  void finishNow() {
    while (!finished) {
      updateTree(1 / 30);
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    h = game.viewHeight;
    size = Vector2(320, h);
    seam = yFor(VersusConfig.seamY);
    _plan();

    final fg = game.foregroundColor, bg = game.stageBackground;
    add(_Backing(this));
    _shake = PositionComponent(size: size);
    add(_shake);

    // Bottom panel (you): pink 16 % over bg, −45° stripes drifting right,
    // squares sinking.
    _bottom = VersusIntroPanel(
      this,
      top: false,
      color: Color.lerp(bg, _pink, VersusConfig.bottomTint)!,
      stripe: _pink.withValues(alpha: VersusConfig.stripeBottomAlpha),
      square: _pink.withValues(alpha: VersusConfig.floatBottomAlpha),
    );
    youBird = VersusIntroBird(
      look: myLook,
      home: Offset(
        VersusConfig.youBird.dx,
        yFor(VersusConfig.youBird.dy),
      ),
      mirror: false,
      bobPeriod: VersusConfig.youBobPeriod,
      bobDelay: 0,
      blinkDelay: 0,
    );
    youPlate = VersusIntroPlate(
      this,
      rect: VersusConfig.youPlate.translate(
        0,
        yFor(VersusConfig.youPlate.top) - VersusConfig.youPlate.top,
      ),
      avatar: _pink,
      glyph: _soft,
      level: myLevel,
    );
    _bottom.addAll([youBird, youPlate]);

    // Top panel (opponent): fg 26 % over bg, 45° stripes drifting left,
    // squares rising; the seam teeth belong to it.
    _top = VersusIntroPanel(
      this,
      top: true,
      color: Color.lerp(bg, fg, VersusConfig.topTint)!,
      stripe: fg.withValues(alpha: VersusConfig.stripeTopAlpha),
      square: fg.withValues(alpha: VersusConfig.floatTopAlpha),
    );
    oppPlate = VersusIntroPlate(
      this,
      rect: VersusConfig.oppPlate.translate(
        0,
        yFor(VersusConfig.oppPlate.top) - VersusConfig.oppPlate.top,
      ),
      avatar: fg,
      glyph: bg,
      level: _reelLevels.first,
      reel: true,
    )..opacity = 0;
    oppBird = VersusIntroBird(
      look: opponent.look,
      home: Offset(VersusConfig.oppBird.dx, yFor(VersusConfig.oppBird.dy)),
      mirror: true,
      bobPeriod: VersusConfig.oppBobPeriod,
      bobDelay: -.4,
      blinkDelay: -1.4,
    );
    found = VersusIntroFoundTag(
      position: Vector2(VersusConfig.foundTag.dx, yFor(VersusConfig.foundTag.dy)),
    )
      ..opacity = 0;
    _top.addAll([_FindingText(this), _QMark(this), oppPlate, oppBird, found]);

    vs = VersusIntroVs(
      rect: Rect.fromLTWH(
        VersusConfig.vsBox.left,
        yFor(VersusConfig.vsBox.top),
        VersusConfig.vsBox.width,
        VersusConfig.vsBox.height,
      ),
    );
    particles = ParticlePool(capacity: 260);
    fireworks = Fireworks(launchY: seam - 2, random: _rnd);
    _shake.addAll([_bottom, _top, vs, particles, fireworks]);
    youBird.opacity = 0;
    oppBird.opacity = 0;
  }

  void _at(double t, void Function() f) => _cues.add((t, f));

  void _sfx(Sfx s) {
    if (!_frozen) game.sound.play(s);
  }

  /// The §5.8 timeline (mock `play()`), absolute seconds from START.
  void _plan() {
    // Reel: 20 names, interval 40 + 330·p^2.4 ms, the last = the opponent.
    const n = VersusConfig.reelNames;
    final pool = [...fillers]..shuffle(_rnd);
    _reelNames = [
      for (var i = 0; i < n; i++)
        i == n - 1 ? opponent.name : pool[i % pool.length],
    ];
    _reelLevels = [
      for (var i = 0; i < n; i++)
        i == n - 1 ? opponent.level : 1 + _rnd.nextInt(10),
    ];
    const reelStart = VersusConfig.youFlyAt + VersusConfig.youFly;
    _reelAt = [];
    var t = reelStart;
    for (var i = 0; i < n; i++) {
      _reelAt.add(t);
      final p = i / (n - 1);
      t +=
          (VersusConfig.reelBaseMs +
              VersusConfig.reelSlowMs * math.pow(p, VersusConfig.reelPow)) /
          1000;
    }
    lockAt = t;
    oppFlyAt = lockAt + VersusConfig.oppFlyDelay;
    vsAt = oppFlyAt + VersusConfig.oppFly + VersusConfig.vsDelay;
    fadeAt = vsAt + VersusConfig.fadeAt;
    endAt = fadeAt + VersusConfig.whiteFade;

    // 0.12 s: panels + whoosh; 0.54 s they cover the home screen.
    _at(VersusConfig.panelsAt, () => _sfx(Sfx.vsWhoosh));
    _at(
      VersusConfig.panelsAt + VersusConfig.panelsSlide,
      () => onCovered?.call(),
    );
    // 0.54 s: your bird flies in; opponent plate drops; FINDING RIVAL…
    _at(VersusConfig.youFlyAt, () {
      youBird
        ..opacity = 1
        ..fly(time, VersusConfig.youFly, _youPath, VersusConfig.flyFlap);
      oppPlate.dropAt = time;
      _findingIn = time;
      _qIn = time;
      _sfx(Sfx.flap);
    });
    _at(VersusConfig.youFlyAt + .3, () => _sfx(Sfx.flap));
    // Landing: squash, idle, your emblem pops (boing); the opponent's
    // emblem starts cycling with the reel.
    _at(reelStart, () {
      youBird.land(time);
      youPlate.popAt = time;
      oppPlate.emblemVisible = true;
      _sfx(Sfx.vsBoing);
    });
    for (var i = 0; i < n; i++) {
      final at = _reelAt[i];
      final last = i == n - 1;
      final dur = last
          ? (at - _reelAt[i - 1])
          : (i + 1 < n ? _reelAt[i + 1] - at : .04);
      _at(at, () {
        oppPlate.spin(
          _reelNames[i],
          time,
          last ? VersusConfig.reelLand : dur * .85,
          last: last,
        );
        oppPlate.avatar = last
            ? game.foregroundColor
            : avatarColors[i % avatarColors.length];
        oppPlate.level = _reelLevels[i];
        _sfx(Sfx.vsTick);
      });
    }
    // Lock.
    _at(lockAt, () {
      _sfx(Sfx.vsChime);
      oppPlate
        ..flashAt = time
        ..punchAt = time
        ..popAt = time;
      found.popAt = time;
      _findingOut = time;
      if (!game.reduceMotion) {
        _shake.add(
          ConfettiBurst.burst(
            origin: Offset(160, yFor(106)),
            count: VersusConfig.lockConfetti,
            coinEvery: 1 << 20,
            random: _rnd,
          ),
        );
      }
      for (final r in VersusConfig.rockets) {
        fireworks.launch(r.$1, yFor(r.$2), r.$3, delay: r.$4);
      }
      youBird.hop(time, 22);
    });
    for (final r in VersusConfig.rockets) {
      _at(lockAt + r.$4, () => _sfx(Sfx.vsRocket));
      _at(lockAt + r.$4 + Fireworks.rise, () => _sfx(Sfx.vsPop));
    }
    // Opponent flies in.
    _at(oppFlyAt, () {
      _qOut = time;
      oppBird
        ..opacity = 1
        ..fly(time, VersusConfig.oppFly, _oppPath, .09);
      _sfx(Sfx.flap);
    });
    _at(oppFlyAt + .26, () => _sfx(Sfx.flap));
    _at(oppFlyAt + VersusConfig.oppFly, () {
      oppBird.land(time, flapPeriod: .2);
      found.outAt = time + .4;
    });
    // VS punch.
    _at(vsAt, () {
      _sfx(Sfx.vsThud);
      vs.punchAt = time;
    });
    _at(vsAt + VersusConfig.shakeAt, () {
      _sparks();
      _shakeAt = time;
      oppBird.lunge(time, -1);
      youBird.lunge(time, 1);
    });
    _at(vsAt + VersusConfig.shakeAt + .15, () => vs.liveAt = time);
    // Hold + taunts.
    _at(vsAt + VersusConfig.flipAt, () {
      oppBird.flip(time);
      _sfx(Sfx.vsBoing);
    });
    _at(vsAt + VersusConfig.hop1At, () {
      youBird.hop(time, 26);
      _sfx(Sfx.flap);
    });
    _at(vsAt + VersusConfig.hop2At, () {
      youBird.hop(time, 16);
      _sfx(Sfx.flap);
    });
    _cues.sort((a, b) => a.$1.compareTo(b.$1));
  }

  // Fly-in paths (x, y, rotation°) relative to the home spot.
  static const List<(double, double, double, double)> _youPath = [
    (0, -280, 70, 25),
    (.5, -120, -30, -10),
    (.85, 14, -6, -6),
    (1, 0, 0, 0),
  ];
  static const List<(double, double, double, double)> _oppPath = [
    (0, 280, -110, -20),
    (.45, 110, -60, 8),
    (.85, -16, 10, 6),
    (1, 0, 0, 0),
  ];

  void _sparks() {
    if (game.reduceMotion) return;
    const colors = [_gold, _soft, _white];
    for (var i = 0; i < 26; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final v = 120 + _rnd.nextDouble() * 180;
      particles.spawn(
        x: 160,
        y: seam + 4,
        vx: math.cos(a) * v * 1.6,
        vy: math.sin(a) * v * .5,
        w: 4,
        color: colors[_rnd.nextInt(3)],
        life: .35 + _rnd.nextDouble() * .25,
        gravity: 110,
        drag: 1.2,
      );
    }
  }

  void _trail(VersusIntroBird b, int dir) {
    if (!b.flying(time) || game.reduceMotion) return;
    if (_rnd.nextDouble() >= .7) return;
    final spec = BirdArt.byId(b.look.bird);
    final colors = [spec.c, spec.d, _white];
    final p = b.absoluteCentre(this);
    particles.spawn(
      x: p.dx + (_rnd.nextDouble() * 20 - 10),
      y: p.dy + (_rnd.nextDouble() * 20 - 10),
      vx: dir * -(40 + _rnd.nextDouble() * 50),
      vy: -20 + _rnd.nextDouble() * 60,
      w: 3 + _rnd.nextDouble() * 4,
      color: colors[_rnd.nextInt(3)],
      life: .35 + _rnd.nextDouble() * .25,
      rot: _rnd.nextDouble() * 6,
      spin: 6,
      alpha0: .9,
    );
  }

  /// Panel slide offset at the current time (top: −362 → 6 → 0).
  double panelOffset({required bool top}) {
    final u = _prog(time, VersusConfig.panelsAt, VersusConfig.panelsSlide);
    final from = top ? -(seam + 22) : h - seam;
    if (u == null) return from;
    final o = top ? VersusConfig.panelOvershoot : -VersusConfig.panelOvershoot;
    return _kf(_panelEase(u), [(0, from), (.8, o), (1, 0)]);
  }

  /// The panels have landed (the backing shows behind them).
  bool get panelsIn =>
      time >= VersusConfig.panelsAt + VersusConfig.panelsSlide;

  @override
  void update(double dt) {
    if (_frozen) return;
    super.update(dt);
    time += dt;
    while (_nextCue < _cues.length && _cues[_nextCue].$1 <= time) {
      _cues[_nextCue++].$2();
    }
    _trail(youBird, 1);
    _trail(oppBird, -1);
    // Shake (0.3 s, ±6 / ±5 pt, keyframes every 0.05 s).
    final su = _prog(time, _shakeAt, VersusConfig.shake);
    if (su != null && su < 1) {
      final k = (su * 6).floor();
      final r = math.Random(k * 7919 + 13);
      _shake.position = Vector2(
        r.nextDouble() * 12 - 6,
        r.nextDouble() * 10 - 5,
      );
    } else {
      _shake.position = Vector2.zero();
    }
    if (time >= endAt && !_done.isCompleted) _done.complete();
  }

  // ---- overlays read by the parts --------------------------------------
  double get findingOpacity {
    final i = _prog(time, _findingIn, .25);
    if (i == null) return 0;
    final o = _prog(time, _findingOut, .15);
    return o == null ? i : (1 - o);
  }

  (double scale, double opacity) get qmark {
    final i = _prog(time, _qIn, .3);
    if (i == null) return (0, 0);
    final o = _prog(time, _qOut, .2);
    if (o != null) return (1 + o, 1 - o);
    final e = Ease.cssOut(i);
    return (.3 + .7 * e, i.clamp(0.0, 1.0));
  }
}

/// The fg-coloured backing: a shake never shows the page background.
class _Backing extends Component {
  _Backing(this.intro);
  final VersusIntro intro;
  final Paint _p = Paint();

  @override
  void render(Canvas canvas) {
    if (!intro.panelsIn) return;
    _p.color = intro.game.foregroundColor;
    canvas.drawRect(Rect.fromLTWH(-10, 0, 340, intro.h), _p);
  }
}

/// One half: its flat tint, the moving stripes and the floating squares,
/// clipped to its shape (the top one owns the seam teeth). Children ride
/// with its slide.
class VersusIntroPanel extends PositionComponent {
  VersusIntroPanel(
    this.intro, {
    required this.top,
    required this.color,
    required this.stripe,
    required this.square,
  });

  final VersusIntro intro;
  final bool top;
  final Color color, stripe, square;
  final Paint _p = Paint();

  // Floating squares (x, y in the panel, size, duration, delay) — mock.
  static const List<(double, double, double, double, double)> _topSquares = [
    (40, 300, 12, 8, -2),
    (270, 320, 9, 6.5, -5),
    (150, 310, 14, 9, -7),
    (220, 290, 8, 7, -1),
  ];
  static const List<(double, double, double, double, double)> _botSquares = [
    (30, 40, 10, 7, -1),
    (250, 10, 14, 9, -4),
    (120, 90, 8, 6, -2.5),
    (200, 60, 12, 8, -6),
  ];

  Path _shape() {
    final s = intro.seam;
    if (!top) return Path()..addRect(Rect.fromLTWH(0, s, 320, intro.h - s + 10));
    final base = s - 3, tip = base + VersusConfig.seamTooth;
    final p = Path()
      ..moveTo(0, -10)
      ..lineTo(320, -10)
      ..lineTo(320, base);
    const half = VersusConfig.seamPeriod / 2;
    var x = 320.0;
    var down = true;
    while (x > 0) {
      x -= half;
      p.lineTo(x, down ? tip : base);
      down = !down;
    }
    return p..close();
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y = intro.panelOffset(top: top);
  }

  @override
  void render(Canvas canvas) {
    final t = intro.time;
    final shape = _shape();
    canvas.save();
    canvas.clipPath(shape);
    _p.color = color;
    canvas.drawPath(shape, _p);
    // Stripes: 14 band / 14 clear across the gradient direction; one
    // horizontal period (39.6 pt) every 3.2 s.
    final phase = (t / VersusConfig.stripePeriod) % 1;
    final dx = (top ? -1 : 1) * VersusConfig.stripeDrift * phase;
    _p.color = stripe;
    canvas.save();
    canvas.translate(160 + dx, intro.seam);
    canvas.rotate(top ? -math.pi / 4 : -3 * math.pi / 4);
    const band = VersusConfig.stripeBand;
    for (var k = -40; k <= 40; k++) {
      canvas.drawRect(Rect.fromLTWH(k * 2 * band, -1000, band, 2000), _p);
    }
    canvas.restore();
    // Squares rise (top) / sink (bottom), rotating 180°.
    final list = top ? _topSquares : _botSquares;
    final y0 = top ? 0.0 : intro.seam;
    for (final (x, y, s, d, dl) in list) {
      final u = ((t - dl) / d) % 1;
      final a = u < .15
          ? u / .15 * .8
          : u > .85
          ? (1 - u) / .15 * .8
          : .8;
      final dy = (top ? -1 : 1) * VersusConfig.floatTravel * u;
      _p.color = square.withValues(alpha: square.a * a);
      canvas.save();
      canvas.translate(x + s / 2, y0 + y + dy + s / 2);
      canvas.rotate((top ? 1 : -1) * math.pi * u);
      canvas.drawRect(Rect.fromLTWH(-s / 2, -s / 2, s, s), _p);
      canvas.restore();
    }
    canvas.restore();
  }
}

/// A name plate (232 × 52): avatar square with the person glyph, the name
/// (or the reel) and the level emblem overhanging the right slot.
class VersusIntroPlate extends PositionComponent with GroupOpacity {
  VersusIntroPlate(
    this.intro, {
    required this.rect,
    required this.avatar,
    required this.glyph,
    required int level,
    this.reel = false,
  }) : super(position: rect.topLeft.toVector2(), size: rect.size.toVector2()) {
    emblem = EmblemView(
      level: level,
      artScale: VersusConfig.emblemScale,
      position: Vector2(rect.width - VersusConfig.plateSlot / 2, rect.height / 2),
    );
  }

  final VersusIntro intro;
  final Rect rect;
  Color avatar;
  final Color glyph;
  final bool reel;
  late final EmblemView emblem;

  double? dropAt, popAt, flashAt, punchAt;
  bool emblemVisible = false;

  String _name = '';
  String _old = '';
  double _spinAt = -1, _spinLen = .04;
  bool _landing = false;
  final Map<String, HudText> _texts = {};
  final Paint _p = Paint();

  set level(int v) => emblem.level = v;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!reel) _name = intro.myName;
    add(emblem);
  }

  void spin(String name, double at, double length, {required bool last}) {
    _old = _name;
    _name = name;
    _spinAt = at;
    _spinLen = length;
    _landing = last;
  }

  HudText _text(String s) => _texts.putIfAbsent(
    s,
    () => HudText(s, size: VersusConfig.plateNameSize, color: _plum),
  );

  /// The name shown now (tests).
  String get name => _name;

  @override
  void update(double dt) {
    super.update(dt);
    final t = intro.time;
    emblem.t = t;
    // Drop in (opponent): opacity 0 → 1, y −30 → 0, scale .7 → 1.
    var sc = 1.0;
    var dy = 0.0;
    final d = _prog(t, dropAt, VersusConfig.plateDrop);
    if (reel) {
      if (d == null) {
        opacity = 0;
      } else {
        final e = Ease.cssOut(d);
        opacity = d.clamp(0.0, 1.0);
        dy = -30 * (1 - e);
        sc = .7 + .3 * e;
      }
    }
    final pu = _prog(t, punchAt, VersusConfig.lockFlash);
    if (pu != null) sc *= _kf(_easeOut(pu), [(0, 1), (.35, 1.1), (1, 1)]);
    scale = Vector2.all(sc);
    anchor = Anchor.center;
    position = Vector2(rect.center.dx, rect.center.dy + dy);
    // Emblem: hidden until it pops (yours) / starts cycling (theirs).
    final pop = _prog(t, popAt, VersusConfig.emblemPop);
    final shown = emblemVisible || pop != null;
    if (!shown) {
      emblem.popScale = 0;
    } else if (pop != null && pop < 1) {
      final e = _easeOut(pop);
      emblem.popScale = _kf(e, [(0, .15), (.6, 1.3), (.82, .92), (1, 1)]);
      emblem.angle =
          _kf(e, [(0, -25), (.6, 8), (.82, -3), (1, 0)]) * math.pi / 180;
    } else {
      emblem.popScale = 1;
      emblem.angle = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x, hh = size.y;
    const slot = VersusConfig.plateSlot;
    _p.color = intro.game.stageBackground;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, hh), _p);
    _p.color = avatar;
    canvas.drawRect(const Rect.fromLTWH(0, 0, slot, slot), _p);
    // Person glyph, 32 pt (24-unit box).
    canvas.save();
    canvas.translate(10, 10);
    canvas.scale(32 / 24);
    _p.color = glyph;
    canvas.drawCircle(const Offset(12, 8), 4.5, _p);
    canvas.drawPath(
      Path()
        ..moveTo(3, 22)
        ..arcToPoint(const Offset(21, 22), radius: const Radius.circular(9))
        ..close(),
      _p,
    );
    canvas.restore();
    // Name window (clipped; the reel rolls names through it).
    final win = Rect.fromLTWH(slot, 0, w - 2 * slot, hh);
    canvas.save();
    canvas.clipRect(win);
    final t = intro.time;
    final u = _spinAt < 0 ? 1.0 : ((t - _spinAt) / _spinLen).clamp(0.0, 1.0);
    final travel = hh * 1.1;
    if (_old.isNotEmpty && u < 1) {
      final e = _easeIn(u);
      _paintName(canvas, _old, -travel * e, win);
    }
    if (_name.isNotEmpty) {
      final e = _landing ? Ease.cssOut(u) : _easeOut(u);
      _paintName(canvas, _name, travel * (1 - e), win);
    }
    canvas.restore();
    // Lock flash (white .9 → 0).
    final f = _prog(t, flashAt, VersusConfig.lockFlash);
    if (f != null && f < 1) {
      _p.color = _white.withValues(alpha: .9 * (1 - f));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, hh), _p);
    }
  }

  void _paintName(Canvas canvas, String s, double dy, Rect win) {
    final text = _text(s);
    text.paintCentred(
      canvas,
      Offset(
        win.left + VersusConfig.plateNameLeft + text.width / 2,
        win.height / 2 + dy,
      ),
    );
  }
}

/// "FINDING RIVAL…" with blinking dots (14 pt, 0.18 em, stage grey).
class _FindingText extends PositionComponent {
  _FindingText(this.intro);
  final VersusIntro intro;
  HudText? _label, _dot;

  @override
  void render(Canvas canvas) {
    final a = intro.findingOpacity;
    if (a <= 0) return;
    final fg = intro.game.foregroundColor;
    const size = VersusConfig.findingSize;
    final label = _label ??= HudText(
      'FINDING RIVAL',
      size: size,
      color: fg,
      spacing: .18,
    );
    final dot = _dot ??= HudText('.', size: size, color: fg, spacing: .18);
    final gap = size * .18;
    final dotW = dot.width + gap;
    final width = label.width + gap + 3 * dotW;
    var x = 160 - width / 2;
    final cy = intro.yFor(VersusConfig.findingTop) + label.height / 2;
    label.paintCentred(canvas, Offset(x + label.width / 2, cy), opacity: a);
    x += label.width + gap;
    for (var i = 0; i < 3; i++) {
      final ph = (intro.time - i * .33) % 1;
      final da = ph < .5 ? .15 : 1.0;
      dot.paintCentred(canvas, Offset(x + dot.width / 2, cy), opacity: a * da);
      x += dotW;
    }
  }
}

/// The pulsing grey "?" in the empty bird spot (64 pt, `fg` 45 %).
class _QMark extends PositionComponent {
  _QMark(this.intro);
  final VersusIntro intro;
  HudText? _q;

  @override
  void render(Canvas canvas) {
    final (s, a) = intro.qmark;
    if (a <= 0 || s <= 0) return;
    final fg = intro.game.foregroundColor;
    final q = _q ??= HudText('?', size: 64, color: fg.withValues(alpha: .45));
    final ph = (intro.time / .7) % 2;
    final u = _easeInOut(ph < 1 ? ph : 2 - ph);
    final pulse = .92 + .16 * u;
    final rot = (-6 + 12 * u) * math.pi / 180;
    canvas.save();
    canvas.translate(160, intro.yFor(196));
    canvas.rotate(rot);
    canvas.scale(s * pulse);
    q.paintCentred(canvas, Offset.zero, opacity: a);
    canvas.restore();
  }
}

/// The gold "MATCH FOUND!" tag (white 11 pt, 0.08 em, −6°).
class VersusIntroFoundTag extends PositionComponent with GroupOpacity {
  VersusIntroFoundTag({super.position});

  double? popAt, outAt;
  late final MenuText _label;
  final Paint _p = Paint()..color = _gold;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _label = MenuText(
      'MATCH FOUND!',
      fontSize: 11,
      color: _white,
      letterSpacingEm: .08,
      lineHeight: 1.2,
      position: Vector2(6, 3),
    );
    add(_label);
    size = Vector2(_label.width + 12, _label.height + 6);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final intro = parent?.parent?.parent;
    final t = intro is VersusIntro ? intro.time : 0.0;
    final p = _prog(t, popAt, .3);
    if (p == null) {
      opacity = 0;
      return;
    }
    final e = Ease.cssOut(p);
    final o = _prog(t, outAt, .4);
    opacity = o == null ? p.clamp(0.0, 1.0) : 1 - o;
    anchor = Anchor.center;
    scale = Vector2.all(.4 + .6 * e);
    angle = (-12 + 6 * e) * math.pi / 180;
  }

  @override
  void onMount() {
    super.onMount();
    // Position is the top-left of the mock; keep it after anchoring.
    position += size / 2;
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _p);
}

/// The pink VS square on the seam (soft-pink 42 pt): punches in from 3 × /
/// −14°, then pulses ±8 %.
class VersusIntroVs extends PositionComponent {
  VersusIntroVs({required Rect rect})
    : super(
        position: rect.center.toVector2(),
        size: rect.size.toVector2(),
        anchor: Anchor.center,
      );

  double? punchAt, liveAt;
  final HudText _label = HudText(
    'VS',
    size: VersusConfig.vsSize,
    color: _soft,
    spacing: .06,
  );
  final Paint _p = Paint()..color = _pink;

  /// Seen on screen (tests).
  bool get shown => _opacity > 0;
  double _opacity = 0;
  double _pulse = 1;

  @override
  void update(double dt) {
    super.update(dt);
    final intro = parent?.parent;
    final t = intro is VersusIntro ? intro.time : 0.0;
    final p = _prog(t, punchAt, VersusConfig.vsPunch);
    if (p == null) {
      _opacity = 0;
      return;
    }
    final e = _easeIn(p);
    _opacity = _kf(e, [(0, 0), (.6, 1), (1, 1)]);
    scale = Vector2.all(_kf(e, [(0, 3), (.6, .85), (.8, 1.06), (1, 1)]));
    angle = _kf(e, [(0, -14), (.6, 3), (.8, -1), (1, 0)]) * math.pi / 180;
    final l = liveAt;
    if (l != null && t >= l) {
      final ph = ((t - l) / .9) % 2;
      _pulse = 1 + .08 * _easeInOut(ph < 1 ? ph : 2 - ph);
    } else {
      _pulse = 1;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, _opacity));
    canvas.drawRect(size.toRect(), _p);
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(_pulse);
    _label.paintCentred(canvas, Offset.zero);
    canvas.restore();
  }
}

/// A bird of the intro (2.2 ×, the equipped look; the opponent mirrored),
/// always alive: fly-in arc with fast flaps, landing squash, idle bob and
/// tilt, wing flaps, blinks, and the one-off reactions (hop, lunge, flip).
class VersusIntroBird extends PositionComponent {
  VersusIntroBird({
    required this.look,
    required this.home,
    required this.mirror,
    required this.bobPeriod,
    required this.bobDelay,
    required this.blinkDelay,
  });

  final Look look;
  final Offset home;
  final bool mirror;
  final double bobPeriod, bobDelay, blinkDelay;
  late final LookComponent bird;

  double opacity = 1;
  double? _flyAt, _landAt, _hopAt, _lungeAt, _flipAt;
  double _flyLen = 0, _hopH = 0, _lungeDir = 0;
  double _flapPeriod = VersusConfig.idleFlap;
  List<(double, double, double, double)> _path = const [];
  double _t = 0;

  bool flying(double t) =>
      _flyAt != null && t >= _flyAt! && t < _flyAt! + _flyLen;

  void fly(double at, double length, List<(double, double, double, double)> path, double flap) {
    _flyAt = at;
    _flyLen = length;
    _path = path;
    _flapPeriod = flap;
  }

  void land(double at, {double flapPeriod = VersusConfig.idleFlap}) {
    _landAt = at;
    _flapPeriod = flapPeriod;
  }

  void hop(double at, double height) {
    _hopAt = at;
    _hopH = height;
  }

  void lunge(double at, double dir) {
    _lungeAt = at;
    _lungeDir = dir;
  }

  void flip(double at) => _flipAt = at;

  /// The body centre in [root] coordinates (trail spawn point).
  Offset absoluteCentre(PositionComponent root) {
    final p = absolutePosition;
    final r = root.absolutePosition;
    return Offset(p.x - r.x, p.y - r.y);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    bird = LookComponent(look: look, artScale: VersusConfig.birdScale)
      ..flapOverride = false;
    if (mirror) bird.scale = Vector2(-1, 1);
    add(bird);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final intro = parent?.parent?.parent;
    final t = intro is VersusIntro ? intro.time : _t + dt;
    _t = t;
    var x = home.dx, y = home.dy, rot = 0.0, sx = 1.0, sy = 1.0;
    final f = _prog(t, _flyAt, _flyLen);
    if (f != null && f < 1) {
      final e = _flyEase(f);
      x += _kf(e, [for (final k in _path) (k.$1, k.$2)]);
      y += _kf(e, [for (final k in _path) (k.$1, k.$3)]);
      rot += _kf(e, [for (final k in _path) (k.$1, k.$4)]);
    }
    final landed = _landAt != null && t >= _landAt!;
    if (landed) {
      // Idle bob ±7 pt / −5° → 4°, alternate, ease-in-out.
      final ph = ((t - _landAt! - bobDelay) / bobPeriod) % 2;
      final u = _easeInOut(ph < 1 ? ph : 2 - ph);
      y += -VersusConfig.bob + 2 * VersusConfig.bob * u;
      rot += -VersusConfig.bobTilt + 9 * u;
      final l = _prog(t, _landAt, .32);
      if (l != null && l < 1) {
        final e = _easeOut(l);
        sx *= _kf(e, [(0, 1.25), (.45, .9), (.75, 1.04), (1, 1)]);
        sy *= _kf(e, [(0, .75), (.45, 1.12), (.75, .97), (1, 1)]);
      }
    }
    final hp = _prog(t, _hopAt, .3);
    if (hp != null && hp < 1) {
      final e = _easeOut(hp);
      y -= _kf(e, [(0, 0), (.4, _hopH), (.85, 0), (1, 0)]);
      sx *= _kf(e, [(0, 1.15), (.4, .92), (.85, 1.12), (1, 1)]);
      sy *= _kf(e, [(0, .85), (.4, 1.1), (.85, .88), (1, 1)]);
    }
    final lp = _prog(t, _lungeAt, .38);
    if (lp != null && lp < 1) {
      final e = _easeOut(lp);
      y += _kf(e, [(0, 0), (.3, _lungeDir * -18), (1, 0)]);
      final s = _kf(e, [(0, 1), (.3, 1.12), (1, 1)]);
      sx *= s;
      sy *= s;
    }
    final fp = _prog(t, _flipAt, .52);
    if (fp != null && fp < 1) {
      final e = _easeInOut(fp);
      y -= _kf(e, [(0, 0), (.5, 34), (1, 0)]);
      rot += _kf(e, [(0, 0), (.5, -180), (1, -360)]);
    }
    position = Vector2(x, y);
    angle = rot * math.pi / 180;
    scale = Vector2(sx, sy);
    // Wings: continuous flaps (scaleY 1 → −0.75 in the mock = wing down).
    bird.flapOverride = ((t / _flapPeriod).floor()).isOdd;
    bird.opacity = opacity;
    // Blink every ≈ 3.1 s (90 % → 96 %).
    final b = ((t - blinkDelay) / 3.1) % 1;
    bird.blink = b > .9 && b < .96;
  }
}
