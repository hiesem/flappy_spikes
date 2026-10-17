import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../config/jar_config.dart';
import '../effects/collect_fx.dart';
import '../effects/hud_fetch.dart';
import '../effects/particle_pool.dart';
import '../elements.dart';
import '../hud/banners.dart';
import '../hud/run_badges.dart';
import '../hud/run_hud.dart';
import '../mistakes.dart';
import '../pickups/firefly_swarm.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';
import '../run_scaled_world.dart';

/// The Firefly Jar (PRD-2 §3.29, §5.28).
///
/// Grabbing the animated jar starts it ("FIREFLY JAR"); fireflies only
/// appear after that (the director places a swarm of 7 in each following
/// gap while `RunState.jar` is set). Flying through a firefly catches it
/// (glow into the jar under the score); one that passes uncaught escapes
/// and lights a ✕. **20 caught = JAR FULL +25 coins** (`jar`), **3 escaped
/// = JAR BROKE** with no reward; either way the jar and its fireflies are
/// gone. A crash loses it (also with a revive); a save keeps it; a portal
/// ride clears the swarms on screen without counting escapes (§3.0.3).
class JarFeature extends RunFeature {
  RunContext? _c;
  JarBadge? _badge;
  CollectBursts? _bursts;

  /// Jars that ended, full or broken (tests / debug).
  int fullJars = 0;
  int brokenJars = 0;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<PickupEscaped>(_onEscaped);
    _bursts = CollectBursts();
    c.game.world.addRun(_bursts!);
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null) return;
    if (e.element == ElementId.jar) {
      _start(c);
      return;
    }
    if (e.element != ElementId.fireflySwarm) return;
    final jar = c.s.jar;
    if (jar == null) return;
    jar.caught++;
    c.sfx(Sfx.jarTwinkle);
    final pickup = e.pickup;
    final at = pickup is FireflySwarm ? pickup.lastCollectedAt : null;
    final from = at == null
        ? const Offset(JarConfig.hudJarX, JarConfig.hudJarY)
        : _screen(c, at);
    c.game.world.addRun(
      GlowFetch(from: from, to: const Offset(JarConfig.hudJarX, JarConfig.hudJarY)),
    );
    if (jar.caught >= JarConfig.total) _finish(c, jar, full: true);
  }

  void _onEscaped(PickupEscaped e) {
    final c = _c;
    if (c == null || e.element != ElementId.fireflySwarm) return;
    final jar = c.s.jar;
    if (jar == null) return;
    jar.escaped++;
    c.sfx(Sfx.jarEscape);
    if (jar.escaped >= JarConfig.maxEscapes) _finish(c, jar, full: false);
  }

  void _start(RunContext c) {
    c.s.jar = JarState();
    _mountBadge(c);
    c.sfx(Sfx.jarPickup);
    c.track('jar_collected');
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        JarConfig.bannerText,
        color: JarConfig.bannerColor,
        subtitle: JarConfig.bannerSub,
      ),
    );
  }

  void _finish(RunContext c, JarState jar, {required bool full}) {
    final caught = jar.caught;
    c.s.jar = null; // the remaining swarms fly away unjudged
    _dropBadge();
    if (full) {
      fullJars++;
      c.emit(const JarFilled()); // PRD-2.3.1 §12.2
      _bursts?.burst(
        at: const Offset(JarConfig.hudJarX, JarConfig.hudJarY),
        colors: JarConfig.fullColors,
        pieces: JarConfig.fullPieces,
        speed: JarConfig.fullSpeed,
        shape: ParticleShape.circle,
      );
      c.earn(JarConfig.reward, CoinSource.jar);
      c.sfx(Sfx.jarFull);
      RunHud.ensureFor(c.run).banners.show(
        ElementBanner(
          JarConfig.fullText,
          color: JarConfig.bannerColor,
          subtitle: JarConfig.fullSub,
        ),
      );
    } else {
      brokenJars++;
      c.sfx(Sfx.jarBreak);
      RunHud.ensureFor(c.run).banners.show(
        ElementBanner(
          JarConfig.brokeText,
          color: JarConfig.brokeGrey,
          subtitle: JarConfig.brokeSub,
        ),
      );
    }
    c.track('jar_result', {'result': full ? 'full' : 'broken', 'caught': caught});
  }

  Offset _screen(RunContext c, Offset track) {
    final s = c.geo.toScreen(Vector2(track.dx, track.dy));
    return Offset(s.x, s.y);
  }

  void _mountBadge(RunContext c) {
    _dropBadge();
    _badge = JarBadge(c.run);
    RunHud.ensureFor(c.run).add(_badge!);
  }

  void _dropBadge() {
    _badge?.removeFromParent();
    _badge = null;
  }

  @override
  void onDeath(Mistake m) => _dropBadge();

  @override
  void detach() {
    final c = _c;
    c?.events
      ?..off<PickupCollected>(_onCollected)
      ..off<PickupEscaped>(_onEscaped);
    _dropBadge();
    _bursts?.removeFromParent();
    _bursts = null;
    _c = null;
  }
}
