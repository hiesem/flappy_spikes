import 'dart:ui';
import 'spikes_v26.dart';
import 'phoenixring_v26.dart';
import 'legend_v26.dart';
import 'thread_v26.dart';
import 'constellation_v26.dart';
import 'fireflies_v26.dart';
import 'skycrown_v26.dart';
import 'nest_v26.dart';

/// A hoop uses size as its vertical radius; trails and hats use it as scale.
/// The front flag, horizontal radius and line width apply to hoops only.
typedef F10c1Painter =
    void Function(
      Canvas canvas,
      Offset center,
      double size,
      double time, {
      bool front,
      double? rx,
      double lineWidth,
    });

const Map<String, F10c1Painter> f10c1Painters = {
  'spikes': paintSpikesV26,
  'phoenixring': paintPhoenixringV26,
  'legend': paintLegendV26,
  'thread': paintThreadV26,
  'constellation': paintConstellationV26,
  'fireflies': paintFirefliesV26,
  'skycrown': paintSkycrownV26,
  'nest': paintNestV26,
};
