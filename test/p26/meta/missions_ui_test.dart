import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import '../../helpers.dart';
import '../../home_layout_test.dart' show loadFonts;
import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/progression/missions.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({'gamesPlayed': 4}, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'panel renders three 54 pt rows at $height',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final panel = MissionsPanel(
          missions: Missions(
            missions: [
              const MissionProgress(
                template: MissionTemplate.m01,
                target: 3,
                progress: 1,
              ),
              const MissionProgress(template: MissionTemplate.m03, target: 15),
              const MissionProgress(
                template: MissionTemplate.m11,
                target: 10,
                progress: 10,
                paid: true,
              ),
            ],
          ),
          now: DateTime(2026, 1, 1, 18, 48),
          onDismiss: () {},
        );
        game.world.add(panel);
        await flushAndMount(game);
        final texts = panel.card.children
            .whereType<MenuText>()
            .map((e) => e.text)
            .toList();
        expect(
          texts,
          containsAll([
            'MISSIONS',
            'TODAY',
            missionCountdown(game.storage.now()),
            'ALL 3 DONE',
          ]),
        );
        final rows = panel.card.children
            .whereType<PositionComponent>()
            .where((e) => e.size == Vector2(256, 54))
            .toList();
        expect(rows, hasLength(3));
        final rowTexts = rows
            .expand((e) => e.children.whereType<MenuText>())
            .map((e) => e.text)
            .join(' ');
        expect(rowTexts, contains('PLAY 3 RUNS'));
        expect(
          rowTexts,
          isNot(contains(RegExp('EASY|MEDIUM|HARD|SWAP|CHEST'))),
        );
        expect(panel.card.y, greaterThanOrEqualTo(44));
        expect(
          panel.card.y + panel.card.height,
          lessThanOrEqualTo(height - 44),
        );
      },
    );
  }

  test('mission strip fits between slot and tiles at both heights', () {
    for (final height in [568.0, 711.0]) {
      final layout = height - 26;
      final strip = Config.homeMissionsRectFor(layout);
      expect(
        strip.top,
        greaterThanOrEqualTo(Config.homeSlotRectFor(layout).bottom),
      );
      expect(strip.bottom, lessThanOrEqualTo(Config.homeTileRowTopFor(height)));
      expect(
        Config.homeEmblemBottomFor(layout),
        lessThan(Config.homeModeRectFor(layout).top),
      );
    }
  });
  test('countdown and mission tasks use the approved copy', () {
    expect(missionCountdown(DateTime(2026, 1, 1, 18, 48)), 'NEW IN 5 H 12 M');
    expect(missionCountdown(DateTime(2026, 1, 1, 23, 1)), 'NEW IN 59 M');
    for (final template in MissionTemplate.values) {
      final task = missionTask(MissionProgress(template: template, target: 3));
      expect(task, isNot(contains('EASY')));
      expect(task, isNot(contains('MEDIUM')));
      expect(task, isNot(contains('HARD')));
    }
  });
}
