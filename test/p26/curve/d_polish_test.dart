import 'dart:math';

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/calm_schedule.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('D4 every calm tuning key controls the schedule', () {
    final original = TuningValues.current;
    addTearDown(() => TuningValues.current = original);
    TuningValues.current = TuningValues.resolve({
      'calm_every':
          '{"first_min":10,"first_max":12,"mult":2,"cap":25,"len":4,"min_gap":8}',
      'calm_after': '{"revive":5,"squeeze":3,"ride":4}',
    });
    final expectedFirst = 10 + Random(7).nextInt(3);
    final schedule = CalmSchedule(Random(7));
    expect(schedule.dueAt(expectedFirst - 1), isFalse);
    expect(schedule.remainingAt(expectedFirst), 4);
    schedule.startAt(expectedFirst, schedule.remainingAt(expectedFirst));
    expect(schedule.remainingAt(expectedFirst + 3), 1);
    expect(schedule.dueAt(expectedFirst + 4), isFalse);
    expect(schedule.dueAt(expectedFirst + 19), isFalse);
    expect(schedule.remainingAt(expectedFirst + 20), 4);
    schedule.startAt(expectedFirst + 20, 4);
    expect(schedule.dueAt(expectedFirst + 44), isFalse);
    expect(schedule.remainingAt(expectedFirst + 45), 4);

    final events = CalmSchedule(Random(7));
    events.onRevive(0);
    expect(events.remainingAt(0), 5);
    expect(events.remainingAt(4), 1);
    expect(events.dueAt(5), isFalse);
    events.onSqueezeEnded(7); // minimum gap is eight, not the default twelve
    expect(events.dueAt(7), isFalse);
    events.onSqueezeEnded(8);
    expect(events.remainingAt(8), 3);
    expect(events.remainingAt(10), 1);
    expect(events.dueAt(11), isFalse);
    events.onRideEnded(16);
    expect(events.remainingAt(16), 4);
    expect(events.remainingAt(19), 1);
    expect(events.dueAt(20), isFalse);
  });

  test('D4 planned revive slot resets the periodic timer only once', () {
    final schedule = CalmSchedule(Random(7));
    schedule.onRevive(11);
    schedule.includePlannedReviveSlot(10);
    expect(schedule.remainingAt(10), 3);
    expect(schedule.remainingAt(12), 1);
    expect(schedule.dueAt(13), isFalse);
    expect(schedule.dueAt(45), isFalse);
    expect(schedule.remainingAt(46), 3);
  });

  test('D2 final tilts at most 15 degrees retain their random sign', () {
    final sampler = LayoutSampler(DirectorTables.prd2, Random(7));
    for (final tilt in [-45.0, -30.0, -20.0, 20.0, 30.0, 45.0]) {
      for (final dy in [-39.9, -20.0, -.1, .1, 20.0, 39.9]) {
        expect(sampler.alignedTilt(tilt, dy, 45), tilt.sign * 15);
      }
      // Motion's cap can also lower a strong draw to 15 degrees.
      expect(sampler.alignedTilt(tilt, -tilt.sign * 100, 15), tilt.sign * 15);
      expect(sampler.alignedTilt(tilt, -tilt.sign * 100, 45), -tilt);
    }
  });

  test('D4 calm gaps prefer fun pickups over big items', () {
    var calmShields = 0;
    var ordinaryShields = 0;
    var calmItems = 0;
    var ordinaryItems = 0;
    const ctx = DirectorContext(viewHeight: 711, topTooth: 44, floorTooth: 667);
    for (var seed = 0; seed < 2000; seed++) {
      GapPlan gap(bool calm) {
        final director = RunDirector(
          seed: seed,
          startHoopIndex: 100,
          enabled: {
            ElementId.normalHoop,
            ElementId.shield,
            ElementId.starTrail,
          },
          met: ElementId.values.toSet(),
        );
        final slot = director.nextSlot(ctx);
        return director.nextGap(ctx, slot.copyWith(calm: calm));
      }

      final calm = gap(true).items;
      final ordinary = gap(false).items;
      calmItems += calm.length;
      ordinaryItems += ordinary.length;
      calmShields += calm.where((item) => item.kind == ElementId.shield).length;
      ordinaryShields += ordinary
          .where((item) => item.kind == ElementId.shield)
          .length;
    }
    expect(ordinaryItems, greaterThan(100));
    expect(
      calmItems,
      ordinaryItems,
      reason: 'the same gap-chance draw is used',
    );
    expect(ordinaryShields, greaterThan(0));
    expect(calmShields, greaterThan(ordinaryShields * 1.5));
  });

  test('D6 a pending unclaimed squeeze precedes a never-met saw debut', () {
    var sawsAfterClaim = 0;
    for (var seed = 0; seed < 200; seed++) {
      final director = RunDirector(
        seed: seed,
        startHoopIndex: 25,
        enabled: {ElementId.normalHoop, ElementId.saw},
        met: ElementId.values.toSet()..remove(ElementId.saw),
      );
      director.onSqueezeWarning(24);
      expect(director.allowsSqueezeWarning(25), isFalse); // reserve until 30
      director.onRideStart(RideKind.portal); // put periodic calm beyond probe
      director.onRideEnd(RideKind.portal);
      for (var hoop = 25; hoop < 40; hoop++) {
        final slot = director.nextSlot(DirectorContext.open(711));
        director.nextGap(DirectorContext.open(711), slot);
        expect(
          slot.kind,
          isNot(HoopKindId.saw),
          reason: 'seed=$seed hoop=$hoop',
        );
      }
      expect(director.allowsSqueezeWarning(40), isTrue);
      director.onSqueezeWarning(40);
      for (var hoop = 40; hoop < 100; hoop++) {
        final slot = director.nextSlot(DirectorContext.open(711));
        director.nextGap(DirectorContext.open(711), slot);
        if (slot.kind == HoopKindId.saw) {
          expect(hoop, greaterThanOrEqualTo(48));
          sawsAfterClaim++;
          break;
        }
      }
    }
    expect(sawsAfterClaim, greaterThan(100));
  });

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'D4 revive includes the planned-ahead hoop in exactly three calm slots',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      final spawner = run.spawner;
      final ahead = spawner.plannedAhead!;
      expect(ahead.calm, isFalse);
      final spawned = <SlotPlan>[];
      run.events.onAny((event) {
        if (event is HoopSpawned) spawned.add(event.plan);
      });
      run.revive(ReviveKind.coins);
      var previousY = spawner.hoops.last.plan.centreY;
      for (var offset = 0; offset < 4; offset++) {
        final planned = spawner.plannedAhead!;
        // Exercise the real spawner conversion without advancing bird physics.
        run.state.camX = planned.trackX - RunConfig.worldWidth;
        spawner.update(0);
        final actual = spawned.singleWhere(
          (slot) => slot.index == ahead.index + offset,
        );
        expect(actual.calm, offset < 3);
        expect(
          spawner.slotLog.singleWhere((slot) => slot.index == actual.index),
          actual,
        );
        if (offset < 3) {
          expect(actual.kind, HoopKindId.normal);
          expect(actual.motion, isNull);
          expect(actual.tiltDeg.abs(), lessThanOrEqualTo(10));
          expect(actual.opening, RunConfig.openingFor(actual.index));
          final median =
              LayoutConfig.bandFor(actual.index).dy.$1 * RunConfig.dyRefBand;
          expect(
            (actual.centreY - previousY).abs(),
            lessThanOrEqualTo(median + 1e-9),
          );
        }
        previousY = actual.centreY;
      }
    },
  );
}
