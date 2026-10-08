import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/star_trail_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/text_pop.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/star_trail_feature.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/pickups/star_trail.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e: the Star Trail (PRD-2 §3.26 rules, §5.25 look / sound).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  StarTrailFeature featureOf(RunController r) =>
      r.features.whereType<StarTrailFeature>().single;

  StarTrail? trailOf(FlappySpikesGame g) =>
      pickupsOf(g).whereType<StarTrail>().firstOrNull;

  /// Spawns a trail from [x0] to [x1] on the flat line [y0] (a symmetric arc).
  void spawnTrail(
    RunController run,
    FlappySpikesGame game, {
    double lead = 70,
    double span = 300,
  }) {
    final bird = run.birdTrackPosition()!;
    final y = bird.y;
    final x0 = bird.x + lead;
    run.spawner.spawnItem(
      GapItemPlan(
        kind: ElementId.starTrail,
        trackX: x0,
        toTrackX: x0 + span,
        y: y,
        toY: y,
        extra: StarTrailConfig.stars,
      ),
    );
  }

  /// The nearest uncollected star ahead of [birdTrackX].
  Offset? nextStar(RunController run, double birdTrackX) {
    final trail = run.spawner.pickups.whereType<StarTrail>().firstOrNull;
    if (trail == null) return null;
    Offset? best;
    for (var i = 0; i < trail.caught.length; i++) {
      if (trail.caught[i]) continue;
      final s = trail.starAt(i);
      if (s.dx < birdTrackX - 6) continue;
      if (best == null || s.dx < best.dx) best = s;
    }
    return best;
  }

  /// Flies with the bird glued to each star in turn; once [bail] holds it is
  /// parked at the absolute y [parkY] (out of the arc's reach).
  Future<void> glide(
    FlappySpikesGame game,
    RunController run,
    bool Function() done, {
    bool Function()? bail,
    double Function()? parkY,
    double maxSeconds = 25,
  }) async {
    for (var f = 0; f < maxSeconds * 60 && !done(); f++) {
      final bird = run.birdTrackPosition();
      if (bird != null) {
        if (bail?.call() ?? false) {
          game.runBird!.setFlight(y: parkY?.call() ?? bird.y, vy: 0);
        } else {
          final s = nextStar(run, bird.x);
          if (s != null && s.dx - bird.x < 160) {
            game.runBird!.setFlight(y: s.dy, vy: 0);
          }
        }
      }
      game.update(1 / 60);
      if (f % 10 == 0) await flushAndMount(game);
    }
  }

  group('§3.26 / §5.25 Star Trail rules (pure)', () {
    test('§3.26 8 stars at u = (i+1)/9, all 8 → +5 coins', () {
      expect(StarTrailConfig.stars, 8);
      expect(RunConfig.starTrailStars, 8);
      expect(StarTrailConfig.u(0), closeTo(1 / 9, 1e-9));
      expect(StarTrailConfig.u(7), closeTo(8 / 9, 1e-9));
      expect(StarTrailConfig.reward, 5);
      expect(RunConfig.starTrailBulge, 40);
      expect(RunConfig.starTrailInset, 40);
      expect(ElementId.starTrail.firstPossible, 5);
    });

    test('§5.25 look: 8 pt gold stars with a pale core, halo r 16 α .45, a '
        '2 / 6 dotted gold line, banner text', () {
      expect(StarTrailConfig.starBase, 8);
      expect(StarTrailConfig.starPulse, 1.6);
      expect(StarTrailConfig.starPulseOmega, 6);
      expect(StarTrailConfig.gold, const Color(0xFFFFB529));
      expect(StarTrailConfig.core, const Color(0xFFFFF8E1));
      expect(StarTrailConfig.haloR, 16);
      expect(StarTrailConfig.haloAlpha, .45);
      expect(StarTrailConfig.lineWidth, 2);
      expect(StarTrailConfig.lineDashes, [2, 6]);
      expect(StarTrailConfig.lineAlpha, .45);
      expect(StarTrailConfig.bannerText, 'PERFECT LINE');
      expect(StarTrailConfig.bannerSub, '8 / 8 stars · +5 coins');
      expect(StarTrailConfig.popColor, const Color(0xFFB87F00));
      expect(StarTrailConfig.sparkleSize, 12);
      expect(StarTrailConfig.sparkleLife, .4);
    });

    test('§5.25 the collected star plays the next note of C major; all 8 a '
        'chord', () {
      expect(StarTrailConfig.notes.length, 8);
      expect(
        StarTrailConfig.notes.map((s) => s.name),
        [
          'trailNote1',
          'trailNote2',
          'trailNote3',
          'trailNote4',
          'trailNote5',
          'trailNote6',
          'trailNote7',
          'trailNote8',
        ],
      );
    });

    test('§3.0.3 hit radius 10, registered pickup kind', () {
      expect(PickupRadii.star, 10);
      expect(PickupRadii.forElement(ElementId.starTrail), 10);
      expect(pickupKindFor(ElementId.starTrail), isA<StarTrailKind>());
      expect(registeredPickupElements(), contains(ElementId.starTrail));
    });
  });

  final spy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5, services: spy),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.26 all 8 stars: PERFECT LINE, +5 coins (star_trail), the 8 notes and '
    'the chord, no "n / 8" pop',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      spy.events.clear();
      final run = await startRun(game);
      game.runDebug.god = true; // the bird is hand-flown along the arc
      final sfx = sfxLog(game);
      final coins0 = run.state.coinsThisRun;
      final bySource = <CoinSource, int>{};
      void onCoins(CoinsEarned e) =>
          bySource.update(e.source, (n) => n + e.amount, ifAbsent: () => e.amount);
      run.events.on<CoinsEarned>(onCoins);
      spawnTrail(run, game);
      await flushAndMount(game);
      final trail = trailOf(game)!;
      final feature = featureOf(run);
      await glide(game, run, () => feature.trails > 0);
      run.events.off<CoinsEarned>(onCoins);
      expect(feature.trails, 1);
      expect(feature.perfects, 1);
      expect(trail.caughtCount, 8);
      expect(run.state.trails.caught[trail.trailId], 8);
      // Only the trail's own payout (the glide also grazes normal hoops).
      expect(bySource[CoinSource.starTrail], StarTrailConfig.reward);
      expect(run.state.coinsThisRun - coins0, greaterThanOrEqualTo(5));
      expect(
        sfx.where((n) => n.startsWith('trailNote')).toList(),
        [
          'trailNote1',
          'trailNote2',
          'trailNote3',
          'trailNote4',
          'trailNote5',
          'trailNote6',
          'trailNote7',
          'trailNote8',
        ],
      );
      expect(sfx, contains('trailChord'));
      expect(
        run.layers.fx.children.whereType<TextPop>().map((p) => p.text),
        isNot(contains('8 / 8')),
      );
      final trails = analyticsLog(
        spy,
      ).where((e) => e.$1 == 'star_trail').toList();
      expect(trails, hasLength(1));
      expect(trails.single.$2, equals(<String, Object>{'stars': 8}));
      // The banner is PERFECT LINE.
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'PERFECT LINE');
      // The wallet got the payout.
      await flushAndMount(game);
      expect(game.menu.wallet.balance, greaterThanOrEqualTo(5));
      expect(run.ended, isFalse);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.26 fewer than 8: the "n / 8" pop, no coins (single stars pay '
    'nothing), no banner',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true; // the bird is hand-flown along the arc
      final coins0 = run.state.coinsThisRun;
      spawnTrail(run, game);
      await flushAndMount(game);
      final trail = trailOf(game)!;
      final feature = featureOf(run);
      // Collect the first three, then park the bird well below the arc.
      await glide(
        game,
        run,
        () => feature.trails > 0,
        bail: () => trail.caughtCount >= 3,
        parkY: () => trail.plan.y! + 150,
      );
      expect(feature.trails, 1);
      expect(feature.perfects, 0);
      expect(trail.caughtCount, 3);
      expect(run.state.trails.caught[trail.trailId], 3);
      expect(run.state.coinsThisRun, coins0);
      await flushAndMount(game); // mount the enqueued TextPop
      final pops = run.layers.fx.children
          .whereType<TextPop>()
          .map((p) => p.text)
          .toList();
      expect(pops, contains('3 / 8'));
      expect(RunHud.ensureFor(run).banners.current, isNull);
      expect(sfxLog(game), isNot(contains('trailChord')));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 568, seed: 11),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§3.26 the arc: the stars sit on a 40 pt bulge at u = (i+1)/9 and one '
    'star alone pays nothing',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true; // the bird is hand-flown along the arc
      final coins0 = run.state.coinsThisRun;
      spawnTrail(run, game);
      await flushAndMount(game);
      final trail = trailOf(game)!;
      final mid = trail.position.y;
      for (var i = 0; i < 8; i++) {
        final u = (i + 1) / 9;
        final s = trail.starAt(i);
        expect(s.dx, closeTo(trail.plan.trackX + 300 * u, 1e-6));
        expect(
          s.dy,
          closeTo(mid - math.sin(math.pi * u) * 40, 1e-6),
          reason: 'star $i bulges up to 40 pt',
        );
      }
      // The arc peaks at u = 0.5 (between stars 3 and 4): the lowest star
      // sits 40 pt up (the bulge), the ends on the line.
      final lowest = [
        for (var i = 0; i < 8; i++) trail.starAt(i).dy,
      ].reduce(math.min);
      expect(lowest, closeTo(mid - 40, .7));
      expect(trail.starAt(0).dy, closeTo(mid - math.sin(math.pi / 9) * 40, 1e-9));
      final feature = featureOf(run);
      await glide(
        game,
        run,
        () => feature.trails > 0,
        bail: () => trail.caughtCount >= 1,
        parkY: () => trail.plan.y! + 150,
      );
      expect(feature.trails, 1);
      expect(trail.caughtCount, 1);
      expect(run.state.coinsThisRun, coins0);
      await flushAndMount(game); // mount the enqueued TextPop
      expect(
        run.layers.fx.children.whereType<TextPop>().map((p) => p.text),
        contains('1 / 8'),
      );
    },
  );
}
