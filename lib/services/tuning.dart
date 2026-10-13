import 'dart:async';

import 'package:flutter/foundation.dart';

import '../run/config/tuning_values.dart';

export '../run/config/tuning_values.dart' show TuningSource, TuningValues;

/// PRD-2.3 §15.1 remote tuning is compiled in only with
/// `--dart-define=FS_TUNING=true` (debug and tester builds). The production
/// build has no flag: it never touches Remote Config and uses the in-app
/// defaults only.
const bool kTuning = bool.fromEnvironment('FS_TUNING');

/// PRD-2.3 §15.2 the Remote Config plugin behind a small interface (the
/// Firebase implementation is `FirebaseTuningBackend`; tests use a fake).
abstract class TuningBackend {
  /// Plugin setup (Firebase up, settings: minimum fetch interval 1 min).
  Future<void> setUp();

  /// Applies the values fetched last time.
  Future<void> activate();

  /// Fetches new values for the NEXT start (never activates them).
  Future<void> fetch();

  /// The active values that came from the console (key → raw string).
  Map<String, String> remoteValues();

  /// The last fetch (null = never) and whether it succeeded.
  DateTime? get lastFetchTime;
  String get lastFetchStatus;
}

/// PRD-2.3 §15.2 the tuning service (the `GameServices` pattern): the
/// default [instance] is a no-op that returns the in-app defaults and never
/// touches a plugin; every plugin call is individually try/caught.
///
/// At startup (`main.dart`, `FS_TUNING` builds only) [initialize]
/// activates the values fetched last time, makes them the active set, then
/// starts a background fetch for the next start. A fetch that completes
/// mid-session never changes the active set. [beginRun] hands the active
/// set to the run (`TuningValues.current`), so a value never changes during
/// a run.
class Tuning {
  /// [active] is the set a run hands to `TuningValues.current` when there is
  /// no backend (tests give a fixed set; the default is the in-app defaults).
  Tuning({this.backend, TuningValues? active})
    : _active = active ?? TuningValues.defaults();

  /// The app-wide service (no-op until `main.dart` replaces it).
  static Tuning instance = Tuning();

  /// Null = the no-op (flag off, tests).
  final TuningBackend? backend;

  /// The values activated at startup (defaults until then / without a
  /// backend).
  TuningValues get active => _active;
  TuningValues _active;

  /// Whether [initialize] has run (TUNING page).
  bool get initialized => _initialized;
  bool _initialized = false;

  /// The background fetch of this start (tests await it).
  Future<void>? get pendingFetch => _fetch;
  Future<void>? _fetch;

  /// The last fetch (TUNING page).
  DateTime? get lastFetchTime {
    try {
      return backend?.lastFetchTime;
    } catch (_) {
      return null;
    }
  }

  /// "success" / "failure" / "throttled" / "never" (TUNING page).
  String get lastFetchStatus {
    if (backend == null) return 'off';
    try {
      return backend!.lastFetchStatus;
    } catch (_) {
      return 'unknown';
    }
  }

  /// §15.2 activate, then a background fetch. Never throws.
  Future<void> initialize() async {
    final b = backend;
    if (b == null) return;
    try {
      await b.setUp();
    } catch (e) {
      debugPrint('Tuning: setUp failed: $e');
    }
    try {
      await b.activate();
    } catch (e) {
      debugPrint('Tuning: activate failed: $e');
    }
    var remote = const <String, String>{};
    try {
      remote = b.remoteValues();
    } catch (e) {
      debugPrint('Tuning: reading values failed: $e');
    }
    _active = TuningValues.resolve(
      remote,
      onReject: (key, raw) => debugPrint(
        'Tuning: $key = "$raw" rejected (wrong type / broken JSON): default',
      ),
    );
    TuningValues.current = _active;
    _initialized = true;
    _fetch = () async {
      try {
        await b.fetch();
      } catch (e) {
        debugPrint('Tuning: fetch failed: $e');
      }
    }();
  }

  /// §15.2 values are read once per run, at run start.
  void beginRun() => TuningValues.current = _active;
}
