import 'package:flame/components.dart';
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
  @override
  int? get verifiedBest => null;
  @override
  int? get bestFloor => null;
  @override
  Future<void> resetLocal() async {}
  @override
  Future<LbGetBoardResult?> getBoard({
    LbBoardTab tab = LbBoardTab.today,
  }) async => LbGetBoardResult(
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
    return const LbClaimGiftResult(
      ok: true,
      id: 'owned-old',
      tier: 'gold',
      prize: LbGiftRoll(kind: 'coins', coins: 175),
    );
  }
}

void main() {
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
    },
  );
}
