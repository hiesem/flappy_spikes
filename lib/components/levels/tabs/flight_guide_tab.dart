import 'dart:ui' show Image;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../../game/config.dart';
import '../../../progression/flight_guide.dart';
import '../../../run/config/puzzle_config.dart';
import '../../../run/effects/life_icons.dart';
import '../../../run/effects/spike_teeth.dart';
import '../../../run/hoops/ring_painter.dart';
import '../../../run/hoops/kinds/bullseye.dart';
import '../../../run/hoops/kinds/spring.dart';
import '../../../run/hoops/kinds/fever.dart';
import '../../../run/hoops/kinds/lucky_spin.dart';
import '../../../run/pickups/capsule.dart';
import '../../../run/pickups/comet_star.dart';
import '../../../run/pickups/egg_pickup.dart';
import '../../../run/pickups/feather_pickup.dart';
import '../../../run/pickups/jar_pickup.dart';
import '../../../run/pickups/piggy_pickup.dart';
import '../../../run/pickups/puzzle_piece_pickup.dart';
import '../../../run/run_state.dart';
import '../levels_screen.dart';
import 'levels_tabs.dart';

/// The shell owns selection, scrolling and the seen count.
class FlightGuideTab {
  static void install(LevelsScreen screen) {
    final rows = <Component>[];
    var y = 276.0;
    for (final group in [
      'HOOPS',
      'PICK-UPS',
      'POWER-UPS',
      'RIDES',
      'HAZARDS',
    ]) {
      final entries = flightGuideEntries
          .where((e) => e.group == group)
          .toList();
      rows.add(_GuideDivider(screen, group, entries, y));
      y += 34;
      for (final entry in entries) {
        rows.add(_GuideRow(screen, entry, y));
        y += 68;
      }
    }
    screen.installTabContent(
      LevelsTab.guide,
      header: _GuideHeader(screen),
      rows: rows,
      contentBottom: y + 40,
    );
  }
}

class _GuideHeader extends PositionComponent {
  _GuideHeader(this.screen);
  final LevelsScreen screen;
  Image? _badge;

  @override
  Future<void> onLoad() async {
    _badge = await screen.game.images.load('achievements/ach_birdwatcher.png');
  }

  @override
  void render(Canvas canvas) {
    final count = flightGuideMetCount(screen.game.storage.metElements);
    canvas.drawRect(
      Offset.zero & const Size(292, 84),
      Paint()..color = const Color(0xFFDFDFDF),
    );
    final gold = count == 32;
    final badge = _badge;
    if (badge != null) {
      canvas.drawImageRect(
        badge,
        Rect.fromLTWH(0, 0, badge.width.toDouble(), badge.height.toDouble()),
        const Rect.fromLTWH(0, 0, 84, 84),
        Paint()
          ..colorFilter = gold
              ? null
              : const ColorFilter.matrix([
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
      );
    }
    _text(
      canvas,
      'MET $count / 32',
      const Offset(94, 10),
      18,
      const Color(0xFF828282),
    );
    _text(
      canvas,
      gold ? 'ACHIEVEMENT EARNED' : 'MEET ALL 32 · ACHIEVEMENT',
      const Offset(94, 36),
      9,
      const Color(0xFF8F8F8F),
    );
    canvas.drawRect(
      const Rect.fromLTWH(94, 57, 186, 16),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(94, 57, 186 * count / 32, 16),
      Paint()..color = gold ? Config.menuGold : Config.menuPink,
    );
    _text(
      canvas,
      gold ? 'BIRDWATCHER ✓' : '${32 - count} TO BIRDWATCHER',
      const Offset(100, 59),
      9,
      const Color(0xFF555555),
    );
  }
}

class _GuideDivider extends PositionComponent {
  _GuideDivider(this.screen, this.group, this.entries, double y)
    : super(position: Vector2(14, y));
  final LevelsScreen screen;
  final String group;
  final List<GuideEntry> entries;
  @override
  void render(Canvas canvas) {
    final count = entries
        .where((e) => e.isMet(screen.game.storage.metElements))
        .length;
    _text(canvas, group, Offset.zero, 10.5, const Color(0xFF888888));
    _text(
      canvas,
      '$count / ${entries.length}',
      const Offset(254, 0),
      10,
      const Color(0xFF888888),
    );
  }
}

class _GuideRow extends PositionComponent {
  _GuideRow(this.screen, this.entry, double y)
    : super(position: Vector2(14, y));
  final LevelsScreen screen;
  final GuideEntry entry;
  Image? _rideBadge;

  @override
  Future<void> onLoad() async {
    if (entry.id.startsWith('portal_')) {
      _rideBadge = await screen.game.images.load(
        'achievements/ach_ride_${entry.id.substring(7)}.png',
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final met = entry.isMet(screen.game.storage.metElements);
    canvas.drawRect(
      Offset.zero & const Size(292, 62),
      Paint()..color = const Color(0xFFE6E6E6),
    );
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, 54, 54),
      Paint()..color = const Color(0xFFF4F4F4),
    );
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(4, 4, 54, 54));
    if (!met) {
      canvas.saveLayer(
        const Rect.fromLTWH(4, 4, 54, 54),
        Paint()
          ..colorFilter = const ColorFilter.mode(
            Color(0xFFBEBEBE),
            BlendMode.srcIn,
          ),
      );
    }
    final badge = _rideBadge;
    if (badge != null) {
      canvas.drawImageRect(
        badge,
        Rect.fromLTWH(0, 0, badge.width.toDouble(), badge.height.toDouble()),
        const Rect.fromLTWH(4, 4, 54, 54),
        Paint(),
      );
    } else {
      _art(canvas, entry);
    }
    if (!met) canvas.restore();
    canvas.restore();
    if (!met) {
      _text(canvas, '?', const Offset(23, 13), 26, const Color(0xFFA9A9A9));
    }
    _text(
      canvas,
      entry.nameFor(screen.game.storage.metElements),
      const Offset(68, 10),
      13.5,
      met ? const Color(0xFF828282) : const Color(0xFFAAAAAA),
    );
    _text(
      canvas,
      entry.ruleFor(screen.game.storage.metElements),
      const Offset(68, 27),
      10.5,
      const Color(0xFF8F8F8F),
      width: 214,
      body: true,
    );
  }
}

void _text(
  Canvas canvas,
  String text,
  Offset at,
  double size,
  Color color, {
  double width = 210,
  bool body = false,
}) {
  final p = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: body ? 'Fredoka' : Config.uiFont,
        fontSize: size,
        color: color,
        fontWeight: body ? FontWeight.w600 : FontWeight.normal,
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: width);
  p.paint(canvas, at);
}

