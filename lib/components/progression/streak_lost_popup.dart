import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/sound.dart';
import '../../progression/day_streak.dart';
import '../home/menu_primitives.dart';
import '../noads_celebration.dart' show NoAdsCelebrationRays;
import '../ui/confetti.dart';
import '../ui/p1_popup.dart';
import 'streak_strip.dart';

enum StreakLostPhase { offer, loading, paying, retry, restoring, givingUp }

/// G2c's optional restore offer. All persisted transitions belong to the game.
class StreakLostPopup extends P1Popup {
  StreakLostPopup({
    required this.state,
    required this.noAds,
    required this.balance,
    required this.onRestore,
    required this.onGiveUp,
    required this.onMomentDone,
    required super.onDismiss,
  });

  final DayStreak state;
  final bool noAds;
  final int Function() balance;
  final void Function() onRestore;
  final void Function() onGiveUp;
  final void Function() onMomentDone;
  StreakLostPhase phase = StreakLostPhase.offer;
  late final _ActionGroup _actions;
  late final MenuButton restoreButton;
  late final MenuButton giveUpButton;
  late final MenuText title;
  late final MenuText action;
  late final MenuText oldCount;
  late final MenuText newCount;
  late final _FlameWipe _oldFlame;
  late final _FlameWipe _newFlame;
  late final PositionComponent arrows;
  late final MenuParagraph lostLine;
  MenuParagraph? detail;
  MenuParagraph? poorLine;
  late final MenuIcon paymentIcon;
  late final _LoadingSpinner _spinner;
  double _time = 0;
  double _moment = 0;
  int _restoredDays = 0;
  NoAdsCelebrationRays? restoreRays;
  bool _done = false;

  bool get resolving =>
      phase == StreakLostPhase.restoring || phase == StreakLostPhase.givingUp;
  bool get canRestore =>
      active &&
      !resolving &&
      phase != StreakLostPhase.loading &&
      phase != StreakLostPhase.paying &&
      state.restorePayment(noAds: noAds, coins: balance()).enabled;
  Rect get buttonRect => Rect.fromLTWH(
    card.x + restoreButton.x,
    card.y + restoreButton.y,
    restoreButton.width,
    restoreButton.height,
  );

  MenuText label(
    String text,
    double x,
    double y,
    double font, {
    Color color = Config.menuPlum,
  }) => MenuText(
    text,
    position: Vector2(x, y),
    fontSize: font,
    color: color,
    anchor: Anchor.topCenter,
  );

