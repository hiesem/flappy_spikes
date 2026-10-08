// Pixel 8 reminder smoke (ARCH §7.3, PRD-2 §3.34):
//   flutter test integration_test/reminders_e2e_test.dart \
//     -d 38300DLJH004SD --dart-define=FS_E2E=true
//
// Drives the *real* `flutter_local_notifications` channel on the device:
// permission, the 14 scheduled requests of the 7-day window, and the payload
// each request carries back. The schedule rules themselves are covered by
// `test/services/s3_34_reminders_test.dart` (pure, fake clock).
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WP-4b reminders: permission + the pending 7-day window', (
    tester,
  ) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    E2EHooks.reset();
    // Fixed clock: the plan is laid out for the 7 days after "now" whatever
    // time of day the suite happens to run at.
    E2EHooks.clockOffset = const Duration(days: 1);
    SharedPreferences.setMockInitialValues({'bestScore': 12, 'coins': 250});

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancelAll();

    final store = GameStorage(
      clock: () => DateTime.now().add(E2EHooks.clockOffset),
    );
    await store.load();

    final reminders = LocalReminders(storage: store);
    await reminders.initialize();
    // The device shows the Android 13+ prompt here; either answer is valid,
    // the app must never ask twice (asserted in the pure tests).
    await reminders.requestPermissionIfNeeded();
    await reminders.reschedule();

    final pending = await plugin.pendingNotificationRequests();
    expect(
      pending,
      hasLength(ReminderScheduler.windowSlots),
      reason: 'payloads: ${pending.map((p) => p.payload).toList()}',
    );
    for (final request in pending) {
      final payload = ReminderPayload.decode(request.payload);
      expect(payload, isNotNull, reason: '§3.34 payload on every request');
      expect(payload!.messageNumber, inInclusiveRange(1, 20));
      expect(request.title, isNotEmpty);
      expect(request.body, isNotEmpty);
    }

    // The plan is persisted so the next pause/start continues the rotation.
    expect(store.notifOrder, hasLength(ReminderMessages.count));
    expect(store.notifPosition, ReminderScheduler.windowSlots);
    expect(store.notifLastSent, isNotEmpty);

    await plugin.cancelAll();
    E2EHooks.reset();
  });
}
