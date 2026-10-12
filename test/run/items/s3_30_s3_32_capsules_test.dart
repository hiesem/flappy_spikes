import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/capsule_config.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/hud/timer_pill.dart';
import 'package:flappy_spikes/run/items/coin_frenzy.dart';
import 'package:flappy_spikes/run/items/hourglass.dart';
import 'package:flappy_spikes/run/items/mini_bird.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/pickups/capsule.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

T _f<T>(RunController r) => r.features.whereType<T>().single;

TimedPowerupSlot _slot(RunController r) => _f<TimedPowerupSlot>(r);

/// Flies with the bot for [seconds] of real time (or until [until]).
Future<void> _fly(
  FlappySpikesGame game,
  RunController run,
  double seconds, {
  bool Function()? until,
}) async {
  final bot = Autopilot(run);
  for (var f = 0; f < seconds * 60; f++) {
    if (until != null && until()) break;
    if (bot.shouldFlap()) game.onScreenTap();
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
  }
}

FlameTester<FlappySpikesGame> _tester({
  double h = 711,
  int seed = 5,
  AnalyticsSpy? spy,
}) => FlameTester<FlappySpikesGame>(
  () => createRunTestGame(worldHeight: h, seed: seed, services: spy),
  gameSize: Vector2(320, h),
);

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// A run a few hoops in (stable flight), nothing forced.
Future<RunController> _run(FlappySpikesGame game) async {
  final run = await startRun(game);
  await _fly(game, run, 1.5);
  return run;
}

