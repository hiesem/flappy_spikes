import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/diag.dart';
import '../game/storage.dart';
import '../levels/levels.dart';
import '../run/config/versus_config.dart';
import '../run/run_summary.dart';
import '../skins/look.dart';
import '../versus/custom_name.dart';
import '../versus/diagnostics.dart';
import '../versus/matcher.dart';
import '../versus/nickname.dart';
import '../versus/opponent.dart';
import '../versus/run_entry.dart';
import '../versus/upload_queue.dart';
import 'firebase_versus_backend.dart';
import 'identity.dart';
import 'pg_salt.dart';
import 'redact.dart';

/// The player's own versus identity (§3.13).
class VersusProfile {
  const VersusProfile({this.name = '', this.level = 0});

  /// §3.13 the generated nickname ('' before it exists). WP-AV: never the
  /// Play Games / Game Center display name, and no picture (the avatar is
  /// drawn from the look).
  final String name;
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

  /// Sync at START: a prefetched match, or null.
  OpponentRun? takeOpponent();

  /// PRD-2.3 §25.3 an opponent is held for the next START (no wait).
  bool get holdsOpponent;

  /// PRD-2.3 §25.3 whether a VERSUS START without a held opponent still
  /// shows the VS intro as the loading screen ([searchForStart]); false =
  /// the 2.2 behaviour (solo at once, no intro: no backend wired).
  bool get loadingIntro;

  /// PRD-2.3 §25.3 a VERSUS START found nothing held: waits for the running
  /// search, or starts one (a failed start-up is retried first). True when
  /// an opponent is held afterwards ([takeOpponent] hands it out). Completes
  /// at once with false when this Home visit's search already found no
  /// rival. The caller applies its own 3 s limit; a later result stays held
  /// for the next START. Never throws.
  Future<bool> searchForStart();

  /// PRD-2.2 §3 the opponent search (Home prefetch): every shard of the own
  /// level, then the other levels nearest first, stopping at the first
  /// usable opponent; 6 s limit; cached for the Home visit (a new search
  /// only after [onRunStart]).
  Future<void> prefetch();

  /// PRD-2.2 §3 / PRD-2.3 §25.2 a run starts (VERSUS or FREE FLY): the
  /// search for the next opponent starts now (the Home prefetch stays as a
  /// backup when nothing is held).
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

  /// WP-NAME sends the custom versus name ('' clears it) to the server now:
  /// accepted (for a uid), refused (with the reason) or offline (the caller
  /// keeps it on the phone; [FirebaseVersusService] sends it later). Never
  /// throws.
  Future<CustomNameSave> sendCustomName(String name);

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
  bool get holdsOpponent => false;

  @override
  bool get loadingIntro => false;

  @override
  Future<bool> searchForStart() async => false;

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

  /// No backend: the name stays on the phone.
  @override
  Future<CustomNameSave> sendCustomName(String name) async =>
      const CustomNameOffline();

  @override
  Future<void> onPlatformSignIn() async {}

  @override
  Future<void> onResume() async {}
}

/// Tests / `FS_E2E`: a scripted opponent pool; records submissions.
class FakeVersusService implements VersusService {
  FakeVersusService({
    List<OpponentRun>? pool,
    this.profile = const VersusProfile(),
    this.loadingIntro = false,
    this.onSearch,
  }) : pool = pool ?? [];

  /// PRD-2.3 §25.3 opt-in: older tests keep the 2.2 solo START (no intro)
  /// when the pool is empty.
  @override
  final bool loadingIntro;

  /// PRD-2.3 §25.3 the scripted search of [searchForStart] when the pool is
  /// empty (null = no rival at once). It may add to [pool] before it
  /// completes with true.
  Future<bool> Function()? onSearch;
  int searchForStartCalls = 0;

