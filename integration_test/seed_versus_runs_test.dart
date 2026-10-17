// PRD-2.2 §13.5 seeding (orchestrator only, AFTER the functions deploy and
// the pool conversion): the e2e test account records about 5 real 2.2 runs
// — the hoop-aware autopilot flies real runs (different seeds, lengths and
// so scores / levels) through the real run code, and each finished run's
// summary is uploaded through the real backend as a new best, so the
// server files them into rising levels. Never a fake opponent: every
// timeline is a recorded run.
//
//   flutter test integration_test/seed_versus_runs_test.dart \
//     -d 38300DLJH004SD --dart-define=FS_SEED_VERSUS=true \
//     --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered token>
//
// Without FS_SEED_VERSUS (or off Android) every test is skipped.
import 'dart:io';
import 'dart:math';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/firebase_options.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/firebase_versus_backend.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers.dart';

/// `--dart-define=FS_SEED_VERSUS=true`: record and upload the seed runs.
const bool kSeedVersus = bool.fromEnvironment('FS_SEED_VERSUS');

/// The runs: (seed, hoops to fly). Rising lengths → rising points, so each
/// upload is a new best (never held by the 3-a-day limit) and lands one
/// level higher.
const List<(int, int)> kSeedRuns = [
  (101, 8),
  (102, 16),
  (103, 28),
  (104, 45),
  (105, 70),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final enabled = kSeedVersus && !kIsWeb && Platform.isAndroid;

  FirebaseVersusBackend? backend;
  String name = 'Flappy';
  final summaries = <RunSummary>[];

  Future<FirebaseVersusBackend> ensureBackend() async {
    final existing = backend;
    if (existing != null) return existing;
    // A separate named app: its own anonymous test account, so seeding never
    // signs the device owner's game out (their runs must stay opponents for
    // them: the matcher skips the player's own uid).
    final seedApp = await Firebase.initializeApp(
      name: 'seed',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAppCheck.instanceFor(app: seedApp).activate(
      providerAndroid: AndroidDebugProvider(
        debugToken: kAppCheckDebugToken.isEmpty ? null : kAppCheckDebugToken,
      ),
    );
    final b = FirebaseVersusBackend(app: seedApp);
    final uid = await b.start().timeout(const Duration(seconds: 30));
    name = generateNickname(Random(uid.hashCode));
    debugPrint('SEED uid $uid as $name');
    return backend = b;
  }

  for (final (i, (seed, hoops)) in kSeedRuns.indexed) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: seed),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'PRD-2.2 §13.5 seed run ${i + 1}: seed $seed, $hoops hoops, uploaded',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        if (!enabled) {
          markTestSkipped('seeding is opt-in (FS_SEED_VERSUS, Android)');
          return;
        }
        final run = await startRun(game);
        // The bot flies; god mode only keeps a rare bot slip from ending
        // the run before its length (the recorded timeline is real).
        game.runDebug.god = true;
        final flight = await flyRun(game, untilHoops: hoops, maxSeconds: 900);
        game.runDebug.god = false;
        expect(flight.hoops, greaterThanOrEqualTo(hoops));
        final s = run.endRun();
        expect(s.timeline.points, s.score);
        summaries.add(s);
        final b = await tester.runAsync(ensureBackend);
        final now = DateTime.now().toUtc();
        final entry = RunEntry.fromSummary(
          s,
          runId: 'seed-${now.millisecondsSinceEpoch}-$seed',
          name: name,
          ts: now,
        );
        expect(entry.fitsLimits, isTrue);
        final day =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
        final write = await tester.runAsync(
          () => b!
              .writeRun(
                QueuedRun(entry, newBest: true),
                PlayerFields(
                  name: name,
                  platform: 'android',
                  look: Look.defaults,
                  uploadsDay: day,
                  uploadsCount: 0,
                ),
              )
              .timeout(const Duration(seconds: 30)),
        );
        expect(write, UploadWrite.done);
        debugPrint(
          'SEED run ${i + 1}: ${s.score} points, ${s.hoopsPassed} hoops, '
          '${s.timeline.entries} entries, level ${levelFor(s.score)}',
        );
      },
    );
  }
}
