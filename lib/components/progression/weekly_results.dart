import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../progression/weekly_course.dart';
import '../home/menu_primitives.dart';

/// Eligibility for the once-per-local-day results entry (G5, O26).
bool showWeeklyHint({
  required bool weekly,
  required bool counts,
  required int games,
  required int bestHoops,
  required int weeklyBest,
  required int shownDay,
  required int today,
  required double height,
  required bool missionMoved,
}) =>
    !weekly &&
    counts &&
    WeeklyCourse.unlocked(gamesPlayed: games, bestHoops: bestHoops) &&
    weeklyBest < 120 &&
    shownDay < today &&
    !(height <= 568 && missionMoved);

/// The hint follows any mission and first-win lines without covering NEXT.
double weeklyHintTop({required bool missionMoved, required bool firstWin}) =>
    (missionMoved ? 589.0 : 565.0) + (firstWin ? 20.0 : 0.0);

String weeklyHintText(int best) => best == 0
    ? "Try this week's course →"
    : "Try this week's course → beat hoop $best";

/// The weekly tier bar animates from the previous best and reports each new tier.
class WeeklyResultsTiers extends PositionComponent {
  WeeklyResultsTiers({
    required this.best,
    required this.before,
    required this.paid,
    required this.earned,
    required this.coin,
    required this.onTier,
  }) : super(position: Vector2(0, 292), size: Vector2(320, 124));
  final int best, before;
  final Set<int> paid, earned;
  final Sprite coin;
  final void Function(int tier, int coins, double x) onTier;
  static const tiers = <int, int>{15: 40, 30: 80, 60: 150, 120: 300};
  final _nodes = <int, _WeeklyTier>{};
  final _announced = <int>{};
  double elapsed = 0;
  double get shownBest {
    final u = ((elapsed - 1.3) / 1.3).clamp(0.0, 1.0);
    return before +
        (math.max(best, before) - before) * (1 - math.pow(1 - u, 3).toDouble());
  }

  static double positionFor(double hoops) {
    const points = [
      (0.0, 30.0),
      (15.0, 52.0),
      (30.0, 124.0),
      (60.0, 196.0),
      (120.0, 268.0),
      (200.0, 290.0),
    ];
    for (var i = 1; i < points.length; i++) {
      if (hoops <= points[i].$1) {
        final a = points[i - 1], b = points[i];
        return a.$2 +
            (b.$2 - a.$2) * ((hoops - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
      }
    }
    return 290;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      MenuText(
        "THIS WEEK'S REWARDS · BEST HOOP",
        fontSize: 10.5,
        color: const Color(0xff8a8a8a),
        position: Vector2(160, 0),
        anchor: Anchor.topCenter,
      ),
    );
    var i = 0;
    for (final entry in tiers.entries) {
      final node = _WeeklyTier(
        tier: entry.key,
        coins: entry.value,
        coin: coin,
        x: 52.0 + i++ * 72,
        got: paid.contains(entry.key) && !earned.contains(entry.key),
      );
      _nodes[entry.key] = node;
      add(node);
    }
    final next = tiers.entries.where((e) => best < e.key).firstOrNull;
    add(
      MenuText(
        next == null
            ? 'ALL TIERS DONE THIS WEEK!'
            : 'NEXT: HOOP ${next.key} → +${next.value}',
        fontSize: 10.5,
        color: Config.menuPlum,
        position: Vector2(160, 108),
        anchor: Anchor.center,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    for (final entry in tiers.entries) {
      if (earned.contains(entry.key) &&
          shownBest >= entry.key &&
          _announced.add(entry.key)) {
        _nodes[entry.key]?.reach();
        onTier(
          entry.key,
          entry.value,
          52.0 + tiers.keys.toList().indexOf(entry.key) * 72,
        );
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(30, 45, 260, 6),
      Paint()..color = Config.menuSoft,
    );
    canvas.drawRect(
      Rect.fromLTWH(30, 45, positionFor(shownBest) - 30, 6),
      Paint()..color = Config.menuPink,
    );
  }
}

class _WeeklyTier extends PositionComponent {
  _WeeklyTier({
    required this.tier,
    required this.coins,
    required this.coin,
    required double x,
    required this.got,
  }) : super(position: Vector2(x, 48), size: Vector2.zero());
  final int tier, coins;
  final Sprite coin;
  bool got;
  double? popAge;
  late RectangleComponent box;
  late MenuText number;
  late MenuText check;

  void reach() {
    got = true;
    popAge = 0;
    _apply();
  }

  void _apply() {
    box.paint.color = got ? Config.menuPink : const Color(0xffffffff);
    number.color = got ? Config.menuSoft : const Color(0xffa0a0a0);
    check.color = got ? Config.menuGold : const Color(0x00000000);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    box = RectangleComponent(
      position: Vector2(-20, -20),
      size: Vector2.all(40),
    );
    number = MenuText(
      '$tier',
      fontSize: 16,
      color: Config.menuPlum,
      anchor: Anchor.center,
    );
    check = MenuText(
      '✓',
      fontSize: 11,
      color: Config.menuGold,
      position: Vector2(17, -20),
      anchor: Anchor.center,
    );
    addAll([
      box,
      number,
      check,
      MenuText(
        '+$coins',
        fontSize: 12,
        color: Config.menuPlum,
        position: Vector2(-3, 26),
        anchor: Anchor.topRight,
      ),
      MenuIcon(coin, size: Vector2.all(12), position: Vector2(1, 26)),
    ]);
    _apply();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final age = popAge;
    if (age == null) return;
    popAge = age + dt;
    final u = (popAge! / .3).clamp(0.0, 1.0);
    scale.setAll(1 + .3 * math.sin(math.pi * u));
    if (u == 1) popAge = null;
  }
}
