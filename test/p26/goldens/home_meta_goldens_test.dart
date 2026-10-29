import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/streak_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();
  final today = streakLocalDay(kGoldenNow);

  for (final height in [568.0, 711.0]) {
    for (final lit in [true, false]) {
      FlameTester<FlappySpikesGame>(() {
        final game = createRunTestGame(
          worldHeight: height,
          clock: goldenClock,
          prefs: {
            'gamesPlayed': 4,
            'bestScore': 115,
            'lastScore': 88,
            'streakDays': 4,
            'streakLastDay': lit ? today : today - 1,
            'streakPaidDay': lit ? today : -1,
            'streakLostDays': 0,
            'streakLostSeenDay': -1,
            'firstSessionDone': true,
            'noAdsPopupLastMs': kGoldenNow.millisecondsSinceEpoch,
            'noAdsPopupClosedMs': kGoldenNow.millisecondsSinceEpoch,
          },
        )..reduceMotionOverride = true;
        return game;
      }, gameSize: Vector2(320, height)).testGameWidget(
        'Home streak chip ${lit ? 'lit' : 'grey'} at ${height.round()}',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
          await flushAndMount(game);
          stepGame(game, 1);
          await flushAndMount(game);
          game.menu.slot
            ..debugForce = Powerup.bigHoops
            ..rollForArrival();
          game.homeScreen!.refresh();
          await flushAndMount(game);
        },
        verify: (game, tester) async {
          final chip = game.homeScreen!
              .descendants()
              .whereType<StreakStrip>()
              .single;
          expect(chip.visible, isTrue);
          expect(chip.flame.lit, lit);
          expect(chip.count.text, '4');
          expect(game.modalPopupOpen, isFalse);
          await expectGameGolden(
            tester,
            game,
            'goldens/home_streak_${lit ? 'lit' : 'grey'}_${height.round()}.png',
          );
        },
      );
    }
  }
}
