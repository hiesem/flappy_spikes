import '../../game/sound.dart';
import '../director/plans.dart';
import '../elements.dart';
import '../rides/ride_theme.dart';
import '../rides/themes/themes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// PRD-2.2 §18.4 rare cues always play: `SoundService` creates a pool on
/// the first `play` and drops that play when the pool took longer than
/// `firstPlayLateLimit`, so a ride's cues (almost always first plays in a
/// session) were often silent. When a **portal hoop spawns** (seconds before
/// the bird reaches it) the pools of `pu_portal`, `pu_land`, `flap` and
/// every cue of the ride theme it opens are created without playing
/// ([SoundService.preload]; the theme is rolled with the portal slot). The
/// same is done, where cheap, for the comet star (`pu_comet_*`) and the
/// capsules (their power-up's cues). The pools stay bounded (PRD-2.2 §33.4):
/// a preload only creates a pool once, and the LRU cap still applies.
class SoundPreloadFeature extends RunFeature {
  RunContext? _c;

  /// Every preload request (tests).
  final List<Set<Sfx>> requests = [];

  /// PRD-2.2 §18.4 the cues a portal into [theme] needs.
  static Set<Sfx> portalCues(RideTheme theme) => {
    Sfx.puPortal,
    Sfx.puLand,
    Sfx.flap,
    ...theme.sounds.values,
  };

  /// PRD-2.2 §18.4 the comet's cues (the loop is a separate player).
  static const Set<Sfx> cometCues = {Sfx.puCometGet, Sfx.puCometEnd};

  /// PRD-2.2 §18.4 a capsule's power-up cues.
  static Set<Sfx> capsuleCues(CapsuleType t) => switch (t) {
    CapsuleType.hourglass => const {
      Sfx.hourglassStart,
      Sfx.hourglassTick,
      Sfx.hourglassEnd,
    },
    CapsuleType.miniBird => const {Sfx.miniStart, Sfx.miniEnd},
    CapsuleType.coinFrenzy => const {
      Sfx.frenzyStart,
      Sfx.frenzyRing,
      Sfx.frenzyEnd,
    },
  };

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<HoopSpawned>(_onHoop)
      ..on<PickupSpawned>(_onPickup);
  }

  void _onHoop(HoopSpawned e) {
    if (e.plan.kind != HoopKindId.portal) return;
    final id = e.plan.extra is RideId ? e.plan.extra! as RideId : RideId.cannon;
    _preload(portalCues(rideThemeFor(id)));
  }

  void _onPickup(PickupSpawned e) {
    final p = e.pickup;
    if (p.id == ElementId.comet) {
      _preload(cometCues);
    } else if (p.id == ElementId.capsule) {
      final t = p.plan?.extra;
      if (t is CapsuleType) _preload(capsuleCues(t));
    }
  }

  void _preload(Set<Sfx> cues) {
    final c = _c;
    if (c == null) return;
    requests.add(cues);
    c.game.sound.preload(cues);
  }

  @override
  void detach() {
    _c?.events
      ?..off<HoopSpawned>(_onHoop)
      ..off<PickupSpawned>(_onPickup);
    _c = null;
  }
}
