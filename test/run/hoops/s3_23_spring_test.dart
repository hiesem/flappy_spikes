import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/spring.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c: the Spring Ring (PRD-2 §3.23, §5.22).
void main() {
  test('§3.23 launch −770 pt/s up / +420 down, flap lock 0.45 / 0.28 s; up '
      'rises ≈ 235 pt (two flaps)', () {
    expect(SpringConfig.launchUp, -770);
    expect(SpringConfig.launchDown, 420);
    expect(SpringConfig.lockUp, .45);
    expect(SpringConfig.lockDown, .28);
    final rise =
        SpringConfig.launchUp * SpringConfig.launchUp / (2 * RunConfig.gravity);
    expect(rise, closeTo(235, 3));
    expect(RunConfig.springJump, 240);
  });

  test('§3.23 the spring has room for its 240 pt jump inside the band at '
      '568 and 711 from hoop 10 (WP-3c fix: band rule, not the row range)', () {
    for (final vh in [568.0, 711.0]) {
      var springs = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet(),
        );
        final plans = <SlotPlan>[];
        for (var k = 0; k < 60; k++) {
          final ctx = DirectorContext.open(vh);
          final s = d.nextSlot(ctx);
          d.nextGap(ctx, s);
          plans.add(s);
        }
        for (final s in plans.where(
          (s) => s.kind == HoopKindId.spring && s.index + 1 < plans.length,
        )) {
          springs++;
          final next = plans[s.index + 1];
          final dir = s.extra == SpringDir.up ? -1 : 1;
          // A portal ring after it keeps its fixed 118 pt (PRD-2.2 §25.1) and
          // is clamped into the band for that size: the launch still lands
          // inside its opening (PRD-2.3 moved the portal to hoop 40+).
          final tol = next.kind == HoopKindId.portal
              ? next.opening / 2 - RunConfig.birdRadius
              : 1e-6;
          expect(
            next.centreY - s.centreY,
            closeTo(dir * 240, tol),
            reason: '$next',
          );
          final ctx = DirectorContext.open(vh);
          final m =
              next.opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin;
          expect(next.centreY, greaterThanOrEqualTo(ctx.topTooth + m - 1e-6));
          expect(next.centreY, lessThanOrEqualTo(ctx.floorTooth - m + 1e-6));
        }
      }
      expect(springs, greaterThan(5), reason: 'at $vh');
    }
  });

  test('§5.22 wobble ±7 pt over 0.5 s', () {
    expect(SpringHoopKind.wobbleAt(0), 0);
    for (var b = .01; b <= 1; b += .01) {
      expect(SpringHoopKind.wobbleAt(b).abs(), lessThanOrEqualTo(7 * b + 1e-9));
    }
    expect(SpringConfig.wobbleSeconds, .5);
    expect(SpringConfig.front.toARGB32(), 0xFF2EBD6B);
    expect(SpringConfig.back.toARGB32(), 0xFF1E8A4C);
  });

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> testerFor(int seed) =>
      FlameTester<FlappySpikesGame>(() {
        spy = AnalyticsSpy();
        return createRunTestGame(worldHeight: 711, services: spy, seed: seed);
      }, gameSize: Vector2(320, 711));
  final tester = testerFor(3);
  final dirs = <int>{};

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  Future<(RunController, Hoop)> toSpring(FlappySpikesGame game) async {
    final run = await startRun(
      game,
      startHoopIndex: 10,
      force: [ElementId.spring],
    );
    expect(
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.spring) != null),
      isTrue,
    );
    return (run, firstHoopOf(game, HoopKindId.spring)!);
  }

  for (final seed in [3, 4]) {
    testerFor(seed).testGameWidget(
      '§3.23 passing launches the bird its arrows\' way; taps are ignored for '
      'the lock, then work again; boing sound, BOING pop, wobble, spring_used '
      '(seed $seed)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await toSpring(game);
        final sfx = sfxLog(game);
        final up = SpringHoopKind.dirOf(h) < 0;
        dirs.add(SpringHoopKind.dirOf(h));
        expect(h.kind.usesTierLook, isFalse);
        expect(await passHoopAt(game, h), isTrue);
        expect(h.takenRing, 0);
        final vy = game.runBirdVelocityY!;
        // One frame of gravity since the launch at most.
        expect(
          vy,
          closeTo(up ? SpringConfig.launchUp : SpringConfig.launchDown, 25),
        );
        expect(run.state.flapLock, greaterThan(0));
        expect(run.flapLocked, isTrue);
        // A tap during the lock changes nothing.
        final before = game.runBirdVelocityY!;
        game.onScreenTap();
        expect(game.runBirdVelocityY, before);
        expect(sfx, contains(up ? 'springUp' : 'springDown'));
        expect(SpringHoopKind.wobbleOf(h), greaterThan(0));
        expect(spy.events.where((e) => e.$1 == 'spring_used').single.$2, {
          'dir': up ? 'up' : 'down',
        });
        await flushAndMount(game);
        expect(
          run.layers.fx.children.whereType<TextPop>().single.text,
          up ? 'BOING ↑' : 'BOING ↓',
        );
        // The lock runs out after 0.45 / 0.28 s of game time.
        var t = 0.0;
        while (run.flapLocked) {
          game.update(1 / 60);
          t += 1 / 60;
        }
        expect(
          t,
          closeTo(up ? SpringConfig.lockUp : SpringConfig.lockDown, 2 / 60),
        );
        game.onScreenTap();
        expect(game.runBirdVelocityY, closeTo(RunConfig.flapVelocity, 1));
        // The wobble is over after 0.5 s.
        for (var i = 0; i < 40; i++) {
          game.update(1 / 60);
        }
        expect(SpringHoopKind.wobbleOf(h), 0);
      },
    );
  }

  for (final dir in SpringDir.values) {
    tester.testGameWidget(
      '§3.23 a ${dir.name} spring sets vy and the flap lock',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await toSpring(game);
        final p = h.plan;
        final fake = Hoop(
          plan: SlotPlan(
            index: p.index,
            kind: p.kind,
            element: p.element,
            trackX: p.trackX,
            centreY: p.centreY,
            opening: p.opening,
            advance: p.advance,
            extra: dir,
          ),
          kind: h.kind,
        );
        fake.kind.onPass(fake, const PassInfo(ring: 0, perfect: true), run.ctx);
        final up = dir == SpringDir.up;
        expect(
          game.runBirdVelocityY,
          up ? SpringConfig.launchUp : SpringConfig.launchDown,
        );
        expect(
          run.state.flapLock,
          up ? SpringConfig.lockUp : SpringConfig.lockDown,
        );
      },
    );
  }

  test('§3.23 up and down come up about equally often (Q62)', () {
    var up = 0, down = 0;
    for (var seed = 1; seed <= 80; seed++) {
      final d = RunDirector(
        seed: seed,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      );
      for (var k = 0; k < 80; k++) {
        final ctx = DirectorContext.open(711);
        final s = d.nextSlot(ctx);
        d.nextGap(ctx, s);
        if (s.kind != HoopKindId.spring) continue;
        s.extra == SpringDir.up ? up++ : down++;
      }
    }
    expect(up, greaterThan(10));
    expect(down, greaterThan(10));
    expect(up / (up + down), inInclusiveRange(.3, .7));
    expect(dirs, isNotEmpty);
  });

  tester.testGameWidget(
    '§3.23 up launch rises ≈ 235 pt; the next ring sits 240 pt away and the '
    'autopilot reaches it',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h) = await toSpring(game);
      final up = SpringHoopKind.dirOf(h) < 0;
      expect(await passHoopAt(game, h), isTrue);
      final y0 = game.runBirdPosition!.y;
      var top = y0;
      for (var i = 0; i < 40; i++) {
        game.update(1 / 60);
        final y = game.runBirdPosition!.y;
        if (y < top) top = y;
      }
      if (up) expect(y0 - top, closeTo(235, 15));
      await flyUntil(
        game,
        (r) => r.spawner.slotLog.any((p) => p.index == h.plan.index + 1),
      );
      final next = run.spawner.slotLog.firstWhere(
        (p) => p.index == h.plan.index + 1,
      );
      expect(next.centreY - h.plan.centreY, closeTo((up ? -1 : 1) * 240, 1e-6));
      final passed = run.state.hoopsPassed;
      expect(await flyUntil(game, (r) => r.state.hoopsPassed > passed), isTrue);
      expect(run.ended, isFalse);
    },
  );

  tester.testGameWidget(
    '§3.0.3 during the comet boost a spring does not launch',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h) = await toSpring(game);
      final vy = game.runBirdVelocityY!;
      h.kind.onPass(
        h,
        const PassInfo(ring: 0, perfect: true, duringRide: true),
        run.ctx,
      );
      expect(run.state.flapLock, 0);
      expect(game.runBirdVelocityY, vy);
    },
  );
}
