import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/components/star_road/star_road_card.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';
import '../../helpers.dart';

void main() {
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({'gamesPlayed': 4}, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'panel measures actual contents before folding at $height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, _) async {
        final panel = MissionsPanel(
          missions: Missions(
            missions: const [
              MissionProgress(template: MissionTemplate.m01, target: 3),
              MissionProgress(template: MissionTemplate.m03, target: 15),
              MissionProgress(template: MissionTemplate.m11, target: 10),
            ],
          ),
          now: game.storage.now(),
          onDismiss: () {},
          weeklyCard: PositionComponent(size: Vector2(256, 90)),
          starRoadBuilder: (compact) => StarRoadCard(
            road: game.starRoad,
            daysLeft: 10,
            compact: compact,
            onPressed: () {},
          ),
        );
        game.world.add(panel);
        await flushAndMount(game);
        final card = panel.card.children.whereType<StarRoadCard>().single;
        expect(card.compact, height == 568);
        expect(card.height, height == 568 ? 44 : 88);
      },
    );
  }
  FlameTester<FlappySpikesGame>(
    () => createTestGame({'gamesPlayed': 4}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'Home missions card opens the road and back restores the panel',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final strip = game.homeScreen!.children
          .whereType<MissionsHomeStrip>()
          .single;
      strip.onPressed();
      await flushAndMount(game);
      final panel = game.world.children.whereType<MissionsPanel>().single;
      panel.card.children.whereType<StarRoadCard>().single.onPressed();
      await flushAndMount(game);
      expect(game.starRoadScreen, isNotNull);
      game.closeStarRoad();
      await flushAndMount(game);
      expect(game.world.children.whereType<MissionsPanel>(), hasLength(1));
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'run-end credits the first run and completed mission once',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.storage.gamesPlayed = 3;
      final board = Missions(
        day: game.storage.today,
        missions: const [
          MissionProgress(
            template: MissionTemplate.m01,
            target: 3,
            progress: 2,
          ),
          MissionProgress(template: MissionTemplate.m03, target: 15),
          MissionProgress(template: MissionTemplate.m11, target: 10),
        ],
      );
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      game.runDebug.ignoreGates = false;
      await startRun(game);
      game.storage.gamesPlayed = 4;
      await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
      expect(game.storage.starRoadXp, 3);
      await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
      expect(game.storage.starRoadXp, 3);
      expect(game.storage.starRoadRunDay, greaterThan(0));
    },
  );
}
