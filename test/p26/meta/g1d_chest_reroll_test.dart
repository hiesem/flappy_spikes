import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'reroll requires completed ad and is limited to once per day',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final board = Missions(
        day: game.storage.today,
        missions: const [
          MissionProgress(template: MissionTemplate.m01, target: 3),
          MissionProgress(template: MissionTemplate.m03, target: 15),
          MissionProgress(template: MissionTemplate.m11, target: 10),
        ],
      );
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      final ads = game.monetization.ads as FakeRewardedAds;
      final before = game.storage.missions.toString();
      final panel = MissionsPanel(
        missions: board,
        now: game.storage.now(),
        onDismiss: () {},
        onSwap: (_) {},
      );
      game.world.add(panel);
      await flushAndMount(game);
      final buttons = panel.card.children
          .whereType<PositionComponent>()
          .expand((row) => row.children.whereType<MenuButton>())
          .where(
            (button) => button.children.whereType<MenuText>().any(
              (text) => text.text.contains('SWAP'),
            ),
          )
          .toList();
      expect(buttons, isNotEmpty);
      panel.removeFromParent();
      ads.mode = FakeAdMode.unavailable;
      expect(await game.rerollMission(0), isFalse);
      expect(game.storage.missions.toString(), before);
      ads.mode = FakeAdMode.fail;
      expect(await game.rerollMission(0), isFalse);
      expect(game.storage.missions.toString(), before);
      ads.mode = FakeAdMode.succeed;
      expect(await game.rerollMission(0), isTrue);
      expect(ads.placements.last, AdPlacement.missionReroll);
      expect(game.storage.missions.toString(), isNot(before));
      expect(await game.rerollMission(1), isFalse);
      expect(game.storage.missionRerollDay, game.storage.today);
      final used = MissionsPanel(
        missions: RunEndBookkeeping.currentMissions(game.storage),
        now: game.storage.now(),
        onDismiss: () {},
        onSwap: (_) {},
      );
      game.world.add(used);
      await flushAndMount(game);
      final swaps = used.card.children
          .whereType<PositionComponent>()
          .expand((row) => row.children.whereType<MenuButton>())
          .where(
            (button) => button.children.whereType<MenuText>().any(
              (text) => text.text.contains('SWAP'),
            ),
          );
      expect(swaps, isEmpty);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'registered opener offers pending chest on Home and claims once',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      expect(game.missionsChestOpenerRegistered, isTrue);
      game.storage.gamesPlayed = 3;
      await game.storage.saveStreakPaidDay(game.storage.today);
      final board = Missions(
        day: game.storage.today,
        missions: const [
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
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      game.homeMoments.beginVisit(
        HomeVisit(
          day: game.storage.now(),
          gamesPlayed: 4,
          requests: const HomeVisitRequests(
            missionsChest: true,
            starRoad: true,
          ),
        ),
      );
      expect(
        (game.homeMoments as HomeMomentBudget).selectedMoment,
        HomeMoment.missionsChest,
      );
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.missionsChestPopup, isNotNull);
      stepGame(game, 2);
      game.missionsChestPopup!.onDismiss();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(game.storage.feathers, 1);
      expect(
        RunEndBookkeeping.currentMissions(game.storage).chestPending,
        isFalse,
      );
      var starShown = false;
      game.homeMoments.show(HomeMoment.starRoad, () => starShown = true);
      expect(starShown, isFalse);
    },
  );
}
