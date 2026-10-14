import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §8: a graze (or a clean off-centre pass) that breaks a running
/// streak resets it at once and shows no text. The "GRAZE · streak lost"
/// notice is gone; the analytics `streak_broken` (cause) stays.
void main() {
  late AnalyticsSpy spy;

  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  /// Every text component the run HUD shows now.
  List<String> hudText(FlappySpikesGame g) => g.runHud!
      .descendants()
      .whereType<TextComponent>()
      .map((t) => t.text)
      .toList();

  /// P1-08: the renderers that paint text in a full frame, whatever their
  /// component type (a `TextComponent`, or a plain `Component` painting a
  /// `TextPainter` like the removed `_GrazeNotice`): the innermost
  /// `*.render` frame of every `drawParagraph` call, with the paragraph
  /// count per renderer (the stand-in test below proves it sees one).
  Map<String, int> textPainters(FlappySpikesGame g) {
    final canvas = TestRecordingCanvas();
    g.render(canvas);
    final frame = RegExp(r'^#\d+\s+(\S+)\.render \(', multiLine: true);
    final out = <String, int>{};
    for (final r in canvas.invocations) {
      if (r.invocation.memberName != #drawParagraph) continue;
      final who = frame.firstMatch(r.stack.toString())?.group(1) ?? '?';
      out[who] = (out[who] ?? 0) + 1;
    }
    return out;
  }

  /// No renderer outside [allowed] paints text now.
  void expectNoNewText(FlappySpikesGame g, Set<String> allowed) {
    final added = textPainters(g).keys.toSet().difference(allowed);
    expect(added, isEmpty, reason: 'new text painted by $added');
  }

  /// The text renderers of the next [frames] frames (every 5th sampled).
  Set<String> sample(FlappySpikesGame g, {int frames = 90}) {
    final out = textPainters(g).keys.toSet();
    for (var i = 0; i < frames; i++) {
      g.update(1 / 60);
      if (i % 5 == 0) out.addAll(textPainters(g).keys);
    }
    return out;
  }

  /// A run with a streak of [n] perfect passes. Returns the text renderers
  /// allowed after a break: the same non-perfect pass ([clean]) with no
  /// streak running (no break, so never a notice: its coin popup and the
  /// rest of a pass's own feedback) plus everything the streak showed.
  Future<(RunController, Set<String>)> streakOf(
    FlappySpikesGame g,
    int n, {
    bool clean = false,
  }) async {
    final run = await startRun(g);
    run.debugPass(perfect: false, clean: clean);
    await flushAndMount(g);
    expect(run.state.streak, 0);
    final allowed = sample(g);
    for (var i = 0; i < n; i++) {
      run.debugPass(perfect: true);
    }
    g.update(1 / 60);
    await flushAndMount(g);
    expect(run.state.streak, n);
    allowed.addAll(textPainters(g).keys);
    return (run, allowed);
  }

  tester.testGameWidget(
    'a graze with a streak running resets the streak and paints no new '
    'text (no text component, no text painted by any component)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, allowed) = await streakOf(game, 3);
      final before = hudText(game);
      expect(allowed, isNotEmpty); // the score at least
      run.debugPass(perfect: false); // a graze
      game.update(1 / 60);
      await flushAndMount(game);
      expectNoNewText(game, allowed);
      expect(run.state.streak, 0);
      expect(run.state.tier, 0);
      expect(spy.events.where((e) => e.$1 == 'streak_broken').single.$2, {
        'length': 3,
        'cause': 'graze',
      });
      expect(hudText(game), before, reason: 'no new text on a graze');
      expect(hudText(game), isNot(contains('GRAZE · streak lost')));
      // Still no text a few frames later.
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
        if (i % 5 == 0) expectNoNewText(game, allowed);
      }
      await flushAndMount(game);
      expect(hudText(game), before);
    },
  );

  tester.testGameWidget(
    'a clean off-centre pass also resets a running streak with no text '
    '(PRD-2.2 §11.1, cause clean)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, allowed) = await streakOf(game, 2, clean: true);
      final before = hudText(game);
      run.debugPass(perfect: false, clean: true);
      game.update(1 / 60);
      await flushAndMount(game);
      expect(run.state.streak, 0);
      expect(spy.events.where((e) => e.$1 == 'streak_broken').single.$2, {
        'length': 2,
        'cause': 'clean',
      });
      expect(hudText(game), before);
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
        if (i % 5 == 0) expectNoNewText(game, allowed);
      }
    },
  );

  tester.testGameWidget(
    'P1-08 the check sees a notice painted by a plain component (a '
    'TextPainter, like the removed _GrazeNotice)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (_, allowed) = await streakOf(game, 1);
      expect(allowed, isNot(contains('_CanvasNotice')));
      game.runHud!.add(_CanvasNotice());
      await flushAndMount(game);
      expect(textPainters(game)['_CanvasNotice'], 1);
      expect(() => expectNoNewText(game, allowed), throwsA(isA<TestFailure>()));
      expect(hudText(game), isNot(contains('GRAZE · streak lost')));
    },
  );
}

/// A stand-in for the removed `_GrazeNotice` (P1-08): a plain component
/// that paints its text with a [TextPainter].
class _CanvasNotice extends Component {
  @override
  void render(Canvas canvas) {
    TextPainter(
        text: const TextSpan(
          text: 'GRAZE · streak lost',
          style: TextStyle(fontSize: 22, color: Color(0xff828282)),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, const Offset(60, 250));
  }
}
