import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/skin_catalog.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/monetization.dart';
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

/// Boots a home-screen game with [prefs], a spy and fake ads, then runs
/// [verify].
void homeTest(
  String name, {
  Map<String, Object> prefs = const {},
  double height = 568,
  FakeAdMode adMode = FakeAdMode.succeed,
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
  final ads = FakeRewardedAds()..mode = adMode;
  FlameTester<FlappySpikesGame>(
    () => createTestGame(prefs, height, spy, Monetization(ads: ads)),
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
        }
        await pressAndBack(() => game.homeScreen!.leaderboard.onPressed());
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

  group('powerup slot (PRD-1 §3.6)', () {
    homeTest(
      'ad completed -> armed (check, not tappable) -> consumed on START',
      verify: (game, spy, ads, tester) async {
        final offered = game.menu.slot.offered;
        expect(offered, isNot(Powerup.none));
        final slot = game.homeScreen!.slotButton;
        expect(slot.shown, offered);
        expect(slot.armed, isFalse);

        await game.tapPowerupSlot();
        game.update(0);
        expect(ads.placements, [AdPlacement.homeSlot]);
        expect(game.menu.slot.armed, offered);
        expect(spy.last('ad_rewarded_shown'), {'placement': 'home_slot'});
        expect(slot.armed, isTrue);
        expect(slot.labelText, PowerupSlotButton.labelFor(offered));
        expect(slot.tappable, isFalse, reason: 'armed slot is not tappable');

        // Tapping again does nothing (no second ad).
        await game.tapPowerupSlot();
        expect(ads.shown, 1);

        game.onScreenTap(); // START
        expect(game.state, GameState.playing);
        expect(game.menu.slot.armed, Powerup.none);
        expect(
          spy.names,
          contains(offered == Powerup.bigHoops ? 'big_hoops_used' : 'shield_armed'),
        );
      },
    );

    homeTest(
      'No-ads owners arm without an ad; no video icon',
      prefs: const {'noAds': true},
      verify: (game, spy, ads, tester) async {
        await game.tapPowerupSlot();
        expect(ads.shown, 0);
        expect(game.menu.slot.armed, game.menu.slot.offered);
      },
    );

    homeTest(
      'ad unavailable: dimmed slot, toast, nothing armed',
      adMode: FakeAdMode.unavailable,
      verify: (game, spy, ads, tester) async {
        game.update(0);
        final slot = game.homeScreen!.slotButton;
        expect(slot.unavailable, isTrue);
        expect(slot.dimmed, isTrue);
        expect(slot.tappable, isTrue, reason: 'tap -> toast');
        await game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.menu.slot.armed, Powerup.none);
        final toast = game.world.children.query<ServiceMessage>().single;
        expect(toast.message, 'No video available right now');
        expect(toast.position, Config.homeToastPositionFor(game.viewHeight));
      },
    );

    homeTest(
      'ad failed: toast, nothing armed',
      adMode: FakeAdMode.fail,
      verify: (game, spy, ads, tester) async {
        await game.tapPowerupSlot();
        await flushAndMount(game);
        expect(game.menu.slot.armed, Powerup.none);
        expect(game.world.children.query<ServiceMessage>(), hasLength(1));
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
      },
    );

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

  group('skins', () {
    homeTest(
      'equipped skin is drawn by the run bird and the home bird',
      prefs: const {
        'ownedSkins': ['pink', 'blue'],
        'equippedSkin': 'blue',
      },
      verify: (game, spy, ads, tester) async {
        final blue = skinById('blue')!;
        final bird = game.world.children.query<Bird>().single;
        expect(bird.skin.id, 'blue');
        expect(game.homeScreen!.bird.sprites.skin.id, 'blue');
        // Menus: identity colour.
        game.update(0);
        expect(bird.skinSprite.tint, blue.mockColor);
        expect(game.homeScreen!.bird.skinSprite.tint, blue.mockColor);

        // Equipping another skin swaps both in place.
        await game.menu.skins.equip('pink');
        await flushAndMount(game);
        game.update(0);
        await flushAndMount(game);
        expect(bird.skin.id, 'pink');
        expect(game.homeScreen!.bird.sprites.skin.id, 'pink');
      },
    );

    homeTest(
      'run tint: identity at stage 0, lerp 0.35 toward the stage from 5',
      prefs: const {
        'ownedSkins': ['pink', 'blue'],
        'equippedSkin': 'blue',
      },
      verify: (game, spy, ads, tester) async {
        final blue = skinById('blue')!;
        game.onScreenTap();
        final bird = game.world.children.query<Bird>().single;
        game.update(1 / 60);
        expect(bird.skinSprite.tint, blue.mockColor);
        game.score = 4;
        // Score 5 -> stage 5 crossfade.
        game.onScoreSensor(PipePair(gapBottomY: 351));
        game.update(0.25); // halfway through the 0.5 s crossfade
        expect(game.skinBlend, closeTo(Config.skinStageBlend / 2, 1e-9));
        game.update(0.5);
        expect(game.skinBlend, Config.skinStageBlend);
        game.update(0);
        expect(
          bird.skinSprite.tint,
          Color.lerp(blue.mockColor, kPalettes[5]!.foreground, 0.35),
        );
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
      'Skins stub toasts "Coming soon"; invite logs',
      verify: (game, spy, ads, tester) async {
        game.openSkins();
        game.invite();
        expect(spy.names, contains('invite_tap'));
        expect(spy.names, contains('skins_open'));
        await flushAndMount(game);
        final toast = game.world.children.query<ServiceMessage>().single;
        expect(toast.message, 'Coming soon');
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
        expect(tile.label.text, 'AD-FREE');
        game.openNoAdsPopup('home_tile');
        expect(spy.names, isNot(contains('noads_popup_shown')));
      },
    );

    homeTest(
      'NEW badge on Skins only when a skin is affordable and unseen',
      prefs: const {'coins': 99},
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
}
