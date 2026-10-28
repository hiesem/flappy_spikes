import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gift retains the final rows and settlement age', () {
    final gift = LbGift.fromJson({
      'gid': 'day',
      'tier': 'gold',
      'boardRank': 1,
      'createdAt': {'_seconds': 100, '_nanoseconds': 0},
      'playerCount': 7,
      'finalBoard': [
        {
          'rid': 'opaque',
          'rank': 1,
          'name': 'Bird',
          'points': 20,
          'look': {
            'bird': 'classic',
            'gear': 'none',
            'hat': 'none',
            'hoop': 'pink',
            'trail': 'flame',
          },
        },
      ],
    });
    expect(gift.createdAt!.millisecondsSinceEpoch, 100000);
    expect(gift.playerCount, 7);
    expect(gift.finalBoard.single.name, 'Bird');
    expect(gift.finalBoard.single.points, 20);
  });
  test('opaque stored rows parse as neutral placeholders', () {
    final gift = LbGift.fromJson({
      'gid': 'old',
      'tier': 'bronze',
      'boardRank': 3,
      'finalBoard': [
        {'rid': 'opaque', 'rank': 1, 'points': 12},
      ],
    });
    expect(gift.finalBoard.single.name, 'PLAYER');
    expect(gift.finalBoard.single.look.bird, 'classic');
  });
}
