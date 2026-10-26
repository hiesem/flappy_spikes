import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/calm_schedule.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/headline_window.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/gen_obf_strings.dart';

void main() {
  test('the PRD-2.6 storage keys are appended in order', () {
    expect(kObfStrings.values.skip(kObfStrings.length - 8).toList(), [
      'ftueSteps',
      'showcaseSeen',
      'showcaseAttempt',
      'showcaseRuns',
      'showcaseDoneAt',
      'installAtMs',
      'bestHoops',
      'pendingFirstMeets',
    ]);
    expect([
      Obf.prefFtueSteps,
      Obf.prefShowcaseSeen,
      Obf.prefShowcaseAttempt,
      Obf.prefShowcaseRuns,
      Obf.prefShowcaseDoneAt,
      Obf.prefInstallAtMs,
      Obf.prefBestHoops,
      Obf.prefPendingFirstMeets,
    ], kObfStrings.values.skip(kObfStrings.length - 8).toList());
  });

  test(
    'the new state round-trips and Delete my data clears run queue state',
    () async {
      SharedPreferences.setMockInitialValues({
        'ftueSteps': 3,
        'showcaseSeen': 5,
        'showcaseAttempt': 2,
        'showcaseRuns': 4,
        'showcaseDoneAt': 6,
        'installAtMs': 123,
        'bestHoops': 17,
        'pendingFirstMeets': [
          '{"element":"saw","hoop":3,"games":1,"forced":true,"survived":false}',
        ],
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.ftueSteps, 3);
      expect(storage.showcaseSeen, 5);
      expect(storage.showcaseAttempt, 2);
      expect(storage.showcaseRuns, 4);
      expect(storage.showcaseDoneAt, 6);
      expect(storage.installAtMs, 123);
      expect(storage.bestHoops, 17);
      expect(storage.pendingFirstMeets, hasLength(1));

      await storage.resetVersusData();
      final prefs = await SharedPreferences.getInstance();
      expect(storage.ftueSteps, 0);
      expect(storage.showcaseSeen, 0);
      expect(storage.showcaseAttempt, 0);
      expect(storage.showcaseRuns, 0);
      expect(storage.showcaseDoneAt, isNull);
      expect(storage.pendingFirstMeets, isEmpty);
      for (final key in [
        Obf.prefFtueSteps,
        Obf.prefShowcaseSeen,
        Obf.prefShowcaseAttempt,
        Obf.prefShowcaseRuns,
        Obf.prefShowcaseDoneAt,
        Obf.prefPendingFirstMeets,
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    },
  );

  // region P26-C3R
  test('PRD-2.6 C3: rating waits for the showcase and two later runs', () {
    // C3R editor call: PRD silent on unfinished showcase; follows C3 intent.
    expect(Config.ratingMinRunsFor(null), 7);
    expect(Config.ratingMinRunsFor(0), 5);
    expect(Config.ratingMinRunsFor(3), 5);
    expect(Config.ratingMinRunsFor(4), 6);
    expect(Config.ratingMinRunsFor(10), 12);
  });

  test('PRD-2.6 C3: rating minimum reads both tuning keys', () {
    final previous = TuningValues.current;
    addTearDown(() => TuningValues.current = previous);
    TuningValues.current = TuningValues.resolve({
      'rate_min_runs': '10',
      'showcase_max_games': '12',
    });
    expect(Config.ratingMinRunsFor(null), 13);
    expect(Config.ratingMinRunsFor(3), 10);
    expect(Config.ratingMinRunsFor(8), 10);
    expect(Config.ratingMinRunsFor(9), 11);

    TuningValues.current = TuningValues.resolve({
      'rate_min_runs': '15',
      'showcase_max_games': '8',
    });
    expect(Config.ratingMinRunsFor(null), 15);
    expect(Config.ratingMinRunsFor(6), 15);
  });
  // endregion

  test('Home moments use the C2 priority order and pass through', () {
    expect(HomeMoment.values, [
      HomeMoment.streakLost,
      HomeMoment.levelUp,
      HomeMoment.streakReward,
      HomeMoment.leaderboardCollect,
      HomeMoment.missionsChest,
      HomeMoment.starRoad,
      HomeMoment.noAds,
      HomeMoment.rating,
    ]);
    var opened = false;
    const PassthroughHomeMoments().show(HomeMoment.rating, () {
      opened = true;
    });
    expect(opened, isTrue);
  });

  test('the wave-1 model defaults and stub modules are inert', () {
    const setup = RunSetup(seed: 1, viewHeight: 711);
    expect(setup.showcase, isNull);
    expect(setup.extraStarters, isEmpty);
    final plan = const SlotPlan(
      index: 0,
      kind: HoopKindId.normal,
      element: ElementId.normalHoop,
      trackX: 0,
      centreY: 0,
      opening: 100,
      advance: 310,
    );
    expect(plan.calm, isFalse);
    expect(plan.hazardCost, 0);
    expect(plan.formation, isNull);

    final copy = plan.copyWith(
      calm: true,
      hazardCost: 2,
      formation: () => FormationId.stairs,
    );
    expect(copy.calm, isTrue);
    expect(copy.hazardCost, 2);
    expect(copy.formation, FormationId.stairs);

    expect(HazardBudget().allows(copy), isTrue);
    expect(CalmSchedule().dueAt(31), isFalse);
    expect(HeadlineWindow().allows('portal', 7), isTrue);
    expect(Formations().nextAt(150), isNull);
  });
}
