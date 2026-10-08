import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../levels/levels.dart';
import '../run/config/versus_config.dart';
import '../run/run_summary.dart';
import '../skins/look.dart';
import '../versus/matcher.dart';
import '../versus/nickname.dart';
import '../versus/opponent.dart';
import '../versus/run_entry.dart';
import '../versus/upload_queue.dart';
import 'firebase_versus_backend.dart';
import 'identity.dart';

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

// region WP-5b — the Firebase implementation (PRD-2 §3.13, ARCH §6.3–§6.5)

/// The plugin calls [FirebaseVersusService] needs, behind an interface so
/// the matching / queue / profile logic is unit-tested with a fake
/// (`test/versus/`) and the plugins are only touched in
/// [FirebaseVersusBackend]. Implementations may throw; the service
/// try/catches and time-boxes every call.
abstract class VersusBackend {
  /// App Check (once) + anonymous Firebase Auth when signed out. Returns
  /// the uid.
  Future<String> start();

  /// The signed-in Firebase uid, or null.
  String? get uid;

  /// The Firebase user's photo URL (Play Games link), or ''.
  String get photoUrl;

  /// Whether the Firebase user is already linked to Play Games.
  bool get linkedToPlatform;

  /// The entries of `pools/{id}` (empty when the doc does not exist).
  Future<List<PoolEntry>> readPool(String id);

  /// Writes one new run into `players/{uid}` (ARCH §6.1 write contract).
  Future<UploadWrite> writeRun(QueuedRun run, PlayerFields fields);

  /// Links the platform credential (anonymous user → `linkWithCredential`;
  /// `credential-already-in-use` → sign in with it: the account that
  /// already owns the Play Games id wins, ARCH §6.4).
  Future<void> link(PlatformIdentity identity);

  /// The `deleteMyData` callable, then sign out. True when the server
  /// confirmed.
  Future<bool> deleteMyData();

  /// `FirebaseAnalytics.resetAnalyticsData()`.
  Future<void> resetAnalytics();
}

/// The player-level fields written with every run (ARCH §6.1).
class PlayerFields {
  const PlayerFields({
    required this.name,
    required this.avatar,
    required this.platform,
    required this.look,
    required this.uploadsDay,
    required this.uploadsCount,
  });

  final String name;
  final String avatar;
  final String platform;
  final Look look;
  final String uploadsDay;
  final int uploadsCount;
}

/// The real versus service (PRD-2 §3.13), wired by `main.dart` on Android
/// only (like `GameServices`); tests keep [NoopVersusService] /
/// [FakeVersusService]. Every call is try/caught and time-boxed: a failure
/// means a solo run, never a crash or a blocked START.
///
/// - [initialize]: App Check + anonymous auth, the nickname (once per
///   install), the Play Games link when a player is signed in, the queue
///   flush and the first [prefetch];
/// - matching is local from one pool document per read (own level, random
///   shard, else a random other level), re-read when the session's
///   candidates run out; an opponent is always held ready for START;
/// - [submitRun]: the §3.13 upload rules through the persisted
///   [UploadQueue] (3 a day per UTC day, best always, score ≥ 3), flushed
///   one run per write and retried on the next flush.
class FirebaseVersusService implements VersusService {
  FirebaseVersusService({
    required this.storageOf,
    PlatformIdentity? identity,
    VersusBackend? backend,
    Random? random,
    DateTime Function()? clock,
    this.timeout = VersusConfig.callTimeout,
  }) : identity = identity ?? PlayGamesIdentity(),
       backend = backend ?? FirebaseVersusBackend(),
       _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  /// The game's storage (read lazily: `main.dart` builds the service
  /// before the game).
  final GameStorage Function() storageOf;
  final PlatformIdentity identity;
  final VersusBackend backend;
  final Random _random;
  final DateTime Function() _clock;
  final Duration timeout;

  bool _ready = false;
  bool _starting = false;
  OpponentRun? _held;
  List<PoolEntry> _pool = const [];
  final Set<String> _seen = {};
  bool _loading = false;
  DateTime? _emptyReadAt;
  PlatformPlayer? _player;
  StreamSubscription<PlatformPlayer?>? _playerSub;
  UploadQueue? _queue;

  GameStorage get storage => storageOf();
  UploadQueue get queue => _queue ??= UploadQueue(storage, clock: _clock);

  /// The opponent held for the next START (tests).
  OpponentRun? get held => _held;

  /// Run ids met this session (tests).
  Set<String> get seen => _seen;

  /// Pool entries loaded this session (tests).
  List<PoolEntry> get pool => _pool;

  Future<T> _call<T>(Future<T> f) => f.timeout(timeout);

  void _log(String what, Object e) {
    if (kDebugMode) debugPrint('versus: $what failed: $e');
  }

  @override
  bool get ready => _ready;

  @override
  Future<void> initialize() async {
    if (_ready || _starting) return;
    _starting = true;
    try {
      await ensureNickname();
      await _call(backend.start());
      _ready = true;
      try {
        _playerSub ??= identity.player.listen(_onPlayer, onError: (_) {});
      } catch (e) {
        _log('player stream', e);
      }
      unawaited(flush());
      await prefetch();
    } catch (e) {
      _log('initialize', e);
      _ready = false;
    } finally {
      _starting = false;
    }
  }

