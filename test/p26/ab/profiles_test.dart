import 'dart:math';

import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/ab_arms.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_types.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _DrawSpy implements Random {
  @override
  bool nextBool() => throw StateError("unexpected bool draw");
  @override
  double nextDouble() => throw StateError("unexpected double draw");
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    expect(max, 1);
    return 0;
  }
}

class _Properties extends GameServices {
  final values = <String, String?>{};
  @override
  void setUserProperty(String name, String? value) => values[name] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalTuning = TuningValues.current;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => TuningValues.current = originalTuning);

  test('2.6 ships one arm with every key at its baked default', () {
    expect(AbArms.profiles.keys, ['0']);
    expect(AbArms.profiles['0'], isEmpty);
    final values = TuningValues.defaults().withArm('0');
    for (final def in kTuningDefaults) {
      expect(values.raw(def.key), def.value, reason: def.key);
    }
    final random = _DrawSpy();
    expect(AbArms.draw(random: random), '0');
    expect(random.calls, 1); // A one-arm release still draws.
  });

  test('every baked profile obeys both independent PRD WP-H key lists', () {
    for (final entry in AbArms.profiles.entries) {
      for (final key in entry.value.keys) {
        expect(
          [
            'curve_',
            'point_',
            'spawn_',
            'squeeze_',
            'ride_',
            'coin_',
            'revive_',
            'hazard_',
            'calm_',
            'level_',
          ].any(key.startsWith),
          isFalse,
          reason: '${entry.key}: $key',
        );
        expect(
          {'gate_saw', 'gate_squeeze', 'rate_min_runs'}.contains(key) ||
              [
                'showcase_',
                'ads_grace_',
                'ads_interstitial_',
                'ui_unlock_',
                'mission_target_',
              ].any(key.startsWith),
          isTrue,
          reason: '${entry.key}: $key',
        );
      }
      expect(() => TuningValues.defaults().withArm(entry.key), returnsNormally);
    }
  });

  test('overlay rejects forbidden, unlisted, unknown and invalid keys', () {
    final values = TuningValues.defaults();
    for (final prefix in AbArms.forbiddenPrefixes) {
      expect(
        () => values.withArmOverrides({'${prefix}test': '1'}),
        throwsArgumentError,
      );
    }
    for (final key in [
      'gate_egg',
      'gate_saw_extra',
      'rate_min_runs_extra',
      'mission_rewards',
      'mission_chest_coins',
      'weekly_rewards',
      'physics_gravity',
      'mission_target_unknown',
    ]) {
      expect(
        () => values.withArmOverrides({key: '1'}),
        throwsArgumentError,
        reason: key,
      );
    }
    expect(
      () => values.withArmOverrides({'gate_saw': 'bad'}),
      throwsArgumentError,
    );
    expect(values.i('gate_saw'), 3);
  });

  test(
    'overlay accepts only lifetime knobs and leaves other values intact',
    () {
      final baseline = TuningValues.resolve(
        {'coin_hoop': '999'},
        defs: const [
          TuningDef('coin_hoop', TuningType.integer, 1),
          TuningDef('mission_target_hoops', TuningType.integer, 20),
          TuningDef('showcase_max_games', TuningType.integer, 6),
          TuningDef('gate_saw', TuningType.integer, 3),
          TuningDef('gate_squeeze', TuningType.integer, 5),
          TuningDef('ads_grace_games', TuningType.integer, 3),
          TuningDef('ads_interstitial_games', TuningType.integer, 4),
          TuningDef('rate_min_runs', TuningType.integer, 5),
          TuningDef('ui_unlock_games', TuningType.integer, 3),
        ],
      );
      final overrides = {
        for (final def in baseline.defs.where((d) => d.key != 'coin_hoop'))
          def.key: '12',
      };
      final overlay = baseline.withArmOverrides(overrides);
      for (final key in overrides.keys) {
        expect(overlay.i(key), 12, reason: key);
      }
      expect(overlay.i('coin_hoop'), 999);
      expect(baseline.i('gate_saw'), 3);
    },
  );

  test(
    'first launch assigns arm 0 and restart keeps the persisted arm',
    () async {
      final first = GameStorage();
      await first.load();
      final prefs = await SharedPreferences.getInstance();
      expect(first.abArmV1, '0');
      expect(prefs.getString(Obf.prefAbArmV1), first.abArmV1);
      final restart = GameStorage();
      await restart.load();
      expect(restart.abArmV1, first.abArmV1);
      // A retired id must survive too: this catches an accidental redraw to 0.
      await restart.saveAbArmV1('retired-arm');
      final downgrade = GameStorage();
      await downgrade.load();
      expect(downgrade.abArmV1, 'retired-arm');
      expect(AbArms.overridesFor(downgrade.abArmV1), isEmpty);
    },
  );

  test('S0 empty placeholder receives the first-launch assignment', () async {
    SharedPreferences.setMockInitialValues({Obf.prefAbArmV1: ''});
    final storage = GameStorage();
    await storage.load();
    expect(storage.abArmV1, '0');
  });

  test(
    'Delete my data keeps arm in memory and across restart (§8.3-12)',
    () async {
      SharedPreferences.setMockInitialValues({Obf.prefAbArmV1: 'retired-arm'});
      final storage = GameStorage();
      await storage.load();
      await storage.resetVersusData();
      expect(storage.abArmV1, 'retired-arm');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Obf.prefAbArmV1), 'retired-arm');
      final restart = GameStorage();
      await restart.load();
      expect(restart.abArmV1, 'retired-arm');
    },
  );

  final properties = _Properties();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      services: properties,
      prefs: {Obf.prefAbArmV1: 'retired-arm'},
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'fs_arm reports the persisted assignment rather than a constant',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      expect(game.storage.abArmV1, 'retired-arm');
      final run = await startRun(game);
      run.endRun();
      expect(properties.values['fs_arm'], game.storage.abArmV1);
      expect(properties.values['fs_arm'], 'retired-arm');
    },
  );
}
