import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/ui/mystery_box.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const int _w = 240, _h = 220;

Future<void> _loadFonts() async {
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await fredoka.load();
}

Future<Uint8List> _render(
  MysteryBoxLook look, {
  MysteryBoxLid? lid,
  double size = 160,
  bool drawBody = true,
  bool drawLid = true,
}) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  c.translate(_w / 2, _h / 2 + 10);
  MysteryBox.paint(
    c,
    look,
    size: size,
    lid: lid ?? const MysteryBoxLid.closed(),
    drawBody: drawBody,
    drawLid: drawLid,
  );
  final image = await rec.endRecording().toImage(_w, _h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return data!.buffer.asUint8List();
}

ui.Color _at(Uint8List px, int x, int y) {
  final i = (y * _w + x) * 4;
  return ui.Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
}

int _changed(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  test('O99 style A geometry and approved tier colours', () {
    expect(MysteryBox.referenceSize, 80);
    expect(MysteryBox.bodyBounds, const ui.Rect.fromLTRB(-40, -10, 40, 42));
    expect(MysteryBox.lidBounds, const ui.Rect.fromLTRB(-46, -24, 46, -8));
    expect(MysteryBoxTier.gold.main.toARGB32(), 0xFFFFB529);
    expect(MysteryBoxTier.gold.dark.toARGB32(), 0xFFC98A00);
    expect(MysteryBoxTier.silver.main.toARGB32(), 0xFFC3CDD3);
    expect(MysteryBoxTier.silver.dark.toARGB32(), 0xFF7F8C94);
    expect(MysteryBoxTier.bronze.main.toARGB32(), 0xFFDB8B4C);
    expect(MysteryBoxTier.bronze.dark.toARGB32(), 0xFF9C5A2A);
    expect(MysteryBoxTier.pink.main.toARGB32(), 0xFFEC008C);
    expect(MysteryBoxTier.pink.dark.toARGB32(), 0xFFB0006B);
    expect(MysteryBoxLook.levelBox.main.toARGB32(), 0xFFBDBDBD);
    expect(MysteryBoxLook.levelBox.dark.toARGB32(), 0xFF9C9C9C);
    expect(MysteryBoxLook.levelBox.label, '?');
  });

  test(
    'O99 renders gold, silver, bronze, pink and the level-box colour',
    () async {
      final gold = await _render(MysteryBoxLook.tier(MysteryBoxTier.gold));
      final silver = await _render(MysteryBoxLook.tier(MysteryBoxTier.silver));
      final bronze = await _render(MysteryBoxLook.tier(MysteryBoxTier.bronze));
      final pink = await _render(MysteryBoxLook.tier(MysteryBoxTier.pink));
      final level = await _render(MysteryBoxLook.levelBox);
      expect(_changed(gold, silver), greaterThan(500));
      expect(_changed(gold, bronze), greaterThan(500));
      expect(_changed(gold, pink), greaterThan(500));
      expect(_changed(gold, level), greaterThan(500));
      expect(_changed(level, silver), greaterThan(500));
      // The approved metal paints the body, the lid and the right-side shade.
      expect(_at(gold, _w ~/ 2 - 30, _h ~/ 2 + 25), MysteryBoxTier.gold.main);
      expect(_at(gold, _w ~/ 2 + 40, _h ~/ 2 + 25), MysteryBoxTier.gold.dark);
      expect(
        _at(silver, _w ~/ 2 + 40, _h ~/ 2 + 25),
        MysteryBoxTier.silver.dark,
      );
      expect(
        _at(bronze, _w ~/ 2 - 30, _h ~/ 2 + 25),
        MysteryBoxTier.bronze.main,
      );
    },
  );

  test(
    'O99 every approved palette renders with and without the "?" label',
    () async {
      final looks = [
        MysteryBoxLook.tier(MysteryBoxTier.gold),
        MysteryBoxLook.tier(MysteryBoxTier.silver),
        MysteryBoxLook.tier(MysteryBoxTier.bronze),
        MysteryBoxLook.tier(MysteryBoxTier.pink),
        MysteryBoxLook.levelBox,
      ];
      final labelless = [
        for (final look in looks)
          MysteryBoxLook.colours(look.main, look.dark, label: null),
      ];
      for (var i = 0; i < looks.length; i++) {
        final labelled = await _render(looks[i]);
        final unlabelled = await _render(labelless[i]);
        final changed = _changed(labelled, unlabelled);
        expect(
          changed,
          greaterThan(80),
          reason: 'palette $i removes its label',
        );
        expect(changed, lessThan(900));
      }

      final noBody = await _render(
        MysteryBoxLook.tier(MysteryBoxTier.gold),
        drawBody: false,
      );
      final body = await _render(MysteryBoxLook.tier(MysteryBoxTier.gold));
      expect(_changed(body, noBody), greaterThan(500));
    },
  );

  test('O99 closed → shake → lid-off steps deterministically', () async {
    final anim = const MysteryBoxAnimation();
    expect(anim.shakeFrom, closeTo(.3, 1e-9));
    expect(anim.shakeLength, closeTo(.75, 1e-9));
    expect(anim.lidOffFrom, closeTo(1.05, 1e-9));
    expect(anim.lidOffLength, closeTo(.5, 1e-9));
    expect(anim.at(0).phase, MysteryBoxPhase.closed);
    expect(anim.at(.299).phase, MysteryBoxPhase.closed);
    expect(anim.at(.3).phase, MysteryBoxPhase.shake);
    expect(anim.at(.3).shake, 0);

    final shaking = anim.at(.7);
    expect(shaking.phase, MysteryBoxPhase.shake);
    expect(shaking.revealTime, closeTo(.7, 1e-9));
    expect(shaking.shake, closeTo(8 / 15, 1e-9));
    expect(
      shaking.wobble,
      closeTo(math.sin(.7 * 42) * 406 / 75 * math.pi / 180, 1e-12),
    );
    expect(
      shaking.hop,
      closeTo(-math.sin(.7 * 21).abs() * (3 + 48 / 15), 1e-12),
    );
    expect(anim.at(1.049999).phase, MysteryBoxPhase.shake);
    expect(anim.at(1.05).phase, MysteryBoxPhase.lidOff);
    expect(anim.at(1.05).u, 0);

    final a = anim.at(.7), b = anim.at(.7);
    expect(a.shake, b.shake);
    expect(a.wobble, b.wobble);
    expect(a.hop, b.hop);

    final off = anim.at(1.2);
    expect(off.isOff, isTrue);
    expect(off.u, closeTo(.3, 1e-9));
    expect(off.lift, closeTo(18, 1e-9));
    expect(off.drop, closeTo(-41.4, 1e-9));
    expect(off.angle, closeTo(24 * math.pi / 180, 1e-9));
    expect(anim.at(1.55).u, closeTo(1, 1e-9));

    final comp = MysteryBoxComponent(
      look: MysteryBoxLook.tier(MysteryBoxTier.gold),
      boxSize: 160,
      animation: const MysteryBoxAnimation(),
    );
    comp.update(.3);
    expect(comp.lid.phase, MysteryBoxPhase.shake);
    comp.update(.7);
    expect(comp.lid.phase, MysteryBoxPhase.shake);
    comp.update(.05);
    expect(comp.lid.phase, MysteryBoxPhase.lidOff);
    comp.update(.5);
    expect(comp.lid.u, 1);
  });

  test(
    'O99 the lid phases draw different pixels in a deterministic order',
    () async {
      final look = MysteryBoxLook.tier(MysteryBoxTier.gold);
      final closed = await _render(look);
      final shake = await _render(
        look,
        lid: const MysteryBoxLid.shake(.5, revealTime: .675),
      );
      final off = await _render(look, lid: const MysteryBoxLid.off(1));
      expect(_changed(closed, shake), greaterThan(200));
      expect(_changed(shake, off), greaterThan(200));
      expect(_changed(closed, off), greaterThan(200));
      final again = await _render(
        look,
        lid: const MysteryBoxLid.shake(.5, revealTime: .675),
      );
      expect(_changed(shake, again), 0);
    },
  );

  test('O99 label-less pair boxes draw no "?" marks', () async {
    final pair = MysteryBoxLook.colours(
      const ui.Color(0xFFFF3B3B),
      const ui.Color(0xFFA50E14),
      label: null,
    );
    final a = await _render(pair);
    final b = await _render(pair);
    expect(_changed(a, b), 0);
    final labelled = await _render(
      MysteryBoxLook.colours(
        const ui.Color(0xFFFF3B3B),
        const ui.Color(0xFFA50E14),
      ),
    );
    expect(_changed(labelled, a), greaterThan(80));
  });

  testWidgets('O99 renders the style A contact sheet to build/p26', (
    tester,
  ) async {
    final looks = [
      MysteryBoxLook.tier(MysteryBoxTier.gold),
      MysteryBoxLook.tier(MysteryBoxTier.silver),
      MysteryBoxLook.tier(MysteryBoxTier.bronze),
      MysteryBoxLook.tier(MysteryBoxTier.pink),
      MysteryBoxLook.levelBox,
    ];
    final lids = [
      MysteryBoxLid.closed(),
      const MysteryBoxLid.shake(.5, revealTime: .675),
      MysteryBoxLid.off(1),
    ];
    const cellW = 240, cellH = 260, cols = 3, rows = 10;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.drawRect(
        ui.Rect.fromLTWH(
          0,
          0,
          (cellW * cols).toDouble(),
          (cellH * rows).toDouble(),
        ),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      for (var row = 0; row < rows; row++) {
        final labelled = row < looks.length;
        final base = looks[row % looks.length];
        final look = labelled
            ? base
            : MysteryBoxLook.colours(base.main, base.dark, label: null);
        for (var col = 0; col < lids.length; col++) {
          c.save();
          c.translate(cellW * col + cellW / 2, cellH * row + 175);
          MysteryBox.paint(c, look, size: 92, lid: lids[col]);
          c.restore();
        }
      }
      final image = await rec.endRecording().toImage(
        cellW * cols,
        cellH * rows,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('build/p26/mystery_box_style_a.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      expect(file.existsSync(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(8000));
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(cellW * cols, 720);
      expect(cellH * rows, 2600);
    });
  });
}
