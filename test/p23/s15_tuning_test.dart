import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_codegen.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_types.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A fake Remote Config plugin: [fetched] becomes active on [activate].
class FakeTuningBackend implements TuningBackend {
  FakeTuningBackend(this.fetched);

  /// What the last fetch stored (the next activate applies it).
  Map<String, String> fetched;
  Map<String, String> active = {};
  final List<String> calls = [];

  /// The next fetch stores this (null = keep [fetched]).
  Map<String, String>? nextFetch;

  @override
  Future<void> setUp() async => calls.add('setUp');

  @override
  Future<void> activate() async {
    calls.add('activate');
    active = {...fetched};
  }

  @override
  Future<void> fetch() async {
    calls.add('fetch');
    if (nextFetch != null) fetched = nextFetch!;
  }

  @override
  Map<String, String> remoteValues() {
    calls.add('values');
    return active;
  }

  @override
  DateTime? lastFetchTime = DateTime(2026, 10, 13, 9, 30);

  @override
  String lastFetchStatus = 'success';
}

/// A plugin that throws everywhere (the service must survive it).
class ThrowingBackend implements TuningBackend {
  int calls = 0;
  @override
  Future<void> setUp() async => throw StateError('no firebase ${calls++}');
  @override
  Future<void> activate() async => throw StateError('activate ${calls++}');
  @override
  Future<void> fetch() async => throw StateError('fetch ${calls++}');
  @override
  Map<String, String> remoteValues() => throw StateError('values ${calls++}');
  @override
  DateTime? get lastFetchTime => throw StateError('time');
  @override
  String get lastFetchStatus => throw StateError('status');
}

