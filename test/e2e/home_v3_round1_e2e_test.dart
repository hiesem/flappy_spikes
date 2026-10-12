import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/levels/levels_screen.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/ui/confetti.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

// Independent QA against PRD-home-v3 and briefs3/common.md. The S1-/S2-
// groups pin the round-1 findings (fixed in hv-fix1).

class _Events extends GameServices {
  final events = <(String, Map<String, Object>?)>[];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));

  List<Map<String, Object>?> params(String name) => [
    for (final event in events)
      if (event.$1 == name) event.$2,
  ];
}

class _Rig {
  final events = _Events();
  final ads = FakeRewardedAds();
  final iap = FakeIapService();
  final sounds = <Sfx>[];
}

// Captures Path identities for §11, independently of raster/frame timing.
class _PathRecorder implements ui.Canvas {
  final paths = <ui.Path>[];

  @override
  void drawPath(ui.Path path, ui.Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  double height = 711,
}) {
  final rig = _Rig();
  FlameTester<FlappySpikesGame>(
    () => createTestGame(
      prefs,
      height,
      rig.events,
      Monetization(ads: rig.ads, iap: rig.iap),
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
      game.coinFlyRandom = math.Random(30);
      // Subscribe in the test zone, so fake billing callbacks are drained
      // by the test binding instead of the setup's runAsync zone.
      game.purchases
        ..dispose()
        ..start();
      try {
        await verify(game, rig, tester);
      } finally {
        // Drain Flutter's 40 ms multi-tap gesture timers, including when
        // an open-defect assertion throws.
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}

// Round-1 defect reproductions, fixed in hv-fix1 (now regular regressions).
void _defect(
  String id,
  String description,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
}) {
  group(id, () => _journey(description, verify, prefs: prefs));
}

Future<void> _settle(FlappySpikesGame game, WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    for (var i = 0; i < 20; i++) {
      await Future<void>.value();
    }
    await tester.binding.delayed(Duration.zero);
  }
  await flushAndMount(game);
}

Future<void> _advance(
  FlappySpikesGame game,
  double seconds, {
  void Function()? sample,
}) async {
  for (var t = 0.0; t < seconds - 1e-9; t += .05) {
    stepGame(game, .05);
    await flushAndMount(game);
    sample?.call();
  }
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

Future<void> _shot(
  FlappySpikesGame game,
  WidgetTester tester,
  String name,
) async {
  await tester.runAsync(() => captureShot(game, 2, 'qa3_$name'));
  game.onGameResize(Vector2(320, game.viewHeight));
}

Future<GameStorage> _reload() async {
  final storage = GameStorage();
  await storage.load();
  return storage;
}

Iterable<String> _texts(Component parent) =>
    parent.descendants().whereType<MenuText>().map((text) => text.text);

List<String> _claimed(int upTo) => [for (var n = 1; n <= upTo; n++) '$n'];

// Real physics/scoring, using the existing acceptance bot's look-ahead
// controller. No score, best, wallet or claimed-level writes in this run.
Future<void> _flyToEgg(FlappySpikesGame game) async {
  // WP-1a: the hoop-aware acceptance bot (PRD-2 §7) flies the real course.
  final flight = await flyRun(game, maxSeconds: 75, untilHoops: 12);
  expect(game.score, greaterThanOrEqualTo(12),
      reason: 'actual hoop scoring\n${flight.trace.reversed.take(5).join('\n')}');
  // WP-3a: a comet boost (first met at hoop 10) flies itself; finish it.
  await flyOutOfRide(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  test('QA home v3: rank thresholds and all 10 rewards match §4.1', () {
    const thresholds = [10, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000];
    const rewards = [50, 100, 150, 250, 400, 600, 800, 1000, 2000, 5000];
    const names = [
      'EGG',
      'CHICK',
      'FLEDGLING',
      'FLAPPER',
      'GLIDER',
      'FALCON',
      'HAWK',
      'SPIKE ACE',
      'PHOENIX',
      'LEGEND',
    ];
    expect(kLevels.map((level) => level.threshold), thresholds);
    expect(kLevels.map((level) => level.reward), rewards);
    expect(kLevels.map((level) => level.name), names);
    expect(rewards.reduce((a, b) => a + b), 10350);
    for (var i = 0; i < thresholds.length; i++) {
      expect(levelFor(thresholds[i] - 1), i);
      expect(levelFor(thresholds[i]), i + 1);
      expect(levelFor(thresholds[i] + 1), i + 1);
    }
  });

  for (final height in [568.0, 711.0]) {
    _journey('QA fresh install → real run 12 → home → claim → EGG ($height)', (
      game,
      rig,
      tester,
    ) async {
      expect(game.homeScreen!.emblem.level, 0);
      expect(game.homeScreen!.lastStat.value, '—');
      await _tap(game, tester, game.homeScreen!.startButton);
      await flushAndMount(game);
      expect(game.state, GameState.playing);
      await _flyToEgg(game);
      expect(game.levelUpPopup, isNull, reason: 'no popup in a run');
      // Stop flapping: the bird misses a hoop or hits the floor, tumbles
      // (§3.0.5) and the results come up.
      await _advance(game, 3);
      // PRD-2 §3.14 (WP-2d): ≥ 6 hoops → the revive offer; No thanks.
      await declineRevive(game);
      expect(game.state, GameState.results);
      expect(game.levelUpPopup, isNull, reason: 'no popup at game over');
      final score = game.storage.lastScore!;
      final earned = game.menu.wallet.balance;
      expect(score, greaterThanOrEqualTo(12));
      // PRD-2 §3.2: 1 coin per hoop, 2 for a perfect pass, at the pass.
      expect(earned, game.run!.state.coinsThisRun);
      expect(earned, greaterThanOrEqualTo(score));
      // PRD-2 §3.14: the level up is celebrated and claimed on the results
      // page (it replaces the home LEVEL UP popup).
      final panel = game.world.children.query<ResultsScreen>().single;
      await _advance(game, 4.2);
      expect(panel.claimShowing, isTrue);
      expect(panel.rank.text, 'EGG · LV 1');
      await _tap(game, tester, panel.claimButton.button);
      expect(game.menu.wallet.balance, earned + 50);
      await _advance(game, 3);
      expect(panel.shownReward, earned + 50);
      await _tap(game, tester, panel.nextButton);
      await _advance(game, .9);
      expect(game.levelUpPopup, isNull, reason: 'claimed on the results page');
      expect(game.stageBackground, paletteForStage(0).background);
      expect(game.foregroundColor, paletteForStage(0).foreground);
      await _advance(game, 4);
      expect(game.levelUpPopup, isNull);
      expect(game.coinPill.shownBalance, earned + 50);
      expect(game.menu.levels.pendingLevelUp, isNull);
      expect(game.homeScreen!.emblem.level, 1);
      expect(rig.events.params('level_up'), [
        {'from': 0, 'to': 1, 'reward': 50, 'claim': 'tap'},
      ]);
      final saved = await _reload();
      expect(saved.claimedLevels, {1});
      expect(saved.coins, earned + 50);
      await _tap(game, tester, game.homeScreen!.bird);
      await _advance(game, .5);
      final levels = game.levelsScreen!;
      expect(levels.rows.first.state, LevelRowState.current);
      expect(levels.rows.first.reached, isTrue);
      expect(levels.rows[1].state, LevelRowState.locked);
      expect(rig.events.params('levels_open'), [
        {'source': 'home_emblem'},
      ]);
      await _tap(game, tester, levels.backButton);
      await _advance(game, 1);
      expect(game.levelUpPopup, isNull);
      expect(rig.events.params('level_up'), hasLength(1));
    }, height: height);
  }

  _journey(
    'QA existing FALCON: launch upsell → single catch-up → close claims → persisted',
    (game, rig, tester) async {
      expect(game.noAdsPopup, isNotNull);
      await _advance(game, .8);
      expect(game.levelUpPopup, isNull);
      game.handleBack();
      await _advance(game, .8);
      expect(game.noAdsPopup, isNull);
      final popup = game.levelUpPopup!;
      expect(popup.pending.toLevel, 6);
      expect(popup.pending.reward, 1550);
      await _tap(game, tester, popup.closeButton);
      await _advance(game, 5);
      expect(game.menu.wallet.balance, 2800);
      expect(game.coinPill.shownBalance, 2800);
      expect(rig.events.params('level_reward_claimed'), [
        {'level': 6, 'coins': 1550},
      ]);
      expect(await game.menu.levels.claim(), 0);
      final saved = await _reload();
      expect(saved.claimedLevels, {1, 2, 3, 4, 5, 6});
      expect(saved.coins, 2800);
      await _tap(game, tester, game.homeScreen!.bird);
      await _advance(game, .5);
      final levels = game.levelsScreen!;
      expect(levels.scroll.offset, greaterThan(0));
      expect(levels.currentRow!.def.name, 'FALCON');
      expect(levels.header.statsText.text, 'BEST 640 · GAMES 34');
      expect(levels.header.barText.text, '160 TO HAWK');
      await _tap(game, tester, levels.backButton);
      await _advance(game, 1);
      expect(game.levelUpPopup, isNull);
      expect(rig.events.params('level_up'), hasLength(1));
    },
    prefs: {
      'bestScore': 640,
      'coins': 1250,
      'gamesPlayed': 34,
      'installDay': 1,
    },
  );

  for (final height in [568.0, 640.0, 711.0, 730.0]) {
    _journey(
      'QA home alignment and 4+ digit shrink ($height)',
      (game, rig, tester) async {
        game.reduceMotionOverride = true;
        await _advance(game, .2);
        final home = game.homeScreen!;
        expect(home.gearButton.x, 14);
        expect(home.gearButton.y, 58);
        expect(home.trophyButton.x, 60);
        expect(home.bestStat.x, 14);
        expect(home.lastStat.x + home.lastStat.width, 306);
        expect(home.shopTile.x, 14);
        expect(home.noAdsTile.x + home.noAdsTile.width, 306);
        expect(game.coinPill.x + game.coinPill.width, 306);
        expect(home.emblem.x, 160);
        expect(home.startButton.x + home.startButton.width / 2, 160);
        expect(home.slotButton.x + home.slotButton.width / 2, 160);
        expect(home.bestStat.y + home.bestStat.height / 2, home.emblem.y);
        expect(home.lastStat.y + home.lastStat.height / 2, home.emblem.y);
        final ribbonBottom = home.emblem.y + 72 * home.emblem.artScale;
        // PRD-2.2 §2.1: the centred block starts at the mode button.
        final topGap = home.modeButton.y - ribbonBottom;
        final bottomGap =
            home.shopTile.y - home.slotButton.y - home.slotButton.height;
        expect(topGap, greaterThan(0));
        expect(
          bottomGap,
          closeTo(topGap, 3),
          reason: 'approximately centred; ribbon reaches about 72 art units',
        );
        for (final stat in [home.bestStat, home.lastStat]) {
          expect(
            stat.numberText.width * stat.numberText.scale.x,
            lessThanOrEqualTo(70),
          );
          expect(stat.numberText.scale.x, lessThan(1));
        }
        // PRD-2.2 §2.1: below 0.78 only on the shortest screens (8 pt gaps).
        expect(home.emblem.artScale, greaterThanOrEqualTo(.70));
        if (height == 711) {
          expect(home.startButton.y, 403); // PRD-2.2 §2.1 (was 390)
          expect(home.slotButton.y, 474); // (was 461)
          expect(home.shopTile.y, 562);
        }
      },
      prefs: {
        'bestScore': 6000,
        'lastScore': 1234,
        'claimedLevels': _claimed(10),
      },
      height: height,
    );
  }

  const packs = [
    (IapProduct.coins1000, 6, .9, 40, Sfx.skBuyCommon),
    (IapProduct.coins10000, 9, 1.2, 70, Sfx.skBuyRare),
    (IapProduct.coins17000, 12, 1.5, 100, Sfx.skBuyEpic),
    (IapProduct.coins100000, 16, 1.9, 150, Sfx.skBuyLegendary),
  ];
  for (final preset in packs) {
    _journey(
      'QA fake IAP ${preset.$1.storeId} → flight → monotone count → saved balance',
      (game, rig, tester) async {
        await _tap(game, tester, game.homeScreen!.shopTile);
        await _advance(game, .6);
        final shop = game.shopScreen!;
        expect(_texts(shop), isNot(contains('RESTORE PURCHASES')));
        final pack = shop.packFor(preset.$1)!;
        await _tap(game, tester, pack);
        expect(game.menu.wallet.balance, 1250 + preset.$1.coins);
        expect(game.coinPill.shownBalance, 1250);
        final reward = game.coinReward!;
        expect(reward.coins, preset.$2);
        expect(reward.countDuration, preset.$3);
        expect(reward.confetti, preset.$4);
        expect(reward.from, pack.artRect);
        var previous = 1250;
        var sawIntermediate = false;
        await _advance(
          game,
          6,
          sample: () {
            final shown = game.coinPill.shownBalance;
            expect(shown, inInclusiveRange(previous, 1250 + preset.$1.coins));
            sawIntermediate |= shown > 1250 && shown < 1250 + preset.$1.coins;
            previous = shown;
          },
        );
        expect(sawIntermediate, isTrue);
        expect(previous, 1250 + preset.$1.coins);
        expect(
          rig.sounds.where((sound) => sound == Sfx.bnCoin),
          hasLength(preset.$2),
        );
        expect(
          rig.sounds,
          containsAllInOrder([
            Sfx.bnCoin,
            Sfx.skTick,
            preset.$5,
            Sfx.skProgress,
          ]),
        );
        expect((await _reload()).coins, previous);
        expect(rig.events.params('iap_purchase'), [
          {'product': preset.$1.storeId},
        ]);
        expect(rig.events.params('coins_earned'), [
          {'amount': preset.$1.coins, 'source': 'iap'},
        ]);
        expect(
          game.world.descendants().whereType<ConfettiBurst>(),
          isEmpty,
          reason: 'every burst expires; no stranded particles',
        );
        expect(game.purchaseResultPopup, isNull);
      },
      prefs: const {'coins': 1250},
    );
  }

  for (final mode in [
    FakeIapMode.cancel,
    FakeIapMode.fail,
    FakeIapMode.pending,
  ]) {
    for (final noAds in [false, true]) {
      _journey(
        'QA ${mode.name} ${noAds ? 'No ads' : 'coin pack'} → result → unchanged wallet',
        (game, rig, tester) async {
          rig.iap.mode = mode;
          if (noAds) {
            await _tap(game, tester, game.homeScreen!.noAdsTile);
          } else {
            await _tap(game, tester, game.homeScreen!.shopTile);
            await _advance(game, .6);
            await _tap(game, tester, game.shopScreen!.packs.first);
          }
          await _advance(game, .5);
          expect(game.menu.wallet.balance, 1250);
          expect(game.menu.noAds, isFalse);
          expect(game.noAdsCelebration, isNull);
          expect(game.coinReward, isNull);
          final product = noAds ? 'no_ads' : 'coins_1000';
          if (mode == FakeIapMode.pending) {
            expect(game.purchaseResultPopup, isNull);
            expect(rig.events.params('purchase_result_popup'), isEmpty);
          } else {
            final popup = game.purchaseResultPopup!;
            expect(
              _texts(popup),
              contains(
                mode == FakeIapMode.cancel
                    ? 'PURCHASE CANCELLED'
                    : 'PURCHASE FAILED',
              ),
            );
            expect(rig.events.params('purchase_result_popup'), [
              {
                'product': product,
                'outcome': mode == FakeIapMode.cancel ? 'cancelled' : 'failed',
                if (mode == FakeIapMode.fail) 'code': 'fake',
              },
            ]);
            expect(
              rig.events.params('iap_error'),
              mode == FakeIapMode.fail
                  ? [
                      {
                        'product': product,
                        'reason': 'Fake error',
                        'code': 'fake',
                      },
                    ]
                  : isEmpty,
            );
            await _tap(game, tester, popup.okButton);
            await _advance(game, .2);
            expect(game.purchaseResultPopup, isNull);
          }
          expect((await _reload()).coins, 1250);
        },
        prefs: const {'coins': 1250},
      );
    }
  }

  for (final source in ['tile', 'shop_banner', 'popup']) {
    _journey(
      'QA fresh No ads from $source → claim → owned → restore/redelivery silent',
      (game, rig, tester) async {
        if (source == 'tile') {
          await _tap(game, tester, game.homeScreen!.noAdsTile);
        } else if (source == 'shop_banner') {
          await _tap(game, tester, game.homeScreen!.shopTile);
          await _advance(game, .6);
          await _tap(game, tester, game.shopScreen!.banner);
        } else {
          game.openNoAdsPopup();
          await _advance(game, .3);
          await _tap(game, tester, game.noAdsPopup!.priceButton);
        }
        await _advance(game, .7);
        expect(game.noAdsPopup, isNull);
        expect(game.noAdsCelebration, isNotNull);
        expect(game.menu.wallet.balance, 2250);
        expect(game.coinPill.shownBalance, 1250);
        expect(game.noAdsShown, isFalse);
        expect(rig.events.params('noads_celebration_shown'), [
          {'source': source},
        ]);
        await _tap(game, tester, game.noAdsCelebration!.claimButton);
        await _advance(
          game,
          6,
          sample: () =>
              expect(game.coinPill.shownBalance, inInclusiveRange(1250, 2250)),
        );
        expect(game.coinPill.shownBalance, 2250);
        expect(game.noAdsShown, isTrue);
        expect(game.noAdsVideoGone, isTrue);
        expect(rig.sounds, containsAll([Sfx.noadsUnlock, Sfx.noadsStamp]));
        expect(rig.events.params('noads_bonus_claimed'), hasLength(1));
        if (source == 'shop_banner') {
          expect(game.shopScreen!.banner.owned, isTrue);
          expect(game.shopScreen!.banner.tappable, isFalse);
          expect(game.shopScreen!.freeCoins.chipText, 'CLAIM');
          expect(game.shopScreen!.freeCoins.videoIcon, isNull);
          await _tap(game, tester, game.shopScreen!.backButton);
          await _advance(game, .6);
        }
        expect(game.homeScreen!.noAdsTile.label.text, 'AD-FREE');
        expect(game.homeScreen!.slotButton.showsVideo, isFalse);
        final saved = await _reload();
        expect(saved.noAds, isTrue);
        expect(saved.coins, 2250);
        // A purchase already owned in the fake store is redelivered.
        unawaited(rig.iap.buy(IapProduct.noAds));
        await _settle(game, tester);
        await game.restorePurchases();
        await _settle(game, tester);
        expect(game.noAdsCelebration, isNull);
        expect(game.menu.wallet.balance, 2250);
        expect(rig.events.params('noads_celebration_shown'), hasLength(1));
        expect(rig.events.params('coins_earned'), [
          {'amount': 1000, 'source': 'noads_bonus'},
        ]);
      },
      prefs: const {'coins': 1250},
    );
  }

  _journey(
    'QA reinstall: Settings restore of store-owned No ads has no celebration or bonus',
    (game, rig, tester) async {
      // Seed ownership on the store side without a grant to this fresh
      // installation. The fake store remembers bought non-consumables.
      game.purchases.dispose();
      unawaited(rig.iap.buy(IapProduct.noAds));
      await _settle(game, tester);
      expect(rig.iap.ownsNoAds, isTrue);
      expect(game.menu.noAds, isFalse);
      game.purchases.start();
      await _tap(game, tester, game.homeScreen!.gearButton);
      await _advance(game, .6);
      final settings = game.world.children.query<SettingsPanel>().single;
      await _tap(game, tester, settings.restoreLink!.button);
      await _advance(game, .3);
      expect(game.menu.noAds, isTrue);
      expect(game.noAdsCelebration, isNull);
      expect(game.coinReward, isNull);
      expect(game.menu.wallet.balance, 1250);
      expect(rig.events.params('noads_celebration_shown'), isEmpty);
      expect(rig.events.params('coins_earned'), isEmpty);
      await _tap(game, tester, settings.backButton);
      await _advance(game, .6);
      expect(game.homeScreen!.noAdsTile.owned, isTrue);
      expect(game.homeScreen!.slotButton.showsVideo, isFalse);
      expect((await _reload()).noAds, isTrue);
    },
    prefs: const {'coins': 1250},
  );

  _journey(
    'QA stored RUMBLE off: menu taps stay silent; toggled state persists',
    (game, rig, tester) async {
      expect(game.rumble.on, isFalse);
      await _tap(game, tester, game.homeScreen!.shopTile);
      await _advance(game, .6);
      await _tap(game, tester, game.shopScreen!.backButton);
      await _advance(game, .6);
      await _tap(game, tester, game.homeScreen!.gearButton);
      await _advance(game, .6);
      expect(game.rumble.fired, isEmpty);
      final settings = game.world.children.query<SettingsPanel>().single;
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.fired, [RumbleKind.knock]);
      await _advance(game, .2);
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.fired, [RumbleKind.knock]);
      expect((await _reload()).rumble, isFalse);
    },
    prefs: const {'rumble': false},
  );

  _journey(
    'QA Settings actual rumble toggle → one enable knock → persist → run silence',
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.gearButton);
      await _advance(game, .6);
      final settings = game.world.children.query<SettingsPanel>().single;
      expect(
        settings.backButton.toRect(),
        const ui.Rect.fromLTWH(14, 58, 38, 38),
      );
      expect(settings.restoreLink, isNotNull);
      final previous = game.rumble.fired.length;
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.on, isFalse);
      expect(game.rumble.fired.length, previous, reason: 'off is silent');
      await _advance(game, .2);
      await _tap(game, tester, settings.rumbleButton);
      expect(game.rumble.fired.length, previous + 1);
      expect(game.rumble.fired.last, RumbleKind.knock);
      expect(settings.rumbleButton.buzzing, isTrue);
      await _advance(game, .4);
      expect(settings.rumbleButton.buzzing, isFalse);
      expect((await _reload()).rumble, isTrue);
      expect(rig.events.params('rumble_toggle'), [
        {'on': 0},
        {'on': 1},
      ]);
      await _tap(game, tester, settings.backButton);
      await _advance(game, .6);
      final beforeStart = game.rumble.fired.length;
      await _tap(game, tester, game.homeScreen!.startButton);
      expect(game.rumble.fired.length, beforeStart + 1);
      await _advance(game, .15);
      final inRun = game.rumble.fired.length;
      await tester.tapAt(const ui.Offset(160, 300));
      await _settle(game, tester);
      game.run!.debugPass();
      killRun(game);
      await _advance(game, 2);
      // PRD-2 §3.33 (WP-2b): a non-perfect pass knocks once; the death and
      // the screens after it never rumble.
      expect(
        game.rumble.fired.sublist(inRun),
        [RumbleKind.knock],
        reason: 'one knock for the pass, nothing for the death',
      );
    },
  );

  _journey(
    'QA reduce motion: home idle static emblem; coin and No ads grants still complete',
    (game, rig, tester) async {
      // The game reads dart:ui's singleton, not the binding's wrapped
      // TestPlatformDispatcher. Exercise its channel-free override.
      game.reduceMotionOverride = true;
      expect(game.reduceMotion, isTrue);
      await _advance(game, 15);
      expect(game.homeScreen!.emblem.t, 0);
      expect(game.homeScreen!.emblem.shine, isFalse);
      expect(game.homeScreen!.bird.idle.lastAction, isNull);
      await _tap(game, tester, game.homeScreen!.shopTile);
      await _advance(game, .6);
      await _tap(game, tester, game.shopScreen!.packs.last);
      await _advance(
        game,
        6,
        sample: () => expect(
          game.world.descendants().whereType<ConfettiBurst>(),
          isEmpty,
        ),
      );
      expect(game.coinPill.shownBalance, 100000);
      await _tap(game, tester, game.shopScreen!.banner);
      await _advance(game, .8);
      expect(game.world.children.query<ScreenFlash>(), isEmpty);
      expect(game.world.children.query<ScreenShake>(), isEmpty);
      expect(game.world.descendants().whereType<ConfettiBurst>(), isEmpty);
      await _tap(game, tester, game.noAdsCelebration!.claimButton);
      await _advance(game, 5);
      expect(game.coinPill.shownBalance, 101000);
      expect(game.shopScreen!.banner.owned, isTrue);
    },
    prefs: {'bestScore': 6000, 'claimedLevels': _claimed(10)},
  );

  _defect(
    'S1-30',
    'late No ads success must wait for the existing LEVEL UP card',
    (game, rig, tester) async {
      rig.iap.delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      expect(game.purchases.isPending(IapProduct.noAds), isTrue);
      // The owed catch-up settles while the payment method is pending.
      await _advance(game, .8);
      expect(game.levelUpPopup, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
      expect(game.menu.noAds, isTrue, reason: 'billing callback delivered');
      await _shot(game, tester, 'S1-30_queued');
      expect(
        game.noAdsCelebration,
        isNull,
        reason: 'queue the celebration until LEVEL UP has been claimed',
      );
      expect(game.queuedPopups, 1);
      await _tap(game, tester, game.levelUpPopup!.claimButton);
      expect(game.levelUpPopup, isNull);
      expect(game.noAdsCelebration, isNotNull, reason: 'its turn now');
      expect(game.queuedPopups, 0);
      await _tap(game, tester, game.noAdsCelebration!.claimButton);
      await _advance(game, 5);
      expect(game.levelUpPopup, isNull, reason: 'EGG paid once');
      expect(game.coinPill.shownBalance, 1050);
    },
    prefs: const {'bestScore': 10},
  );

  _defect('S2-30', 'LEVEL UP emblem must freeze under OS reduce motion', (
    game,
    rig,
    tester,
  ) async {
    game.reduceMotionOverride = true;
    expect(game.reduceMotion, isTrue);
    await _advance(game, 1);
    final popup = game.levelUpPopup!;
    expect(popup.pending.toLevel, 10);
    expect(popup.confetti, isNull);
    final phase = popup.emblem.t;
    await _advance(game, 1);
    expect(popup.emblem.shine, isFalse);
    expect(
      popup.emblem.t,
      phase,
      reason: 'flags, stars, rays and ring must be static',
    );
  }, prefs: {'bestScore': 5000, 'claimedLevels': _claimed(9)});

  _defect('S2-31', 'LEVEL UP home upgrade pop must follow the coin count-up', (
    game,
    rig,
    tester,
  ) async {
    await _advance(game, .8);
    await _tap(game, tester, game.levelUpPopup!.claimButton);
    await _advance(game, .1);
    expect(game.coinPill.shownBalance, 0, reason: 'first coin has not landed');
    expect(
      game.homeScreen!.popping,
      isFalse,
      reason: 'upgrade pop belongs after the reward count-up (§4.3)',
    );
    expect(game.homeScreen!.emblem.level, 0, reason: 'upgrades with the pop');
    var popAt = -1.0;
    var countedAt = -1.0;
    var t = .1;
    await _advance(
      game,
      4,
      sample: () {
        t += .05;
        if (countedAt < 0 && game.coinPill.shownBalance == 50) countedAt = t;
        if (popAt < 0 && game.homeScreen!.popping) popAt = t;
      },
    );
    expect(countedAt, greaterThan(0));
    expect(popAt, greaterThanOrEqualTo(countedAt));
    expect(game.homeScreen!.emblem.level, 1);
    expect(game.homeScreen!.popping, isFalse);
  }, prefs: const {'bestScore': 10});

  for (final mode in [FakeIapMode.cancel, FakeIapMode.fail]) {
    _defect(
      'S2-32',
      '${mode.name} while playing must present its result on returning home',
      (game, rig, tester) async {
        rig.iap.mode = mode;
        rig.iap.delay = const Duration(seconds: 2);
        await _tap(game, tester, game.homeScreen!.noAdsTile);
        await _tap(game, tester, game.homeScreen!.startButton);
        expect(game.state, GameState.playing);
        await tester.pump(const Duration(seconds: 2));
        await _settle(game, tester);
        expect(rig.events.params('purchase_result_popup'), hasLength(1));
        killRun(game);
        await _advance(game, 1);
        game.goHome();
        await _advance(game, 1);
        expect(
          game.purchaseResultPopup,
          isNotNull,
          reason:
              '§6 always shows cancellation/failure; never discard a late result',
        );
      },
    );
  }

  for (final mode in [
    FakeIapMode.succeed,
    FakeIapMode.cancel,
    FakeIapMode.fail,
  ]) {
    _journey(
      'R1 pending toast is dismissed when the No ads purchase resolves (${mode.name})',
      (game, rig, tester) async {
        rig.iap.mode = mode;
        rig.iap.delay = const Duration(seconds: 2);
        await _tap(game, tester, game.homeScreen!.noAdsTile);
        expect(game.toastMessage?.message, 'Purchase pending…');
        await tester.pump(const Duration(seconds: 2));
        await _settle(game, tester);
        expect(game.toastMessage, isNull, reason: 'resolved: toast gone');
        if (mode == FakeIapMode.succeed) {
          expect(game.noAdsCelebration, isNotNull);
        } else {
          expect(game.purchaseResultPopup, isNotNull);
        }
      },
    );
  }

  _journey(
    'R1 a coin pack result keeps the toast of another pending product',
    (game, rig, tester) async {
      rig.iap.delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      final toast = game.toastMessage;
      expect(toast?.message, 'Purchase pending…');
      // An unrelated product resolving must not drop No ads' toast.
      game.purchases.onResolved!(IapProduct.coins1000);
      await flushAndMount(game);
      expect(game.toastMessage, same(toast));
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
    },
  );

  _journey(
    'R1 a purchase result waits for LEVEL UP, then opens (arrival order)',
    (game, rig, tester) async {
      rig.iap.mode = FakeIapMode.cancel;
      rig.iap.delay = const Duration(seconds: 2);
      await _tap(game, tester, game.homeScreen!.noAdsTile);
      await _advance(game, .8);
      expect(game.levelUpPopup, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      await _settle(game, tester);
      expect(rig.events.params('purchase_result_popup'), hasLength(1));
      expect(game.purchaseResultPopup, isNull, reason: 'never two popups');
      await _tap(game, tester, game.levelUpPopup!.claimButton);
      expect(game.purchaseResultPopup, isNotNull);
      await _tap(game, tester, game.purchaseResultPopup!.okButton);
      expect(game.purchaseResultPopup, isNull);
      expect(game.queuedPopups, 0);
    },
    prefs: const {'bestScore': 10},
  );

  group('S2-33', () {
    test('FALCON sweep must reuse path geometry between frames (§11)', () {
      final first = _PathRecorder();
      final second = _PathRecorder();
      EmblemPainter.paint(first, 6, t: .2);
      EmblemPainter.paint(second, 6, t: .3);
      final newPaths = second.paths
          .where((path) => !first.paths.any((old) => identical(old, path)))
          .length;
      expect(
        newPaths,
        0,
        reason: 'move a cached sweep shape with a canvas transform',
      );
    });
  });
}