  @override
  Future<bool> searchForStart() async {
    searchForStartCalls++;
    if (pool.isNotEmpty) return true;
    final f = onSearch;
    if (f == null) return false;
    try {
      return await f() && pool.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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
  bool get holdsOpponent => pool.isNotEmpty;

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

  /// WP-NAME names sent ([sendCustomName]) and the scripted answer (null =
  /// accepted for uid 'fake').
  final List<String> sentNames = [];
  CustomNameSave? nameAnswer;

  /// WP-NAME completes the answer later when set (tests of the SAVING state).
  Future<void>? nameDelay;

  @override
  Future<CustomNameSave> sendCustomName(String name) async {
    sentNames.add(name);
    final d = nameDelay;
    if (d != null) await d;
    return nameAnswer ?? const CustomNameAccepted('fake');
  }

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

  /// Whether the Firebase user is already linked to Play Games.
  bool get linkedToPlatform;

  /// The entries of `pools/{id}` (empty when the doc does not exist).
  Future<List<PoolEntry>> readPool(String id);

  /// Writes one new run into `players/{uid}` (ARCH §6.1 write contract).
  Future<UploadWrite> writeRun(QueuedRun run, PlayerFields fields);

  /// Links the platform credential (anonymous user → `linkWithCredential`;
  /// `credential-already-in-use` → sign in with it: the account that
  /// already owns the Play Games id wins, ARCH §6.4).
  ///
  /// PRD-2.3 §21.4: in the `credential-already-in-use` case, while still
  /// signed in as the old **anonymous** uid, [beforeSwitch] runs first (the
  /// service deletes that uid's versus data). It never blocks the switch:
  /// the backend catches whatever it throws.
  ///
  /// QA P2-01 the service runs it in its Auth queue: no other change of
  /// the Firebase user starts until it settled.
  Future<void> link(
    PlatformIdentity identity, {
    Future<void> Function()? beforeSwitch,
  });

  /// The `deleteMyData` callable, then sign out. True when the server
  /// confirmed.
  Future<bool> deleteMyData();

  /// PRD-2.3 §21.4 the `deleteMyData` callable for the signed-in uid
  /// without signing out (the account switch signs in with the Play Games
  /// credential right after). True when the server confirmed.
  Future<bool> deleteOnline();

  /// `FirebaseAnalytics.resetAnalyticsData()`.
  Future<void> resetAnalytics();

  /// WP-NAME the `setVersusName` callable ('' clears). May throw (offline).
  Future<CustomNameSave> setCustomName(String name);

  /// WP-N2 the `getVersusName` callable: the name the server holds for the
  /// signed-in uid ('' = none), null when it did not answer. May throw.
  Future<String?> getCustomName();
}

/// The player-level fields written with every run (ARCH §6.1).
class PlayerFields {
  const PlayerFields({
    required this.name,
    required this.platform,
    required this.look,
    required this.uploadsDay,
    required this.uploadsCount,
    this.level,
  });

  /// WP-L the stored player level for `players/{uid}.level` (null: the
  /// pool level of the best, [levelFor]).
  final int? level;

  final String name;
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
    PgSaltSource? pgSalt,
    this.readTimeout = VersusConfig.readTimeout,
  }) : identity = identity ?? PlayGamesIdentity(),
       backend = backend ?? FirebaseVersusBackend(),
       pgSalt = pgSalt ?? RemoteConfigPgSalt(),
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

  /// PRD-2.3 §21.4 the salt of the hashed Play Games id (`pg`).
  final PgSaltSource pgSalt;

  /// PRD-2.3 §25.2 the time box of one pool read (4 s).
  final Duration readTimeout;

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

  /// The pool entry behind [_held] (S8-03: its uid and `pg` are checked
  /// again whenever my identity changes and at every take).
  PoolEntry? _heldEntry;
  List<PoolEntry> _pool = const [];

  /// PRD-2.3 §25.2 the run ids met (taken at a START), oldest first, at
  /// most [VersusConfig.metCap]: a preference, not a block.
  final List<String> _met = [];
  bool _loading = false;

  /// The search in flight (PRD-2.3 §25.3: a START waits for it).
  Future<void>? _searching;

  /// PRD-2.3 §21.4 my hashed Play Games id ('' = none / not known yet).
  String _pg = '';
  String _pgFor = '';

  /// PRD-2.2 §3 a search ended since the last run start: the result is
  /// cached for the Home visit (no new search until [onRunStart]).
  bool _searched = false;

  /// PRD-2.2 §3 (fix S7-06) bumped by every invalidation of [_searched]
  /// (run start, data reset): a search that started before it must not
  /// mark the new Home visit as searched when it ends late.
  int _searchGen = 0;
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

