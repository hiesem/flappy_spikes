import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §10.4 hoop rumble: the rim touch knocks at the moment of
/// contact, a graze pass adds nothing, a perfect pass shakes 80 ms at 255.
void main() {
  test('§10.4 constants: shake 80 ms at 255, knock 15 ms at 90', () {
    expect(Rumble.shakeMs, 80);
    expect(Rumble.shakeAmplitude, 255);
    expect(Rumble.knockMs, 15);
    expect(Rumble.knockAmplitude, 90);
    expect(Rumble.knockThrottle, .09);
  });

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  tester.testGameWidget(
    '§10.4 a rim touch knocks in the frame of the touch; the following '
    'graze pass adds nothing',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      await flyUntil(game, (r) => r.spawner.nextHoopAhead() != null);
      final h = run.spawner.nextHoopAhead()!;
      final log = rumbleLog(game)..clear();
      // Glide into the lower rim end: a bounce, the bird lives.
      final ry = h.opening / 2 + h.kind.rimRadius(h) - 4;
      await glideInto(
        game,
        h,
        h.position.y + h.rings.first + ry,
        seconds: 1,
        until: (_) => events.any((e) => e is RimTouched),
      );
      expect(events.whereType<RimTouched>(), isNotEmpty);
      expect(run.dying, isFalse);
      expect(log, [RumbleKind.knock], reason: 'knocked in the touch frame');
      // Fly on until the hoop resolves (graze pass or not): no more rumble
      // from this hoop's pass.
      await flyUntil(game, (_) => h.resolved, maxSeconds: 2);
      final passed = events.whereType<HoopPassed>().where((e) => e.hoop == h);
      if (passed.isNotEmpty) {
        expect(passed.single.rimTouched, isTrue);
        expect(passed.single.perfect, isFalse);
        expect(passed.single.clean, isFalse);
      }
      expect(log.where((k) => k == RumbleKind.shake), isEmpty);
      expect(
        log.where((k) => k == RumbleKind.knock).length,
        lessThanOrEqualTo(events.whereType<RimTouched>().length),
      );
    },
  );

  tester.testGameWidget(
    '§10.4 two rim touches within 90 ms → one knock',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.spawner.nextHoopAhead() != null);
      final h = run.spawner.nextHoopAhead()!;
      final log = rumbleLog(game)..clear();
      void touch() =>
          run.events.emit(RimTouched(h, Vector2.zero(), Vector2(0, 1)));
      void frame() {
        game.runBird!.setFlight(y: game.viewHeight / 2, vy: 0);
        game.update(1 / 60);
      }

      touch();
      frame();
      touch(); // 16 ms later
      frame();
      touch(); // 33 ms later
      frame();
      expect(log, [RumbleKind.knock]);
      for (var i = 0; i < 6; i++) {
        frame();
      }
      touch(); // > 90 ms later
      frame();
      expect(log, [RumbleKind.knock, RumbleKind.knock]);
    },
  );

  tester.testGameWidget(
    '§10.4 a rim touch in the frame of a death does not rumble',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.spawner.nextHoopAhead() != null);
      final h = run.spawner.nextHoopAhead()!;
      final log = rumbleLog(game)..clear();
      run.events.emit(RimTouched(h, Vector2.zero(), Vector2(0, 1)));
      killRun(game);
      for (var i = 0; i < 10; i++) {
        game.update(1 / 60);
      }
      expect(log, isEmpty);
    },
  );

  tester.testGameWidget(
    '§10.4 a lethal rim touch (saw ring) → no rumble',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 20,
        force: [ElementId.saw],
      );
      final h = await flyToHoop(game, HoopKindId.saw, ElementId.saw);
      expect(h, isNotNull);
      final log = rumbleLog(game)..clear();
      final ry = h!.opening / 2 + h.kind.rimRadius(h);
      await glideInto(
        game,
        h,
        h.position.y + ry,
        seconds: .3,
        until: (r) => r.dying,
      );
      expect(run.dying, isTrue);
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(log, isEmpty);
    },
  );

  tester.testGameWidget(
    '§10.4 a perfect pass → one shake; plus a pickup in the same frame → '
    'only the shake',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.spawner.nextHoopAhead() != null);
      final h = run.spawner.nextHoopAhead()!;
      final log = rumbleLog(game)..clear();
      run.events.onAny((e) {
        if (e is HoopPassed && e.hoop == h) {
          run.events.emit(const PickupCollected(ElementId.heart, null));
        }
      });
      expect(await passHoopAt(game, h), isTrue);
      expect(log, [RumbleKind.shake]);
    },
  );
}
