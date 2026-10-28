import 'package:flappy_spikes/components/star_road/star_road_card.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/progression/star_road.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('O75 item tiles do not disclose rarity', () {
    for (final tier in [10, 20, 25]) {
      expect(starRoadRewardLabel(starRoadReward(tier)), 'MYSTERY');
    }
  });
  test('O37 panel folds only when expanded content overflows', () {
    expect(
      starRoadCardShouldFold(otherContentHeight: 400, availableHeight: 488),
      false,
    );
    expect(
      starRoadCardShouldFold(otherContentHeight: 401, availableHeight: 488),
      true,
    );
    final card = StarRoadCard(
      road: StarRoad(season: 1, xp: 80, claimed: {1, 2, 3, 4, 5, 6, 7, 8}),
      daysLeft: 5,
      compact: true,
      onPressed: () {},
    );
    expect(card.height, 44);
    expect(card.compactLabel, 'TIER 10 · 2 TO CLAIM');
  });
  test('PRD claim cues', () {
    expect(starRoadClaimSound(starRoadReward(1)), Sfx.bnCoin);
    expect(starRoadClaimSound(starRoadReward(10)), Sfx.lvClaim);
    expect(starRoadClaimSound(starRoadReward(20)), Sfx.lvClaim);
    expect(starRoadClaimSound(starRoadReward(25)), Sfx.lvUpBig);
  });
}
