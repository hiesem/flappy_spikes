import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../levels/levels.dart';
import '../run/config/versus_config.dart';
import '../run/run_summary.dart';
import '../skins/look.dart';
import '../versus/diagnostics.dart';
import '../versus/matcher.dart';
import '../versus/nickname.dart';
import '../versus/opponent.dart';
import '../versus/run_entry.dart';
import '../versus/upload_queue.dart';
import 'avatars.dart';
import 'firebase_versus_backend.dart';
import 'identity.dart';

/// The player's own versus identity (§3.13).
class VersusProfile {
  const VersusProfile({
    this.name = '',
    this.avatarUrl = '',
    this.avatarImage = '',
    this.level = 0,
  });

  /// §3.13 the Play Games display name when signed in, else the
  /// generated nickname ('' before either exists).
  final String name;

  /// The avatar URL that is uploaded with a run ('' = default avatar).
  final String avatarUrl;

  /// The [AvatarImages] key of the own avatar on this phone: the Play
  /// Games icon image (`data:` URI) or [avatarUrl] (S6-64); '' = glyph.
  final String avatarImage;
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

  /// PRD-2.2 §3 the opponent search (Home prefetch): every shard of the own
  /// level, then the other levels nearest first, stopping at the first
  /// usable opponent; 6 s limit; cached for the Home visit (a new search
  /// only after [onRunStart]).
  Future<void> prefetch();

  /// PRD-2.2 §3 a run starts (VERSUS or FREE FLY): the next Home prefetch
  /// searches again.
  void onRunStart();

  /// PRD-2.2 §4 the latest search (debug panel).
  VersusSearchInfo get lastSearch;

  /// PRD-2.2 §4 why a VERSUS START without an opponent is solo right now.
  VersusSoloReason get soloReason;

  /// Queue + rules (best always, ≤ 3 a day, score ≥ 3), retried online.
  Future<void> submitRun(RunSummary s, Look look);

  /// Callable + local reset + analytics reset (WP-4c: `false` when the
  /// server could not be reached, so Settings can say so and keep the local
  /// state for a retry).
  Future<bool> deleteMyData();

  VersusProfile get me;

  /// Links the platform identity's credential to the Firebase user.
  Future<void> onPlatformSignIn();

  /// App back in the foreground: recovers a failed start (S6-66) and
  /// retries the upload queue. Never throws.
  Future<void> onResume();
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
  void onRunStart() {}

  @override
  VersusSearchInfo get lastSearch => const VersusSearchInfo();

  /// No backend wired (tests, iOS while paused): never signed in.
  @override
  VersusSoloReason get soloReason => VersusSoloReason.auth;

  @override
  Future<void> submitRun(RunSummary s, Look look) async {}

  @override
  Future<bool> deleteMyData() async => true;

  @override
  VersusProfile get me => const VersusProfile();

  @override
  Future<void> onPlatformSignIn() async {}

  @override
  Future<void> onResume() async {}
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

  /// What [deleteMyData] reports (tests script the failure path).
  bool deleteSucceeds = true;
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

  int runStarts = 0;

  @override
  void onRunStart() => runStarts++;

  /// PRD-2.2 §4 scripted diagnostics (tests).
  VersusSearchInfo searchInfo = const VersusSearchInfo();
  VersusSoloReason reason = VersusSoloReason.noRival;

  @override
  VersusSearchInfo get lastSearch => searchInfo;

  @override
  VersusSoloReason get soloReason => reason;

  @override
  Future<void> submitRun(RunSummary s, Look look) async => submitted.add(s);

  @override
  Future<bool> deleteMyData() async {
    deleteCalls++;
    return deleteSucceeds;
  }

  @override
  VersusProfile get me => profile;

  @override
  Future<void> onPlatformSignIn() async => signInCalls++;

  int resumeCalls = 0;

  @override
  Future<void> onResume() async => resumeCalls++;
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
/// - matching is local: the Home prefetch searches the pools (PRD-2.2 §3:
///   every shard of the own level, then the other levels nearest first,
///   stopping at the first usable opponent, ≤ 44 reads, 6 s limit) once
///   per Home visit; the found shard's other candidates are used first;
///   a held opponent is ready for START; a solo START has a §4 reason
///   ([soloReason], [lastSearch]);
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
    this.searchLimit = VersusConfig.searchLimit,
    this.retryBase,
    this.retryMax = VersusConfig.authRetryMax,
    this.startAfter,
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

  /// PRD-2.2 §3 the search's own time limit (6 s).
  final Duration searchLimit;

