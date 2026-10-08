import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/puzzle_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/items/puzzle.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/puzzle_piece_pickup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// PRD-2 §3.16 / §5.15 puzzle pieces: one missing piece per run, banked at
/// the touch, the pill, 4/4 = random 50–250 (step 5) credited at once in
/// the run (YOUR REWARD includes it) with mask 0 and round + 1 together,
/// 8 colour rounds as data, the pinwheel cut.
void main() {
  group('§5.15 data and geometry', () {
    test('§5.15 the 8 rounds in order, hexes as data, looped', () {
      expect(PuzzleConfig.themes.map((t) => t.name), [
        'Pink', 'Sky', 'Gold', 'Ocean', 'Cocoa', 'Mint', 'Grape', 'Tangerine', //
      ]);
      String hex(int v) => v.toRadixString(16).toUpperCase().substring(2);
      final rows = [
        for (final t in PuzzleConfig.themes)
          [t.card, t.body, t.wing, t.beak].map((c) => hex(c.toARGB32())).join(' '),
      ];
      expect(rows, [
        'FCD9EE EC008C C2185B FFB529',
        'D3F5FF 0CD9FF 0890AD FFB529',
        'FFF0C7 FFB529 D48A00 EC008C',
        'DCE6FF 0067FF 001D89 FFB529',
        'F3E3D3 8B5A2B 5A3818 FFB529',
        'D9F7E4 21C46B 137A42 FFB529',
        'ECDFFF 8E44FF 5420B0 FFB529',
        'FFE4CC FF7A1A B84A00 FFD54A',
      ]);
      const gold = 0xFFFFB529, white = 0xFFFFFFFF;
      expect(PuzzleConfig.themes.map((t) => t.sparkle.toARGB32()), [
        gold, white, white, gold, gold, white, gold, white, //
      ]);
      expect(PuzzleConfig.themeFor(8).name, 'Pink');
      expect(PuzzleConfig.themeFor(9).name, 'Sky');
      for (final t in PuzzleConfig.themes) {
        expect(t.edge, t.wing);
      }
    });

    test('§5.15 2 × 2 cut, 24 pt cells, pinwheel tabs '
        '(TL → right, TR → down, BR → left, BL → up)', () {
      final b = [for (final p in PuzzleArt.paths) p.getBounds()];
      // TL: its right edge bulges past x 0; its bottom is straight at 0.
      expect(b[0].right, greaterThan(4));
      expect(b[0].bottom, closeTo(0, .01));
      // TR: its bottom bulges below y 0.
      expect(b[1].bottom, greaterThan(4));
      expect(b[1].left, closeTo(0, .01));
      // BR: its left edge bulges past x 0.
      expect(b[3].left, lessThan(-4));
      expect(b[3].top, closeTo(0, .01));
      // BL: its top bulges above y 0.
      expect(b[2].top, lessThan(-4));
      expect(b[2].right, closeTo(0, .01));
      // Outer edges straight on the 48 pt board.
      expect(b[0].left, -24);
      expect(b[0].top, -24);
      expect(b[3].right, 24);
      expect(b[3].bottom, 24);
      expect(PuzzleArt.centreOf(0), const Offset(-12, -12));
      expect(PuzzleArt.centreOf(3), const Offset(12, 12));
    });

    test('§3.16 / §5.15 knobs', () {
      expect(RunConfig.puzzleBonusMin, 50);
      expect(RunConfig.puzzleBonusMax, 250);
      expect(RunConfig.puzzleBonusStep, 5);
      expect(PuzzleConfig.pickupScale, 2.1);
      expect(PuzzleConfig.glowRadius, 46);
      expect(PuzzleConfig.rayOmega, .6);
      expect(PuzzleConfig.twinkleEvery, .22);
      expect(PuzzleConfig.twinkleRadius, 36);
      expect(PuzzleConfig.pillWidth, 140);
      expect(PuzzleConfig.pillHeight, 64);
      expect(PuzzleConfig.boardX, -32);
      expect(PuzzleConfig.countX, 34);
      expect(PuzzleConfig.fadeAt, 2.15);
      expect(PuzzleConfig.fadeAtComplete, 4.6);
      expect(PuzzleConfig.confetti, 22);
      expect(PuzzleConfig.completeRingTo, 100);
      expect(PuzzleConfig.badgeDelay, .55);
      expect(PuzzleConfig.badgeCoins, 7);
      expect(PuzzleConfig.countLength, .8);
      expect(PuzzleConfig.stickerText, 'PICTURE COMPLETE');
      expect(PickupRadii.puzzlePiece, 22);
    });
  });

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    double height = 711,
    int seed = 5,
  }) => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: prefs,
      worldHeight: height,
      seed: seed,
      services: AnalyticsSpy(),
    ),
    gameSize: Vector2(320, height),
  );

  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  tester(prefs: {'puzzlePieces': 0xB, 'puzzleRound': 2}).testGameWidget(
    '§3.16 only a missing piece spawns; a touched piece is banked at once; '
    'slot sound by count; analytics',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final sfx = sfxLog(g);
      final run = await startRun(
        g,
        startHoopIndex: ElementId.puzzlePiece.firstPossible!,
        force: [ElementId.puzzlePiece],
      );
      final p = await collectPickup(g, ElementId.puzzlePiece, reforce: false);
      expect(p, isA<PuzzlePiecePickup>());
      final piece = p! as PuzzlePiecePickup;
      expect(piece.piece, 2, reason: 'the one missing piece');
      expect(piece.theme.name, 'Gold');
      expect(run.state.pieceSpawned, isTrue);
      // 4/4 → paid, mask 0, round + 1.
      final feature = run.features.whereType<PuzzleFeature>().single;
      expect(feature.paid, hasLength(1));
      expect(g.storage.puzzlePieces, 0);
      expect(g.storage.puzzleRound, 3);
      expect(sfx, contains('col4PuzzleGet'));
      final spy = g.services as AnalyticsSpy;
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'puzzle_piece_collected').single.$2,
        {'piece': 3, 'count': 4, 'round': 3},
      );
      await stepSeconds(g, .9);
      expect(sfx, contains('col4PuzzleSlot4'));
    },
  );

  tester(prefs: {'puzzlePieces': 0x8}).testGameWidget(
    '§3.16 the slot sound follows the count held, not the position',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final sfx = sfxLog(g);
      final run = await startRun(g);
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      // No pickup: the first missing place (piece 0) → 2 pieces held.
      expect(g.storage.puzzlePieces, 0x9);
      await flushAndMount(g);
      expect((await SharedPreferences.getInstance()).getInt('puzzlePieces'), 0x9);
      await stepSeconds(g, .9);
      expect(sfx, contains('col4PuzzleSlot2'));
      expect(sfx, isNot(contains('col4PuzzleSlot1')));
      final item = CollectLayer.of(run)!.slot.current! as PuzzlePillItem;
      expect(item.count, 2);
      expect(item.reward, isNull);
      expect(item.fadeAt, PuzzleConfig.fadeAt);
    },
  );

  tester(prefs: {'puzzlePieces': 0x7, 'puzzleRound': 7}).testGameWidget(
    '§3.16 4/4: random 50–250 step 5 credited exactly once, in the run, '
    'mask 0 + round + 1 at once; PICTURE COMPLETE + coin badge; '
    'YOUR REWARD includes it',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      g.runDebug.god = true;
      final sfx = sfxLog(g);
      final run = await startRun(g);
      final wallet = g.menu.wallet.balance;
      final coins = run.state.coinsThisRun;
      final earned = <CoinsEarned>[];
      run.events.on<CoinsEarned>(earned.add);
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      final feature = run.features.whereType<PuzzleFeature>().single;
      expect(feature.paid, hasLength(1));
      final bonus = feature.paid.single;
      expect(bonus, inInclusiveRange(50, 250));
      expect(bonus % 5, 0);
      expect(g.menu.wallet.balance, wallet + bonus);
      expect(run.state.coinsThisRun, coins + bonus);
      expect(earned.single.amount, bonus);
      expect(g.storage.puzzlePieces, 0);
      expect(g.storage.puzzleRound, 8);
      await flushAndMount(g);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('puzzlePieces'), 0);
      expect(prefs.getInt('puzzleRound'), 8);
      // S6-62: once the coin write landed, the payout record is cleared.
      expect(g.storage.puzzlePayout, 0);
      expect(prefs.getInt('puzzlePayout'), 0);
      expect(prefs.getInt('coins'), wallet + bonus);
      final spy = g.services as AnalyticsSpy;
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'puzzle_completed').single.$2,
        {'round': 8, 'coins': bonus},
      );
      final layer = CollectLayer.of(run)!;
      await flushAndMount(g);
      final item = layer.slot.current! as PuzzlePillItem;
      expect(item.theme.name, 'Tangerine', reason: 'the round just finished');
      expect(item.fadeAt, PuzzleConfig.fadeAtComplete);
      await stepSeconds(g, 1.3);
      expect(
        layer.children.whereType<GoldSticker>().single.text,
        'PICTURE COMPLETE',
      );
      await stepSeconds(g, 1.5);
      expect(sfx, contains('col4Coins'));
      expect(item.badgeCount(layer.slot.time), bonus);
      // The next piece starts the new round (Pink, 1/4): no second payment.
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      expect(feature.paid, hasLength(1));
      expect(g.storage.puzzlePieces, 0x1);
      expect(g.menu.wallet.balance, wallet + bonus);
      // YOUR REWARD: the run's coins incl. the puzzle bonus.
      g.runDebug.god = false;
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.results);
      expect(g.resultsScreen!.summary.coins, run.state.coinsThisRun);
      expect(g.resultsScreen!.summary.coins, greaterThanOrEqualTo(bonus));
    },
  );

  for (final h in [568.0, 711.0]) {
    tester(height: h, seed: 11).testGameWidget(
      '§3.16 / §3.0.3 one piece per run (gap 14–25) while the round is open '
      '(${h.round()} pt)',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        g.runDebug.god = true;
        final run = await startRun(g);
        expect(run.director.pieceAt, inInclusiveRange(14, 25));
        var spawned = 0;
        run.events.on<ElementSpawned>((e) {
          if (e.element == ElementId.puzzlePiece) spawned++;
        });
        await flyRun(g, untilHoops: 40, maxSeconds: 120);
        expect(run.state.hoopsPassed, greaterThanOrEqualTo(30));
        expect(spawned, 1);
      },
    );
  }
}
