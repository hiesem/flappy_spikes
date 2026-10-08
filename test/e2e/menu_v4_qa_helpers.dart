import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../shop_flow_test.dart' show EventSpy;

class V4Clock {
  DateTime now = DateTime(2026, 10, 7, 8);
  DateTime call() => now;
  int get day => DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(1970)).inDays;
}

class V4Rig {
  V4Rig({IapService? iap, FakeRewardedAds? ads})
    : iap = iap ?? FakeIapService(),
      ads = ads ?? FakeRewardedAds();

  final clock = V4Clock();
  final events = EventSpy();
  final IapService iap;
  final FakeRewardedAds ads;

  Map<String, Object> get eligible => {
    'installDay': clock.day - 1,
    'firstSessionDone': true,
  };

  FlappySpikesGame newGame(double height) => FlappySpikesGame(
    worldHeight: height,
    services: events,
    monetization: Monetization(iap: iap, ads: ads),
    clock: clock.call,
    soundEnabled: false,
  )..runSeed = 7;
}

void v4Journey(
  String name,
  Future<void> Function(FlappySpikesGame, V4Rig, WidgetTester) verify, {
  Map<String, Object> Function(V4Rig)? prefs,
  bool eligible = false,
  double height = 711,
  IapService? iap,
  FakeRewardedAds? ads,
}) {
  final rig = V4Rig(iap: iap, ads: ads);
  FlameTester<FlappySpikesGame>(
    () {
      SharedPreferences.setMockInitialValues(
        prefs?.call(rig) ?? (eligible ? rig.eligible : {}),
      );
      return rig.newGame(height);
    },
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
      // Stream deliveries must use the widget test's zone.
      game.purchases
        ..dispose()
        ..start();
      await rig.iap.initialize();
      await v4Settle(game, tester);
      game.coinFlyRandom = math.Random(70);
      try {
        await verify(game, rig, tester);
      } finally {
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}

Future<void> v4Settle(FlappySpikesGame game, WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    for (var n = 0; n < 20; n++) {
      await Future<void>.value();
    }
    await tester.binding.delayed(Duration.zero);
  }
  await flushAndMount(game);
}

Future<void> v4Tap(
  PositionComponent component,
  FlappySpikesGame game,
  WidgetTester tester,
) async {
  final p = component.absolutePositionOfAnchor(Anchor.center);
  await tester.tapAt(ui.Offset(p.x, p.y));
  await v4Settle(game, tester);
}

Future<void> v4Background(
  FlappySpikesGame game,
  V4Rig rig,
  WidgetTester tester,
  Duration away,
) async {
  game.lifecycleStateChange(AppLifecycleState.inactive);
  game.lifecycleStateChange(AppLifecycleState.hidden);
  game.lifecycleStateChange(AppLifecycleState.paused);
  rig.clock.now = rig.clock.now.add(away);
  game.lifecycleStateChange(AppLifecycleState.hidden);
  game.lifecycleStateChange(AppLifecycleState.inactive);
  game.lifecycleStateChange(AppLifecycleState.resumed);
  await v4Settle(game, tester);
}

Future<FlappySpikesGame> v4Restart(
  FlappySpikesGame game,
  V4Rig rig,
  WidgetTester tester,
) async {
  game.purchases.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
  final next = rig.newGame(game.viewHeight);
  await tester.runAsync(() async {
    await tester.pumpWidget(GameWidget(game: next));
    await tester.pump();
    await next.ready();
    await preloadImages(next);
    await flushAndMount(next);
  });
  next.purchases
    ..dispose()
    ..start();
  await v4Settle(next, tester);
  return next;
}

// Drive START -> the game's death handler -> replay/home. Inject the final
// score to reach exact policy boundaries; physics is covered by the existing
// acceptance bot. Do not write any policy, wallet, run-count or best state.
Future<void> v4FinishRun(
  FlappySpikesGame game,
  WidgetTester tester,
  int score,
) async {
  await game.startRun();
  expect(game.state, GameState.playing);
  game.score = score;
  killRun(game);
  await v4Settle(game, tester);
  game.goHome();
  stepGame(game, .3);
  await v4Settle(game, tester);
  expect(game.state, GameState.start);
}

Future<void> v4Videos(
  FlappySpikesGame game,
  WidgetTester tester,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    await game.showRewardedAd(AdPlacement.shopFreeCoins);
    await v4Settle(game, tester);
  }
}

void v4Escape(FlappySpikesGame game) => game.onKeyEvent(
  KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.escape,
    logicalKey: LogicalKeyboardKey.escape,
    timeStamp: Duration.zero,
  ),
  {},
);

int v4ModalCount(FlappySpikesGame game) => [
  game.noAdsPopup,
  game.levelUpPopup,
  game.purchaseResultPopup,
  game.noAdsCelebration,
].where((popup) => popup != null).length;

int v4EffectiveMs(V4Rig rig, FlappySpikesGame game) =>
    rig.clock.now.millisecondsSinceEpoch +
    game.storage.debugDayOffset * Duration.millisecondsPerDay;

Duration get v4SessionGap => Config.sessionGap;
