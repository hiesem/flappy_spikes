import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/hud/name_chip.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/skins/art/card_name_art.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../run/shots/versus_shots_test.dart' show rival;

Future<List<int>> pixels(
  void Function(ui.Canvas) draw, {
  int width = 320,
  int height = 180,
}) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = (await image.toByteData())!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return data;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Fredoka')
      ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    await font.load();
  });

  test(
    'F9f name styles animate, preserve fitting, and freeze with their clock',
    () async {
      CardNameArt.debugClearLayoutCache();
      final before = CardNameArt.debugLayoutCount;
      final chip = NameChip('SparklySparrow888', 60, style: 'n_flappy');
      final prepared = CardNameArt.debugLayoutCount;
      expect(
        prepared,
        greaterThan(before),
        reason: 'construction prepares glyph layouts',
      );
      final plain = NameChip('SparklySparrow888', 60);
      expect(chip.shown, plain.shown);
      expect(chip.size, plain.size);
      expect(chip.width, lessThanOrEqualTo(86));
      final a = await pixels((c) => chip.render(c, 1, t: .2));
      expect(
        CardNameArt.debugLayoutCount,
        prepared,
        reason: 'the first rendered frame must not lay out styled glyphs',
      );
      final b = await pixels((c) => chip.render(c, 1, t: .6));
      expect(a, isNot(b), reason: 'Flappy must move on the HUD name plate');
      expect(
        await pixels((c) => chip.render(c, 1, t: .6)),
        b,
        reason: 'retaining the run clock must freeze animation exactly',
      );
      final invisible = await pixels((c) => chip.render(c, 0, t: .6));
      expect(invisible.every((v) => v == 0), isTrue);
    },
  );

  for (final h in [568.0, 711.0]) {
    for (final outcome in ['win', 'lose', 'draw', 'plain']) {
      final theirs = outcome == 'win' ? 1 : 5;
      final mine = outcome == 'draw' ? 5 : 3;
      final noCards = outcome == 'plain';
      final opponentLook = Look(
        bird: 'sky',
        card: noCards ? '' : 'f_neon|n_flappy|s_flawless',
      );
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: h,
          prefs: {
            'bestScore': 100,
            'ownedItems': ['card:f_orbit', 'card:n_fire', 'card:s_kaching'],
            'equippedItem.card': noCards ? '' : 'f_orbit|n_fire|s_kaching',
          },
          versus: FakeVersusService(
            pool: [rival(score: theirs, look: opponentLook)],
          ),
        ),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        'F9f $outcome: intro, HUD pause and winner sticker at ${h.round()}',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, tester) async {
          g.onScreenTap();
          await flushAndMount(g);
          final intro = g.versusIntro!;
          intro.debugFreeze(intro.lockAt + .8);
          await flushAndMount(g);
          expect(intro.oppPlate.bird, opponentLook);
          expect(intro.oppPlate.cardFrame, noCards ? '' : 'f_neon');
          expect(intro.oppPlate.cardName, noCards ? '' : 'n_flappy');
          expect(intro.oppPlate.cardSticker, noCards ? '' : 's_flawless');
          expect(intro.youPlate.cardSticker, noCards ? '' : 's_kaching');
          if (!noCards) {
            for (final plate in [intro.youPlate, intro.oppPlate]) {
              final styled = await tester.runAsync(() => pixels(plate.render));
              final original = plate.bird;
              plate.bird = original!.withItem(SkinLayer.card, '');
              final plain = await tester.runAsync(() => pixels(plate.render));
              plate.bird = original;
              expect(
                styled,
                isNot(plain),
                reason: 'each intro plate must actually draw its card art',
              );
            }
          }
          intro.unfreeze();
          await finishVersusIntro(g);
          await flushAndMount(g);
          final run = g.run!;
          if (run.waiting) g.onScreenTap();
          run.state.invulnerable = 100;
          stepGame(g, .5);
          final hud = g.runHud!;
          final bar = hud.versus!;
          hud.rowOpacity = 1;
          expect(bar.them.style, noCards ? '' : 'n_flappy');
          expect(bar.you.style, noCards ? '' : 'n_fire');
          final running = await tester.runAsync(() => pixels(bar.render));
          final layouts = CardNameArt.debugLayoutCount;
          stepGame(g, .2);
          final moved = await tester.runAsync(() => pixels(bar.render));
          expect(
            CardNameArt.debugLayoutCount,
            layouts,
            reason: 'both live HUD chips must use the cached glyph layouts',
          );
          if (!noCards) expect(running, isNot(moved));
          g.pause();
          await flushAndMount(g);
          final clock = bar.cardTime;
          final flash = bar.flash;
          expect(flash, greaterThan(0), reason: 'opponent just scored');
          stepGame(g, .5);
          expect(bar.flash, 0, reason: 'legacy score flash uses dt on pause');
          expect(bar.flash, lessThan(flash));
          final paused = await tester.runAsync(() => pixels(bar.render));
          stepGame(g, .4);
          expect(bar.cardTime, clock);
          expect(await tester.runAsync(() => pixels(bar.render)), paused);
          g.resume();
          await flushAndMount(g);
          hud.rowOpacity = 1;
          final image = (await tester.runAsync(() => pixels(bar.render)))!;
          if (!noCards) {
            final index = (93 * 320 + 241) * 4;
            expect(
              image.sublist(index, index + 4),
              isNot([255, 255, 255, 255]),
              reason: 'the neon frame must be visible over the name chip',
            );
          }
          // Frame decorations may extend 7 pt, but the score box covers them.
          for (final x in [99, 220]) {
            final index = (60 * 320 + x) * 4;
            final color = x == 99 ? HudConfig.youBox : g.foregroundColor;
            expect(image.sublist(index, index + 4), [
              (color.r * 255).round(),
              (color.g * 255).round(),
              (color.b * 255).round(),
              255,
            ]);
          }
          expect(
            image.skip(140 * 320 * 4).every((v) => v == 0),
            isTrue,
            reason: 'no victory sticker on the run HUD',
          );

          run.state.score = mine - 1;
          run.debugPass(clean: true);
          expect(run.state.score, mine);
          run.state.invulnerable = 0;
          killRunThroughSaves(g);
          await flushAndMount(g);
          await declineRevive(g);
          await flushAndMount(g);
          final page = g.resultsScreen!;
          final tags = [
            ...page.you.children.whereType<ResultsWinnerTag>(),
            ...?page.them?.children.whereType<ResultsWinnerTag>(),
          ];
          if (outcome == 'draw') {
            expect(tags, isEmpty, reason: 'draw has no winner');
          } else {
            expect(tags, hasLength(1));
            final tag = tags.single;
            expect(
              tag.slapTilt,
              closeTo(
                (outcome == 'win' ? 9 : -9) * 3.141592653589793 / 180,
                1e-9,
              ),
              reason: 'F9 mock tilts rival victory stickers to the left',
            );
            expect(
              tag.sticker,
              noCards
                  ? ''
                  : outcome == 'win'
                  ? 's_kaching'
                  : 's_flawless',
            );
            if (noCards) {
              expect(tag.hasSticker, isFalse);
              expect(tag.children, isNotEmpty, reason: 'plain WINNER label');
            } else {
              expect(tag.children, isEmpty, reason: 'sticker replaces WINNER');
              final early = await tester.runAsync(() => pixels(tag.render));
              expect(
                early!.every((v) => v == 0),
                isTrue,
                reason: 'sticker waits 0.7 s after arrival',
              );
              expect(tag.slapBurst.alive, 16);
              stepGame(g, 1.2);
              expect(tag.slapBurst.alive, 16);
              final late = await tester.runAsync(() => pixels(tag.render));
              expect(late!.any((v) => v != 0), isTrue);
            }
          }
        },
      );
    }
  }
}
