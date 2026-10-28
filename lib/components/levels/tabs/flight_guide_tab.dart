import 'dart:async';
import 'dart:ui' show Image, ImageFilter;
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../../game/config.dart';
import '../../../game/flappy_game.dart';
import '../../../run/director/plans.dart';
import '../../../run/elements.dart';
import '../../../run/hoops/hoop.dart';
import '../../../run/hoops/motion/motion_guide.dart';
import '../../../run/hoops/kinds/pair/gift_box.dart';
import '../../../run/hoops/kinds/saw/saw_kind.dart';
import '../../../run/hoops/kinds/switch/switch_kind.dart';
import '../../../run/pickups/star_trail.dart';
import '../../../run/rides/ride_theme.dart';
import '../../../run/rides/themes/themes.dart';
import '../../../run/rides/themes/space.dart';
import '../../../run/rides/themes/storm.dart';
import '../../../run/run_controller.dart';
import '../../../run/run_setup.dart';
import '../../../skins/art/look_painter.dart';
import '../../../skins/look.dart';
import '../../../progression/flight_guide.dart';
import '../../../run/config/puzzle_config.dart';
import '../../../run/effects/life_icons.dart';
import '../../../run/effects/spike_teeth.dart';
import '../../../run/hoops/ring_painter.dart';
import '../../../run/hoops/kinds/bullseye.dart';
import '../../../run/hoops/kinds/spring.dart';
import '../../../run/hoops/kinds/fever.dart';
import '../../../run/hoops/kinds/lucky_spin.dart';
import '../../../run/hoops/kinds/train.dart';
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
    final art = FlightGuideArt(screen.game);
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
        rows.add(_GuideRow(screen, entry, art, y));
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
  void onLoad() {
    // Image decoding must not hold the Levels screen's lifecycle open.
    unawaited(_loadBadge());
  }

  Future<void> _loadBadge() async {
    try {
      _badge = await screen.game.images.load(
        'achievements/ach_birdwatcher.png',
      );
    } catch (error) {
      debugPrint('Flight guide badge failed to load: $error');
    }
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
  _GuideRow(this.screen, this.entry, this.art, double y)
    : super(position: Vector2(14, y));
  final LevelsScreen screen;
  final GuideEntry entry;
  final FlightGuideArt art;

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
    art.paint(canvas, entry);
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

class FlightGuideArt {
  FlightGuideArt(this.game);
  final FlappySpikesGame game;
  // Only the switch and saw painters need a run context. Construct it on
  // first use, after GUIDE is opened, and never mount it as a live run.
  RunController? _preview;
  RunController get preview => _preview ??= RunController(
    game: game,
    setup: RunSetup(seed: 7, viewHeight: game.viewHeight),
  );

  @visibleForTesting
  bool get previewCreated => _preview != null;
  final Map<RideId, (RideTheme, RideView)> _rides = {};
  late final TrainGroup _train = () {
    final group = TrainGroup(spec: const TrainSpec(dir: -1, dx: 24, dy: 12));
    for (var i = 0; i < 3; i++) {
      group.hoops.add(
        Hoop(
          kind: TrainHoopKind(),
          plan: SlotPlan(
            index: i,
            kind: HoopKindId.train,
            element: ElementId.train,
            trackX: i * 24.0,
            centreY: i * -12.0,
            opening: 24,
            advance: 300,
          ),
        ),
      );
    }
    group.passedRings.add(0);
    return group;
  }();
  late final _switchHoop = hoop(HoopKindId.switchRing, ElementId.switchRing);
  late final _switchArt = SwitchDesignArt.of(SwitchDesign.laserGate);
  late final _switchState = SwitchRingState(
    _switchHoop,
    preview.ctx,
    _switchArt,
  );
  late final _switchPickup = SwitchPickup(
    const GapItemPlan(kind: ElementId.switchRing, trackX: 0),
    SwitchDesign.laserGate,
    _switchHoop,
  );
  late final _sawArt = SawDesignArt.of(SawDesign.liveWire);
  late final _sawState = SawRingState(
    hoop(HoopKindId.saw, ElementId.saw),
    preview.ctx,
    _sawArt,
    seed: 7,
  );

  (RideTheme, RideView) ride(RideId id) => _rides.putIfAbsent(id, () {
    final theme = rideThemeFor(id);
    final view = RideView(
      path: theme.buildPath(),
      h: 711,
      rnd: math.Random(7),
      cue: (_) {},
    );
    theme.init(view);
    return (theme, view);
  });

  Hoop hoop(HoopKindId kind, ElementId element) => Hoop(
    kind: kind == HoopKindId.saw ? SawHoopKind() : SwitchRingKind(),
    plan: SlotPlan(
      index: 0,
      kind: kind,
      element: element,
      trackX: 0,
      centreY: 0,
      opening: 65,
      advance: 300,
    ),
  );

  void bird(Canvas canvas, Offset at, double scale) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(scale);
    LookPainter.paint(canvas, Look.defaults);
    canvas.restore();
  }

  void rideArt(Canvas canvas, RideId id) {
    final (theme, v) = ride(id);
    canvas.save();
    switch (id) {
      case RideId.space:
        canvas.translate(31, 28);
        canvas.scale(.63);
        SpaceTheme.rocket(canvas, Offset.zero, 0, fire: true, t: 0);
      case RideId.sea:
        // The first fish school is placed by SeaTheme.init from this seed.
        // Position its real painter in the thumbnail, with no copied fish art.
        final random = math.Random(23);
        final offset = 90 + random.nextDouble() * 80;
        random.nextDouble(); // school size
        final phase = random.nextDouble() * 6;
        final point = v.path.at(700);
        final heading = v.path.headingAt(700);
        final x = point.x - math.sin(heading) * offset;
        final y = point.y + math.cos(heading) * offset;
        final cam = Vector2(x - 300 + math.sin(phase) * 6 - 30, y + 4 - 30);
        canvas.translate(31, 31);
        canvas.scale(1.35);
        canvas.translate(-30, -30);
        theme.paintWorld(canvas, v, cam);
      case RideId.cannon:
        v.phase = RidePhase.exit;
        v.camEnd = Vector2(v.path.end.x, v.path.end.y);
        canvas.translate(31, 7);
        canvas.scale(.33);
        theme.paintExitFront(canvas, v, 0, Offset.zero);
      case RideId.pinball:
        // Frame one real bumper and one real flipper from the ride scene.
        final station = 40 * 70 * math.pi / 180 + 520;
        final point = v.path.at(station + 30);
        final heading = v.path.headingAt(station + 30);
        final bumper = Vector2(
          point.x + math.cos(heading) * 36,
          point.y + math.sin(heading) * 36,
        );
        canvas.save();
        canvas.translate(41, 19);
        canvas.scale(.48);
        canvas.translate(-160, -300);
        theme.paintWorld(canvas, v, bumper - Vector2(160, 300));
        canvas.restore();
        canvas.translate(18, 43);
        canvas.scale(.28);
        canvas.translate(-100, -600);
        theme.paintExit(canvas, v, .6, Offset.zero);
      case RideId.volcano:
        canvas.translate(31, 22);
        canvas.scale(.22);
        canvas.translate(-160, -560);
        theme.paintExit(canvas, v, 0, Offset.zero);
      case RideId.storm:
        canvas.translate(31, 31);
        canvas.scale(.14);
        final p = v.path.points[60];
        theme.paintWorld(canvas, v, Vector2(v.path.axisX, p.y));
        canvas.scale(2.5);
        StormTheme.paintUmbrella(canvas, const Offset(0, 65), 0, 1);
    }
    canvas.restore();
  }

  void paint(Canvas canvas, GuideEntry e) {
    const c = Offset(31, 31);
    switch (e.id) {
      case 'normal_hoop':
        RingPainter.paintBoth(
          canvas,
          centre: const Offset(36, 31),
          opening: 34,
        );
        bird(canvas, const Offset(19, 31), .35);
      case 'angled_ring':
        RingPainter.paintBoth(
          canvas,
          centre: const Offset(37, 31),
          opening: 34,
          tilt: .42,
        );
        bird(canvas, const Offset(13, 35), .28);
      case 'moving_ring':
        canvas.save();
        canvas.translate(36, 31);
        canvas.scale(.65);
        MotionGuidePainter.paint(
          canvas,
          const MotionSpec(type: MotionType.rail, halfTravel: 30),
          opening: 25,
          color: const Color(0xFFB0006B),
        );
        RingPainter.paintBoth(canvas, centre: Offset.zero, opening: 25);
        canvas.restore();
      case 'switch_ring':
        canvas.save();
        canvas.translate(39, 31);
        canvas.scale(.52);
        _switchArt.paintBack(canvas, _switchState);
        _switchArt.paintFront(canvas, _switchState);
        canvas.restore();
        canvas.save();
        canvas.translate(13, 31);
        canvas.scale(.34);
        _switchArt.paintSwitch(canvas, _switchPickup);
        canvas.restore();
      case 'saw':
        canvas.save();
        canvas.translate(31, 31);
        canvas.scale(.55);
        _sawArt.paintBack(canvas, _sawState);
        _sawArt.paintFront(canvas, _sawState);
        canvas.restore();
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
        canvas.save();
        canvas.translate(19, 37);
        canvas.scale(.5);
        TrainHoopKind.paintTrack(
          canvas,
          _train.hoops.first,
          _train,
          const Color(0xFF828282),
        );
        for (var i = 0; i < _train.hoops.length; i++) {
          final h = _train.hoops[i];
          RingPainter.paintBoth(
            canvas,
            centre: Offset(h.position.x, h.position.y),
            opening: h.opening,
            colors: i == 0 ? RingColors.gold : RingColors.pink,
          );
        }
        canvas.restore();
      case 'pair':
        for (final dy in [-13.0, 13.0]) {
          canvas.save();
          canvas.translate(c.dx, c.dy + dy);
          canvas.scale(.55);
          RingPainter.paintBoth(
            canvas,
            centre: Offset.zero,
            opening: 28,
            colors: dy < 0
                ? const RingColors(Color(0xFF1E88E5), Color(0xFF0D47A1))
                : const RingColors(Color(0xFF8E44FF), Color(0xFF5420B0)),
          );
          canvas.scale(.45);
          GiftBox.paint(canvas, dy < 0 ? PairReward.shield : PairReward.comet);
          canvas.restore();
        }
      case 'big_hoops':
        canvas.save();
        canvas.translate(15, 36);
        canvas.scale(.5);
        RingPainter.paintBoth(canvas, centre: Offset.zero, opening: 26);
        canvas.restore();
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
        // A thin dark edge keeps the cream run egg visible on the pale tile.
        canvas.saveLayer(
          const Rect.fromLTWH(4, 4, 54, 54),
          Paint()
            ..imageFilter = ImageFilter.dilate(radiusX: 1.2, radiusY: 1.2)
            ..colorFilter = const ColorFilter.mode(
              Color(0xFFB09A73),
              BlendMode.srcIn,
            ),
        );
        EggArt.paint(canvas, c, scale: 2.0, cracks: 1);
        canvas.restore();
        EggArt.paint(canvas, c, scale: 2.0, cracks: 1);
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
      case 'star_trail':
        final trail = StarTrail(
          const GapItemPlan(
            kind: ElementId.starTrail,
            trackX: 0,
            toTrackX: 80,
            y: 0,
            toY: 0,
          ),
        );
        canvas.save();
        canvas.translate(c.dx, c.dy + 10);
        canvas.scale(.6);
        trail.render(canvas);
        canvas.restore();
      case 'comet':
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(-.65, .65);
        CometStar.paintStar(canvas, Offset.zero);
        canvas.restore();
      case 'portal_cannon' ||
          'portal_pinball' ||
          'portal_sea' ||
          'portal_space' ||
          'portal_storm' ||
          'portal_volcano':
        rideArt(canvas, RideId.fromStorageId(e.id.substring(7))!);
      case 'spikes' || 'squeeze':
        final reach = e.id == 'spikes' ? 11.0 : 19.0;
        canvas.save();
        canvas.translate(4, 4);
        SpikeTeethPainter.paint(
          canvas,
          width: 54,
          color: const Color(0xFF828282),
          reach: reach,
        );
        canvas.restore();
        canvas.save();
        canvas.translate(4, 58);
        canvas.scale(1, -1);
        SpikeTeethPainter.paint(
          canvas,
          width: 54,
          color: const Color(0xFF828282),
          reach: reach,
        );
        canvas.restore();
        bird(canvas, c, e.id == 'spikes' ? .30 : .20);
      default:
        throw StateError('Missing flight guide art: ${e.id}');
    }
  }
}
