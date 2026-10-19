// PRD-2.3 §2 / §3 / §4 / §5.6 / §6.1: the share card flow, the random
// picks, the share call and its text-only fallback, the card data, the
// analytics and the Invite tile.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/share_sheet.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/share/share_card.dart';
import 'package:flappy_spikes/share/share_content.dart';
import 'package:flappy_spikes/share/share_flow.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Records share-sheet calls instead of opening the sheet.
class SheetSpy implements ShareSheet {
  final List<(String, List<XFile>)> calls = [];
  bool failWithFiles = false;

  @override
  Future<void> share({
    required String text,
    List<XFile> files = const [],
  }) async {
    if (failWithFiles && files.isNotEmpty) throw StateError('no files');
    calls.add((text, files));
  }
}

ShareCardData sampleData() => ShareContent(Random(1)).spotlight(
  score: 12,
  best: 140,
  level: 3,
  look: const Look(bird: 'sky'),
  name: 'Tester',
);

/// Width and height from a PNG header.
(int, int) pngSize(Uint8List b) {
  expect(b.sublist(1, 4), 'PNG'.codeUnits);
  final d = ByteData.sublistView(b);
  return (d.getUint32(16), d.getUint32(20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§3 / §6.1 text picks', () {
    test('every id 1-5 comes out of both lists; texts carry the score and '
        'end with the share link', () {
      final picks = ShareContent(Random(42));
      final texts = <int>{}, banners = <int>{};
      for (var i = 0; i < 200; i++) {
        final d = picks.spotlight(
          score: 37,
          best: 50,
          level: 2,
          look: Look.defaults,
          name: 'n',
        );
        texts.add(d.textId);
        banners.add(d.bannerId);
        expect(d.text, contains('37'));
        expect(d.text, endsWith('flappyspikes.com/get'));
        expect(
          d.text,
          Config.shareTexts[d.textId - 1].replaceAll('{score}', '37'),
        );
        expect(Config.shareBanners, contains(d.banner));
        expect(d.banner, Config.shareBanners[d.bannerId - 1]);
      }
      expect(texts, {1, 2, 3, 4, 5});
      expect(banners, {1, 2, 3, 4, 5});
    });

    test('the picks are independent: the text does not predict the banner', () {
      final picks = ShareContent(Random(7));
      final seen = <int, Set<int>>{};
      for (var i = 0; i < 1000; i++) {
        final d = picks.spotlight(
          score: 1,
          best: 1,
          level: 0,
          look: Look.defaults,
          name: 'n',
        );
        seen.putIfAbsent(d.textId, () => {}).add(d.bannerId);
      }
      for (final t in [1, 2, 3, 4, 5]) {
        expect(seen[t], {1, 2, 3, 4, 5}, reason: 'text $t');
      }
    });

    test('§3.1-3.3 the approved texts, in order', () {
      expect(Config.shareTexts, [
        'I scored {score} points in Flappy Spikes 🐦 Think you can beat me? flappyspikes.com/get',
        '{score} points in Flappy Spikes. Beat that, I dare you 😏 flappyspikes.com/get',
        'Just hit {score} points in Flappy Spikes 🐦 Your move. flappyspikes.com/get',
        "{score} points in Flappy Spikes. Bet you can't top it 😎 flappyspikes.com/get",
        'I got {score} points in Flappy Spikes 🔥 Can you do better? flappyspikes.com/get',
      ]);
      expect(Config.shareBanners, [
        'BEAT MY SCORE!',
        'TRY TO BEAT ME!',
        'I DARE YOU!',
        'CAN YOU BEAT IT?',
        'THINK YOU CAN WIN?',
      ]);
      expect(Config.inviteTexts, [
        'Can you beat me at Flappy Spikes? flappyspikes.com/get',
        "Bet you can't beat me at Flappy Spikes! flappyspikes.com/get",
        'Come play Flappy Spikes with me, I dare you! flappyspikes.com/get',
      ]);
    });

    test('§2.2 a new player: dodge and flock both come out, one of the 5 '
        'banners and one of the 3 new-player texts', () {
      final picks = ShareContent(Random(3));
      final kinds = <ShareCardKind>{}, texts = <int>{}, banners = <int>{};
      for (var i = 0; i < 200; i++) {
        final d = picks.invite(
          best: 0,
          lastScore: 0,
          level: 0,
          look: Look.defaults,
          name: 'n',
        );
        kinds.add(d.kind);
        texts.add(d.textId);
        banners.add(d.bannerId);
        expect(Config.inviteTexts, contains(d.text));
        expect(d.text, endsWith('flappyspikes.com/get'));
        expect(d.text, isNot(contains('play.google.com')));
        expect(d.level, 0);
      }
      expect(kinds, {ShareCardKind.dodge, ShareCardKind.flock});
      expect(texts, {1, 2, 3});
      expect(banners, {1, 2, 3, 4, 5});
    });

    test('§2.2 best > 0: the Spotlight card of the last score, or the best '
        'when none is stored; a last run of 0 shows 0', () {
      final a = ShareContent(Random(5)).invite(
        best: 140,
        lastScore: 33,
        level: 2,
        look: Look.defaults,
        name: 'n',
      );
      expect(a.kind, ShareCardKind.spotlight);
      expect(a.score, 33);
      expect(a.best, 140);
      expect(a.level, 2, reason: 'WP-L the stored level, not the best');
      expect(a.text, contains('33'));
      final b = ShareContent(Random(5)).invite(
        best: 140,
        lastScore: null,
        level: 2,
        look: Look.defaults,
        name: 'n',
      );
      expect(b.score, 140);
      final c = ShareContent(Random(5)).invite(
        best: 140,
        lastScore: 0,
        level: 2,
        look: Look.defaults,
        name: 'n',
      );
      expect(c.score, 0);
      for (final d in [a, b, c]) {
        expect(d.text, isNot(contains('play.google.com')));
      }
    });
  });

  group('§2.0 / §6.1 the share call', () {
    test(
      'passes the text and exactly one 1080 x 1080 image/png file',
      () async {
        final sheet = SheetSpy();
        final dir = await Directory.systemTemp.createTemp('share_test');
        final flow = ShareFlow(sheet: sheet, directory: () async => dir);
        final data = sampleData();
        expect(await flow.share(data), isTrue);
        expect(sheet.calls, hasLength(1));
        final (text, files) = sheet.calls.single;
        expect(text, data.text);
        expect(files, hasLength(1));
        expect(files.single.mimeType, 'image/png');
        expect(pngSize(await files.single.readAsBytes()), (1080, 1080));
        await dir.delete(recursive: true);
      },
    );

    test('when the painter throws, the text goes alone', () async {
      final sheet = SheetSpy();
      final flow = ShareFlow(
        sheet: sheet,
        render: (_, _) => throw StateError('painter broke'),
      );
      expect(await flow.share(sampleData()), isFalse);
      expect(sheet.calls.single.$2, isEmpty);
      expect(sheet.calls.single.$1, sampleData().text);
    });

    test('when the sheet refuses the file, the text goes alone', () async {
      final sheet = SheetSpy()..failWithFiles = true;
      final dir = await Directory.systemTemp.createTemp('share_test');
      final flow = ShareFlow(sheet: sheet, directory: () async => dir);
      expect(await flow.share(sampleData()), isFalse);
      expect(sheet.calls.single.$2, isEmpty);
      await dir.delete(recursive: true);
    });

    test(
      'the card image is freed after encoding (renders twice in a row)',
      () async {
        final assets = await ShareCardAssets.load();
        for (var i = 0; i < 2; i++) {
          final png = await renderShareCardPng(sampleData(), assets);
          final codec = await ui.instantiateImageCodec(png);
          final f = await codec.getNextFrame();
          expect(f.image.width, 1080);
          f.image.dispose();
          codec.dispose();
        }
      },
    );
  });

  group('§5.6 / §12 config', () {
    test('URLs', () {
      expect(Config.privacyPolicyUrl, 'https://flappyspikes.com/privacy');
      expect(Config.shareUrl, 'flappyspikes.com/get');
      expect(Config.siteUrl, 'https://flappyspikes.com');
      expect(Config.tagline, 'FLAP FAST, FLY FAR');
    });

    test('§12 no string in lib/ contains "touch the spikes"', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().toLowerCase().contains('touch the spikes')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('§9 / §6.1 app icon', () {
    test('Android launcher resources exist at every density and the '
        'adaptive icon has the three layers', () {
      const res = 'android/app/src/main/res';
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File('$res/mipmap-$d/ic_launcher.png').existsSync(),
          isTrue,
          reason: d,
        );
        for (final layer in ['foreground', 'background', 'monochrome']) {
          expect(
            File('$res/drawable-$d/ic_launcher_$layer.png').existsSync(),
            isTrue,
            reason: '$d $layer',
          );
        }
      }
      final xml = File(
        '$res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(xml, contains('@drawable/ic_launcher_foreground'));
      expect(xml, contains('@drawable/ic_launcher_background'));
      expect(xml, contains('@drawable/ic_launcher_monochrome'));
    });

    test('assets/images/app_icon.png is the v3 (icon10) picture: 1024, no '
        'alpha, sky blue corners (the splash colour), the pink bird in the middle', () async {
      final bytes = File('assets/images/app_icon.png').readAsBytesSync();
      expect(pngSize(bytes), (1024, 1024));
      expect(bytes[25], 2, reason: 'colour type 2 = RGB, no alpha');
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final px = (await image.toByteData())!;
      int at(int x, int y) => px.getUint32((y * 1024 + x) * 4);
      for (final (x, y) in [(8, 8), (1015, 8), (8, 1015), (1015, 1015)]) {
        final c = at(x, y);
        // icon10: #2CA4F4 corners.
        expect(c >> 24, lessThan(70), reason: 'corner ($x, $y) red');
        expect((c >> 8) & 0xFF, greaterThan(220), reason: 'corner blue');
      }
      final pink = at(300, 820); // the bird's body, left of the beak
      expect(pink >> 24, greaterThan(200), reason: 'pink red channel');
      expect((pink >> 16) & 0xFF, lessThan(80), reason: 'pink green channel');
      image.dispose();
      codec.dispose();
    });

    test('the splash colour is the icon\'s corner blue #2CA4F4 everywhere', () {
      expect(
        RegExp(
          'color: "#2CA4F4"',
        ).allMatches(File('pubspec.yaml').readAsStringSync()),
        hasLength(3),
      );
      for (final v in ['values-v31', 'values-night-v31']) {
        final xml = File(
          'android/app/src/main/res/$v/styles.xml',
        ).readAsStringSync();
        expect(xml, isNot(contains('#2BC8F5')), reason: v);
        expect(RegExp('#2CA4F4').allMatches(xml), hasLength(2), reason: v);
      }
    });

    test(
      'the Android adaptive icon is the whole picture filling the 72 dp '
      'view (one crisp layer), the foreground is empty',
      () async {
        Future<ByteData> rgba(String path) async {
          final bytes = File(path).readAsBytesSync();
          expect(pngSize(bytes), (432, 432), reason: path);
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          final px = (await image.toByteData())!;
          image.dispose();
          codec.dispose();
          return px;
        }

        final fg = await rgba('assets/icon/ic_foreground.png');
        for (final (x, y) in [(0, 0), (216, 216), (431, 431)]) {
          expect(fg.getUint8((y * 432 + x) * 4 + 3), 0, reason: 'fg $x,$y');
        }
        final bg = await rgba('assets/icon/ic_background.png');
        int ch(int x, int y, int c) => bg.getUint8((y * 432 + x) * 4 + c);
        // The bird's pink body (left cheek); a blue corner, no fade.
        expect(ch(110, 280, 0), greaterThan(180), reason: 'pink red');
        expect(ch(110, 280, 2), lessThan(170), reason: 'pink blue');
        expect(ch(4, 428, 2), greaterThan(180), reason: 'blue corner');
      },
    );
  });

  group('§2 / §6.1 in the game', () {
    Future<void> settle(FlappySpikesGame g) async {
      for (var i = 0; i < 5; i++) {
        await flushAndMount(g);
      }
    }

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {
          'bestScore': 5,
          'claimedLevels': ['1'],
          'playerLevel': 1,
        },
        services: AnalyticsSpy(),
        versus: FakeVersusService(
          pool: [
            OpponentRun(
              uid: 'rival',
              name: 'Rival',
              score: 100,
              best: 100,
              level: 3,
              timeline: RunTimeline()
                ..addEntry(3, 100)
                ..end(20),
            ),
          ],
        ),
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§4.1 after a versus run the card has only the sharer\'s data; the '
      'best counts the run; share_score analytics; the nickname is made '
      'before drawing',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        await tester.runAsync(() => g.versus.prefetch());
        final run = await startRun(g);
        run.ctx.addScore(21);
        killRunThroughSaves(g);
        await flushAndMount(g);
        expect(g.storage.versusNickname, isNull);
        final shared = <ShareCardData>[];
        g.onShareScore = shared.add;
        g.shareContent = ShareContent(Random(9));
        g.shareScore();
        await settle(g);
        final d = shared.single;
        expect(d.kind, ShareCardKind.spotlight);
        expect(d.score, g.score);
        expect(d.score, isNot(100));
        expect(d.best, g.storage.bestScore);
        expect(d.best, greaterThanOrEqualTo(21));
        // WP-L the stored level (EGG), not the level of the best (21: 0).
        expect(d.level, 1);
        expect(d.level, g.menu.levels.level);
        expect(d.look, g.menu.items.look);
        expect(d.name, isNot('Rival'));
        expect(d.name, isNotEmpty);
        expect(d.name, g.storage.versusNickname, reason: 'nickname created');
        final spy = g.services as AnalyticsSpy;
        final params = spy.events.lastWhere((e) => e.$1 == 'share_score').$2!;
        expect(params, {
          'score': d.score,
          'text_id': d.textId,
          'banner_id': d.bannerId,
          'level': d.level,
        });

        // §2.2 the Invite tile after that run: the same Spotlight card the
        // results page made (same picks with the same seed).
        g.onInvite = shared.add;
        g.shareContent = ShareContent(Random(9));
        g.replay();
        await settle(g);
        stepGame(g, 1);
        g.invite();
        await settle(g);
        final inv = shared.last;
        expect(shared, hasLength(2));
        expect(inv.kind, d.kind);
        expect(inv.score, d.score);
        expect(inv.best, d.best);
        expect(inv.level, d.level);
        expect(inv.look, d.look);
        expect(inv.name, d.name);
        expect(inv.text, d.text);
        expect(inv.banner, d.banner);
        final ip = spy.events.lastWhere((e) => e.$1 == 'invite').$2!;
        expect(ip, {
          'card': 'spotlight',
          'text_id': inv.textId,
          'banner_id': inv.bannerId,
          'level': inv.level,
        });
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: AnalyticsSpy()),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§2.2 a new player (best 0, no name): the nickname is created, a '
      'dodge / flock card with a new-player text',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        final shared = <ShareCardData>[];
        g.onInvite = shared.add;
        g.shareContent = ShareContent(Random(11));
        stepGame(g, 1);
        for (var i = 0; i < 12; i++) {
          g.invite();
          await settle(g);
        }
        expect(shared, hasLength(12));
        expect(shared.map((d) => d.kind).toSet(), {
          ShareCardKind.dodge,
          ShareCardKind.flock,
        });
        final nick = g.storage.versusNickname;
        expect(nick, isNotNull);
        for (final d in shared) {
          expect(d.name, nick);
          expect(Config.inviteTexts, contains(d.text));
          expect(d.level, 0);
        }
        final spy = g.services as AnalyticsSpy;
        final cards = spy.events
            .where((e) => e.$1 == 'invite')
            .map((e) => e.$2!['card'])
            .toSet();
        expect(cards, {'dodge', 'flock'});
      },
    );
  });
}