  /// §3.13 the generated nickname, created once per install.
  Future<String> ensureNickname() async {
    final s = storage;
    final have = s.versusNickname;
    if (have != null && have.isNotEmpty) return have;
    final name = generateNickname(_random);
    await s.saveVersusNickname(name);
    return name;
  }

  void _onPlayer(PlatformPlayer? p) {
    _player = p;
    if (p != null && _ready && !backend.linkedToPlatform) {
      unawaited(onPlatformSignIn());
    }
  }

  @override
  VersusProfile get me {
    final s = storage;
    final pgs = _player?.displayName ?? '';
    return VersusProfile(
      name: pgs.trim().isNotEmpty
          ? RunEntry.clampName(pgs)
          : (s.versusNickname ?? ''),
      avatarUrl: _safe(() => backend.photoUrl) ?? '',
      level: levelFor(s.bestScore),
    );
  }

  T? _safe<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  @override
  OpponentRun? takeOpponent() {
    final o = _held;
    _held = null;
    if (o != null) {
      _seen.add(o.runId);
      _pickFromPool();
      if (_held == null) unawaited(prefetch());
    }
    return o;
  }

  /// Holds a random match from the loaded pool (§3.13 matching).
  void _pickFromPool() {
    if (_held != null || _pool.isEmpty) return;
    final uid = _safe(() => backend.uid) ?? '';
    final best = storage.bestScore;
    final c = pickOpponent(
      _pool.map(PoolCandidate.new),
      myLevel: levelFor(best),
      myBest: best,
      myUid: uid,
      seen: _seen,
      r: _random,
    );
    if (c == null) return;
    _seen.add(c.runId);
    _held = c.entry.toOpponent();
  }

  @override
  Future<void> prefetch() async {
    if (!_ready || _held != null) return;
    _pickFromPool();
    if (_held != null || _loading) return;
    final empty = _emptyReadAt;
    if (empty != null &&
        _clock().difference(empty) < VersusConfig.poolRetry) {
      return;
    }
    _loading = true;
    try {
      final plan = poolReadPlan(levelFor(storage.bestScore), _random);
      var entries = await _call(backend.readPool(plan.first));
      final uid = backend.uid ?? '';
      bool usable(List<PoolEntry> l) =>
          l.any((e) => e.uid != uid && !_seen.contains(e.runId));
      if (!usable(entries)) {
        entries = await _call(backend.readPool(plan.fallback));
      }
      _pool = entries;
      _pickFromPool();
      _emptyReadAt = _held == null ? _clock() : null;
    } catch (e) {
      _log('prefetch', e);
      _emptyReadAt = _clock();
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> submitRun(RunSummary s, Look look) async {
    try {
      final p = me;
      final entry = RunEntry.fromSummary(
        s,
        runId: _newRunId(),
        name: p.name.isEmpty ? await ensureNickname() : p.name,
        avatar: p.avatarUrl,
        look: look,
        platform: identity.platform,
        ts: _clock().toUtc(),
      );
      await queue.offer(entry, newBest: s.newBest);
      unawaited(flush());
    } catch (e) {
      _log('submit', e);
    }
  }

  /// Uploads the queue one run per write (retried on the next call).
  Future<int> flush() async {
    if (!_ready) return 0;
    try {
      return await queue.flush((q) async {
        final p = me;
        return _call(
          backend.writeRun(
            q,
            PlayerFields(
              name: p.name.isEmpty ? q.entry.name : p.name,
              avatar: p.avatarUrl,
              platform: identity.platform,
              look: q.entry.look,
              uploadsDay: queue.today,
              uploadsCount: queue.uploadsToday.clamp(0, 1000),
            ),
          ),
        );
      });
    } catch (e) {
      _log('flush', e);
      return 0;
    }
  }

  String _newRunId() {
    final t = _clock().millisecondsSinceEpoch.toRadixString(36);
    final r = List.generate(
      12,
      (_) => _random.nextInt(36).toRadixString(36),
    ).join();
    return '$t-$r';
  }

  @override
  Future<void> deleteMyData() async {
    try {
      await _call(backend.deleteMyData());
    } catch (e) {
      _log('deleteMyData', e);
    }
    try {
      await _call(backend.resetAnalytics());
    } catch (e) {
      _log('resetAnalytics', e);
    }
    // Local reset (ARCH §5): new nickname, empty queue and counter; the
    // session's pool and held opponent go too. Coins, skins and levels stay.
    try {
      await queue.clear();
      await storage.saveVersusNickname(generateNickname(_random));
    } catch (e) {
      _log('local reset', e);
    }
    _held = null;
    _pool = const [];
    _seen.clear();
    _emptyReadAt = null;
    _ready = false;
    // A fresh anonymous account so versus keeps working.
    await initialize();
  }

  @override
  Future<void> onPlatformSignIn() async {
    if (!_ready) return;
    try {
      await _call(backend.link(identity));
    } catch (e) {
      _log('link', e);
    }
  }
}
// endregion WP-5b
