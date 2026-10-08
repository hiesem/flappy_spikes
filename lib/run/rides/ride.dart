import '../director/plans.dart';
import '../run_context.dart';

export '../director/plans.dart' show RideId, RideKind;

/// A ride (comet boost §3.8, portal roller-coaster §3.12; ARCH §1.8).
abstract class Ride {
  RideKind get kind;

  /// The portal ride's theme (null for the comet).
  RideId? get rideId => null;
  void start(RunContext c);
  void update(double dt);
  bool get done;
}
