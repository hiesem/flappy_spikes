// Opt-in evidence for S6-60 against real emulator rules and the trigger.
// Run only inside firebase emulators:exec --project demo-flappy-spikes.
import 'dart:io';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_emulator_test.dart' as emulator;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This opt-in integration probe needs the real loopback HttpClient.
  HttpOverrides.global = null;
  test(
    'S6-60 real emulators: an offline backlog is paced, nothing is rate-rejected',
    () async {
      expect(
        emulator.enabled,
        isTrue,
        reason: 'FS_EMULATOR_TESTS=1 inside demo emulators required',
      );
      final (uid, token) = await emulator.signUp();
      var now = DateTime.now().toUtc().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage();
      await store.load();
      final queue = UploadQueue(store, clock: () => now);
      for (var day = 0; day < 2; day++) {
        for (var i = 0; i < 3; i++) {
          final run = emulator.clientRun(3, 100, id: 'p45-$day-$i-$uid');
          expect(await queue.offer(run, newBest: false), UploadDecision.queued);
        }
        now = now.add(const Duration(days: 1));
      }
      final statuses = <int>[];
      expect(
        await queue.flush((q) async {
          final status = await emulator.writeRun(
            uid,
            token,
            q.entry,
            newBest: q.newBest,
          );
          statuses.add(status);
          return status == 200 ? UploadWrite.done : UploadWrite.retry;
        }),
        3,
        reason: 'one UTC upload day takes the server\'s three non-best runs',
      );
      expect(
        statuses,
        everyElement(200),
        reason: 'the client documents pass the real rules',
      );
      Map<String, Object?>? rate;
      for (var i = 0; i < 100; i++) {
        // Emulator-only administrator token: the supporting rate collection is
        // deliberately unreadable by clients; never use a production endpoint.
        rate = await emulator.getDoc('versusRate/$uid', 'owner');
        if ((rate?['seen'] as List?)?.length == 3) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        rate?['seen'],
        hasLength(3),
        reason: 'all three trigger invocations finished',
      );
      expect(rate?['count'], 3);
      expect(rate?['last'], containsPair('status', 'accepted'));
      expect(
        queue.pending.length,
        3,
        reason: 'the three runs over the server rate wait for a later day',
      );
    },
    skip: emulator.enabled ? false : 'opt-in: FS_EMULATOR_TESTS=1 in demo emulators',
  );
}
