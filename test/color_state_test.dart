import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/ui/fadable_text.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
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

    // Pipe sprites tinted with stage-0 fg.
    final pipes = game.world.children.query<PipePair>();
    expect(pipes, isNotEmpty, reason: 'need a pipe on screen to inspect');
    for (final pipe in pipes) {
      for (final sprite in pipe.children.whereType<SpriteComponent>()) {
        expect(sprite.paint.colorFilter, isNotNull,
            reason: 'pipe sprites must carry the fg tint');
        expect(sprite.paint.colorFilter.toString(), expectedFilter,
            reason: 'pipe tint must be stage-0 fg #828282');
      }
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

  /// Ensures at least one pipe pair is mounted for tint inspection: mounts
  /// any pending spawn, then adds a controlled pair if the world is empty.
  Future<void> ensureInspectablePipe(FlappySpikesGame game) async {
    await flushAndMount(game);
    if (game.world.children.query<PipePair>().isEmpty) {
      final pipe = PipePair(gapBottomY: 300);
      await game.world.add(pipe);
      await flushAndMount(game);
    }
  }

  withGame.testGameWidget(
    'colors stay stage-0 through an unscored playing phase',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
      // No pipes near the bird during this test's window.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(1 / 60);
      await game.ready();
    },
    verify: (game, tester) async {
      // Step well past any fade (> 1 s), no scoring.
      stepGame(game, 1.2, flapBelow: 320);
      expect(game.state, GameState.playing);
      expect(game.score, 0);
      await ensureInspectablePipe(game);
      expectStage0Colors(game);
    },
  );

  withGame.testGameWidget(
    'colors stay stage-0 after scoring one point (no fade at score 1)',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
      // Controlled pair whose sensor already overlaps the bird: scores on
      // the first frames, then despawns; the natural t=1.5 spawn remains
      // for the tint inspection.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(1 / 60);
      await game.ready();
      final pipe = PipePair(gapBottomY: Config.birdY + Config.pipeGap / 2);
      await game.world.ensureAdd(pipe);
      await pipe.loaded;
      pipe.body.setTransform(Vector2(-20, Config.worldHeight / 2), 0);
    },
    verify: (game, tester) async {
      stepGame(game, 1.2, flapBelow: 320);
      expect(game.state, GameState.playing);
      expect(game.score, 1, reason: 'sensor should have fired by now');
      // stageOf(1) == 0: no color fade may be triggered by the point.
      stepGame(game, 1.0, flapBelow: 320);
      expect(game.state, GameState.playing);
      await ensureInspectablePipe(game);
      expectStage0Colors(game);
    },
  );
}
