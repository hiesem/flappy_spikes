// Pixel 8 element run for WP-3d (ARCH §7.3: each P3 WP adds its elements
// forced once and passed): a saw ring (from hoop 20), a switch ring (from
// 12; the autopilot takes the switch first) and a pair of powerup rings
// (from 12; the nearer ring).
//   flutter test integration_test/hazard_rings_elements_e2e_test.dart \
//     -d 38300DLJH004SD --dart-define=FS_E2E=true
import 'package:flame/game.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/main.dart' as app;
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WP-3d saw / switch / pair rings: each forced once and passed '
      'by the autopilot (fixed seed, fake ads)', (tester) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    app.main();
    FlappySpikesGame? game;
    for (var i = 0; i < 300 && game == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final w = find.byType(GameWidget<FlappySpikesGame>);
      if (w.evaluate().isNotEmpty) {
        final g = tester.widget<GameWidget<FlappySpikesGame>>(w).game;
        if (g != null && g.isLoaded) game = g;
      }
    }
    final g = game!;
    for (var i = 0; i < 100 && g.homeScreen?.isLoaded != true; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 5 && g.modalPopupOpen; i++) {
      g.handleBack();
      await tester.pump(const Duration(milliseconds: 500));
    }

    for (final (element, kind, start) in [
      (ElementId.saw, HoopKindId.saw, 20),
      (ElementId.switchRing, HoopKindId.switchRing, 12),
      (ElementId.pair, HoopKindId.pair, 12),
    ]) {
      E2EHooks.reset();
      E2EHooks.autopilot = true;
      E2EHooks.startHoopIndex = start;
      E2EHooks.force.add(element);
      await tester.pump(const Duration(seconds: 1));
      await g.startRun();
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.state, GameState.playing);
      final run = g.run!;
      var passed = false;
      for (var i = 0; i < 400 && g.state == GameState.playing && !passed; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        passed = run.spawner.hoops.any(
          (h) => h.plan.kind == kind && h.takenRing != null,
        );
      }
      expect(passed, isTrue, reason: '${element.storageId} passed');
      if (g.state == GameState.playing) g.onBirdHit(MistakeCause.spikes);
      for (var i = 0; i < 60 && g.state != GameState.results; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (g.state == GameState.reviving) g.reviveScreen?.tapNoThanks();
      }
      expect(g.state, GameState.results);
      g.goHome();
      await tester.pump(const Duration(seconds: 1));
    }
    E2EHooks.reset();
  });
}
