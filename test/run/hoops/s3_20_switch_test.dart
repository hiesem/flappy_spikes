import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/switch_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/switch/switch_kind.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3d: rings with an on/off switch (PRD-2 §3.20, §5.19).
void main() {
  group('§3.20 rules (pure)', () {
    test('§3.20 / §5.19 every design opens within 0.8 s; the open words and '
        'the crash words', () {
      for (final d in SwitchDesign.values) {
        expect(
          SwitchConfig.openDone(d),
          lessThanOrEqualTo(SwitchConfig.openMax),
        );
        expect(
          SwitchConfig.openAt(d),
          lessThanOrEqualTo(SwitchConfig.openDone(d)),
        );
      }
      expect(SwitchConfig.openMax, .8);
      expect(SwitchConfig.coins, 1);
      expect(SwitchConfig.openWord(SwitchDesign.lockdown), isNull);
      expect(SwitchConfig.openWord(SwitchDesign.laserGate)!.$1, 'POWER OFF');
      expect(SwitchConfig.openWord(SwitchDesign.powerIris)!.$1, 'POWER ON');
      expect(SwitchConfig.openWord(SwitchDesign.snoozer)!.$1, 'WAKE UP!');
      expect(SwitchConfig.openWord(SwitchDesign.giftWrap)!.$1, 'SNIP!');
      expect(SwitchDesign.values.map(SwitchConfig.crashWord), [
        'LOCKED!',
        'ZAPPED!',
        'SHUT!',
        'HMPF!',
        'WRAPPED!',
      ]);
      expect(SwitchConfig.stay(SwitchDesign.laserGate), .3);
      expect(SwitchConfig.stay(SwitchDesign.powerIris), 1.1);
      expect(PickupRadii.switchPickup, 18);
    });

    test('§3.20 five designs at random (all used, about equally), never the '
        'same twice in a row, mixed within a run', () {
      final counts = <SwitchDesign, int>{};
      for (final seed in [1, 2, 3, 4, 5]) {
        final d = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet(),
          startHoopIndex: 12,
        );
        SwitchDesign? last;
        final seen = <SwitchDesign>{};
        for (var i = 0; i < 300; i++) {
          d.debugForce(ElementId.switchRing);
          final s = d.nextSlot(DirectorContext.open(711));
          d.nextGap(DirectorContext.open(711), s);
          if (s.kind != HoopKindId.switchRing) continue;
          final design = s.extra! as SwitchDesign;
          expect(design, isNot(last));
          last = design;
          seen.add(design);
          counts[design] = (counts[design] ?? 0) + 1;
          // The switch is decided with its ring and carries its design.
          expect(s.attached.single.extra, design);
        }
        expect(seen, hasLength(5), reason: 'mixed within one run');
      }
      final total = counts.values.fold(0, (a, b) => a + b);
      for (final c in counts.values) {
        expect(c / total, closeTo(1 / 5, .05));
      }
    });

    test('§3.20 a closed ring at the plane is a mistake; open, a pass', () {
      final kind = SwitchRingKind();
      expect(kind.usesTierLook, isFalse);
      final h = Hoop(plan: _plan(SwitchDesign.snoozer), kind: kind);
      final s = RunState(seed: 1, viewHeight: 711, metElements: {});
      expect(kind.rimMode(h, s), RimMode.bounce);
      h.open = true;
      expect(kind.themedDeath(h)!.holdSeconds, 0);
    });
  });

  group('§3.20 in a run', () {
    late AnalyticsSpy spy;
    FlameTester<FlappySpikesGame> tester({double h = 711, int seed = 11}) =>
        FlameTester<FlappySpikesGame>(() {
          spy = AnalyticsSpy();
          return createRunTestGame(worldHeight: h, services: spy, seed: seed);
        }, gameSize: Vector2(320, h));

    Future<void> prepare(FlappySpikesGame g) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    }

    Future<(RunController, Hoop)> switchRun(
      FlappySpikesGame game, {
      SwitchDesign? design,
      Powerup starter = Powerup.none,
    }) async {
      final run = await startRun(
        game,
        startHoopIndex: 12,
        force: [ElementId.switchRing],
        starter: starter,
      );
      final h = await flyToHoop(
        game,
        HoopKindId.switchRing,
        ElementId.switchRing,
        // The design is a seeded roll: feathers / pieces (WP-4a) shift the
        // course, so allow a longer flight to meet every design.
        maxSeconds: 150,
        where: (h) {
          final st = SwitchRingKind.stateOf(h);
          final p = st?.pickup;
          final b = run.birdTrackPosition();
          return (design == null || SwitchRingKind.designOf(h) == design) &&
              p != null &&
              b != null &&
              p.position.x > b.x + 60;
        },
      );
      expect(h, isNotNull);
      return (run, h!);
    }

    for (final design in SwitchDesign.values) {
      tester().testGameWidget(
        '§3.20 ${design.name}: spawns closed with its switch in the gap before '
        '(1.0 s × scroll ≥ 150 pt, 70–100 pt off the centre); the autopilot '
        'takes the switch first: +1 coin (switch), the ring opens at once '
        '(animation ≤ 0.8 s), the streak is unchanged; then a normal pass',
        setUp: (g, _) => prepare(g),
        verify: (game, _) async {
          final (run, h) = await switchRun(game, design: design);
          expect(h.open, isFalse);
          final st = SwitchRingKind.stateOf(h)!;
          final p = st.pickup!;
          expect(p.design, design);
          expect(p.ring, same(h));
          // At the director's spot (its placement rules are tested in
          // s3_0_3_director_test): ≥ 150 pt before the ring.
          final plan = h.plan.attached.single;
          expect(p.position, Vector2(plan.trackX, plan.y!));
          final lead = h.planeX - p.position.x;
          expect(lead, greaterThanOrEqualTo(RunConfig.switchLeadMin - 1e-6));
          // The autopilot aims at the switch first.
          final aim = h.kind.autopilotTarget(h, run.state, 0);
          expect(aim.preTarget, isNotNull);
          expect(aim.preTarget!.x, p.position.x);
          final events = <RunEvent>[];
          run.events.onAny(events.add);
          final sfx = sfxLog(game);
          final streak = run.state.streak;
          expect(await flyUntil(game, (_) => p.collected), isTrue);
          expect(h.open, isTrue, reason: 'open at once in the logic');
          expect(
            run.state.streak,
            streak,
            reason: 'the switch keeps the streak',
          );
          final coins = events.whereType<CoinsEarned>().toList();
          // A hatched chick (a seeded egg on the way) doubles it.
          expect(coins.single.amount, coins.single.eggX2 ? 2 : 1);
          expect(coins.single.source, CoinSource.switchRing);
          expect(sfx, contains(SwitchConfig.touchSound(design).name));
          expect(h.kind.autopilotTarget(h, run.state, 0).preTarget, isNull);
          expect(
            spy.events.lastWhere((e) => e.$1 == 'switchring_switch_taken').$2,
            {'design': SwitchRingKind.storageName(design)},
          );
          // The open animation finishes within 0.8 s.
          await flyUntil(game, (_) => st.hitT >= SwitchConfig.openMax);
          expect(sfx, contains(SwitchConfig.openSound(design).name));
          // Then it is a normal hoop.
          final score = run.state.score;
          expect(await flyUntil(game, (_) => h.resolved), isTrue);
          expect(run.dying, isFalse);
          expect(h.takenRing, 0);
          expect(run.state.score, score + 1);
          expect(spy.events.map((e) => e.$1), contains('switchring_passed'));
          expect(game.storage.metElements, contains('switch_ring'));
        },
      );
    }

    tester().testGameWidget(
      '§3.20 reaching the ring while it is still closed is a mistake: the '
      'crash plays, the knock is straight back (−x), the red banner shows the '
      'design word; switchring_closed_hit {used: none}',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await switchRun(game);
        final design = SwitchRingKind.designOf(h);
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final sfx = sfxLog(game);
        // Avoid the switch: glide straight at the ring centre.
        final p = SwitchRingKind.stateOf(h)!.pickup!;
        await flyUntil(
          game,
          (r) {
            final b = r.birdTrackPosition();
            return b != null && p.position.x - b.x <= 60;
          },
          flap: (r) {
            final b = game.runBirdPosition!;
            return b.y > h.position.y + 6 && (game.runBirdVelocityY ?? 0) > -40;
          },
        );
        // Steer away from the switch, toward the ring centre.
        game.runBird!.setFlight(y: h.position.y, vy: 0);
        p.position.y = h.position.y + 300; // out of reach
        await flyUntil(
          game,
          (r) => r.dying || h.resolved,
          flap: (r) {
            final b = game.runBirdPosition!;
            return b.y > h.position.y + 6 && (game.runBirdVelocityY ?? 0) > -40;
          },
        );
        expect(p.collected, isFalse);
        expect(run.dying, isTrue);
        expect(events.whereType<ClosedSwitchReached>().single.hoop, same(h));
        final died = events.whereType<RunDied>().single;
        expect(died.mistake.cause, MistakeCause.closedSwitch);
        expect(died.mistake.normal, Vector2(-1, 0));
        expect(sfx, contains(SwitchConfig.crashSound(design).name));
        expect(
          events.whereType<HoopMissed>(),
          isEmpty,
          reason: 'no miss flash',
        );
        expect(run.tumble!.velocity.x, lessThan(run.state.forwardSpeed));
        final host = BannerHost.ensureIn(game.world);
        expect(
          (host.current! as ElementBanner).text,
          SwitchConfig.crashWord(design),
        );
        expect(
          spy.events.lastWhere((e) => e.$1 == 'switchring_closed_hit').$2,
          {'design': SwitchRingKind.storageName(design), 'used': 'none'},
        );
        expect(SwitchRingKind.stateOf(h)!.crashT, greaterThanOrEqualTo(0));
      },
    );

    tester().testGameWidget(
      '§3.20 with a shield the closed ring is saved: it counts as passed with '
      'no score, the streak resets; switchring_closed_hit {used: shield}',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await switchRun(game, starter: Powerup.shield);
        final p = SwitchRingKind.stateOf(h)!.pickup!;
        p.position.y = h.position.y + 300; // out of reach
        await flyUntil(
          game,
          (r) {
            final b = r.birdTrackPosition();
            return b != null && h.planeX - b.x <= 12;
          },
          flap: (r) {
            final b = game.runBirdPosition!;
            return b.y > h.position.y + 6 && (game.runBirdVelocityY ?? 0) > -40;
          },
        );
        expect(run.state.shield, isTrue);
        run.state.streak = 3;
        final score = run.state.score;
        game.runBird!.setFlight(y: h.position.y, vy: 0);
        await flyUntil(
          game,
          (_) => h.resolved,
          maxSeconds: .4,
          autopilot: false,
        );
        expect(run.dying, isFalse);
        expect(h.resolved, isTrue);
        expect(h.takenRing, isNull);
        expect(run.state.score, score);
        expect(run.state.streak, 0);
        expect(
          spy.events.lastWhere((e) => e.$1 == 'switchring_closed_hit').$2,
          {
            'design': SwitchRingKind.storageName(SwitchRingKind.designOf(h)),
            'used': 'shield',
          },
        );
      },
    );

    tester().testGameWidget(
      '§3.20 a closed switch ring on screen opens by itself when the comet '
      'arrives (no coin)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await switchRun(game);
        final coins = run.state.coinsThisRun;
        run.state.ride = RideState(kind: RideKind.comet);
        game.update(1 / 60);
        expect(h.open, isTrue);
        expect(run.state.coinsThisRun, coins);
        run.state.ride = null;
      },
    );
  });
}

SlotPlan _plan(SwitchDesign d) => SlotPlan(
  index: 12,
  kind: HoopKindId.switchRing,
  element: ElementId.switchRing,
  trackX: 400,
  centreY: 300,
  opening: 112,
  advance: 310,
  extra: d,
);
