import 'dart:async';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/gift_popup.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers.dart';

class _Board implements LeaderboardService {
  int claims = 0;
  bool fail = false;
  bool serverRolled = false;
  Completer<LbGetBoardResult?>? blocked;
  @override
  int? get verifiedBest => null;
  @override
  int? get bestFloor => null;
  @override
  Future<void> resetLocal() async {}
  @override
  Future<LbGetBoardResult?> getBoard({
    LbBoardTab tab = LbBoardTab.today,
  }) async => blocked != null
      ? blocked!.future
      : LbGetBoardResult(
          today: LbBoardPayload(
            tab: LbBoardTab.today,
            rows: const [],
            gifts: [
              LbGift(
                gid: 'new',
                tier: 'silver',
                boardRank: 2,
                createdAt: DateTime.utc(2026, 10, 20),
              ),
              LbGift(
                gid: 'old',
                tier: 'gold',
                boardRank: 1,
                createdAt: DateTime.utc(2026, 10, 19),
                claimedAt: serverRolled ? DateTime.utc(2026, 10, 20) : null,
                rolled: serverRolled
                    ? const LbGiftRoll(kind: 'coins', coins: 175)
                    : null,
              ),
            ],
          ),
          best: const LbBoardPayload(tab: LbBoardTab.best, rows: []),
        );
  @override
  Future<LbSubmitRunResult?> submitRun(LbSubmitRunRequest request) async =>
      null;
  @override
  Future<LbClaimGiftResult?> claimGift(String id, {List<String>? owned}) async {
    claims++;
    if (fail) return null;
    serverRolled = true;
    return const LbClaimGiftResult(
      ok: true,
      id: 'owned-old',
      tier: 'gold',
      prize: LbGiftRoll(kind: 'coins', coins: 175),
    );
  }
}

