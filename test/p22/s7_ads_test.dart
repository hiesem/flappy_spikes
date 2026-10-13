import 'dart:async';
import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/fake_ad_overlay.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/tap_catcher.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/game/playfield_viewport.dart';
import 'package:flappy_spikes/run/screens/phoenix_rise.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §7.12: the gameplay banner, resize per scene and the
/// interstitial after each run (WP-7a), with the in-memory fakes.
void main() {
  group('§7.10 ad services', () {
    test('§7.3 unit IDs: release = real units, debug/profile = test units', () {
      expect(
        AdMobBannerAds.androidUnitId,
        'ca-app-pub-2660521344509391/8797133596',
      );
      expect(
        AdMobInterstitialAds.androidUnitId,
        'ca-app-pub-2660521344509391/1357627279',
      );
      expect(
        AdMobRewardedAds.androidUnitId,
        'ca-app-pub-2660521344509391/3758032081',
      );
      expect(
        AdMobBannerAds.androidTestUnitId,
        'ca-app-pub-3940256099942544/9214589741',
      );
      expect(
        AdMobInterstitialAds.androidTestUnitId,
        'ca-app-pub-3940256099942544/1033173712',
      );
      String pick(bool release, TargetPlatform p) => pickAdUnit(
        release: 'real',
        test: 'test',
        iosTest: 'ios',
        releaseMode: release,
        platform: p,
      );
      expect(pick(true, TargetPlatform.android), 'real');
      expect(pick(false, TargetPlatform.android), 'test');
      expect(pick(true, TargetPlatform.iOS), 'ios');
      // The test host runs in debug mode: the test unit.
      expect(
        pickAdUnit(release: 'real', test: 'test', iosTest: 'ios'),
        'test',
      );
    });

    test('Monetization carries rewarded, interstitial, banner and consent; '
        'the fakes keep tests free of interstitials and banners', () {
      final m = Monetization();
      expect(m.ads, isA<FakeRewardedAds>());
      expect(m.interstitial, isA<FakeInterstitialAds>());
      expect(m.banner, isA<FakeBannerAds>());
      expect(m.consent, isA<FakeAdsConsent>());
      expect(m.interstitial.isAvailable, isFalse);
      expect(m.banner.canShow, isFalse);
      // forPlatform on the (non-mobile) test host: fakes.
      expect(Monetization.forPlatform().banner, isA<FakeBannerAds>());
    });

    test('Noop variants never show', () async {
      final i = NoopInterstitialAds();
      await i.initialize();
      i.preload();
      expect(i.isAvailable, isFalse);
      expect(await i.show(), AdResult.unavailable);
      final b = NoopBannerAds();
      await b.initialize();
      b.preload();
      expect(b.canShow, isFalse);
      expect(b.heightDp, isNull);
      expect(b.buildAd(), isNull);
      expect(await NoopRewardedAds().ensureLoaded(), isFalse);
    });

    test('FakeInterstitialAds: onShown once, then completed', () async {
      final i = FakeInterstitialAds(mode: FakeAdMode.succeed);
      var shown = 0;
      expect(await i.show(onShown: () => shown++), AdResult.completed);
      expect(shown, 1);
      i.mode = FakeAdMode.fail;
      expect(await i.show(onShown: () => shown++), AdResult.failed);
      expect(shown, 1);
    });

    test('FakeBannerAds: off by default; loads, fills, disposes', () {
      final b = FakeBannerAds();
      b.preload();
      expect(b.loaded.value, isFalse);
      b.enabled = true;
      b.preload();
      expect(b.loaded.value, isTrue);
      expect(b.buildAd(), isNotNull);
      b.dispose();
      expect(b.loaded.value, isFalse);
      b.fill = false;
      b.preload();
      expect(b.loaded.value, isFalse, reason: 'no fill');
    });

    test('§7.8 RewardedAds.ensureLoaded waits for a load up to the timeout',
        () async {
      final ads = FakeRewardedAds()..mode = FakeAdMode.unavailable;
      expect(await ads.ensureLoaded(timeout: Duration.zero), isFalse);
      ads.loadsAfter = const Duration(milliseconds: 20);
      expect(
        await ads.ensureLoaded(timeout: const Duration(milliseconds: 200)),
        isTrue,
      );
      ads.mode = FakeAdMode.unavailable;
      ads.loadsAfter = const Duration(seconds: 10);
      expect(
        await ads.ensureLoaded(timeout: const Duration(milliseconds: 20)),
        isFalse,
      );
      expect(ads.loadRequests, 3);
    });

    test('FakeAdsConsent: privacy options form can withdraw consent', () async {
      final c = FakeAdsConsent(privacyOptionsRequired: true);
      expect(c.canRequestAds.value, isTrue);
      c.privacyFormResult = false;
      expect(await c.showPrivacyOptions(), isFalse);
      expect(c.canRequestAds.value, isFalse);
      expect(c.privacyFormsShown, 1);
    });
  });

  group('§7.5 banner + resize per scene', () {
    final spy = AnalyticsSpy();
    late FakeBannerAds banner;
    late FakeInterstitialAds interstitial;
    late FakeRewardedAds rewarded;

    FlameTester<FlappySpikesGame> tester({
      double screen = 711,
      double bannerDp = 48,
      bool enabled = true,
      Map<String, Object> prefs = const {},
      VersusService? versus,
    }) => FlameTester<FlappySpikesGame>(
      () {
        spy.events.clear();
        banner = FakeBannerAds(
          enabled: enabled,
          heightDp: bannerDp,
          widthDp: 320,
        );
        interstitial = FakeInterstitialAds();
        rewarded = FakeRewardedAds();
        return createRunTestGame(
          prefs: prefs,
          worldHeight: screen,
          services: spy,
          versus: versus,
          monetization: Monetization(
            ads: rewarded,
            banner: banner,
            interstitial: interstitial,
          ),
        );
      },
      gameSize: Vector2(320, screen),
    );

    Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
      await g.ready();
      await preloadImages(g);
    }

    SpikeStrip ground(FlappySpikesGame g) =>
        g.world.children.query<SpikeStrip>().firstWhere((s) => !s.isCeiling);
    SpikeStrip ceiling(FlappySpikesGame g) =>
        g.world.children.query<SpikeStrip>().firstWhere((s) => s.isCeiling);
    double resolutionY(FlappySpikesGame g) =>
        (g.camera.viewport as PlayfieldViewport).resolution.y;

    void expectFullHeight(FlappySpikesGame g, double h) {
      expect(g.viewHeight, h);
      expect(g.visibleHeight, h);
      expect(g.stripDrop, 0);
      expect(g.bottomStripInset, 44);
      expect(resolutionY(g), h);
      expect(ground(g).body.position.y, closeTo(h - 22, 1e-6));
    }

    tester().testGameWidget(
      '§7.4 off on Home → shown at first flight; §7.5.4 the lowered strip: '
      'visible 663, 24 pt of strip, deadly line follows the teeth',
      setUp: boot,
      verify: (g, _) async {
        expect(g.bannerState.value, BannerState.off);
        expectFullHeight(g, 711);
        // §7.5.1 preloaded on Home, invisible.
        expect(banner.loaded.value, isTrue);
        expect(banner.preloads, 1);

        final run = await startRun(g);
        expect(g.bannerState.value, BannerState.showing);
        expect(g.runHasBanner, isTrue);
        expect(g.visibleHeight, 663);
        expect(g.stripDrop, Config.bannerStripDrop);
        expect(g.viewHeight, 683);
        expect(g.bottomStripInset, 24);
        expect(resolutionY(g), 663);
        // The bottom strip: viewHeight − 44 + drop of the VISIBLE view.
        final groundTop = ground(g).body.position.y - 22;
        expect(groundTop, closeTo(663 - 44 + Config.bannerStripDrop, 1e-6));
        // 18 pt teeth + 6 pt base visible; the tooth line 24 pt above.
        expect(g.visibleHeight - groundTop, 24);
        expect(run.geo.floorTooth, closeTo(663 - 24, 1e-6));
        // The top strip doesn't change.
        expect(ceiling(g).body.position.y, closeTo(22, 1e-6));
        expect(run.geo.topTooth, 44);
        // §3.0.1 the run's band: 595 pt between the strips (Pixel 8).
        expect(run.geo.floorTooth - run.geo.topTooth, 595);
        // Persistent chrome followed the resize.
        final backdrop = g.world.children
            .whereType<RectangleComponent>()
            .firstWhere((c) => c.priority == -1000);
        expect(backdrop.size.y, 683);
        expect(g.world.children.query<TapCatcher>().single.size.y, 683);
        expect(
          g.world.children.query<ScoreHud>().single.position.y,
          closeTo(683 / 2 + 35, 1e-9),
        );
        // §7.6 the interstitial preloads when the bird starts flying (only
        // once it could show: gamesPlayed is 0 here, so no load yet).
        expect(interstitial.preloads, 0);
      },
    );

    tester().testGameWidget(
      '§7.5.2 the bird waiting at its spawn point moves with the resize; a '
      'flying bird does not',
      setUp: boot,
      verify: (g, _) async {
        final bird = g.world.children.query<Bird>().single;
        expect(bird.body.position.y, closeTo(711 / 2, 1e-6));
        await startRun(g);
        // START flapped from the new middle (683 / 2) at once.
        expect(bird.body.position.y, closeTo(683 / 2, 2));
        final y = bird.body.position.y;
        g.setPlayfieldHeight(600, stripDrop: 20);
        expect(bird.body.position.y, y, reason: 'gravity on: not moved');
      },
    );

    tester().testGameWidget(
      '§7.5.2 setPlayfieldHeight re-lays out every PlayfieldResizable',
      setUp: boot,
      verify: (g, _) async {
        final seen = <double>[];
        final probe = PlayfieldResizeCallback(seen.add);
        g.registerResizable(probe);
        expect(g.resizables, contains(probe));
        expect(g.resizables.whereType<SpikeStrip>().length, 2);
        expect(g.resizables.whereType<TapCatcher>().length, 1);
        expect(g.resizables.whereType<Bird>().length, 1);
        g.setPlayfieldHeight(600, stripDrop: 20);
        expect(seen, [620]);
        expect(g.viewHeight, 620);
        expect(g.visibleHeight, 600);
        expect(resolutionY(g), 600);
        expect(ground(g).body.position.y, closeTo(620 - 22, 1e-6));
        g.setPlayfieldHeight(600, stripDrop: 20);
        expect(seen, [620], reason: 'no change, no re-layout');
        g.unregisterResizable(probe);
        g.setPlayfieldHeight(711);
        expect(seen, [620]);
        expectFullHeight(g, 711);
      },
    );

    for (final (name, enabled, prefs) in [
      ('NO ADS owner', true, <String, Object>{'noAds': true}),
      ('no consent', false, <String, Object>{}),
    ]) {
      tester(enabled: enabled, prefs: prefs).testGameWidget(
        '§7.5.6 banner off for $name: no strip, no resize, no load',
        setUp: boot,
        verify: (g, _) async {
          final run = await startRun(g);
          expect(g.bannerState.value, BannerState.off);
          expect(g.runHasBanner, isFalse);
          expectFullHeight(g, 711);
          expect(run.geo.floorTooth, 711 - 44);
          expect(banner.preloads, 0);
        },
      );
    }

    tester(
      versus: FakeVersusService(
        pool: [
          OpponentRun(
            uid: 'u1',
            name: 'BrightOwl',
            score: 3,
            best: 9,
            level: 1,
            timeline: RunTimeline()
              ..addPoint(2)
              ..end(3),
          ),
        ],
      ),
    ).testGameWidget(
      '§7.4 VS intro: the strip is reserved and stays empty; the banner '
      'shows only when the bird flies',
      setUp: boot,
      verify: (g, _) async {
        await g.versus.prefetch();
        g.onScreenTap();
        await flushAndMount(g);
        expect(g.state, GameState.versusIntro);
        expect(g.bannerState.value, BannerState.reservedEmpty);
        expect(g.visibleHeight, 663, reason: 'shrunk before the VS intro');
        final states = <BannerState>{};
        await flushAndMount(g);
        for (var i = 0; i < 1200 && g.state == GameState.versusIntro; i++) {
          states.add(g.bannerState.value);
          g.update(1 / 30);
          await Future<void>.value();
        }
        expect(states, {BannerState.reservedEmpty});
        expect(g.state, GameState.playing);
        // PRD-2.3 §10.1 the bird flies with the first tap.
        expect(g.bannerState.value, BannerState.reservedEmpty);
        g.onPlayfieldTap();
        expect(g.bannerState.value, BannerState.showing);
      },
    );

    tester(
      prefs: {'gamesPlayed': 5, 'feathers': 3},
    ).testGameWidget(
      '§7.12 flow: run → die → revive offer → decline → bonus → results → '
      'NEXT → interstitial → Home at full height, banner state at each step',
      setUp: boot,
      verify: (g, _) async {
        interstitial.mode = FakeAdMode.succeed;
        final hold = Completer<void>();
        interstitial.hold = hold.future;
        final run = await startRun(g);
        expect(g.bannerState.value, BannerState.showing);
        expect(interstitial.preloads, 1, reason: '§7.6 preload at flight');
        // §7.11 one ad_banner_shown per run, at the first impression.
        banner.impression();
        banner.impression();
        expect(
          spy.events.where((e) => e.$1 == 'ad_banner_shown').length,
          1,
        );
        run.state.invulnerable = 0;
        for (var i = 0; i < 8; i++) {
          run.debugPass(perfect: true);
        }
        killRun(g);
        await flushAndMount(g);
        expect(g.state, GameState.reviving);
        expect(g.bannerState.value, BannerState.showing);
        // §7.5.4 under the revive dim the strip greys like the spikes.
        for (var i = 0; i < 60; i++) {
          g.update(1 / 60);
        }
        final dim = g.world.children.query<ReviveDim>().single;
        expect(dim.alpha, closeTo(.62, 1e-6));
        expect(
          g.bannerStripColor.value.toARGB32(),
          const Color(0xFF313131).toARGB32(),
        );
        await declineRevive(g);
        expect(g.state, GameState.bonus);
        expect(g.bannerState.value, BannerState.showing);
        expect(g.visibleHeight, 663);
        final b = g.bonusScreen!;
        for (final i in [0, 1, 2]) {
          expect(b.tapTile(i), isTrue);
          stepGame(g, 1.2);
          await flushAndMount(g);
        }
        for (var i = 0; i < 600 && !b.noThanksShown; i++) {
          g.update(1 / 60);
        }
        expect(b.noThanksShown, isTrue);
        b.tapNoThanks();
        await flushAndMount(g);
        expect(g.state, GameState.results);
        expect(g.bannerState.value, BannerState.showing);
        stepGame(g, 1);
        await flushAndMount(g);
        g.resultsScreen!.next();
        await flushAndMount(g);
        // The video ad is up; the banner stays until it covers it.
        expect(g.interstitialShowing, isTrue);
        expect(g.state, GameState.results);
        expect(g.bannerState.value, BannerState.showing);
        expect(interstitial.shown, 1);
        expect(spy.events.map((e) => e.$1), contains('ad_interstitial_shown'));
        expect(g.storage.noAdsPopupVideos, 1, reason: '§7.6 NO ADS upsell');
        hold.complete();
        await flushAndMount(g);
        expect(g.interstitialShowing, isFalse);
        expect(g.state, GameState.start);
        expect(g.bannerState.value, BannerState.off);
        expectFullHeight(g, 711);
        expect(g.lastFullScreenAdClosedAt, isNotNull);
        // The used banner is dropped and the next one loads on Home.
        stepGame(g, .2);
        expect(banner.disposals, 1);
        expect(banner.preloads, 2);
        expect(banner.loaded.value, isTrue);
      },
    );

    tester(prefs: {'gamesPlayed': 5}).testGameWidget(
      '§7.6 / §7.10 Linux fake interstitial: "TEST AD" overlay for 3 s',
      setUp: boot,
      verify: (g, _) async {
        g.monetization.showFakeAdOverlay = true;
        interstitial.mode = FakeAdMode.succeed;
        await startRun(g);
        killRunThroughSaves(g);
        await declineRevive(g);
        await flushAndMount(g);
        expect(g.state, GameState.results);
        stepGame(g, 1);
        g.goHome();
        await flushAndMount(g);
        final overlay = g.fakeAdOverlay;
        expect(overlay, isNotNull);
        expect(overlay!.interstitial, isTrue);
        expect(overlay.secondsLeft, 3);
        stepGame(g, 1.5);
        expect(g.state, GameState.results);
        stepGame(g, 1.6);
        await flushAndMount(g);
        expect(g.state, GameState.start);
        stepGame(g, .5);
        await flushAndMount(g);
        expect(g.world.children.query<FakeAdOverlay>(), isEmpty);
      },
    );
  });

  group('§7.6 interstitial guards', () {
    final spy = AnalyticsSpy();
    late FakeInterstitialAds interstitial;
    late FakeRewardedAds rewarded;
    var now = DateTime(2026, 10, 12, 12);

    FlameTester<FlappySpikesGame> tester(Map<String, Object> prefs) =>
        FlameTester<FlappySpikesGame>(() {
          spy.events.clear();
          now = DateTime(2026, 10, 12, 12);
          interstitial = FakeInterstitialAds(mode: FakeAdMode.succeed);
          rewarded = FakeRewardedAds();
          return createRunTestGame(
            prefs: prefs,
            services: spy,
            clock: () => now,
            monetization: Monetization(
              ads: rewarded,
              interstitial: interstitial,
            ),
          );
        }, gameSize: Vector2(320, 568));

    Future<void> toResults(FlappySpikesGame g) async {
      await startRun(g);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      expect(g.state, GameState.results);
      stepGame(g, 1);
    }

    Future<String?> next(FlappySpikesGame g) async {
      spy.events.clear();
      g.goHome();
      await flushAndMount(g);
      expect(g.state, GameState.start);
      final skipped = spy.events.where(
        (e) => e.$1 == 'ad_interstitial_skipped',
      );
      if (spy.events.any((e) => e.$1 == 'ad_interstitial_shown')) {
        expect(skipped, isEmpty);
        return null;
      }
      return skipped.single.$2!['reason'] as String;
    }

    tester({'gamesPlayed': 5}).testGameWidget(
      'show path: the 4th+ run, nothing else → the ad plays',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        await toResults(g);
        expect(g.interstitialSkipReason(), isNull);
        expect(await next(g), isNull);
        expect(interstitial.shown, 1);
      },
    );

    tester({'gamesPlayed': 5, 'noAds': true}).testGameWidget(
      'guard 1: NO ADS',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        await toResults(g);
        expect(await next(g), 'no_ads');
        expect(interstitial.shown, 0);
      },
    );

    tester({'gamesPlayed': 2}).testGameWidget(
      'guard 2 (PRD-2.3 §18.2): the new-player grace covers runs 3 and 4, '
      'run 5 shows',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        await toResults(g);
        expect(g.storage.gamesPlayed, 3);
        expect(await next(g), 'new_player');
        await toResults(g);
        expect(g.storage.gamesPlayed, 4);
        expect(await next(g), 'new_player');
        await toResults(g);
        expect(g.storage.gamesPlayed, 5);
        expect(await next(g), isNull);
      },
    );

    tester({'gamesPlayed': 5}).testGameWidget(
      'guard 3: a rewarded ad watched in this run (any displayed one)',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        await startRun(g);
        // E.g. the revive heart; a closed-early ad counts too.
        rewarded.mode = FakeAdMode.succeed;
        await g.showRewardedAd(AdPlacement.revive);
        expect(g.rewardedWatchedThisRun, isTrue);
        now = now.add(const Duration(minutes: 5));
        killRunThroughSaves(g);
        await declineRevive(g);
        await flushAndMount(g);
        stepGame(g, 1);
        expect(await next(g), 'rewarded_this_run');
        // The next run starts clean.
        await toResults(g);
        expect(g.rewardedWatchedThisRun, isFalse);
        expect(await next(g), isNull);
      },
    );

    tester({'gamesPlayed': 5}).testGameWidget(
      'guard 4: < 60 s since the previous full-screen ad closed',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        // A rewarded ad on Home (powerup slot) — not "this run".
        await g.showRewardedAd(AdPlacement.homeSlot);
        await toResults(g);
        now = now.add(const Duration(seconds: 59));
        expect(await next(g), 'cooldown');
        await toResults(g);
        now = now.add(const Duration(seconds: 2));
        expect(await next(g), isNull);
        // The interstitial itself starts the next 60 s.
        await toResults(g);
        now = now.add(const Duration(seconds: 30));
        expect(await next(g), 'cooldown');
      },
    );

    tester({'gamesPlayed': 5}).testGameWidget(
      'guard 5: no interstitial loaded',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        interstitial.mode = FakeAdMode.unavailable;
        await toResults(g);
        expect(await next(g), 'not_loaded');
      },
    );

    tester({'gamesPlayed': 5}).testGameWidget(
      'guard 6: the app is in the background',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        await toResults(g);
        g.lifecycleStateChange(AppLifecycleState.paused);
        expect(g.interstitialSkipReason(), InterstitialSkip.background);
        g.lifecycleStateChange(AppLifecycleState.resumed);
        expect(g.interstitialSkipReason(), isNull);
        g.lifecycleStateChange(AppLifecycleState.hidden);
        expect(await next(g), 'background');
      },
    );

    tester({'gamesPlayed': 5}).testGameWidget(
      'a failed show still goes Home; never mid-run or on a menu',
      setUp: (g, _) async => g.ready(),
      verify: (g, _) async {
        interstitial.mode = FakeAdMode.fail;
        await toResults(g);
        g.goHome();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(interstitial.shown, 1);
        // goHome is a no-op outside the results page.
        g.goHome();
        await startRun(g);
        g.goHome();
        expect(interstitial.shown, 1);
        expect(g.state, GameState.playing);
      },
    );
  });
}
