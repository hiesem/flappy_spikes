import 'dart:convert';
import 'dart:io';

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/director/plans.dart' show RideId;
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.5 §3.6 WP-VERSUS the false-positive gate of the anomaly flags:
/// the hoop-aware autopilot flies real runs (seeds × 568 / 711 pt, and runs
/// with FEVER, Ring Trains, pairs, the chick, comets, portal rides, bonus
/// pickups and the hourglass forced again and again) and their timelines are
/// encoded with the real [RunEntry] encoder. `functions/test/anomaly.test.ts`
/// asserts that none of them raises a flag.
///
/// Regenerate `functions/test/fixtures/honest_runs.json` after a scoring
/// change:
///
///   FS_WRITE_FIXTURES=1 flutter test test/versus/anomaly_fixtures_test.dart
///
/// Without the variable the test only checks the runs (server timeline
/// rules, sane shape) and reports whether the committed file is current.
const _out = 'functions/test/fixtures/honest_runs.json';

class _Case {
  const _Case(
    this.name, {
    this.height = 568,
    this.seed = 7,
    this.force = const [],
    this.ride,
    this.starter = Powerup.none,
    this.chick = false,
    this.god = true,
    this.seconds = 120,
    this.startHoop = 0,
  });

  final String name;
  final double height;
  final int seed;

  /// Re-forced into the next slot / gap whenever the queue runs empty.
  final List<ElementId> force;
  final RideId? ride;
  final Powerup starter;

  /// Gives the bird an egg whenever it has none (5 passes hatch the chick).
  final bool chick;
  final bool god;
  final double seconds;

  /// Starts deep into the run (top scroll speed from hoop 150).
  final int startHoop;
}

const _gapPickups = {
  ElementId.piggy,
  ElementId.jar,
  ElementId.coinFrenzy,
  ElementId.puzzlePiece,
  ElementId.hourglass,
  ElementId.feather,
  ElementId.starTrail,
};

final _cases = <_Case>[
  for (final h in [568.0, 711.0])
    for (final seed in [7, 21, 1234, 99, 4242]) ...[
      _Case('plain h${h.round()} s$seed', height: h, seed: seed),
      _Case(
        'natural death h${h.round()} s$seed',
        height: h,
        seed: seed,
        god: false,
      ),
    ],
  for (final h in [568.0, 711.0]) ...[
    _Case('fever h${h.round()}', height: h, force: [ElementId.fever]),
    _Case('train h${h.round()}', height: h, force: [ElementId.train]),
    _Case('pair h${h.round()}', height: h, force: [ElementId.pair]),
    _Case('chick h${h.round()}', height: h, chick: true, seed: 21),
    _Case(
      'chick + fever h${h.round()}',
      height: h,
      chick: true,
      force: [ElementId.fever],
    ),
    _Case(
      'chick + pair + train h${h.round()}',
      height: h,
      chick: true,
      force: [ElementId.pair, ElementId.train],
      seed: 1234,
    ),
    _Case('comet h${h.round()}', height: h, force: [ElementId.comet]),
    _Case(
      'bonuses h${h.round()}',
      height: h,
      force: [
        ElementId.piggy,
        ElementId.jar,
        ElementId.coinFrenzy,
        ElementId.puzzlePiece,
      ],
    ),
    _Case(
      'hourglass h${h.round()}',
      height: h,
      force: [ElementId.hourglass],
      seed: 21,
    ),
    _Case(
      'big hoops h${h.round()}',
      height: h,
      starter: Powerup.bigHoops,
      seed: 99,
    ),
    _Case(
      'mixed h${h.round()}',
      height: h,
      force: [
        ElementId.fever,
        ElementId.train,
        ElementId.pair,
        ElementId.spring,
        ElementId.bullseye,
        ElementId.luckySpin,
      ],
      chick: true,
      seed: 4242,
      seconds: 180,
    ),
  ],
  // Top scroll speed (`curve_speed` 187.5 pt/s from hoop 150): the
  // tightest honest pace.
  for (final h in [568.0, 711.0])
    for (final start in [150]) ...[
      _Case(
        'fast h${h.round()} from $start',
        height: h,
        startHoop: start,
        seed: 21,
        seconds: 180,
      ),
      _Case(
        'fast mixed h${h.round()} from $start',
        height: h,
        startHoop: start,
        seed: 1234,
        seconds: 180,
        chick: true,
        force: [ElementId.fever, ElementId.pair, ElementId.train],
      ),
    ],
  for (final r in RideId.values)
    _Case('portal ${r.name}', ride: r, force: [ElementId.portal], seed: 21),
];

