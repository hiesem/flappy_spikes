import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §6: every bullseye hit pays `coin_bullseye` (3) coins and the
/// same number of points on top of the pass. A rim touch does not change it.
void main() {
  /// The test-wide set (flutter_test_config.dart) plus [extra]; a run start
  /// hands `Tuning.instance.active` to the config getters, so a remote value
  /// has to live in the service.
  void useTuning(Map<String, String> extra) {
    Tuning.instance = Tuning(
      active: TuningValues.resolve({'ui_unlock_best': '0', ...extra}),
    );
    TuningValues.current = Tuning.instance.active;
  }

  tearDown(() => useTuning(const {}));

  /// Starts a run with a bullseye forced at hoop 6 and passes it at [dy].
  /// [rimTouched] marks the hoop as touched before the pass (a graze).
  Future<
    ({
      RunController run,
      Hoop hoop,
      List<RunEvent> events,
      int points,
      int coins,
      int wallet,
    })
  >
  passBullseye(
    FlappySpikesGame game, {
    double dy = 0,
    bool rimTouched = false,
  }) async {
    final run = await startRun(
      game,
      startHoopIndex: 6,
      force: [ElementId.bullseye],
    );
    final events = <RunEvent>[];
    run.events.onAny(events.add);
    expect(
      await flyUntil(
        game,
        (_) => firstHoopOf(game, HoopKindId.bullseye) != null,
      ),
      isTrue,
    );
    final hoop = firstHoopOf(game, HoopKindId.bullseye)!;
    if (rimTouched) hoop.touched = true;
    final score0 = run.state.score;
    final coins0 = run.state.coinsThisRun;
    final wallet0 = game.menu.wallet.balance;
    expect(await passHoopAt(game, hoop, dy: dy), isTrue);
    expect(hoop.takenRing, 0, reason: 'passed, not missed');
    return (
      run: run,
      hoop: hoop,
      events: events,
      points: run.state.score - score0,
      coins: run.state.coinsThisRun - coins0,
      wallet: game.menu.wallet.balance - wallet0,
    );
  }

  List<CoinsEarned> bullseyeCoins(List<RunEvent> events) => events
      .whereType<CoinsEarned>()
      .where((e) => e.source == CoinSource.bullseye)
      .toList();

  ElementBanner? bannerOf(RunController run) {
    final banner = RunHud.of(run)?.banners.current;
    return banner is ElementBanner ? banner : null;
  }

  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  group('PRD-2.3.1 §6 bullseye pays +3 coins and +3 points', () {
    test('the default coin_bullseye is 3', () {
      expect(TuningValues.defaults().i('coin_bullseye'), 3);
      expect(BullseyeConfig.coins, 3);
    });

    tester().testGameWidget(
      'a bullseye pass adds the pass reward plus exactly 3 coins and 3 '
      'points; the banner reads "BULLSEYE!" "+3 coins"',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final p = await passBullseye(game);
        // A centred pass is perfect: 2 points (streak 1) and 2 coins.
        expect(
          p.events
              .whereType<HoopPassed>()
              .where((e) => e.hoop == p.hoop)
              .single
              .perfect,
          isTrue,
        );
        expect(
          p.events.whereType<CoinsEarned>().map((e) => (e.source, e.amount)),
          containsAll([(CoinSource.perfect, 2), (CoinSource.bullseye, 3)]),
        );
        expect(bullseyeCoins(p.events).single.amount, 3);
        expect(p.points, 2 + 3);
        expect(p.coins, 2 + 3);
        expect(p.wallet, 2 + 3);
        final banner = bannerOf(p.run);
        expect(banner?.text, 'BULLSEYE!');
        expect(banner?.subtitle, '+3 coins');
      },
    );

    tester().testGameWidget(
      'a rim-touched bullseye also pays +3 coins and +3 points (the pass is '
      'not perfect: 1 coin and 1 point on top)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final p = await passBullseye(game, rimTouched: true);
        final pass = p.events
            .whereType<HoopPassed>()
            .where((e) => e.hoop == p.hoop)
            .single;
        expect(pass.perfect, isFalse);
        expect(pass.rimTouched, isTrue);
        expect(bullseyeCoins(p.events).single.amount, 3);
        expect(p.coins, 1 + 3);
        expect(p.points, 1 + 3);
        expect(bannerOf(p.run)?.subtitle, '+3 coins');
      },
    );

    tester().testGameWidget(
      'remote coin_bullseye = 1: a hit adds 1 coin and 1 point, and the '
      'banner reads "+1 coin"',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        useTuning({'coin_bullseye': '1'});
        final p = await passBullseye(game);
        expect(bullseyeCoins(p.events).single.amount, 1);
        expect(p.coins, 2 + 1);
        expect(p.points, 2 + 1);
        expect(bannerOf(p.run)?.subtitle, '+1 coin');
      },
    );
  });
}
