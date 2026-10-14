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

  // PRD-2.3.1 §12.2 the debug origin of the offered / armed / consumed
  // powerup: a "Slot: force …" roll is a debug start (no achievements).
  bool _offeredDebug = false;
  bool _armedDebug = false;
  bool _consumedDebug = false;

  /// Returns and clears whether the last [consume]d powerup was a debug-forced
  /// one (PRD-2.3.1 §12.2; read once by the run setup).
  bool takeConsumedDebug() {
    final d = _consumedDebug;
    _consumedDebug = false;
    return d;
  }

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
    _offeredDebug = debugForce != null;
    notifyListeners();
    return roll;
  }

  /// Arms the offered powerup; overwrites any previously armed one.
  Future<void> armOffered() async {
    _armedDebug = _offeredDebug && _offered != Powerup.none;
    await _storage.saveArmedPowerup(_offered.name);
    notifyListeners();
  }

  /// Returns and clears the armed powerup (consumed on START).
  Powerup consume() {
    final current = armed;
    _consumedDebug = _armedDebug && current != Powerup.none;
    _armedDebug = false;
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