void _art(Canvas canvas, GuideEntry e) {
  const c = Offset(31, 31);
  switch (e.id) {
    case 'bullseye':
      RingPainter.paintBoth(canvas, centre: c, opening: 34);
      BullseyeHoopKind.paintTarget(canvas, c, guide: const Color(0xFF828282));
    case 'spring':
      RingPainter.paintBoth(
        canvas,
        centre: c,
        opening: 25,
        colors: SpringHoopKind.colors,
      );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      SpringHoopKind.paintDecor(canvas, 25, -1, 0, 0);
      canvas.restore();
    case 'fever':
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(.65);
      FeverRingPainter.paint(canvas, 34, 0, 1, 0, front: false);
      FeverRingPainter.paint(canvas, 34, 0, 1, 0, front: true);
      canvas.restore();
    case 'lucky_spin':
      canvas.save();
      canvas.translate(c.dx, c.dy + 12);
      canvas.scale(.55);
      RingPainter.paintBoth(canvas, centre: Offset.zero, opening: 25);
      LuckySpinHoopKind.paintWheel(
        canvas,
        const Offset(0, -18),
        0,
        const Color(0xFF828282),
      );
      canvas.restore();
    case 'train':
      for (final dx in [-12.0, 0.0, 12.0]) {
        canvas.save();
        canvas.translate(c.dx + dx, c.dy);
        canvas.scale(.55);
        RingPainter.paintBoth(canvas, centre: Offset.zero, opening: 34);
        canvas.restore();
      }
    case 'pair':
      for (final dy in [-13.0, 13.0]) {
        canvas.save();
        canvas.translate(c.dx, c.dy + dy);
        canvas.scale(.55);
        RingPainter.paintBoth(canvas, centre: Offset.zero, opening: 28);
        canvas.restore();
      }
    case 'big_hoops':
      RingPainter.paintBoth(
        canvas,
        centre: c,
        opening: 36,
        colors: RingColors.gold,
      );
    case 'heart':
      LifeIcons.paintHeart(canvas, c, 32, shine: true);
    case 'shield':
      LifeIcons.paintShield(canvas, c, 32);
    case 'egg':
      EggArt.paint(canvas, c);
    case 'piggy':
      PiggyArt.paint(canvas, c, 1);
    case 'jar':
      JarArt.paint(canvas, c, 1);
    case 'feather':
      FeatherArt.paintAt(canvas, c, 1, 0);
    case 'puzzle_piece':
      canvas.save();
      canvas.translate(c.dx, c.dy);
      PuzzleArt.paintPieceCentred(canvas, 0, PuzzleConfig.themes.first);
      canvas.restore();
    case 'hourglass':
      CapsuleArt.paintCapsule(canvas, c, TimedPowerup.hourglass, 0);
    case 'mini_bird':
      CapsuleArt.paintCapsule(canvas, c, TimedPowerup.mini, 0);
    case 'coin_frenzy':
      CapsuleArt.paintCapsule(canvas, c, TimedPowerup.frenzy, 0);
    case 'comet' || 'star_trail':
      CometStar.paintStar(canvas, c);
    case 'spikes' || 'squeeze':
      canvas.save();
      canvas.translate(4, 10);
      SpikeTeethPainter.paint(
        canvas,
        width: 54,
        color: const Color(0xFF828282),
        reach: 30,
      );
      canvas.restore();
    default:
      RingPainter.paintBoth(
        canvas,
        centre: c,
        opening: 34,
        tilt: e.id == 'angled_ring' ? .3 : 0,
      );
  }
}