  /// Run ids met (tests; [met] keeps the order).
  Set<String> get seen => _met.toSet();

  /// PRD-2.3 §25.2 the met list, oldest first (tests).
  List<String> get met => List.unmodifiable(_met);

  /// PRD-2.3 §21.4 my hashed Play Games id now (tests).
  String get pg => _pg;

  /// PRD-2.3 §21.4 settles the pg (tests).
  Future<void> settleIdentity() async {
    await _ensurePg();
  }

  /// What the upload queue decided for the last submitted run (tests and
  /// the device e2e: PRD-2.2 §2.2 FREE FLY runs are queued too).
  UploadDecision? lastOffer;

  /// Pool entries loaded this session (tests).
  List<PoolEntry> get pool => _pool;

  Future<T> _call<T>(Future<T> f) => f.timeout(timeout);

  void _log(String what, Object e) {
    // S7-18: plugin messages can carry OAuth / id tokens (a failed link
    // echoes `?access_token=…`): never print them.
    if (kDebugMode) debugPrint('versus: $what failed: ${redactSecrets(e)}');
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
        if (!_ready) return;
      }
      // PRD-2.3.1 §2.2 a switch that failed (the player is on a fresh
      // guest, or the link was cut off and versus had to start again) is
      // tried again on resume: also the first resume after a recovery
      // (QA P1-01), through the same single-flight link.
      await _retryLink();
      await flush();
    } catch (e) {
      _log('resume', e);
    }
  }

  Future<void> _initialize() async {
    // iOS round 2 §5: the platform player is followed from the start (not
    // only once Firebase / App Check / auth are up, which can take seconds
    // or fail offline), so its `pg` is known early. WP-AV: the profile
    // name stays the nickname. Linking waits for [_ready].
    try {
      _playerSub ??= identity.player.listen(_onPlayer, onError: (_) {});
    } catch (e) {
      _log('player stream', e);
    }
    try {
      final gate = startAfter;
      if (gate != null) await gate();
      await ensureNickname();
      // QA P2-01 Auth changes one at a time (a link still at work first).
      await _authCall(backend.start);
      _ready = true;
      _startFailure = null;
      _failures = 0;
      _retry?.cancel();
      _retry = null;
      _identityChanged(); // PRD-2.3 §21.3 / §21.4
      // QA P1-01 a known platform player whose link was interrupted (the
      // start-up had to begin again) is linked again now.
      unawaited(_retryLink());
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
    diag(
      'FS-GC versus player ${p == null ? 'none' : 'signed in'} '
      '(${identity.platform}) ready=$_ready',
    );
    // Before the start-up finished, [_initialize] refreshes the identity
    // and links (`_retryLink`) once it is ready.
    if (!_ready) return;
    if (p != null && !backend.linkedToPlatform) {
      unawaited(onPlatformSignIn());
    } else {
      _identityChanged();
    }
  }

  /// PRD-2.3 §21.4 the player or the uid changed: the pg hash follows.
  void _identityChanged() {
    // S8-03: a held opponent picked under the old uid / pg may now be me.
    _dropHeldIfMine();
    unawaited(_ensurePg().then((_) => _dropHeldIfMine()));
    // WP-NAME a new uid gets the custom name too.
    if (_ready) unawaited(syncCustomName());
  }

  /// PRD-2.3 §21.4 `pg` = SHA-256(Play Games id + salt), '' without Play
  /// Games or without the salt. Never throws.
  Future<String> _ensurePg() async {
    final id = _player?.id ?? '';
    if (id.isEmpty) {
      _pg = '';
      _pgFor = '';
      return '';
    }
    if (_pgFor == id && _pg.isNotEmpty) return _pg;
    try {
      final salt = await pgSalt.salt().timeout(timeout);
      final pg = hashPlayGamesId(id, salt);
      if ((_player?.id ?? '') == id) {
        _pg = pg;
        _pgFor = pg.isEmpty ? '' : id;
      }
      return pg;
    } catch (e) {
      _log('pg salt', e);
      return '';
    }
  }

  @override
  VersusProfile get me {
    final s = storage;
    return VersusProfile(
      name: s.versusNickname ?? '', // WP-AV the generated name only
      level: s.playerLevel.clamp(0, kMaxLevel), // WP-L the stored level
    );
  }

  @override
  Future<CustomNameSave> sendCustomName(String name) async {
    if (!_ready) {
      // Offline start-up: kept on the phone, sent once versus is up.
      unawaited(_recover());
      return const CustomNameOffline();
    }
    try {
      return await _call(backend.setCustomName(name));
    } catch (e) {
      _log('custom name', e);
      return const CustomNameOffline();
    }
  }

  /// The custom-name sync in flight (one at a time).
  Future<void>? _namesSyncing;

  /// WP-N2 the next sync reads the server's name even when it was read
  /// today (a link to Play Games / Game Center just happened).
  bool _readNameNow = false;

  /// WP-NAME / WP-N2 keeps the custom name in step with the server for the
  /// current uid. Never throws.
  ///
  /// - A local edit the server has not confirmed (typed offline) wins
  ///   until the server answers: it is sent. A refusal puts back the name
  ///   the server holds for this uid (or the last confirmed one) and keeps
  ///   the reason for the Settings card.
  /// - Otherwise the server is the source of truth: its name is read back
  ///   (`getVersusName`) for a new uid at once (reinstall, sign-in, account
  ///   switch), else at most once a UTC day (the activity ping that keeps
  ///   a guest's name). Its answer replaces the local name — '' too (a
  ///   guest name released after 30 days) — except right after a switch
  ///   to an account without a name: the name this phone confirmed for the
  ///   previous uid moves to the account (sent; `taken` → "You").
  Future<void> syncCustomName() => _namesSyncing ??= _syncCustomName()
      .whenComplete(() => _namesSyncing = null);

  Future<void> _syncCustomName() async {
    try {
      if (!_ready) return;
      final uid = _safe(() => backend.uid) ?? '';
      if (uid.isEmpty) return;
      final s = storage;
      final name = s.versusCustomName;
      final confirmed = _confirmedName(s);
      // A local edit not confirmed by any server answer yet.
      if (name != (confirmed?.$2 ?? '')) {
        await _sendCustomName(uid, name, s.versusCustomNameSyncedFor(uid));
        return;
      }
      final today = _utcDay(_clock());
      if (!_readNameNow && s.versusCustomNameRead == '$uid\n$today') return;
      _readNameNow = false;
      final server = await _call(backend.getCustomName());
      if (server == null) return;
      // The player changed it meanwhile, or the user changed: the next
      // pass handles that.
      if (s.versusCustomName != name ||
          (_safe(() => backend.uid) ?? '') != uid) {
        return;
      }
      await s.saveVersusCustomNameRead(uid, today);
      final carried = confirmed != null && confirmed.$1 != uid;
      if (server.isEmpty && name.isNotEmpty && carried) {
        await _sendCustomName(uid, name, '');
        return;
      }
      if (server != name || s.versusCustomNameSyncedFor(uid) != server) {
        await s.saveVersusCustomName(server, syncedUid: uid);
      }
    } catch (e) {
      _log('custom name sync', e);
    }
  }

  /// Sends [name] for [uid]; a refusal falls back to the server's current
  /// name, else [fallback] (the last confirmed one; null = "You").
  Future<void> _sendCustomName(
    String uid,
    String name,
    String? fallback,
  ) async {
    final s = storage;
    final r = await _call(backend.setCustomName(name));
    // The player changed it again meanwhile: the next pass sends that.
    if (s.versusCustomName != name) return;
    switch (r) {
      case CustomNameAccepted(uid: final at):
        await s.saveVersusCustomNameSync(at, name);
        await s.saveVersusCustomNameRead(at, _utcDay(_clock()));
      case CustomNameRefused(:final reason, :final current):
        final back = current ?? fallback ?? '';
        await s.saveVersusCustomName(
          back,
          syncedUid: current != null ? uid : null,
        );
        await s.saveVersusCustomNameError(reason.key);
      case CustomNameOffline():
        break;
    }
  }

  /// The (uid, name) the server last confirmed on this phone, or null.
  (String, String)? _confirmedName(GameStorage s) {
    final v = s.versusCustomNameSync;
    final i = v.indexOf('\n');
    if (i <= 0) return null;
    return (v.substring(0, i), v.substring(i + 1));
  }

  static String _utcDay(DateTime t) {
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }

  T? _safe<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  /// PRD-2.3 §21.4 (S8-03) drops the held opponent when it belongs to my
  /// CURRENT uid or hashed Play Games id (a sign-in or account switch
  /// after it was picked), then holds another match from the loaded pool,
  /// which [pickOpponent] filters with the current identity.
  void _dropHeldIfMine() {
    final e = _heldEntry;
    if (e == null || _held == null) return;
    final uid = _safe(() => backend.uid) ?? '';
    if (isOtherPlayer(PoolCandidate(e), myUid: uid, myPg: _pg)) return;
    _held = null;
    _heldEntry = null;
    _pickFromPool();
  }

  @override
  OpponentRun? takeOpponent() {
    _dropHeldIfMine();
    final o = _held;
    _held = null;
    _heldEntry = null;
    if (o != null) {
      _meet(o.runId);
      // The next unmet match from the same shard, held for the next START;
      // otherwise the run-start search looks further (PRD-2.3 §25.2).
      _pickFromPool(freshOnly: true);
    }
    return o;
  }

  /// PRD-2.3 §25.2 records a met run (most recent last, capped).
  void _meet(String runId) {
    if (runId.isEmpty) return;
    _met
      ..remove(runId)
      ..add(runId);
    while (_met.length > VersusConfig.metCap) {
      _met.removeAt(0);
    }
  }

  @override
  bool get loadingIntro => true;

  @override
  bool get holdsOpponent => _held != null;

  @override
  Future<bool> searchForStart() async {
    try {
      // S8-03: the pg of a just-arrived Play Games identity is known
      // before the held run is trusted.
      if (_held != null) {
        await _ensurePg().timeout(VersusConfig.pgWait, onTimeout: () => _pg);
        _dropHeldIfMine();
      }
      if (_held != null) return true;
      if (!_ready) {
        // A failed start-up is retried (initialize ends with a search).
        await _recover();
        final s = _searching;
        if (s != null) await s;
        return _held != null;
      }
      final running = _searching;
      if (running != null) {
        await running;
        return _held != null;
      }
      // This Home visit already searched and found no rival: known at once.
      if (_searched && _search.reason == VersusSoloReason.noRival) {
        return false;
      }
      _searched = false;
      await prefetch();
      return _held != null;
    } catch (e) {
      _log('search for start', e);
      return false;
    }
  }

  @override
  void onRunStart() {
    _searched = false;
    _searchGen++;
    // PRD-2.3 §25.2 the next opponent is searched during the run.
    unawaited(prefetch());
  }

  @override
  VersusSearchInfo get lastSearch => _search;

  @override
  VersusSoloReason get soloReason {
    if (!_ready) return _startFailure ?? VersusSoloReason.auth;
    // START came while the search still ran: it did not finish in time.
    if (_loading) return VersusSoloReason.timeout;
    return _search.reason ?? VersusSoloReason.noRival;
  }

  /// Holds a random match from the loaded pool (§3.13 matching, PRD-2.3
  /// §25.2 met longest ago when only met runs are left). [freshOnly]: only
  /// a run not met yet (after a START the search looks further first).
  void _pickFromPool({bool freshOnly = false}) {
    if (_held != null || _pool.isEmpty) return;
    final uid = _safe(() => backend.uid) ?? '';
    final best = storage.bestScore;
    final pool = _pool.map(PoolCandidate.new);
    // WP-L matching stays on the pool level of the best ([levelFor]): the
    // server files every run by it, so like meets like.
    if (freshOnly &&
        !hasFreshOpponent(pool, myUid: uid, myPg: _pg, met: _met)) {
      return;
    }
    final c = pickOpponent(
      pool,
      myLevel: levelFor(best),
      myBest: best,
      myUid: uid,
      myPg: _pg,
      met: _met,
      r: _random,
    );
    if (c == null) return;
    _heldEntry = c.entry;
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
    // PRD-2.3 §25.2 the loaded shard only serves a run not met yet; for a
    // rematch the search looks at every pool first.
    _pickFromPool(freshOnly: true);
    if (_held != null || _loading || _searched) return;
    final done = Completer<void>();
    _searching = done.future;
    _loading = true;
    final gen = _searchGen;
    // WP-L the pool level of the best (the server's shards), not the
    // stored player level.
    final level = levelFor(storage.bestScore);
    _search = VersusSearchInfo(state: VersusSearchState.running, level: level);
    var startedAt = _clock();
    final watch = Stopwatch()..start();
    Duration elapsed() {
      final byClock = _clock().difference(startedAt);
      return byClock > watch.elapsed ? byClock : watch.elapsed;
    }

    var reads = 0;
    try {
      // PRD-2.3.1 §2.3 an `auth` failure (no live user) re-authenticates
      // once and searches again (with its own time limit).
      for (var attempt = 0; ; attempt++) {
        try {
          final uid = _safe(() => backend.uid) ?? '';
          // The salt is normally known since start-up; a slow Remote Config
          // never holds the search up for long (the VS intro waits ≤ 3 s).
          final myPg = await _ensurePg().timeout(
            VersusConfig.pgWait,
            onTimeout: () => _pg,
          );
          final found = await searchPools<PoolCandidate>(
            order: poolSearchOrder(level, _random),
            myUid: uid,
            myPg: myPg,
            met: List.of(_met),
            expired: () => elapsed() >= searchLimit,
            // PRD-2.3 §25.2 item 4: every read counts as it happens.
            onRead: (n) {
              reads = n;
              if (gen == _searchGen && _loading) {
                _search = VersusSearchInfo(
                  state: VersusSearchState.running,
                  reads: n,
                  level: level,
                );
              }
            },
            read: (id) async {
              final left = searchLimit - elapsed();
              final box = left < readTimeout ? left : readTimeout;
              final entries = await backend
                  .readPool(id)
                  .timeout(box.isNegative ? Duration.zero : box);
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
          break;
        } catch (e) {
          _log('prefetch', e);
          if (attempt == 0 &&
              soloReasonOf(e) == VersusSoloReason.auth &&
              await _reauthenticate()) {
            startedAt = _clock();
            watch
              ..reset()
              ..start();
            reads = 0;
            continue;
          }
          _search = VersusSearchInfo(
            state: VersusSearchState.solo,
            reason: soloReasonOf(e),
            reads: reads,
            level: level,
          );
          break;
        }
      }
    } finally {
      _loading = false;
      // S7-06: a search overtaken by a run start leaves the next Home free
      // to search again.
      if (gen == _searchGen) _searched = true;
      _searching = null;
      done.complete();
    }
    if (kDebugMode) {
      debugPrint('versus: search (${_search.debugLine})');
    }
  }

  @override
  Future<void> submitRun(RunSummary s, Look look) async {
    try {
      final p = me;
      final pg = await _ensurePg();
      final entry = RunEntry.fromSummary(
        s,
        pg: pg,
        runId: _newRunId(),
        name: p.name.isEmpty ? await ensureNickname() : p.name,
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

  /// PRD-2.3.1 §2.3 a fresh start (the backend replaces a missing or dead
  /// user by a new anonymous one). True when it worked.
  Future<bool> _reauthenticate() async {
    try {
      // QA P2-01 never next to a link still at work.
      await _authCall(backend.start);
      if (kDebugMode) debugPrint('versus: re-authenticated after auth');
      _identityChanged();
      return true;
    } catch (e) {
      _log('re-authenticate', e);
      return false;
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
    unawaited(syncCustomName()); // WP-NAME
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
              platform: identity.platform,
              look: q.entry.look,
              uploadsDay: queue.today,
              uploadsCount: queue.uploadsToday.clamp(0, 1000),
              level: p.level,
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
      // QA P2-01 never next to a link still at work. Versus is off from
      // the moment the user is gone: a link queued behind it skips.
      ok = await _authCall(() async {
        final deleted = await backend.deleteMyData();
        if (deleted) _ready = false;
        return deleted;
      });
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
    // held opponent go too. Coins and skins stay; the stored level is reset
    // by the game (`confirmDeleteMyData`, WP-L).
    try {
      await storage.resetVersusData();
    } catch (e) {
      _log('local reset', e);
    }
    _held = null;
    _heldEntry = null;
    _pool = const [];
    _met.clear();
    _searched = false;
    _searchGen++;
    _search = const VersusSearchInfo();
    _ready = false;
    // A fresh anonymous account so versus keeps working.
    await initialize();
    return true;
  }

  /// The link in flight (PRD-2.3.1: one at a time — a resume and the
  /// player stream may ask together). It stays set until the link's auth
  /// work settles, also after a caller stopped waiting (QA P1-02).
  Future<void>? _linking;

  /// QA P2-01 the end of the Auth queue (null = idle). Every change of the
  /// Firebase user (start / re-authentication, link / switch, data reset)
  /// runs in it, one at a time; the next one starts only when the previous
  /// one SETTLED. A plugin call cannot be cancelled, so a time-boxed caller
  /// that stops waiting never lets another change start next to it.
  Future<void>? _authTail;

  /// Runs [op] after every earlier Auth change settled (never time-boxed:
  /// a stuck plugin call keeps the queue, and versus, waiting). An idle
  /// queue runs [op] at once (no future is kept across idle periods).
  Future<T> _serialized<T>(Future<T> Function() op) {
    final before = _authTail;
    final run = before == null ? Future.sync(op) : before.then((_) => op());
    late final Future<void> tail;
    tail = run.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_authTail, tail)) _authTail = null;
    });
    _authTail = tail;
    return run;
  }

  /// [op] through the Auth queue, for a caller that waits at most 3 ×
  /// [timeout] for its turn and [timeout] for the call itself. When the
  /// wait for the turn runs out, [op] is dropped (it never runs late).
  Future<T> _authCall<T>(Future<T> Function() op) async {
    var gaveUp = false;
    final turn = Completer<void>();
    final run = _serialized<T>(() {
      if (gaveUp) throw TimeoutException('auth: the caller stopped waiting');
      turn.complete();
      return op();
    });
    try {
      await turn.future.timeout(timeout * 3);
    } on TimeoutException {
      gaveUp = true;
      rethrow;
    }
    return run.timeout(timeout);
  }

  @override
  Future<void> onPlatformSignIn() {
    if (!_ready) return Future.value();
    final link = _linking ??= _serialized(
      _link,
    ).whenComplete(() => _linking = null);
    // PRD-2.3.1 §2: two auth codes, the clean-up and the switch: more
    // than one plugin call's time box. The caller stops waiting then; the
    // link itself keeps its place in the Auth queue until it settles.
    return link.timeout(
      timeout * 3,
      onTimeout: () => _log('link', TimeoutException('link', timeout * 3)),
    );
  }

  /// PRD-2.3.1 §2.2 links the known platform player when the Firebase
  /// user is not linked to it yet (single flight via [onPlatformSignIn]).
  Future<void> _retryLink() async {
    if (_player == null || !_ready) return;
    if (_safe(() => backend.linkedToPlatform) ?? true) return;
    await onPlatformSignIn();
  }

  /// Runs in the Auth queue (QA P2-01): no other change of the Firebase
  /// user happens while it works.
  Future<void> _link() async {
    // A data reset ran first: the next start-up links again.
    if (!_ready) return;
    try {
      await backend.link(identity, beforeSwitch: _cleanUpAnonymousAccount);
    } catch (e) {
      _log('link', e);
    }
    // WP-N2 linked (same uid) or switched (the account's uid): the server's
    // name is read back now, not tomorrow.
    _readNameNow = true;
    final uid = _safe(() => backend.uid) ?? '';
    // PRD-2.3.1 §2.2 the link ended without a live user (the fallback
    // guest could not sign in, e.g. offline): versus starts again.
    if (uid.isEmpty) {
      _ready = false;
      _startFailure = VersusSoloReason.auth;
      _scheduleRetry();
    }
    _identityChanged();
  }

  /// PRD-2.3 §21.4 the link met `credential-already-in-use`: before the
  /// switch to the uid that owns the Play Games id, the old anonymous
  /// uid's versus data (runs, pool entries) is deleted while still
  /// signed in as it. Never throws and never blocks the switch.
  Future<void> _cleanUpAnonymousAccount() async {
    try {
      final ok = await _call(backend.deleteOnline());
      if (kDebugMode) debugPrint('versus: old anonymous account deleted: $ok');
    } catch (e) {
      _log('anonymous clean-up', e);
    }
  }
}
// endregion WP-5b
