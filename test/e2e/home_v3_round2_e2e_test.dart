import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/components/levels/levels_screen.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/ui/confetti.dart';
import 'package:flappy_spikes/components/levels/emblem_view.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/run_events.dart' show PickupCollected;
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;
import '../purchase_feedback_test.dart' show run, texts;
import '../shop_flow_test.dart' show EventSpy;
import '../services/store_iap_service_test.dart' show FakeStore;

// Round 1 already covers the 568/711 fresh journeys and all pack presets.
// Round 2 extends the real journeys to 640/730 and interrupted/queued flows.
// The S1-31 / S1-32 / S2-34 / S2-35 regressions were fixed in "Fix home-v3
// R2" and run as normal tests.

class _Rig {
  final events = EventSpy();
  final iap = FakeIapService();
  final sounds = <Sfx>[];
}

void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  double height = 711,
  IapService? service,
}) {
  final rig = _Rig();
  FlameTester<FlappySpikesGame>(
    () => createTestGame(
      prefs,
      height,
      rig.events,
      Monetization(iap: service ?? rig.iap, ads: FakeRewardedAds()),
    ),
    gameSize: Vector2(320, height),
    pumpWidget: (widget, tester) async {
      tester.view
        ..physicalSize = ui.Size(320, height)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(widget);
    },
  ).testGameWidget(
    name,
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.sound.onPlay = rig.sounds.add;
      game.coinFlyRandom = math.Random(31);
      // Deliver fake billing in the binding's test zone.
      game.purchases
        ..dispose()
        ..start();
      try {
        await verify(game, rig, tester);
      } finally {
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}

void _defect(
  String id,
  String description,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  IapService? service,
}) => group(
  id,
  () => _journey(description, verify, prefs: prefs, service: service),
);

Future<void> _settle(FlappySpikesGame game, WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    for (var n = 0; n < 20; n++) {
      await Future<void>.value();
    }
    await tester.binding.delayed(Duration.zero);
  }
  await flushAndMount(game);
}

Future<void> _tap(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent component,
) async {
  final p = component.absolutePositionOfAnchor(Anchor.center);
  await tester.tapAt(ui.Offset(p.x, p.y));
  await _settle(game, tester);
}

Future<GameStorage> _saved() async {
  final storage = GameStorage();
  await storage.load();
  return storage;
}

class _PathRecorder implements ui.Canvas {
  final paths = <ui.Path>[];

