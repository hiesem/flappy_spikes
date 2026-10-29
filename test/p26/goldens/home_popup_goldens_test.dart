import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/gift_popup.dart';
import 'package:flappy_spikes/components/progression/missions_chest_popup.dart';
import 'package:flappy_spikes/components/progression/star_road_popup.dart';
import 'package:flappy_spikes/components/progression/streak_lost_popup.dart';
import 'package:flappy_spikes/components/progression/streak_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/progression/star_road.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

final _today = streakLocalDay(kGoldenNow);

Map<String, Object> _prefs({bool streakReward = false}) => {
  'gamesPlayed': 4,
  'bestScore': 115,
  'lastScore': 88,
  'firstSessionDone': true,
  'noAdsPopupLastMs': kGoldenNow.millisecondsSinceEpoch,
  'noAdsPopupClosedMs': kGoldenNow.millisecondsSinceEpoch,
  'starRoadPopupDay': _today,
  'streakDays': streakReward ? 4 : 0,
  'streakLastDay': streakReward ? _today : _today - 1,
  'streakPaidDay': streakReward ? _today - 1 : _today,
  'streakLostDays': 0,
  'streakLostSeenDay': -1,
};

FlameTester<FlappySpikesGame> _tester(
  double height, {
  bool streakReward = false,
}) {
  return FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: height,
      clock: goldenClock,
      prefs: _prefs(streakReward: streakReward),
    )..reduceMotionOverride = true,
    gameSize: Vector2(320, height),
  );
}

Future<void> _ready(FlappySpikesGame game) async {
  await game.ready();
  await preloadImages(game);
  await flushAndMount(game);
  stepGame(game, .25);
  await flushAndMount(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();

  for (final height in [568.0, 711.0]) {
    _tester(height).testGameWidget(
      'STREAK LOST popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final popup = StreakLostPopup(
          state: DayStreak(
            streakDays: 0,
            streakLastDay: _today - 1,
            streakLostDays: 5,
            streakLostSeenDay: -1,
          ),
          noAds: false,
          balance: () => 0,
          onRestore: () {},
          onGiveUp: () {},
          onMomentDone: () {},
          onDismiss: () {},
        );
        game.world.add(popup);
        await flushAndMount(game);
        expect(popup.cardHeight, 388);
        expect(popup.lostLine.text, '5 days of day streak interrupted!');
        expect(popup.card.y + popup.card.height, lessThanOrEqualTo(height));
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_streak_lost_${height.round()}.png',
        );
      },
    );

    _tester(height, streakReward: true).testGameWidget(
      'streak reward popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final popup = StreakCard(
          state: game.dayStreak,
          today: game.storage.today,
          reward: true,
          onDismiss: () {},
          onCollect: (_) {},
        );
        game.world.add(popup);
        await flushAndMount(game);
        expect(popup.cardHeight, 370);
        expect(popup.collectButton, isNotNull);
        expect(game.previewStreakReward.coins, 40);
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_streak_reward_${height.round()}.png',
        );
      },
    );

    _tester(height).testGameWidget(
      'GO TO COLLECT popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        const names = ['Ava', 'Ben', 'Cleo', 'Dev', 'Eli'];
        final rows = [
          for (var i = 0; i < names.length; i++)
            LbBoardRow(
              rid: 'row-${i + 1}',
              rank: i + 1,
              name: names[i],
              look: Look.defaults,
              points: 480 - i * 60,
              playingNow: true,
            ),
        ];
        final popup = GiftPopup(
          gift: LbGift(
            gid: 'golden-gift',
            tier: 'silver',
            boardRank: 2,
            finalBoard: rows,
            playerCount: 50,
          ),
          onCollect: () {},
          onDismiss: () {},
        );
        game.world.add(popup);
        await flushAndMount(game);
        expect(popup.cardHeight, 450);
        expect(popup.card.y + popup.card.height, lessThanOrEqualTo(height));
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_gift_${height.round()}.png',
        );
      },
    );

    _tester(height).testGameWidget(
      'missions chest popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final popup = MissionsChestPopup(
          reward: const MissionChestReward(MissionChestKind.coins, 40),
          piece: 0,
          onDismiss: () {},
        );
        game.world.add(popup);
        await flushAndMount(game);
        stepGame(game, 2.05);
        await flushAndMount(game);
        expect(popup.cardHeight, 346);
        expect(popup.elapsed, greaterThanOrEqualTo(2));
        expect(popup.box.lid.u, greaterThan(0));
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_missions_chest_${height.round()}.png',
        );
      },
    );

    _tester(height).testGameWidget(
      'LEVEL UP popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        await game.storage.saveLevelStep(
          index: 1,
          points: 0,
          pending: const [
            {
              'lvl': 1,
              'coins': 50,
              'item': 'hat:cap',
              'extraCoins': 0,
              'fallback': 'none',
            },
          ],
        );
        game.openLevelUpPopup(debugForce: true);
        await flushAndMount(game);
        expect(game.levelUpPopup, isNotNull);
        final popup = game.levelUpPopup!;
        stepGame(game, 2.05);
        await flushAndMount(game);
        expect(popup.reveal.current.revealed, isTrue);
        expect(popup.reveal.title, 'LEVEL REWARD');
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_level_up_${height.round()}.png',
        );
      },
    );

    _tester(height).testGameWidget(
      'Star Road popup at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final popup = StarRoadPopup(
          road: StarRoad(season: 3, xp: 72, claimed: {1, 2, 3, 4, 5, 6, 7, 8}),
          onGo: () {},
          onDismiss: () {},
        );
        game.world.add(popup);
        await flushAndMount(game);
        stepGame(game, 2.05);
        await flushAndMount(game);
        expect(popup.cardHeight, 364);
        expect(popup.title.text, 'TIER 9 REACHED');
        expect(popup.tiles.single.label, '40 COINS');
        expect(popup.goButton.isActive?.call(), isTrue);
        await expectGameGolden(
          tester,
          game,
          'goldens/home_popup_star_road_${height.round()}.png',
        );
      },
    );
  }
}
