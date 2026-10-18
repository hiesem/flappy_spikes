import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/hud/fit_name.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
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

/// The three name lengths of PRD-2.3 §21.5: 10 characters, a 17-character
/// generated nickname, a 32-character Play Games name.
const _names = [
  'HiesemSurf',
  'SparklyFlappy1234',
  'Wolfgang Amadeus Mozart Junior 3',
];

/// PRD-2.3 §21.2 / §21.5 one name rule for every name tag.
void main() {
  setUpAll(_fonts);

  group('§21.2 fitName', () {
    // A monospace-like measure: 0.6 em per character.
    double mono(String s, double size) => s.length * size * .6;

    test('§21.2 a name that fits keeps its normal size', () {
      final f = fitName('HiesemSurf', 200, 22, mono);
      expect((f.text, f.size), ('HiesemSurf', 22));
    });

    test('§21.2 a wider name shrinks until it fits, never under 70 %', () {
      // 17 chars × 22 × .6 = 224 → fits 180 at 17.6 pt (80 %).
      final f = fitName('SparklyFlappy1234', 180, 22, mono);
      expect(f.text, 'SparklyFlappy1234', reason: 'digits stay');
      expect(f.size, lessThan(22));
      expect(f.size, greaterThanOrEqualTo(22 * HudConfig.nameMinScale));
      expect(mono(f.text, f.size), lessThanOrEqualTo(180));
    });

    test('§21.2 at 70 % and still too wide: cut and ended with "…"', () {
      const name = 'Wolfgang Amadeus Mozart Junior 3';
      final f = fitName(name, 116, 22, mono);
      expect(f.size, closeTo(22 * HudConfig.nameMinScale, 1e-9));
      expect(f.cut, isTrue);
      expect(f.text, endsWith('…'));
      expect(name.startsWith(f.text.substring(0, f.text.length - 1).trimRight()),
          isTrue);
      expect(mono(f.text, f.size), lessThanOrEqualTo(116));
      // The longest prefix: one more character would not fit.
      final n = f.text.length - 1;
      expect(mono('${name.substring(0, n + 1)}…', f.size), greaterThan(116));
    });
  });

  for (final h in [568.0, 711.0]) {
    final tag = h.round();
    for (final name in _names) {
      final n = name.length;
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: h,
          prefs: {'bestScore': 640, 'playerLevel': 6},
          versus: FakeVersusService(
            pool: [
              shots.rival(
                name: name,
                score: 12,
                best: 700,
                look: const Look(bird: 'grape', gear: 'shades', hat: 'cap'),
              ),
            ],
            profile: VersusProfile(name: name),
          ),
        ),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§21.5 a $n-character name fits the intro plates, the HUD chips and '
        'the results at $tag',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, tester) async {
          // ---- the VS intro plates
          g.onScreenTap();
          await flushAndMount(g);
          final intro = g.versusIntro!;
          for (var i = 0; i < 600 && intro.time < intro.lockAt + .6; i++) {
            g.update(1 / 60);
            await Future<void>.value();
          }
          for (final plate in [intro.youPlate, intro.oppPlate]) {
            // WP-NAME the own plate is "You" (no custom name set).
            final want = plate == intro.youPlate ? 'You' : name;
            expect(plate.name, want);
            final t = plate.shownText!;
            expect(t.size, greaterThanOrEqualTo(VersusConfig.plateNameSize * HudConfig.nameMinScale - 1e-6));
            expect(t.width, lessThanOrEqualTo(plate.nameRoom + .5));
            // The name ends before the emblem's overhang (never covered).
            final nameRight = VersusConfig.plateSlot +
                VersusConfig.plateNameLeft +
                t.width;
            final emblemLeft = plate.size.x -
                VersusConfig.plateSlot / 2 -
                VersusConfig.plateEmblemHalf;
            expect(nameRight, lessThanOrEqualTo(emblemLeft));
            if (n <= 10) expect(t.text, want, reason: 'a short name is whole');
            if (n >= 32 && want == name) expect(t.text, endsWith('…'));
          }
          final short = n <= 10 ? 's' : (n <= 17 ? 'm' : 'l');
          await tester.runAsync(() => shots.shot(g, 1.5, 's21_intro_${short}_$tag'));
          g.onGameResize(Vector2(320, h));
          await finishVersusIntro(g);

          // ---- the HUD name chips
          final bar = g.runHud!.versus!;
          for (final chip in [bar.you, bar.them]) {
            final want = chip == bar.you ? 'You' : name; // WP-NAME
            expect(chip.name, want);
            expect(chip.size, greaterThanOrEqualTo(HudConfig.chipNameSize * HudConfig.nameMinScale - 1e-6));
            expect(chip.width,
                lessThanOrEqualTo(HudConfig.boxWidth - 2 * HudConfig.chipPad + .5));
            if (n <= 10) expect(chip.shown, want);
          }
          for (var i = 0; i < 60; i++) {
            g.update(1 / 60);
          }
          await flushAndMount(g);
          await tester.runAsync(() => shots.shot(g, 1.5, 's21_hud_${short}_$tag'));
          g.onGameResize(Vector2(320, h));

          // ---- the results columns
          // §10: leave the waiting state before injecting a death. Without
          // the first tap, killRun bypassed the run's mistake pipeline and
          // screenshots still contained the undismissed first-run hint.
          g.onPlayfieldTap();
          stepGame(g, .4);
          await flushAndMount(g);
          final run = g.run!;
          run.state.score = 30;
          run.state.invulnerable = 0;
          killRun(g);
          await flushAndMount(g);
          await declineRevive(g);
          for (var i = 0; i < 30 && g.resultsScreen == null; i++) {
            g.update(1 / 60);
            await flushAndMount(g);
          }
          for (var i = 0; i < 17; i++) {
            stepGame(g, .1);
            await flushAndMount(g);
          }
          final page = g.resultsScreen!;
          for (final col in [page.you, page.them!]) {
            final t = col.nameText;
            expect(t.fontSize, greaterThanOrEqualTo(ResultsConfig.nameFontSize * HudConfig.nameMinScale - 1e-6));
            expect(t.size.x, lessThanOrEqualTo(ResultsConfig.nameRoomVersus + .5));
          }
          await tester.runAsync(() => shots.shot(g, 1.5, 's21_results_${short}_$tag'));
        },
      );
    }
  }
}
