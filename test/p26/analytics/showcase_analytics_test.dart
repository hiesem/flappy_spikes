import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/main.dart' show productionShowcaseFactory;
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/ftue_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ShowcaseShow.resetProcessMemoryForTests);

  final spy = AnalyticsSpy();
  List<Map<String, Object>> events(String name) => [
    for (final event in spy.events)
      if (event.$1 == name) event.$2!,
  ];

  for (final (save, via) in [
    ('none', 'all'),
    ('life', 'all'),
    ('shield', 'all'),
    ('none', 'cap'),
    ('none', 'fast'),
  ]) {
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        if (via == 'cap') 'gamesPlayed': 5,
        if (via == 'cap') 'showcaseSeen': 1,
      });
      return FlappySpikesGame(
        worldHeight: 711,
        soundEnabled: false,
        services: spy,
        showcaseFactory: productionShowcaseFactory(spy),
      )..runSeed = 7;
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'game-level showcase reports each highlight once and real end fields ($save/$via)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) => tester.runAsync(() async {
        final run = await startRun(game);
        spy.events.clear();
        if (save != 'none') {
          run.state
            ..shield = save == 'shield'
            ..extraLife = save == 'life'
            ..invulnerable = 0;
          expect(
            run.mistake(const Mistake(MistakeCause.missedHoop)),
            MistakeOutcome.saved,
          );
        }
        // Exercise both listeners: the progress model and the analytics router.
        run.events.emit(
          const HighlightStarted('portal', scripted: true, hoop: 7),
        );
        if (via == 'all') {
          run.events
            ..emit(const HighlightStarted('comet', scripted: false, hoop: 20))
            ..emit(const HighlightStarted('fever', scripted: false, hoop: 22));
        }
        final runNo = via == 'cap' ? 6 : 1;
        expect(events('highlight_seen'), [
          {'id': 'portal', 'scripted': true, 'run_no': runNo, 'hoop': 7},
          if (via == 'all')
            {'id': 'comet', 'scripted': false, 'run_no': runNo, 'hoop': 20},
          if (via == 'all')
            {'id': 'fever', 'scripted': false, 'run_no': runNo, 'hoop': 22},
        ]);
        for (var i = 0; i < 3; i++) {
          run.debugPass(perfect: true);
        }
        // A revive counts as usage in showcase_end.
        run.revive(ReviveKind.coins);
        run.state
          ..shield = false
          ..invulnerable = 0;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.died,
        );
        if (via == 'fast') run.state.hoopsPassed = 40;
        final summary = run.endRun();
        expect(summary.score, greaterThan(0));
        expect(summary.revives, 1);
        expect(summary.shieldUsed, save == 'shield');
        expect(summary.saves, save == 'none' ? 0 : 1);
        game.endRun(summary);
        game.endRun(summary); // the results guard must suppress a second end
        expect(events('showcase_end'), [
          {
            'step': via == 'cap' ? 2 : 1,
            'attempt': 1,
            'hoops': summary.hoopsPassed,
            'score': summary.score,
            'highlight': via == 'cap' ? 0 : 1,
            'cause': 'spikes',
            'shield_used': save == 'shield' ? 1 : 0,
            'revive_used': 1,
          },
        ]);
        expect(events('showcase_done').single['via'], via);
        expect(
          events(
            'ftue_step',
          ).where((event) => event['name'] == FtueStep.showcaseDone),
          hasLength(1),
        );
        await (game.showcaseProgress as ShowcaseShow).writesSettled;
      }),
    );
  }
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(
      worldHeight: 711,
      soundEnabled: false,
      services: spy,
      showcaseFactory: productionShowcaseFactory(spy),
    )..runSeed = 7;
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'planned portal pass emits highlight analytics through the real ride',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      spy.events.clear();
      Hoop? portal;
      run.events.on<HoopSpawned>((event) {
        if (event.plan.index == 7 && event.plan.kind == HoopKindId.portal) {
          portal = event.hoop;
        }
      });
      await flyRun(
        game,
        maxSeconds: 30,
        onFrame: (_) {
          if (portal != null) run.clock.running = false;
        },
      );
      expect(portal, isNotNull);
      run.events.emit(HoopPassed(portal));
      run.clock.running = true;
      stepGame(game, .1);
      expect(events('highlight_seen'), [
        {'id': 'portal', 'scripted': true, 'run_no': 1, 'hoop': 7},
      ]);
    },
  );
}
