import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/ui/fadable_text.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/game/tintable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final stage0 = kPalettes[0]!;

  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  void expectStage0Colors(FlappySpikesGame game) {
    // The letterbox bars (what the GameWidget paints behind the world) use
    // the FOREGROUND tint so they match the spike strips on tall screens.
    expect(
      game.backgroundColor(),
      stage0.foreground,
      reason: 'letterbox bars must be the stage-0 fg #828282 (spike grey)',
    );
    expect(game.foregroundColor, stage0.foreground);

    // The world's own background is the in-world backdrop rect, painted with
    // the stage-0 BACKGROUND color. (Compared via toARGB32: Paint.color
    // round-trips through float32, so exact Color equality is too brittle.)
    final backdrop = game.world.children
        .whereType<RectangleComponent>()
        .firstWhere((c) => c.priority == -1000);
    expect(
      backdrop.paint.color.toARGB32(),
      stage0.background.toARGB32(),
      reason: 'world backdrop must be stage-0 bg #F1F1F1',
    );

    final expectedFilter =
        ColorFilter.mode(stage0.foreground, BlendMode.modulate).toString();

    // PRD-2 §3.1: hoops keep their fixed colours (the equipped skin, M0
    // pink by default) — the tint registry no longer applies to obstacles.
    final hoops = hoopsOf(game);
    expect(hoops, isNotEmpty, reason: 'need a hoop on screen to inspect');
    for (final hoop in hoops) {
      expect(hoop, isNot(isA<Tintable>()));
      expect(hoop.look.colors, isNull, reason: 'skin colours, not the tint');
    }

    // Spike strip tiles tinted with stage-0 fg.
    for (final strip in game.world.children.query<SpikeStrip>()) {
      for (final tile in strip.children.whereType<SpriteComponent>()) {
        expect(tile.paint.colorFilter, isNotNull,
            reason: 'spike strip tiles must carry the fg tint');
        expect(tile.paint.colorFilter.toString(), expectedFilter,
            reason: 'spike strip tint must be stage-0 fg #828282');
      }
    }

    // The watermark score text uses the stage-0 BACKGROUND color (by spec).
    final hud = game.world.children.query<ScoreHud>().single;
    final scoreText = hud.children.whereType<FadableTextComponent>().single;
    expect(scoreText.textRenderer.style.color, stage0.background,
        reason: 'score text color must be stage-0 bg (watermark effect)');

    // The score circle must be a LIGHTENED shade of the foreground tint so
    // pipe outlines stay visible against it.
    final circle = hud.children.whereType<SpriteComponent>().single;
    final lightened = Color.lerp(
      stage0.foreground,
      stage0.background,
      Config.hudCircleLighten,
    )!;
    expect(
      circle.paint.colorFilter.toString(),
      ColorFilter.mode(lightened, BlendMode.modulate).toString(),
      reason: 'score circle must be lighter than the pipe tint',
    );
  }

  /// Lets the run's first hoop finish mounting for the inspection.
  Future<void> ensureInspectableHoop(FlappySpikesGame game) =>
      flushAndMount(game);

  withGame.testGameWidget(
    'colors stay stage-0 through an unscored playing phase',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
    },
    verify: (game, tester) async {
      // Step well past any fade (> 1 s), no scoring.
      stepGame(game, 1.2, flapBelow: 320);
      expect(game.state, GameState.playing);
      expect(game.score, 0);
      await ensureInspectableHoop(game);
      expectStage0Colors(game);
    },
  );

  withGame.testGameWidget(
    'colors stay stage-0 after one hoop (no fade before hoop 10)',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
    },
    verify: (game, tester) async {
      game.run!.debugPass(); // one hoop passed
      stepGame(game, 1.2, flapBelow: 320);
      expect(game.state, GameState.playing);
      expect(game.score, 1);
      // §3.0.1 the stage changes every 10 hoops: no fade at hoop 1.
      stepGame(game, 1.0, flapBelow: 320);
      expect(game.state, GameState.playing);
      await ensureInspectableHoop(game);
      expectStage0Colors(game);
    },
  );
}
