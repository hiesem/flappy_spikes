import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/ui/mystery_box.dart';
import 'package:flappy_spikes/run/config/pair_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/gift_box.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/pair_kind.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// O99 / PRD-2.6 §0.4: the paired-hoops gift is only a parameterised use of
/// the one mystery-box master. The pair's hitboxes, plane and timings are
/// not touched by this visual change; the behavioural authority stays
/// `test/run/hoops/s3_21_pair_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('O99 every pair reward uses the master look in its reward colours', () {
    for (final reward in PairReward.values) {
      final style = PairConfig.style(reward);
      final look = GiftBox.look(reward);
      expect(look.main, style.main);
      expect(look.dark, style.dark);
      expect(look.ribbon.toARGB32(), 0xFFFFFFFF);
      expect(look.label, isNull, reason: 'the gift tag carries the word');
    }
  });

  test('O99 the pair box keeps its 44 pt reach and style A proportions', () {
    final size = PairConfig.boxHalf * 2 * PairConfig.boxScale;
    expect(size, closeTo(43.5, 1e-9));
    expect(PairConfig.boxReach, PairConfig.boxHalf * PairConfig.boxScale + 2);
    expect(PairConfig.boxReach, 23.75);
    expect(
      size / MysteryBox.referenceSize,
      closeTo(PairConfig.boxScale * PairConfig.boxHalf * 2 / 80, 1e-9),
    );
  });

  test(
    'O99 every pair reward paints pixel-identically through the master',
    () async {
      for (final reward in PairReward.values) {
        final style = PairConfig.style(reward);
        final viaPair = await _raw((c) => GiftBox.paint(c, reward));
        final viaMaster = await _raw(
          (c) => MysteryBox.paintPair(
            c,
            main: style.main,
            dark: style.dark,
            size: PairConfig.boxHalf * 2 * PairConfig.boxScale,
          ),
        );
        expect(viaPair, viaMaster, reason: '$reward must use the master');
      }
    },
  );

  test('O99 the lid bit is the master lid under the pair transform', () async {
    for (final reward in PairReward.values) {
      final style = PairConfig.style(reward);
      final viaPair = await _raw((c) {
        c.scale(PairConfig.boxScale);
        c.translate(0, PairConfig.boxHalf + 2);
        GiftBox.paintLid(c, reward);
      });
      final viaMaster = await _raw((c) {
        c.scale(PairConfig.boxScale);
        c.translate(0, PairConfig.boxHalf + 2);
        MysteryBox.paint(
          c,
          MysteryBoxLook.colours(style.main, style.dark, label: null),
          size: PairConfig.boxHalf * 2,
          drawBody: false,
          lid: const MysteryBoxLid.closed(),
        );
      });
      expect(viaPair, viaMaster, reason: '$reward lid must use the master');
    }
  });

  test(
    'O99 the closed and opened pair boxes have distinct master states',
    () async {
      final closed = await _raw((c) => GiftBox.paint(c, PairReward.shield));
      final open = await _raw(
        (c) => GiftBox.paint(c, PairReward.shield, lid: false),
      );
      expect(_diff(closed, open), greaterThan(200));
    },
  );

  test('O99 the pair plane, ring offsets and hitbox are unchanged', () {
    const o = 230.0;
    final plan = SlotPlan(
      index: 12,
      kind: HoopKindId.pair,
      element: ElementId.pair,
      trackX: 300,
      centreY: 355.5,
      opening: RunConfig.opening0,
      ringOffsets: const [-o / 2, o / 2],
      advance: 310,
    );
    final hoop = Hoop(plan: plan, kind: PairHoopKind());
    final frame = hoop.frame();
    expect(hoop.position.x, 300);
    expect(hoop.planeX, 300);
    expect(hoop.position.y, 355.5);
    expect(hoop.rings, [-o / 2, o / 2]);
    expect(frame.rings, hoop.rings);
    expect(frame.opening, RunConfig.opening0);
    expect(frame.rimR, RunConfig.rimRadius);
    expect(frame.reach, RunConfig.opening0 / 2 + RunConfig.rimRadius);
    expect(frame.reach, 66);
    expect(RunConfig.pairOffsetAt711, o);
    expect(RunConfig.rimRadius, 7);
    expect(RingPainter.rx, 12);
  });
}

const int _w = 120, _h = 120;

Future<Uint8List> _raw(void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    const ui.Rect.fromLTWH(0, 0, 120, 120),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  c.translate(_w / 2, _h / 2);
  draw(c);
  final image = await rec.endRecording().toImage(_w, _h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return data!.buffer.asUint8List();
}

int _diff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}
