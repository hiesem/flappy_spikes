import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/effects/life_icons.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §9: the HUD heart floats on the game. No grey panel: the empty
/// heart is see-through with the dotted outline, a partly filled heart is
/// see-through above its red fill and keeps the outline on the whole heart.
///
/// Records what [HeartIndicator.render] draws. Only the three calls the heart
/// makes are recorded; every other [Canvas] member is a no-op.
class _RecordingCanvas implements Canvas {
  final List<Rect> rects = [];
  final List<Rect> clips = [];
  final List<(PaintingStyle, Path)> paths = [];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void clipRect(
    Rect rect, {
    bool doAntiAlias = true,
    ClipOp clipOp = ClipOp.intersect,
  }) => clips.add(rect);

  @override
  void drawPath(Path path, Paint paint) => paths.add((paint.style, path));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  Iterable<Path> get fills =>
      paths.where((p) => p.$1 == PaintingStyle.fill).map((p) => p.$2);

  Iterable<Path> get outlines =>
      paths.where((p) => p.$1 == PaintingStyle.stroke).map((p) => p.$2);
}

void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  );

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  /// Draws the run's heart with [hearts] (0–3) collected and returns what it
  /// painted.
  Future<_RecordingCanvas> paintHeart(
    FlappySpikesGame game,
    RunController run,
    int hearts,
  ) async {
    run.state.hearts = hearts;
    game.runHud!.rowOpacity = 1;
    await flushAndMount(game);
    final canvas = _RecordingCanvas();
    game.runHud!.heart.render(canvas);
    return canvas;
  }

  final bounds = LifeIcons.heart24.getBounds();

  /// The top of the red fill when the heart is [f] full (clipped from below).
  double fillTop(double f) => bounds.bottom - f * bounds.height;

  tester.testGameWidget(
    'PRD-2.3.1 §9 the heart indicator paints no rectangle at 0, 1, 2 or 3 '
    'hearts (no grey panel)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (final n in [0, 1, 2, 3]) {
        final canvas = await paintHeart(game, run, n);
        expect(canvas.rects, isEmpty, reason: '$n hearts');
      }
    },
  );

  tester.testGameWidget(
    'PRD-2.3.1 §9 empty heart (0 hearts): no fill, the dotted outline only',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final canvas = await paintHeart(game, run, 0);
      expect(canvas.clips, isEmpty);
      expect(canvas.fills, isEmpty);
      expect(canvas.outlines, isNotEmpty, reason: 'the dashed outline');
    },
  );

  tester.testGameWidget(
    'PRD-2.3.1 §9 one and two of three hearts: the red fill rises from the '
    'bottom (clipped), the unfilled top is not painted, the outline still '
    'traces the whole heart',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (final (n, f) in [(1, 1 / 3), (2, 2 / 3)]) {
        final canvas = await paintHeart(game, run, n);
        expect(canvas.clips, hasLength(1), reason: '$n hearts');
        expect(canvas.clips.single.top, closeTo(fillTop(f), 1e-9));
        expect(canvas.clips.single.bottom, 26);
        expect(canvas.fills, hasLength(1), reason: 'the red fill');
        expect(canvas.fills.single, same(LifeIcons.heart24));
        expect(canvas.outlines, isNotEmpty, reason: 'the outline is on');
        expect(canvas.rects, isEmpty);
      }
    },
  );

  tester.testGameWidget(
    'PRD-2.3.1 §9 three hearts (full): red, no outline (as before)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final canvas = await paintHeart(game, run, 3);
      expect(canvas.clips.single.top, closeTo(fillTop(1), 1e-9));
      expect(canvas.fills, hasLength(1));
      expect(canvas.outlines, isEmpty);
      expect(canvas.rects, isEmpty);
    },
  );
}
