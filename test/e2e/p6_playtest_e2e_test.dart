import 'dart:ui' show Offset, Rect;

import 'package:firebase_core/firebase_core.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/piggy_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_badges.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/pickups/piggy_pickup.dart';
import 'package:flappy_spikes/services/firebase_versus_backend.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// Isolate the real App Check activation guard from Auth/network plugins.
/// Firebase deliberately remains uninitialized, like Home winning the race
/// against main.dart's fire-and-forget Firebase.initializeApp on the Pixel 8.
class _ActivationProbe extends FirebaseVersusBackend {
  final failures = <Object>[];
  int completedActivations = 0;

  @override
  Future<String> start() async {
    try {
      await FirebaseVersusBackend.activateAppCheck();
      completedActivations++;
      return 'activation-probe';
    } catch (error) {
      failures.add(error);
      rethrow;
    }
  }

  @override
  String get uid => 'activation-probe';

  @override
  Future<List<PoolEntry>> readPool(String id) async => const [];
}

class _UnavailableBackend extends FirebaseVersusBackend {
  @override
  Future<String> start() async => throw StateError('isolated auth failure');
}

void main() {
  group('S6-F01 App Check activation retry', () {
    final backend = _ActivationProbe();
    late FlappySpikesGame game;
    final service = FirebaseVersusService(
      storageOf: () => game.storage,
      backend: backend,
      identity: const GameCenterIdentity(), // empty stream; no native identity
    );

    FlameTester<FlappySpikesGame>(
      () => game = createRunTestGame(worldHeight: 711, versus: service),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'S6-F01 Home App Check failure must not mark activation successful',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        expect(Firebase.apps, isEmpty);
        // Wait for the actual Home prefetch started in _setupStartScene.
        await service.initialize();
        expect(
          backend.failures,
          contains(
            isA<FirebaseException>().having((e) => e.code, 'code', 'no-app'),
          ),
        );
        // A retry must attempt activation again. With Firebase still absent,
        // it must fail again, rather than silently report activation complete.
        await service.prefetch();
        expect(
          backend.completedActivations,
          0,
          reason:
              'A failed activation cannot latch the process-wide guard. '
              'On the phone this bypasses App Check before the real pool read.',
        );
        service.dispose();
      },
    );
  }, skip: 'S6-F01 open');

  group('S6-F02 nickname across cold starts', () {
    const original = 'SwiftKiwi482';
    late FlappySpikesGame game;
    final service = FirebaseVersusService(
      storageOf: () => game.storage,
      backend: _UnavailableBackend(),
      identity: const GameCenterIdentity(),
    );
    FlameTester<FlappySpikesGame>(
      () => game = createRunTestGame(
        prefs: {'versusNickname': original},
        worldHeight: 711,
        versus: service,
      ),
      gameSize: Vector2(320, 711),
      pumpWidget: (widget, tester) async {
        // Android can resume the GameWidget before async onLoad has read
        // storage. Exercise that actual lifecycle handler, then mount Home.
        game.lifecycleStateChange(AppLifecycleState.resumed);
        await service.initialize();
        await tester.pumpWidget(widget);
      },
    ).testGameWidget(
      'S6-F02 early resume must retain the nickname saved by the last launch',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('versusNickname'), original);
        expect(g.storage.versusNickname, original);
      },
    );
  }, skip: 'S6-F02 open');

  group('S6-F03 Piggy Bank banner collision', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'S6-F03 collecting a piggy must leave its progress counter readable',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g);
        g.runDebug.god = true;
        final bird = run.birdTrackPosition()!;
        run.spawner.spawnItem(
          GapItemPlan(kind: ElementId.piggy, trackX: bird.x + 150, y: bird.y),
        );
        await flushAndMount(g);
        for (var f = 0; f < 300 && run.state.piggy == null; f++) {
          final pickup = pickupsOf(g).whereType<PiggyPickup>().firstOrNull;
          if (pickup != null) {
            g.runBird!.setFlight(y: pickup.position.y, vy: 0);
          }
          g.update(1 / 60);
          if (f % 10 == 0) await flushAndMount(g);
        }
        await flushAndMount(g);
        final hud = RunHud.ensureFor(run);
        expect(hud.children.whereType<PiggyBadge>(), hasLength(1));
        final banner = hud.banners.current!;
        expect(banner.text, 'PIGGY BANK');
        final band = Rect.fromLTWH(
          banner.position.x,
          banner.position.y,
          banner.bandWidth,
          banner.bandHeight,
        );
        expect(
          band.contains(
            const Offset(PiggyConfig.hudTextX, PiggyConfig.hudTextY),
          ),
          isFalse,
          reason: 'The visible progress counter is painted through the banner.',
        );
      },
    );
  }, skip: 'S6-F03 open');
}
