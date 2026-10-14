import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/gates_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The gated elements the director can place, by storage id.
const gated = {
  'heart', 'star_trail', 'bullseye', 'switch_ring', 'train', 'comet', //
  'portal', 'capsule', 'hourglass', 'mini_bird', 'coin_frenzy', 'shield', //
  'spring', 'pair', 'egg', 'feather', 'puzzle_piece', 'piggy', 'jar', //
  'fever', 'lucky_spin', 'saw',
};

/// PRD-2.3 §14.6 the table: what is open from each `gamesPlayed`
/// (PRD-2.3.1 §0 live RC v21 gates 0/2/4/6/8/12; were 0/3/5/8/10/15/20).
Set<String> openAt(int games) => {
  'heart', 'star_trail', 'bullseye', 'switch_ring', 'train',
  if (games >= 2) ...[
    'comet', 'portal', 'capsule', 'hourglass', 'mini_bird', 'coin_frenzy', //
    'shield',
  ],
  if (games >= 4) ...['spring', 'pair', 'egg'],
  if (games >= 6) ...['feather', 'puzzle_piece', 'piggy', 'jar'],
  if (games >= 8) ...['fever', 'lucky_spin'],
  if (games >= 12) 'saw',
};

/// What spawned in [seeds] long runs with the elements open at [games]
/// (nothing met yet, so first-meet forces every open element: "forced
/// eligibility").
Set<String> spawnedAt(int games, {int seeds = 40, int slots = 220}) {
  final registered = {...registeredElements(), ...registeredPickupElements()};
  final enabled = GatesConfig.filter(registered, games);
  final out = <String>{};
  for (var seed = 1; seed <= seeds; seed++) {
    final d = RunDirector(seed: seed, enabled: enabled, met: const {});
    for (var k = 0; k < slots; k++) {
      final ctx = DirectorContext.open(711);
      final s = d.nextSlot(ctx);
      final g = d.nextGap(ctx, s);
      out.add(s.element.storageId);
      if (s.cometHang) out.add('comet');
      for (final it in [...s.attached, ...g.items]) {
        out.add(it.kind.storageId);
        final x = it.extra;
        if (x is CapsuleType) out.add(x.element.storageId);
      }
    }
  }
  return out.intersection(gated);
}

