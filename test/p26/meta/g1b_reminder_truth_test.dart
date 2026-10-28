import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/services/reminders.dart';

void main() {
  test('persisted mission rewards and streak day reach reminder truth', () {
    final store = GameStorage()
      ..gamesPlayed = 4
      ..streakDays = 3
      ..streakLastDay = 120
      ..missionDay = 120
      ..missionTier = 0
      ..missions = Missions(missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 3),
        MissionProgress(template: MissionTemplate.m03, target: 15),
        MissionProgress(template: MissionTemplate.m11, target: 10),
      ]).toRecords();
    final truth = ReminderTruth.fromStorage(store);
    expect(truth.lastRunDay, 120);
    expect(truth.streakDays, 3);
    expect(truth.unfinishedMissionRewards, [35, 55]);
  });
}
