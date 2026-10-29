// region P26-J5
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../levels/level_progress.dart';
import '../../run/screens/level_reveal_sheet.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../ui/confetti.dart';

const List<String> kLevelUpPopupImages = ['menu/close.png', 'menu/coin.png'];

/// Home catch-up for the rewards persisted at run end (PRD-2.6 J7).
class LevelUpPopup extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  LevelUpPopup({
    required this.pending,
    required this.look,
    required this.onClaim,
  }) : super(priority: 26);

  final PendingLevelUp pending;
  final Look look;
  final void Function(Rect? from) onClaim;
  late final LevelCatchUpSheet reveal;
  bool active = true;
  double _t = 0;
  double get time => _t;
  double get rayAngle => game.reduceMotion ? 0 : _t * .5;
  ConfettiBurst? confetti;
  bool _confettiDone = false;
  bool _skipRequested = false;
  final Paint _dimPaint = Paint()..color = const Color(0xB8282830);

  // Compatibility for the existing direct-action integration seam. This is
  // never mounted or shown; real choices live in the reveal sheet.
  late final MenuButton claimButton = MenuButton(
    size: Vector2.zero(),
    onPressed: () => unawaited(game.claimLevelUp()),
  );

  static int confettiFor(int level) => level >= 9
      ? 140
      : level >= 5
      ? 90
      : 50;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    final revealScale = ((h - 250) / 360).clamp(.65, 1.0);
    final revealTop = (h * .38).clamp(0.0, h - 310 * revealScale);
    add(
      _Header(this, size: Vector2(Config.p1PopupWidth, 60))
        ..position = Vector2(
          (Config.worldWidth - Config.p1PopupWidth * revealScale) / 2,
          revealTop - 60 * revealScale,
        )
        ..scale.setAll(revealScale),
    );
    reveal = LevelCatchUpSheet(
      rewards: game.menu.levels.pending,
      onFinished: () => onClaim(null),
    );
    add(reveal);
  }

  // region P26-FIX2
  /// Back reveals the current box; the next Back chooses LATER, so the popup
  /// closes and its persisted reward is paid.
  // endregion
  void skipReveal() {
    _skipRequested = true;
    _applySkip();
  }

  void _applySkip() {
    if (!isLoaded || !reveal.isLoaded || !reveal.current.isMounted) return;
    _skipRequested = false;
    // region P26-FIX2
    reveal.current.advanceSkill();
    // endregion
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_skipRequested) _applySkip();
    if (!_confettiDone && _t >= Config.levelUpConfettiDelay) {
      _confettiDone = true;
      if (!game.reduceMotion) {
        final rect = Config.levelUpCardRectFor(game.viewHeight);
        final burst = ConfettiBurst.burst(
          origin: Offset(Config.worldWidth / 2, rect.top + 90),
          count: confettiFor(pending.toLevel),
          speed: pending.toLevel >= 9 ? 300 : 220,
          driftX: 0,
          priority: 30,
        );
        confetti = burst;
        parent?.add(burst);
      }
    }
  }

  @override
  void render(Canvas canvas) =>
      canvas.drawRect(bleedRectFor(this, size.y), _dimPaint);

  @override
  bool containsLocalPoint(Vector2 point) =>
      active && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}
// endregion

/// The pink header: 16 slowly rotating soft-pink ray wedges (22 %, 0.5
/// rad/s, static under reduce motion) behind the emblem + bird, clipped to
/// the header.
class _Header extends PositionComponent {
  // region P26-J5
  _Header(this._popup, {super.size});
  // endregion

  final LevelUpPopup _popup;
  final Paint _pink = Paint()..color = Config.menuPink;
  final Paint _ray = Paint()..color = Config.menuSoft.withValues(alpha: .22);

  static final Path _rays = () {
    final path = Path();
    const n = 16;
    const step = 2 * math.pi / n;
    final box = Rect.fromCircle(center: Offset.zero, radius: 190);
    for (var i = 0; i < n; i++) {
      path
        ..moveTo(0, 0)
        ..arcTo(box, i * step, step / 2, false)
        ..close();
    }
    return path;
  }();

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x, y, width, height));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _pink);
    final still = _popup.game.reduceMotion;
    canvas.save();
    canvas.translate(width / 2, Config.levelUpEmblemY);
    // region P26-J5
    if (!still) canvas.rotate(_popup.rayAngle);
    // endregion
    canvas.drawPath(_rays, _ray);
    canvas.restore();
  }
}
