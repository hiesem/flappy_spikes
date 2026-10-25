import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/run/director/calm_schedule.dart';

final class FixedDrawRandom implements Random {
  FixedDrawRandom(this.value, this.draws);

  final int value;
  final List<int> draws;

  @override
  int nextInt(int max) {
    draws.add(max);
    return value;
  }

  @override
  double nextDouble() => throw UnsupportedError('not used');

  @override
  bool nextBool() => throw UnsupportedError('not used');
}

void main() {
  test('periodic calm stretches follow the growing interval', () {
    final schedule = CalmSchedule(FixedDrawRandom(2, []));
    final starts = <int>[];
    var slots = 0;

    for (var hoop = 0; hoop <= 230; hoop++) {
      if (schedule.remainingAt(hoop) == 3) {
        starts.add(hoop);
        schedule.startAt(hoop, 3);
      }
      if (schedule.isCalm(hoop)) slots++;
    }

    expect(starts, [32, 68, 111, 163, 218]);
    expect(slots, starts.length * 3);

    for (var index = 1; index < starts.length; index++) {
      expect(starts[index] - starts[index - 1], greaterThanOrEqualTo(12));
    }
  });

  test('event triggers create the specified calm lengths', () {
    final schedule = CalmSchedule(Random(7));

    schedule.onRevive(20);
    expect(
      [for (var hoop = 20; hoop < 23; hoop++) schedule.remainingAt(hoop)],
      [3, 2, 1],
    );
    expect(schedule.isCalm(23), isFalse);

    schedule.onSqueezeEnded(40);
    expect(
      [for (var hoop = 40; hoop < 42; hoop++) schedule.remainingAt(hoop)],
      [2, 1],
    );

    schedule.onRideEnded(60);
    expect(
      [for (var hoop = 60; hoop < 62; hoop++) schedule.remainingAt(hoop)],
      [2, 1],
    );
  });

  test('a revive always calms and suppresses nearby event calms', () {
    final schedule = CalmSchedule(Random(7));

    schedule.onSqueezeEnded(20);
    schedule.onRevive(24);
    expect(schedule.remainingAt(24), 3);
    expect(schedule.remainingAt(26), 1);

    schedule.onRideEnded(30);
    expect(schedule.isCalm(30), isFalse);
    expect(schedule.isCalm(31), isFalse);
  });

  test('a calm or ride resets the periodic timer', () {
    final calm = CalmSchedule(FixedDrawRandom(2, []));
    calm.onSqueezeEnded(10);
    calm.startAt(10, 2);
    var calmDue = -1;
    for (var hoop = 12; hoop <= 60; hoop++) {
      if (calm.dueAt(hoop)) {
        calmDue = hoop;
        break;
      }
    }
    expect(calmDue, 46);

    final ride = CalmSchedule(FixedDrawRandom(2, []));
    ride.onRideStart(12);
    var rideDue = -1;
    for (var hoop = 13; hoop <= 60; hoop++) {
      if (ride.dueAt(hoop)) {
        rideDue = hoop;
        break;
      }
    }
    expect(rideDue, 48);
  });

  test('squeeze warnings cannot start inside a calm stretch', () {
    final schedule = CalmSchedule(Random(7));
    schedule.onRevive(20);

    for (var hoop = 20; hoop < 23; hoop++) {
      expect(schedule.allowsSqueezeWarning(hoop), isFalse);
    }
    expect(schedule.allowsSqueezeWarning(23), isTrue);
  });

  test('event outcomes do not change the timing-stream draw count', () {
    final plainDraws = <int>[];
    final eventDraws = <int>[];
    CalmSchedule(FixedDrawRandom(4, plainDraws));
    final eventSchedule = CalmSchedule(FixedDrawRandom(4, eventDraws));
    eventSchedule.onRevive(10);
    eventSchedule.onRideEnded(40);

    expect(eventDraws, [5]);
    expect(plainDraws, [5]);
  });

  test('the no-argument schedule is deterministic', () {
    final first = CalmSchedule();
    final starts = <int>[];
    final calmHoops = <bool>[];
    for (var hoop = 0; hoop <= 230; hoop++) {
      if (first.remainingAt(hoop) == 3) {
        starts.add(hoop);
        first.startAt(hoop, 3);
      }
      calmHoops.add(first.isCalm(hoop));
    }

    for (var run = 0; run < 50; run++) {
      final schedule = CalmSchedule();
      final otherStarts = <int>[];
      final otherCalmHoops = <bool>[];
      for (var hoop = 0; hoop <= 230; hoop++) {
        if (schedule.remainingAt(hoop) == 3) {
          otherStarts.add(hoop);
          schedule.startAt(hoop, 3);
        }
        otherCalmHoops.add(schedule.isCalm(hoop));
      }
      expect(otherStarts, starts, reason: 'run $run');
      expect(otherCalmHoops, calmHoops, reason: 'run $run');
    }

    expect(starts, [32, 68, 111, 163, 218]);
    expect(CalmSchedule().dueAt(31), isFalse);
  });
}
