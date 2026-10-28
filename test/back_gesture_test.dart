import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/main.dart' show SystemBackObserver;
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// PRD-2.2 §8: the Android system back closes the menu screens and popups,
/// and does nothing anywhere else. It never closes the app.
void main() {
  group('PRD-2.2 §8 Android back gesture', () {
    _backTest(
      'home with nothing open: nothing closes, plays or is logged',
      verify: (game, spy, tester) async {
        final sounds = sfxLog(game);
        expect(game.handleSystemBack(), isFalse);
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.menuScene, MenuScene.home);
        expect(sounds, isEmpty);
        expect(_backScreens(spy), isEmpty);
      },
    );

    _backTest(
      'settings: the topmost popup closes first, then settings',
      verify: (game, spy, tester) async {
        game.openSettings();
        await flushAndMount(game);
        game.openDeleteDataConfirm();
        await flushAndMount(game);
        expect(game.deleteDataPopup, isNotNull);

        expect(game.handleSystemBack(), isTrue);
        expect(game.deleteDataPopup, isNull, reason: 'the popup is on top');
        expect(game.menuScene, MenuScene.settings);

        expect(game.handleSystemBack(), isFalse, reason: 'one close per back');
        await stepSeconds(game, Config.systemBackDebounce + 0.01);

        expect(game.handleSystemBack(), isTrue);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
        expect(_backScreens(spy), ['popup', 'settings']);
      },
    );

    _backTest(
      'shop, skins and levels close back to home',
      verify: (game, spy, tester) async {
        game.openShop();
        await flushAndMount(game);
        expect(game.shopScreen, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        expect(game.shopScreen, isNull);
        await stepSeconds(game, Config.systemBackDebounce + 0.01);

        game.openSkins();
        await flushAndMount(game);
        expect(game.skinShop, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        expect(game.skinShop, isNull);
        await stepSeconds(game, Config.systemBackDebounce + 0.01);

        game.openLevels();
        await flushAndMount(game);
        expect(game.levelsScreen, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        expect(game.levelsScreen, isNull);
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(_backScreens(spy), ['shop', 'skins', 'levels']);
      },
    );

    _backTest(
      'home popups close like their own close: the NO ADS offer and LEVEL UP',
      verify: (game, spy, tester) async {
        await stepSeconds(game, 0.6); // the home intro (popups wait for it)
        game.openNoAdsPopup();
        await flushAndMount(game);
        expect(game.noAdsPopup, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        expect(game.noAdsPopup, isNull);
        await stepSeconds(game, Config.systemBackDebounce + 0.01);

        await game.menu.levels.debugForceLevelUp(); // a reward is owed
        // PRD 2.6 C2: the No-Ads popup spent the first visit's slot. Test
        // LEVEL UP's back handler on the next declared Home visit.
        game.homeMoments.beginVisit(
          HomeVisit(
            day: game.storage.now(),
            gamesPlayed: game.storage.gamesPlayed,
            requests: const HomeVisitRequests(levelUpCatchUp: true),
          ),
        );
        game.openLevelUpPopup();
        await flushAndMount(game);
        expect(game.levelUpPopup, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        // PRD-2.6 J7: Back reveals the box; LATER pays the pending reward.
        await flushAndMount(game);
        final reveal = game.levelUpPopup!.reveal;
        expect(reveal.current.revealed, isTrue);
        expect(game.menu.levels.pending, isNotEmpty);
        await reveal.current.choose(false);
        await flushAndMount(game);
        expect(game.levelUpPopup, isNull);
        expect(game.menu.levels.pending, isEmpty);
        expect(_backScreens(spy), ['popup', 'popup']);
      },
    );

    _backTest(
      'in a run: nothing closes or pauses or resumes, the pause settings stay',
      verify: (game, spy, tester) async {
        await startRun(game);
        expect(game.state, GameState.playing);
        expect(game.handleSystemBack(), isFalse);
        expect(game.state, GameState.playing);

        game.onKeyEvent(_keyDown(LogicalKeyboardKey.escape), {});
        await flushAndMount(game);
        expect(game.state, GameState.paused, reason: 'Esc still pauses');
        expect(game.handleSystemBack(), isFalse);
        expect(game.state, GameState.paused);

        game.openRunSettings();
        await flushAndMount(game);
        expect(game.runSettingsOpen, isTrue);
        expect(game.handleSystemBack(), isFalse);
        expect(game.runSettingsOpen, isTrue, reason: 'use its back arrow');
        expect(game.state, GameState.paused);
        expect(_backScreens(spy), isEmpty);
      },
    );

    _backTest(
      'the other run states (versus intro, dying, revive, bonus, results) '
      'do nothing',
      verify: (game, spy, tester) async {
        var calls = 0;
        bool probe() {
          calls++;
          return true;
        }

        game.pushBack(probe);
        for (final state in [
          GameState.versusIntro,
          GameState.dying,
          GameState.reviving,
          GameState.bonus,
          GameState.results,
        ]) {
          game.state = state;
          expect(game.handleSystemBack(), isFalse, reason: '$state');
        }
        game.state = GameState.start;
        expect(calls, 0, reason: 'no handler ran in any run state');
        game.popBack(probe);
        expect(_backScreens(spy), isEmpty);
      },
    );

    _backTest(
      'the purchase result card and the No-ads celebration close too',
      verify: (game, spy, tester) async {
        await stepSeconds(game, 0.6); // the home intro
        game.openPurchaseResultPopup(
          IapProduct.coins1000,
          PurchaseProblem.failed,
          null,
        );
        await flushAndMount(game);
        expect(game.purchaseResultPopup, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        expect(game.purchaseResultPopup, isNull);
        await stepSeconds(game, Config.systemBackDebounce + 0.01);

        game.openNoAdsCelebration();
        await flushAndMount(game);
        expect(game.noAdsCelebration, isNotNull);
        expect(game.handleSystemBack(), isTrue);
        await flushAndMount(game);
        expect(game.noAdsCelebration, isNull);
        expect(_backScreens(spy), ['popup', 'popup']);
      },
    );

    _backTest(
      'a video ad on screen: system back does nothing and the ad stays',
      monetization: () =>
          Monetization(ads: FakeRewardedAds())..showFakeAdOverlay = true,
      verify: (game, spy, tester) async {
        final tap = game.tapPowerupSlot();
        await flushAndMount(game);
        final overlay = game.fakeAdOverlay;
        expect(overlay, isNotNull, reason: 'the test ad is up');
        expect(game.handleSystemBack(), isFalse);
        expect(game.fakeAdOverlay, same(overlay));
        expect(_backScreens(spy), isEmpty);

        // Esc still closes the ad early (the current keyboard path).
        game.onKeyEvent(_keyDown(LogicalKeyboardKey.escape), {});
        await stepSeconds(game, 0.5);
        await tap;
        expect(game.fakeAdOverlay, isNull);
      },
    );

    _backTest(
      'one close per gesture: a close still fading out blocks the next back',
      verify: (game, spy, tester) async {
        final order = <String>[];
        game.pushBack(_popper(game, 'a', order));
        game.pushBack(_popper(game, 'b', order));

        expect(game.handleSystemBack(), isTrue, reason: 'b closes');
        expect(game.handleSystemBack(), isFalse, reason: 'b is fading out');
        expect(order, ['b']);

        await stepSeconds(game, Config.systemBackDebounce + 0.01);
        expect(game.handleSystemBack(), isTrue, reason: 'now a closes');
        expect(order, ['b', 'a']);
        expect(_backScreens(spy), ['popup', 'popup']);
      },
    );

    _backTest(
      'Esc is not debounced: it closes at once, right after a system back',
      verify: (game, spy, tester) async {
        final order = <String>[];
        game.pushBack(_popper(game, 'a', order));
        game.pushBack(_popper(game, 'b', order));

        expect(game.handleSystemBack(), isTrue);
        expect(
          game.onKeyEvent(_keyDown(LogicalKeyboardKey.escape), {}),
          KeyEventResult.handled,
        );
        expect(order, ['b', 'a']);
        expect(_backScreens(spy), ['popup'], reason: 'only the system back');
      },
    );

    _backTest(
      'plays the same sound as the back arrow',
      verify: (game, spy, tester) async {
        final sounds = sfxLog(game);

        game.openSettings();
        await flushAndMount(game);
        await stepSeconds(game, 0.3);
        sounds.clear();
        game.closeSettings(); // the back arrow's own close
        final arrow = List<String>.of(sounds);

        await stepSeconds(game, Config.systemBackDebounce + 0.01);
        game.openSettings();
        await flushAndMount(game);
        await stepSeconds(game, 0.3);
        sounds.clear();
        expect(game.handleSystemBack(), isTrue);
        expect(sounds, arrow);
        expect(arrow, [Sfx.click.name]);
      },
    );

    _backTest(
      'the system back observer reports every back as handled, so the app '
      'never leaves',
      verify: (game, spy, tester) async {
        final platform = <String>[];
        final messenger = TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
          platform.add(call.method);
          return Future<Object?>.value();
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final observer = SystemBackObserver(game);
        WidgetsBinding.instance.addObserver(observer);
        addTearDown(() => WidgetsBinding.instance.removeObserver(observer));

        // Home with nothing open: handled, nothing happens.
        expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
        expect(game.state, GameState.start);

        // A menu screen: it closes, the back is still handled.
        game.openSettings();
        await flushAndMount(game);
        expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
        expect(game.menuScene, MenuScene.home);
        await stepSeconds(game, 0.6); // the home fades back in

        // A run: handled, the run is untouched; so is every other state.
        await startRun(game);
        expect(await observer.didPopRoute(), isTrue);
        expect(game.state, GameState.playing);
        for (final state in [GameState.results, GameState.bonus]) {
          game.state = state;
          expect(await observer.didPopRoute(), isTrue, reason: '$state');
          expect(game.state, state);
        }

        expect(platform, isNot(contains('SystemNavigator.pop')));
      },
    );
  });
}

/// Analytics: the `back_gesture` events that were logged, as their `screen`.
List<Object?> _backScreens(AnalyticsSpy spy) => [
  for (final (name, params) in analyticsLog(spy))
    if (name == 'back_gesture') params?['screen'],
];

KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: key,
  timeStamp: Duration.zero,
);

/// A back handler that records [name] and pops itself, as the real closers
/// do.
bool Function() _popper(
  FlappySpikesGame game,
  String name,
  List<String> log,
) {
  late final bool Function() self;
  self = () {
    log.add(name);
    game.popBack(self);
    return true;
  };
  return self;
}

/// Boots a home-screen game with a spy, then runs [verify].
void _backTest(
  String name, {
  Map<String, Object> prefs = const {},
  Monetization Function()? monetization,
  required Future<void> Function(
    FlappySpikesGame game,
    AnalyticsSpy spy,
    WidgetTester tester,
  )
  verify,
}) {
  final spy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => createTestGame(prefs, null, spy, monetization?.call()),
  ).testGameWidget(
    name,
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) => verify(game, spy, tester),
  );
}
