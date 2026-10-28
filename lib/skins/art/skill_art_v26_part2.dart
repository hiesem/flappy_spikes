import 'dart:math' as math;
import 'package:flutter/painting.dart' show HSLColor;
import 'dart:ui';
import 'bird_art.dart';
import 'jackpot_v26.dart';
import 'magpie_v26.dart';
import 'prism_v26.dart';
import 'daynight_v26.dart';
import 'goggles_v26.dart';
import 'hoopchain_v26.dart';
import 'peacock_v26.dart';

/// Paints at game-clock time, in back then front passes in bird coordinates.
/// The three bird painters draw the body and tail only. F10a must call
/// paintBirdFace after the front pass, with the corresponding face spec below;
/// that shared master owns flap, blink, eye and beak rendering.
typedef SkillArtPainterV26 =
    void Function(Canvas canvas, BirdShape shape, double time, bool back);

const Map<String, SkillArtPainterV26> f10c2Painters = {
  'jackpot': paintJackpotV26,
  'magpie': paintMagpieV26,
  'prism': paintPrismV26,
  'daynight': paintDaynightV26,
  'goggles': paintGogglesV26,
  'hoopchain': paintHoopchainV26,
  'peacock': paintPeacockV26,
};

/// Face colours for the three skill birds, to be passed to paintBirdFace.
BirdSpec f10c2BirdFace(String id, BirdShape shape, double time) {
  switch (id) {
    case 'magpie':
      final h = 215 + math.sin(time * 1.7) * 30;
      return BirdSpec(
        id,
        shape.kind,
        c: const Color(0xff1c1c1c),
        d: HSLColor.fromAHSL(1, h % 360, .72, .42).toColor(),
        bk: const Color(0xff3a3a3a),
      );
    case 'prism':
      return BirdSpec(
        id,
        shape.kind,
        c: const Color(0xffeaf8ff),
        d: const Color(0x6b6eb9e4),
        bk: const Color(0xff8fd3f4),
      );
    case 'daynight':
      return BirdSpec(
        id,
        shape.kind,
        c: const Color(0xff4fc3f7),
        d: const Color(0x29000000),
        bk: const Color(0xffffb529),
      );
    default:
      throw ArgumentError.value(id, 'id', 'Not a skill bird');
  }
}
