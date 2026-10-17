import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §14.3 results count-up ticks: one `sk_tick` stream, min(24,
/// 8 + the largest count), the CLAIM count ticks too, none for 0 / 0, NEXT
/// stops them.
void main() {
  const claimed1to6 = ['1', '2', '3', '4', '5', '6'];

  test('§14.1 tick count: min(24, 8 + amount); 0 → none', () {
    expect(ResultsScreen.ticksFor(0), 0);
    expect(ResultsScreen.ticksFor(1), 9);
    expect(ResultsScreen.ticksFor(14), 22);
    expect(ResultsScreen.ticksFor(16), 24);
    expect(ResultsScreen.ticksFor(800), 24);
  });

  void rt(
    String name,
    Map<String, Object> prefs,
    Future<void> Function(FlappySpikesGame g) body,
  ) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: prefs),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      name,
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) => body(g),
    );
  }

  Future<ResultsScreen> endWith(
    FlappySpikesGame g, {
    required int points,
    int coins = 0,
  }) async {
    await startRun(g);
    final run = g.run!;
    run.ctx.addScore(points);
    if (coins > 0) run.ctx.earn(coins, CoinSource.hoop);
    killRun(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
    return g.resultsScreen!;
  }

  int ticks(List<String> sfx) => sfx.where((s) => s == 'skTick').length;

  for (final (points, coins) in [(12, 3), (3, 14), (40, 2)]) {
    rt(
      '§14.3 the first count ($points points, $coins coins) plays '
      'min(24, 8 + max) ticks, one stream',
      {
        'bestScore': 900, 'playerLevel': 7,
        'claimedLevels': [...claimed1to6, '7', '8'],
      },
      (g) async {
        final sfx = sfxLog(g);
        await endWith(g, points: points, coins: coins);
        sfx.clear();
        stepGame(g, 1.5);
        expect(
          ticks(sfx),
          ResultsScreen.ticksFor(points > coins ? points : coins),
        );
      },
    );
  }

  rt(
    '§14.3 a 0 / 0 run plays no ticks; sound disabled (tests): play only '
    'reaches the recorder, no channel',
    {'bestScore': 900, 'playerLevel': 7},
    (g) async {
      expect(g.sound.enabled, isFalse);
      final sfx = sfxLog(g);
      await endWith(g, points: 0);
      stepGame(g, 1.5);
      expect(ticks(sfx), 0);
    },
  );

  rt(
    '§14.3 the ticks follow the eased count: quick at first, slower later',
    {
      'bestScore': 900, 'playerLevel': 7,
      'claimedLevels': [...claimed1to6, '7', '8'],
    },
    (g) async {
      final sfx = sfxLog(g);
      final page = await endWith(g, points: 40);
      sfx.clear();
      // Up to the count start (0.45 s).
      stepGame(g, .45 - page.time + 1e-6);
      final first = <double>[];
      final last = <double>[];
      for (var i = 0; i < 60; i++) {
        final before = ticks(sfx);
        stepGame(g, 1 / 60);
        if (ticks(sfx) > before) (i < 30 ? first : last).add(page.time);
      }
      expect(first.length, greaterThan(last.length));
      expect(ticks(sfx), 24);
    },
  );

  rt(
    '§14.3 NEXT mid-count stops further ticks',
    {
      'bestScore': 900, 'playerLevel': 7,
      'claimedLevels': [...claimed1to6, '7', '8'],
    },
    (g) async {
      final sfx = sfxLog(g);
      final page = await endWith(g, points: 40, coins: 5);
      sfx.clear();
      stepGame(g, .55);
      final mid = ticks(sfx);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(24));
      page.next();
      stepGame(g, 1);
      expect(ticks(sfx), mid);
    },
  );

  rt(
    '§14.3 the CLAIM count plays min(24, 8 + claimed) ticks under lv_claim',
    {'bestScore': 760, 'playerLevel': 6, 'claimedLevels': claimed1to6},
    (g) async {
      final sfx = sfxLog(g);
      final page = await endWith(g, points: 815, coins: 65);
      expect(page.model.levelReward, 800);
      stepGame(g, 3.9);
      await flushAndMount(g);
      expect(page.claimShowing, isTrue);
      expect(ticks(sfx), 24, reason: 'the first count');
      sfx.clear();
      page.claimButton.button.onPressed();
      await flushAndMount(g);
      stepGame(g, 2);
      expect(sfx, contains('lvClaim'));
      expect(ticks(sfx), ResultsScreen.ticksFor(800));
    },
  );
}
