import 'dart:async';
import 'dart:ui' show FilterQuality;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/skins/catalog.dart' show kNewInUpdate;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Records analytics events instead of sending them.
class EventSpy extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  List<String> get names => events.map((e) => e.$1).toList();

  Map<String, Object>? last(String name) =>
      events.lastWhere((e) => e.$1 == name).$2;

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

/// Lets fire-and-forget persistence writes land.
Future<void> flushPrefs() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
  }
}

KeyDownEvent keyDown(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: key,
  timeStamp: Duration.zero,
);

/// The analytics event a consumed powerup logs on run start.
String usedEvent(Powerup p) =>
    p == Powerup.bigHoops ? 'big_hoops_used' : 'shield_armed';

/// Boots a home-screen game with [prefs], a spy and fake ads, then runs
/// [verify].
void homeTest(
  String name, {
  Map<String, Object> prefs = const {},
  double height = 568,
  FakeAdMode adMode = FakeAdMode.succeed,
  FakeRewardedAds? fakeAds,
  bool fakeAdOverlay = false,
  bool exactSurface = false,
  required Future<void> Function(
    FlappySpikesGame game,
    EventSpy spy,
    FakeRewardedAds ads,
    WidgetTester tester,
  )
  verify,
}) {
  final spy = EventSpy();
  final ads = (fakeAds ?? FakeRewardedAds())..mode = adMode;
  FlameTester<FlappySpikesGame>(
    () => createTestGame(
      prefs,
      height,
      spy,
      Monetization(ads: ads)..showFakeAdOverlay = fakeAdOverlay,
    ),
    pumpWidget: exactSurface
        ? (gameWidget, tester) async {
            tester.view
              ..physicalSize = Size(320, height)
              ..devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(gameWidget);
          }
        : null,
  ).testGameWidget(
    name,
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) => verify(game, spy, ads, tester),
  );
}