/// PRD-2.3 §15.6 remote tuning.
void main() {
  tearDown(() {
    Tuning.instance = Tuning();
    TuningValues.current = TuningValues.defaults();
  });

  group('§15.6 flag off', () {
    test('kTuning is off in tests; the no-op service never touches a '
        'plugin and every getter returns its default', () async {
      expect(kTuning, isFalse);
      final t = Tuning();
      expect(t.backend, isNull);
      await t.initialize();
      expect(t.initialized, isFalse);
      expect(t.lastFetchStatus, 'off');
      t.beginRun();
      for (final d in kTuningDefaults) {
        expect(TuningValues.current.raw(d.key), d.value, reason: d.key);
        expect(TuningValues.current.sourceOf(d.key), TuningSource.defaultValue);
      }
    });

    // PRD-2.3.1 §0: the section 14 values, updated to the live RC v21 set
    // (except coin_bullseye 3 and shop_ad_coins 75).
    test('tuning_defaults.dart equals the section 14 values', () {
      final t = TuningValues.defaults();
      // §14.2 coins
      expect(t.i('coin_hoop'), 1);
      expect(t.i('coin_perfect'), 2);
      expect(t.i('coin_piggy_per'), 3);
      expect(t.i('coin_jar'), 5);
      expect(t.ints('coin_spin_slices'), [1, 2, 3, 1, 2, 1]);
      expect(t.i('coin_star_trail'), 2);
      expect(t.i('coin_bullseye'), 3); // PRD-2.3.1 §6 (was 2)
      expect(t.i('coin_train'), 1);
      expect(t.i('coin_switch'), 0);
      expect(t.i('coin_pair_gift'), 3);
      expect(t.i('coin_frenzy_ring'), 1);
      expect(t.i('coin_versus_win'), 10);
      expect(t.i('coin_versus_draw'), 5);
      expect(t.ints('bonus_prizes'), [25, 25, 25, 40, 40, 40, 50, 50, 100]);
      expect(t.d('bonus_feather_chance'), .6);
      expect(t.range('bonus_feather_gaps'), (5, 30));
      expect(t.d('puzzle_chance'), .6);
      expect(t.range('puzzle_gaps'), (5, 30));
      expect(t.ints('puzzle_reward'), [40, 100, 5]);
      expect(t.ints('revive_ladder'), [250, 500, 1000, 2000, 4000, 8000]);
      expect(t.i('revive_min_hoops'), 6);
      expect(
        t.ints('level_rewards'),
        [50, 100, 150, 250, 400, 600, 800, 1000, 2000, 5000],
      );
      expect(t.i('shop_ad_coins'), 75); // PRD-2.3.1 §5 (was 40)
      expect(t.i('shop_ad_per_day'), 5);
      expect(t.i('shop_ad_cooldown_s'), 300);
      // §14.3 points
      expect(t.i('point_pass'), 1);
      expect(t.i('point_perfect_min'), 2);
      expect(t.i('point_chick'), 1);
      expect(t.i('point_fever_streak'), 5);
      // §14.4 difficulty
      expect(t.raw('curve_speed'), [
        [0, 150],
        [50, 172.5],
        [150, 187.5],
      ]);
      expect(t.raw('curve_opening'), [
        [1, 118],
        [2, 118],
        [6, 114],
        [10, 110.5],
        [16, 105.5],
        [20, 102],
        [25, 98],
        [30, 94.5],
        [35, 90.5],
        [40, 87.5],
        [50, 81],
        [60, 76.5],
        [75, 72],
        [100, 66],
      ]);
      expect(t.raw('curve_moving'), [
        [19, 0],
        [20, 0.15],
        [35, 0.40],
        [60, 0.60],
        [80, 0.75],
      ]);
      expect(t.range('squeeze_first'), (25, 40));
      expect(t.range('squeeze_hold'), (5, 10));
      expect(t.range('squeeze_gap'), (25, 45));
      // §14.5 rides
      expect(t.d('ride_comet_chance'), .04);
      expect(t.i('ride_comet_from'), 8);
      expect(t.i('ride_comet_spacing'), 18);
      expect(t.range('ride_portal_first'), (12, 25));
      expect(t.range('ride_portal_then'), (80, 90));
      expect(t.d('ride_comet_hoop_gap'), 560);
      expect(t.d('ride_comet_tail'), 100); // PRD-2.3.1 §16
      expect(t.d('ride_comet_after_gap'), 310); // PRD-2.3.1 §16
      expect(t.i('ride_portal_max'), 2); // PRD-2.3.1 §17
      // §14.6 gates
      expect({
        for (final k in [
          'heart', 'star_trail', 'bullseye', 'switch', 'train', 'comet', //
          'portal', 'capsule', 'shield', 'spring', 'pair', 'egg', //
          'feather', 'puzzle', 'piggy', 'jar', 'fever', 'lucky_spin', 'saw',
        ])
          k: t.i('gate_$k'),
      }, {
        'heart': 0, 'star_trail': 0, 'bullseye': 0, //
        'switch': 0, 'train': 0, //
        'comet': 2, 'portal': 2, 'capsule': 2, 'shield': 2, //
        'spring': 4, 'pair': 4, 'egg': 4, //
        'feather': 6, 'puzzle': 6, 'piggy': 6, 'jar': 6, //
        'fever': 8, 'lucky_spin': 8, //
        'saw': 12,
      });
    });

    test('§15.3 every key is <group>_<name> snake_case in a known group, '
        'unique, and its default is valid for its type', () {
      final keys = <String>{};
      for (final d in kTuningDefaults) {
        expect(RegExp(r'^[a-z]+(_[a-z0-9]+)+$').hasMatch(d.key), isTrue,
            reason: d.key);
        expect(kTuningGroups, contains(d.group), reason: d.key);
        expect(keys.add(d.key), isTrue, reason: 'duplicate ${d.key}');
        expect(d.type.validate(d.value, d.value), isNotNull, reason: d.key);
        expect(d.section, isNotEmpty);
        // The default survives its own console string.
        expect(
          renderValue(d.type, d.type.parse(d.type.encode(d.value), d.value)!),
          renderValue(d.type, d.value),
          reason: d.key,
        );
      }
      // §0 item 5: the ads_, rate_, noads_ and ui_ groups are supported.
      expect(kTuningGroups, containsAll(['ads', 'rate', 'noads', 'ui']));
    });
  });

  group('§15.6 flag on (fake plugin)', () {
    test('remote int, double, list and keyframe table override their '
        'defaults; startup activates then fetches in the background',
        () async {
      final b = FakeTuningBackend({
        'coin_jar': '12',
        'ride_comet_chance': '0.05',
        'bonus_prizes': '[10,20,30]',
        'curve_opening': '[[1,100],[50,80]]',
      });
      final t = Tuning(backend: b);
      await t.initialize();
      await t.pendingFetch;
      expect(b.calls, ['setUp', 'activate', 'values', 'fetch']);
      final v = t.active;
      expect(v.i('coin_jar'), 12);
      expect(v.d('ride_comet_chance'), .05);
      expect(v.ints('bonus_prizes'), [10, 20, 30]);
      expect(v.curve('curve_opening').at(25.5), closeTo(90, 1e-9));
      for (final k in [
        'coin_jar',
        'ride_comet_chance',
        'bonus_prizes',
        'curve_opening',
      ]) {
        expect(v.sourceOf(k), TuningSource.remote, reason: k);
      }
      expect(v.sourceOf('coin_hoop'), TuningSource.defaultValue);
      // The game reads the active set (startup, and every run start).
      expect(TuningValues.current.i('coin_jar'), 12);
      expect(RunConfig.openingFor(1), 100);
      expect(RunConfig.openingFor(0), 118, reason: 'hoop 0 stays 118');
    });

    test('a wrong type and broken JSON fall back to the default, marked '
        'default*', () async {
      final b = FakeTuningBackend({
        'coin_jar': 'eight',
        'coin_hoop': '1.5',
        'bonus_prizes': '[25, 25,',
        'curve_speed': '[[50,1],[10,2]]', // hoops must ascend
        'spawn_saw': '{"from": 20}', // keys missing
        'revive_ladder': '{"a": 1}',
        'bonus_feather_chance': 'true',
      });
      final t = Tuning(backend: b);
      await t.initialize();
      final v = t.active;
      for (final k in b.fetched.keys) {
        expect(v.sourceOf(k), TuningSource.rejected, reason: k);
        expect(v.sourceOf(k).label, 'default*');
        final d = kTuningDefaults.firstWhere((d) => d.key == k);
        expect(v.raw(k), d.value, reason: k);
      }
    });

    test('values activated at startup do not change when a fetch completes '
        'mid-session (they apply at the next start)', () async {
      final b = FakeTuningBackend({'coin_jar': '12'})
        ..nextFetch = {'coin_jar': '30'};
      final t = Tuning(backend: b);
      await t.initialize();
      await t.pendingFetch;
      expect(b.fetched, {'coin_jar': '30'});
      t.beginRun();
      expect(TuningValues.current.i('coin_jar'), 12);
      expect(t.active.i('coin_jar'), 12);
      // The next start activates what was fetched.
      final next = Tuning(backend: b);
      await next.initialize();
      expect(next.active.i('coin_jar'), 30);
    });

    test('a plugin that throws everywhere never takes the game down', () async {
      final t = Tuning(backend: ThrowingBackend());
      await t.initialize();
      await t.pendingFetch;
      expect(t.active.i('coin_jar'), 5); // the default (live RC v21)
      expect(t.lastFetchTime, isNull);
      expect(t.lastFetchStatus, 'unknown');
    });
  });

  group('§15.3 / §15.6 keyframe tables', () {
    final k = Keyframes([
      [10, 100],
      [20, 50],
      [30, 50],
      [31, 0],
    ]);
    test('linear between keys, flat before the first and after the last',
        () {
      expect(k.at(0), 100);
      expect(k.at(10), 100);
      expect(k.at(15), 75);
      expect(k.at(17.5), 62.5);
      expect(k.at(31), 0);
      expect(k.at(500), 0);
    });
    test('a plateau (two keys with the same value) and a step (two keys '
        'one hoop apart)', () {
      expect(k.at(25), 50);
      expect(k.at(30), 50);
      expect(k.at(31), 0);
      final step = Keyframes([
        [19, 0],
        [20, .15],
      ]);
      expect(step.at(19), 0);
      expect(step.at(20), .15);
      expect(step.at(0), 0);
      expect(step.at(99), .15);
    });
    test('the §14.4 curves', () {
      final v = TuningValues.defaults();
      final opening = v.curve('curve_opening');
      expect(opening.at(1), 118);
      expect(opening.at(50), closeTo(81, .2));
      expect(opening.at(100), 66);
      expect(opening.at(250), 66);
      final speed = v.curve('curve_speed');
      expect(speed.at(0), 150);
      expect(speed.at(50), 172.5);
      expect(speed.at(150), 187.5);
      expect(speed.at(300), 187.5);
    });
  });

  group('§15.5 export / import', () {
    test('an export → import round trip gives an identical '
        'tuning_defaults.dart', () {
      final file = File('lib/run/config/tuning_defaults.dart')
          .readAsStringSync();
      expect(renderDefaultsFile(kTuningDefaults), file,
          reason: 'run `dart run tool/tuning_sync.dart format`');
      final template =
          jsonDecode(exportTemplateJson(kTuningDefaults)) as Map<String, dynamic>;
      final values = templateValues(template);
      expect(values.length, kTuningDefaults.length);
      final r = importDefs(kTuningDefaults, values);
      expect(r.changed, isEmpty);
      expect(r.rejected, isEmpty);
      expect(r.unknown, isEmpty);
      expect(renderDefaultsFile(r.defs), file);
    });

    test('the committed template is the export of the defaults', () {
      expect(
        File('docs/p23/remote_config_template.json').readAsStringSync(),
        exportTemplateJson(kTuningDefaults),
        reason: 'run `dart run tool/tuning_sync.dart export`',
      );
      // Every key is in TUNING.md's generated table.
      final doc = File('docs/p23/TUNING.md').readAsStringSync();
      expect(doc, contains(renderKeyTable(kTuningDefaults)));
    });

    test('import takes the console values, keeps the order, rejects what '
        'does not parse and ignores unknown keys', () {
      final template = {
        'parameters': {
          'coin_jar': {
            'defaultValue': {'value': '9'},
          },
          'nope_key': {
            'defaultValue': {'value': '1'},
          },
        },
        'parameterGroups': {
          'curve': {
            'parameters': {
              'curve_opening': {
                'defaultValue': {'value': '[[1,92],[100,70]]'},
              },
              'curve_speed': {
                'defaultValue': {'value': 'oops'},
              },
              'curve_moving': {
                'defaultValue': {'useInAppDefault': true},
              },
            },
          },
        },
      };
      final r = importDefs(kTuningDefaults, templateValues(template));
      expect(r.changed, ['coin_jar', 'curve_opening']);
      expect(r.rejected, ['curve_speed']);
      expect(r.unknown, ['nope_key']);
      expect([for (final d in r.defs) d.key], [
        for (final d in kTuningDefaults) d.key,
      ]);
      final out = renderDefaultsFile(r.defs);
      expect(
        out,
        contains("TuningDef('coin_jar', TuningType.integer, 9, '14.2',"),
      );
      expect(out, contains('[[1, 92], [100, 70]]'));
    });
  });

  group('§15.4 the TUNING page', () {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711),
      gameSize: Vector2(Config.worldWidth, 711),
    );
    tester.testGameWidget(
      'lists every key with its active value and source, and the last fetch',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, widgetTester) async {
        final b = FakeTuningBackend({'coin_jar': '12', 'coin_hoop': 'x'});
        Tuning.instance = Tuning(backend: b);
        await Tuning.instance.initialize();
        expect(FlappySpikesGame.debugAvailable, isTrue);
        game.openDebugPanel();
        await flushAndMount(game);
        final p = game.world.children.query<DebugPanel>().single;
        final open = p.actions.indexWhere((a) => a.label() == 'TUNING >');
        expect(open, greaterThanOrEqualTo(0));
        await p.press(open);
        await flushAndMount(game);
        expect(p.actions.first.label(), 'Fetch: success · 2026-10-13 09:30');
        final labels = <String>{};
        for (var page = 0; page < 40; page++) {
          labels.addAll(p.actions.map((a) => a.label()));
          if (page == 0) {
            await widgetTester.runAsync(() => _capture(game, 'tuning_page'));
          }
          await p.press(
            p.actions.indexWhere((a) => a.label().startsWith('Page ')),
          );
          await flushAndMount(game);
          if (p.actions.first.label().startsWith('Fetch:')) break;
        }
        for (final d in kTuningDefaults) {
          expect(
            labels.any((l) => l.startsWith('${d.key} = ')),
            isTrue,
            reason: d.key,
          );
        }
        expect(labels, contains('coin_jar = 12 [remote]'));
        expect(labels, contains('coin_hoop = 1 [default*]'));
        expect(labels, contains('coin_perfect = 2 [default]'));
        // Read-only: a key row changes nothing.
        final row = p.actions.indexWhere((a) => a.label().startsWith('coin_'));
        if (row >= 0) await p.press(row);
        expect(Tuning.instance.active.i('coin_jar'), 12);
        await p.press(p.actions.indexWhere((a) => a.label() == '< Back'));
        expect(p.actions.any((a) => a.label() == 'TUNING >'), isTrue);
      },
    );
  });
}

/// The screenshot-test pattern (`captureShot`, test/menu_screenshot_test.dart),
/// written to build/shots/p23/.
Future<void> _capture(FlappySpikesGame game, String name) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  await lvdc.load();
  const scale = 1.5;
  final size = Vector2(320 * scale, (game.viewHeight * scale).roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  image.dispose();
  final file = File('build/shots/p23/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
}
