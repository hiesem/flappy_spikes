import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/bullseye.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c: the Bullseye Ring (PRD-2 §3.24, §5.23).
void main() {
  test('§3.24 the bullseye band is ±12 pt around the ring centre, fixed as '
      'openings shrink (Q63)', () {
    expect(BullseyeConfig.band, 12);
    expect(BullseyeConfig.coins, 2, reason: 'owner 2026-10-13 (was 1; 2.2: 3)');
    for (final opening in [118.0, 100.0, 92.0]) {
      final f = HoopFrame(centre: Vector2(400, 300), opening: opening);
      for (final (dy, hit) in [
        (0.0, true),
        (11.9, true),
        (-12.0, true),
        (12.2, false),
        (-13.0, false),
        (30.0, false),
      ]) {
        expect(
          BullseyeHoopKind.isBullseye(f, Vector2(401, 300 + dy)),
          hit,
          reason: 'opening $opening, dy $dy',
        );
      }
    }
  });

  test('§5.23 target rings 15 / 11 / 7 / 3.5 pt white / red at 62 % width; '
      'band lines from 46 pt before the ring at fg 45 %', () {
    expect(BullseyeConfig.target.map((e) => e.$1), [15, 11, 7, 3.5]);
    expect(BullseyeConfig.target.map((e) => e.$2.toARGB32()), [
      0xFFFFFFFF,
      0xFFFF3B5C,
      0xFFFFFFFF,
      0xFFFF3B5C,
    ]);
    expect(BullseyeConfig.targetSquash, .62);
    expect(BullseyeConfig.guideFrom, 46);
    expect(BullseyeConfig.guideAlpha, .45);
  });

  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 5);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  for (final (dy, hit) in [(0.0, true), (20.0, false)]) {
    tester.testGameWidget(
      hit
          ? '§3.24 a pass with the bird centre in the band is a BULLSEYE: +2 '
                'coins (bullseye), banner, flash, thunk + chord, bullseye_hit'
          : '§3.24 a pass outside the band is a normal pass (no bonus)',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: 6,
          force: [ElementId.bullseye],
        );
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final sfx = sfxLog(game);
        expect(
          await flyUntil(
            game,
            (_) => firstHoopOf(game, HoopKindId.bullseye) != null,
          ),
          isTrue,
        );
        final h = firstHoopOf(game, HoopKindId.bullseye)!;
        expect(h.kind, isA<BullseyeHoopKind>());
        expect(h.kind.usesTierLook, isTrue);
        final scoreBefore = run.state.score;
        expect(await passHoopAt(game, h, dy: dy), isTrue);
        expect(h.takenRing, 0, reason: 'passed, not missed');
        // PRD-2.2 §13.1: a bullseye is a perfect pass (2 points at streak
        // 1) plus the bonus in points (owner 2026-10-13: +2); outside the band
        // at 20 pt it is still perfect (PRD-2.3 §14.3: no rim touch).
        expect(run.state.score, scoreBefore + (hit ? 2 + 2 : 2));
        final bonus = events
            .whereType<CoinsEarned>()
            .where((e) => e.source == CoinSource.bullseye)
            .toList();
        final banner = RunHud.of(run)?.banners.current;
        final names = spy.events.map((e) => e.$1).toList();
        if (hit) {
          expect(bonus.single.amount, 2);
          expect(banner, isA<ElementBanner>());
          expect((banner! as ElementBanner).text, 'BULLSEYE!');
          expect(banner.subtitle, '+2 coins');
          expect(sfx, containsAll(['bullThunk', 'bullChord']));
          expect(names, contains('bullseye_hit'));
          expect(BullseyeHoopKind.flashOf(h), greaterThan(0));
          // The pass itself still pays its +2 (perfect) and shakes.
          expect(
            events.whereType<CoinsEarned>().map((e) => e.source),
            contains(CoinSource.perfect),
          );
          expect(rumbleLog(game), contains(RumbleKind.shake));
        } else {
          expect(bonus, isEmpty);
          expect(sfx, isNot(contains('bullThunk')));
          expect(names, isNot(contains('bullseye_hit')));
        }
        // §3.0.8 it was met on screen.
        expect(game.storage.metElements, contains('bullseye'));
      },
    );
  }
}
