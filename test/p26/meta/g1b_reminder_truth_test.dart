import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/services/reminders.dart';

void main() {
  test('persisted mission rewards and streak day reach reminder truth', () {
    final store = GameStorage()
      ..gamesPlayed = 4
      ..streakDays = 3
      ..streakLastDay = 120
      ..missionDay = 120
      ..missionTier = 0
      ..missions = Missions(
        missions: const [
          MissionProgress(
            template: MissionTemplate.m01,
            target: 3,
            progress: 3,
          ),
          MissionProgress(template: MissionTemplate.m03, target: 15),
          MissionProgress(template: MissionTemplate.m11, target: 10),
        ],
      ).toRecords();
    final truth = ReminderTruth.fromStorage(store);
    expect(truth.lastRunDay, 120);
    expect(truth.streakDays, 3);
    expect(truth.unfinishedMissionRewards, [35, 55]);
  });
  test('weekly and level reminder facts come from current persisted data', () {
    final now = DateTime.utc(2026, 10, 28);
    final week = WeeklyWeek.at(now);
    final store = GameStorage(clock: () => now)
      ..gamesPlayed = 6
      ..bestHoops = 40
      ..weeklyBest = {week.key: 30}
      ..lvlIndex = 3
      ..lvlPoints = 40
      ..recentScores = [10, 20, 30];
    final truth = ReminderTruth.fromStorage(store);
    expect(truth.weeklyUnlocked, isTrue);
    expect(truth.weeklyEndsAt, week.endsAt);
    expect(truth.weeklyBest, 30);
    expect(truth.nextLevelName, trackLevelDef(4)!.name);
    expect(truth.pointsNeeded, needFor(3) - 40);
    expect(truth.averageRunScore, 20);
    store.weeklyBest = {'old': 50};
    store.recentScores = [];
    final fresh = ReminderTruth.fromStorage(store);
    expect(fresh.weeklyBest, isNull);
    expect(fresh.averageRunScore, isNull);
  });
}
