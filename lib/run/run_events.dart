import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../menu/wallet.dart';
import 'director/plans.dart';
import 'elements.dart';
import 'hoops/hoop.dart';
import 'mistakes.dart';
import 'pickups/pickup.dart';
import 'pickups/star_trail.dart';
import 'run_setup.dart';
import 'run_state.dart';
import 'run_summary.dart';

/// Typed synchronous event bus of a run (ARCH §2.4). Events are delivered
/// in order, from the update loop. A throwing handler is caught and
/// debug-printed; it never breaks the run.
class RunEvents {
  final Map<Type, List<Function>> _handlers = {};
  final List<void Function(RunEvent)> _any = [];

  /// Every event, in order (tests and the debug overlay).
  final List<RunEvent> log = [];

  /// Keep [log] (tests); off by default to avoid growth in long runs.
  bool recordLog = false;

  void on<T extends RunEvent>(void Function(T e) handler) =>
      (_handlers[T] ??= []).add(handler);

  void off<T extends RunEvent>(void Function(T e) handler) =>
      _handlers[T]?.remove(handler);

  /// Listens to every event.
  void onAny(void Function(RunEvent e) handler) => _any.add(handler);

  void offAny(void Function(RunEvent e) handler) => _any.remove(handler);

  void emit(RunEvent e) {
    if (recordLog) log.add(e);
    final list = _handlers[e.runtimeType];
    if (list != null) {
      for (final h in List.of(list)) {
        try {
          (h as dynamic)(e);
        } catch (err, st) {
          debugPrint('RunEvents: ${e.runtimeType} handler threw $err\n$st');
        }
      }
    }
    for (final h in List.of(_any)) {
      try {
        h(e);
      } catch (err) {
        debugPrint('RunEvents: any-handler threw $err');
      }
    }
  }

  void clear() {
    _handlers.clear();
    _any.clear();
  }
}

/// The event catalogue (ARCH §2.4). A WP that needs a new event appends it
/// in its region at the end of this file.
sealed class RunEvent {
  const RunEvent();
}

class RunStarted extends RunEvent {
  const RunStarted(this.setup);
  final RunSetup setup;
}

class HoopSpawned extends RunEvent {
  const HoopSpawned(this.hoop, this.plan);
  final Hoop hoop;
  final SlotPlan plan;
}

/// [onScreen] = it entered the screen (counts as met, §3.0.8).
class ElementSpawned extends RunEvent {
  const ElementSpawned(this.element, {this.onScreen = true});
  final ElementId element;
  final bool onScreen;
}

class HoopPassed extends RunEvent {
  const HoopPassed(
    this.hoop, {
    this.ring = 0,
    this.perfect = false,
    this.clean = false,
    this.rimTouched = false,
    this.bullseye = false,
    this.duringRide = false,
    this.trainK,
  });
  final Hoop? hoop;
  final int ring;
  final bool perfect;

  /// PRD-2.2 §11 a clean off-centre pass: no rim touched, outside the
  /// perfect zone (non-perfect, not a graze).
  final bool clean;
  final bool rimTouched;
  final bool bullseye;
  final bool duringRide;

  /// Ring number in a train (0..2), else null.
  final int? trainK;
}

class RimTouched extends RunEvent {
  const RimTouched(this.hoop, this.point, this.normal);
  final Hoop hoop;
  final Vector2 point;
  final Vector2 normal;
}

class HoopMissed extends RunEvent {
  const HoopMissed(this.hoop);
  final Hoop hoop;
}

class ClosedSwitchReached extends RunEvent {
  const ClosedSwitchReached(this.hoop);
  final Hoop hoop;
}

/// SPEC WP-3d: a saw ring or a closed switch ring whose mistake a shield /
/// extra life saved counts as passed with no score (`passes`,
/// `hoopsPassed`, the colour stage and the hoop goals move; no points,
/// coins or streak). Emitted after the counters moved.
class SavedHoopPassed extends RunEvent {
  const SavedHoopPassed(this.hoop);
  final Hoop hoop;
}

