import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/progression/puzzle_album.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';

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
    await album.recordPicture(3);
    expect(storage.albumCounts, [0, 0, 0, 1, 0, 0, 0, 0]);
    await album.recordPicture(3);
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
}
