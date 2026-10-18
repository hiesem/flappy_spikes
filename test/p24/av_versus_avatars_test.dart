import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../run/shots/versus_shots_test.dart' as shots show rival;
import '../versus/s3_13_service_test.dart' as fixture;

/// Evidence directory (outside git); falls back to build/ when absent.
String get _outDir {
  const brief = '/home/killerhis/Projects/flappyspikes/.worktrees/briefs13';
  return Directory(brief).existsSync()
      ? '$brief/evidence/av'
      : 'build/shots/p24/av';
}

/// The game rendered at [scale] px per point (resized right before the
/// render: the harness reverts earlier resizes).
Future<(ByteData, int)> _render(
  FlappySpikesGame g, {
  double scale = 1,
  String? save,
}) async {
  final w = (320 * scale).round(), h = (g.viewHeight * scale).round();
  g.onGameResize(Vector2(w.toDouble(), h.toDouble()));
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(c);
  final im = await rec.endRecording().toImage(w, h);
  if (save != null) {
    final png = (await im.toByteData(format: ui.ImageByteFormat.png))!;
    File('$_outDir/$save.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
  }
  final data = (await im.toByteData())!;
  im.dispose();
  g.onGameResize(Vector2(320, g.viewHeight));
  return (data, w);
}

/// How many pixels of [r] (points, at 1 px per point) pass [test].
int _count(
  (ByteData, int) px,
  ui.Rect r,
  bool Function(int r, int g, int b) test,
) {
  final (d, w) = px;
  var n = 0;
  for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
    for (var x = r.left.ceil(); x < r.right.floor(); x++) {
      final i = (y * w + x) * 4;
      if (test(d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2))) n++;
    }
  }
  return n;
}

/// The sky bird's blue.
bool _isSky(int r, int g, int b) => b > 200 && b - r > 80;

/// The sticker's white edge.
bool _isWhite(int r, int g, int b) => r > 245 && g > 245 && b > 245;

