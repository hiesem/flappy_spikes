import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/run/screens/revive_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §24 the revive page: only the heart, GET COINS (locked) and No
/// thanks react; every other tap does nothing (no decline, no sound, no
/// animation, nothing reaches the run). §7.15: it never moves on by itself.
void main() {
  const h = 711.0;
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      return createRunTestGame(prefs: prefs, services: spy, worldHeight: h);
    },
    gameSize: Vector2(320, h),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  Future<(RunController, ReviveScreen)> toOffer(FlappySpikesGame g) async {
    final run = await startRun(g);
    run.state.invulnerable = 0;
    for (var i = 0; i < 6; i++) {
      run.debugPass(perfect: true);
    }
    killRunThroughSaves(g);
    for (var i = 0; i < 600 && g.state == GameState.dying; i++) {
      g.update(1 / 60);
    }
    await flushAndMount(g);
    expect(g.state, GameState.reviving);
    final screen = g.reviveScreen!;
    for (var i = 0; i < 30 && screen.ui < 1; i++) {
      g.update(1 / 60);
    }
    return (run, screen);
  }

  Future<void> tap(WidgetTester tester, FlappySpikesGame g, Offset p) async {
    final rect = tester.getRect(find.byGame<FlappySpikesGame>());
    // Viewport (screen) points → the widget (the fixed 320 pt resolution
    // is letterboxed into the test surface).
    final v = g.camera.viewport.localToGlobal(Vector2(p.dx, p.dy));
    await tester.tapAt(rect.topLeft + Offset(v.x, v.y));
    // Past the MultiTapGestureRecognizer's countdown (no pending timer).
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Points outside the heart, No thanks and GET COINS: the corners, the
  /// coin pill, the dead bird, the score circle, between the heart and No
  /// thanks, beside the heart and empty space.
  List<Offset> outside(FlappySpikesGame g, ReviveScreen s) {
    final heart = s.heartRect;
    final bird = g.runBirdPosition!;
    return [
      const Offset(8, 8),
      const Offset(312, 8),
      const Offset(8, h - 8),
      const Offset(312, h - 8),
      s.pillRect.center,
      Offset(bird.x, bird.y),
      const Offset(160, 130), // the score circle's band
      Offset(160, heart.bottom + 30), // between the heart and No thanks
      Offset(20, heart.center.dy),
      Offset(300, heart.center.dy),
      Offset(30, heart.bottom + ReviveConfig.noThanksGap),
      const Offset(160, h - 80),
    ];
  }

  tester().testGameWidget(
    '§24 taps outside the heart / No thanks do nothing: screen up, no '
    'sound, no revive_declined, no flap, nothing reaches the run',
    setUp: boot,
    verify: (g, tester) async {
      final (run, screen) = await toOffer(g);
      final sounds = sfxLog(g)..clear();
      spy.events.clear();
      final vy = g.runBird!.body.linearVelocity.y;
      final pops = <double>[];
      for (final p in outside(g, screen)) {
        await tap(tester, g, p);
        g.update(1 / 60);
        pops.add(screen.beat);
        expect(screen.phase, RevivePhase.offer, reason: 'tap at $p');
      }
      expect(g.state, GameState.reviving);
      expect(g.reviveScreen, same(screen));
      expect(sounds, isEmpty, reason: 'no sound, no flap');
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_declined')));
      expect(
        spy.events.map((e) => e.$1),
        isNot(contains('revive_locked_tap')),
      );
      expect(g.runBird!.body.linearVelocity.y, vy);
      expect(run.dying, isTrue);
      // The page blocks every tap below it while offering.
      expect(screen.containsLocalPoint(Vector2(8, 8)), isTrue);
    },
  );

  tester().testGameWidget(
    '§24 a tap inside the No thanks box declines and the next screen follows',
    setUp: boot,
    verify: (g, tester) async {
      final (_, screen) = await toOffer(g);
      final heart = screen.heartRect;
      // Inside the 160 × ≈ 50 box around the text, off its centre.
      await tap(
        tester,
        g,
        Offset(100, heart.bottom + ReviveConfig.noThanksGap + 4),
      );
      expect(spy.events.map((e) => e.$1), contains('revive_declined'));
      for (var i = 0; i < 60 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
      }
      await flushAndMount(g);
      expect(g.state, isNot(GameState.reviving));
    },
  );

  tester().testGameWidget(
    '§24 a tap on the heart revives (the ad offer) as today',
    setUp: boot,
    verify: (g, tester) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final (_, screen) = await toOffer(g);
      expect(screen.offer.isAd, isTrue);
      await tap(tester, g, screen.heartRect.center);
      for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(g);
      }
      expect(ads.placements, [AdPlacement.revive]);
      expect(g.state, GameState.playing);
    },
  );

  tester().testGameWidget(
    '§24 a locked heart only shakes (no decline, no payment)',
    setUp: boot,
    verify: (g, tester) async {
      final run = await startRun(g);
      // The ad step is used: the 250 coin offer, which the wallet cannot pay.
      ReviveLadder.record(run.state, const ReviveOffer.ad());
      final (_, screen) = await toOffer(g);
      await g.menu.wallet.spend(g.menu.wallet.balance, 'test');
      g.update(1 / 60);
      expect(screen.locked, isTrue);
      await tap(tester, g, screen.heartRect.center);
      expect(spy.events.map((e) => e.$1), contains('revive_locked_tap'));
      expect(screen.phase, RevivePhase.offer);
      expect(g.state, GameState.reviving);
    },
  );

  tester().testGameWidget(
    '§24 / §7.15 after 30 s without a tap the page is still up; the back '
    'gesture does nothing on it',
    setUp: boot,
    verify: (g, tester) async {
      final (_, screen) = await toOffer(g);
      for (var i = 0; i < 30 * 60; i++) {
        g.update(1 / 60);
      }
      expect(g.state, GameState.reviving);
      expect(screen.phase, RevivePhase.offer);
      expect(screen.drain, 1);
      g.handleSystemBack();
      g.update(1 / 60);
      expect(screen.phase, RevivePhase.offer);
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_declined')));
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_timeout')));
      // Pressing the empty heart still revives (and reports the wait).
      screen.tapHeart();
      for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(g);
      }
      expect(g.state, GameState.playing);
      final waited = spy.events
          .where((e) => e.$1 == 'revive_offer_waited')
          .single
          .$2!;
      expect(waited['seconds'], 25);
    },
  );
}
