// Fix P45 R1: the own versus identity (§3.13 "Who plays", §5.7, §5.8,
// §5.10) — S6-65 the own name is the nickname on the intro plate, HUD chip
// and results card. WP-AV (2.4): the avatars are the sticker avatars drawn
// from the looks (S6-64's picture cache and Play Games names are gone).
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 's3_13_service_test.dart' as fixture;
import 's3_13_versus_run_test.dart' show opponentAt;

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

/// How many pixels in the [side] square at ([x], [y]) are clearly blue
/// (the sky bird's body).
Future<int> blue(
  void Function(ui.Canvas) paint,
  int w,
  int h,
  double x,
  double y,
  double side,
) async {
  final rec = ui.PictureRecorder();
  paint(ui.Canvas(rec));
  final image = await rec.endRecording().toImage(w, h);
  final d = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  var n = 0;
  for (var yy = y.ceil(); yy < (y + side).floor(); yy++) {
    for (var xx = x.ceil(); xx < (x + side).floor(); xx++) {
      final i = (yy * w + xx) * 4;
      if (d[i + 2] > 180 && d[i + 2] - d[i] > 80) n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final src = opponentAt([1, 3, 6]);
  final opponent = OpponentRun(
    uid: src.uid,
    name: src.name,
    look: const Look(bird: 'sky', hat: 'cap'),
    score: src.score,
    best: src.best,
    level: src.level,
    timeline: src.timeline,
    runId: src.runId,
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: 711,
      prefs: const {
        'ownedItems': ['bird:lime'],
        'equippedItem.bird': 'lime',
      },
      versus: FakeVersusService(
        pool: [opponent],
        profile: const VersusProfile(name: 'SwiftKiwi482'),
      ),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'S6-65 / WP-AV HUD chip and results card use the own name and the '
    'sticker avatars (yours: your look; theirs: their look)',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
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
        // right end of the box at x 170 (§5.7): their sky bird is blue,
        // your lime one is not.
        expect(await blue(bar.render, 320, 120, 60, 62, 38), 0);
        expect(
          await blue(bar.render, 320, 120, 222, 62, 38),
          greaterThan(38 * 38 * .08),
        );
      });
      expect(
        g.avatars.cachedKeys,
        containsAll([
          startsWith('lime|none|none|'),
          startsWith('sky|none|cap|'),
        ]),
      );
      run.state.invulnerable = 0;
      killRunThroughSaves(g);
      await flushAndMount(g);
      await declineRevive(g);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.you.name, 'SwiftKiwi482');
      expect(page.you.look.bird, 'lime');
      expect(page.them!.look, opponent.look);
      await tester.runAsync(() async {
        const s = ResultsConfig.avatarSize;
        const y = ResultsConfig.avatarTop;
        expect(
          await blue(page.you.render, 320, 711, page.you.centreX - s / 2, y, s),
          0,
        );
        expect(
          await blue(
            page.them!.render,
            320,
            711,
            page.them!.centreX - s / 2,
            y,
            s,
          ),
          greaterThan(s * s * .08),
        );
        // The corner of the square keeps the square colour (the sticker
        // is not a full-bleed photo).
        expect(
          await pixel(
            page.you.render,
            320,
            711,
            page.you.centreX - s / 2 + 1,
            y + 1,
          ),
          [
            (ResultsConfig.pink.r * 255).round(),
            (ResultsConfig.pink.g * 255).round(),
            (ResultsConfig.pink.b * 255).round(),
          ],
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
      await g.storage.saveVersusNickname('BoldOwl007');
      expect(g.myVersusName, 'BoldOwl007');
    },
  );

  test('WP-AV the service profile is always the nickname: a Play Games / '
      'Game Center player never changes it', () async {
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
    identity.controller.add(const PlatformPlayer(id: 'g1'));
    await Future<void>.delayed(Duration.zero);
    expect(service.me.name, nick);
    await identity.controller.close();
  });
}
