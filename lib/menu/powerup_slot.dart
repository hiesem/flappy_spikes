import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/storage.dart';

/// Home-slot powerups; enum names double as the stored strings.
enum Powerup { none, bigHoops, shield }

/// One home-arrival roll of the BIG HOOPS / SHIELD slot.
class PowerupSlot extends ChangeNotifier {
  PowerupSlot(this._storage, {Random? random}) : _random = random ?? Random() {
    rollForArrival();
  }

  final GameStorage _storage;
  final Random _random;

  Powerup _offered = Powerup.none;

  /// Forces rolls to this powerup (debug panel); still recorded.
  Powerup? debugForce;

  /// The item shown on this arrival; set by the first roll.
  Powerup get offered => _offered;

  Powerup get armed => _parse(_storage.armedPowerup);

  /// Picks 50/50, avoiding a fourth repeat of the last three rolls.
  Powerup rollForArrival() {
    final roll = debugForce ?? _pick();
    final history = [..._storage.slotHistory, roll.name];
    while (history.length > 3) {
      history.removeAt(0);
    }
    _storage.slotHistory = history;
    unawaited(_storage.saveSlotHistory(history));
    _offered = roll;
    notifyListeners();
    return roll;
  }

  /// Arms the offered powerup; overwrites any previously armed one.
  Future<void> armOffered() async {
    await _storage.saveArmedPowerup(_offered.name);
    notifyListeners();
  }

  /// Returns and clears the armed powerup (consumed on START).
  Powerup consume() {
    final current = armed;
    _storage.armedPowerup = 'none';
    unawaited(_storage.saveArmedPowerup('none'));
    notifyListeners();
    return current;
  }

  Powerup _pick() {
    final history = _storage.slotHistory;
    if (history.length == 3 &&
        history[0] == history[1] &&
        history[1] == history[2]) {
      return _parse(history.last) == Powerup.bigHoops
          ? Powerup.shield
          : Powerup.bigHoops;
    }
    return _random.nextBool() ? Powerup.bigHoops : Powerup.shield;
  }

  Powerup _parse(String value) => Powerup.values.firstWhere(
        (powerup) => powerup.name == value,
        orElse: () => Powerup.none,
      );
}
