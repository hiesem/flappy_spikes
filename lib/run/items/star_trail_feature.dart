import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../config/star_trail_config.dart';
import '../effects/text_pop.dart';
import '../elements.dart';
import '../hud/banners.dart';
import '../hud/run_hud.dart';
import '../pickups/star_trail.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// The Star Trail's result (PRD-2 §3.26, §5.25).
///
/// The [StarTrail] pickup itself draws the arc, collects one star per frame
/// (sparkle + the next C-major note) and emits [StarTrailFinished] when its
/// last star is behind the bird; this feature records the count and decides
/// the end: **all 8** shows PERFECT LINE, pays +5 coins (`star_trail`) and
/// plays the chord, anything less pops "n / 8" (`trailPop`) and pays nothing. Single
/// stars pay nothing on their own (Q65).
class StarTrailFeature extends RunFeature {
  RunContext? _c;

  /// Trails that finished (tests / debug).
  int trails = 0;

  /// Trails completed with all 8 stars (tests / debug).
  int perfects = 0;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<StarTrailFinished>(_onFinished);
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null || e.element != ElementId.starTrail) return;
    final trail = e.pickup;
    if (trail is! StarTrail) return;
    c.s.trails.caught[trail.trailId] = trail.caughtCount;
  }

  void _onFinished(StarTrailFinished e) {
    final c = _c;
    if (c == null) return;
    trails++;
    final n = e.trail.caughtCount;
    c.track('star_trail', {'stars': n});
    if (n >= StarTrailConfig.stars) {
      perfects++;
      c.emit(const StarTrailPerfect()); // PRD-2.3.1 §12.2
      RunHud.ensureFor(c.run).banners.show(
        ElementBanner(
          StarTrailConfig.bannerText,
          color: StarTrailConfig.bannerColor,
          subtitle: StarTrailConfig.bannerSub,
        ),
      );
      c.earn(StarTrailConfig.reward, CoinSource.starTrail);
      c.sfx(Sfx.trailChord);
      return;
    }
    // §3.26 / SOUNDS the partial "n / 8" pop (S6-42).
    c.sfx(Sfx.trailPop);
    final bird = c.run.birdTrackPosition();
    if (bird == null) return;
    c.layers.fx.add(
      TextPop(
        '$n / ${StarTrailConfig.stars}',
        Vector2(
          bird.x + StarTrailConfig.popDx,
          bird.y + StarTrailConfig.popDy,
        ),
        StarTrailConfig.popColor,
        fontSize: StarTrailConfig.popSize,
      ),
    );
  }

  @override
  void detach() {
    _c?.events
      ?..off<PickupCollected>(_onCollected)
      ..off<StarTrailFinished>(_onFinished);
    _c = null;
  }
}
