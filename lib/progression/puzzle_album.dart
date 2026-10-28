import 'dart:math';

import '../game/storage.dart';
import '../skins/catalog.dart';
import '../skins/look.dart';

/// PRD 2.6 O36/O78: counts only pictures completed since the update.
class PuzzleAlbum {
  PuzzleAlbum(this.storage);
  final GameStorage storage;

  int get completed => storage.albumCounts.where((n) => n > 0).length;
  int get current => storage.puzzleRound % 8;
  int get held =>
      (storage.puzzlePieces & 15).toRadixString(2).split('1').length - 1;

  /// Record the colour being completed, before the puzzle round advances.
  Future<void> recordPicture(int round) async {
    final counts = List<int>.of(storage.albumCounts);
    counts[round % 8]++;
    await storage.saveAlbumCounts(counts);
  }

  /// Same eligible categories and rarity fallback as the level reward (R9).
  static SkinItem? roll(Set<String> owned, Set<String> pending, Random random) {
    for (final rarity in [Rarity.epic, Rarity.legendary]) {
      final candidates = allItems
          .where(
            (i) =>
                i.layer != SkinLayer.card &&
                !i.isFree &&
                i.unlock == null &&
                i.rarity == rarity &&
                !owned.contains(i.key) &&
                !pending.contains(i.key),
          )
          .toList();
      if (candidates.isNotEmpty) {
        return candidates[random.nextInt(candidates.length)];
      }
    }
    return null;
  }
}