  @override
  void drawPath(ui.Path path, ui.Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

int _modalCount(FlappySpikesGame game) => [
  game.noAdsPopup,
  game.levelUpPopup,
  game.purchaseResultPopup,
  game.noAdsCelebration,
].where((popup) => popup != null).length;

List<String> _claimed(int n) => [for (var i = 1; i <= n; i++) '$i'];

// Same physical flight controller as the acceptance bot / round 1. It
// presses flap; it never writes score, best, wallet or claimed levels.
Future<void> _flyToEgg(FlappySpikesGame game) async {
  // WP-1a: the hoop-aware acceptance bot (PRD-2 §7) flies the real course.
  // PRD-2.3 §14.3: every rim-free pass is perfect, so the bot's points
  // grow with the uncapped streak (12 hoops ≈ 79 points = level 2). 8 hoops
  // (≥ 6 for the revive offer) keep this journey at EGG · LV 1 (10–49).
  final flight = await flyRun(game, maxSeconds: 75, untilHoops: 8);
  expect(
    game.score,
    inInclusiveRange(10, 49),
    reason: 'actual hoop scoring\n${flight.trace.reversed.take(5).join('\n')}',
  );
  // WP-3a: a comet boost (first met at hoop 10) flies itself; finish it.
  await flyOutOfRide(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  for (final height in [640.0, 730.0]) {
    _journey(
      'R2 fresh install → real 12+ run → LEVEL UP → CLAIM → EGG ($height)',
      (game, rig, tester) async {
        final home = game.homeScreen!;
        expect(home.emblem.level, 0);
        expect(home.lastStat.value, '—');
        expect(home.gearButton.x, 14);
        expect(home.lastStat.toRect().right, 306);
        expect(home.startButton.toRect().center.dx, 160);
        expect(home.slotButton.toRect().center.dx, 160);
        expect(
          home.startButton.toRect().bottom,
          lessThan(home.slotButton.toRect().top),
        );
        expect(
          home.slotButton.toRect().bottom,
          lessThan(home.shopTile.toRect().top),
        );
        await _tap(game, tester, home.startButton);
        await _flyToEgg(game);
        await run(game, 3);
        // PRD-2 §3.14 (WP-2d): ≥ 6 hoops → the revive offer; No thanks.
        await declineRevive(game);
        expect(game.state, GameState.results);
        expect(game.levelUpPopup, isNull);
        final earned = game.menu.wallet.balance;
        // PRD-2 §3.14: NEXT on the results page claims the owed level
        // reward first (never lost), then home — no home LEVEL UP popup.
        final panel = game.world.children.query<ResultsScreen>().single;
        await run(game, .4);
        await _tap(game, tester, panel.nextButton);
        expect(game.menu.wallet.balance, earned + 50);
        await run(game, 2.5);
        expect(game.state, GameState.start);
        expect(game.stageBackground, paletteForStage(0).background);
        await run(game, 4);
        expect(game.levelUpPopup, isNull);
        expect(game.coinPill.shownBalance, earned + 50);
        expect(game.storage.claimedLevels, {1});
        await _tap(game, tester, game.homeScreen!.bird);
        await run(game, .6);
        expect(game.levelsScreen!.rows.first.state, LevelRowState.current);
        expect(game.levelsScreen!.rows[1].state, LevelRowState.locked);
        await _tap(game, tester, game.levelsScreen!.backButton);
        await run(game, 1);
        expect(game.levelUpPopup, isNull);
        expect(rig.events.count('level_up'), 1);
        expect(rig.events.last('level_up'), {
          'from': 0,
          'to': 1,
          'reward': 50,
          'claim': 'auto_next',
        });
      },
      height: height,
    );
  }

  _journey(
    'R2 existing LEGEND → one catch-up → rapid double claim → MAX LEVEL',
    (game, rig, tester) async {
      await run(game, .8);
      final popup = game.levelUpPopup!;
      expect(popup.pending.reward, 10350);
      await _tap(game, tester, popup.claimButton);
      // Re-enter the action before the fade removes the old component.
      popup.claimButton.onPressed();
      await _settle(game, tester);
      await run(game, 5);
      expect(game.menu.wallet.balance, 11600);
      expect(game.storage.claimedLevels, {for (var i = 1; i <= 10; i++) i});
      expect(await game.menu.levels.claim(), 0);
      await _tap(game, tester, game.homeScreen!.bird);
      await run(game, .6);
      final levels = game.levelsScreen!;
      expect(levels.header.barText.text, 'MAX LEVEL');
      expect(levels.rows.every((row) => row.reached), isTrue);
      expect(levels.scroll.offset, greaterThan(0));
      await _tap(game, tester, levels.backButton);
      await run(game, 1);
      expect(game.levelUpPopup, isNull);
      expect(rig.events.count('level_up'), 1);
      expect(rig.events.count('level_reward_claimed'), 1);
      final saved = await _saved();
      expect(saved.coins, 11600);
    },
    prefs: const {'bestScore': 5000, 'coins': 1250},
  );

  _journey('R2 pack count-up survives Shop → home → LEVELS → home', (
    game,
    rig,
    tester,
  ) async {
    await _tap(game, tester, game.homeScreen!.shopTile);
    await run(game, .6);
    await _tap(game, tester, game.shopScreen!.packs[2]);
    expect(game.coinPill.shownBalance, 1250);
    await run(game, .8);
    expect(game.coinReward!.counting, isTrue);
    await _tap(game, tester, game.shopScreen!.backButton);
    await run(game, .6);
    await _tap(game, tester, game.homeScreen!.bird);
    await run(game, 5);
    expect(game.menu.wallet.balance, 18250);
    expect(game.coinPill.shownBalance, 18250);
    expect(game.coinPill.held, isFalse);
    expect(game.world.descendants().whereType<ConfettiBurst>(), isEmpty);
    await _tap(game, tester, game.levelsScreen!.backButton);
    await run(game, .6);
    expect(game.coinPill.opacity, 1);
    expect(game.coinPill.shownBalance, 18250);
    expect(rig.sounds.where((s) => s == Sfx.bnCoin), hasLength(12));
    expect((await _saved()).coins, 18250);
  }, prefs: const {'coins': 1250});

  for (final mode in [
    FakeIapMode.cancel,
    FakeIapMode.fail,
    FakeIapMode.pending,
  ]) {
    _journey('R2 ${mode.name}: pending Shop billing → Settings → result', (
      game,
      rig,
      tester,
    ) async {
      rig.iap
        ..mode = mode
        ..delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.shopTile);
      await run(game, .6);
      await _tap(game, tester, game.shopScreen!.packs[1]);
      await _tap(game, tester, game.shopScreen!.backButton);
      await run(game, .6);
      await _tap(game, tester, game.homeScreen!.gearButton);
      await run(game, .6);
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
      if (mode == FakeIapMode.pending) {
        expect(game.purchaseResultPopup, isNull);
        expect(rig.events.count('purchase_result_popup'), 0);
      } else {
        final popup = game.purchaseResultPopup!;
        await run(game, .3);
        expect(
          texts(popup),
          contains(
            mode == FakeIapMode.cancel
                ? 'PURCHASE CANCELLED'
                : 'PURCHASE FAILED',
          ),
        );
        expect(_modalCount(game), 1);
        await tester.tapAt(const ui.Offset(5, 110)); // dim dismissal
        await _settle(game, tester);
        expect(game.purchaseResultPopup, isNull);
        expect(game.menuScene, MenuScene.settings);
        expect(rig.events.count('iap_error'), mode == FakeIapMode.fail ? 1 : 0);
      }
      expect(game.menu.wallet.balance, 1250);
      expect((await _saved()).coins, 1250);
    }, prefs: const {'coins': 1250});
  }

  _journey('R2 No ads ✕ → bonus once → home owned → persisted', (
    game,
    rig,
    tester,
  ) async {
    await _tap(game, tester, game.homeScreen!.noAdsTile);
    await run(game, .8);
    expect(game.noAdsCelebration, isNotNull);
    expect(game.coinPill.shownBalance, 1250);
    expect(game.menu.wallet.balance, 2250);
    final popup = game.noAdsCelebration!;
    await _tap(game, tester, popup.closeButton);
    popup.onDismiss();
    await run(game, 6);
    expect(game.coinPill.shownBalance, 2250);
    expect(game.homeScreen!.noAdsTile.owned, isTrue);
    expect(game.homeScreen!.slotButton.showsVideo, isFalse);
    expect(rig.events.count('noads_bonus_claimed'), 1);
    await game.restorePurchases();
    await _settle(game, tester);
    expect(game.noAdsCelebration, isNull);
    expect(game.menu.wallet.balance, 2250);
    expect((await _saved()).noAds, isTrue);
  }, prefs: const {'coins': 1250});

  _journey(
    'R2 Settings rumble off/on → one enable knock → reopen → runs silent',
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.gearButton);
      await run(game, .6);
      var settings = game.world.children.query<SettingsPanel>().single;
      final before = game.rumble.fired.length;
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.fired.length, before);
      expect((await _saved()).rumble, isFalse);
      await run(game, .2);
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.fired.length, before + 1);
      expect(game.rumble.fired.last, RumbleKind.knock);
      await run(game, .4);
      await _tap(game, tester, settings.backButton);
      await run(game, .6);
      await _tap(game, tester, game.homeScreen!.gearButton);
      await run(game, .6);
      settings = game.world.children.query<SettingsPanel>().single;
      expect(settings.rumbleButton.on, isTrue);
      expect((await _saved()).rumble, isTrue);
      await _tap(game, tester, settings.backButton);
      await run(game, .6);
      await _tap(game, tester, game.homeScreen!.startButton);
      final inRun = game.rumble.fired.length;
      final runState = game.run!.state;
      var pickups = 0;
      game.run!.events.on<PickupCollected>((_) => pickups++);
      await _flyToEgg(game);
      await run(game, 2);
      // PRD-2 §3.33 (WP-2b): runs rumble — one shake per perfect pass (never
      // skipped), knocks only for grazes / pickups; nothing else.
      final pulses = game.rumble.fired.sublist(inRun);
      expect(
        pulses.where((k) => k == RumbleKind.shake).length,
        runState.perfectPasses,
      );
      expect(
        pulses.where((k) => k == RumbleKind.knock).length,
        lessThanOrEqualTo(
          runState.passes - runState.perfectPasses + pickups,
        ),
      );
    },
  );

  _journey('R2 reduce motion toggled at home → LEVELS → static emblems', (
    game,
    rig,
    tester,
  ) async {
    await run(game, .3);
    expect(game.homeScreen!.emblem.t, greaterThan(0));
    game.reduceMotionOverride = true;
    await run(game, 1);
    expect(game.homeScreen!.emblem.t, 0);
    expect(game.homeScreen!.emblem.shine, isFalse);
    await _tap(game, tester, game.homeScreen!.bird);
    await run(game, .6);
    final levels = game.levelsScreen!;
    expect(levels.currentRow!.liveEmblem!.t, 0);
    expect(levels.header.emblem.t, 0);
    await run(game, 2);
    expect(levels.currentRow!.liveEmblem!.t, 0);
    expect(levels.header.emblem.shine, isFalse);
  }, prefs: {'bestScore': 5000, 'claimedLevels': _claimed(10)});

  _defect(
    'S1-31',
    'No ads bonus stays held while the preceding LEVEL UP counts',
    (game, rig, tester) async {
      rig.iap.delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      await run(game, .8);
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
      expect(game.levelUpPopup, isNotNull);
      expect(game.queuedPopups, 1);
      expect(game.coinPill.shownBalance, 1250);
      await _tap(game, tester, game.levelUpPopup!.claimButton);
      expect(game.noAdsCelebration, isNotNull);
      await run(game, 4);
      expect(game.menu.wallet.balance, 2300);
      expect(
        game.coinPill.shownBalance,
        1300,
        reason: 'only EGG +50 may count before the No ads CLAIM',
      );
      await _tap(game, tester, game.noAdsCelebration!.claimButton);
      await run(game, .9);
      expect(game.coinPill.shownBalance, inExclusiveRange(1300, 2300));
      await run(game, 5);
      expect(game.coinPill.shownBalance, 2300);
      expect(rig.events.count('noads_bonus_claimed'), 1);
    },
    prefs: const {'coins': 1250, 'bestScore': 10},
  );

  _journey(
    'R2 delayed fresh No ads during a run → home → celebration → claim',
    (game, rig, tester) async {
      rig.iap.delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      await _tap(game, tester, game.homeScreen!.startButton);
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
      expect(game.menu.noAds, isTrue);
      expect(game.noAdsCelebration, isNull);
      expect(game.queuedPopups, 1);
      await run(game, 2);
      expect(game.state, GameState.results);
      final panel = game.world.children.query<ResultsScreen>().single;
      await run(game, .4);
      await _tap(game, tester, panel.nextButton);
      await run(game, .8);
      expect(_modalCount(game), 1);
      expect(game.noAdsCelebration, isNotNull);
      expect(game.coinPill.shownBalance, 1250);
      await _tap(game, tester, game.noAdsCelebration!.claimButton);
      await run(game, 6);
      expect(game.coinPill.shownBalance, 2250);
      expect(game.homeScreen!.noAdsTile.owned, isTrue);
      expect(rig.events.count('noads_celebration_shown'), 1);
    },
    prefs: const {'coins': 1250},
  );

  _defect(
    'S2-34',
    'No ads header must stop when reduce motion becomes enabled',
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      await run(game, .2);
      final popup = game.noAdsCelebration!;
      game.reduceMotionOverride = true;
      await run(game, .05);
      expect(
        (popup.cardPose.scale, popup.cardPose.angle, popup.iconWobble),
        (1.0, 0.0, (1.0, 0.0)),
        reason: 'the card must settle and the AD icon must stop wobbling',
      );
    },
  );

  group('S2-35', () {
    test('unranked frame must reuse its static paths between warm frames', () {
      final first = _PathRecorder();
      final second = _PathRecorder();
      EmblemPainter.paint(first, 0, t: .2);
      EmblemPainter.paint(second, 0, t: .3);
      expect(
        second.paths.where(
          (path) => !first.paths.any((old) => identical(old, path)),
        ),
        isEmpty,
        reason: 'the unranked octagon has no animated geometry (§11)',
      );
    });
    test('unranked view must cache even during the ranked sweep interval', () {
      final view = EmblemView(level: 0, artScale: 1)..t = .2;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      view.render(canvas); // warm
      view.t = .3;
      view.render(canvas);
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      expect(
        view.drewCached,
        isTrue,
        reason: 'there is no sweep to repaint on the unranked frame',
      );
    });
  });

  final redeliveryStore = FakeStore()..goLive(IapProduct.values);
  _defect(
    'S1-32',
    'cold redelivery of an old No ads receipt must not celebrate',
    (game, rig, tester) async {
      await game.monetization.iap.initialize();
      // Reinstall: no local ownership yet, no buy initiated this session.
      // The store replays a previously completed non-consumable receipt.
      redeliveryStore.purchases.add([
        PurchaseDetails(
          purchaseID: 'already-completed-noads',
          productID: IapProduct.noAds.storeId,
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'google_play',
          ),
          transactionDate: '1665000000000',
          status: PurchaseStatus.purchased,
        ),
      ]);
      await _settle(game, tester);
      await run(game, .8);
      expect(redeliveryStore.launched, isEmpty);
      expect(game.menu.noAds, isTrue);
      expect(
        (game.noAdsCelebration == null, game.menu.wallet.balance),
        (true, 1250),
        reason: 'an old receipt recovers ownership without a fresh bonus',
      );
      expect(rig.events.count('noads_celebration_shown'), 0);
    },
    prefs: const {'coins': 1250},
    service: StoreIapService(store: redeliveryStore),
  );

  // Visual probe: a separately captured frame avoids inherited screenshot
  // resize state and checks the actual shared chrome, not just hit geometry.
  _journey('R2 Settings shared back box visible after Shop round trip', (
    game,
    rig,
    tester,
  ) async {
    await _tap(game, tester, game.homeScreen!.shopTile);
    await run(game, .6);
    await _tap(game, tester, game.shopScreen!.backButton);
    await run(game, .6);
    await _tap(game, tester, game.homeScreen!.gearButton);
    await run(game, .6);
    expect(game.cornerBox.opacity, 1);
    expect(game.cornerBox.gearMix, 0);
    expect(game.cornerBox.isMounted, isTrue);
    await tester.runAsync(() => captureShot(game, 2, 'r2_settings_back_probe'));
  });
}
