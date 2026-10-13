import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/items/puzzle.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection at the real preferences persistence boundary.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../helpers.dart';
import '../versus/s3_13_service_test.dart' as fixture;
import '../versus/s3_13_versus_run_test.dart' show opponentAt;

Future<Map<String, dynamic>> backendProbe(Map<String, Object?> input) async {
  final process = await Process.start('node', [
    'test/e2e/p45_backend_probe.cjs',
  ]);
  process.stdin.write(jsonEncode(input));
  await process.stdin.close();
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  expect(await process.exitCode, 0, reason: await errors);
  return jsonDecode(await output) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  void journey(
    String name,
    Future<void> Function(FlappySpikesGame, WidgetTester) body, {
    Map<String, Object> prefs = const {},
    double h = 711,
    bool duel = false,
    int seed = 21,
  }) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: prefs,
        worldHeight: h,
        seed: seed,
        services: AnalyticsSpy(),
        versus: FakeVersusService(
          pool: duel
              ? [
                  opponentAt([1, 3, 6, 9]),
                ]
              : [],
        ),
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      name,
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: body,
    );
  }

  for (final h in [568.0, 711.0]) {
    journey(
      'P45 ($h): feather set survives revive, bonus pays per tap, results excludes pops',
      (g, _) async {
        final r = await startRun(
          g,
          startHoopIndex: 3,
          force: [ElementId.feather],
        );
        g.runDebug.god = true;
        expect(
          await collectPickup(g, ElementId.feather, reforce: false),
          isNotNull,
        );
        expect(g.storage.feathers, 3);
        while (r.state.hoopsPassed < 6) {
          r.debugPass();
        }
        g.runDebug.god = false;
        killRun(g);
        await flushAndMount(g);
        expect(g.state, GameState.reviving);
        final stopped = r.state.runClock;
        g.reviveScreen!.tapHeart();
        for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
          g.update(1 / 60);
          if (g.state == GameState.reviving) expect(r.state.runClock, stopped);
          if (i % 5 == 0) await flushAndMount(g);
        }
        expect(g.state, GameState.playing);
        expect(g.storage.feathers, 3);
        r.state.invulnerable = 0;
        killRun(g);
        await flushAndMount(g);
        await declineRevive(g);
        expect(g.state, GameState.bonus);
        final b = g.bonusScreen!;
        final reward = r.state.coinsThisRun;
        final before = g.menu.wallet.balance;
        for (final i in [0, 1, 2]) {
          expect(b.tapTile(i), isTrue);
          expect(b.tapTile(8), isFalse, reason: 'opening locks input');
          await stepSeconds(g, 2);
        }
        final prize = b.prizes.take(3).reduce((a, b) => a + b);
        expect(g.menu.wallet.balance, before + prize);
        expect(g.storage.feathers, 0);
        await stepSeconds(g, 3.2);
        b.tapNoThanks();
        await flushAndMount(g);
        expect(g.resultsScreen!.model.reward, reward);
        expect(
          analyticsLog(
            g.services as AnalyticsSpy,
          ).where((e) => e.$1 == 'bonus_pop'),
          hasLength(3),
        );
      },
      prefs: {'feathers': 2, 'bestScore': 100},
      h: h,
    );

    journey(
      'P45 ($h): puzzle mask and round persist across real runs, complete pays once',
      (g, _) async {
        for (var n = 0; n < 4; n++) {
          final r = await startRun(
            g,
            startHoopIndex: 14,
            force: [ElementId.puzzlePiece],
          );
          g.runDebug.god = true;
          expect(
            await collectPickup(g, ElementId.puzzlePiece, reforce: false),
            isNotNull,
          );
          final paid = r.features.whereType<PuzzleFeature>().single.paid;
          if (n < 3) {
            expect(paid, isEmpty);
            expect(g.storage.puzzleRound, 7);
          } else {
            expect(paid, hasLength(1));
            // PRD-2.3 §14.2: 50–150 (was 50–250).
            expect(paid.single, inInclusiveRange(50, 150));
            expect(paid.single % 5, 0);
            expect(r.state.coinsThisRun, greaterThanOrEqualTo(paid.single));
            expect(g.storage.puzzlePieces, 0);
            expect(g.storage.puzzleRound, 8);
          }
          await flushAndMount(g);
          final back = GameStorage();
          await back.load();
          expect(back.puzzlePieces, g.storage.puzzlePieces);
          expect(back.puzzleRound, g.storage.puzzleRound);
          g.runDebug.god = false;
          r.state.invulnerable = 0;
          killRun(g);
          await flushAndMount(g);
          if (g.state == GameState.reviving) await declineRevive(g);
          expect(g.resultsScreen!.model.reward, r.state.coinsThisRun);
          g.goHome();
          await flushAndMount(g);
          await stepSeconds(g, .6);
        }
        expect(
          analyticsLog(
            g.services as AnalyticsSpy,
          ).where((e) => e.$1 == 'puzzle_completed'),
          hasLength(1),
        );
      },
      prefs: {
        'puzzleRound': 7,
        'bestScore': 100,
        'noAds': true,
        'claimedLevels': ['1', '2', '3'],
      },
      h: h,
    );
  }

  journey(
    'P45 versus: portal + comet replay, pause, real Hourglass and opponent out',
    (g, _) async {
      final r = await startRun(g, startHoopIndex: 25, ride: RideId.space);
      g.runDebug.god = true;
      expect(
        await flyUntil(g, (r) => r.state.ride?.kind == RideKind.portal),
        isTrue,
      );
      final clock = r.state.runClock;
      g.pause();
      await flushAndMount(g);
      await stepSeconds(g, 2);
      expect(r.state.runClock, clock);
      g.resume();
      expect(
        await flyUntil(g, (r) => r.state.ride == null, maxSeconds: 40),
        isTrue,
      );
      expect(
        r.state.timeline.flags.where((f) => f == 1).length,
        greaterThanOrEqualTo(11),
      );
      expect(g.runHud!.versus!.out, isTrue);
      r.debugForce(ElementId.comet);
      expect(
        await flyUntil(
          g,
          (r) => r.features.whereType<CometFeature>().single.active,
          maxSeconds: 40,
        ),
        isTrue,
      );
      expect(
        await flyUntil(
          g,
          (r) => !r.features.whereType<CometFeature>().single.active,
          maxSeconds: 20,
        ),
        isTrue,
      );
      r.debugForce(ElementId.hourglass);
      expect(
        await collectPickup(g, ElementId.capsule, reforce: false),
        isNotNull,
      );
      await stepSeconds(g, .3);
      expect(r.state.timeScale, lessThan(1));
      final before = r.state.runClock;
      await flyUntil(g, (r) => r.state.runClock > before + .1, maxSeconds: 1);
      expect(r.state.runClock - before, lessThan(.4));
      g.runDebug.god = false;
      r.state.invulnerable = 0;
      killRun(g);
      await flushAndMount(g);
      await declineRevive(g);
      expect(g.resultsScreen!.summary.duel, DuelResult.win);
      expect(r.state.duelBonus, 10);
      expect(g.resultsScreen!.model.reward, r.state.coinsThisRun);
      final log = analyticsLog(g.services as AnalyticsSpy);
      expect(log.where((e) => e.$1 == 'versus_result'), hasLength(1));
      expect(log.where((e) => e.$1 == 'portal_entered'), isNotEmpty);
      expect(log.where((e) => e.$1 == 'comet_collected'), isNotEmpty);
    },
    duel: true,
    prefs: {
      'bestScore': 1000,
      'claimedLevels': ['1', '2', '3', '4', '5', '6', '7', '8'],
    },
  );

  // PRD-2.2 §19.3 / PRD-2.3 §14.2: the feather and the piece come in
  // ≈ 60 % of runs each (gap 10–40) and never in the same run (the feather
  // wins): one seed per item whose run has it before the held window ends.
  int seedWith({required bool feather}) =>
      [for (var s = 1; s < 300; s++) s].firstWhere((s) {
        final d = RunDirector(
          seed: s,
          enabled: const {},
          met: const {},
          startHoopIndex: 2,
        );
        return feather
            ? d.featherThisRun && d.featherAt <= 25
            : d.pieceThisRun && d.pieceAt <= 25;
      });
  for (final feather in [true, false]) {
    final what = feather ? 'feather' : 'piece';
    journey(
      'P45 squeeze: the $what remains scheduled until the walls reopen',
      seed: seedWith(feather: feather),
      (g, _) async {
        final r = await startRun(g, startHoopIndex: 2);
        g.runDebug.god = true;
        // Suppress its gap through the whole scheduled window.
        r.features.whereType<SqueezeFeature>().single.phaseT = -1000;
        r.state.squeeze.phase = SqueezePhase.hold;
        r.state.squeeze.inset = 100;
        expect(
          await flyUntil(g, (r) => r.state.hoopIndex >= 28, maxSeconds: 80),
          isTrue,
        );
        expect(r.state.featherSpawned, isFalse);
        expect(r.state.pieceSpawned, isFalse);
        r.state.squeeze.phase = SqueezePhase.idle;
        r.state.squeeze.inset = 0;
        r.state.squeeze.nextAt = 10000;
        expect(
          await flyUntil(
            g,
            (r) => feather ? r.state.featherSpawned : r.state.pieceSpawned,
            // PRD-2.2 §27: an activity on the way makes it wait.
            maxSeconds: 60,
          ),
          isTrue,
        );
        // PRD-2.3 §14.2 never both in one run.
        expect(r.state.featherSpawned && r.state.pieceSpawned, isFalse);
      },
    );
  }

  for (final owner in [false, true]) {
    journey('P45 bonus: jackpot and one refill (${owner ? 'owner' : 'ad'})', (
      g,
      _,
    ) async {
      await startRun(g);
      killRun(g);
      await flushAndMount(g);
      final b = g.bonusScreen!;
      final before = g.menu.wallet.balance;
      // PRD-2.3 §14.2 the jackpot is 150 (was 250).
      final jackpot = b.prizes.indexOf(BonusConfig.jackpot);
      expect(BonusConfig.jackpot, 150);
      expect(b.tapTile(jackpot), isTrue);
      expect(
        g.menu.wallet.balance,
        before + BonusConfig.jackpot,
        reason: 'credit at tap',
      );
      await stepSeconds(g, 2);
      final others = List.generate(9, (i) => i)..remove(jackpot);
      for (final i in others.take(2)) {
        expect(b.tapTile(i), isTrue);
        await stepSeconds(g, 2);
      }
      await stepSeconds(g, .5);
      // PRD-2.2 §7.7: NO ADS owners watch the ad too.
      expect(b.offer, BonusOffer.ad);
      expect(b.noThanksShown, isFalse);
      await stepSeconds(g, 3.1);
      expect(b.noThanksShown, isTrue);
      final ads = g.monetization.ads as FakeRewardedAds;
      final calls = ads.placements.length;
      await b.tapOffer();
      await stepSeconds(g, 1.5);
      expect(b.feathers, 3);
      expect(ads.placements.length, calls + 1);
      for (final i in others.skip(2).take(3)) {
        expect(b.tapTile(i), isTrue);
        await stepSeconds(g, 2);
      }
      await stepSeconds(g, 1);
      expect(b.pops, 6);
      expect(b.phase, BonusPhase.done);
      expect(b.nextShown, isTrue);
      expect(List.generate(9, (i) => i).where(b.isRevealed), hasLength(6));
      b.tapNext();
      await flushAndMount(g);
      expect(g.resultsScreen!.model.reward, 0);
    }, prefs: {'feathers': 3, 'noAds': owner});
  }

  journey('P45 bonus: unavailable ad: the offer waits 5 s, then NEXT '
      '(PRD-2.2 §7.8)', (
    g,
    _,
  ) async {
    (g.monetization.ads as FakeRewardedAds).mode = FakeAdMode.unavailable;
    await startRun(g);
    killRun(g);
    await flushAndMount(g);
    final b = g.bonusScreen!;
    for (final i in [0, 1, 2]) {
      expect(b.tapTile(i), isTrue);
      await stepSeconds(g, 2);
    }
    await stepSeconds(g, 1);
    expect(b.offer, BonusOffer.ad);
    expect(b.adWaiting, isTrue);
    await stepSeconds(g, 5.5);
    expect(b.phase, BonusPhase.done);
    expect(b.nextShown, isTrue);
    b.tapNext();
    await flushAndMount(g);
    expect(g.state, GameState.results);
  }, prefs: {'feathers': 3});

  group('S6-65: the intro shows the current identity name', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 711,
        versus: FakeVersusService(
          pool: [
            opponentAt([1, 3, 6]),
          ],
          profile: const VersusProfile(name: 'SwiftKiwi482'),
        ),
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'S6-65 own name plate uses the generated nickname or Play Games name',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.onScreenTap();
        await flushAndMount(g);
        g.versusIntro!.debugFreeze(2);
        expect(
          g.versusIntro!.youPlate.name,
          g.versus.me.name,
          reason: 'own name is hardcoded to You despite a ready profile',
        );
      },
    );
  });

  group('S6-64: a cached Play Games avatar is displayed', () {
    const url = 'https://qa.invalid/avatar.png';
    final source = opponentAt([1, 3, 6]);
    final opponent = OpponentRun(
      uid: source.uid,
      name: source.name,
      avatarUrl: url,
      score: source.score,
      best: source.best,
      level: source.level,
      timeline: source.timeline,
      runId: source.runId,
    );
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 711,
        versus: FakeVersusService(pool: [opponent]),
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'S6-64 locked intro draws the available avatar instead of the neutral glyph',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          canvas.drawRect(
            const ui.Rect.fromLTWH(0, 0, 52, 52),
            ui.Paint()..color = const ui.Color(0xFFFF0000),
          );
          g.images.add(url, await rec.endRecording().toImage(52, 52));
        });
        g.onScreenTap();
        await flushAndMount(g);
        g.versusIntro!.debugFreeze(6);
        await tester.runAsync(() async {
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          g.versusIntro!.oppPlate.render(canvas);
          final image = await rec.endRecording().toImage(232, 52);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          image.dispose();
          final index = (5 * 232 + 5) * 4;
          expect(
            bytes.sublist(index, index + 3),
            [255, 0, 0],
            reason:
                'cached avatar exists but the plate always paints a placeholder',
          );
        });
      },
    );
  });

  test(
    'P45 reminders: repeated sessions, spring DST and 20-message rotation',
    () async {
      final zone = tz.getLocation('Europe/Amsterdam');
      var now = tz.TZDateTime(zone, 2027, 3, 20, 9);
      SharedPreferences.setMockInitialValues({});
      final platform = FakeReminderPlatform();
      final seen = <int, DateTime>{};
      final all = <int>{};
      for (var day = 0; day < 30; day++) {
        final store = GameStorage(clock: () => now);
        await store.load();
        final reminders = LocalReminders(
          storage: store,
          platform: platform,
          scheduler: ReminderScheduler(location: zone, random: Random(day)),
        );
        for (final raw in platform.pending) {
          final p = ReminderPayload.decode(raw)!;
          if (p.epochMs <= now.millisecondsSinceEpoch) {
            final at = tz.TZDateTime.fromMillisecondsSinceEpoch(
              zone,
              p.epochMs,
            );
            final old = seen[p.messageNumber];
            if (old != null) {
              expect(
                DateTime.utc(
                  at.year,
                  at.month,
                  at.day,
                ).difference(DateTime.utc(old.year, old.month, old.day)).inDays,
                greaterThanOrEqualTo(10),
              );
            }
            seen[p.messageNumber] = at;
            all.add(p.messageNumber);
          }
        }
        platform.deliverDue(now);
        await reminders.initialize();
        await reminders.requestPermissionIfNeeded();
        await reminders.reschedule();
        await reminders.reschedule();
        for (final slot in platform.scheduled) {
          expect(slot.time.hour, inInclusiveRange(9, 21));
          expect(
            slot.time.difference(now),
            greaterThan(const Duration(hours: 2)),
          );
          expect(
            slot.time.isAfter(
              tz.TZDateTime(zone, now.year, now.month, now.day + 7, 9),
            ),
            isFalse,
          );
        }
        now = tz.TZDateTime(zone, now.year, now.month, now.day + 1, 9);
      }
      expect(all, hasLength(20));
      expect(platform.permissionCalls, 1);
    },
  );

  test(
    'S6-66 recovering connectivity after anonymous-auth startup failure retries queued runs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage();
      await store.load();
      final backend = fixture.FakeBackend()..offline = true;
      final identity = fixture.FakeIdentity();
      final service = FirebaseVersusService(
        storageOf: () => store,
        backend: backend,
        identity: identity,
        random: Random(2),
      );
      await service.initialize();
      expect(service.ready, isFalse);
      backend.offline = false;
      await service.submitRun(fixture.summary(3), const Look());
      // Home prefetch and submitRun/flush are the recovery calls wired in
      // the app; main.dart never calls initialize a second time.
      await service.prefetch();
      await service.flush();
      await identity.controller.close();
      expect(
        service.queue.pending,
        isEmpty,
        reason:
            'phone online; ready remains false and no call retries anonymous auth',
      );
      expect(backend.starts, greaterThan(0));
    },
  );

  test(
    'S6-66 a failed start retries by itself with backoff (no other call)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage();
      await store.load();
      final backend = fixture.FakeBackend()..offline = true;
      final identity = fixture.FakeIdentity();
      final service = FirebaseVersusService(
        storageOf: () => store,
        backend: backend,
        identity: identity,
        random: Random(2),
        retryBase: const Duration(milliseconds: 20),
        retryMax: const Duration(milliseconds: 80),
      );
      try {
        await service.initialize();
        expect(service.ready, isFalse);
        // Still offline: the waits double (20, 40, 80, 80 … ms).
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(service.ready, isFalse);
        expect(service.failures, greaterThanOrEqualTo(3));
        expect(backend.starts, 0);
        // Back online: the next background retry starts the service.
        backend.offline = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(service.ready, isTrue);
        expect(backend.starts, 1);
        expect(service.failures, 0);
        // App resume on a ready service flushes the queue.
        await service.submitRun(fixture.summary(3), const Look());
        await service.onResume();
        expect(service.queue.pending, isEmpty);
      } finally {
        service.dispose();
        await identity.controller.close();
      }
    },
  );

  test('S6-66 app resume recovers a failed start', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStorage();
    await store.load();
    final backend = fixture.FakeBackend()..offline = true;
    final identity = fixture.FakeIdentity();
    final service = FirebaseVersusService(
      storageOf: () => store,
      backend: backend,
      identity: identity,
      random: Random(2),
    );
    await service.initialize();
    expect(service.ready, isFalse);
    backend.offline = false;
    await service.onResume();
    expect(service.ready, isTrue);
    expect(backend.starts, 1);
    await identity.controller.close();
  });

  group('S6-60: offline backlog must survive the server UTC upload cap', () {
    test(
      'S6-60 six non-best runs queued over two days are retained until accepted',
      () async {
        var now = DateTime.utc(2026, 10, 6, 12);
        SharedPreferences.setMockInitialValues({});
        final store = GameStorage();
        await store.load();
        final queue = UploadQueue(store, clock: () => now);
        for (var day = 0; day < 2; day++) {
          for (var i = 0; i < 3; i++) {
            final entry = RunEntry.fromSummary(
              fixture.summary(3, bestBefore: 100),
              runId: 'q$day-$i',
              name: 'SwiftKiwi482',
              ts: now,
            );
            expect(
              await queue.offer(entry, newBest: false),
              UploadDecision.queued,
            );
          }
          now = now.add(const Duration(days: 1));
        }
        final documents = <Map<String, Object?>>[];
        final processedAt = <int>[];
        Map<String, Object?>? old;
        Future<UploadWrite> write(QueuedRun q) async {
          old = nextPlayerDoc(
            old: old,
            run: q.entry.toMap(ts: q.entry.ts.millisecondsSinceEpoch),
            newBest: q.newBest,
            name: q.entry.name,
            avatar: '',
            platform: 'android',
            look: const Look(),
            uploadsDay: queue.today,
            uploadsCount: queue.uploadsToday,
          );
          documents.add(old!);
          processedAt.add(now.millisecondsSinceEpoch);
          // The real backend returns done on a successful Firestore transaction,
          // before the trigger's acceptance/rejection (no acknowledgement read).
          return UploadWrite.done;
        }

        // Day three: only the server's three non-best runs a UTC day go out.
        expect(await queue.flush(write), 3);
        var result = await backendProbe({
          'mode': 'queue',
          'documents': documents,
          'nowMs': processedAt,
        });
        expect(result['accepted'], hasLength(3));
        expect(
          result['rejected'],
          isEmpty,
          reason: 'no run is sent past the server rate and lost',
        );
        expect(
          queue.pending.length,
          3,
          reason:
              'the three runs over the server rate stay queued for a later day',
        );
        // Same day again: nothing more goes out.
        expect(await queue.flush(write), 0);
        expect(queue.pending.length, 3);
        // Day four: the rest are written and accepted.
        now = now.add(const Duration(days: 1));
        expect(await queue.flush(write), 3);
        result = await backendProbe({
          'mode': 'queue',
          'documents': documents,
          'nowMs': processedAt,
        });
        expect(result['accepted'], hasLength(6));
        expect(result['rejected'], isEmpty);
        expect(queue.pending, isEmpty);
      },
    );

    test('S6-60 a new best is not held back by the paced backlog', () async {
      var now = DateTime.utc(2026, 10, 6, 12);
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage();
      await store.load();
      final queue = UploadQueue(store, clock: () => now);
      for (var i = 0; i < 6; i++) {
        if (i == 3) now = now.add(const Duration(days: 1));
        await queue.offer(
          RunEntry.fromSummary(
            fixture.summary(3, bestBefore: 100),
            runId: 'n$i',
            name: 'SwiftKiwi482',
            ts: now,
          ),
          newBest: false,
        );
      }
      await queue.offer(
        RunEntry.fromSummary(
          fixture.summary(120, bestBefore: 100),
          runId: 'best',
          name: 'SwiftKiwi482',
          ts: now,
        ),
        newBest: true,
      );
      now = now.add(const Duration(days: 1));
      final sent = <String>[];
      expect(
        await queue.flush((q) async {
          sent.add(q.entry.runId);
          return UploadWrite.done;
        }),
        4,
      );
      expect(sent, ['n0', 'n1', 'n2', 'best']);
      expect(queue.pending.map((q) => q.entry.runId), ['n3', 'n4', 'n5']);
      // A restart keeps the upload-day count.
      final again = GameStorage();
      await again.load();
      expect(UploadQueue(again, clock: () => now).sentToday, 3);
    });
  });

  test(
    'S6-61 a backend delete failure leaves every online document intact',
    () async {
      final result = await backendProbe({'mode': 'delete'});
      expect(result['failed'], isTrue);
      expect(result['rateExists'], isTrue);
      expect(
        result['playerExists'],
        isTrue,
        reason: 'call failed after removing the player document',
      );
    },
  );

  group(
    'S6-62: completing a picture survives interrupted coin persistence',
    () {
      journey(
        'S6-62 real fourth-piece collection does not lose an unpaid picture on restart',
        (g, tester) async {
          final r = await startRun(
            g,
            startHoopIndex: 14,
            force: [ElementId.puzzlePiece],
          );
          g.runDebug.god = true;
          final original = SharedPreferencesStorePlatform.instance;
          final prefs = await SharedPreferences.getInstance();
          final disk = {
            for (final k in prefs.getKeys()) 'flutter.$k': prefs.get(k)!,
          };
          final cut = _KillCoinWrite(disk);
          SharedPreferencesStorePlatform.instance = cut;
          try {
            expect(
              await collectPickup(g, ElementId.puzzlePiece, reforce: false),
              isNotNull,
            );
            await flushAndMount(g);
            final paid = r.features
                .whereType<PuzzleFeature>()
                .single
                .paid
                .single;
            expect(cut.stopped, isTrue);
            // Every coin write of this session is cut (the pickups' too),
            // so the balance the app held is what a restart must reach.
            final live = g.storage.coins;
            expect(live, greaterThanOrEqualTo(100 + paid));
            final saved = await cut.getAll();
            SharedPreferencesStorePlatform.instance = original;
            SharedPreferences.setMockInitialValues({
              for (final e in saved.entries)
                e.key.replaceFirst('flutter.', ''): e.value,
            });
            final restarted = GameStorage();
            await restarted.load();
            expect(
              restarted.coins == live ||
                  restarted.puzzlePieces == 7 ||
                  restarted.puzzlePayout == live,
              isTrue,
              reason:
                  'disk has no coin payout and no recoverable completed picture: $saved',
            );
            // The start-up recovery pays the interrupted credit exactly once.
            final wallet = Wallet(restarted);
            final owed = live - restarted.coins;
            expect(owed, greaterThanOrEqualTo(paid));
            expect(await PuzzleFeature.settlePayout(restarted, wallet), owed);
            expect(restarted.coins, live);
            expect(restarted.puzzlePieces, 0);
            expect(restarted.puzzleRound, 3);
            expect(await PuzzleFeature.settlePayout(restarted, wallet), 0);
            expect(restarted.coins, live);
            final again = GameStorage();
            await again.load();
            expect(again.coins, live);
            expect(again.puzzlePayout, 0);
            expect(await PuzzleFeature.settlePayout(again, Wallet(again)), 0);
          } finally {
            SharedPreferencesStorePlatform.instance = original;
          }
        },
        prefs: {'puzzlePieces': 7, 'puzzleRound': 2, 'coins': 100},
      );
    },
  );

  group(
    'S6-63: bonus NEXT retains its reference size and bottom distance',
    () {
      journey(
        'S6-63 568pt balloon page keeps NEXT 292x50 and 99pt bottom gap',
        (g, tester) async {
          await startRun(g);
          killRun(g);
          await flushAndMount(g);
          final b = g.bonusScreen!;
          final ref = BonusConfig.nextButton;
          final rect = b.nextRect;
          expect(g.viewHeight - rect.bottom, closeTo(711 - ref.bottom, .01));
          expect(rect.width, closeTo(292, .01));
          expect(rect.height, closeTo(50, .01));
          // The scaled column above ends at or above the band.
          final (k, off) = BonusRules.layoutFor(g.viewHeight);
          expect(
            off.dy + BonusConfig.panel.bottom * k,
            lessThan(rect.top),
          );
          // What is drawn and tapped: NEXT's pink fills that rect.
          b.phase = BonusPhase.done;
          await stepSeconds(g, 1.2);
          expect(b.nextShown, isTrue);
          await tester.runAsync(() async {
            final rec = ui.PictureRecorder();
            b.renderTree(ui.Canvas(rec));
            final image = await rec.endRecording().toImage(320, 568);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            image.dispose();
            List<int> at(double x, double y) {
              final i = (y.floor() * 320 + x.floor()) * 4;
              return bytes.sublist(i, i + 3);
            }

            final pink = BonusConfig.pink;
            final want = [
              (pink.r * 255).round(),
              (pink.g * 255).round(),
              (pink.b * 255).round(),
            ];
            expect(at(rect.left + 2, rect.top + 2), want);
            expect(at(rect.right - 2, rect.bottom - 2), want);
            expect(at(rect.left + 2, rect.bottom + 2), isNot(want));
            expect(at(rect.right + 2, rect.top + 2), isNot(want));
          });
          b.tapAt(rect.bottomRight - const Offset(2, 2));
          await flushAndMount(g);
          expect(g.state, GameState.results);
        },
        prefs: {'feathers': 3},
        h: 568,
      );
    },
  );
}

class _KillCoinWrite extends InMemorySharedPreferencesStore {
  _KillCoinWrite(super.data) : super.withData();
  bool stopped = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.coins') {
      stopped = true;
      return Completer<bool>().future;
    }
    return super.setValue(valueType, key, value);
  }
}
