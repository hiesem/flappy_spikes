import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 's3_13_upload_entry_test.dart' show entry;

void main() {
  test(
    'E1 preserves score 3, three non-bests/day, unlimited new bests',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final queue = UploadQueue(
        storage,
        clock: () => DateTime.utc(2026, 10, 27),
      );
      expect(
        await queue.offer(entry(2), newBest: true),
        UploadDecision.lowScore,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          await queue.offer(entry(3, id: 'r$i'), newBest: false),
          UploadDecision.queued,
        );
      }
      expect(
        await queue.offer(entry(3), newBest: false),
        UploadDecision.dailyCap,
      );
      for (var i = 0; i < 5; i++) {
        expect(
          await queue.offer(entry(60 + i, id: 'best$i'), newBest: true),
          UploadDecision.queuedBest,
        );
      }
      expect(queue.pending, hasLength(8));
    },
  );

  test('R4 player doc uses progression level, missing is UNRANKED', () {
    Map<String, Object?> doc([int? level]) => nextPlayerDoc(
      old: null,
      run: entry(5000).toMap(),
      newBest: true,
      name: 'Player',
      platform: 'android',
      look: const Look(),
      uploadsDay: '2026-10-27',
      uploadsCount: 1,
      level: level,
    );
    expect(doc()['level'], 0);
    expect(doc(25)['level'], 25);
    expect(doc(10000)['level'], 9999);
    expect(doc(-1)['level'], 0);
  });
}
