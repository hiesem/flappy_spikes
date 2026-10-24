import 'dart:math' as math;

import '../game/storage.dart';
import '../run/elements.dart';
import 'game_services.dart';

/// PRD-2.6 milestone ids emitted by the game's FTUE hooks.
abstract final class FtueStep {
  static const String firstTap = 'first_tap';
  static const String run1Highlight = 'run1_highlight';
  static const String run1End = 'run1_end';
  static const String run2End = 'run2_end';
  static const String run3End = 'run3_end';
  static const String showcaseDone = 'showcase_done';
  static const String run4Start = 'run4_start';
  static const String firstSaw = 'first_saw';
  static const String firstSqueeze = 'first_squeeze';
  static const String level1 = 'level_1';
  static const String level5 = 'level_5';
  static const String level10 = 'level_10';
  static const String versusFirstEnd = 'versus_first_end';
  static const String run20End = 'run20_end';

  static const Map<String, int> bits = {
    firstTap: 0,
    run1Highlight: 1,
    run1End: 2,
    run2End: 3,
    run3End: 4,
    showcaseDone: 5,
    run4Start: 6,
    firstSaw: 7,
    firstSqueeze: 8,
    level1: 9,
    level5: 10,
    level10: 11,
    versusFirstEnd: 12,
    run20End: 13,
  };
}

/// Records first-use milestones.
abstract class FtueTracker {
  const FtueTracker();

  void step(String id, {required int gamesPlayed});

  void highlight(
    String id, {
    required bool scripted,
    required int runNo,
    required int hoop,
  }) {}

  void firstMeet(
    ElementId element, {
    required int hoop,
    required int games,
    required bool forced,
    required bool survived,
  }) {}
}

class InertFtueTracker extends FtueTracker {
  const InertFtueTracker();

  @override
  void step(String id, {required int gamesPlayed}) {}
}

class PersistedFtueTracker extends FtueTracker {
  PersistedFtueTracker({
    required this.services,
    required this.storage,
    int Function()? secondsSinceInstall,
  }) : _injectedSecondsSinceInstall = secondsSinceInstall;

  final GameServices services;
  final GameStorage storage;
  final int Function()? _injectedSecondsSinceInstall;

  late final int Function() _secondsSinceInstall =
      _injectedSecondsSinceInstall ?? () => _installSeconds(storage);

  static int _installSeconds(GameStorage storage) {
    final installDay = storage.installDay;
    final elapsedDays = installDay == null
        ? 0
        : math.max(0, storage.today - installDay);
    return math.max(storage.playtimeSeconds, elapsedDays * 86400);
  }

  @override
  void step(String id, {required int gamesPlayed}) {
    final bit = FtueStep.bits[id];
    if (bit == null || storage.ftueSteps & (1 << bit) != 0) return;
    storage.saveFtueSteps(storage.ftueSteps | (1 << bit));
    services.track('ftue_step', {
      'name': id,
      's_since_install': _secondsSinceInstall(),
    });
  }

  @override
  void highlight(
    String id, {
    required bool scripted,
    required int runNo,
    required int hoop,
  }) => services.track('highlight_seen', {
    'id': id,
    'scripted': scripted,
    'run_no': runNo,
    'hoop': hoop,
  });

  @override
  void firstMeet(
    ElementId element, {
    required int hoop,
    required int games,
    required bool forced,
    required bool survived,
  }) => services.track('first_meet', {
    'element': element.storageId,
    'hoop': hoop,
    'games': games,
    'forced': forced,
    'survived': survived,
  });
}
