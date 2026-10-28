import 'dart:async';
import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/items/puzzle.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/components/levels/tabs/album_reveal_art.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flappy_spikes/components/levels/tabs/levels_tabs.dart';
import '../../helpers.dart';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/progression/puzzle_album.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';

class _InterruptedPreferences extends InMemorySharedPreferencesStore {
  _InterruptedPreferences() : super.empty();
  String? interruptAfter;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final result = await super.setValue(type, key, value);
    if (key == 'flutter.$interruptAfter') throw StateError('interrupted');
    return result;
  }
}

class _DelayedJournal extends InMemorySharedPreferencesStore {
  _DelayedJournal() : super.empty();
  final gate = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.albumCompletionJournal') await gate.future;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('O36 and O78: empty album, held pieces and repeated pictures', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    await storage.savePuzzleRound(3);
    await storage.savePuzzlePieces(5);
    final album = PuzzleAlbum(storage);
    expect(album.completed, 0);
    expect(album.current, 3);
    expect(album.held, 2);
    await storage.beginPuzzleCompletion(payout: 50);
    expect(storage.albumCounts, [0, 0, 0, 1, 0, 0, 0, 0]);
    await storage.savePuzzleRound(3);
    await storage.beginPuzzleCompletion(payout: 50);
    expect(storage.albumCounts[3], 2);
    expect(album.completed, 1);
  });
  test(
    'R9 selects unowned epic, then legendary, excluding card and skill items',
    () {
      final epic = PuzzleAlbum.roll({}, {}, Random(1))!;
      expect(epic.rarity, Rarity.epic);
      expect(epic.layer, isNot(SkinLayer.card));
      final owned = allItems
          .where((i) => i.rarity == Rarity.epic)
          .map((i) => i.key)
          .toSet();
      final next = PuzzleAlbum.roll(owned, {}, Random(1))!;
      expect(next.rarity, Rarity.legendary);
      expect(next.unlock, isNull);
      expect(
        PuzzleAlbum.roll(allItems.map((i) => i.key).toSet(), {}, Random(1)),
        isNull,
      );
    },
  );
  test(
    'G6c concurrent wallet writes wait until the journal is durable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final platform = _DelayedJournal();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final storage = GameStorage();
      await storage.load();
      final wallet = Wallet(storage);
      final journal = storage.beginPuzzleCompletion(payout: 100);
      final bonus = wallet.addAfter(100, CoinSource.puzzle, journal);
      final hoop = wallet.add(5, CoinSource.hoop);
      expect(wallet.balance, 105);
      expect((await platform.getAll()).containsKey('flutter.coins'), isFalse);
      platform.gate.complete();
      await Future.wait([bonus, hoop]);
      await storage.endPuzzlePayout();
      await prefs.reload();
      final recovered = GameStorage();
      await recovered.load();
      expect(recovered.coins, 105);
      expect(recovered.albumCounts.first, 1);
    },
  );

  test('G6c actual interrupted writes replay on reload', () async {
    for (final key in [
      'albumCompletionJournal',
      'puzzlePayout',
      'albumCounts',
      'puzzlePieces',
      'puzzleRound',
    ]) {
      SharedPreferences.setMockInitialValues({});
      final platform = _InterruptedPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final storage = GameStorage();
      await storage.load();
      await storage.savePuzzleRound(3);
      await storage.savePuzzlePieces(7);
      platform.interruptAfter = key;
      await expectLater(
        storage.beginPuzzleCompletion(payout: 140),
        throwsStateError,
      );
      platform.interruptAfter = null;
      await prefs.reload();
      final recovered = GameStorage();
      await recovered.load();
      expect(recovered.puzzleRound, 4, reason: key);
      expect(recovered.puzzlePieces, 0, reason: key);
      expect(recovered.puzzlePayout, 140, reason: key);
      expect(recovered.albumCounts, [0, 0, 0, 1, 0, 0, 0, 0], reason: key);
      expect(prefs.containsKey('albumCompletionJournal'), isFalse);
    }
  });

  test('G6c completion journal replays each interrupted write once', () async {
    for (var writes = 0; writes <= 4; writes++) {
      final counts = [1, 1, 1, 2, 1, 1, 1, 1];
      SharedPreferences.setMockInitialValues({
        'coins': 40,
        'puzzleRound': writes >= 4 ? 4 : 3,
        'puzzlePieces': writes >= 3 ? 0 : 7,
        if (writes >= 1) 'puzzlePayout': 140,
        if (writes >= 2) 'albumCounts': counts.map((n) => '$n').toList(),
        'albumCompletionJournal': jsonEncode({
          'round': 4,
          'payout': 140,
          'counts': counts,
        }),
      });
      final restored = GameStorage();
      await restored.load();
      expect(restored.puzzleRound, 4);
      expect(restored.puzzlePieces, 0);
      expect(restored.puzzlePayout, 140);
      expect(restored.albumCounts, counts);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'albumCompletionJournal',
        ),
        isFalse,
      );
      final again = GameStorage();
      await again.load();
      expect(again.albumCounts, counts);
      final wallet = Wallet(again);
      expect(await PuzzleFeature.settlePayout(again, wallet), 100);
      expect(wallet.balance, 140);
      expect(await PuzzleFeature.settlePayout(again, wallet), 0);
      final paid = GameStorage();
      await paid.load();
      expect(paid.albumCounts, counts);
      expect(paid.coins, 140);
      expect(paid.puzzlePayout, 0);
    }
  });

  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'gamesPlayed': 4,
      'puzzleRound': 7,
      'puzzlePieces': 7,
      'albumCounts': ['1', '1', '1', '1', '1', '1', '1', '0'],
    }),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'G6c last held piece opens one reward; later laps never pay',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      g.runDebug.god = true;
      final run = await startRun(g);
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      await flushAndMount(g);
      expect(g.storage.albumCounts, List.filled(8, 1));
      expect(g.storage.puzzleRound, 8);
      expect(g.storage.puzzlePieces, 0);
      expect(run.features.whereType<PuzzleFeature>().single.paid, hasLength(1));
      final summary = RunSummary(
        score: 0,
        hoopsPassed: 0,
        coins: 0,
        bestBefore: 0,
        bestAfter: 0,
        runSeconds: 5,
        cause: MistakeCause.spikes,
        hoopIndex: 0,
        timeline: RunTimeline.empty(),
      );
      final sounds = <Sfx>[];
      g.sound.onPlay = sounds.add;
      final page = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      g.world.add(page);
      await flushAndMount(g);
      stepGame(g, 10);
      await flushAndMount(g);
      expect(page.revealSheet, isNotNull);
      final sheet = page.revealSheet!;
      expect(sheet.album, isTrue);
      expect(sheet.card.children.whereType<AlbumRevealArt>(), hasLength(1));
      final reward = sheet.item!;
      expect(reward.rarity, Rarity.epic);
      expect(g.storage.ownedItems, isNot(contains(reward.key)));
      stepGame(g, 3);
      await flushAndMount(g);
      expect(sounds, contains(Sfx.lvClaim));
      await sheet.choose(false);
      await flushAndMount(g);
      expect(g.storage.albumRewardClaimed, isTrue);
      expect(g.storage.ownedItems, contains(reward.key));
      expect(g.storage.albumRewardItem, reward.key);
      final saved = GameStorage();
      await saved.load();
      expect(saved.albumRewardClaimed, isTrue);
      expect(saved.ownedItems, contains(reward.key));
      await g.storage.savePuzzlePieces(7);
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      await flushAndMount(g);
      expect(g.storage.albumCounts.first, 2);
      final page2 = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      g.world.add(page2);
      await flushAndMount(g);
      stepGame(g, 10);
      await flushAndMount(g);
      expect(page2.revealSheet, isNull);
      expect(g.storage.ownedItems, contains(reward.key));
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'gamesPlayed': 4,
      'albumCounts': List.filled(8, '1'),
      'albumRewardClaimed': true,
      'albumRewardItem': 'hat:wizard',
      'ownedItems': ['hat:wizard'],
    }),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'G6c completed header shows the awarded item and its name',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      g.openLevels();
      await flushAndMount(g);
      g.levelsScreen!.selectTab(LevelsTab.album);
      final headers = g.levelsScreen!.children
          .whereType<PositionComponent>()
          .where((c) => c.position == Vector2(14, 172));
      final header = headers.singleWhere(
        (c) => c.children.whereType<MenuText>().any(
          (t) => t.text == 'ALBUM COMPLETE',
        ),
      );
      expect(
        header.children.whereType<ItemTile>().single.item.key,
        'hat:wizard',
      );
      expect(
        header.children.whereType<MenuText>().map((t) => t.text),
        contains('WON: WIZARD · EPIC HAT'),
      );
      expect(
        header.children.whereType<MenuText>().map((t) => t.text),
        contains('8 / 8 PICTURES ✓'),
      );
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'gamesPlayed': 4,
      'albumCounts': List.filled(8, '1'),
      'ownedItems': allItems.map((i) => i.key).toList(),
    }),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'G6c exhausted R9 fallback pays coins once',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      final summary = RunSummary(
        score: 0,
        hoopsPassed: 0,
        coins: 0,
        bestBefore: 0,
        bestAfter: 0,
        runSeconds: 5,
        cause: MistakeCause.spikes,
        hoopIndex: 0,
        timeline: RunTimeline.empty(),
      );
      final before = g.menu.wallet.balance;
      final page = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      g.world.add(page);
      await flushAndMount(g);
      stepGame(g, 10);
      await flushAndMount(g);
      final sheet = page.revealSheet!;
      expect(sheet.item, isNull);
      expect(sheet.extraCoins, 2000);
      stepGame(g, 3);
      await flushAndMount(g);
      await sheet.choose(false);
      expect(g.menu.wallet.balance, before + 2000);
      final saved = GameStorage();
      await saved.load();
      expect(saved.albumRewardClaimed, isTrue);
      expect(saved.coins, before + 2000);
      final page2 = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      g.world.add(page2);
      await flushAndMount(g);
      stepGame(g, 10);
      await flushAndMount(g);
      expect(page2.revealSheet, isNull);
      expect(g.menu.wallet.balance, before + 2000);
    },
  );
}
