import 'dart:async';

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/run/screens/versus_intro.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../run/shots/versus_shots_test.dart' as shots show rival, shot;

Future<void> _fonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  await Future.wait([opificio.load(), fredoka.load(), lvdc.load()]);
}

/// Steps the game until [until] holds (≤ [seconds]), letting microtasks run.
Future<void> stepUntil(
  FlappySpikesGame g,
  bool Function() until, {
  double seconds = 10,
}) async {
  for (var t = 0.0; t < seconds && !until(); t += 1 / 60) {
    g.update(1 / 60);
    await Future<void>.value();
  }
}

/// A screenshot (real async, outside the fake clock), then the game's own
/// size again.
Future<void> snap(FlappySpikesGame g, WidgetTester tester, String name) async {
  final size = g.size.clone();
  await tester.runAsync(() => shots.shot(g, 1.5, name));
  g.onGameResize(size);
}

/// PRD-2.3 §25.3 / §25.4 the VS screen is the loading screen.
void main() {
  setUpAll(_fonts);
  setUp(E2EHooks.reset);

  void vt(
    String name,
    FakeVersusService Function() versus,
    Future<void> Function(
      FlappySpikesGame g,
      AnalyticsSpy spy,
      FakeVersusService v,
      WidgetTester tester,
    )
    body, {
    double h = 711,
  }) {
    late AnalyticsSpy spy;
    late FakeVersusService v;
    FlameTester<FlappySpikesGame>(() {
      spy = AnalyticsSpy();
      v = versus();
      return createRunTestGame(worldHeight: h, services: spy, versus: v);
    }, gameSize: Vector2(320, h)).testGameWidget(
      name,
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) => body(g, spy, v, tester),
    );
  }

  vt(
    '§25.4 opponent held → today\'s intro (no wait, no versus_intro_wait)',
    () => FakeVersusService(pool: [shots.rival()], loadingIntro: true),
    (g, spy, v, tester) async {
      g.onScreenTap();
      await flushAndMount(g);
      final intro = g.versusIntro!;
      expect(intro.waited, isFalse);
      expect(intro.waiting, isFalse);
      expect(intro.opponent!.name, 'Pond');
      expect(intro.endAt, closeTo(7.34, .1), reason: 'the 2.2 schedule');
      expect(v.searchForStartCalls, 0);
      await finishVersusIntro(g);
      expect(g.run!.setup.opponent!.name, 'Pond');
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'versus_intro_wait'),
        isEmpty,
      );
    },
  );

  for (final h in [568.0, 711.0]) {
    final tag = h.round();
    late Completer<bool> search;
    late FakeVersusService fake;
    vt(
      '§25.4 found after 1.2 s ($tag): the reel cycles fillers, then lands on '
      'the opponent without a jump',
      () {
        search = Completer<bool>();
        return fake = FakeVersusService(
          loadingIntro: true,
          onSearch: () => search.future,
        );
      },
      (g, spy, v, tester) async {
        g.onScreenTap();
        expect(g.state, GameState.versusIntro, reason: 'every START shows it');
        await flushAndMount(g);
        final intro = g.versusIntro!;
        expect(intro.waiting, isTrue);
        await stepUntil(g, () => intro.time >= .5);
        await snap(g, tester, 's25_wait_0.5s_$tag');
        await stepUntil(g, () => intro.time >= 1.2);
        expect(intro.waiting, isTrue);
        expect(intro.reelName, isNotEmpty, reason: 'fillers spin');
        expect(VersusIntroFillersOnly.check(intro.reelName), isTrue);
        final shownAtFind = intro.reelName;
        final ticksAtFind = intro.reelIndex;
        fake.pool.add(shots.rival(name: 'RapidParrot123'));
        search.complete(true);
        await Future<void>.value();
        await Future<void>.value();
        g.update(0);
        expect(intro.waiting, isFalse);
        expect(intro.opponent!.name, 'RapidParrot123');
        expect(intro.resolvedAt, closeTo(1.2, .05));
        // No jump: the name shown stays until the next base-interval tick.
        expect(intro.reelName, shownAtFind);
        g.update(1 / 60);
        await stepUntil(g, () => intro.reelIndex > ticksAtFind);
        expect(intro.reelIndex, ticksAtFind + 1);
        await stepUntil(g, () => intro.locked);
        g.update(1 / 60);
        expect(intro.reelName, 'RapidParrot123');
        expect(intro.oppPlate.name, 'RapidParrot123');
        expect(intro.noRival, isFalse);
        expect(
          intro
              .descendants()
              .whereType<VersusIntroNoRivalHint>()
              .single
              .opacity,
          0,
        );
        await stepUntil(g, () => intro.time >= intro.lockAt + .5);
        await snap(g, tester, 's25_landed_$tag');
        await finishVersusIntro(g);
        expect(g.run!.setup.opponent!.name, 'RapidParrot123');
        final wait = analyticsLog(
          spy,
        ).where((e) => e.$1 == 'versus_intro_wait').single.$2!;
        expect(wait['found'], 1);
        expect(wait['waited_ms'] as int, closeTo(1200, 50));
        expect(analyticsLog(spy).where((e) => e.$1 == 'versus_solo'), isEmpty);
      },
      h: h,
    );

    vt(
      '§25.4 nothing in 3 s ($tag): NO RIVAL FOUND, then FLY SOLO, then a solo '
      'run; a late result stays held for the next START',
      () {
        search = Completer<bool>();
        return fake = FakeVersusService(
          loadingIntro: true,
          onSearch: () => search.future,
        );
      },
      (g, spy, v, tester) async {
        g.onScreenTap();
        await flushAndMount(g);
        final intro = g.versusIntro!;
        await stepUntil(g, () => !intro.waiting);
        expect(intro.time, closeTo(VersusConfig.introWait, .03));
        expect(intro.noRival, isTrue);
        await stepUntil(g, () => intro.locked);
        g.update(1 / 60);
        expect(intro.reelName, VersusConfig.noRivalText);
        expect(intro.oppPlate.noRival, isTrue);
        expect(intro.found.opacity, 0, reason: 'no MATCH FOUND! tag');
        // PRD-2.6 E3 / T4: honest copy beneath the plate, inside 320 pt.
        final hint = intro
            .descendants()
            .whereType<VersusIntroNoRivalHint>()
            .single;
        expect(hint.opacity, 1);
        expect(
          hint.y,
          greaterThanOrEqualTo(intro.oppPlate.y + intro.oppPlate.height),
        );
        final labels = hint.children.whereType<MenuText>().toList();
        expect(labels.map((l) => l.text).join(' '), VersusConfig.noRivalHint);
        for (final label in labels) {
          expect(hint.x + label.x - label.width / 2, greaterThanOrEqualTo(0));
          expect(hint.x + label.x + label.width / 2, lessThanOrEqualTo(320));
        }
        await stepUntil(g, () => intro.soloBanner != null);
        expect(intro.soloBanner!.text, VersusConfig.flySoloText);
        g.update(.4);
        await snap(g, tester, 's25_no_rival_$tag');
        // The search ends late: the opponent stays held for the next START.
        fake.pool.add(shots.rival());
        search.complete(true);
        await finishVersusIntro(g);
        expect(g.state, GameState.playing);
        expect(g.run!.setup.opponent, isNull, reason: 'solo');
        expect(g.runHud!.versus, isNull);
        expect(fake.pool, hasLength(1), reason: 'kept for the next START');
        final log = analyticsLog(spy);
        expect(
          log.where((e) => e.$1 == 'versus_solo').single.$2!['waited_ms'],
          3000,
        );
        expect(log.where((e) => e.$1 == 'versus_intro_wait').single.$2, {
          'waited_ms': 3000,
          'found': 0,
        });
      },
      h: h,
    );
  }

  vt(
    '§25.4 no-rival known at once: it slows to NO RIVAL FOUND without '
    'waiting the full 3 s',
    () => FakeVersusService(loadingIntro: true),
    (g, spy, v, tester) async {
      g.onScreenTap();
      await flushAndMount(g);
      final intro = g.versusIntro!;
      await stepUntil(g, () => !intro.waiting, seconds: 1);
      expect(intro.waiting, isFalse);
      expect(intro.noRival, isTrue);
      expect(intro.resolvedAt!, lessThan(.1));
      expect(
        intro.lockAt,
        lessThan(VersusConfig.introWait + 1),
        reason: 'lands on the normal reel schedule from the reel start',
      );
      await finishVersusIntro(g);
      expect(g.run!.setup.opponent, isNull);
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'versus_intro_wait').single.$2,
        {'waited_ms': intro.waitedMs, 'found': 0},
      );
    },
  );

  vt(
    '§25.3 FREE FLY is unchanged: no VS screen, no search',
    () => FakeVersusService(loadingIntro: true),
    (g, spy, v, tester) async {
      g.toggleHomeMode();
      g.onScreenTap();
      expect(g.state, GameState.playing);
      expect(g.versusIntro, isNull);
      expect(v.searchForStartCalls, 0);
    },
  );
}

/// The reel's filler names are display names only (PRD-2.2 §5.8 honesty).
abstract final class VersusIntroFillersOnly {
  static bool check(String name) => const [
    'Kiwi', 'Zap', 'Ace', 'Pip', 'Tofu', 'Rex', 'Luna', 'Fizz', 'Gizmo', //
    'Bean', 'Echo', 'Juno', 'Spike', 'Dash', 'Bubbles', 'Taco', 'Ziggy',
    'Nugget', 'Wren', 'Sky',
  ].contains(name);
}
