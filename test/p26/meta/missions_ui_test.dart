import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
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
        Iterable<MenuText> allText(Component c) sync* {
          if (c is MenuText) yield c;
          for (final child in c.children) {
            yield* allText(child);
          }
        }

        final allowed = {
          'MISSIONS',
          'TODAY',
          missionCountdown(game.storage.now()),
          'ALL 3 DONE',
          'PLAY 3 RUNS',
          '1 / 3',
          '+20',
          '15 PERFECT PASSES',
          '0 / 15',
          '+35',
          'PASS 10 HOOPS IN ONE RUN',
          '10 / 10',
          '+55',
        };
        expect(allText(panel.card).map((t) => t.text).toSet(), allowed);
        final strip = game.homeScreen!.children
            .whereType<MissionsHomeStrip>()
            .single;
        final layout = Config.homeLayoutHeightFor(height, missions: true);
        expect(
          strip.position,
          Vector2(
            Config.homeMissionsRectFor(layout).left,
            Config.homeMissionsRectFor(layout).top,
          ),
        );
        expect(strip.size, Vector2(216, 22));
        strip.onPressed();
        await flushAndMount(game);
        expect(game.modalPopupOpen, isTrue);
        final opened = game.world.children.whereType<MissionsPanel>().last;
        opened.onDismiss();
        expect(game.modalPopupOpen, isFalse);
        expect(panel.card.y, greaterThanOrEqualTo(44));
        expect(
          panel.card.y + panel.card.height,
          lessThanOrEqualTo(height - 44),
        );
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'results row appears only when the board advances',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.storage.gamesPlayed = 3;
      final board = Missions(
        day: game.storage.today,
        missions: const [
          MissionProgress(
            template: MissionTemplate.m01,
            target: 3,
            progress: 2,
          ),
          MissionProgress(template: MissionTemplate.m03, target: 15),
          MissionProgress(
            template: MissionTemplate.m11,
            target: 10,
            progress: 5,
          ),
        ],
      );
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissionTier(0);
      await game.storage.saveMissions(board.toRecords());
      game.runDebug.ignoreGates = false;
      final run = await startRun(game);
      game.storage.gamesPlayed = 4;
      await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
      final summary = run.endRun();
      final page = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      game.world.add(page);
      await flushAndMount(game);
      final row = page.content.children.whereType<MissionResultsStrip>().single;
      expect(row.before, [2, 0, 5]);
      expect(row.missions.first.progress, 3);
      page.removeFromParent();
      await flushAndMount(game);
      game.missionsAtRunStart = RunEndBookkeeping.currentMissions(game.storage);
      final unchanged = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      game.world.add(unchanged);
      await flushAndMount(game);
      expect(
        unchanged.content.children.whereType<MissionResultsStrip>(),
        isEmpty,
      );
    },
  );

  var now = DateTime(2026, 1, 1, 18, 0);
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(clock: () => now),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'all done panel and strip use the completion state',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final board = Missions(
        missions: const [
          MissionProgress(
            template: MissionTemplate.m01,
            target: 3,
            progress: 3,
          ),
          MissionProgress(
            template: MissionTemplate.m03,
            target: 15,
            progress: 15,
          ),
          MissionProgress(
            template: MissionTemplate.m11,
            target: 10,
            progress: 10,
          ),
        ],
      );
      final panel = MissionsPanel(missions: board, now: now, onDismiss: () {});
      final strip = MissionsHomeStrip(
        missions: board,
        rect: const Rect.fromLTWH(52, 400, 216, 22),
        onPressed: () {},
        isActive: () => true,
      );
      game.world.addAll([panel, strip]);
      await flushAndMount(game);
      expect(
        panel.card.children.whereType<MenuText>().map((t) => t.text),
        contains('ALL DONE · NEW MISSIONS TOMORROW'),
      );
      expect(
        strip.children.whereType<MissionPips>().single.color,
        Config.menuPlum,
      );
      expect(strip.countdown!.text, 'NEW IN 6 H');
      now = DateTime(2026, 1, 1, 19, 0);
      stepGame(game, .1);
      expect(strip.countdown!.text, 'NEW IN 5 H');
    },
  );

  test('mission strip fits between slot and tiles at both heights', () {
    for (final height in [568.0, 711.0]) {
      final layout = Config.homeLayoutHeightFor(height, missions: true);
      final strip = Config.homeMissionsRectFor(layout);
      expect(strip.top, equals(Config.homeSlotRectFor(layout).bottom + 8));
      expect(strip.bottom, lessThanOrEqualTo(Config.homeTileRowTopFor(height)));
      expect(
        Config.homeEmblemBottomFor(layout),
        lessThan(Config.homeModeRectFor(layout).top),
      );
    }
  });
  FlameTester<FlappySpikesGame>(
    () => createTestGame({'gamesPlayed': 4}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'results pips fill and reveal the chest message',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final rows = [
        const MissionProgress(
          template: MissionTemplate.m01,
          target: 3,
          progress: 3,
        ),
        const MissionProgress(
          template: MissionTemplate.m03,
          target: 15,
          progress: 15,
        ),
        const MissionProgress(
          template: MissionTemplate.m11,
          target: 10,
          progress: 10,
        ),
      ];
      final strip = MissionResultsStrip(missions: rows, before: [3, 15, 5]);
      game.world.add(strip);
      await flushAndMount(game);
      expect(strip.label.text, 'MISSIONS');
      expect(strip.pips.fractionAt(2), closeTo(.5, .001));
      stepGame(game, .85);
      expect(strip.pips.fractionAt(2), greaterThan(.5));
      expect(strip.pips.fractionAt(2), lessThan(1));
      stepGame(game, 1);
      expect(strip.pips.fractionAt(2), 1);
      expect(strip.label.text, 'ALL DONE · CHEST ON HOME');
      expect(strip.pips.color, Config.menuPlum);
    },
  );
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
