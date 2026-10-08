import 'dart:ui';

import '../config/capsule_config.dart';
import '../director/plans.dart';
import '../elements.dart';
import '../hud/banners.dart';
import '../hud/run_hud.dart';
import '../hud/timer_pill.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';

/// The capsule powerups' names, colours and fixed durations (PRD-2 §3.30–
/// §3.32). `TimedPowerup.comet` is the comet boost's use of the same slot
/// (§3.8); it has no capsule, banner, pill or analytics here.
extension TimedPowerupInfo on TimedPowerup {
  /// The capsule type that starts it (null for the comet).
  static TimedPowerup fromCapsule(CapsuleType t) => switch (t) {
    CapsuleType.hourglass => TimedPowerup.hourglass,
    CapsuleType.miniBird => TimedPowerup.mini,
    CapsuleType.coinFrenzy => TimedPowerup.frenzy,
  };

  /// A capsule powerup (Hourglass, Mini Bird, Coin Frenzy) — not the comet.
  bool get isCapsule => this != TimedPowerup.comet;

  /// §6 `powerup_started` / `powerup_ended` type value.
  String get analyticsName => name; // hourglass / mini / frenzy

  ElementId get element => switch (this) {
    TimedPowerup.hourglass => ElementId.hourglass,
    TimedPowerup.mini => ElementId.miniBird,
    TimedPowerup.frenzy => ElementId.coinFrenzy,
    TimedPowerup.comet => ElementId.comet,
  };

  /// §5.29–5.31 the powerup colour (capsule, banner, pill).
  Color get color => switch (this) {
    TimedPowerup.hourglass => CapsuleConfig.hourglass,
    TimedPowerup.mini => CapsuleConfig.mini,
    TimedPowerup.frenzy => CapsuleConfig.frenzy,
    TimedPowerup.comet => CapsuleConfig.frenzy,
  };
}

/// The one timed-powerup slot (PRD-2 §3.30 "only one timed powerup runs at
/// a time"; ARCH §1.7 `TimedPowerupSlot`). State lives in
/// `RunState.timed`; the comet boost (WP-3a) fills the same field itself,
/// so the exclusivity (no capsule / comet hoop while one runs, the
/// director's `timedPowerupRunning`) covers all four.
///
/// - **Start:** a collected capsule (`PickupCollected(capsule)`) starts its
///   powerup at once — Hourglass rolls 10–20 s on the director's `timing`
///   stream, Mini Bird 8 s, Coin Frenzy 6 s — with the banner (name + one
///   line) and the [TimerPill]; a capsule touched while a timed powerup or
///   a ride runs starts nothing.
/// - **Clock:** the remaining time counts down in **real time** (§3.30
///   "real time"; the Hourglass slows the world, not its own timer), stops
///   while a portal ride pauses it (WP-3b sends `PowerupPaused` /
///   `PowerupResumed`) and while the game is paused (the world is frozen).
/// - **End:** at 0 the slot clears and sends [PowerupEnded]; a death ends
///   it too (`ReviveRulesFeature`, §3.14).
/// - **Analytics (§6):** `powerup_started {type, duration}` and
///   `powerup_ended {type}` for hourglass / mini / frenzy only — never for
///   the comet (WP-3a note).
///
/// The effects themselves are [TimedPowerupEffect] features (Hourglass,
/// Mini Bird, Coin Frenzy) reacting to the slot's events.
class TimedPowerupSlot extends RunFeature {
  RunContext? _c;

  /// The HUD timer pill (recreated after a death clears the HUD).
  TimerPill? pill;

  /// Capsule powerups started this run (tests, debug).
  int started = 0;