  void _detail(String text) {
    if (detail?.text == text) return;
    detail?.removeFromParent();
    card.add(
      detail = MenuParagraph(
        text,
        fontSize: 12.5,
        color: const Color(0xFF9A4D78),
        maxWidth: 248,
        position: Vector2(16, 197),
      ),
    );
  }

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 388;
    card.add(
      RectangleComponent(
        size: Vector2(280, 46),
        paint: Paint()..color = Config.menuPink,
      ),
    );
    card.add(title = label('STREAK LOST', 118, 12, 21, color: Config.menuSoft));
    card.add(
      closeBox(Sprite(await game.images.load('menu/close.png')), onDismiss),
    );
    _oldFlame = _FlameWipe(side: 44, lit: 1, position: Vector2(58, 60));
    _newFlame = _FlameWipe(side: 44, lit: 0, position: Vector2(178, 60));
    card.addAll([_oldFlame, _newFlame]);
    card.add(
      oldCount = label(
        '${state.streakLostDays}',
        80,
        119,
        36,
        color: const Color(0xFFFF7A1A),
      ),
    );
    card.add(
      newCount = label('0', 200, 119, 36, color: const Color(0xFFB5B5B5)),
    );
    card.add(arrows = label('›››', 140, 77, 30, color: Config.menuPink));
    card.add(
      RectangleComponent(
        position: Vector2(16, 168),
        size: Vector2(248, 64),
        paint: Paint()..color = const Color(0xFFFFFFFF),
      ),
    );
    card.add(
      lostLine = MenuParagraph(
        state.lostMessage,
        fontSize: 14,
        color: Config.menuPink,
        maxWidth: 248,
        position: Vector2(16, 173),
      ),
    );
    _detail(state.restoreMessage(noAds: noAds));
    card.add(_actions = _ActionGroup());
    restoreButton = MenuButton(
      position: Vector2(16, 246),
      size: Vector2(248, 50),
      color: Config.menuPink,
      isActive: () => canRestore,
      onPressed: onRestore,
    );
    restoreButton.add(action = label('', 114, 12, 22, color: Config.menuSoft));
    restoreButton.add(
      paymentIcon = MenuIcon(
        Sprite(
          await game.images.load(noAds ? 'menu/coin.png' : 'menu/video.png'),
        ),
        size: Vector2.all(22),
        position: Vector2(220, 25),
        anchor: Anchor.center,
      ),
    );
    restoreButton.add(_spinner = _LoadingSpinner(position: Vector2(20, 25)));
    _actions.add(restoreButton);
    giveUpButton = MenuButton(
      position: Vector2(16, 328),
      size: Vector2(248, 44),
      color: Config.menuSoft,
      isActive: () => active && !resolving,
      onPressed: onGiveUp,
      children: [label('GIVE UP', 124, 10, 20)],
    );
    _actions.add(giveUpButton);
    _sync();
  }

  void loading({bool coins = false}) {
    phase = coins ? StreakLostPhase.paying : StreakLostPhase.loading;
    _sync();
  }

  void retry() {
    phase = noAds ? StreakLostPhase.offer : StreakLostPhase.retry;
    _detail(
      noAds
          ? state.restoreMessage(noAds: true)
          : 'No video right now. Your streak waits for you.',
    );
    _sync();
  }

  void restoreMoment(int days, {required bool flewToday}) {
    phase = StreakLostPhase.restoring;
    _moment = 0;
    // Keep the displayed total consistent with the restored n + k state
    // (PRD G2 RESTORE); review round 2 explicitly permits this presentation.
    _restoredDays = days;
    card.add(
      restoreRays = NoAdsCelebrationRays(
        rayCenter: const Offset(200, 41.5),
        motion: () => !game.reduceMotion,
        position: Vector2(0, 46),
        size: Vector2(Config.p1PopupWidth, cardHeight - 46),
        priority: -1,
      ),
    );
    title.text = 'STREAK RESTORED!';
    title.fontSize = 17;
    lostLine.removeFromParent();
    card.add(
      MenuParagraph(
        'Your $days-day streak is back!',
        fontSize: 14,
        color: Config.menuPink,
        maxWidth: 248,
        position: Vector2(16, 173),
      ),
    );
    _detail(flewToday ? '' : 'Fly one run today to keep it going.');
    game.sound.play(Sfx.rvIgnite);
    if (!game.reduceMotion) {
      card.add(
        ConfettiBurst.burst(
          origin: const Offset(200, 100),
          count: 24,
          speed: 75,
          up: 90,
          driftX: 0,
          priority: 12,
        ),
      );
    }
    _sync();
  }

  void giveUpMoment() {
    phase = StreakLostPhase.givingUp;
    _moment = 0;
    game.sound.play(Sfx.skClose);
    _sync();
  }

  void _sync() {
    final poor =
        noAds &&
        !resolving &&
        phase != StreakLostPhase.paying &&
        !state.restorePayment(noAds: true, coins: balance()).enabled;
    action.text = switch (phase) {
      StreakLostPhase.loading => 'LOADING VIDEO',
      StreakLostPhase.retry => 'TRY AGAIN',
      _ =>
        noAds
            ? 'RESTORE · ${state.restorePayment(noAds: true, coins: balance()).coins}'
            : 'RESTORE',
    };
    action.fontSize = phase == StreakLostPhase.loading ? 18 : 22;
    restoreButton.color = poor ? const Color(0xFFCFCFCF) : Config.menuPink;
    paymentIcon.opacity = phase == StreakLostPhase.loading || resolving ? 0 : 1;
    _spinner.visible = phase == StreakLostPhase.loading;
    if (poorLine?.text != (poor ? 'You have ${balance()} coins.' : null)) {
      poorLine?.removeFromParent();
      poorLine = null;
      if (poor) {
        card.add(
          poorLine = MenuParagraph(
            'You have ${balance()} coins.',
            fontSize: 11.5,
            color: const Color(0xFF9A9A9A),
            maxWidth: 248,
            position: Vector2(16, 302),
          ),
        );
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += game.reduceMotion ? 0 : dt;
    _oldFlame.still = _newFlame.still = game.reduceMotion;
    _spinner.angle = _time * 5;
    arrows.scale.setAll(game.reduceMotion ? 1 : 1 + .08 * math.sin(_time * 5));
    if (!resolving) {
      _sync();
      return;
    }
    _moment += dt;
    final t = (_moment / .55).clamp(0.0, 1.0);
    if (phase == StreakLostPhase.restoring) {
      _newFlame.lit = game.reduceMotion ? 1 : t;
      newCount.text =
          '${game.reduceMotion ? _restoredDays : (_restoredDays * t).round()}';
      newCount.color = const Color(0xFFFF7A1A);
      _actions.opacity = game.reduceMotion
          ? 0
          : 1 - ((_moment - .4) / .2).clamp(0.0, 1.0);
      final pop = game.reduceMotion ? 1.0 : 1 + .28 * math.sin(t * math.pi);
      _newFlame.scale.setAll(pop);
      newCount.scale.setAll(pop);
    } else {
      _oldFlame.lit = game.reduceMotion ? 0 : 1 - t;
      oldCount.color = Color.lerp(
        const Color(0xFFFF7A1A),
        const Color(0xFFB5B5B5),
        t,
      )!;
    }
    if (!_done && _moment >= (phase == StreakLostPhase.restoring ? 1.15 : .6)) {
      _done = true;
      onMomentDone();
    }
  }
}

/// A bottom-up clip of the shared flame, never a second flame drawing.
class _FlameWipe extends PositionComponent {
  _FlameWipe({required double side, required this.lit, super.position})
    : grey = StreakFlame(side: side, lit: false),
      fire = StreakFlame(side: side),
      super(size: Vector2(side, side * 1.25));
  final StreakFlame grey;
  final StreakFlame fire;
  double lit;
  bool still = false;
  @override
  void update(double dt) {
    super.update(dt);
    fire.still = still;
    fire.update(dt);
  }

  @override
  void render(Canvas canvas) {
    grey.render(canvas);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, height * (1 - lit), width, height * lit));
    fire.render(canvas);
    canvas.restore();
  }
}

class _LoadingSpinner extends PositionComponent {
  _LoadingSpinner({super.position})
    : super(size: Vector2.all(16), anchor: Anchor.center);
  bool visible = false;
  final _paint = Paint()
    ..color = Config.menuSoft
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  @override
  void render(Canvas canvas) {
    if (visible) canvas.drawArc(size.toRect(), 0, math.pi * 1.5, false, _paint);
  }
}

class _ActionGroup extends PositionComponent with GroupOpacity {}
