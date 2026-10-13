import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'tuning.dart';

/// PRD-2.3 §15.2 the Firebase Remote Config [TuningBackend]. Only
/// `main.dart` creates it, and only when `kTuning` is set, so the
/// production build never reaches it (tree-shaken with the const flag).
class FirebaseTuningBackend implements TuningBackend {
  FirebaseTuningBackend({required this.ensureFirebase});

  /// The shared `Firebase.initializeApp` of `GameServices` (S6-F01).
  final Future<bool> Function() ensureFirebase;

  FirebaseRemoteConfig? _rc;

  @override
  Future<void> setUp() async {
    if (!await ensureFirebase()) throw StateError('Firebase is not up');
    final rc = FirebaseRemoteConfig.instance;
    // §15.2 tester builds: a new value may be fetched every minute.
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 20),
        minimumFetchInterval: const Duration(minutes: 1),
      ),
    );
    _rc = rc;
  }

  @override
  Future<void> activate() async => _rc?.activate();

  @override
  Future<void> fetch() async => _rc?.fetch();

  @override
  Map<String, String> remoteValues() {
    final rc = _rc;
    if (rc == null) return const {};
    return {
      for (final e in rc.getAll().entries)
        if (e.value.source == ValueSource.valueRemote) e.key: e.value.asString(),
    };
  }

  @override
  DateTime? get lastFetchTime {
    final rc = _rc;
    if (rc == null || rc.lastFetchStatus == RemoteConfigFetchStatus.noFetchYet) {
      return null;
    }
    return rc.lastFetchTime;
  }

  @override
  String get lastFetchStatus => switch (_rc?.lastFetchStatus) {
    null || RemoteConfigFetchStatus.noFetchYet => 'never',
    RemoteConfigFetchStatus.success => 'success',
    RemoteConfigFetchStatus.failure => 'failure',
    RemoteConfigFetchStatus.throttle => 'throttled',
  };
}
