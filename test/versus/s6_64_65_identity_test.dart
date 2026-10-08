// Fix P45 R1: the own versus identity (§3.13 "Who plays", §5.7, §5.8,
// §5.10) — S6-65 the own name is the Play Games name / nickname on the
// intro plate, HUD chip and results card; S6-64 avatars come from the
// shared cache (Play Games icon image or URL), the glyph while missing.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/services/avatars.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 's3_13_service_test.dart' as fixture;
import 's3_13_versus_run_test.dart' show opponentAt;

Future<ui.Image> solid(ui.Color c, [int side = 40]) {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ui.Paint()..color = c,
  );
  return rec.endRecording().toImage(side, side);
}

Future<List<int>> pixel(
  void Function(ui.Canvas) paint,
  int w,
  int h,
  double x,
  double y,
) async {
  final rec = ui.PictureRecorder();
  paint(ui.Canvas(rec));
  final image = await rec.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  final i = (y.floor() * w + x.floor()) * 4;
  return bytes.sublist(i, i + 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const myKey = 'https://qa.invalid/me.png';
  const oppUrl = 'https://qa.invalid/opp.png';
  final src = opponentAt([1, 3, 6]);
  final opponent = OpponentRun(
    uid: src.uid,
    name: src.name,
    avatarUrl: oppUrl,
    score: src.score,
    best: src.best,
    level: src.level,
    timeline: src.timeline,
    runId: src.runId,
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: 711,
      versus: FakeVersusService(
        pool: [opponent],
        profile: const VersusProfile(
          name: 'SwiftKiwi482',
          avatarImage: myKey,
        ),
      ),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'S6-65 / S6-64 HUD chip and results card use the own name and avatars',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      await tester.runAsync(() async {
        g.images.add(myKey, await solid(const ui.Color(0xFFFF0000)));
        g.images.add(oppUrl, await solid(const ui.Color(0xFF0000FF)));
      });
      expect(g.myVersusName, 'SwiftKiwi482');
      final run = await startRun(g);
      final bar = g.runHud!.versus!;
      expect(bar.you.name, 'SwiftKiwi482');
      expect(bar.them.name, opponent.name);
      for (var i = 0; i < 60; i++) {
        g.update(1 / 60);
      }
      expect(g.runHud!.rowOpacity, 1);
      await tester.runAsync(() async {
        // HUD avatar squares: you at x 60 (outside left), them at the
        // right end of the box at x 170 (§5.7).
        expect(await pixel(bar.render, 320, 120, 64, 70), [255, 0, 0]);
        expect(await pixel(bar.render, 320, 120, 256, 70), [0, 0, 255]);
      });
      run.state.invulnerable = 0;
      killRunThroughSaves(g);
      await flushAndMount(g);
      await declineRevive(g);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.you.name, 'SwiftKiwi482');
      expect(page.you.avatar, myKey);
      expect(page.them!.avatar, oppUrl);
      await tester.runAsync(() async {
        final y = ResultsConfig.avatarTop + 5;
        expect(
          await pixel(page.you.render, 320, 711, page.you.centreX, y),
          [255, 0, 0],
        );
        expect(
          await pixel(page.them!.render, 320, 711, page.them!.centreX, y),
          [0, 0, 255],
        );
      });
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'S6-65 without any identity (no backend, no nickname) the name is "You"',
    setUp: (g, _) async {
      await g.ready();
    },
    verify: (g, _) async {
      expect(g.myVersusName, 'You');
      expect(g.myAvatarKey, '');
      await g.storage.saveVersusNickname('BoldOwl007');
      expect(g.myVersusName, 'BoldOwl007');
    },
  );

  testWidgets('S6-64 AvatarImages decodes a Play Games icon image (base64) '
      'into the cache; misses fall back to null', (tester) async {
    await tester.runAsync(() async {
      final image = await solid(const ui.Color(0xFF00FF00), 8);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final key = AvatarImages.dataUri(
        base64Encode(Uint8List.view(png.buffer)),
      );
      final avatars = AvatarImages(Images(prefix: ''));
      expect(avatars.lookup(key), isNull, reason: 'glyph while it loads');
      for (var i = 0; i < 50 && avatars.lookup(key) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final got = avatars.lookup(key);
      expect(got, isNotNull);
      expect(got!.width, 8);
      // No source (tests / desktop): a URL never loads, never throws.
      expect(avatars.lookup('https://qa.invalid/x.png'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(avatars.lookup('https://qa.invalid/x.png'), isNull);
      expect(avatars.lookup(''), isNull);
    });
  });

  test('S6-64 / S6-65 the service profile: Play Games name and icon image, '
      'else the nickname and the uploaded URL', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStorage();
    await store.load();
    final identity = fixture.FakeIdentity();
    final service = FirebaseVersusService(
      storageOf: () => store,
      backend: fixture.FakeBackend(),
      identity: identity,
      random: Random(4),
    );
    await service.initialize();
    final nick = store.versusNickname!;
    expect(service.me.name, nick);
    expect(service.me.avatarImage, '');
    identity.controller.add(
      const PlatformPlayer(id: 'g1', displayName: 'Hiesem', iconImage: 'QUJD'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.me.name, 'Hiesem');
    expect(service.me.avatarImage, 'data:image/png;base64,QUJD');
    await identity.controller.close();
  });
}