void main() {
  test('late gifts join only an unspent visit and keep higher priorities', () {
    final moments = HomeMomentBudget();
    final gift = HomeGiftBoxRequest(
      id: 'gift',
      availableAt: DateTime.utc(2026),
    );
    HomeVisit visit(HomeVisitRequests requests) =>
        HomeVisit(day: DateTime.utc(2026), gamesPlayed: 4, requests: requests);
    moments.beginVisit(
      visit(const HomeVisitRequests(streakReward: true, noAds: true)),
    );
    moments.offerLeaderboardGifts([gift]);
    expect(moments.selectedMoment, HomeMoment.streakReward);
    expect(moments.tryShow(HomeMoment.streakReward, () {}), isTrue);
    moments.offerLeaderboardGifts([gift]);
    expect(moments.tryShow(HomeMoment.leaderboardCollect, () {}), isFalse);
    moments.beginVisit(visit(const HomeVisitRequests(noAds: true)));
    moments.offerLeaderboardGifts([gift]);
    expect(moments.selectedMoment, HomeMoment.leaderboardCollect);
    expect(moments.selectedGift?.id, 'gift');
  });
  final board = _Board();
  final flame = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'firstSessionDone': true,
      'gamesPlayed': 1,
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      leaderboard: board,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  flame.testGameWidget(
    'Home selects oldest gift and opening credits it once',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final policy = game.homeMoments as HomeMomentBudget;
      expect(policy.selectedMoment, HomeMoment.leaderboardCollect);
      expect(policy.selectedGift?.id, 'old');
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);
      final popup = game.world.children.whereType<GiftPopup>().single;
      expect(popup.gift.gid, 'old');
      popup.onCollect();
      await flushAndMount(game);
      final opening = game.world.children.whereType<GiftOpeningPopup>().single;
      await opening.open();
      await opening.open();
      expect(board.claims, 1);
      expect(game.menu.wallet.balance, 175);
      expect(game.storage.lbGiftPending['applied'], true);
      stepGame(game, 1.3);
      await flushAndMount(game);
      expect(opening.coinCount!.text, startsWith('+'));
      stepGame(game, .4);
      expect(opening.coinCount!.text, '+175');
    },
  );
  final failingBoard = _Board()..fail = true;
  final failure = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'firstSessionDone': true,
      'gamesPlayed': 1,
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      leaderboard: failingBoard,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  failure.testGameWidget(
    'failed claim can be closed with Back',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);
      game.world.children.whereType<GiftPopup>().single.onCollect();
      await flushAndMount(game);
      final opening = game.world.children.whereType<GiftOpeningPopup>().single;
      await opening.open();
      expect(opening.canDismiss, isTrue);
      expect(failingBoard.claims, 1);
      expect(game.handleBack(), isTrue);
      await flushAndMount(game);
      expect(game.modalPopupOpen, isFalse);
      expect(game.menu.wallet.balance, 0);
    },
  );

  final restartBoard = _Board();
  final restart = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'firstSessionDone': true,
      'gamesPlayed': 1,
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      leaderboard: restartBoard,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  restart.testGameWidget(
    'restart during opening recovers the journal once and resumes reveal',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      // The durable journal is the boundary immediately after the server roll
      // and before the wallet mutation, exactly as GiftApply writes it.
      await game.storage.saveLbGiftPending({
        'id': 'owned-old',
        'request_id': 'old',
        'tier': 'gold',
        'kind': 'coins',
        'coins': 175,
        'fallback': false,
        'target': 175,
        'applied': false,
      });
      final next = FlappySpikesGame(
        worldHeight: Config.worldHeight,
        soundEnabled: false,
        leaderboard: restartBoard,
      );
      await tester.pumpWidget(GameWidget(game: next));
      await tester.runAsync(() async {
        await next.ready();
        await preloadImages(next);
        await flushAndMount(next);
      });
      expect(next.menu.wallet.balance, 175);
      expect(next.storage.lbGiftPending['applied'], true);
      stepGame(next, Config.levelUpSettleDelay + .2);
      await flushAndMount(next);
      final opening = next.world.children.whereType<GiftOpeningPopup>().single;
      await opening.open();
      expect(next.menu.wallet.balance, 175);
      expect(restartBoard.claims, 0);
    },
  );

  final slowBoard = _Board()..blocked = Completer<LbGetBoardResult?>();
  final slow = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'firstSessionDone': true,
      'gamesPlayed': 1,
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      leaderboard: slowBoard,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  slow.testGameWidget(
    'a stalled board fetch never blocks the Home budget',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      expect((game.homeMoments as HomeMomentBudget).visitActive, isTrue);
      expect(game.state, GameState.start);
      expect(slowBoard.blocked!.isCompleted, isFalse);
      slowBoard.blocked!.complete(null);
    },
  );
  // The server committed a roll but the process died before its reply could
  // create lbGiftPending. On launch, the claimed stub must still be offered.
  final rolledBoard = _Board()..serverRolled = true;
  final lostReply = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'firstSessionDone': true,
      'gamesPlayed': 1,
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      leaderboard: rolledBoard,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  lostReply.testGameWidget(
    'server roll lost before local journal is credited once on launch',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      expect(game.storage.lbGiftPending, isEmpty);
      expect((game.homeMoments as HomeMomentBudget).selectedGift?.id, 'old');
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);
      game.world.children.whereType<GiftPopup>().single.onCollect();
      await flushAndMount(game);
      final opening = game.world.children.whereType<GiftOpeningPopup>().single;
      await opening.open();
      expect(rolledBoard.claims, 1);
      expect(game.menu.wallet.balance, 175);
      expect(game.storage.lbGiftsClaimed, contains('old'));
      stepGame(game, 1.3);
      await flushAndMount(game);
      opening.finish(opening.prize!, opening.claimRect);
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(game.storage.lbGiftPending, isEmpty);
      final next = FlappySpikesGame(
        worldHeight: Config.worldHeight,
        soundEnabled: false,
        leaderboard: rolledBoard,
      );
      await tester.pumpWidget(GameWidget(game: next));
      await tester.runAsync(() async {
        await next.ready();
        await preloadImages(next);
        await flushAndMount(next);
      });
      expect(next.menu.wallet.balance, 175);
      expect(next.storage.lbGiftsClaimed, contains('old'));
      expect(
        (next.homeMoments as HomeMomentBudget).selectedGift?.id,
        isNot('old'),
      );
      expect(rolledBoard.claims, 1);
    },
  );
}
