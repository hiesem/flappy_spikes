import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/levels/level_progress.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/phoenix_rise.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// QA fault injection uses the existing plugin's platform interface.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../helpers.dart';

// Independent QA round P2: the five defects it found (S6-20 … S6-24) are
// fixed in `Fix P2 R1`; the regressions below run with, and guard, the fix.
void main() {
  setUpAll(tzdata.initializeTimeZones);
  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  void qa(
    String name,
    Future<void> Function(FlappySpikesGame, WidgetTester) body, {
    double height = 711,
    Map<String, Object> prefs = const {},
  }) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, seed: 21, prefs: prefs),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      name,
      setUp: (g, _) => boot(g),
      verify: (g, tester) => body(g, tester),
    );
  }

  Future<void> endWith(FlappySpikesGame g, int score) async {
    final r = await startRun(g);
    r.ctx.addScore(score);
    killRun(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
  }

  for (final h in [568.0, 711.0]) {
    qa(
      'P2 journey ($h): real home slot, forced course, pause/background, '
      'ad + 250/500/1000 revives, CLAIM, NEXT and fresh ladder',
      (g, tester) async {
        g.menu.slot.debugForce = Powerup.bigHoops;
        g.menu.slot.rollForArrival();
        g.runDebug.force.addAll([
          ElementId.angledRing,
          ElementId.movingRing,
          ElementId.heart,
        ]);
        stepGame(g, .6);
        await flushAndMount(g);
        await g.tapPowerupSlot();
        await flushAndMount(g);
        final r = g.run!;
        expect(r.state.bigHoops, isNotNull);
        expect(g.storage.armedPowerup, 'none');
        final flight = await flyRun(g, untilHoops: 12, maxSeconds: 45);
        expect(
          flight.hoops,
          greaterThanOrEqualTo(12),
          reason: flight.trace.join('\n'),
        );
        expect(r.spawner.slotLog.any((p) => p.tiltDeg != 0), isTrue);
        expect(r.spawner.slotLog.any((p) => p.motion != null), isTrue);
        final clock = r.state.runClock, cam = r.state.camX;
        final bird = g.runBirdPosition!;
        g.pause();
        await flushAndMount(g);
        stepGame(g, 2);
        expect(r.state.runClock, clock);
        expect(r.state.camX, cam);
        expect(g.runBirdPosition, bird);
        g.resume();
        expect(g.state, GameState.playing);
        g.lifecycleStateChange(AppLifecycleState.inactive);
        expect(g.state, GameState.paused);
        g.lifecycleStateChange(AppLifecycleState.resumed);
        expect(g.state, GameState.paused);
        g.resume();
        final earned = r.state.coinsThisRun;
        final played = g.storage.gamesPlayed;
        final before = g.menu.wallet.balance;
        var spent = 0;
        for (final price in [0, 250, 500, 1000]) {
          r.state
            ..shield = false
            ..extraLife = false
            ..invulnerable = 0
            ..egg = EggState()
            ..piggy = PiggyState()
            ..jar = JarState();
          killRun(g, MistakeCause.spikes);
          await flushAndMount(g);
          expect(r.state.egg, isNull);
          expect(r.state.piggy, isNull);
          expect(r.state.jar, isNull);
          expect(g.state, GameState.reviving);
          final screen = g.reviveScreen!;
          expect(screen.offer.price, price);
          expect(screen.offer.isAd, price == 0);
          final stopped = r.state.runClock;
          stepGame(g, .5);
          screen.tapHeart();
          for (
            var frame = 0;
            frame < 400 && g.state == GameState.reviving;
            frame++
          ) {
            g.update(1 / 60);
            if (g.state == GameState.reviving) {
              expect(r.state.runClock, stopped);
            }
            if (frame % 5 == 0) await flushAndMount(g);
          }
          expect(g.state, GameState.playing);
          expect(g.runBirdPosition!.x, closeTo(70, .01));
          expect(r.state.invulnerable, closeTo(2, .05));
          expect(g.storage.gamesPlayed, played);
          spent += price;
          expect(g.menu.wallet.balance, before - spent);
        }
        expect(r.state.revivesThisGame, 4);
        expect(r.state.coinRevives, 3);
        expect((g.monetization.ads as FakeRewardedAds).placements, [
          AdPlacement.homeSlot,
          AdPlacement.revive,
        ]);
        r.state.invulnerable = 0;
        killRun(g);
        await flushAndMount(g);
        expect(g.reviveScreen!.offer.price, 2000);
        await declineRevive(g);
        final page = g.resultsScreen!;
        expect(page.model.reward, earned);
        expect(g.storage.gamesPlayed, played + 1);
        expect(g.storage.unclaimedLevelReward, 50);
        stepGame(g, 4.2);
        await flushAndMount(g);
        expect(page.claimShowing, isTrue);
        page.claimButton.button.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before - spent + 50);
        expect(g.storage.unclaimedLevelReward, 0);
        stepGame(g, 1.6);
        expect(page.shownReward, earned + 50);
        page.next();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.levelUpPopup, isNull);
        stepGame(g, .6);
        await startRun(g);
        for (var i = 0; i < 6; i++) {
          g.run!.debugPass();
        }
        killRun(g);
        await flushAndMount(g);
        expect(g.reviveScreen!.offer.isAd, isTrue);
      },
      height: h,
      prefs: const {'coins': 10000},
    );
  }

  // Derive the restart image from a real run's persisted preferences.
  Map<String, Object>? killedBeforeClaim;
  qa('P2 kill before CLAIM: persist the actual results-page reward', (
    g,
    tester,
  ) async {
    await endWith(g, 12);
    expect(g.storage.unclaimedLevelReward, 50);
    final prefs = await SharedPreferences.getInstance();
    killedBeforeClaim = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    expect(killedBeforeClaim!['unclaimedLevelReward'], 50);
    expect(g.storage.claimedLevels, isEmpty);
  });
  FlameTester<FlappySpikesGame>(
    () =>
        createRunTestGame(prefs: killedBeforeClaim!, services: AnalyticsSpy()),
  ).testGameWidget(
    'P2 restart after kill before CLAIM: one credit, no popup',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      expect(g.storage.coins, (killedBeforeClaim!['coins'] as int? ?? 0) + 50);
      expect(g.storage.claimedLevels, {1});
      expect(g.storage.unclaimedLevelReward, 0);
      expect(await claimLevelRewards(g, 'app_start'), 0);
      stepGame(g, 1);
      expect(g.levelUpPopup, isNull);
    },
  );

  test('P2 reminders: spring DST and persisted daily plans', () async {
    final zone = tz.getLocation('Europe/Amsterdam');
    final platform = FakeReminderPlatform();
    SharedPreferences.setMockInitialValues({});
    var now = tz.TZDateTime(zone, 2027, 3, 24, 9);
    final delivered = <int, DateTime>{};
    final offsets = <int>{};
    for (var day = 0; day < 25; day++) {
      final store = GameStorage(clock: () => now);
      await store.load();
      final reminders = LocalReminders(
        storage: store,
        platform: platform,
        scheduler: ReminderScheduler(random: Random(day + 21), location: zone),
      );
      await reminders.initialize();
      await reminders.requestPermissionIfNeeded();
      for (final raw in platform.pending) {
        final p = ReminderPayload.decode(raw)!;
        final time = tz.TZDateTime.fromMillisecondsSinceEpoch(zone, p.epochMs);
        if (time.isAfter(now)) continue;
        offsets.add(time.timeZoneOffset.inHours);
        final minutes = time.hour * 60 + time.minute;
        expect(
          minutes >= 690 && minutes <= 810 ||
              minutes >= 1110 && minutes <= 1230,
          isTrue,
        );
        final prior = delivered[p.messageNumber];
        final date = DateTime.utc(time.year, time.month, time.day);
        if (prior != null) {
          expect(date.difference(prior).inDays, greaterThanOrEqualTo(10));
        }
        delivered[p.messageNumber] = date;
      }
      await reminders.reschedule();
      expect(platform.scheduled.length, lessThanOrEqualTo(14));
      now = tz.TZDateTime(zone, now.year, now.month, now.day + 1, 9);
    }
    expect(offsets, {1, 2});
    expect(delivered.length, 20);
    expect(platform.permissionCalls, 1);
  });

  group('S6-20 regression', () {
    qa('S6-20 phoenix targets the unresolved tilted ring still ahead', (
      g,
      tester,
    ) async {
      final r = await startRun(g);
      final hoop = r.spawner.hoops.first;
      hoop.tilt = 45;
      hoop.basePosition.y = 200;
      r.state.camX = hoop.planeX - 70 + 20;
      expect(r.spawner.nextHoopAhead(), same(hoop));
      expect(hoop.frame().rightmostX, greaterThan(r.state.camX + 70));
      expect(reviveSafeLine(r), closeTo(200, .001));
    });
  });

  group('S6-21 regression', () {
    qa('S6-21 revive heartbeat stays within approved idle/urgent peaks', (
      g,
      tester,
    ) async {
      final r = await startRun(g);
      for (var i = 0; i < 6; i++) {
        r.debugPass();
      }
      killRun(g);
      await flushAndMount(g);
      final screen = g.reviveScreen!;
      double idlePeak = 1, urgentPeak = 1;
      for (var i = 0; i < 299; i++) {
        g.update(1 / 60);
        if (screen.countdown < 3) {
          idlePeak = max(idlePeak, screen.beat);
        } else {
          urgentPeak = max(urgentPeak, screen.beat);
        }
      }
      expect(
        [idlePeak, urgentPeak],
        [lessThanOrEqualTo(1.0351), lessThanOrEqualTo(1.0601)],
      );
    });
  });

  Map<String, Object>? interruptedClaim;
  group('S6-22 regression', () {
    test(
      'S6-22 reproduce kill at the real claim persistence boundary',
      () async {
        SharedPreferences.setMockInitialValues({
          'bestScore': 12,
          'unclaimedLevelReward': 50,
          'coins': 100,
        });
        final storage = GameStorage();
        await storage.load();
        final prefs = await SharedPreferences.getInstance();
        final platform = _KillBeforeCoinWrite({
          for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
        });
        SharedPreferencesStorePlatform.instance = platform;
        // Run the real claim. The simulated kill prevents its coin write.
        unawaited(LevelProgress(storage, Wallet(storage)).claim());
        final disk = await platform.atCoinWrite.future;
        interruptedClaim = {
          for (final e in disk.entries)
            e.key.substring('flutter.'.length): e.value,
        };
        expect(interruptedClaim!['claimedLevels'], ['1']);
        expect(interruptedClaim!['coins'], 100);
        expect(interruptedClaim!['unclaimedLevelReward'], 50);
      },
    );
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: interruptedClaim!),
    ).testGameWidget(
      'S6-22 restart recovers reward interrupted between claim and credit',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        expect(
          g.storage.coins,
          150,
          reason: 'the persisted 50-coin reward was never credited',
        );
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );
  });

  group('S6-23 regression', () {
    qa('S6-23 NEXT keeps its reference bottom offset and size at 568 pt', (
      g,
      tester,
    ) async {
      await endWith(g, 3);
      final page = g.resultsScreen!;
      final k = page.content.scale.y;
      final left =
          page.content.position.x + page.nextButton.x * page.content.scale.x;
      final bottom =
          page.content.position.y +
          (page.nextButton.y + page.nextButton.height) * page.content.scale.y;
      expect(
        g.viewHeight - bottom,
        closeTo(711 - ResultsConfig.next.bottom, .001),
      );
      // §3.0.1: the bottom button keeps its §5.10 size while the column
      // above it scales.
      expect(page.nextButton.height * k, closeTo(ResultsConfig.next.height, .001));
      expect(page.nextButton.width * k, closeTo(ResultsConfig.next.width, .001));
      expect(left, closeTo(ResultsConfig.next.left, .001));
    }, height: 568);
  });

  group('S6-24 regression', () {
    qa('S6-24 CLAIM renders the unmodified shared coin sprite', (
      g,
      tester,
    ) async {
      await endWith(g, 12);
      stepGame(g, 4.2);
      await flushAndMount(g);
      final icon = g.resultsScreen!.claimButton.button.children
          .whereType<MenuIcon>()
          .single;
      // Raster evidence: a shared coin contains gold and pale-ring pixels.
      // Compare rendered bytes to the identical sprite without the UI paint.
      Future<List<int>> pixels(ui.Paint? paint) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        icon.sprite!.render(
          canvas,
          size: Vector2.all(32),
          overridePaint: paint,
        );
        final image = await rec.endRecording().toImage(32, 32);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }

      await tester.runAsync(() async {
        final actual = await pixels(icon.paint);
        final expected = await pixels(
          ui.Paint()..filterQuality = icon.paint.filterQuality,
        );
        expect(
          actual.asMap().entries.every((e) => e.value == expected[e.key]),
          isTrue,
          reason: 'CLAIM coin must retain the gold disc and pale inner ring',
        );
      });
    });
  });
}

/// Stops exactly before persisting a reward's coin credit, while keeping
/// the actual preceding writes. The unresolved future represents process death.
class _KillBeforeCoinWrite extends InMemorySharedPreferencesStore {
  _KillBeforeCoinWrite(super.data) : super.withData();
  final atCoinWrite = Completer<Map<String, Object>>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.coins') {
      atCoinWrite.complete(await getAll());
      return Completer<bool>().future;
    }
    return super.setValue(valueType, key, value);
  }
}
