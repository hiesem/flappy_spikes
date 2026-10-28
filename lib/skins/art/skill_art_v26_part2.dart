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
