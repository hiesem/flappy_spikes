import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;

/// QA P2: shortened banner layouts through all rides, and free revive
/// through a real versus run/controller instead of just the ladder.
void main() {
  Future<void> boot(FlappySpikesGame g, _) async {
    await g.ready();
    await preloadImages(g);
  }

  for (final (screen, banner) in [
    (711.0, 48.0),
    (640.0, 44.0),
    (568.0, 44.0),
  ]) {
    final visible = screen - banner;
    for (final id in RideId.values) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: screen,
          seed: 5,
          prefs: {
            'metElements': [for (final e in ElementId.values) e.storageId],
          },
          monetization: Monetization(
            banner: FakeBannerAds(
              enabled: true,
              heightDp: banner,
              widthDp: 320,
            ),
          ),
        ),
        gameSize: Vector2(320, visible),
      ).testGameWidget(
        '§7 / §18 / §27 ${id.name} at $visible: banner survives every phase, '
        'circle never vanishes, control returns with a flap and first hoop '
        'two seconds later; deferred rewards keep two breather hoops',
        setUp: boot,
        verify: (g, tester) async {
          final run = await startRun(g, startHoopIndex: 25, ride: id);
          g.runDebug.god = true;
          final feature = run.features.whereType<PortalRideFeature>().single;
          expect(
            await flyUntil(g, (_) => feature.ride != null, maxSeconds: 40),
            isTrue,
          );
          final ride = feature.ride!;
          final phases = <RidePhase>{};
          for (var i = 0; i < 60 * 30 && !ride.done; i++) {
            g.update(1 / 60);
            phases.add(ride.phase);
            expect(g.visibleHeight, visible);
            expect(g.bannerState.value, BannerState.showing);
            expect(g.scoreHud.visibleOpacity, greaterThanOrEqualTo(.5 - 1e-9));
            if (i % 20 == 0) await flushAndMount(g);
            if (id == RideId.sea && i == 180) {
              await loadFonts();
              await tester.runAsync(
                () => _capture(g, 'sea_${visible.round()}'),
              );
            }
          }
          expect(ride.done, isTrue);
          expect(
            phases,
            containsAll([
              RidePhase.ride,
              RidePhase.exit,
              RidePhase.fly,
              RidePhase.glide,
            ]),
          );
          expect(g.runBirdVelocityY, closeTo(-Config.flapVelocity, 1e-6));
          expect(run.state.cometLanding, isFalse);
          expect(run.state.timeScale, 1);
          expect(g.scoreHud.sceneMix, 0);
          // The spawner synchronizes activity at the next update boundary.
          g.update(1 / 60);
          expect(run.state.activity, isNull);
          final endX = run.state.camX + RunConfig.birdX;
          final first = run.spawner.slotLog.firstWhere((p) => p.trackX > endX);
          final before = run.state.runClock;
          run.debugForce(ElementId.heart);
          run.debugForce(ElementId.pair);
          expect(
            await flyUntil(
              g,
              (r) => r.state.camX + RunConfig.birdX >= first.trackX,
              maxSeconds: 3,
            ),
            isTrue,
          );
          expect(run.state.runClock - before, closeTo(2, .1));
          await flyRun(g, maxSeconds: 6);
          final rewards = run.spawner.gapLog
              .expand((p) => p.items)
              .where((p) => p.trackX > endX && p.kind == ElementId.heart);
          expect(rewards, isNotEmpty);
          for (final reward in rewards) {
            final between = run.spawner.slotLog.where(
              (p) => p.trackX > endX && p.trackX < reward.trackX,
            );
            expect(between.length, greaterThanOrEqualTo(2));
          }
        },
      );
    }
  }

  for (final noAds in [false, true]) {
    final rewarded = FakeRewardedAds();
    final versus = FakeVersusService(
      pool: [
        OpponentRun(
          uid: 'qa-p2-rival',
          name: 'Rival',
          score: 20,
          best: 20,
          level: 1,
          timeline: RunTimeline()
            ..addEntry(3, 20)
            ..end(20),
        ),
      ],
    );
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 568,
        // PRD-2.3.1 §14: a NO ADS owner's 1st revive is a 250 coin revive.
        prefs: {'noAds': noAds, if (noAds) 'coins': 1000},
        versus: versus,
        monetization: Monetization(
          ads: rewarded,
          banner: FakeBannerAds(enabled: true, heightDp: 44, widthDp: 320),
        ),
      ),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      '§7.7 / §24 versus ${noAds ? '250 coin (PRD-2.3.1 §14)' : 'ad'} '
      'revive: thirty-second wait preserves the opponent and score, then '
      'exactly one phoenix${noAds ? '' : ' without charging coins'}',
      setUp: boot,
      verify: (g, _) async {
        await versus.prefetch();
        final run = await startRun(g);
        expect(run.setup.opponent, isNotNull);
        for (var i = 0; i < 8; i++) {
          run.debugPass(perfect: true);
        }
        killRunThroughSaves(g);
        await flushAndMount(g);
        expect(g.state, GameState.reviving);
        final screen = g.reviveScreen!;
        expect(
          screen.offer.kind,
          noAds ? ReviveOfferKind.coins : ReviveOfferKind.ad,
        );
        final score = run.state.score;
        final time = run.state.runClock;
        final balance = g.menu.wallet.balance;
        final opponent = run.setup.opponent;
        await stepSeconds(g, 30);
        expect(g.state, GameState.reviving);
        expect(run.state.score, score);
        expect(run.state.runClock, time);
        final phoenix = <RevivePhoenixStarted>[];
        run.events.on<RevivePhoenixStarted>(phoenix.add);
        screen.tapHeart();
        for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
          g.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(g);
        }
        expect(g.state, GameState.playing);
        expect(phoenix, hasLength(1));
        expect(phoenix.single.kind, noAds ? ReviveKind.coins : ReviveKind.ad);
        expect(g.menu.wallet.balance, balance - (noAds ? 250 : 0));
        expect(rewarded.shown, noAds ? 0 : 1);
        expect(run.setup.opponent, same(opponent));
        expect(run.state.score, score);
        expect(g.visibleHeight, noAds ? 568 : 524);
        expect(run.state.adStepAvailableThisGame, isFalse);
      },
    );
  }
}

/// `captureShot` pattern: resize immediately before rendering. Crop to
/// the actual visible height (the banner slot stays outside the capture).
Future<void> _capture(FlappySpikesGame g, String name) async {
  final size = Vector2(640, g.visibleHeight * 2);
  g.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  final picture = rec.endRecording();
  final image = await picture.toImage(size.x.round(), size.y.round());
  picture.dispose();
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('build/qa_p2/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
