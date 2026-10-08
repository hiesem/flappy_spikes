import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/config/feather_config.dart';
import 'package:flappy_spikes/run/config/puzzle_config.dart';
import 'package:flappy_spikes/run/config/capsule_config.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/effects/fetch_flight.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/items/feathers.dart';
import 'package:flappy_spikes/run/pickups/feather_pickup.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// PRD-2 §3.15 / §5.14 golden feathers in the run: banked at the touch
/// (persistent 0–3), the fetch into the feather tray, the 3rd feather's
/// set-complete + BONUS UNLOCKED!, once per run, no effect on score /
/// coins / streak, and the set carried across runs into the bonus screen.
void main() {
  group('§5.14 knobs', () {
    test('§5.14 feather art, idle and tray numbers', () {
      expect(FeatherConfig.vane.toARGB32(), 0xFFFFB529);
      expect(FeatherConfig.vaneRight.toARGB32(), 0xFFF09A0A);
      expect(FeatherConfig.quill.toARGB32(), 0xFFEC008C);
      expect(FeatherConfig.pickupTilt, closeTo(20 * 3.14159 / 180, .01));
      expect(FeatherConfig.bob, 4);
      expect(FeatherConfig.bobHz, .6);
      expect(FeatherConfig.pulse, .06);
      expect(FeatherConfig.sway, closeTo(13 * 3.14159 / 180, .01));
      expect(FeatherConfig.swayHz, .7);
      expect(FeatherConfig.drift, 3);
      expect(FeatherConfig.twinkleEvery, .28);
      expect(FeatherConfig.twinkleRadius, 24);
      expect(FeatherConfig.trayWidth, 132);
      expect(FeatherConfig.trayHeight, 48);
      expect(FeatherConfig.slotSize, 36);
      expect(FeatherTrayItem.slotX(0), -42);
      expect(FeatherTrayItem.slotX(2), 42);
      expect(FeatherConfig.slotScale, .82);
      expect(FeatherConfig.slotTilt, closeTo(26 * 3.14159 / 180, .01));
      expect(FeatherConfig.landAt, closeTo(.76, 1e-9));
      expect(FeatherConfig.fadeAt, 2.15);
      expect(FeatherConfig.fadeAtComplete, 3.4);
      expect(FeatherConfig.confetti, 26);
      expect(FeatherConfig.completeRingTo, 90);
      expect(FeatherConfig.stickerText, 'BONUS UNLOCKED!');
      expect(PickupRadii.feather, 18);
    });

    test('§5.14 fetch: swell ×1.4 from the pickup, land at 0.82 / 26°', () {
      final f = FetchFlight(
        from: const Offset(84, 400),
        to: const Offset(118, 288),
        art: (c, s, r) {},
      );
      expect(f.at(0).$2, closeTo(FeatherConfig.pickupScale, 1e-9));
      expect(f.at(.14).$2, closeTo(1.05 * 1.4, 1e-3));
      final end = f.at(FetchSpec.feather.total);
      expect(end.$2, closeTo(.82, 1e-9));
      expect(end.$3, closeTo(.45, 1e-9));
    });

    test('§3.15 / §3.16 the collect slot clears the banner band and the '
        'timer pill (call: y 288)', () {
      const trayTop = CollectConfig.slotY - FeatherConfig.trayHeight / 2;
      const pillTop = CollectConfig.slotY - PuzzleConfig.pillHeight / 2;
      // Banner band: y 190, ≈ 46 pt (+ 13 pt subtitle line) tall.
      expect(pillTop, greaterThan(PartsConfig.bannerTop + 62));
      expect(trayTop, greaterThan(pillTop));
      expect(CapsuleConfig.pillY + 11, lessThan(PartsConfig.bannerTop));
    });
  });

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    double height = 711,
    int seed = 5,
  }) => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: prefs,
      worldHeight: height,
      seed: seed,
      services: AnalyticsSpy(),
    ),
    gameSize: Vector2(320, height),
  );

  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  tester().testGameWidget(
    '§3.15 a touched feather is banked at once (persistent), flies into '
    'the tray; sounds, analytics, rumble, met',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final sfx = sfxLog(g);
      final run = await startRun(
        g,
        startHoopIndex: ElementId.feather.firstPossible!,
        force: [ElementId.feather],
      );
      final p = await collectPickup(g, ElementId.feather, reforce: false);
      expect(p, isA<FeatherPickup>());
      expect(run.state.featherSpawned, isTrue);
      expect(g.storage.feathers, 1);
      await flushAndMount(g);
      expect((await SharedPreferences.getInstance()).getInt('feathers'), 1);
      expect(sfx, contains('colFeatherGet'));
      expect(rumbleLog(g), contains(RumbleKind.knock));
      final spy = g.services as AnalyticsSpy;
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'feather_collected').single.$2,
        {'count': 1},
      );
      expect(g.storage.metElements, contains(ElementId.feather.storageId));
      final layer = CollectLayer.of(run)!;
      final item = layer.slot.current;
      expect(item, isA<FeatherTrayItem>());
      expect((item! as FeatherTrayItem).count, 1);
      expect(item.fadeAt, FeatherConfig.fadeAt);
      expect(layer.slot.position, Vector2(160, CollectConfig.slotY));
      expect(layer.children.whereType<FetchFlight>(), hasLength(1));
      expect(sfx, isNot(contains('colFeatherSlot1')));
      await stepSeconds(g, .9);
      expect(sfx, contains('colFeatherSlot1'));
      expect(layer.children.whereType<FetchFlight>(), isEmpty);
      await stepSeconds(g, 1.6);
      expect(layer.slot.current, isNull, reason: 'faded out ≈ 2.45 s');
    },
  );

  tester(prefs: {'feathers': 2}).testGameWidget(
    '§3.15 the 3rd feather: set complete, BONUS UNLOCKED!, tray holds 3.4 s',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final sfx = sfxLog(g);
      final run = await startRun(g);
      run.events.emit(const PickupCollected(ElementId.feather, null));
      expect(g.storage.feathers, 3);
      final layer = CollectLayer.of(run)!;
      await flushAndMount(g);
      final item = layer.slot.current! as FeatherTrayItem;
      expect(item.complete, isTrue);
      expect(item.fadeAt, FeatherConfig.fadeAtComplete);
      await stepSeconds(g, 1.3);
      expect(sfx, contains('colFeatherSlot3'));
      expect(item.doneAt, isNotNull);
      final sticker = layer.children.whereType<GoldSticker>().single;
      expect(sticker.text, 'BONUS UNLOCKED!');
      await stepSeconds(g, 2.6);
      expect(layer.slot.current, isNull);
      expect(layer.children.whereType<GoldSticker>(), isEmpty);
    },
  );

  tester(prefs: {'feathers': 3}).testGameWidget(
    '§3.15 holding 3 feathers: a debug feather keeps the count at 3',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      final run = await startRun(g);
      run.events.emit(const PickupCollected(ElementId.feather, null));
      expect(g.storage.feathers, 3);
    },
  );

  tester().testGameWidget(
    '§3.15 feathers do not touch score, coins, streak',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      final run = await startRun(g);
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      final s = run.state;
      final before = (s.score, s.coinsThisRun, s.streak, g.menu.wallet.balance);
      run.events.emit(const PickupCollected(ElementId.feather, null));
      expect(
        (s.score, s.coinsThisRun, s.streak, g.menu.wallet.balance),
        before,
      );
      expect(g.storage.feathers, 1);
    },
  );

  for (final h in [568.0, 711.0]) {
    tester(height: h, seed: 11).testGameWidget(
      '§3.15 / §3.0.3 one feather per run (gap 3–12, also across a '
      'revive) while < 3 held '
      '(${h.round()} pt)',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        g.runDebug.god = true;
        final run = await startRun(g);
        final at = run.director.featherAt;
        expect(at, inInclusiveRange(3, 12));
        var spawned = 0;
        run.events.on<ElementSpawned>((e) {
          if (e.element == ElementId.feather) spawned++;
        });
        await flyRun(g, untilHoops: 14, maxSeconds: 90);
        expect(spawned, 1);
        // A revive keeps the run's director: no second feather after it.
        run.director.onRevive();
        await flyRun(g, untilHoops: 28, maxSeconds: 90);
        expect(run.state.hoopsPassed, greaterThanOrEqualTo(20));
        expect(spawned, 1);
        expect(run.state.featherSpawned, isTrue);
      },
    );
  }

  tester(prefs: {'feathers': 3}, seed: 11).testGameWidget(
    '§3.15 no feather spawns while 3 are held',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final run = await startRun(g);
      var spawned = 0;
      run.events.on<ElementSpawned>((e) {
        if (e.element == ElementId.feather) spawned++;
      });
      await flyRun(g, untilHoops: 20, maxSeconds: 90);
      expect(spawned, 0);
      expect(run.state.featherSpawned, isFalse);
    },
  );

  tester().testGameWidget(
    '§3.15 a death keeps the banked feather; the set carries across runs '
    'and opens the bonus screen after the 3rd',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      for (var n = 1; n <= 3; n++) {
        final run = await startRun(g);
        run.events.emit(const PickupCollected(ElementId.feather, null));
        expect(run.features.whereType<FeathersFeature>().single.collected, 1);
        killRun(g);
        await flushAndMount(g);
        if (n < 3) {
          expect(g.state, GameState.results);
          expect(g.storage.feathers, n);
          g.goHome();
          await stepSeconds(g, 1);
        }
      }
      expect(g.state, GameState.bonus);
      expect(g.bonusScreen, isNotNull);
      expect(g.storage.feathers, 0);
    },
  );
}
