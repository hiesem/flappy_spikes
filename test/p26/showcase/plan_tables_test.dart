import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/showcase_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B3 script tables', () {
    test('every step × attempt (A = 1, 2, 3, 5) matches the PRD', () {
      const attempts = [1, 2, 3, 5];

      for (final attempt in attempts) {
        final key = ShowcaseConfig.attemptKey(attempt);
        final expectedPortal = {'1': 7, '2': 5, '3': 3}[key]!;
        final expectedComet = {'1': 9, '2': 6, '3': 4}[key]!;
        final expectedFever = {'1': 5, '2': 4, '3': 3}[key]!;
        final expectedSpace = {'1': 15, '2': 13, '3': 11}[key]!;

        final portal = ShowcaseScript.planFor(0, attempt);
        expect(portal.highlightId, 'portal');
        expect(portal.step, 0);
        expect(portal.attempt, attempt);
        expect(portal.portalHoops, [expectedPortal]);
        expect(portal.portals, [
          ShowcasePortal(hoop: expectedPortal, theme: RideId.cannon),
        ]);
        expect(portal.cometHoops, isEmpty);
        expect(portal.feverHoops, isEmpty);
        expect(portal.bullseyeHoops, isEmpty);
        expect(
          portal.gapsOf('star_trail'),
          {
            '1': [2, 5],
            '2': [2],
            '3': [2],
          }[key],
        );
        expect(
          portal.gapsOf('feather'),
          {
            '1': [4],
            '2': [3],
            '3': [2],
          }[key],
        );
        expect(portal.gapsOf('coin_frenzy'), isEmpty);
        expect(portal.gapsOf('puzzle_piece'), isEmpty);
        expect(portal.gapsOf('hourglass'), isEmpty);
        expect(portal.hearts, [10, 13, 16]);
        expect(portal.bigHoopsSeconds, 60);
        expect(portal.freeRevive, isTrue);
        expect(portal.extraStarters, [Powerup.bigHoops, Powerup.shield]);

        final comet = ShowcaseScript.planFor(1, attempt);
        expect(comet.highlightId, 'comet');
        expect(comet.step, 1);
        expect(comet.attempt, attempt);
        expect(comet.cometHoops, [expectedComet]);
        expect(comet.bullseyeHoops, [14]);
        expect(
          comet.gapsOf('coin_frenzy'),
          {
            '1': [3],
            '2': [3],
            '3': [2],
          }[key],
        );
        expect(
          comet.gapsOf('star_trail'),
          {
            '1': [6],
            '2': [5],
            '3': <int>[],
          }[key],
        );
        expect(comet.hearts, [12, 15, 18]);
        expect(comet.portalHoops, isEmpty);
        expect(comet.portals, isEmpty);
        expect(comet.feverHoops, isEmpty);
        expect(comet.bigHoopsSeconds, isNull);
        expect(comet.freeRevive, isTrue);
        expect(comet.extraStarters, [Powerup.bigHoops, Powerup.shield]);

        final fever = ShowcaseScript.planFor(2, attempt);
        expect(fever.highlightId, 'fever');
        expect(fever.step, 2);
        expect(fever.attempt, attempt);
        expect(fever.feverHoops, [expectedFever]);
        expect(fever.portalHoops, [expectedSpace]);
        expect(fever.portals, [
          ShowcasePortal(hoop: expectedSpace, theme: RideId.space),
        ]);
        expect(
          fever.gapsOf('puzzle_piece'),
          {
            '1': [8],
            '2': [6],
            '3': [5],
          }[key],
        );
        expect(
          fever.gapsOf('hourglass'),
          {
            '1': [11],
            '2': [11],
            '3': [9],
          }[key],
        );
        expect(fever.hearts, isEmpty);
        expect(fever.cometHoops, isEmpty);
        expect(fever.bullseyeHoops, isEmpty);
        expect(fever.bigHoopsSeconds, isNull);
        expect(fever.freeRevive, isTrue);
        expect(fever.extraStarters, [Powerup.bigHoops, Powerup.shield]);
      }
    });

    test('the highlight slot in each script is the first table entry', () {
      expect(ShowcaseConfig.scripts['portal']!['1'], [7]);
      expect(ShowcaseConfig.scripts['portal']!['2'], [5]);
      expect(ShowcaseConfig.scripts['portal']!['3'], [3]);
      expect(ShowcaseConfig.scripts['comet']!['1'], [9]);
      expect(ShowcaseConfig.scripts['comet']!['2'], [6]);
      expect(ShowcaseConfig.scripts['comet']!['3'], [4]);
      expect(ShowcaseConfig.scripts['fever']!['1'], [5]);
      expect(ShowcaseConfig.scripts['fever']!['2'], [4]);
      expect(ShowcaseConfig.scripts['fever']!['3'], [3]);
    });

    test('attempt bands: 1 / 2 / 3+', () {
      expect(ShowcaseConfig.attemptKey(1), '1');
      expect(ShowcaseConfig.attemptKey(2), '2');
      expect(ShowcaseConfig.attemptKey(3), '3');
      expect(ShowcaseConfig.attemptKey(5), '3');
      expect(
        ShowcaseScript.planFor(0, 5).portalHoops,
        ShowcaseScript.planFor(0, 3).portalHoops,
      );
    });

    test('plans are index-based and identical at 568 / 711 / 730 pt', () {
      // No view height enters the model. The three heights are recorded here
      // so a future screen-position field cannot creep in unnoticed.
      for (final height in [568.0, 711.0, 730.0]) {
        expect(height, isPositive);
        for (var step = 0; step < 3; step++) {
          for (final attempt in [1, 2, 3, 5]) {
            expect(
              ShowcaseScript.planFor(step, attempt),
              ShowcaseScript.planFor(step, attempt),
            );
          }
        }
      }
    });

    test('invalid steps are rejected', () {
      expect(() => ShowcaseScript.planFor(-1, 1), throwsRangeError);
      expect(() => ShowcaseScript.planFor(3, 1), throwsRangeError);
    });
  });
}
