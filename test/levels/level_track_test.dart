import 'dart:convert';

import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => TuningValues.current = TuningValues.defaults());

  test('J1 table cumulative points, F11 coins and rarity budget', () {
    const cumulative = [
      25,
      75,
      175,
      325,
      525,
      825,
      1225,
      1725,
      2325,
      3025,
      3825,
      4725,
      5725,
      6925,
      8325,
      9925,
      11725,
      13725,
      15925,
      18325,
      20925,
      23725,
      26725,
      30225,
      34225,
      38725,
      43725,
      49725,
      56725,
      64725,
      74725,
    ];
    expect(kLevels.length, 31);
    var total = 0;
    for (var i = 0; i < kLevels.length; i++) {
      final def = kLevels[i];
      expect(def.level, i + 1);
      total += def.points;
      expect(total, cumulative[i]);
      expect(needFor(i), def.points);
    }
    expect(kLevels.fold(0, (sum, def) => sum + def.coins), 18800);
    expect(kLevels.take(5).fold(0, (sum, def) => sum + def.coins), 250);
    expect(kLevels.take(5).every((def) => def.rarity == Rarity.common), isTrue);
    expect(
      [
        for (final rarity in Rarity.values)
          kLevels.where((def) => def.rarity == rarity).length,
      ],
      [13, 10, 6, 2],
    );
    expect(levelDef(31)!.layer, isNull);
    expect(levelDef(31)!.rarity, Rarity.legendary);
  });

  test('J3 accumulate, exact hit, at most one level and dropped surplus', () {
    expect(LevelTrack.step(0, 10, 14), (
      index: 0,
      points: 24,
      levelledUp: false,
      surplus: 0,
    ));
    expect(LevelTrack.step(0, 24, 1), (
      index: 1,
      points: 0,
      levelledUp: true,
      surplus: 0,
    ));
    expect(LevelTrack.step(0, 24, 30), (
      index: 1,
      points: 0,
      levelledUp: true,
      surplus: 29,
    ));
    expect(LevelTrack.step(0, 0, 1000000).index, 1);
    expect(LevelTrack.step(1, 0, 0).points, 0);
  });

  test('J2 endless levels 31 to 32 to 33 and beyond, without stars', () {
    var index = 31;
    for (var n = 0; n < 100; n++) {
      expect(LevelTrack.step(index, 9998, 1).index, index);
      final result = LevelTrack.step(index, 9999, 1);
      expect(result.index, index + 1);
      expect(result.points, 0);
      index = result.index;
      expect(levelDef(index)!.level, index);
      expect(levelDef(index)!.name, 'ETERNAL WING');
      expect(levelDef(index)!.coins, 2500);
      expect(needFor(index), 10000);
    }
    expect(levelDef(0), isNull);
  });

  test('J13 painted fallback covers ten emblems and stays at ten', () {
    expect(paintedEmblemFor(0), 0);
    expect(
      {for (var i = 1; i <= 31; i++) paintedEmblemFor(i)},
      {1, 2, 3, 4, 5, 6, 7, 8, 9, 10},
    );
    expect(paintedEmblemFor(32), 10);
    expect(paintedEmblemFor(10000), 10);
    expect(levelDef(32)!.plate, kEternalWing.plate);
  });

  test('S0 tuning is read for points, coins, item rows and eternal levels', () {
    final points = tuning.ints('level_points')..[0] = 42;
    final coins = tuning.ints('level_coins')..[0] = 99;
    final items = List<String>.from(tuning.raw('level_items') as List)
      ..[0] = 'gear:epic';
    TuningValues.current = TuningValues.resolve({
      'level_points': jsonEncode(points),
      'level_coins': jsonEncode(coins),
      'level_items': jsonEncode(items),
      'level_eternal_points': '12345',
      'level_eternal_coins': '3456',
    });
    expect(needFor(0), 42);
    expect(levelDef(1)!.coins, 99);
    expect(levelDef(1)!.item, (layer: SkinLayer.gear, rarity: Rarity.epic));
    expect(needFor(31), 12345);
    expect(levelDef(32)!.coins, 3456);
  });

  for (final invalid in [
    'card:common',
    'bird:mythic',
    'bird',
    'any:legendary:extra',
    ':rare',
    'hat:COMMON',
  ]) {
    test('invalid level_items row $invalid falls back to its default row', () {
      final items = List<String>.from(tuning.raw('level_items') as List)
        ..[0] = invalid
        ..[30] = invalid;
      TuningValues.current = TuningValues.resolve({
        'level_items': jsonEncode(items),
      });
      expect(levelDef(1)!.item, (layer: SkinLayer.hat, rarity: Rarity.common));
      expect(levelDef(31)!.item, (layer: null, rarity: Rarity.legendary));
    });
  }
}
