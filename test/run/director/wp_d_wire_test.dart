import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('WP-D3 the rolling four-slot hazard ledger holds on every screen', () {
    const heights = [568.0, 711.0, 730.0];
    final budget = HazardBudget();

    for (final height in heights) {
      for (var seed = 1; seed <= 200; seed++) {
        final director = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet(),
        );
        final window = <SlotPlan>[];
        for (var slot = 0; slot < 400; slot++) {
          final plan = director.nextSlot(DirectorContext.open(height));
          director.nextGap(DirectorContext.open(height), plan);
          window.add(plan);
          if (window.length > HazardBudget.windowSize) {
            window.removeAt(0);
          }
          final forced = window.any((entry) => entry.forced);
          final sum = window.fold(
            0.0,
            (total, entry) => total + entry.hazardCost,
          );
          expect(plan.hazardCost, greaterThanOrEqualTo(0));
          if (!forced) {
            expect(
              sum,
              lessThanOrEqualTo(budget.budgetAt(plan.index) + 1e-9),
              reason:
                  'height $height seed $seed hoop ${plan.index} '
                  'sum $sum',
            );
          }
        }
      }
    }
  });

  test('WP-D3 forced slots are counted but exempt from the budget', () {
    final director = RunDirector(
      seed: 54,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    final first = director.nextSlot(DirectorContext.open(711));
    director.debugForce(ElementId.saw);
    final forced = director.nextSlot(DirectorContext.open(711));

    expect(first.hazardCost, 0);
    expect(forced.forced, isTrue);
    expect(forced.kind, HoopKindId.saw);
    expect(forced.hazardCost, 2);
    expect(first.hazardCost + forced.hazardCost, greaterThan(0));
  });

  test('WP-D4 revive, squeeze-end and ride-end calm stretches are exact', () {
    RunDirector make() => RunDirector(
      seed: 54,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );

    var director = make();
    for (var slot = 0; slot < 10; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), plan);
    }
    director.onRevive();
    for (var slot = 0; slot < 4; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      expect(plan.calm, slot < 3);
      if (slot < 3) expect(plan.kind, HoopKindId.normal);
      expect(plan.motion, isNull);
      expect(plan.tiltDeg.abs(), lessThanOrEqualTo(10));
      expect(plan.opening, closeTo(RunConfig.openingFor(plan.index), 1e-9));
    }
    expect(director.allowsSqueezeWarning(10), isFalse);
    expect(director.allowsSqueezeWarning(11), isFalse);
    expect(director.allowsSqueezeWarning(12), isFalse);

    director = make();
    for (var slot = 0; slot < 10; slot++) {
      director.nextSlot(DirectorContext.open(711));
    }
    director.onSqueezeEnded(9);
    for (var slot = 0; slot < 3; slot++) {
      expect(
        director.nextSlot(DirectorContext.open(711)).calm,
        slot < 2,
        reason: 'squeeze slot $slot',
      );
    }

    director = make();
    for (var slot = 0; slot < 10; slot++) {
      director.nextSlot(DirectorContext.open(711));
    }
    director.onRideEnd(RideKind.portal);
    for (var slot = 0; slot < 3; slot++) {
      expect(
        director.nextSlot(DirectorContext.open(711)).calm,
        slot < 2,
        reason: 'ride slot $slot',
      );
    }
  });

  test('WP-D4 periodic calm follows the schedule and minimum spacing', () {
    final starts = <int>[];
    SlotPlan? previous;
    final director = RunDirector(
      seed: 17,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    for (var slot = 0; slot < 240; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), plan);
      if (plan.calm && (previous == null || !previous.calm)) {
        starts.add(plan.index);
      }
      if (plan.calm) {
        expect(plan.kind, HoopKindId.normal);
        expect(plan.motion, isNull);
        expect(plan.tiltDeg.abs(), lessThanOrEqualTo(10));
        if (previous != null) {
          final median =
              LayoutConfig.bandFor(plan.index).dy.$1 * RunConfig.dyRefBand;
          expect(
            (plan.centreY - previous.centreY).abs(),
            lessThanOrEqualTo(median + 1e-9),
          );
        }
      }
      previous = plan;
    }

    expect(starts.first, inInclusiveRange(30, 34));
    final expected = [
      starts.first,
      starts.first + 36,
      starts.first + 36 + 43,
      starts.first + 36 + 43 + 52,
      starts.first + 36 + 43 + 52 + 55,
    ];
    for (var index = 0; index < expected.length; index++) {
      expect(starts[index], closeTo(expected[index], 4));
    }
    for (var index = 1; index < starts.length; index++) {
      expect(starts[index] - starts[index - 1], greaterThanOrEqualTo(12));
    }
  });

  // region P26-D-TESTS
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'WP-D5 the real squeeze feature preserves nonzero indices on revive',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      final feature = run.features.whereType<SqueezeFeature>().single;
      for (final index in [0, 1, 3]) {
        for (final phase in SqueezePhase.values) {
          run.state.squeeze
            ..index = index
            ..phase = phase;
          feature.onRevive();
          expect(run.state.squeeze.index, index, reason: '$phase index=$index');
        }
      }
    },
  );

  test('WP-D6 first-meet headlines reserve the next eight hoops', () {
    for (var seed = 1; seed <= 40; seed++) {
      final director = RunDirector(
        seed: seed,
        startHoopIndex: ElementId.bullseye.firstPossible!,
        enabled: {ElementId.normalHoop, ElementId.bullseye},
        met: {ElementId.normalHoop},
      );
      SlotPlan? firstMeet;
      for (var slot = 0; slot < 20; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        if (plan.kind == HoopKindId.bullseye) {
          firstMeet = plan;
          break;
        }
      }
      expect(
        firstMeet,
        isNotNull,
        reason: 'seed=$seed must exercise first-meet',
      );
      expect(director.firstMeet.met, contains(ElementId.bullseye));
      director.onSqueezeEnded(firstMeet!.index - 3);
      expect(director.allowsSqueezeWarning(firstMeet.index + 7), isFalse);
      expect(director.allowsSqueezeWarning(firstMeet.index + 8), isTrue);
    }
  });

  test(
    'WP-D6 D1 rows count first meets as introductions, once per element',
    () {
      // PRD §8.3 decision 15: met elements were already introduced; switch
      // and moving first meets own their row, while never-met saw queues it.
      for (final (row, element) in [
        (15, ElementId.switchRing),
        (25, ElementId.movingRing),
        (30, ElementId.saw),
      ]) {
        for (final enabled in [false, true]) {
          for (final met in [false, true]) {
            final director = RunDirector(
              seed: 54,
              enabled: {ElementId.normalHoop, if (enabled) element},
              met: {ElementId.normalHoop, if (met) element},
            );
            final headlines = <(String, int)>[];
            director.onHeadline = (id, hoop) => headlines.add((id, hoop));
            for (var hoop = 0; hoop < 60; hoop++) {
              final slot = director.nextSlot(DirectorContext.open(711));
              director.nextGap(DirectorContext.open(711), slot);
            }
            if (met || !enabled) {
              expect(headlines, isEmpty);
            } else {
              expect(headlines, hasLength(1));
              expect(
                headlines.single.$1,
                element.firstMeet ? 'first-meet' : 'introduction',
              );
              expect(headlines.single.$2, inInclusiveRange(row, row + 5));
            }
          }
        }
      }
    },
  );

  test('WP-D6 moving and saw introductions wait eight hoops apart', () {
    final director = RunDirector(
      seed: 54,
      startHoopIndex: 25,
      enabled: {ElementId.normalHoop, ElementId.movingRing, ElementId.saw},
      met: {ElementId.normalHoop},
    );
    final headlines = <(String, int)>[];
    director.onHeadline = (id, hoop) => headlines.add((id, hoop));
    for (var hoop = 25; hoop <= 40; hoop++) {
      final slot = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), slot);
    }
    // PRD §8.3 decision 15: saw's row at 30 waits for the window at 33.
    expect(headlines, [('first-meet', 25), ('introduction', 33)]);
  });

  test(
    'WP-D6 moving first meet owns its introduction without a second claim',
    () {
      final director = RunDirector(
        seed: 16,
        enabled: {ElementId.normalHoop, ElementId.movingRing},
        met: {ElementId.normalHoop},
      );
      final headlines = <(String, int)>[];
      director.onHeadline = (id, hoop) => headlines.add((id, hoop));
      for (var hoop = 0; hoop < 60; hoop++) {
        final slot = director.nextSlot(DirectorContext.open(711));
        director.nextGap(DirectorContext.open(711), slot);
      }
      expect(headlines, hasLength(1));
      expect(headlines.single.$1, 'first-meet');
      expect(headlines.single.$2, inInclusiveRange(25, 30));
    },
  );

  test('WP-D6 pending introductions preserve a squeeze reservation', () {
    final director = RunDirector(
      seed: 54,
      startHoopIndex: 25,
      enabled: {ElementId.normalHoop, ElementId.movingRing, ElementId.saw},
      met: ElementId.values.toSet()..remove(ElementId.saw),
    );
    final introductions = <int>[];
    director.onHeadline = (id, hoop) {
      if (id == 'introduction') introductions.add(hoop);
    };
    director.onSqueezeWarning(24);
    expect(director.allowsSqueezeWarning(25), isFalse);
    // Move calm beyond the reservation probe without changing headlines.
    director.onSqueezeEnded(22);
    for (var hoop = 25; hoop <= 48; hoop++) {
      final slot = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), slot);
      if (hoop == 32) {
        expect(director.allowsSqueezeWarning(32), isTrue);
        director.onSqueezeWarning(32);
      }
    }
    expect(introductions, [40]);
  });
  // endregion

  test('WP-D6 all five headline families stay eight hoops apart', () {
    const bonusKinds = {
      HoopKindId.pair,
      HoopKindId.luckySpin,
      HoopKindId.fever,
    };
    final families = <String>{};
    // Keep the original every-slot warning stress and add realistic gaps so
    // deferred introductions also get an opportunity to claim a window.
    for (final warningEvery in [0, 40]) {
      for (var seed = 1; seed <= 40; seed++) {
        final director = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet()
            ..removeAll({ElementId.bullseye, ElementId.saw}),
        );
        var nextWarning = warningEvery == 0 ? 25 : 35;
        final headlines = <(String, int)>[];
        director.onHeadline = (id, hoop) {
          if (id == 'first-meet' || id == 'introduction') {
            headlines.add((id, hoop));
          }
        };
        for (var slot = 0; slot < 240; slot++) {
          final plan = director.nextSlot(DirectorContext.open(711));
          final gap = director.nextGap(DirectorContext.open(711), plan);
          if (plan.kind == HoopKindId.portal || plan.cometHang) {
            headlines.add(('ride', plan.index));
          } else if (bonusKinds.contains(plan.kind)) {
            headlines.add(('big-bonus', plan.index));
          } else if (gap.items.any(
            (item) => RunDirector.isBigItem(item.kind),
          )) {
            headlines.add(('big-bonus', gap.index));
          }

          if (plan.index >= nextWarning &&
              director.allowsSqueezeWarning(plan.index)) {
            headlines.add(('squeeze', plan.index));
            director.onSqueezeWarning(plan.index);
            nextWarning = plan.index + warningEvery;
          }
        }

        families.addAll(headlines.map((headline) => headline.$1));
        for (var left = 0; left < headlines.length; left++) {
          for (var right = left + 1; right < headlines.length; right++) {
            expect(
              headlines[right].$2 - headlines[left].$2,
              greaterThanOrEqualTo(8),
              reason: 'seed $seed: ${headlines[left]} then ${headlines[right]}',
            );
          }
        }
      }
    }
    expect(
      families,
      containsAll([
        'ride',
        'squeeze',
        'big-bonus',
        'first-meet',
        'introduction',
      ]),
    );
  });

  test('WP-D filters keep timing rolls off the layout stream', () {
    List<(SlotPlan, GapPlan)> course(RunDirector director) {
      final out = <(SlotPlan, GapPlan)>[];
      for (var slot = 0; slot < 80; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        out.add((plan, director.nextGap(DirectorContext.open(711), plan)));
      }
      return out;
    }

    final plain = course(
      RunDirector(
        seed: 5,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      ),
    );
    final mixedDirector = RunDirector(
      seed: 5,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    final mixed = <(SlotPlan, GapPlan)>[];
    for (var slot = 0; slot < 80; slot++) {
      mixedDirector.rollSqueezeAt(slot.toDouble(), hoop: slot);
      mixedDirector.rollBigHoopsDuration();
      mixedDirector.rollPuzzleBonus();
      final plan = mixedDirector.nextSlot(DirectorContext.open(711));
      mixed.add((plan, mixedDirector.nextGap(DirectorContext.open(711), plan)));
    }

    expect(mixed.map((entry) => entry.$1), plain.map((entry) => entry.$1));
    expect(mixed.map((entry) => entry.$2), plain.map((entry) => entry.$2));
  });

  test('WP-D wiring is deterministic for the same seed', () {
    RunDirector make() => RunDirector(
      seed: 1234,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );

    List<(SlotPlan, GapPlan)> course(RunDirector director) {
      final out = <(SlotPlan, GapPlan)>[];
      for (var slot = 0; slot < 240; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        out.add((plan, director.nextGap(DirectorContext.open(711), plan)));
      }
      return out;
    }

    final first = course(make());
    final second = course(make());
    expect(first.map((entry) => entry.$1), second.map((entry) => entry.$1));
    expect(first.map((entry) => entry.$2), second.map((entry) => entry.$2));
  });
}
