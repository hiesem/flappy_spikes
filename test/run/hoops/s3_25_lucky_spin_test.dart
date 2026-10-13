import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/lucky_spin.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c: Lucky Spin (PRD-2 §3.25, §5.24).
void main() {
  test('§3.25 slices (PRD-2.3 §14.2: +1, +2, +3, +5, +1, +2, equal chance, '
      'average ≈ 2.33); '
      '§5.24 colours, r 24, 36 pt above, 7 rad/s, 8 rad/s²', () {
    expect(RunConfig.luckySpinSlices, [1, 2, 3, 5, 1, 2]);
    final avg = RunConfig.luckySpinSlices.reduce((a, b) => a + b) / 6;
    expect(avg, closeTo(14 / 6, 1e-9));
    expect(LuckySpinConfig.sliceColors.map((c) => c.toARGB32()), [
      0xFFEC008C,
      0xFFFFB529,
      0xFF2F80FF,
      0xFF8E5CFF,
      0xFFFF7A1A,
      0xFF2EBD6B,
    ]);
    expect(LuckySpinConfig.radius, 24);
    expect(LuckySpinConfig.above, 36);
    expect(LuckySpinConfig.postWidth, 3);
    expect(LuckySpinConfig.spin, 7);
    expect(LuckySpinConfig.decel, 8);
    // ≈ 0.9 s to stop from 7 rad/s at 8 rad/s².
    expect(LuckySpinConfig.spin / LuckySpinConfig.decel, closeTo(.9, .03));
  });

  test('§5.24 the slice under the pointer (mock idxOf)', () {
    const seg = 2 * math.pi / 6;
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 - (i + .5) * seg;
      expect(LuckySpinHoopKind.sliceAt(a), i);
      expect(LuckySpinHoopKind.sliceAt(a + 4 * math.pi), i);
    }
  });

  late AnalyticsSpy spy;
  for (final seed in [2, 13, 40]) {
    FlameTester<FlappySpikesGame>(() {
      spy = AnalyticsSpy();
      return createRunTestGame(worldHeight: 711, services: spy, seed: seed);
    }, gameSize: Vector2(320, 711)).testGameWidget(
      '§3.25 the wheel spins while approaching, slows after the pass, stops '
      '≈ 0.9 s later on the pre-rolled slice and pays it at once '
      '(lucky_spin), banner in the slice colour (seed $seed)',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: 15,
          force: [ElementId.luckySpin],
        );
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final sfx = sfxLog(game);
        expect(
          await flyUntil(
            game,
            (_) => firstHoopOf(game, HoopKindId.luckySpin) != null,
          ),
          isTrue,
        );
        final h = firstHoopOf(game, HoopKindId.luckySpin)!;
        final prize = h.plan.extra! as SpinPrize;
        expect(RunConfig.luckySpinSlices[prize.slice], prize.coins);
        final wheel = LuckySpinHoopKind.wheelOf(h)!;
        // Spinning on approach (≈ 7 rad/s).
        final a0 = wheel.angle;
        await flyUntil(game, (_) => false, maxSeconds: .5);
        final rate = (wheel.angle - a0) / .5;
        expect(rate, closeTo(7, 1.5));
        expect(await passHoopAt(game, h), isTrue);
        expect(wheel.released, isTrue);
        expect(sfx, contains('luckyWhoosh'));
        expect(wheel.stopSeconds, closeTo(.875, .2));
        var t = 0.0;
        await flyUntil(game, (_) {
          if (!wheel.stopped) t += 1 / 60;
          return wheel.stopped;
        }, maxSeconds: 3);
        expect(run.dying, isFalse);
        expect(wheel.stopped, isTrue);
        expect(t, closeTo(.9, .25));
        expect(LuckySpinHoopKind.sliceAt(wheel.angle), prize.slice);
        final paid = events
            .whereType<CoinsEarned>()
            .where((e) => e.source == CoinSource.luckySpin);
        expect(paid.single.amount, prize.coins);
        final banner = RunHud.of(run)!.banners.current! as ElementBanner;
        expect(banner.text, '+${prize.coins}');
        expect(banner.color, LuckySpinConfig.sliceColors[prize.slice]);
        expect(sfx, containsAll(['luckyTick', 'luckyWin']));
        expect(
          spy.events.where((e) => e.$1 == 'lucky_spin').single.$2,
          {'prize': prize.coins},
        );
        expect(game.storage.metElements, contains('lucky_spin'));
      },
    );
  }
}