class PickupCollected extends RunEvent {
  const PickupCollected(this.element, this.pickup);
  final ElementId element;
  final Pickup? pickup;
}

/// A piggy coin missed / a firefly escaped.
class PickupEscaped extends RunEvent {
  const PickupEscaped(this.element);
  final ElementId element;
}

class ScoreChanged extends RunEvent {
  const ScoreChanged(this.oldScore, this.newScore, {this.flags = 0});
  final int oldScore;
  final int newScore;

  /// `PointFlags` (ride / train / gift).
  final int flags;
}

class CoinsEarned extends RunEvent {
  const CoinsEarned(this.amount, this.source, {this.eggX2 = false});

  /// After the chick's ×2.
  final int amount;
  final CoinSource source;
  final bool eggX2;
}

/// PRD-2.2 §11: [clean] = a clean off-centre pass reset the streak.
enum StreakCause { pass, graze, clean, save, death, fever, ride }

class StreakChanged extends RunEvent {
  const StreakChanged(this.oldStreak, this.newStreak, this.cause);
  final int oldStreak;
  final int newStreak;
  final StreakCause cause;
}

class TierChanged extends RunEvent {
  const TierChanged(this.oldTier, this.newTier);
  final int oldTier;
  final int newTier;
}

class MistakeSaved extends RunEvent {
  const MistakeSaved(this.mistake, this.by);
  final Mistake mistake;

  /// 'shield' / 'extra_life'.
  final String by;
}

class RunDied extends RunEvent {
  const RunDied(this.mistake);
  final Mistake mistake;
}

class PowerupStarted extends RunEvent {
  const PowerupStarted(this.type, this.duration);
  final TimedPowerup type;
  final double duration;
}

class PowerupEnded extends RunEvent {
  const PowerupEnded(this.type);
  final TimedPowerup type;
}

class PowerupPaused extends RunEvent {
  const PowerupPaused(this.type);
  final TimedPowerup type;
}

class PowerupResumed extends RunEvent {
  const PowerupResumed(this.type);
  final TimedPowerup type;
}

class RideStarted extends RunEvent {
  const RideStarted(this.kind, [this.rideId]);
  final RideKind kind;
  final RideId? rideId;
}

class RideEnded extends RunEvent {
  const RideEnded(this.kind, [this.rideId]);
  final RideKind kind;
  final RideId? rideId;
}

class SqueezePhaseChanged extends RunEvent {
  const SqueezePhaseChanged(this.phase, this.index);
  final SqueezePhase phase;
  final int index;
}

/// How a revive was paid. PRD-2.3.1 §14 removed PRD-2.2 §7.7's `free`
/// (a NO ADS owner's first revive of a game).
enum ReviveKind { ad, coins }

class RevivePhoenixStarted extends RunEvent {
  const RevivePhoenixStarted(this.kind, this.price);
  final ReviveKind kind;
  final int price;
}

class Revived extends RunEvent {
  const Revived(this.kind, this.price);
  final ReviveKind kind;
  final int price;
}

class RunEnded extends RunEvent {
  const RunEnded(this.summary);
  final RunSummary summary;
}

/// §3.0.8 debug force of an element the director does not place (squeeze):
/// its feature reacts.
class DebugForced extends RunEvent {
  const DebugForced(this.element);
  final ElementId element;
}

// region anchors — append below (one region per WP)
// endregion anchors

// region WP-3c — FEVER (PRD-2 §3.19, §3.21 FEVER gift)
/// Lights the FEVER fire from another source than the FEVER ring (the pair
/// FEVER gift, Q59). `FeverFeature` reacts; the streak part of the gift is
/// the gift's owner's.
class FeverIgnite extends RunEvent {
  const FeverIgnite(this.source);

  /// Analytics source, e.g. 'pair'.
  final String source;
}

