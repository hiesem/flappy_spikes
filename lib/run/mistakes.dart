import 'package:flame/components.dart';

import 'hoops/hoop.dart';
import 'run_context.dart';
import 'run_events.dart';

/// What went wrong (§3.3 list; analytics `run_end` cause, §6).
enum MistakeCause {
  missedHoop('missed_hoop'),
  spikes('spikes'),
  saw('saw'),
  closedSwitch('closed_switch'),
  pairMissed('pair_missed');

  const MistakeCause(this.analyticsName);
  final String analyticsName;
}

/// A themed death's signature moment (§3.0.5: Live Wire, Frost Ring, Black
/// Hole, switch crashes); played before the tumble.
class ThemedDeath {
  const ThemedDeath(this.id, {this.holdSeconds = 0, this.noBody = false});
  final String id;

  /// The moment before the tumble (e.g. zap hold 0.6 s).
  final double holdSeconds;

  /// Black Hole: the bird is swallowed (no tumble, no body).
  final bool noBody;
}

class Mistake {
  const Mistake(this.cause, {this.normal, this.themed, this.hoop});
  final MistakeCause cause;

  /// Contact normal (towards the bird) for the tumble knock (§3.0.5).
  final Vector2? normal;
  final ThemedDeath? themed;
  final Hoop? hoop;
}

/// A save (shield order 10, extra life order 20; call: the shield absorbs
/// first, matching the prototype).
abstract class MistakeInterceptor {
  int get order;

  /// Returns true when it absorbed [m] (and has applied its effect).
  bool tryAbsorb(Mistake m, RunContext ctx);

  /// 'shield' / 'extra_life' (analytics `used`, [MistakeSaved.by]).
  String get id;
}

/// The one mistake pipeline (ARCH §2.6). Ignores mistakes while
/// invulnerable or during a ride; asks the interceptors in order; a save
/// emits [MistakeSaved], otherwise [RunDied].
class MistakePipeline {
  final List<MistakeInterceptor> _interceptors = [];

  void add(MistakeInterceptor i) {
    _interceptors
      ..add(i)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  void remove(MistakeInterceptor i) => _interceptors.remove(i);

  /// Returns the outcome; [MistakeOutcome.died] ends the run.
  MistakeOutcome resolve(Mistake m, RunContext ctx) {
    final s = ctx.s;
    if (s.invulnerable > 0 || s.ride != null) return MistakeOutcome.ignored;
    for (final i in _interceptors) {
      if (i.tryAbsorb(m, ctx)) {
        s.saves++;
        ctx.emit(MistakeSaved(m, i.id));
        return MistakeOutcome.saved;
      }
    }
    ctx.emit(RunDied(m));
    return MistakeOutcome.died;
  }
}

enum MistakeOutcome { ignored, saved, died }
