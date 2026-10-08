// Pixel 8 smoke run of the PRD-2 run core (ARCH §7.3):
//   flutter test integration_test/run_core_e2e_test.dart \
//     -d 38300DLJH004SD --dart-define=FS_E2E=true
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/main.dart' as app;
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WP-0b run core: launch → home → run start (fixed seed, fake '
      'ads, autopilot) → run end → home', (tester) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    E2EHooks.reset();
    E2EHooks.autopilot = true;

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
    expect(game, isNotNull, reason: 'the game loaded');
    final g = game!;

    // Home screen.
    for (var i = 0; i < 100 && g.homeScreen?.isLoaded != true; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(g.state, GameState.start);
    expect(g.homeScreen, isNotNull);
    expect(g.monetization.ads, isA<FakeRewardedAds>());
    // Let a launch popup (if any) be dismissed by pressing back.
    for (var i = 0; i < 5 && g.modalPopupOpen; i++) {
      g.handleBack();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(seconds: 1));

    // Run start.
    await g.startRun();
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.state, GameState.playing);
    final run = g.run!;
    expect(run.started, isTrue);
    expect(run.setup.seed, kE2ESeed);

    // The autopilot plays for a few seconds of real frames.
    for (var i = 0; i < 60 && g.state == GameState.playing; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(run.clock.t, greaterThan(1));

    // End the run (if the bot is still alive) and go home.
    if (g.state == GameState.playing) g.onBirdHit(MistakeCause.spikes);
    await tester.pump(const Duration(milliseconds: 500));
    expect(g.state, GameState.gameOver);
    expect(run.ended, isTrue);
    g.goHome();
    await tester.pump(const Duration(seconds: 1));
    expect(g.state, GameState.start);
    expect(g.run, isNull);
    E2EHooks.reset();
    // audioplayers' frame-based position updater must be gone before the
    // binding checks for leftover frame callbacks.
    await FlameAudio.bgm.stop();
    await FlameAudio.bgm.audioPlayer.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
