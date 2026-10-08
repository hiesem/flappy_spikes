import 'package:flappy_spikes/game/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2 §7 persistence table: every key round-trips with its default
/// (ARCH §5).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameStorage> fresh() async {
    final s = GameStorage();
    await s.load();
    return s;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('§7 defaults of every PRD-2 key on a fresh install', () async {
    final s = await fresh();
    expect(s.bestScore, 0);
    expect(s.gamesPlayed, 0);
    expect(s.muteSound, isFalse);
    expect(s.musicVolume, 0.6);
    expect(s.rumble, isTrue);
    expect(s.feathers, 0);
    expect(s.puzzlePieces, 0);
    expect(s.puzzleRound, 0);
    expect(s.lastPortalRide, isNull);
    expect(s.unclaimedLevelReward, 0);
    expect(s.levelRewardPayout, 0);
    expect(s.metElements, isEmpty);
    expect(s.levelRewardsClaimed, 0);
    expect(s.versusNickname, isNull);
    expect(s.uploadQueue, isEmpty);
    expect(s.uploadsToday, 0);
    expect(s.uploadsDay, '');
    expect(s.notifOrder, isEmpty);
    expect(s.notifPosition, 0);
    expect(s.notifLastSent, isEmpty);
    expect(s.notifPermissionAsked, isFalse);
  });

  test('§7 every PRD-2 key round-trips', () async {
    final a = await fresh();
    await a.saveBestScore(41);
    await a.incrementGamesPlayed();
    await a.saveMuteSound(true);
    await a.saveMusicVolume(0.25);
    await a.saveRumble(false);
    await a.saveFeathers(2);
    await a.savePuzzlePieces(0x5);
    await a.savePuzzleRound(3);
    await a.saveLastPortalRide('storm');
    await a.saveUnclaimedLevelReward(150);
    await a.saveLevelRewardPayout(150);
    await a.saveMetElements({'saw', 'portal'});
    await a.markElementMet('egg');
    await a.saveClaimedLevels({1, 2, 4});
    await a.saveVersusNickname('BrightOwl123');
    await a.saveUploadQueue(['{"runId":"a"}', '{"runId":"b"}']);
    await a.saveUploadsToday('2026-10-08', 2);
    await a.saveNotifOrder([3, 1, 2]);
    await a.saveNotifPosition(1);
    await a.saveNotifLastSent({3: '2026-10-07', 12: '2026-10-08'});
    await a.saveNotifPermissionAsked(true);

    final b = await fresh();
    expect(b.bestScore, 41);
    expect(b.gamesPlayed, 1);
    expect(b.muteSound, isTrue);
    expect(b.musicVolume, 0.25);
    expect(b.rumble, isFalse);
    expect(b.feathers, 2);
    expect(b.puzzlePieces, 0x5);
    expect(b.puzzleRound, 3);
    expect(b.lastPortalRide, 'storm');
    expect(b.unclaimedLevelReward, 150);
    expect(b.levelRewardPayout, 150);
    expect(b.metElements, {'saw', 'portal', 'egg'});
    expect(b.levelRewardsClaimed, 4);
    expect(b.versusNickname, 'BrightOwl123');
    expect(b.uploadQueue, ['{"runId":"a"}', '{"runId":"b"}']);
    expect(b.uploadsToday, 2);
    expect(b.uploadsDay, '2026-10-08');
    expect(b.notifOrder, [3, 1, 2]);
    expect(b.notifPosition, 1);
    expect(b.notifLastSent, {3: '2026-10-07', 12: '2026-10-08'});
    expect(b.notifPermissionAsked, isTrue);
  });

  test('§3.16 completing a round clears the mask and bumps the round at '
      'once', () async {
    final a = await fresh();
    await a.savePuzzlePieces(0xF);
    await a.savePuzzleRound(7);
    final done = a.completePuzzleRound();
    expect(a.puzzlePieces, 0, reason: 'set before the first await');
    expect(a.puzzleRound, 8);
    await done;
    final b = await fresh();
    expect(b.puzzlePieces, 0);
    expect(b.puzzleRound, 8);
  });

  test('§3.15 feathers stay 0–3; §3.16 the mask stays 4 bits', () async {
    final a = await fresh();
    await a.saveFeathers(9);
    expect(a.feathers, 3);
    await a.savePuzzlePieces(0x1F);
    expect(a.puzzlePieces, 0xF);
  });

  test('§3.0.8 markElementMet adds once', () async {
    final a = await fresh();
    await a.markElementMet('saw');
    await a.markElementMet('saw');
    expect(a.metElements, {'saw'});
  });

  test('§3.14 (Fix P2 R1, S6-22) the level-reward record is durable and '
      'cleared in one write', () async {
    final a = await fresh();
    await a.beginLevelRewardClaim(payout: 190, claimed: {1, 2});
    // The record must already be on disk before the credit runs.
    final mid = await fresh();
    expect(mid.levelRewardPayout, 190);
    expect(mid.levelRewardsClaimed, 2);
    await a.endLevelRewardClaim();
    final b = await fresh();
    expect(b.levelRewardPayout, 0);
    expect(b.unclaimedLevelReward, 0);
    expect(b.levelRewardsClaimed, 2, reason: 'the claim itself stays');
  });

  test('§3.13 "Delete my data" (Q22) resets the versus keys only', () async {
    SharedPreferences.setMockInitialValues({
      'coins': 77,
      'noAds': true,
      'bestScore': 12,
      'feathers': 2,
      'versusNickname': 'SwiftKiwi482',
      'uploadQueue': ['{"runId":"a"}'],
      'uploadsToday': 2,
      'uploadsDay': '2026-10-08',
    });
    final a = await fresh();
    await a.resetVersusData();
    expect(a.versusNickname, isNull);
    expect(a.uploadQueue, isEmpty);
    expect(a.uploadsToday, 0);
    expect(a.uploadsDay, '');
    expect(a.coins, 77);
    expect(a.noAds, isTrue);
    expect(a.bestScore, 12);
    expect(a.feathers, 2);
    // The clear is durable (a kill right after it does not resurrect it).
    final b = await fresh();
    expect(b.versusNickname, isNull);
    expect(b.uploadQueue, isEmpty);
    expect(b.uploadsDay, '');
    expect(b.coins, 77);
  });

  test('§7 the PRD-1 menu keys are untouched by the PRD-2 keys', () async {
    SharedPreferences.setMockInitialValues({
      'coins': 77,
      'armedPowerup': 'shield',
      'noAds': true,
    });
    final s = await fresh();
    expect(s.coins, 77);
    expect(s.armedPowerup, 'shield');
    expect(s.noAds, isTrue);
  });
}