/// The bird caught fire ([lit]) or the fire went out (cause: graze /
/// extra_life / shield / death).
class FeverFireChanged extends RunEvent {
  const FeverFireChanged({required this.lit, this.cause});
  final bool lit;
  final String? cause;
}
// endregion WP-3c

// region WP-5b — versus (PRD-2 §3.13)
/// The run is ending: emitted by `RunController.endRun` right before the
/// summary is built, so the versus duel can credit its win / draw bonus
/// through `ctx.earn` and land in YOUR REWARD (ARCH §17).
class RunEnding extends RunEvent {
  const RunEnding();
}
// endregion WP-5b

// region WP-3d — pair gifts (PRD-2 §3.21)
/// Raises the perfect-pass streak to at least [value] (the pair FEVER
/// gift: "streak set to at least ×5", Q59). `StreakFeature` applies it
/// (tier change, banner); a higher streak is kept.
class StreakAtLeast extends RunEvent {
  const StreakAtLeast(this.value);
  final int value;
}

// endregion WP-3d
// region WP-3e — collectables (PRD-2 §3.26 Star Trail)
/// §3.0.3 a portal ride cleared an uncaught item on screen: it is gone
/// without counting as a miss / escape. The Piggy Bank and the Firefly Jar
/// drop the unresolved coins / fireflies from what they still owe (a bank
/// whose coins vanished can still resolve); nothing else listens.
class PickupCleared extends RunEvent {
  const PickupCleared(this.element, this.pickup);
  final ElementId element;
  final Pickup pickup;
}

// region WP-G2 — PRD-2.2 §15 / §27
/// A pickup component was created (the spawner; PRD-2.2 §15 on-screen
/// spawn checks).
class PickupSpawned extends RunEvent {
  const PickupSpawned(this.pickup);
  final Pickup pickup;
}

/// PRD-2.2 §27 an activity started (comet / portal ride, piggy / jar run,
/// capsule power-up).
class ActivityStarted extends RunEvent {
  const ActivityStarted(this.activity);
  final RunActivity activity;
}

/// PRD-2.2 §27 the activity ended (the 2-hoop cool-down starts).
class ActivityEnded extends RunEvent {
  const ActivityEnded(this.activity);
  final RunActivity activity;
}
// endregion WP-G2

/// The Star Trail's last star went behind the bird (§3.26): the trail is
/// over. `StarTrailFeature` reads [trail]'s caught count and either shows
/// PERFECT LINE and pays +5 coins, or shows the "n / 8" pop.
class StarTrailFinished extends RunEvent {
  const StarTrailFinished(this.trail);
  final StarTrail trail;
}
// endregion WP-3e

// region P231-E — achievements (PRD-2.3.1 §12.2)
/// The egg hatched into a chick (`EggFeature._hatch`).
class EggHatched extends RunEvent {
  const EggHatched();
}

/// A Firefly Jar was filled (`JarFeature._finish(full: true)`).
class JarFilled extends RunEvent {
  const JarFilled();
}

/// All 8 stars of a Star Trail were caught (PERFECT LINE).
class StarTrailPerfect extends RunEvent {
  const StarTrailPerfect();
}

/// The puzzle picture was completed (`puzzle_completed`).
class PuzzleCompleted extends RunEvent {
  const PuzzleCompleted();
}

/// A real FEVER started (the FEVER ring's perfect pass or the pair gift's
/// [FeverIgnite]), also when the bird already burned. Never for the
/// streak's on-fire state alone.
class FeverStarted extends RunEvent {
  const FeverStarted();
}
// endregion P231-E

// region PRD-2.6 WP-B — invisible showcase
// region P26-B2
/// A portal, comet or FEVER started, organically or from a showcase slot.
class HighlightStarted extends RunEvent {
  const HighlightStarted(this.id, {required this.scripted, required this.hoop});

  final String id;

  /// True only when the source is one of the frozen showcase plan slots.
  final bool scripted;

  /// The source hoop index (for a comet, the hoop carrying its star).
  final int hoop;
}
// endregion
// endregion
