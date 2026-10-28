import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
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
        if (!card.compact) {
          expect(
            card.children
                .whereType<MenuTag>()
                .single
                .children
                .whereType<MenuText>()
                .single
                .text,
            '10 DAYS LEFT',
          );
        }
        if (card.compact) {
          expect(
            card.children.whereType<MenuText>().map((t) => t.text),
            contains('STAR ROAD ·'),
          );
        }
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
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'PRD 2.6 O28: runs 1–3 never earn stars or advance the watermark',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.runDebug.ignoreGates = false;
      await startRun(game);
      for (var n = 1; n <= 3; n++) {
        game.storage.gamesPlayed = n;
        await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
        expect(game.storage.starRoadXp, 0);
        expect(game.storage.starRoadRunDay, -1);
        await tester.runAsync(() => RunEndBookkeeping.record(game, 0));
        expect(game.missionRunSettlementPending, isFalse);
      }
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({'gamesPlayed': 4}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'Home preparation recovers from a failed prior settlement',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await game.storage.saveMissionDay(-1);
      await tester.runAsync(
        () => RunEndBookkeeping.prepareHome(
          game,
          Future<void>.error(StateError('write failed')),
        ),
      );
      expect(game.storage.missionDay, game.storage.today);
      expect(game.storage.missions, isNotEmpty);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'last-day card renders the UTC hours chip',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final card = StarRoadCard(
        road: game.starRoad,
        daysLeft: 1,
        compact: false,
        clock: () => DateTime.utc(2026, 11, 22, 18, 48),
        onPressed: () {},
      );
      game.world.add(card);
      await flushAndMount(game);
      final chip = card.children.whereType<MenuTag>().single;
      expect(
        chip.children.whereType<MenuText>().single.text,
        'ENDS IN 5 H 12 M',
      );
    },
  );
}
