import '../../director/plans.dart';
import '../ride_theme.dart';
import 'cannon.dart';
import 'pinball.dart';
import 'sea.dart';
import 'space.dart';
import 'storm.dart';
import 'volcano.dart';

/// A fresh theme for [id] (each ride keeps its own state; PRD-2 §3.12 the
/// six rides: cannon + 5 themed).
RideTheme rideThemeFor(RideId id) => switch (id) {
  RideId.cannon => CannonTheme(),
  RideId.space => SpaceTheme(),
  RideId.volcano => VolcanoTheme(),
  RideId.sea => SeaTheme(),
  RideId.pinball => PinballTheme(),
  RideId.storm => StormTheme(),
};
