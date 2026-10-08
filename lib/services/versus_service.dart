import '../run/run_summary.dart';
import '../skins/look.dart';
import '../versus/opponent.dart';

/// The player's own versus identity (§3.13).
class VersusProfile {
  const VersusProfile({this.name = '', this.avatarUrl = '', this.level = 0});
  final String name;
  final String avatarUrl;
  final int level;
}

/// Versus backend (PRD-2 §3.13, ARCH §6.4). Same wrapper pattern as
/// `GameServices`: the default is the no-op [NoopVersusService]; the
/// Firebase implementation (WP-5b) is created only from `main.dart`.
/// Implementations never throw — a failure means a solo run.
abstract class VersusService {
  /// Anonymous auth, App Check, profile, first prefetch; never throws.
  Future<void> initialize();

  bool get ready;

  /// Sync at START: a prefetched match, or null (→ solo, no intro).
  OpponentRun? takeOpponent();

  /// Own level + random shard, else a random other level.
  Future<void> prefetch();

  /// Queue + rules (best always, ≤ 3 a day, score ≥ 3), retried online.
  Future<void> submitRun(RunSummary s, Look look);

  /// Callable + local reset + analytics reset.
  Future<void> deleteMyData();

  VersusProfile get me;

  /// Links the platform identity's credential to the Firebase user.
  Future<void> onPlatformSignIn();
}

/// Default: no backend, always solo.
class NoopVersusService implements VersusService {
  @override
  Future<void> initialize() async {}

  @override
  bool get ready => false;

  @override
  OpponentRun? takeOpponent() => null;

  @override
  Future<void> prefetch() async {}

  @override
  Future<void> submitRun(RunSummary s, Look look) async {}

  @override
  Future<void> deleteMyData() async {}

  @override
  VersusProfile get me => const VersusProfile();

  @override
  Future<void> onPlatformSignIn() async {}
}

/// Tests / `FS_E2E`: a scripted opponent pool; records submissions.
class FakeVersusService implements VersusService {
  FakeVersusService({List<OpponentRun>? pool, this.profile = const VersusProfile()})
    : pool = pool ?? [];

  /// Opponents handed out in order by [takeOpponent] (null when empty).
  final List<OpponentRun> pool;
  final VersusProfile profile;

  final List<RunSummary> submitted = [];
  int deleteCalls = 0;
  int prefetchCalls = 0;
  int signInCalls = 0;
  bool _ready = false;

  @override
  Future<void> initialize() async => _ready = true;

  @override
  bool get ready => _ready;

  @override
  OpponentRun? takeOpponent() => pool.isEmpty ? null : pool.removeAt(0);

  @override
  Future<void> prefetch() async => prefetchCalls++;

  @override
  Future<void> submitRun(RunSummary s, Look look) async => submitted.add(s);

  @override
  Future<void> deleteMyData() async => deleteCalls++;

  @override
  VersusProfile get me => profile;

  @override
  Future<void> onPlatformSignIn() async => signInCalls++;
}