  RunContext? get context => _c;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<PowerupStarted>(_onStarted)
      ..on<PowerupEnded>(_onEnded);
  }

  void _onCollected(PickupCollected e) {
    if (e.element != ElementId.capsule) return;
    final type = e.pickup?.plan?.extra;
    if (type is! CapsuleType) return;
    start(type);
  }

  /// §3.30 the duration of a fresh [type] (s, real time).
  double rollDuration(TimedPowerup type) => switch (type) {
    TimedPowerup.hourglass => _c!.director.rollHourglassDuration(),
    TimedPowerup.mini => CapsuleConfig.miniDuration,
    TimedPowerup.frenzy => CapsuleConfig.frenzyDuration,
    TimedPowerup.comet => 0,
  };

  /// Starts [capsule]'s powerup now. False (nothing starts) while a timed
  /// powerup or a ride runs (§3.30 exclusivity).
  bool start(CapsuleType capsule) {
    final c = _c;
    if (c == null) return false;
    final s = c.s;
    if (s.timed != null || s.ride != null) return false;
    final type = TimedPowerupInfo.fromCapsule(capsule);
    final duration = rollDuration(type);
    s.timed = TimedPowerupState(type: type, duration: duration);
    started++;
    final id = type.element.storageId;
    s.taken[id] = (s.taken[id] ?? 0) + 1;
    c.emit(PowerupStarted(type, duration));
    final hud = RunHud.ensureFor(c.run);
    hud.banners.show(
      ElementBanner(
        CapsuleConfig.bannerTitle(type.analyticsName),
        color: type.color,
        subtitle: CapsuleConfig.bannerLine(type.analyticsName, duration),
        duration: CapsuleConfig.bannerDuration,
      ),
    );
    final p = pill;
    if (p == null || p.isRemoved || p.isRemoving) {
      hud.add(pill = TimerPill(c.run));
    }
    return true;
  }

  void _onStarted(PowerupStarted e) {
    if (!e.type.isCapsule) return;
    _c?.track('powerup_started', {
      'type': e.type.analyticsName,
      'duration': e.duration.round(),
    });
  }

  void _onEnded(PowerupEnded e) {
    if (!e.type.isCapsule) return;
    _c?.track('powerup_ended', {'type': e.type.analyticsName});
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    final t = c.s.timed;
    if (t == null || !t.type.isCapsule || t.paused) return;
    t.remaining -= realDt;
    if (t.remaining <= 0) {
      t.remaining = 0;
      c.s.timed = null;
      c.emit(PowerupEnded(t.type));
    }
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.events
        ..off<PickupCollected>(_onCollected)
        ..off<PowerupStarted>(_onStarted)
        ..off<PowerupEnded>(_onEnded);
    }
    pill?.removeFromParent();
    pill = null;
    _c = null;
  }
}

/// Base of one capsule powerup's effect (Hourglass, Mini Bird, Coin
/// Frenzy): it follows the [TimedPowerupSlot]'s events for its [type] —
/// started, paused / resumed by a portal ride (the effect is suspended),
/// ended (time up, or a death: then without the end sound / ease).
abstract class TimedPowerupEffect extends RunFeature {
  TimedPowerup get type;

  RunContext? c;

  /// The powerup runs (started, not ended).
  bool active = false;

  /// A portal ride holds it (§3.0.3).
  bool paused = false;

  /// Running and not held by a ride.
  bool get on => active && !paused;

  /// Seconds since the start (real time, stops while paused).
  double elapsed = 0;

  /// This run's duration.
  double duration = 0;

  @override
  void attach(RunContext c) {
    this.c = c;
    c.events
      ..on<PowerupStarted>(_started)
      ..on<PowerupEnded>(_ended)
      ..on<PowerupPaused>(_paused)
      ..on<PowerupResumed>(_resumed);
  }

  void _started(PowerupStarted e) {
    if (e.type != type) return;
    active = true;
    paused = false;
    elapsed = 0;
    duration = e.duration;
    onStart();
  }

  void _ended(PowerupEnded e) {
    if (e.type != type || !active) return;
    active = false;
    paused = false;
    final death = c?.run.dying ?? true;
    onEnd(death: death);
  }

  void _paused(PowerupPaused e) {
    if (e.type != type || !active || paused) return;
    paused = true;
    onPause();
  }

  void _resumed(PowerupResumed e) {
    if (e.type != type || !active || !paused) return;
    paused = false;
    onResume();
  }

  void onStart();

  /// Time up ([death] false: end sound, ease back) or a death (everything
  /// back at once).
  void onEnd({required bool death});

  /// A portal ride starts: the effect is suspended (no slow-motion or mini
  /// rides, no coin rings).
  void onPause();

  void onResume();

  /// Every frame: [gameDt] is the (slowed) world time, [realDt] real time.
  void step(double gameDt, double realDt);

  /// Hard reset of every visual and the shared state this effect owns
  /// (death, end of the run).
  void reset();

  @override
  void update(double gameDt, double realDt) {
    if (on) elapsed += realDt;
    step(gameDt, realDt);
  }

  @override
  void onDeath(Mistake m) {
    // `ReviveRulesFeature` ends the slot after this ([PowerupEnded]); an
    // effect still easing out after its end stops here as well.
    reset();
  }

  @override
  void detach() {
    final ctx = c;
    if (ctx != null) {
      ctx.events
        ..off<PowerupStarted>(_started)
        ..off<PowerupEnded>(_ended)
        ..off<PowerupPaused>(_paused)
        ..off<PowerupResumed>(_resumed);
    }
    active = false;
    paused = false;
    reset();
    c = null;
  }
}
