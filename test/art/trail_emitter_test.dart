import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'art_render.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvasWidth = 240;
  const canvasHeight = 90;
  final head = const ui.Offset(180, 45);

  void prime(TrailEmitter e, double seconds, {double k = 1, double vx = -140}) {
    const dt = 1 / 60;
    var elapsed = 0.0;
    while (elapsed < seconds - 1e-9) {
      e.emit(head, dt, k: k, vx: vx);
      e.step(dt);
      elapsed += dt;
    }
  }

  Future<Uint8List> render(TrailEmitter e, WidgetTester tester) =>
      capture(tester, canvasWidth, canvasHeight, (canvas) => e.paint(canvas));

  test('ids match the PRD 5.5 catalogue in display order', () {
    // PRD 2.6 F10: three skill items follow the original grid.
    expect(TrailEmitter.ids, [for (final i in itemsFor(SkinLayer.trail)) i.id]);
    expect(TrailEmitter.ids, hasLength(33));
    expect(TrailEmitter.fallbackId, 'flame');
  });

  test('pool is bounded and keeps recycling on a long stream', () {
    for (final id in TrailEmitter.ids) {
      final e = TrailEmitter(id, random: math.Random(1));
      prime(e, 40);
      expect(
        e.particleCount,
        lessThanOrEqualTo(TrailEmitter.capacity),
        reason: '$id stayed bounded',
      );
      prime(e, 40);
      expect(
        e.particleCount,
        lessThanOrEqualTo(TrailEmitter.capacity),
        reason: '$id stayed bounded',
      );
      // PRD F10 skill trails are procedural paths rather than particles.
      if (const {'thread', 'constellation', 'fireflies'}.contains(id)) {
        expect(e.pathLength, 1, reason: '$id emits a path');
        expect(e.pathPoint(0), head, reason: '$id tracks the trail head');
      } else if (id != 'rainbow') {
        expect(e.particleCount, greaterThan(0), reason: '$id emits particles');
      }
    }
  });

  test('a flood of emissions cannot grow the pool beyond capacity', () {
    final e = TrailEmitter('laser', random: math.Random(2));
    for (var frame = 0; frame < 4000; frame++) {
      e.emit(head, 1 / 60);
    }
    expect(e.particleCount, TrailEmitter.capacity);
  });

  test('clear() drops particles and history', () {
    final e = TrailEmitter('flame', random: math.Random(3));
    prime(e, .5);
    expect(e.particleCount, greaterThan(0));
    e.clear();
    expect(e.particleCount, 0);

    final ribbon = TrailEmitter('rainbow', random: math.Random(3));
    prime(ribbon, .5);
    ribbon.clear();
    final recorder = ui.PictureRecorder();
    ribbon.paint(ui.Canvas(recorder));
    recorder.endRecording().dispose();
  });

  test('emit and step are no-ops for a non-positive dt', () {
    final e = TrailEmitter('flame', random: math.Random(4));
    e.emit(head, 0);
    e.step(0);
    e.emit(head, -1);
    e.step(-1);
    expect(e.particleCount, 0);
  });

  test('switching trailId clears the old particles', () {
    final e = TrailEmitter('flame', random: math.Random(5));
    prime(e, .5);
    expect(e.particleCount, greaterThan(0));
    e.trailId = 'bubbles';
    expect(e.particleCount, 0);
    // Assigning the same id is a no-op, not a clear.
    prime(e, .2);
    final count = e.particleCount;
    e.trailId = 'bubbles';
    expect(e.particleCount, count);
  });

  testWidgets('unknown trail id falls back to the classic flame', (
    tester,
  ) async {
    final known = TrailEmitter('flame', random: math.Random(7));
    final unknown = TrailEmitter('not-a-trail', random: math.Random(7));
    prime(known, 1);
    prime(unknown, 1);
    expect(await render(unknown, tester), equals(await render(known, tester)));
    expect(hasInk(await render(known, tester)), isTrue);
  });

  testWidgets('a seeded Random makes emission deterministic', (tester) async {
    for (final id in const [
      'flame',
      'sparkle',
      'bubbles',
      'laser',
      'bolt',
      'notes',
    ]) {
      final a = TrailEmitter(id, random: math.Random(11));
      final b = TrailEmitter(id, random: math.Random(11));
      prime(a, 1);
      prime(b, 1);
      expect(
        await render(a, tester),
        equals(await render(b, tester)),
        reason: id,
      );
    }
  });

  testWidgets('every trail paints ink after a second of emission', (
    tester,
  ) async {
    for (final id in TrailEmitter.ids) {
      final e = TrailEmitter(id, random: math.Random(13));
      e.lookPainter = stubLook;
      prime(e, 1);
      final rgba = await render(e, tester);
      expect(hasInk(rgba), isTrue, reason: '$id paints');
    }
  });

  testWidgets('the ribbon draws from its path history without particles', (
    tester,
  ) async {
    final e = TrailEmitter('rainbow', random: math.Random(9));
    prime(e, 1);
    expect(e.particleCount, 0);
    expect(hasInk(await render(e, tester)), isTrue);
  });

  testWidgets('the Afterimage copies need an injected look painter', (
    tester,
  ) async {
    final withLook = TrailEmitter(
      'echo',
      random: math.Random(10),
      lookPainter: stubLook,
    )..look = Look.defaults;
    final withoutLook = TrailEmitter('echo', random: math.Random(10));
    prime(withLook, 2);
    prime(withoutLook, 2);

    final withRgba = await render(withLook, tester);
    final withoutRgba = await render(withoutLook, tester);
    expect(hasInk(withRgba), isTrue);
    expect(
      hasInk(withoutRgba),
      isTrue,
      reason: 'square sparks draw either way',
    );
    expect(
      inkPixels(withRgba),
      greaterThan(inkPixels(withoutRgba)),
      reason: 'the ghost copies only appear with a look painter',
    );
  });

  testWidgets('tile painter emits behind the orb', (tester) async {
    const orb = ui.Offset(60, 40);
    final e = TrailEmitter('flame', random: math.Random(12));
    final bare = await capture(tester, 96, 96, (canvas) {
      TrailEmitter.paintTrailTile(canvas, e, orb, 0, 1);
    });
    expect(e.particleCount, 0, reason: 'dt = 0 draws without emitting');
    expect(hasInk(bare), isTrue, reason: 'the orb itself is drawn');

    for (var frame = 0; frame < 60; frame++) {
      final recorder = ui.PictureRecorder();
      TrailEmitter.paintTrailTile(
        ui.Canvas(recorder),
        e,
        orb,
        1 / 60,
        frame / 60,
      );
      recorder.endRecording().dispose();
    }
    expect(e.particleCount, greaterThan(0));
    final primed = await capture(tester, 96, 96, (canvas) {
      TrailEmitter.paintTrailTile(canvas, e, orb, 0, 1);
    });
    expect(
      primed,
      isNot(equals(bare)),
      reason: 'the trail shows behind the orb',
    );
  });
}
