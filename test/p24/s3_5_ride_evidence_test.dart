import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'backdrop_harness.dart';

/// PRD-2.4 §3.5 WP-R visual check (best-effort, evidence/wpR): one contact
/// sheet per portal ride, 6 frames a row, read left to right: the ride at
/// 0.6 s (scene fading in) and 4 s, the exit's middle, then the launch
/// every 0.25 s after it (τ 0 … 4.75: reveal, glide, landing at τ 4.15,
/// settle end at τ 4.75). Compare with `ride_landings.html` at the same
/// moments (evidence/wpR/proto_RIDE.png).
const List<double> kTaus = [
  0, .25, .5, .75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75,
  4, 4.25, 4.5, 4.75,
];

void main() {
  const h = 568.0;
  for (final id in RideId.values) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        seed: 5,
        worldHeight: h,
        prefs: {
          'firstRunHintSeen': true,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'ride evidence $id',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        if (!Directory(kBackdropEvidence).existsSync()) return;
        g.runDebug.god = true;
        final run = await startRun(g, startHoopIndex: 25, ride: id);
        for (var i = 0; i < 3; i++) {
          run.debugPass(perfect: true);
        }
        final f = run.features.whereType<PortalRideFeature>().single;
        final bot = Autopilot(run);
        final shots = <ui.Picture>[];

        Future<void> until(bool Function(PortalRide? r) done) async {
          for (var i = 0; i < 60 * 40 && !done(f.ride); i++) {
            if (f.ride == null && bot.shouldFlap()) g.onScreenTap();
            g.update(1 / 60);
            if (i % 10 == 0) await flushAndMount(g);
          }
          await flushAndMount(g);
        }

        void shot() {
          // resize right before rendering (the harness reverts resizes)
          g.onGameResize(Vector2(320, h));
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.drawRect(const ui.Rect.fromLTWH(0, 0, 320, h), ui.Paint()..color = g.backgroundColor());
          g.render(c);
          shots.add(rec.endRecording());
        }

        double tau(PortalRide r) => switch (r.phase) {
          RidePhase.fly => r.view.ft,
          RidePhase.glide => 1.65 + r.view.gt,
          RidePhase.done => 99,
          _ => -1,
        };

        await until((r) => r != null && r.view.rt >= .6);
        shot();
        await until((r) => r != null && r.view.rt >= 4);
        shot();
        PortalRide? ride;
        await until((r) {
          if (r != null) ride = r;
          return r != null && r.phase == RidePhase.exit && r.view.et >= r.theme.exitDuration / 2;
        });
        shot();
        for (final t in kTaus) {
          await until((r) => r == null || tau(r) >= t - 1e-9);
          if (f.ride == null) break;
          shot();
        }
        expect(ride, isNotNull);
        await tester.runAsync(() async {
          const cols = 6;
          final rows = (shots.length / cols).ceil();
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.drawRect(ui.Rect.fromLTWH(0, 0, cols * 324.0, rows * (h + 4)), ui.Paint()..color = const ui.Color(0xFF000000));
          for (var i = 0; i < shots.length; i++) {
            c
              ..save()
              ..translate((i % cols) * 324.0, (i ~/ cols) * (h + 4))
              ..clipRect(const ui.Rect.fromLTWH(0, 0, 320, h))
              ..drawPicture(shots[i])
              ..restore();
          }
          final img = await rec.endRecording().toImage(cols * 324, (rows * (h + 4)).toInt());
          await saveEvidence(img, 'wpR', 'game_${id.name}');
        });
      },
    );
  }
}
