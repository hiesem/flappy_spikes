import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Random source that always picks the same bool, for deterministic rolls.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final bool value;

  @override
  bool nextBool() => value;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameStorage> loadedStorage([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    final storage = GameStorage();
    await storage.load();
    return storage;
  }

  group('PowerupSlot', () {
    test('first arrival rolls one powerup and records it', () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: Random(1));

      expect(slot.offered, anyOf(Powerup.bigHoops, Powerup.shield));
      expect(storage.slotHistory, [slot.offered.name]);
      expect(slot.armed, Powerup.none);
    });

    test('history is capped to the last 3 rolls', () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: Random(7));
      for (var i = 0; i < 10; i++) {
        slot.rollForArrival();
      }
      expect(storage.slotHistory.length, 3);
      expect(slot.offered.name, storage.slotHistory.last);
    });

    test('never rolls the same powerup more than 3 times in a row', () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: Random(42));
      final results = <Powerup>[slot.offered];
      for (var i = 0; i < 999; i++) {
        results.add(slot.rollForArrival());
      }

      expect(results.every((p) => p != Powerup.none), true);
      var run = 1;
      var maxRun = 1;
      for (var i = 1; i < results.length; i++) {
        run = results[i] == results[i - 1] ? run + 1 : 1;
        if (run > maxRun) maxRun = run;
      }
      expect(maxRun, lessThanOrEqualTo(3));
      expect(maxRun, 3);
    });

    test('repeat cap forces the other item after three identical rolls',
        () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: _FixedRandom(false));

      // Constant random would roll shield forever; the cap flips roll 4.
      expect(slot.offered, Powerup.shield);
      expect(slot.rollForArrival(), Powerup.shield);
      expect(slot.rollForArrival(), Powerup.shield);
      expect(slot.rollForArrival(), Powerup.bigHoops);
      expect(storage.slotHistory, ['shield', 'shield', 'bigHoops']);
    });

    test('debugForce overrides the roll but is still recorded', () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: _FixedRandom(false));
      slot.debugForce = Powerup.bigHoops;

      for (var i = 0; i < 4; i++) {
        expect(slot.rollForArrival(), Powerup.bigHoops);
      }
      expect(storage.slotHistory, ['bigHoops', 'bigHoops', 'bigHoops']);
      expect(slot.offered, Powerup.bigHoops);
    });

    test('arm, overwrite without stacking, and consume', () async {
      final storage = await loadedStorage();
      final slot = PowerupSlot(storage, random: _FixedRandom(false));
      expect(slot.offered, Powerup.shield);

      await slot.armOffered();
      expect(slot.armed, Powerup.shield);
      expect(storage.armedPowerup, 'shield');

      slot.debugForce = Powerup.bigHoops;
      slot.rollForArrival();
      await slot.armOffered();
      expect(slot.armed, Powerup.bigHoops);

      expect(slot.consume(), Powerup.bigHoops);
      expect(slot.armed, Powerup.none);
      expect(storage.armedPowerup, 'none');
      expect(slot.consume(), Powerup.none);
    });

    test('armed state round-trips through storage', () async {
      final storage = await loadedStorage({'armedPowerup': 'shield'});
      final slot = PowerupSlot(storage, random: Random(3));
      expect(slot.armed, Powerup.shield);

      await slot.armOffered();
      final reader = GameStorage();
      await reader.load();
      expect(reader.armedPowerup, slot.offered.name);
    });
  });
}