void main() {
  group('§14.6 lifetime unlock gates (director)', () {
    for (final games in [0, 2, 4, 6, 8, 12, 20]) {
      test('gamesPlayed $games: exactly the listed elements can spawn', () {
        expect(spawnedAt(games), openAt(games));
      });
    }

    test('in between, the lower gate holds (gamesPlayed 3, 11)', () {
      expect(spawnedAt(3, seeds: 20), openAt(2));
      expect(spawnedAt(11, seeds: 20), openAt(8));
    });

    test('a debug force ignores the gate; normal, angled and moving hoops '
        'are never gated', () {
      final all = ElementId.values.toSet();
      final f = GatesConfig.filter(all, 0, keep: [ElementId.saw, ElementId.hourglass]);
      expect(f, containsAll([ElementId.saw, ElementId.hourglass, ElementId.capsule]));
      expect(f, isNot(contains(ElementId.fever)));
      expect(f, containsAll([
        ElementId.normalHoop,
        ElementId.angledRing,
        ElementId.movingRing,
        ElementId.squeeze,
        ElementId.bigHoops,
      ]));
    });
  });

  group('§14.2 feather / piece: never in two runs in a row, never together',
      () {
    test('shownLastRun: blocked for the run right after (and the same '
        'gamesPlayed), never before the first', () {
      expect(GatesConfig.shownLastRun(-1, 0), isFalse);
      expect(GatesConfig.shownLastRun(-1, 30), isFalse);
      expect(GatesConfig.shownLastRun(12, 13), isTrue);
      expect(GatesConfig.shownLastRun(12, 12), isTrue);
      expect(GatesConfig.shownLastRun(12, 14), isFalse);
    });

    test('featherAllowed / pieceAllowed false: never this run; both roll: '
        'the feather wins', () {
      var feathers = 0, pieces = 0;
      for (var seed = 1; seed <= 300; seed++) {
        final all = ElementId.values.toSet();
        final none = RunDirector(
          seed: seed,
          enabled: all,
          met: all,
          featherAllowed: false,
          pieceAllowed: false,
        );
        expect(none.featherThisRun, isFalse);
        expect(none.pieceThisRun, isFalse);
        final d = RunDirector(seed: seed, enabled: all, met: all);
        expect(d.featherThisRun && d.pieceThisRun, isFalse, reason: '$seed');
        // PRD-2.3.1 §0 live RC v21 bonus_feather_gaps [5,30] (was 10–40).
        expect(d.featherAt, inInclusiveRange(5, 32));
        if (d.featherThisRun) feathers++;
        if (d.pieceThisRun) pieces++;
        // The piece alone (the feather not allowed this run) still comes.
        final p = RunDirector(
          seed: seed,
          enabled: all,
          met: all,
          featherAllowed: false,
        );
        expect(p.featherThisRun, isFalse);
      }
      expect(feathers / 300, closeTo(.6, .08));
      // ≈ 0.6 × 0.4 = 24 % of runs.
      expect(pieces / 300, closeTo(.24, .07));
    });
  });

  group('§14.6 in the game', () {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, prefs: {'gamesPlayed': 0}),
      gameSize: Vector2(320, 711),
    );
    tester.testGameWidget(
      'a real run (gates on) at gamesPlayed 0 offers only the first-gate '
      'elements; a forced one still comes',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, _) async {
        game.runDebug.ignoreGates = false;
        final run = await startRun(game, force: [ElementId.saw]);
        expect(run.setup.ignoreGates, isFalse);
        expect(run.enabled, containsAll([
          ElementId.heart,
          ElementId.starTrail,
          ElementId.bullseye,
          ElementId.switchRing, // gate 0 (PRD-2.3.1 §0 live RC v21)
          ElementId.train,
          ElementId.saw, // forced
        ]));
        for (final e in [
          ElementId.fever,
          ElementId.comet,
          ElementId.portal,
          ElementId.feather,
          ElementId.capsule,
        ]) {
          expect(run.enabled, isNot(contains(e)), reason: e.storageId);
        }
      },
    );

    tester.testGameWidget(
      'RUN DEBUG "Runs: N (+5 / 0)" sets gamesPlayed (+5, from 20 back to '
      '0); "Reset menu state" leaves it alone',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, _) async {
        game.openDebugPanel();
        await flushAndMount(game);
        final p = game.world.children.query<DebugPanel>().single;
        await p.press(p.actions.indexWhere((a) => a.label() == 'RUN DEBUG >'));
        await flushAndMount(game);
        int runsRow() =>
            p.actions.indexWhere((a) => a.label().startsWith('Runs: '));
        expect(p.actions[runsRow()].label(), 'Runs: 0 (+5 / 0)');
        final seen = <int>[];
        for (var k = 0; k < 5; k++) {
          await p.press(runsRow());
          seen.add(game.storage.gamesPlayed);
        }
        expect(seen, [5, 10, 15, 20, 0]);
        await p.press(runsRow());
        expect(p.actions[runsRow()].label(), 'Runs: 5 (+5 / 0)');
        await p.press(p.actions.indexWhere((a) => a.label() == '< Back'));
        await p.press(
          p.actions.indexWhere((a) => a.label() == 'Reset menu state'),
        );
        expect(game.storage.gamesPlayed, 5);
      },
    );

    final feather = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, prefs: {'gamesPlayed': 12}),
      gameSize: Vector2(320, 711),
    );
    feather.testGameWidget(
      '§14.2 a run that showed a feather is recorded (lastFeatherRun) before '
      'gamesPlayed counts it',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, _) async {
        game.runDebug.ignoreGates = false;
        final run = await startRun(
          game,
          startHoopIndex: 10,
          force: [ElementId.feather],
        );
        expect(
          await flyUntil(game, (r) => r.state.featherSpawned, maxSeconds: 30),
          isTrue,
        );
        killRun(game);
        await declineRevive(game);
        await flushAndMount(game);
        expect(run.state.featherSpawned, isTrue);
        expect(game.storage.lastFeatherRun, 12);
        expect(game.storage.gamesPlayed, 13);
        expect(game.storage.lastPieceRun, -1);
        expect(
          GatesConfig.shownLastRun(
            game.storage.lastFeatherRun,
            game.storage.gamesPlayed,
          ),
          isTrue,
        );
      },
    );
  });
}