/// WP-AV (2.4) the sticker avatars in the game: the VS intro plates, the
/// versus HUD bar and the results card show the players' own birds (yours:
/// your look; theirs: the look from their run), rendered once and cached;
/// no photo anywhere; names are the generated ones.
void main() {
  setUpAll(() async {
    final opificio = FontLoader('Opificio Neue')
      ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
    final fredoka = FontLoader('Fredoka')
      ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    final lvdc = FontLoader('LVDC Common2')
      ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
    await Future.wait([opificio.load(), fredoka.load(), lvdc.load()]);
  });

  for (final h in [568.0, 711.0]) {
    final tag = h.round();
    final rival = shots.rival(
      name: 'PondWren042',
      score: 12,
      look: const Look(bird: 'sky', gear: 'shades', hat: 'cap'),
    );
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        prefs: {
          'bestScore': 640,
          'playerLevel': 6,
          'ownedItems': ['bird:owl', 'gear:monocle', 'hat:tophat'],
          'equippedItem.bird': 'owl',
          'equippedItem.gear': 'monocle',
          'equippedItem.hat': 'tophat',
        },
        versus: FakeVersusService(
          pool: [rival],
          profile: const VersusProfile(name: 'SwiftKiwi482'),
        ),
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'WP-AV stickers in the VS intro, the HUD bar and the results card '
      '($tag)',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        g.onScreenTap();
        await flushAndMount(g);
        final intro = g.versusIntro!;
        for (var i = 0; i < 600 && intro.time < intro.lockAt + .8; i++) {
          g.update(1 / 60);
          await Future<void>.value();
        }
        expect(intro.youPlate.name, 'You'); // WP-NAME
        const s = VersusConfig.plateSlot;
        ui.Rect square(PositionComponent p) {
          final tl = p.absoluteTopLeftPosition;
          return ui.Rect.fromLTWH(tl.x + 2, tl.y + 2, s - 4, s - 4);
        }

        var px = (await tester.runAsync(
          () => _render(g, scale: 3, save: 'av_game_intro_$tag'),
        ))!;
        px = (await tester.runAsync(() => _render(g)))!;
        final opp = square(intro.oppPlate), you = square(intro.youPlate);
        final area = opp.width * opp.height;
        expect(
          _count(px, opp, _isSky),
          greaterThan(area * .08),
          reason: 'their sky bird sticker',
        );
        expect(_count(px, opp, _isWhite), greaterThan(area * .03));
        expect(_count(px, you, _isSky), 0, reason: 'your owl, not theirs');
        expect(_count(px, you, _isWhite), greaterThan(area * .03));

        await finishVersusIntro(g);
        for (var i = 0; i < 40; i++) {
          g.update(1 / 60);
        }
        await flushAndMount(g);
        const rowH = HudConfig.rowHeight;
        final themAv = ui.Rect.fromLTWH(
          HudConfig.themLeft + HudConfig.boxWidth - rowH + 2,
          HudConfig.rowTop + 2,
          rowH - 4,
          rowH - 4,
        );
        await tester.runAsync(
          () => _render(g, scale: 3, save: 'av_game_hud_$tag'),
        );
        px = (await tester.runAsync(() => _render(g)))!;
        final a2 = themAv.width * themAv.height;
        expect(_count(px, themAv, _isSky), greaterThan(a2 * .08));

        // Static: frames only blit the cached images.
        final renders = g.avatars.renders;
        for (var i = 0; i < 30; i++) {
          g.update(1 / 60);
          await tester.runAsync(() => _render(g));
        }
        expect(g.avatars.renders, renders, reason: 'rendered once per size');

        g.run!.state.invulnerable = 0;
        killRunThroughSaves(g);
        await flushAndMount(g);
        await declineRevive(g);
        await flushAndMount(g);
        for (var i = 0; i < 120; i++) {
          g.update(1 / 60);
        }
        final page = g.resultsScreen!;
        expect(page.you.look.bird, 'owl');
        expect(page.them!.look, rival.look);
        expect(page.you.name, 'You'); // WP-NAME
        await tester.runAsync(
          () => _render(g, scale: 3, save: 'av_game_results_$tag'),
        );
      },
    );
  }

  group('WP-AV no photos, no platform names', () {
    List<File> dartFiles(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('the app never reads a platform picture or name and never touches '
        'Firebase Storage (grep)', () {
      final banned = <RegExp>[
        RegExp(r'firebase_storage'),
        RegExp(r'FirebaseStorage'),
        RegExp(r'getDownloadURL|putData\('),
        RegExp(r'photoURL|photoUrl'),
        RegExp(r'\.displayName\b'),
        RegExp(r'package:image/'),
        RegExp(r"'avatars/"),
        RegExp(r'avatarUrl|AvatarImages|AvatarSource'),
      ];
      final hits = <String>[];
      for (final f in dartFiles('lib')) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final re in banned) {
            if (re.hasMatch(lines[i])) hits.add('${f.path}:${i + 1} $re');
          }
          // `iconImage` is the platform picture (games_services PlayerData);
          // the no-ads celebration's own asset field has the same name.
          if (lines[i].contains('iconImage') &&
              !f.path.endsWith('noads_celebration.dart')) {
            hits.add('${f.path}:${i + 1} iconImage');
          }
        }
      }
      expect(hits, isEmpty);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('firebase_storage')));
      expect(
        RegExp(r'^\s+image:\s*\^', multiLine: true).hasMatch(pubspec),
        isFalse,
      );
    });

    test('the backend never uses Storage; the rules close it', () {
      for (final f in Directory('functions/src').listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('firebase-admin/storage')), reason: f.path);
        expect(src, isNot(contains('getStorage')), reason: f.path);
      }
      final rules = File('storage.rules').readAsStringSync();
      expect(rules, contains('allow read, write: if false;'));
      expect(rules, isNot(contains('if true')));
      expect(rules, isNot(contains('request.auth')));
    });

    test('a run entry carries the bird / gear / hat ids and no picture; '
        'older entries with a picture URL read without it', () {
      final e = RunEntry.fromSummary(
        fixture.summary(30),
        runId: 'r1',
        name: 'BoldOwl007',
        look: const Look(bird: 'owl', gear: 'monocle', hat: 'tophat'),
        ts: DateTime.utc(2026, 10, 17),
      );
      final m = e.toMap(ts: 0);
      expect(m['avatar'], '');
      expect(m['look'], {
        'bird': 'owl',
        'gear': 'monocle',
        'hat': 'tophat',
        'hoop': 'pink',
        'trail': 'flame',
      });
      expect(m.keys, hasLength(12));
      final legacy = jsonDecode(jsonEncode(m)) as Map<String, Object?>;
      legacy['avatar'] = 'https://storage.example/avatars/u.jpg';
      final pooled = PoolEntry.fromMap({...legacy, 'uid': 'u', 'level': 3})!;
      final o = pooled.toOpponent();
      expect(o.look.bird, 'owl');
      expect(o.look.gear, 'monocle');
      expect(o.look.hat, 'tophat');
      expect(pooled.run.toMap()['avatar'], '');
    });

    test('unknown ids from a newer app fall back per layer', () {
      final o = PoolEntry.fromMap({
        ...RunEntry.fromSummary(
          fixture.summary(30),
          runId: 'r2',
          name: 'BoldOwl007',
          ts: DateTime.utc(2026, 10, 17),
        ).toMap(ts: 0),
        'look': {
          'bird': 'hyperbird',
          'gear': 'monocle',
          'hat': 'warp_hat',
          'hoop': 'pink',
          'trail': 'flame',
        },
        'uid': 'u',
        'level': 3,
      })!.toOpponent();
      expect(o.look.bird, 'classic');
      expect(o.look.gear, 'monocle');
      expect(o.look.hat, 'none');
    });

    test('the own versus name is the generated one, also when signed in to '
        'Play Games / Game Center; uploads carry it', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final identity = fixture.FakeIdentity();
      final backend = fixture.FakeBackend();
      final versus = FirebaseVersusService(
        storageOf: () => storage,
        backend: backend,
        identity: identity,
        random: Random(9),
      );
      await versus.initialize();
      identity.controller.add(const PlatformPlayer(id: 'g7'));
      await Future<void>.delayed(Duration.zero);
      final name = versus.me.name;
      expect(isGeneratedNickname(name), isTrue, reason: name);
      await versus.submitRun(
        fixture.summary(40),
        const Look(bird: 'duck', gear: 'shades', hat: 'sprout'),
      );
      await versus.flush();
      final (q, f) = backend.writes.single;
      expect(q.entry.name, name);
      expect(f.name, name);
      expect(q.entry.look.hat, 'sprout');
      expect(q.entry.toMap()['avatar'], '');
      await identity.controller.close();
    });
  });
}