  /// S6-66 the first background retry wait after a failed start (doubling
  /// up to [retryMax]); null = no background timer (tests), the on-demand
  /// recoveries still run. `main.dart` passes [VersusConfig.authRetryBase].
  final Duration? retryBase;
  final Duration retryMax;

  /// S6-F01 / S6-F02: what every start attempt waits for first — in the
  /// app `Firebase.initializeApp` (the shared `GameServices.ensureFirebase`
  /// future) and the game's storage load, so neither Home's prefetch nor
  /// an early app resume can start versus before them. A throw counts as a
  /// failed start (retried like one). Null = start at once (tests).
  final Future<void> Function()? startAfter;

  bool _ready = false;
  Future<void>? _start;
  Timer? _retry;
  int _failures = 0;
  Future<int>? _flushing;
  OpponentRun? _held;
  List<PoolEntry> _pool = const [];
  final Set<String> _seen = {};
  bool _loading = false;

  /// PRD-2.2 §3 a search ended since the last run start: the result is
  /// cached for the Home visit (no new search until [onRunStart]).
  bool _searched = false;
  VersusSearchInfo _search = const VersusSearchInfo();

  /// PRD-2.2 §4 why the last start (App Check + auth) failed.
  VersusSoloReason? _startFailure;
  PlatformPlayer? _player;
  StreamSubscription<PlatformPlayer?>? _playerSub;
  UploadQueue? _queue;

  GameStorage get storage => storageOf();
  UploadQueue get queue => _queue ??= UploadQueue(storage, clock: _clock);

  /// The opponent held for the next START (tests).
  OpponentRun? get held => _held;

  /// Run ids met this session (tests).
  Set<String> get seen => _seen;

  /// What the upload queue decided for the last submitted run (tests and
  /// the device e2e: PRD-2.2 §2.2 FREE FLY runs are queued too).
  UploadDecision? lastOffer;

  /// Pool entries loaded this session (tests).
  List<PoolEntry> get pool => _pool;

  Future<T> _call<T>(Future<T> f) => f.timeout(timeout);

  void _log(String what, Object e) {
    if (kDebugMode) debugPrint('versus: $what failed: $e');
  }

  @override
  bool get ready => _ready;

  /// Background auth retries scheduled so far (tests).
  int get failures => _failures;

  @override
  Future<void> initialize() {
    if (_ready) return Future.value();
    // A start in flight: every caller waits for the same attempt.
    return _start ??= _initialize().whenComplete(() => _start = null);
  }

  /// S6-66 a failed (or never finished) start is tried again now: on app
  /// resume, Home prefetch, a run submit and before every flush.
  Future<void> _recover() async {
    if (_ready) return;
    await initialize();
  }

  void _scheduleRetry() {
    final base = retryBase;
    if (base == null || _retry != null) return;
    final ms = min(
      base.inMilliseconds * pow(2, min(_failures, 16)),
      retryMax.inMilliseconds.toDouble(),
    );
    _failures++;
    _retry = Timer(Duration(milliseconds: ms.round()), () {
      _retry = null;
      if (!_ready) unawaited(initialize());
    });
  }

  /// Stops a pending background retry (tests / teardown).
  void dispose() {
    _retry?.cancel();
    _retry = null;
  }

  @override
  Future<void> onResume() async {
    try {
      if (!_ready) {
        await _recover();
      } else {
        await flush();
      }
    } catch (e) {
      _log('resume', e);
    }
  }

  Future<void> _initialize() async {
    try {
      final gate = startAfter;
      if (gate != null) await gate();
      await ensureNickname();
      await _call(backend.start());
      _ready = true;
      _startFailure = null;
      _failures = 0;
      _retry?.cancel();
      _retry = null;
      try {
        _playerSub ??= identity.player.listen(_onPlayer, onError: (_) {});
      } catch (e) {
        _log('player stream', e);
      }
      unawaited(flush());
      await prefetch();
    } catch (e) {
      _log('initialize', e);
      if (!_ready) {
        // §4: a classified failure keeps its reason (offline, app_check,
        // …); anything else means sign-in failed.
        _startFailure = e is VersusFailure ? e.reason : VersusSoloReason.auth;
        _scheduleRetry();
      }
    }
  }

