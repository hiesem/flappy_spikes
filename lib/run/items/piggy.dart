import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../config/piggy_config.dart';
import '../director/plans.dart';
import '../effects/collect_fx.dart';
import '../effects/hud_fetch.dart';
import '../elements.dart';
import '../hud/banners.dart';
import '../hud/run_badges.dart';
import '../hud/run_hud.dart';
import '../mistakes.dart';
import '../pickups/piggy_coin.dart';
import '../pickups/pickup.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';

/// The Piggy Bank (PRD-2 §3.28, §5.27).
///
/// Grabbing the piggy starts a bank ("PIGGY BANK"): 4 coins appear in its
/// own gap (this feature emits them, since the director had already planned
/// that gap) and the director fills the next 4 gaps with 4 coins each while
/// `RunState.piggy` is set (`DirectorContext.piggyRunning`) — exactly 20.
/// Caught coins go into the bank, uncaught ones are missed and gone. When
/// all 20 are resolved the piggy smashes (a burst at the HUD piggy + a 4 pt
/// camera kick), pays **×2 of what was caught** into the wallet (`piggy`;
/// the chick's ×2 stacks on top through `RunContext.earn`), shows "+N" and
/// disappears. A crash before the pay-out loses the bank (also with a
/// revive); a shield / extra life save keeps it (Q67). A portal ride clears
/// the coins on screen without counting them missed; the director places
/// them again after the landing (§3.0.3, S6-41).
class PiggyFeature extends RunFeature {
  RunContext? _c;
  PiggyBadge? _badge;
  CollectBursts? _bursts;

  /// Banks that paid out (tests / debug).
  int paid = 0;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<PickupEscaped>(_onEscaped)
      ..on<PickupCleared>(_onCleared);
    _bursts = CollectBursts();
    c.game.world.add(_bursts!);
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null) return;
    if (e.element == ElementId.piggy) {
      _start(c, e.pickup);
      return;
    }
    if (e.element != ElementId.piggyCoins) return;
    final bank = c.s.piggy;
    if (bank == null) return;
    bank.caught++;
    c.sfx(Sfx.piggyCoin);
    final pickup = e.pickup;
    final at = pickup is PiggyCoin ? pickup.lastCollectedAt : null;
    final from = at == null
        ? Offset(PiggyConfig.hudPigX, PiggyConfig.hudPigY)
        : _screen(c, at);
    c.game.world.add(
      CoinFetch(from: from, to: const Offset(PiggyConfig.hudPigX, PiggyConfig.hudPigY)),
    );
    _check(c, bank);
  }

  void _onEscaped(PickupEscaped e) {
    final c = _c;
    if (c == null || e.element != ElementId.piggyCoins) return;
    final bank = c.s.piggy;
    if (bank == null) return;
    bank.missed++;
    c.sfx(Sfx.piggyMiss);
    _check(c, bank);
  }

  /// §3.0.3 / §3.28 a portal ride cleared a coin field: its unresolved
  /// coins are neither caught nor missed. The bank stays open and the
  /// director places them again after the landing (S6-41: all 20 must be
  /// caught or missed before the pay-out).
  void _onCleared(PickupCleared e) {
    final c = _c;
    if (c == null || e.element != ElementId.piggyCoins) return;
    if (c.s.piggy == null) return;
    final field = e.pickup;
    if (field is PiggyCoin) {
      c.run.director.refundPiggyCoins(
        field.count - field.caughtCount - field.missedCount,
      );
    }
  }

  /// Starts the bank and emits the 4 own-gap coins (PRD §3.28: from 20 pt
  /// after the piggy to 40 pt before the next hoop, on the line between the
  /// piggy's hoop and the next).
  void _start(RunContext c, Pickup? piggy) {
    c.s.piggy = PiggyState();
    _mountBadge(c);
    c.sfx(Sfx.piggyOink);
    c.track('piggy_collected');
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        PiggyConfig.bannerText,
        color: PiggyConfig.bannerColor,
        subtitle: PiggyConfig.bannerSub,
      ),
    );
    if (piggy == null) return;
    final next = c.run.spawner.nextHoopAhead();
    final x0 = piggy.position.x + PiggyConfig.ownGapStart;
    final x1 = next != null
        ? next.plan.trackX - PiggyConfig.ownGapEnd
        : x0 + PiggyConfig.ownGapFallback;
    final y0 = piggy.position.y;
    final y1 = next?.plan.centreY ?? y0;
    c.run.spawner.spawnItem(
      GapItemPlan(
        kind: ElementId.piggyCoins,
        trackX: x0,
        toTrackX: x1,
        y: y0,
        toY: y1,
        extra: PiggyConfig.ownGapCoins,
      ),
    );
  }

  /// Pays out once all 20 coins are caught or missed.
  void _check(RunContext c, PiggyState bank) {
    if (bank.caught + bank.missed < PiggyConfig.total) return;
    final caught = bank.caught;
    final payout = caught * PiggyConfig.payoutMult;
    c.s.piggy = null;
    _dropBadge();
    paid++;
    _bursts?.burst(
      at: const Offset(PiggyConfig.hudPigX, PiggyConfig.hudPigY),
      colors: PiggyConfig.smashColors,
      pieces: PiggyConfig.smashPieces,
      speed: PiggyConfig.smashSpeed,
    );
    c.game.world.add(CollectShake(c));
    c.sfx(Sfx.piggySmash);
    c.earn(payout, CoinSource.piggy);
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        '+$payout',
        color: PiggyConfig.payoutColor,
        subtitle: '$caught${PiggyConfig.payoutSub}',
      ),
    );
    c.track('piggy_paid', {'caught': caught, 'payout': payout});
  }

  Offset _screen(RunContext c, Offset track) {
    final s = c.geo.toScreen(Vector2(track.dx, track.dy));
    return Offset(s.x, s.y);
  }

  void _mountBadge(RunContext c) {
    _dropBadge();
    _badge = PiggyBadge(c.run);
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
      ..off<PickupEscaped>(_onEscaped)
      ..off<PickupCleared>(_onCleared);
    _dropBadge();
    _bursts?.removeFromParent();
    _bursts = null;
    _c = null;
  }
}
