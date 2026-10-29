import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

final _normal = Missions(
  day: 0,
  missions: [
    MissionProgress(template: MissionTemplate.m01, target: 3, progress: 1),
    MissionProgress(template: MissionTemplate.m03, target: 15, progress: 7),
    MissionProgress(template: MissionTemplate.m11, target: 10, progress: 4),
  ],
);

final _allDone = Missions(
  day: 0,
  missions: [
    MissionProgress(
      template: MissionTemplate.m01,
      target: 3,
      progress: 3,
      paid: true,
    ),
    MissionProgress(
      template: MissionTemplate.m03,
      target: 15,
      progress: 15,
      paid: true,
    ),
    MissionProgress(
      template: MissionTemplate.m11,
      target: 10,
      progress: 10,
      paid: true,
    ),
  ],
);

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();

  for (final height in [568.0, 711.0]) {
    for (final pending in [false, true]) {
      final missions = pending
          ? Missions(
              day: _allDone.day,
              tier: _allDone.tier,
              missions: _allDone.missions,
              chestsOwed: 1,
            )
          : _normal;
      FlameTester<FlappySpikesGame>(() {
        final game = createRunTestGame(
          worldHeight: height,
          clock: goldenClock,
          prefs: {
            'gamesPlayed': 4,
            'bestScore': 115,
            'lastScore': 88,
            'firstSessionDone': true,
            'noAdsPopupLastMs': kGoldenNow.millisecondsSinceEpoch,
            'noAdsPopupClosedMs': kGoldenNow.millisecondsSinceEpoch,
          },
        )..reduceMotionOverride = true;
        return game;
      }, gameSize: Vector2(320, height)).testGameWidget(
        'Missions panel ${pending ? 'chest pending' : 'in progress'} at '
        '${height.round()}',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
          await flushAndMount(game);
          stepGame(game, 1);
          final panel = MissionsPanel(
            missions: missions,
            now: kGoldenNow,
            onDismiss: () {},
          );
          game.world.add(panel);
          await flushAndMount(game);
        },
        verify: (game, tester) async {
          final panel = game.world.children.whereType<MissionsPanel>().single;
          expect(panel.card.y, greaterThanOrEqualTo(44));
          expect(
            panel.card.y + panel.card.height,
            lessThanOrEqualTo(height - 44),
          );
          expect(panel.missions.allDone, pending);
          expect(panel.missions.chestPending, pending);
          await expectGameGolden(
            tester,
            game,
            'goldens/missions_panel_${pending ? 'pending' : 'normal'}_${height.round()}.png',
          );
        },
      );
    }
  }
}
