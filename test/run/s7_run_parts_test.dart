import 'dart:io';

import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§3.13 versus timeline codec (ARCH §6.1)', () {
    test('§3.13 uint16 centisecond deltas + flag bytes round-trip (base64)',
        () {
      final t = RunTimeline()
        ..addPoint(2.1)
        ..addPoint(4.05, flag: PointFlags.train)
        ..addPoint(4.05, flag: PointFlags.gift)
        ..addPoint(9.99)
        ..end(12.5);
      expect(t.cs, [210, 195, 0, 594]);
      expect(t.flags, [0, 2, 4, 0]);
      expect(t.endCs, 251);
      final d = RunTimeline.decode(t.encodeTl(), t.encodeFlags(), t.endCs);
      expect(d.cs, t.cs);
      expect(d.flags, t.flags);
      expect(d.lengthSeconds, closeTo(12.5, 1e-9));
    });

    test('§3.13 scoreAt replays on runClock; out after the end', () {
      final t = RunTimeline()
        ..addPoint(1)
        ..addPoint(2)
        ..addPoint(3)
        ..end(5);
      expect(t.scoreAt(0.5), 0);
      expect(t.scoreAt(2), 2);
      expect(t.scoreAt(4), 3);
      expect(t.outAt(4.9), isFalse);
      expect(t.outAt(5.1), isTrue);
      expect(RunTimeline.empty().outAt(100), isFalse);
    });
  });

  group('§3.9 sound: approved files + the loop API (ARCH §2.7)', () {
    test('§3.9 every approved PRD-2 run sound is bundled', () {
      for (final f in [
        'perfect_1', 'perfect_2', 'perfect_3', 'pu_heart_1', 'pu_heart_2',
        'pu_heart_use', 'pu_shield_get', 'pu_shield_hit', 'pu_comet_get',
        'pu_comet_end', 'pu_portal', 'pu_cannon_aim', 'pu_cannon_shot',
        'pu_land', 'miss_shock', 'rv_pay', 'rv_ignite', 'rv_burst',
        'rv_locked', 'lv_bar', 'lv_up', 'lv_up_big', 'lv_claim',
        'col_feather_get', 'col_feather_slot1', 'col_feather_slot2',
        'col_feather_slot3', 'bn_balloon_open', 'bn_prize_s', 'bn_prize_m',
        'bn_prize_big', 'col4_puzzle_get', 'col4_puzzle_slot1',
        'col4_puzzle_slot2', 'col4_puzzle_slot3', 'col4_puzzle_slot4',
        'col4_coins', 'sq_warn', 'sq_close', 'sq_lock', 'sq_tick', 'sq_open',
      ]) {
        expect(SoundService.audioFiles.values, contains('$f.mp3'), reason: f);
      }
      final rides = SoundService.audioFiles.values.where((f) => f.startsWith('rd_'));
      expect(rides, hasLength(16));
      for (final l in SfxLoop.values) {
        expect(l.file, endsWith('.wav'), reason: 'seamless loop');
        expect(File('assets/audio/${l.file}').existsSync(), isTrue);
      }
    });

    test('§3.9 loops are recorded and silent when disabled; stop is '
        'idempotent', () async {
      final sound = SoundService(enabled: false);
      final log = <(SfxLoop, double)>[];
      sound.onLoop = (l, v) => log.add((l, v));
      final h = sound.loop(SfxLoop.cometLoop, volume: 0.3);
      expect(log, [(SfxLoop.cometLoop, 0.3)]);
      expect(sound.activeLoops, [h]);
      await h.stop();
      await h.stop();
      expect(h.stopped, isTrue);
      expect(sound.activeLoops, isEmpty);
      sound.loop(SfxLoop.sqHold);
      await sound.stopAllLoops();
      expect(sound.activeLoops, isEmpty);
    });

    test('§3.30 / §5.9 music rate and duck are stored without a plugin',
        () async {
      final sound = SoundService(enabled: false);
      await sound.setMusicRate(0.72);
      await sound.duckMusic(0.5);
      expect(sound.musicRate, 0.72);
      expect(sound.musicDuck, 0.5);
    });
  });

  group('§6 wallet sources and ad placements', () {
    test('§6 coins_earned source names', () {
      expect(
        {
          for (final s in [
            CoinSource.hoop, CoinSource.perfect, CoinSource.winBonus,
            CoinSource.bonus, CoinSource.puzzle, CoinSource.switchRing,
            CoinSource.pair, CoinSource.train, CoinSource.bullseye,
            CoinSource.luckySpin, CoinSource.starTrail, CoinSource.piggy,
            CoinSource.jar, CoinSource.frenzy,
          ])
            s.analyticsName,
        },
        {
          'hoop', 'perfect', 'win_bonus', 'bonus', 'puzzle', 'switch',
          'pair', 'train', 'bullseye', 'lucky_spin', 'star_trail', 'piggy',
          'jar', 'frenzy',
        },
      );
      expect(CoinSource.levelReward.analyticsName, 'level_reward');
      expect(CoinSource.hoop.aggregatedInRun, isTrue);
      expect(CoinSource.winBonus.aggregatedInRun, isFalse);
      expect(CoinSource.bonus.aggregatedInRun, isFalse);
      expect(CoinSource.puzzle.aggregatedInRun, isFalse);
    });

    test('§6 ad placement bonus_feathers', () {
      expect(AdPlacement.bonusFeathers.analyticsName, 'bonus_feathers');
      expect(AdPlacement.revive.analyticsName, 'revive');
    });
  });

  group('§3.0.7 elements and §3.0.3 pickup radii', () {
    test('§3.0.7 every element has a unique stable storage id', () {
      final ids = ElementId.values.map((e) => e.storageId).toList();
      expect(ids.toSet().length, ids.length);
      for (final e in ElementId.values) {
        expect(ElementId.fromStorageId(e.storageId), e);
        expect(RegExp(r'^[a-z0-9_]+$').hasMatch(e.storageId), isTrue);
      }
    });

    test('§3.0.3 pickup hit radii', () {
      expect(PickupRadii.forElement(ElementId.heart), 16);
      expect(PickupRadii.forElement(ElementId.shield), 18);
      expect(PickupRadii.forElement(ElementId.puzzlePiece), 22);
      // PRD-2.2 §26: the 16 pt piggy coin catches at 14 (was 10).
      expect(PickupRadii.forElement(ElementId.piggyCoins), 14);
      expect(PickupRadii.forElement(ElementId.starTrail), 10);
      expect(PickupRadii.forElement(ElementId.fireflySwarm), 16);
      expect(PickupRadii.forElement(ElementId.hourglass), 18);
    });

    test('§3.0.1 cruise ramp and colour stage', () {
      expect(RunConfig.cruise(0), 150);
      expect(RunConfig.cruise(60), closeTo(155.25, 1e-9));
      expect(RunConfig.stageForHoops(9), 0);
      expect(RunConfig.stageForHoops(10), 1);
      expect(RunConfig.stageForHoops(109), 10);
      expect(RunConfig.stageForHoops(110), 0);
    });
  });

  test('ARCH §7.3 FS_E2E defaults (plain test run)', () {
    expect(kE2E, isFalse);
    expect(kE2ESeed, 7);
    E2EHooks.force.add(ElementId.saw);
    E2EHooks.reset();
    expect(E2EHooks.force, isEmpty);
  });
}