void main() {
  group('START only (PRD-1 §4.2)', () {
    homeTest(
      'a real tap on an empty home area does not start a run',
      exactSurface: true,
      verify: (game, spy, ads, tester) async {
        // Empty spots: right of START, and between the pill and the title.
        for (final p in [const Offset(300, 240), const Offset(160, 110)]) {
          await tester.tapAt(p);
          await tester.pump(const Duration(milliseconds: 100));
          expect(game.state, GameState.start, reason: 'tap at $p');
        }
        // The TapCatcher path directly.
        game.onPlayfieldTap();
        expect(game.state, GameState.start);
        expect(game.homeScreen, isNotNull);
      },
    );

    homeTest(
      'the START button starts the run (real tap) and flaps at once',
      exactSurface: true,
      verify: (game, spy, ads, tester) async {
        final start = Config.homeStartRectFor(game.viewHeight);
        await tester.tapAt(start.center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(game.state, GameState.playing);
        final bird = game.world.children.query<Bird>().single;
        // Flapped on START (the pump then ran 0.1 s of gravity).
        expect(bird.body.linearVelocity.y, lessThan(-200));
        expect(spy.names, contains('game_start'));

        // A tap where START was now flaps (the fading home lets it through).
        stepGame(game, 0.3);
        await tester.tapAt(start.center);
        await tester.pump(const Duration(milliseconds: 100));
        // (The pump advanced 0.1 s of gravity after the flap.)
        expect(bird.body.linearVelocity.y, lessThan(-200),
            reason: 'the fading START button must not eat the flap');

        // Home fades out and is removed; the run's bird fades in.
        stepGame(game, 0.6, flapBelow: 320);
        await flushAndMount(game);
        expect(game.world.children.query<HomeScreen>(), isEmpty);
        expect(bird.spriteOpacity, 1);
      },
    );

    homeTest(
      'home buttons do not start a run; onScreenTap (tests/keyboard) does',
      verify: (game, spy, ads, tester) async {
        // Shop / No-ads open screens over home: back out of each (a fresh
        // home screen comes back after the Shop).
        Future<void> pressAndBack(void Function() press) async {
          press();
          await flushAndMount(game);
          expect(game.state, GameState.start);
          while (game.handleBack()) {}
          await flushAndMount(game);
        }

        for (var i = 0; i < 4; i++) {
          await pressAndBack(() => game.homeScreen!.tiles[i].onPressed());
          // The No-ads tile starts a store purchase now (still no run):
          // let the fake store's round-trip finish so no timer outlives
          // the test.
          if (i == 3) await tester.pump(const Duration(milliseconds: 1));
        }
        await pressAndBack(() => game.homeScreen!.trophyButton.onPressed());
        await pressAndBack(() => game.homeScreen!.coinPill.onPressed());
        expect(game.state, GameState.start);
        expect(game.menuScene, MenuScene.home);
        game.onScreenTap();
        expect(game.state, GameState.playing);
      },
    );

    homeTest(
      'beforeRunStart is awaited between START and the run',
      verify: (game, spy, ads, tester) async {
        final gate = Completer<void>();
        var calls = 0;
        game.beforeRunStart = () {
          calls++;
          return gate.future;
        };
        unawaited(game.startRun());
        unawaited(game.startRun()); // double press while waiting: ignored
        expect(calls, 1);
        expect(game.state, GameState.start);
        gate.complete();
        await flushAndMount(game);
        expect(game.state, GameState.playing);
      },
    );
  });

  group('powerup slot: watch ad -> play with it (2.0 deviation)', () {
    /// No check glyph anywhere in the slot (there is no armed state).
    void expectNoCheck(FlappySpikesGame game) {
      final check = game.images.fromCache('menu/check.png');
      final slot = game.homeScreen!.slotButton;
      expect(
        slot.descendants().whereType<MenuIcon>().where(
          (icon) => identical(icon.sprite?.image, check),
        ),
        isEmpty,
      );
    }

    homeTest(
      'ad completed -> the run starts at once with the powerup consumed',
      verify: (game, spy, ads, tester) async {
        final offered = game.menu.slot.offered;
        expect(offered, isNot(Powerup.none));
        final slot = game.homeScreen!.slotButton;
        expect(slot.shown, offered);
        expect(slot.showsVideo, isTrue, reason: 'the ad icon is always shown');
        expect(slot.labelText, PowerupSlotButton.labelFor(offered));
        expectNoCheck(game);

        await game.tapPowerupSlot();
        expect(ads.placements, [AdPlacement.homeSlot]);
        expect(spy.last('ad_rewarded_shown'), {'placement': 'home_slot'});
        expect(game.state, GameState.playing);
        expect(spy.names, contains(usedEvent(offered)));
        expect(spy.names.where((n) => n == 'game_start'), hasLength(1));
        expect(game.menu.slot.armed, Powerup.none, reason: 'consumed');
        await flushPrefs();
        expect(game.storage.armedPowerup, 'none');
      },
    );

    homeTest(
      'plain START never carries a powerup (no ad either)',
      verify: (game, spy, ads, tester) async {
        game.onScreenTap();
        expect(game.state, GameState.playing);
        expect(ads.shown, 0);
        expect(spy.names, isNot(contains('big_hoops_used')));
        expect(spy.names, isNot(contains('shield_armed')));
      },
    );

    homeTest(
      'a stale armed powerup from storage is cleared at startup',
      prefs: const {'armedPowerup': 'shield'},
      verify: (game, spy, ads, tester) async {
        expect(game.menu.slot.armed, Powerup.none);
        game.onScreenTap();
        expect(game.state, GameState.playing);
        expect(spy.names, isNot(contains('shield_armed')));
      },
    );

    homeTest(
      'No-ads owners start with the powerup without an ad; no video icon',
      prefs: const {'noAds': true},
      verify: (game, spy, ads, tester) async {
        game.update(0);
        expect(game.homeScreen!.slotButton.showsVideo, isFalse);
        expectNoCheck(game);
        final offered = game.menu.slot.offered;
        await game.tapPowerupSlot();
        expect(ads.shown, 0);
        expect(game.state, GameState.playing);
        expect(spy.names, contains(usedEvent(offered)));
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
      },
    );

    homeTest(
      'ad unavailable: dimmed slot, toast, stays home, nothing armed',
      adMode: FakeAdMode.unavailable,
      verify: (game, spy, ads, tester) async {
        game.update(0);
        final slot = game.homeScreen!.slotButton;
        expect(slot.unavailable, isTrue);
        expect(slot.dimmed, isTrue);
        expect(slot.tappable, isTrue, reason: 'tap -> toast');
        await game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.menu.slot.armed, Powerup.none);
        final toast = game.world.children.query<ServiceMessage>().single;
        expect(toast.message, 'No video available right now');
        expect(toast.position, Config.homeToastPositionFor(game.viewHeight));
      },
    );

    homeTest(
      'ad failed: toast, stays home, nothing armed',
      adMode: FakeAdMode.fail,
      verify: (game, spy, ads, tester) async {
        await game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.homeScreen, isNotNull);
        expect(game.menu.slot.armed, Powerup.none);
        expect(game.world.children.query<ServiceMessage>(), hasLength(1));
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
        expect(spy.names, isNot(contains('game_start')));
        // The home screen works again afterwards.
        game.onScreenTap();
        expect(game.state, GameState.playing);
      },
    );

    final gated = _GatedAds();
    homeTest(
      'no input while the ad plays: no double start, keys ignored',
      fakeAds: gated,
      verify: (game, spy, ads, tester) async {
        gated.gate = Completer<AdResult>();
        final tap = game.tapPowerupSlot();
        await flushAndMount(game);
        expect(gated.shown, 1);

        game.onScreenTap();
        await game.startRun();
        game.onKeyEvent(keyDown(LogicalKeyboardKey.space), {});
        game.onKeyEvent(keyDown(LogicalKeyboardKey.enter), {});
        await game.tapPowerupSlot();
        game.openSettings();
        game.openShop();
        game.openSkins();
        game.openNoAdsPopup();
        expect(game.state, GameState.start);
        expect(game.menuScene, MenuScene.home);
        expect(game.noAdsPopup, isNull);
        expect(gated.shown, 1, reason: 'no second ad');

        gated.gate!.complete(AdResult.completed);
        await tap;
        await flushAndMount(game);
        expect(game.state, GameState.playing);
        expect(spy.names.where((n) => n == 'game_start'), hasLength(1));
        expect(spy.names, contains(usedEvent(game.menu.slot.offered)));
      },
    );
  });

  group('fake ad overlay (Linux / desktop)', () {
    /// Steps menu time (no run yet) in small increments.
    // 60 fps frames: one update never exceeds Config.maxFrameStep, which
    // would slow the game clock (and the ad countdown) down.
    void advance(FlappySpikesGame game, double seconds) =>
        stepGame(game, seconds);

    homeTest(
      'off by default: the test fake completes without an overlay',
      verify: (game, spy, ads, tester) async {
        expect(game.monetization.showFakeAdOverlay, isFalse);
        await game.tapPowerupSlot();
        expect(game.fakeAdOverlay, isNull);
        expect(game.state, GameState.playing);
      },
    );

    homeTest(
      'TEST AD countdown, then reward -> run starts with the powerup',
      fakeAdOverlay: true,
      verify: (game, spy, ads, tester) async {
        final offered = game.menu.slot.offered;
        final tap = game.tapPowerupSlot();
        await flushAndMount(game);
        final overlay = game.fakeAdOverlay!;
        expect(overlay.isMounted, isTrue);
        expect(overlay.placement, AdPlacement.homeSlot);
        expect(overlay.messageText, '3');
        expect(game.state, GameState.start);

        // Space does not start a run under the ad.
        game.onKeyEvent(keyDown(LogicalKeyboardKey.space), {});
        expect(game.state, GameState.start);

        advance(game, 1.5);
        expect(overlay.messageText, '2');
        advance(game, Config.fakeAdCountdown - 1.5 + 0.05);
        expect(overlay.granted, isTrue);
        expect(overlay.messageText, 'REWARD GRANTED');
        expect(game.state, GameState.start);

        advance(game, Config.fakeAdResultHold + 0.05);
        await tap;
        await flushAndMount(game);
        expect(game.state, GameState.playing);
        expect(game.fakeAdOverlay, isNull);
        expect(spy.last('ad_rewarded_shown'), {'placement': 'home_slot'});
        expect(spy.names, contains(usedEvent(offered)));

        advance(game, Config.popupFadeDuration + 0.05);
        await flushAndMount(game);
        expect(overlay.isMounted, isFalse, reason: 'faded out and removed');
      },
    );

    homeTest(
      'Esc during the countdown closes it early: no reward, stays home',
      fakeAdOverlay: true,
      verify: (game, spy, ads, tester) async {
        final tap = game.tapPowerupSlot();
        await flushAndMount(game);
        advance(game, 1);
        expect(
          game.onKeyEvent(
            KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.escape,
              logicalKey: LogicalKeyboardKey.escape,
              timeStamp: Duration.zero,
            ),
            {},
          ),
          KeyEventResult.handled,
        );
        await tap;
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.fakeAdOverlay, isNull);
        expect(game.menu.slot.armed, Powerup.none);
        // The test ad was on screen (S1-07): "shown" counts it even though
        // the reward was skipped.
        expect(spy.last('ad_rewarded_shown'), {'placement': 'home_slot'});
        expect(spy.names, isNot(contains('ad_reward_earned')));
        expect(
          game.world.children.query<ServiceMessage>().single.message,
          'No video available right now',
        );
        // Home is interactive again.
        game.onScreenTap();
        expect(game.state, GameState.playing);
      },
    );

    homeTest(
      'fail mode: "Ad failed to load" briefly, then toast, stays home',
      fakeAdOverlay: true,
      adMode: FakeAdMode.fail,
      verify: (game, spy, ads, tester) async {
        final tap = game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.fakeAdOverlay!.messageText, 'Ad failed to load');
        advance(game, Config.fakeAdFailHold + 0.05);
        await tap;
        await flushAndMount(game);
        expect(game.fakeAdOverlay, isNull);
        expect(game.state, GameState.start);
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
      },
    );

    homeTest(
      'unavailable mode: no overlay, just the toast',
      fakeAdOverlay: true,
      adMode: FakeAdMode.unavailable,
      verify: (game, spy, ads, tester) async {
        await game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.fakeAdOverlay, isNull);
        expect(game.state, GameState.start);
        expect(
          game.world.children.query<ServiceMessage>().single.message,
          'No video available right now',
        );
      },
    );
  });

  group('powerup slot rolls (PRD-1 §3.6)', () {
    homeTest(
      'one roll per arrival: launch (no extra roll), goHome re-rolls, '
      'settings round trip does not',
      verify: (game, spy, ads, tester) async {
        expect(game.storage.slotHistory, hasLength(1),
            reason: 'the launch arrival rolled once (PowerupSlot ctor)');
        expect(spy.names.where((n) => n == 'home_slot_shown'), hasLength(1));

        game.openSettings();
        await flushAndMount(game);
        game.closeSettings();
        await flushAndMount(game);
        expect(game.storage.slotHistory, hasLength(1));

        game.menu.slot.debugForce = Powerup.shield;
        game.onScreenTap();
        game.onBirdHit();
        await flushAndMount(game);
        game.goHome();
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.storage.slotHistory, hasLength(2));
        expect(game.menu.slot.offered, Powerup.shield);
        expect(spy.last('home_slot_shown'), {'item': 'shield'});
        expect(game.homeScreen!.slotButton.shown, Powerup.shield);
      },
    );
  });

  group('coins + game over', () {
    homeTest(
      'coins credited at game over = score; panel shows "+N"',
      prefs: const {'coins': 7},
      verify: (game, spy, ads, tester) async {
        game.onScreenTap();
        game.score = 13;
        game.onBirdHit();
        await flushPrefs();
        await flushAndMount(game);
        expect(game.menu.wallet.balance, 20);
        expect(spy.last('coins_earned'), {'amount': 13, 'source': 'play'});
        final panel = game.world.children.query<GameOverPanel>().single;
        expect(panel.coinsEarned, 13);
        final labels = panel.children.whereType<TextComponent>();
        expect(labels.map((l) => l.text), contains('+13'));
        final coin = labels.firstWhere((l) => l.text == '+13');
        expect(coin.position.y, Config.coinsEarnedPositionFor(284).y);
      },
    );

    homeTest(
      'score 0 credits nothing',
      verify: (game, spy, ads, tester) async {
        game.onScreenTap();
        game.onBirdHit();
        await flushPrefs();
        expect(game.menu.wallet.balance, 0);
        expect(spy.names, isNot(contains('coins_earned')));
      },
    );

    homeTest(
      'game-over action returns home at stage 0 with short menu strips',
      verify: (game, spy, ads, tester) async {
        final strips = game.world.children.query<SpikeStrip>();
        expect(strips.every((s) => s.visualInset == Config.menuSpikeInset),
            isTrue);
        game.onScreenTap();
        stepGame(game, 0.6, flapBelow: 320);
        expect(strips.every((s) => s.visualInset == 0), isTrue,
            reason: 'the strips slide to full height during a run');

        game.score = 4;
        game.onBirdHit();
        await flushAndMount(game);
        final panel = game.world.children.query<GameOverPanel>().single;
        expect(panel.canContinue, isFalse);
        stepGame(game, 1.0);
        expect(panel.canContinue, isTrue);
        // Space on game over = the panel's action (goHome).
        game.onKeyEvent(keyDown(LogicalKeyboardKey.space), {});
        await flushAndMount(game);
        expect(game.state, GameState.start);
        expect(game.homeScreen, isNotNull);
        expect(game.stageBackground, kPalettes[0]!.background);
        expect(game.foregroundColor, kPalettes[0]!.foreground);
        expect(strips.every((s) => s.visualInset == Config.menuSpikeInset),
            isTrue);
      },
    );
  });

  group('look (PRD-menu-v2)', () {
    homeTest(
      'equipped look is drawn by the run bird and the home bird',
      prefs: const {
        'ownedItems': ['bird:robin'],
        'equippedItem.bird': 'robin',
      },
      verify: (game, spy, ads, tester) async {
        final bird = game.world.children.query<Bird>().single;
        expect(bird.look.bird, 'robin');
        expect(game.homeScreen!.bird.look.bird, 'robin');
        // Menus: identity colours, no stage blend.
        game.update(0);
        expect(bird.lookComponent.blend, 0);
        expect(game.homeScreen!.bird.lookComponent.blend, 0);

        // Equipping another look swaps both in place, live.
        await game.menu.items.equip(SkinLayer.bird, 'classic');
        await flushAndMount(game);
        game.update(0);
        expect(bird.look.bird, 'classic');
        expect(game.homeScreen!.bird.look.bird, 'classic');
      },
    );

    homeTest(
      'run blend: 0 at stage 0, Config.skinStageBlend from stage 5',
      prefs: const {
        'ownedItems': ['bird:robin'],
        'equippedItem.bird': 'robin',
      },
      verify: (game, spy, ads, tester) async {
        game.onScreenTap();
        final bird = game.world.children.query<Bird>().single;
        game.update(1 / 60);
        expect(bird.lookComponent.blend, 0);
        game.score = 4;
        // Score 5 -> stage 5 crossfade.
        game.onScoreSensor(PipePair(gapBottomY: 351));
        // 60 fps frames (a single long update is clamped to maxFrameStep).
        stepGame(game, 0.25); // halfway through the 0.5 s crossfade
        expect(game.skinBlend, closeTo(Config.skinStageBlend / 2, 1e-9));
        stepGame(game, 0.5);
        expect(game.skinBlend, Config.skinStageBlend);
        game.update(0);
        // The bird draws the true colours mixed Config.skinStageBlend toward
        // the stage foreground (LookComponent applies the blend at draw
        // time; look_visual_test checks the rendered pixels).
        expect(bird.lookComponent.blend, Config.skinStageBlend);
        expect(bird.lookComponent.blendColor, kPalettes[5]!.foreground);
      },
    );
  });

  group('keyboard, back stack, debug panel', () {
    homeTest(
      'Space starts, Esc closes settings, D toggles the debug panel',
      verify: (game, spy, ads, tester) async {
        game.openSettings();
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.settings);
        // Space does nothing while settings is open.
        game.onKeyEvent(keyDown(LogicalKeyboardKey.space), {});
        expect(game.state, GameState.start);
        expect(
          game.onKeyEvent(keyDown(LogicalKeyboardKey.escape), {}),
          KeyEventResult.handled,
        );
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.world.children.query<SettingsPanel>().single.opacity,
            lessThan(1),
            reason: 'settings fading out');
        expect(
          game.onKeyEvent(keyDown(LogicalKeyboardKey.escape), {}),
          KeyEventResult.ignored,
          reason: 'nothing left to go back from',
        );

        game.onKeyEvent(keyDown(LogicalKeyboardKey.keyD), {});
        await flushAndMount(game);
        expect(game.debugPanel, isNotNull);
        game.onScreenTap();
        expect(game.state, GameState.start, reason: 'modal open');
        game.onKeyEvent(keyDown(LogicalKeyboardKey.escape), {});
        await flushAndMount(game);
        expect(game.debugPanel, isNull);

        game.onKeyEvent(keyDown(LogicalKeyboardKey.space), {});
        expect(game.state, GameState.playing);
      },
    );

    homeTest(
      'back stack: topmost handler wins, popBack removes it',
      verify: (game, spy, ads, tester) async {
        final calls = <String>[];
        bool a() {
          calls.add('a');
          return true;
        }

        bool b() {
          calls.add('b');
          return true;
        }

        game.pushBack(a);
        game.pushBack(b);
        expect(game.handleBack(), isTrue);
        game.popBack(b);
        expect(game.handleBack(), isTrue);
        game.popBack(a);
        expect(game.handleBack(), isFalse);
        expect(calls, ['b', 'a']);
      },
    );

    homeTest(
      'debug panel: +1000 coins, forced slot, fake ad mode',
      verify: (game, spy, ads, tester) async {
        game.openDebugPanel();
        await flushAndMount(game);
        final panel = game.world.children.query<DebugPanel>().single;
        Future<void> run(String prefix) async {
          final action = panel.actions.firstWhere(
            (a) => a.label().startsWith(prefix),
          );
          await action.run();
          await flushPrefs();
        }

        await run('+1000 coins');
        expect(game.menu.wallet.balance, 1000);
        expect(spy.last('coins_earned'), {'amount': 1000, 'source': 'debug'});
        await run('Slot: force SHIELD');
        expect(game.menu.slot.offered, Powerup.shield);
        await run('Slot: force BIG HOOPS');
        expect(game.menu.slot.offered, Powerup.bigHoops);
        await run('Ads:');
        expect(ads.mode, FakeAdMode.fail);
        await run('Next day');
        expect(game.storage.debugDayOffset, 1);
        await run('Reset menu state');
        expect(game.menu.wallet.balance, 0);
        await run('Close');
        await flushAndMount(game);
        expect(game.debugPanel, isNull);
      },
    );

    homeTest(
      'Skins tile opens the Skins screen; invite logs',
      verify: (game, spy, ads, tester) async {
        game.invite();
        expect(spy.names, contains('invite_tap'));
        game.homeScreen!.skinsTile.onPressed();
        await flushAndMount(game);
        expect(spy.names, contains('skins_open'));
        expect(game.menuScene, MenuScene.skins);
        expect(game.skinShop, isNotNull);
        expect(game.homeScreen, isNull);
        expect(game.state, GameState.start);
      },
    );

    homeTest(
      'No-ads owners: tile shows AD-FREE (dimmed); popup is not offered',
      prefs: const {'noAds': true},
      verify: (game, spy, ads, tester) async {
        final tile = game.homeScreen!.noAdsTile;
        expect(tile.owned, isTrue);
        expect(tile.dimmed, isTrue);
        // PO 2026-10-04: the check sits in the ICON slot (instead of the
        // crossed-AD icon), the label is exactly "AD-FREE" with no inline
        // check, and it fits inside the 70 pt tile.
        expect(tile.label.text, 'AD-FREE');
        expect(tile.showsCheck, isTrue);
        expect(
          tile.icon.sprite!.image,
          same(game.images.fromCache('menu/check.png')),
        );
        expect(tile.icon.paint.filterQuality, kMenuFilterQuality);
        expect(tile.icon.size, Vector2.all(Config.homeTileCheckSize));
        expect(tile.icon.x + tile.icon.width / 2, closeTo(tile.width / 2, 1e-9));
        expect(tile.icon.y + tile.icon.height, lessThan(tile.label.y));
        expect(tile.children.whereType<MenuIcon>(), hasLength(1));
        // (The label-fits check runs with the real font in
        // menu_chrome_test.dart; the test font here is monospace boxes.)
        // Same label line as the other tiles.
        expect(tile.label.y, game.homeScreen!.shopTile.label.y);
        // A tap still only toasts (PO 2026-10-05: no popup, no purchase).
        tile.onPressed();
        await flushAndMount(game);
        expect(
          game.world.children.query<ServiceMessage>().last.message,
          'Already ad-free',
        );
        expect(spy.names, isNot(contains('noads_popup_shown')));
        expect(spy.names, isNot(contains('noads_purchase_tapped')));
        game.openNoAdsPopup();
        expect(spy.names, isNot(contains('noads_popup_shown')));
      },
    );

    homeTest(
      'NEW badge on Skins only when an item is affordable and unseen '
      '(the 2.0 update items already seen)',
      prefs: {'coins': 149, 'seenItems': kNewInUpdate.toList()},
      verify: (game, spy, ads, tester) async {
        final tile = game.homeScreen!.skinsTile;
        expect(tile.tag, isNull);
        await game.menu.wallet.add(1, CoinSource.play);
        game.update(0);
        await flushAndMount(game);
        expect(tile.tag, 'NEW');
        expect(tile.tagComponent, isNotNull);
      },
    );
  });

  group('menu rendering (S1-09)', () {
    homeTest(
      'menu icons sample with mipmapped filtering, not nearest-neighbour',
      verify: (game, spy, ads, tester) async {
        final icons = game.homeScreen!.descendants().whereType<MenuIcon>();
        expect(icons, isNotEmpty);
        for (final icon in icons) {
          expect(icon.paint.filterQuality, kMenuFilterQuality);
        }
        expect(kMenuFilterQuality, isNot(FilterQuality.none));
      },
    );
  });
}

/// Fake ads whose [show] waits for [gate] (input-blocking tests).
class _GatedAds extends FakeRewardedAds {
  Completer<AdResult>? gate;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async {
    shown++;
    placements.add(placement);
    return gate!.future;
  }
}