void main() {
  group('§3.30–§3.32 capsule rules (pure)', () {
    test(
      '§3.0.3 / §3.30 spawn: gap item from gap 10, weight 20, ≥ 20 gaps '
      'apart; Hourglass 35 / Mini Bird 35 / Coin Frenzy 30; hit radius 18',
      () {
        final rule = DirectorTables.prd2.gapItems[ElementId.capsule]!;
        expect(rule.from, 10);
        expect(rule.weight, 20);
        expect(rule.minSince, 20);
        expect(DirectorTables.prd2.capsuleWeights, {
          CapsuleType.hourglass: 35,
          CapsuleType.miniBird: 35,
          CapsuleType.coinFrenzy: 30,
        });
        expect(PickupRadii.capsule, 18);
        for (final e in [
          ElementId.capsule,
          ElementId.hourglass,
          ElementId.miniBird,
          ElementId.coinFrenzy,
        ]) {
          expect(PickupRadii.forElement(e), 18);
          expect(registeredPickupElements(), contains(e));
        }
        expect(pickupKindFor(ElementId.capsule), isA<CapsulePickupKind>());
      },
    );

    test('§3.30 Hourglass: 45 % speed, 0.2 s ease, 10–20 s, music 72 %, '
        'tick every 0.6 s', () {
      expect(CapsuleConfig.hourglassScale, .45);
      expect(CapsuleConfig.hourglassEase, .2);
      expect(RunConfig.hourglassMin, 10);
      expect(RunConfig.hourglassMax, 20);
      expect(CapsuleConfig.hourglassMusicRate, .72);
      expect(CapsuleConfig.hourglassTick, .6);
      expect(CapsuleConfig.hourglass, const Color(0xFF2F80FF));
    });

    test('§3.31 Mini Bird: 52 % for 8 s, 0.15 s ease; §3.32 Coin Frenzy: '
        '+5 per ring for 6 s', () {
      expect(RunConfig.miniBirdScale, .52);
      expect(CapsuleConfig.miniDuration, 8);
      expect(CapsuleConfig.miniShrink, .15);
      expect(CapsuleConfig.mini, const Color(0xFF2EBD6B));
      expect(CapsuleConfig.potionPurple, const Color(0xFFC9A6FF));
      expect(CapsuleConfig.frenzyDuration, 6);
      expect(CapsuleConfig.frenzyCoins, 5);
      expect(CapsuleConfig.frenzy, const Color(0xFFFFB529));
      expect(CapsuleConfig.frenzyRingFront, const Color(0xFFFFD54A));
      expect(CapsuleConfig.frenzyRingBack, const Color(0xFFD48A00));
      expect(CapsuleConfig.frenzyRingStroke, 8);
      expect(CapsuleConfig.orbitCoins, 10);
      expect(CoinSource.frenzy.name, 'frenzy');
    });

    test('§5.29 capsule 34 pt (r 8), bob ±3, ring 25; timer pill 120 × 22 '
        'near the top with a 26 pt icon disc', () {
      expect(CapsuleConfig.size, 34);
      expect(CapsuleConfig.radius, 8);
      expect(CapsuleConfig.bob, 3);
      expect(CapsuleConfig.ringRadius, 25);
      expect(CapsuleConfig.pillWidth, 120);
      expect(CapsuleConfig.pillHeight, 22);
      // Call: above the y-190 banner band (master #7), under the HUD row.
      expect(CapsuleConfig.pillY + CapsuleConfig.pillHeight, lessThan(190));
      expect(CapsuleConfig.pillY, greaterThan(114));
      expect(2 * CapsuleConfig.discRadius, 26);
      expect(CapsuleConfig.frenzyBorder, 10);
    });
  });

  group('§3.30 the timed-powerup slot', () {
    final spy = AnalyticsSpy();
    _tester(spy: spy).testGameWidget(
      '§3.30 / §6 a capsule starts its powerup at once: slot, banner, pill, '
      'powerup_started; one at a time; it ends after its time (real time) '
      'with powerup_ended',
      setUp: (game, t) async {
        await _setUp(game, t);
        spy.events.clear();
      },
      verify: (game, _) async {
        final run = await _run(game);
        final slot = _slot(run);
        expect(slot.start(CapsuleType.miniBird), isTrue);
        final timed = run.state.timed!;
        expect(timed.type, TimedPowerup.mini);
        expect(timed.duration, 8);
        await flushAndMount(game);
        final hud = RunHud.of(run)!;
        final banner = hud.banners.current! as ElementBanner;
        expect(banner.text, 'MINI BIRD');
        expect(banner.color, CapsuleConfig.mini);
        expect(banner.subtitle, contains('8 s'));
        expect(hud.children.whereType<TimerPill>(), hasLength(1));
        // Only one at a time.
        expect(slot.start(CapsuleType.coinFrenzy), isFalse);
        expect(slot.start(CapsuleType.hourglass), isFalse);
        expect(spy.events.where((e) => e.$1 == 'powerup_started').single.$2, {
          'type': 'mini',
          'duration': 8,
        });
        await _fly(game, run, 4);
        expect(run.state.timed!.remaining, closeTo(4, .05));
        await _fly(game, run, 4.1);
        expect(run.state.timed, isNull);
        expect(spy.events.where((e) => e.$1 == 'powerup_ended').single.$2, {
          'type': 'mini',
        });
        // The slot is free again.
        expect(slot.start(CapsuleType.coinFrenzy), isTrue);
      },
    );

    _tester().testGameWidget(
      '§3.30 a capsule collected while a ride runs starts nothing; the '
      'capsule pickup carries its type and its radius is 18',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _run(game);
        run.state.ride = RideState(kind: RideKind.portal);
        expect(_slot(run).start(CapsuleType.hourglass), isFalse);
        run.state.ride = null;
        final p = CapsulePickup(
          const GapItemPlan(
            kind: ElementId.capsule,
            trackX: 0,
            y: 300,
            extra: CapsuleType.coinFrenzy,
          ),
        );
        expect(p.type, TimedPowerup.frenzy);
        expect(p.hitRadius, 18);
        // The touch test uses the bird radius × the Mini Bird scale.
        final bird = Vector2(0, 300 - 18 - RunConfig.birdRadius * .52 + .5);
        expect(p.touches(bird, RunConfig.birdRadius * .52), isTrue);
        expect(
          p.touches(bird - Vector2(0, 1), RunConfig.birdRadius * .52),
          isFalse,
        );
      },
    );

    final cometSpy = AnalyticsSpy();
    _tester(spy: cometSpy).testGameWidget(
      '§6 / WP-3a the comet uses the slot but sends no powerup_started / '
      'powerup_ended; a capsule does not start while it runs',
      setUp: (game, t) async {
        await _setUp(game, t);
        cometSpy.events.clear();
      },
      verify: (game, _) async {
        final run = await _run(game);
        run.state.timed = TimedPowerupState(
          type: TimedPowerup.comet,
          duration: 10,
        );
        run.ctx.emit(const PowerupStarted(TimedPowerup.comet, 10));
        expect(_slot(run).start(CapsuleType.hourglass), isFalse);
        // The slot does not tick the comet (the comet ride owns its clock).
        game.update(.5);
        expect(run.state.timed!.remaining, 10);
        run.state.timed = null;
        run.ctx.emit(const PowerupEnded(TimedPowerup.comet));
        expect(
          cometSpy.events.where((e) => e.$1.startsWith('powerup_')),
          isEmpty,
        );
      },
    );

    _tester().testGameWidget(
      '§3.0.3 a portal ride pauses the powerup: its timer stops, the effect '
      'is suspended, and both resume after the landing',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _run(game);
        _slot(run).start(CapsuleType.hourglass);
        await _fly(game, run, 1);
        final left = run.state.timed!.remaining;
        expect(run.state.timeScale, closeTo(.45, 1e-9));
        run.state.timed!.paused = true;
        run.ctx.emit(const PowerupPaused(TimedPowerup.hourglass));
        // No slow-motion rides: back to 1 at once, music too.
        expect(run.state.timeScale, 1);
        expect(game.sound.musicRate, 1);
        await _fly(game, run, 1);
        expect(run.state.timed!.remaining, closeTo(left, 1e-9));
        run.state.timed!.paused = false;
        run.ctx.emit(const PowerupResumed(TimedPowerup.hourglass));
        await _fly(game, run, .3);
        expect(run.state.timeScale, closeTo(.45, 1e-9));
        expect(game.sound.musicRate, .72);
        expect(run.state.timed!.remaining, lessThan(left - .25));
      },
    );

    final deathSpy = AnalyticsSpy();
    _tester(spy: deathSpy).testGameWidget(
      '§3.14 a death ends the timed powerup: world speed, bird size and '
      'music back at once, powerup_ended sent',
      setUp: (game, t) async {
        await _setUp(game, t);
        deathSpy.events.clear();
      },
      verify: (game, _) async {
        final run = await _run(game);
        _slot(run).start(CapsuleType.hourglass);
        await _fly(game, run, .5);
        expect(run.state.timeScale, closeTo(.45, 1e-9));
        killRun(game);
        expect(run.state.timed, isNull);
        expect(run.state.timeScale, 1);
        expect(run.clock.timeScale, 1);
        expect(game.sound.musicRate, 1);
        expect(_f<HourglassFeature>(run).owning, isFalse);
        expect(
          deathSpy.events.where((e) => e.$1 == 'powerup_ended').single.$2,
          {'type': 'hourglass'},
        );
      },
    );

    _tester().testGameWidget(
      '§3.14 a death while small: the bird is full size again',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _run(game);
        _slot(run).start(CapsuleType.miniBird);
        await _fly(game, run, .5);
        expect(run.state.birdScale, closeTo(.52, 1e-9));
        killRun(game);
        expect(run.state.birdScale, 1);
        expect(game.runBird!.lookComponent.scale.x, 1);
      },
    );
  });

  group('§3.30 the capsule in the run', () {
    for (final type in CapsuleType.values) {
      _tester().testGameWidget(
        '§3.0.8 / §3.30 a forced ${type.name} capsule floats in its gap '
        '(PRD-2.2 §19.4: 30–70 %, ±50 pt off the line), counts as met on screen (capsule + its '
        'type) and starts its powerup when flown into',
        setUp: _setUp,
        verify: (game, _) async {
          final run = await startRun(
            game,
            startHoopIndex: ElementId.capsule.firstPossible!,
            force: [type.element],
          );
          CapsulePickup? cap() =>
              pickupsOf(game).whereType<CapsulePickup>().firstOrNull;
          await _fly(game, run, 20, until: () => cap()?.announced ?? false);
          final p = cap()!;
          expect(p.type, TimedPowerupInfo.fromCapsule(type));
          // PRD-2.2 §19.4: 30–70 % along the gap, ±50 pt off the straight
          // line between the two slot centres (was: mid-gap on the line).
          final slots = run.spawner.slotLog;
          final i = slots.lastIndexWhere((s) => s.lastRingX < p.position.x);
          final a = slots[i], b = slots[i + 1];
          final u = (p.position.x - a.lastRingX) / (b.trackX - a.lastRingX);
          expect(u, inInclusiveRange(.3 - .01, .7 + .01));
          final line = a.centreY + (b.centreY - a.centreY) * u;
          expect(
            p.position.y,
            closeTo(line + p.plan!.lineOffset, 1),
          );
          expect(p.plan!.lineOffset.abs(), lessThanOrEqualTo(50));
          game.update(1 / 60);
          expect(game.storage.metElements, contains('capsule'));
          expect(game.storage.metElements, contains(type.element.storageId));
          // Fly it in.
          final started = <PowerupStarted>[];
          run.events.on<PowerupStarted>(started.add);
          final bird = game.runBird!;
          for (var f = 0; f < 600 && !p.collected; f++) {
            final y = bird.body.position.y;
            if (y > p.position.y + 4 && bird.body.linearVelocity.y > -40) {
              game.onScreenTap();
            }
            game.update(1 / 60);
          }
          expect(p.collected, isTrue);
          expect(started.single.type, TimedPowerupInfo.fromCapsule(type));
        },
      );
    }
  });

  group('§3.30 Hourglass', () {
    _tester().testGameWidget(
      '§3.30 the world runs at 45 % (eased over 0.2 s), runClock slows with '
      'it, the timer counts real time; ticks every 0.6 s; music 72 %; it '
      'eases back out at the end',
      setUp: _setUp,
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await _run(game);
        final hg = _f<HourglassFeature>(run);
        sfx.clear();
        _slot(run).start(CapsuleType.hourglass);
        final d = run.state.timed!.duration;
        expect(d, inInclusiveRange(10, 20));
        expect(sfx, contains('hourglassStart'));
        expect(game.sound.musicRate, .72);
        await _fly(game, run, .1);
        expect(run.state.timeScale, inExclusiveRange(.45, 1));
        await _fly(game, run, .15);
        expect(run.state.timeScale, closeTo(.45, 1e-9));
        expect(hg.glow!.intensity, closeTo(1, 1e-9));
        // runClock (game time) runs at 45 %; the powerup timer in real time.
        final clock0 = run.state.runClock;
        final left0 = run.state.timed!.remaining;
        await _fly(game, run, 3);
        expect(run.state.runClock - clock0, closeTo(3 * .45, .02));
        expect(left0 - run.state.timed!.remaining, closeTo(3, .02));
        // The bird and the world move at 45 % (cruise ≈ 200 pt/s at the
        // start → ≈ 90 pt per real second).
        final camX0 = run.state.camX;
        await _fly(game, run, 1);
        final cruise = RunConfig.cruise(run.state.runClock);
        expect(run.state.camX - camX0, closeTo(cruise * .45, cruise * .08));
        // Ticks ≈ every 0.6 s of real time; ghosts trail the bird.
        expect(
          sfx.where((s) => s == 'hourglassTick').length,
          inInclusiveRange(6, 8),
        );
        expect(hg.ghosts, isNotEmpty);
        expect(hg.ghosts.length, lessThanOrEqualTo(9));
        // To the end: eases back to 1.
        await _fly(game, run, 20, until: () => run.state.timed == null);
        expect(run.state.timed, isNull);
        expect(sfx, contains('hourglassEnd'));
        expect(game.sound.musicRate, 1);
        await _fly(game, run, .3);
        expect(run.state.timeScale, 1);
        await _fly(game, run, .3); // the last ghosts fade
        expect(hg.owning, isFalse);
        expect(hg.glow, isNull);
      },
    );

    _tester().testGameWidget(
      '§3.30 the HUD stays real time; the timer pill shows the icon, the '
      'draining bar and the seconds left',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _run(game);
        _slot(run).start(CapsuleType.hourglass);
        await flushAndMount(game);
        final pill = RunHud.of(run)!.children.whereType<TimerPill>().single;
        await _fly(game, run, 1);
        final t = run.state.timed!;
        expect(pill.alpha, 1);
        expect(pill.shown, TimedPowerup.hourglass);
        expect(pill.fraction, closeTo(t.remaining / t.duration, .02));
        expect(pill.label, '${t.remaining.ceil()} s');
        expect(pill.position, Vector2(100, CapsuleConfig.pillY));
      },
    );
  });

  group('§3.31 Mini Bird', () {
    _tester().testGameWidget(
      '§3.31 the bird shrinks to 52 % over 0.15 s — hitbox and drawn bird — '
      'for 8 s, then pops back; sounds and bubbles',
      setUp: _setUp,
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await _run(game);
        sfx.clear();
        _slot(run).start(CapsuleType.miniBird);
        expect(sfx, contains('miniStart'));
        await _fly(game, run, .2);
        expect(run.state.birdScale, closeTo(.52, 1e-9));
        expect(game.runBird!.lookComponent.scale.x, closeTo(.52, 1e-6));
        // The spike walls and pickups use the scaled radius.
        final mini = _f<MiniBirdFeature>(run);
        expect(mini.on, isTrue);
        await _fly(game, run, 8, until: () => run.state.timed == null);
        expect(run.state.timed, isNull);
        expect(sfx, contains('miniEnd'));
        await _fly(game, run, .2);
        expect(run.state.birdScale, 1);
        expect(game.runBird!.lookComponent.scale.x, 1);
        expect(mini.owning, isFalse);
      },
    );
  });

  group('§3.32 Coin Frenzy', () {
    _tester().testGameWidget(
      '§3.32 every ring passed pays +5 on top of the normal ring coins for '
      '6 s (source frenzy); rings not yet passed are coin rings',
      setUp: _setUp,
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await _run(game);
        final frenzy = _f<CoinFrenzyFeature>(run);
        final earned = <CoinsEarned>[];
        run.events.on<CoinsEarned>(earned.add);
        sfx.clear();
        _slot(run).start(CapsuleType.coinFrenzy);
        expect(sfx, contains('frenzyStart'));
        for (final h in hoopsOf(game).where((h) => !h.resolved)) {
          expect(CoinFrenzyFeature.isCoinRing(h), isTrue);
        }
        expect(frenzy.border, isNotNull);
        final coins0 = run.state.coinsThisRun;
        run.debugPass(); // non-perfect: 1 + 5
        expect(run.state.coinsThisRun - coins0, 6);
        expect(
          earned.where((e) => e.source == CoinSource.frenzy).single.amount,
          5,
        );
        expect(sfx, contains('frenzyRing'));
        // A ride ring pays nothing extra (the ride pauses the frenzy).
        run.events.emit(const HoopPassed(null, duringRide: true));
        expect(frenzy.paid, 1);
        await _fly(game, run, 6.1, until: () => run.state.timed == null);
        expect(run.state.timed, isNull);
        expect(sfx, contains('frenzyEnd'));
        expect(frenzy.border, isNull);
        final coins1 = run.state.coinsThisRun;
        run.debugPass(perfect: true); // 2, no +5 any more
        expect(run.state.coinsThisRun - coins1, 2);
      },
    );
  });
}