void main() {
  final fixtures = <Map<String, Object?>>[];

  for (final c in _cases) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: c.height, seed: c.seed),
      gameSize: Vector2(320, c.height),
    );
    tester.testGameWidget(
      'PRD-2.5 §3.6 honest run fixture: ${c.name}',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        final run = await startRun(
          game,
          starter: c.starter,
          force: c.force,
          ride: c.ride,
          startHoopIndex: c.startHoop,
        );
        game.runDebug.god = c.god;
        void onFrame(RunController r) {
          for (final e in c.force) {
            if (!r.director.forcedQueue.contains(e)) r.debugForce(e);
          }
          if (c.ride != null) r.director.debugForceRide(c.ride!);
          if (c.chick && r.state.egg == null) r.state.egg = EggState();
          // Steer onto a forced bonus pickup just ahead (the bot only
          // aims at hoops), so its coin bonus lands in the timeline.
          final b = r.birdTrackPosition();
          if (b == null || r.state.ride != null) return;
          for (final p in r.spawner.pickups) {
            if (!_gapPickups.contains(p.id) || !c.force.contains(p.id)) {
              continue;
            }
            if (p.collected || p.escaped) continue;
            final dx = p.position.x - b.x;
            if (dx > 0 && dx <= 40) {
              game.runBird?.setFlight(y: p.position.y - r.state.camY, vy: 0);
            }
          }
        }

        final flight = await flyRun(
          game,
          maxSeconds: c.seconds,
          onFrame: onFrame,
        );
        final s = run.state;
        final tl = s.timeline;
        if (!run.ended) tl.end(s.runClock);
        expect(tl.points, s.score, reason: 'timeline sums to the score');
        expect(tl.entries, greaterThan(0), reason: '${c.name} scored');
        // An honest run must pass the server's existing timeline rules
        // (timeline.ts checkRun mirror), or it would never be judged.
        expect(tl.check(), isNull, reason: '${c.name}: ${tl.check()}');
        final entry = _entry(tl, score: s.score);
        var plain = 0, flagged = 0;
        for (final f in tl.flags) {
          f == PointFlags.none ? plain++ : flagged++;
        }
        fixtures.add({
          'name': c.name,
          'score': entry.score,
          'best': entry.best,
          'tl': entry.tl,
          'fl': entry.fl,
          'end': entry.end,
          'hoops': s.hoopsPassed,
          'seconds': double.parse(tl.lengthSeconds.toStringAsFixed(2)),
          'maxValue': tl.values.isEmpty
              ? 0
              : tl.values.reduce((a, b) => a > b ? a : b),
          'plain': plain,
          'flagged': flagged,
        });
        // ignore: avoid_print
        print(
          'FIXTURE ${c.name}: score ${s.score}, hoops ${s.hoopsPassed}, '
          '${tl.entries} entries ($plain plain), '
          '${tl.lengthSeconds.toStringAsFixed(1)} s, end ${flight.cause}',
        );
      },
    );
  }

  tearDownAll(() {
    expect(fixtures.length, _cases.length);
    fixtures.sort(
      (a, b) => (a['name']! as String).compareTo(b['name']! as String),
    );
    final json =
        '${const JsonEncoder.withIndent('  ').convert({'generatedBy': 'test/versus/anomaly_fixtures_test.dart', 'runs': fixtures})}\n';
    final file = File(_out);
    if (Platform.environment['FS_WRITE_FIXTURES'] == '1') {
      file.writeAsStringSync(json);
      // ignore: avoid_print
      print('wrote ${fixtures.length} runs to $_out');
    } else if (!file.existsSync() || file.readAsStringSync() != json) {
      // ignore: avoid_print
      print(
        'NOTE: $_out is not current; regenerate with '
        'FS_WRITE_FIXTURES=1 flutter test test/versus/anomaly_fixtures_test.dart',
      );
    }
  });
}

/// The upload entry of a finished run, encoded exactly as
/// [RunEntry.fromSummary] does (the real `tl` / `fl` / `end` encoders).
RunEntry _entry(RunTimeline tl, {required int score}) => RunEntry(
  runId: 'fixture',
  score: score,
  best: score,
  ts: DateTime.utc(2026, 10, 20),
  name: 'Fixture',
  tl: tl.encodeTl(),
  end: tl.endCs.clamp(0, 0xFFFF),
  fl: tl.encodeFlags(),
);
