import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/components/progression/weekly_card.dart';
import 'package:flappy_spikes/components/star_road/star_road_art.dart';
import 'package:flappy_spikes/components/star_road/star_road_card.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/progression/star_road.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

final _missions = Missions(
  day: 0,
  missions: [
    MissionProgress(template: MissionTemplate.m01, target: 3, progress: 1),
    MissionProgress(template: MissionTemplate.m03, target: 15, progress: 7),
    MissionProgress(template: MissionTemplate.m11, target: 10, progress: 4),
  ],
);

Map<String, Object> _prefs() => {
  'gamesPlayed': 4,
  'bestScore': 115,
  'lastScore': 88,
  'firstSessionDone': true,
  'noAdsPopupLastMs': kGoldenNow.millisecondsSinceEpoch,
  'noAdsPopupClosedMs': kGoldenNow.millisecondsSinceEpoch,
  'starRoadSeason': 3,
  'starRoadXp': 72,
  'starRoadClaimed': ['1', '2', '3', '4', '5', '6', '7', '8'],
};

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();

  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(() {
      return createRunTestGame(
        worldHeight: height,
        clock: goldenClock,
        prefs: _prefs(),
      )..reduceMotionOverride = true;
    }, gameSize: Vector2(320, height)).testGameWidget(
      'Star Road screen midseason at ${height.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        await game.storage.saveStarRoadPopupDay(game.storage.today);
        stepGame(game, .5);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        expect(game.starRoad.season, 3);
        expect(game.starRoad.tier, 9);
        expect(game.starRoad.claimable, [9]);
        expect(game.openStarRoad(daysLeft: 6, onBack: () {}), isTrue);
        await flushAndMount(game);
        final screen = game.starRoadScreen!;
        expect(screen.rows.length, starRoadTierCount);
        expect(screen.rows[9], isNotNull);
        expect(
          screen.rows[9]!.children.whereType<StarRoadTierNode>().single.state,
          StarRoadNodeState.claimable,
        );
        expect(
          screen.rows[10]!.children.whereType<StarRoadTierNode>().single.state,
          StarRoadNodeState.next,
        );
        await expectGameGolden(
          tester,
          game,
          'goldens/star_road_screen_${height.round()}.png',
        );
      },
    );

    FlameTester<FlappySpikesGame>(() {
      return createRunTestGame(
        worldHeight: height,
        clock: goldenClock,
        prefs: _prefs(),
      )..reduceMotionOverride = true;
    }, gameSize: Vector2(320, height)).testGameWidget(
      'Star Road missions-panel card at ${height.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        stepGame(game, 1);
        final panel = MissionsPanel(
          missions: _missions,
          now: kGoldenNow,
          onDismiss: () {},
          weeklyCard: WeeklyCard(
            course: WeeklyCourse(
              weeklyBest: {WeeklyWeek.at(kGoldenNow).key: 31},
            ),
            now: kGoldenNow,
            onPressed: () {},
          ),
          starRoadBuilder: (compact) => StarRoadCard(
            road: game.starRoad,
            daysLeft: 6,
            compact: compact,
            clock: goldenClock,
            onPressed: () {},
          ),
        );
        game.world.add(panel);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final panel = game.world.children.whereType<MissionsPanel>().single;
        final card = panel.card.children.whereType<StarRoadCard>().single;
        expect(card.compact, height == 568);
        expect(card.children.whereType<StarRoadStar>(), isNotEmpty);
        expect(
          panel.card.y + panel.card.height,
          lessThanOrEqualTo(height - 44),
        );
        await expectGameGolden(
          tester,
          game,
          'goldens/star_road_panel_${card.compact ? 'compact' : 'expanded'}_${height.round()}.png',
        );
      },
    );
  }
}
