// PRD-2.3 §10.3 / §10.1 (S8-07): the first-run top warning band never sits
// under the HUD controls (heart, pause, versus bar and name chips), and the
// pause button stays usable while the instructions show.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/first_run_config.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/hud/first_run_hint.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

OpponentRun _opponent() => OpponentRun(
  uid: 'u1',
  name: 'BrightOwl123',
  score: 3,
  best: 9,
  level: 1,
  timeline: RunTimeline()
    ..addPoint(1)
    ..addPoint(2)
    ..addPoint(3)
    ..end(4),
);

Rect _rectOf(PositionComponent c) => Rect.fromLTWH(
  c.absolutePosition.x,
  c.absolutePosition.y,
  c.size.x,
  c.size.y,
);

void main() {
  for (final h in [568.0, 711.0]) {
    for (final vs in [false, true]) {
      final versus = vs
          ? FakeVersusService(pool: [_opponent()])
          : NoopVersusService();
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, versus: versus),
        gameSize: Vector2(Config.worldWidth, h),
      ).testGameWidget(
        'S8-07 §10.3 the top band clears the HUD '
        '(${vs ? 'versus' : 'solo'}, ${h.round()})',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
          if (vs) await g.versus.prefetch();
        },
        verify: (g, _) async {
          final run = await openRun(g);
          expect(run.setup.opponent != null, vs);
          final hint = g.firstRunHint!;
          expect(hint.mode, FirstRunHintMode.firstRun);
          for (var i = 0; i < 30; i++) {
            g.update(1 / 60);
          }
          final band = hint.topBandRect!;
          final hud = g.runHud!;
          final controls = [
            _rectOf(hud.heart),
            _rectOf(hud.pauseButton),
          ];
          if (vs) {
            controls.add(
              const Rect.fromLTWH(
                0,
                HudConfig.rowTop,
                320,
                HudConfig.chipTop + HudConfig.chipHeight - HudConfig.rowTop,
              ),
            );
          }
          for (final c in controls) {
            expect(band.overlaps(c), isFalse, reason: '$band vs $c');
            expect(
              band.top,
              greaterThanOrEqualTo(c.bottom + FirstRunConfig.warningHudGap),
            );
          }
          // Still in the upper part, clear of the flap path (peak 66 above
          // the middle).
          expect(band.bottom, lessThan(g.viewHeight / 2 - 66));
          // The pause button works while the instructions show.
          final pause = hud.pauseButton;
          expect(pause.containsLocalPoint(pause.size / 2), isTrue);
          pause.onTapDown(createTapDownEvents(game: g));
          expect(g.state, GameState.paused);
        },
      );
    }
  }
}
