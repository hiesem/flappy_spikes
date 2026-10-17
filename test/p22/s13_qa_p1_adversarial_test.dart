import 'dart:convert';
import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/puzzle.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p231/tuning_23.dart';

/// PRD-2.2 QA P1: integration boundaries missed by the builder suites.
Future<List<dynamic>> serverChecks(List<Map<String, Object?>> cases) async {
  final p = await Process.start('node', ['test/p22/qa_p1_backend_probe.cjs']);
  p.stdin.write(jsonEncode(cases));
  await p.stdin.close();
  final out = p.stdout.transform(utf8.decoder).join();
  final err = p.stderr.transform(utf8.decoder).join();
  expect(await p.exitCode, 0, reason: await err);
  return jsonDecode(await out) as List;
}

Map<String, Object?> wireRun(RunTimeline t) => {
  'runId': 'qa-p1',
  'score': t.points,
  'best': t.points,
  'name': 'QA',
  'avatar': '',
  'platform': 'android',
  // WP-AV real catalogue ids: the server validates the id shape.
  'look': {'bird': 'classic', 'gear': 'none', 'hat': 'none', 'hoop': 'pink', 'trail': 'flame'},
  'tl': t.encodeTl(),
  'fl': t.encodeFlags(),
  'end': t.endCs,
};

void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );
  // FlameTester's skip parameter is bool-only. A group preserves Flutter's
  // string skip reason on each contained test.
  void gameCase(
    String name, {
    String? skip,
    required Future<void> Function(FlappySpikesGame, WidgetTester) setUp,
    required Future<void> Function(FlappySpikesGame, WidgetTester) verify,
  }) {
    group(name, () {
      tester.testGameWidget('expected behaviour', setUp: setUp, verify: verify);
    }, skip: skip);
  }

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  gameCase(
    '§13.2 three- to five-digit score text stays within the circle',
    setUp: (g, _) async {
      await prepare(g);
      await (FontLoader(
        Config.scoreFont,
      )..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'))).load();
    },
    verify: (g, _) async {
      await startRun(g);
      final hud = g.world.children.whereType<ScoreHud>().single;
      for (final value in [999, 1000, 8888, 12345, 88888]) {
        hud.setScore(value);
        for (var i = 0; i < 60; i++) {
          hud.update(1 / 60);
        }
        expect(
          hud.textWidth,
          lessThanOrEqualTo(Config.scoreCircleSize.x),
          reason:
              '$value has width ${hud.textWidth}; circle ${Config.scoreCircleSize.x}',
        );
      }
    },
  );

  gameCase(
    // PRD-2.3 §14.3: the chick no longer doubles puzzle coins or points.
    '§13.1 / 2.3 §14.3 the chick leaves the puzzle completion coins and points undoubled',
    setUp: (g, _) => prepare(g),
    verify: (g, _) async {
      final run = await startRun(g);
      await g.storage.savePuzzlePieces(7);
      run.state.egg = EggState()..stage = EggStage.chick;
      final coins0 = run.state.coinsThisRun, points0 = run.state.score;
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      final rolled = run.features.whereType<PuzzleFeature>().single.paid.single;
      expect(run.state.coinsThisRun - coins0, rolled);
      expect(run.state.score - points0, rolled);
      expect(run.state.timeline.points, run.state.score);
    },
  );

  for (final (dy, vy, hit) in [(10.0, 500.0, true), (26.0, -500.0, false)]) {
    gameCase(
      '§11.2 Bullseye uses crossing offset: start $dy, velocity $vy',
      setUp: (g, _) {
        // The 2.3 rule this pins (any rim-free pass is perfect): no perfect
        // band (PRD-2.3.1 §0: the live default is ±18).
        useTuning(tuning23(['point_perfect_band']));
        addTearDown(resetTuning);
        return prepare(g);
      },
      verify: (g, _) async {
        final run = await startRun(
          g,
          startHoopIndex: 6,
          force: [ElementId.bullseye],
        );
        await flyUntil(g, (_) => firstHoopOf(g, HoopKindId.bullseye) != null);
        final h = firstHoopOf(g, HoopKindId.bullseye)!;
        run.state.camX = h.planeX - RunConfig.birdX - .1;
        g.runBird!.setFlight(y: h.position.y + dy, vy: vy);
        g.update(0);
        final earned = <CoinsEarned>[];
        final passed = <HoopPassed>[];
        run.events.on<CoinsEarned>(earned.add);
        run.events.on<HoopPassed>(passed.add);
        g.update(1 / 30);
        await flushAndMount(g);
        expect(h.resolved, isTrue);
        expect(h.touched, isFalse);
        expect(h.passOffset!.abs(), hit ? lessThan(12) : greaterThan(24));
        // PRD-2.3 §14.3: perfect = no rim touch; only the Bullseye coin
        // keeps the ±12 pt band.
        expect(passed.single.perfect, isTrue);
        expect(
          earned.where((e) => e.source == CoinSource.bullseye),
          hasLength(hit ? 1 : 0),
          reason:
              'crossing offset ${h.passOffset}, final offset '
              '${h.frame().toLocal(run.birdTrackPosition()!).y}',
        );
      },
    );
  }

  gameCase(
    '§11 × §13 × §29 clean pass resets an uncapped streak and the next '
    'perfect restarts points; every score change replays in TS',
    setUp: (g, _) => prepare(g),
    verify: (g, widgetTester) async {
      final run = await startRun(g);
      for (var i = 0; i < 52; i++) {
        run.state.runClock = 2.0 * (i + 1);
        run.debugPass(perfect: true);
      }
      expect(run.state.streak, 52);
      expect(run.state.tier, 10);
      run.state.runClock = 106;
      run.debugPass(clean: true);
      expect(run.state.streak, 0);
      run.state.runClock = 108;
      run.debugPass(perfect: true);
      expect(run.state.timeline.values.sublist(50), [51, 52, 1, 2]);
      final timeline = run.state.timeline;
      timeline.end(109);
      final checks = await widgetTester.runAsync(
        () => serverChecks([
          {
            'run': wireRun(timeline),
            'replay': [10399, 10400, 10600, 10800],
          },
        ]),
      );
      expect(checks!.single['reason'], isNull);
      expect(checks.single['replay'], [
        timeline.scoreAt(103.99),
        timeline.scoreAt(104),
        timeline.scoreAt(106),
        timeline.scoreAt(108),
      ]);
    },
  );

  final fixture =
      jsonDecode(
            File('test/fixtures/p22_qa_p1_timeline.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('§13.5 shared fixture: ${c['name']}', () async {
      final t = RunTimeline();
      final entries = (c['entries'] as List).cast<List>();
      for (final e in entries) {
        t.addEntry((e[0] as num).toDouble(), e[1] as int, flag: e[2] as int);
      }
      t.end((entries.last[0] as num).toDouble() + 1);
      // The Dart mirror of the server's timeline rules agrees.
      expect(t.check(), c['expect']);
      const times = [0, 199, 200, 289, 290, 380, 400, 600];
      final checks = await serverChecks([
        {'run': wireRun(t), 'replay': times},
      ]);
      expect(checks.single['reason'], c['expect']);
      final decoded = RunTimeline.tryDecode(
        t.encodeTl(),
        t.encodeFlags(),
        t.endCs,
      )!;
      expect(checks.single['replay'], [
        for (final cs in times) decoded.scoreAt(cs / 100),
      ]);
    }, skip: c['finding'] as String?);
  }
}
