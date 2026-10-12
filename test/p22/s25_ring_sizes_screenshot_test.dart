import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/hoops/kinds/normal.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §25 visual check: Live Wire, Frost Ring, Black Hole and FEVER at
/// hoop 20 (top row) and hoop 70 (bottom row). Writes `build/shots/p22/s25_rings.png`
/// (never committed); nothing is asserted beyond "rendered".
void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 9),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§25 shot: saw rings and FEVER at hoops 20 / 70',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      run.state.runClock = 0;
      Hoop hoop(double opening, HoopKindId kind, Object? extra) => Hoop(
        plan: SlotPlan(
          index: 20,
          kind: kind,
          element: kind == HoopKindId.saw ? ElementId.saw : ElementId.fever,
          trackX: 9000,
          centreY: 300,
          opening: opening,
          advance: 310,
          extra: extra,
        ),
        kind: kind == HoopKindId.saw ? SawHoopKind() : NormalHoopKind(),
      );

      const cell = 150.0, rowH = 300.0, scale = 2.0;
      final w = (cell * 4 * scale).toInt(), h = (rowH * 2 * scale).toInt();
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.scale(scale);
      c.drawRect(
        const ui.Rect.fromLTWH(0, 0, cell * 4, rowH * 2),
        ui.Paint()..color = const ui.Color(0xFFFCD9EE),
      );
      for (final (row, idx) in [(0, 20), (1, 70)]) {
        final opening = RunConfig.openingFor(idx);
        for (final (col, design) in [
          (0, SawDesign.liveWire),
          (1, SawDesign.frostRing),
          (2, SawDesign.blackHole),
        ]) {
          final s = SawRingState(
            hoop(opening, HoopKindId.saw, design),
            run.ctx,
            SawDesignArt.of(design),
            seed: 3,
          )..t = .4;
          c.save();
          c.translate(cell * col + cell / 2, rowH * row + rowH / 2);
          s.art.paintBack(c, s);
          s.art.paintFront(c, s);
          c.restore();
        }
        c.save();
        c.translate(cell * 3 + cell / 2, rowH * row + rowH / 2);
        FeverRingPainter.paint(c, opening, 1.1, 5, 0, front: false);
        FeverRingPainter.paint(c, opening, 1.1, 5, 0, front: true);
        c.restore();
      }
      await tester.runAsync(() async {
        final img = await rec.endRecording().toImage(w, h);
        final bytes = (await img.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        img.dispose();
        final file = File('build/shots/p22/s25_rings.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
        expect(bytes.length, greaterThan(10000));
      });
    },
  );
}
