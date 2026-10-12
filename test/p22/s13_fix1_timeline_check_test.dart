import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.2 §13.5 (P22-FIX1, S7-02 / S7-05): the Dart mirror of the server's
/// timeline rules (`RunTimeline.check`) agrees with the shared fixture that
/// `functions/test/timeline.test.ts` runs against `checkRun`.
void main() {
  final fx =
      jsonDecode(
            File('test/fixtures/versus_timeline_v2.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final f in (fx['forged'] as List).cast<Map<String, dynamic>>()) {
    // The sum-vs-score check needs the uploaded score; check() covers the
    // per-entry caps and the gap rule only.
    if (f['score'] != null) continue;
    test(
      '§13.5 forged fixture: ${f['name']} → ${f['expect'] ?? 'accepted'}',
      () {
        final t = RunTimeline(
          cs: (f['deltas'] as List).cast<int>().toList(),
          flags: (f['flags'] as List).cast<int>().toList(),
          values: (f['values'] as List).cast<int>().toList(),
        );
        expect(t.check(), f['expect']);
      },
    );
  }

  test('§13.5 S7-02 a bonus entry does not restart the gap interval', () {
    final t = RunTimeline()
      ..addEntry(2, 2)
      ..addEntry(3.8, 5, flag: PointFlags.bonus)
      ..addEntry(4, 2);
    expect(t.check(), isNull);
    final close = RunTimeline()
      ..addEntry(2, 2)
      ..addEntry(2.5, 5, flag: PointFlags.bonus)
      ..addEntry(2.89, 2);
    expect(close.check(), 'gap');
  });

  test('§13.5 S7-05 bonus cap 80; puzzle completion cap 500', () {
    RunTimeline one(int value, int flag) =>
        RunTimeline()..addEntry(2, value, flag: flag);
    expect(one(80, PointFlags.bonus).check(), isNull);
    expect(one(81, PointFlags.bonus).check(), 'count');
    const puzzle = PointFlags.bonus | PointFlags.puzzle;
    expect(one(500, puzzle).check(), isNull);
    expect(one(501, puzzle).check(), 'count');
  });
}