  /// §3.13 the generated nickname, created once per install.
  ///
  /// S6-F02: the saved value on disk wins over the in-memory field, which
  /// is still empty when this runs before the storage finished loading
  /// (an early app resume) — a saved nickname is never overwritten.
  Future<String> ensureNickname() =>
      storage.ensureVersusNickname(() => generateNickname(_random));

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
    final url = _safe(() => backend.photoUrl) ?? '';
    final icon = _player?.iconImage ?? '';
    return VersusProfile(
      name: pgs.trim().isNotEmpty
          ? RunEntry.clampName(pgs)
          : (s.versusNickname ?? ''),
      avatarUrl: url,
      avatarImage: icon.isNotEmpty ? AvatarImages.dataUri(icon) : url,
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
      // The next match from the same shard, held for the next START; a new
      // search only runs on the next Home visit (PRD-2.2 §3).
      _pickFromPool();
    }
    return o;
  }

  @override
  void onRunStart() => _searched = false;

  @override
  VersusSearchInfo get lastSearch => _search;

  @override
  VersusSoloReason get soloReason {
    if (!_ready) return _startFailure ?? VersusSoloReason.auth;
    // START came while the search still ran: it did not finish in time.
    if (_loading) return VersusSoloReason.timeout;
    return _search.reason ?? VersusSoloReason.noRival;
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
    if (!_ready) {
      // S6-66: Home prefetch recovers a failed start (initialize ends
      // with its own prefetch).
      await _recover();
      return;
    }
    if (_held != null) return;
    _pickFromPool();
    if (_held != null || _loading || _searched) return;
    _loading = true;
    final level = levelFor(storage.bestScore);
    _search = VersusSearchInfo(state: VersusSearchState.running, level: level);
    final startedAt = _clock();
    final watch = Stopwatch()..start();
    Duration elapsed() {
      final byClock = _clock().difference(startedAt);
      return byClock > watch.elapsed ? byClock : watch.elapsed;
    }

    var reads = 0;
    try {
      final uid = _safe(() => backend.uid) ?? '';
      final found = await searchPools<PoolCandidate>(
        order: poolSearchOrder(level, _random),
        myUid: uid,
        seen: _seen,
        expired: () => elapsed() >= searchLimit,
        onRead: (n) => reads = n,
        read: (id) async {
          final left = searchLimit - elapsed();
          final entries = await backend
              .readPool(id)
              .timeout(left < timeout ? left : timeout);
          return entries.map(PoolCandidate.new).toList();
        },
      );
      _pool = [for (final c in found.pool) c.entry];
      _pickFromPool();
      final held = _held;
      _search = held != null
          ? VersusSearchInfo(
              state: VersusSearchState.found,
              reads: found.reads,
              level: level,
              opponentUid: held.uid,
            )
          : VersusSearchInfo(
              state: VersusSearchState.solo,
              reason: found.timedOut
                  ? VersusSoloReason.timeout
                  : VersusSoloReason.noRival,
              reads: found.reads,
              level: level,
            );
    } catch (e) {
      _log('prefetch', e);
      _search = VersusSearchInfo(
        state: VersusSearchState.solo,
        reason: soloReasonOf(e),
        reads: reads,
        level: level,
      );
    } finally {
      _loading = false;
      _searched = true;
    }
    if (kDebugMode) {
      debugPrint('versus: search (${_search.debugLine})');
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
      lastOffer = await queue.offer(entry, newBest: s.newBest);
      unawaited(flush());
    } catch (e) {
      _log('submit', e);
    }
  }

  /// Uploads the queue one run per write (retried on the next call). A
  /// flush in flight is shared: every caller waits for the same pass.
  Future<int> flush() async {
    if (!_ready) {
      // S6-66: before a flush, a failed start is retried.
      await _recover();
      if (!_ready) return 0;
    }
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<int> _flush() async {
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
  Future<bool> deleteMyData() async {
    var ok = false;
    try {
      ok = await _call(backend.deleteMyData());
    } catch (e) {
      _log('deleteMyData', e);
    }
    if (!ok) {
      // Offline / refused: nothing online was deleted, so keep the local
      // state (nickname, queue) and the account — the same account is
      // needed for a retry, and a retry must not orphan the online data.
      return false;
    }
    try {
      await _call(backend.resetAnalytics());
    } catch (e) {
      _log('resetAnalytics', e);
    }
    // Local reset (WP-4c storage helper, ARCH §5): the nickname is created
    // again, the queue and the counter are emptied; the session's pool and
    // held opponent go too. Coins, skins and levels stay.
    try {
      await storage.resetVersusData();
    } catch (e) {
      _log('local reset', e);
    }
    _held = null;
    _pool = const [];
    _seen.clear();
    _searched = false;
    _search = const VersusSearchInfo();
    _ready = false;
    // A fresh anonymous account so versus keeps working.
    await initialize();
    return true;
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
