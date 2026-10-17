import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../run/config/versus_config.dart';
import '../versus/diagnostics.dart';
import '../versus/run_entry.dart';
import '../versus/upload_queue.dart';
import 'e2e.dart';
import 'identity.dart';
import 'versus_auth.dart';
import 'versus_service.dart';

/// The FlutterFire calls of the versus service (PRD-2 §3.13, ARCH §6):
/// App Check, anonymous Auth + the Play Games link, the `players/{uid}`
/// write (one new run per write, in a transaction), the pool read and the
/// `deleteMyData` callable. Only [FirebaseVersusService] calls it, and only
/// after `Firebase.initializeApp` (done by `GameServices.initialize`).
class FirebaseVersusBackend implements VersusBackend {
  /// [app] null = the default app (the game). The §13.5 seeding test passes
  /// a separate named app so its anonymous test account never replaces the
  /// device owner's sign-in.
  ///
  /// PRD-2.3.1 §2 (tests): [auth] replaces the FlutterFire Auth calls,
  /// [appCheck] the App Check activation and [analytics] the
  /// `versus_link` event sink (default: Firebase Analytics).
  FirebaseVersusBackend({
    this.app,
    VersusAuth? auth,
    Future<void> Function()? appCheck,
    void Function(String name, Map<String, Object> params)? analytics,
  }) : auth = auth ?? FirebaseVersusAuth(app: app),
       _appCheck = appCheck ?? activateAppCheck,
       _analytics = analytics ?? _firebaseAnalytics;

  final FirebaseApp? app;

  /// The Firebase Auth calls (PRD-2.3.1 §2: a port, faked in tests).
  final VersusAuth auth;
  final Future<void> Function() _appCheck;
  final void Function(String, Map<String, Object>) _analytics;

  /// PRD-2.3.1 §2.3 the time box of the start-up liveness check of a
  /// persisted user (offline: the user is kept and the start goes on).
  static const Duration liveCheckTimeout = Duration(seconds: 4);

  static void _firebaseAnalytics(String name, Map<String, Object> params) {
    try {
      unawaited(
        FirebaseAnalytics.instance
            .logEvent(name: name, parameters: params)
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  FirebaseFirestore get _db => app == null
      ? FirebaseFirestore.instance
      : FirebaseFirestore.instanceFor(app: app!);

  /// S6-F01: set only AFTER an activation succeeded; a failure (e.g.
  /// `[core/no-app]` when Firebase is not initialized yet) leaves it false
  /// so the next [activateAppCheck] tries again.
  static bool _appCheckActive = false;

  /// The activation in flight: concurrent callers share one attempt.
  static Future<void>? _appCheckActivation;

  /// Whether App Check was activated successfully in this process.
  static bool get appCheckActive => _appCheckActive;

  /// ARCH §6.5: Play Integrity in release; the debug provider in debug and
  /// `FS_E2E` builds (its debug secret is printed to logcat by the native
  /// SDK — "Enter this debug secret into the allow list …" — for the
  /// orchestrator to register; a `FS_APPCHECK_DEBUG_TOKEN` dart-define
  /// passes a registered one). iOS: App Attest with DeviceCheck fallback.
  /// [debugToken] overrides the dart-define (the P6 live versus e2e prints
  /// and passes its own, WP-6a).
  ///
  /// Once per process after it SUCCEEDED (S6-F01): a failed activation
  /// rethrows and the next call tries again.
  static Future<void> activateAppCheck({String? debugToken}) {
    if (_appCheckActive) return Future.value();
    return _appCheckActivation ??= _activateAppCheck(
      debugToken,
    ).whenComplete(() => _appCheckActivation = null);
  }

  static Future<void> _activateAppCheck(String? debugToken) async {
    final debug = kDebugMode || kE2E;
    await FirebaseAppCheck.instance.activate(
      providerAndroid: debug
          ? AndroidDebugProvider(
              debugToken:
                  debugToken ??
                  (kAppCheckDebugToken.isEmpty ? null : kAppCheckDebugToken),
            )
          : const AndroidPlayIntegrityProvider(),
      providerApple: debug
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _appCheckActive = true;
    debugPrint(
      'versus: App Check activated '
      '(${debug ? 'debug provider' : 'Play Integrity / App Attest'})',
    );
    if (debug) {
      debugPrint(
        'versus: App Check debug provider active — register the debug '
        'secret logged by DebugAppCheckProvider (adb logcat | grep '
        '"debug secret") in Firebase console → App Check → Manage debug '
        'tokens.',
      );
    }
  }

  /// PRD-2.2 §4: start failures carry their reason ([VersusFailure]):
  /// App Check activation → `app_check`; no network → `offline`; any other
  /// sign-in failure → `auth`.
  ///
  /// PRD-2.3.1 §2.3 self-healing: a persisted user that is gone on the
  /// server (its reload fails with a [deadUserCodes] code) is signed out
  /// and replaced by a new anonymous user before any pool read.
  @override
  Future<String> start() async {
    try {
      await _appCheck();
    } catch (e) {
      throw VersusFailure(VersusSoloReason.appCheck, e);
    }
    try {
      if (auth.uid != null && !await _userIsLive()) {
        debugPrint('versus: start dead_user');
        try {
          await auth.signOut();
        } catch (_) {}
      }
      if (auth.uid == null) await auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw VersusFailure(
        e.code == 'network-request-failed'
            ? VersusSoloReason.offline
            : VersusSoloReason.auth,
        e,
      );
    }
    final uid = auth.uid;
    if (uid == null) throw StateError('no Firebase user');
    return uid;
  }

  /// PRD-2.3.1 §2.3 false only when the server says the signed-in user is
  /// gone (or there is none); offline / slow keeps the user.
  Future<bool> _userIsLive({bool refresh = false}) async {
    if (auth.uid == null) return false;
    try {
      await (refresh ? auth.refreshToken() : auth.reload()).timeout(
        liveCheckTimeout,
      );
    } on FirebaseAuthException catch (e) {
      if (deadUserCodes.contains(e.code)) return false;
    } catch (_) {}
    return auth.uid != null;
  }

  /// PRD-2.2 §4 the reason of a refused Firestore call. A permission-denied
  /// with a working App Check token is the rules; without one it is App
  /// Check (enforced App Check refuses sideloaded release builds, which
  /// fail Play Integrity — AGENTS.md).
  ///
  /// PRD-2.3.1 §2.3: a permission-denied while there is no live user
  /// ([liveUser] answers false: signed out, or deleted on the server) is
  /// `auth` — the search re-authenticates once and retries.
  static Future<VersusSoloReason> classify(
    FirebaseException e, {
    Future<bool> Function()? liveUser,
  }) async {
    final text = '${e.code} ${e.message}'.toLowerCase();
    if (text.contains('app check') ||
        text.contains('appcheck') ||
        text.contains('app-check')) {
      return VersusSoloReason.appCheck;
    }
    switch (e.code) {
      case 'unavailable' || 'network-request-failed':
        return VersusSoloReason.offline;
      case 'unauthenticated':
        return VersusSoloReason.auth;
      case 'permission-denied':
        if (liveUser != null && !await _safeBool(liveUser, fallback: true)) {
          return VersusSoloReason.auth;
        }
        return await _appCheckTokenOk()
            ? VersusSoloReason.rules
            : VersusSoloReason.appCheck;
    }
    return VersusSoloReason.error;
  }

  static Future<bool> _safeBool(
    Future<bool> Function() f, {
    required bool fallback,
  }) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }

  static Future<bool> _appCheckTokenOk() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  String? get uid => auth.uid;

  @override
  String get photoUrl {
    final url = auth.photoUrl;
    return url.length > VersusConfig.avatarMax ? '' : url;
  }

  @override
  bool get linkedToPlatform => auth.uid != null && auth.linkedToPlayGames;

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db.collection('pools').doc(id).get();
    } on FirebaseException catch (e) {
      throw VersusFailure(
        await classify(e, liveUser: () => _userIsLive(refresh: true)),
        e,
      );
    }
    final entries = snap.data()?['entries'];
    if (entries is! List) return const [];
    return [
      for (final e in entries)
        if (e is Map) ?PoolEntry.fromMap(plain(e) as Map<Object?, Object?>),
    ];
  }

  @override
  Future<UploadWrite> writeRun(QueuedRun run, PlayerFields f) async {
    final uid = this.uid;
    if (uid == null) return UploadWrite.retry;
    final ref = _db.collection('players').doc(uid);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final doc = nextPlayerDoc(
          old: snap.data(),
          run: run.entry.toMap(ts: Timestamp.fromDate(run.entry.ts)),
          newBest: run.newBest,
          name: f.name,
          avatar: f.avatar,
          platform: f.platform,
          look: f.look,
          uploadsDay: f.uploadsDay,
          uploadsCount: f.uploadsCount,
          level: f.level,
        );
        doc['updatedAt'] = FieldValue.serverTimestamp();
        doc['expireAt'] = Timestamp.fromDate(
          DateTime.now().add(VersusConfig.expireAfter),
        );
        tx.set(ref, doc);
      });
      return UploadWrite.done;
    } on FirebaseException catch (e) {
      // Refused by the rules / malformed: never block the queue with it.
      if (e.code == 'permission-denied' || e.code == 'invalid-argument') {
        debugPrint('versus: run ${run.entry.runId} refused (${e.code})');
        return UploadWrite.drop;
      }
      return UploadWrite.retry;
    }
  }

  /// PRD-2.3.1 §2 the link / account switch:
  /// - not signed in to Firebase: sign in with the Play Games credential;
  /// - a guest: `linkWithCredential` (`linked`);
  /// - `credential-already-in-use` (the Play Games id belongs to an older
  ///   account, ARCH §6.4, which wins): a FRESH server auth code is asked
  ///   for (§2.1, a code works only once and the link used it up). Without
  ///   one nothing is deleted and the guest stays (`switch_failed
  ///   no_fresh_code`; the next launch / resume retries). With one, the
  ///   guest's versus data and Auth user are deleted ([beforeSwitch],
  ///   PRD-2.3 §21.4) and the game signs in with it (`switched`);
  /// - the switch fails: a new anonymous user at once (§2.2,
  ///   `fallback_anon`), so the game never stays on the deleted guest.
  ///
  /// Every outcome logs `versus: link <outcome> <code>` in release builds
  /// and sends `versus_link {outcome, code}` (§2.4; codes only).
  @override
  Future<void> link(
    PlatformIdentity identity, {
    Future<void> Function()? beforeSwitch,
  }) async {
    if (linkedToPlatform) return;
    final cred = await identity.firebaseCredential();
    if (cred == null) return;
    if (auth.uid == null) {
      await _switchTo(cred);
      return;
    }
    var linkCred = cred;
    for (var attempt = 0; ; attempt++) {
      try {
        await auth.linkWithCredential(linkCred);
        _report(LinkOutcome.linked);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') break;
        // This account already has the platform provider (e.g. a stale
        // provider list): it is linked, nothing to do.
        if (e.code == 'provider-already-linked') {
          _report(LinkOutcome.linked);
          return;
        }
        // A retry in the same process may get the code an earlier try
        // used up back from the cache: one more try with a fresh one.
        if (attempt == 0 && e.code == 'invalid-credential') {
          final again = await identity.firebaseCredential(fresh: true);
          if (again != null) {
            linkCred = again;
            continue;
          }
        }
        _report(LinkOutcome.failed, e);
        rethrow;
      }
    }
    // §2.1 never the code the link used up: a new one.
    final fresh = await identity.firebaseCredential(fresh: true);
    if (fresh == null) {
      // §2.2 the clean-up waits for a fresh credential: the guest stays.
      _report(LinkOutcome.switchFailed, 'no_fresh_code');
      return;
    }
    // PRD-2.3 §21.4 the old anonymous uid's versus data goes first, while
    // still signed in as it; a failure never blocks the switch.
    if (beforeSwitch != null && auth.isAnonymous) {
      try {
        await beforeSwitch();
      } catch (err) {
        debugPrint('versus: anonymous clean-up failed: ${err.runtimeType}');
      }
    }
    await _switchTo(fresh);
  }

  /// Signs in with [cred]; on failure §2.2 a new anonymous user at once.
  Future<void> _switchTo(AuthCredential cred) async {
    try {
      await auth.signInWithCredential(cred);
      if (auth.uid == null) throw FirebaseAuthException(code: 'no-user');
      _report(LinkOutcome.switched);
    } catch (e) {
      _report(LinkOutcome.switchFailed, e);
      await _fallbackAnonymous();
    }
  }

  /// PRD-2.3.1 §2.2 never stay on a dead account: sign out of whatever is
  /// left and sign in as a new guest. Offline it ends signed out (the
  /// service then retries its start-up).
  Future<void> _fallbackAnonymous() async {
    try {
      await auth.signOut();
    } catch (_) {}
    try {
      await auth.signInAnonymously();
      _report(LinkOutcome.fallbackAnon);
    } catch (e) {
      _report(LinkOutcome.fallbackAnon, e);
    }
  }

  void _report(LinkOutcome outcome, [Object? error]) {
    final code = linkErrorCode(error);
    // §2.4 release builds too (debugPrint is not stripped); codes only.
    debugPrint('versus: link ${outcome.key} $code');
    try {
      _analytics('versus_link', {'outcome': outcome.key, 'code': code});
    } catch (_) {}
  }

  @override
  Future<bool> deleteMyData() async {
    final ok = await deleteOnline();
    await auth.signOut();
    return ok;
  }

  @override
  Future<bool> deleteOnline() async {
    final result = await FirebaseFunctions.instanceFor(
      app: app,
      region: VersusConfig.functionsRegion,
    ).httpsCallable(VersusConfig.deleteFunction).call<Object?>();
    final data = result.data;
    return data is Map && data['ok'] == true;
  }

  /// PRD-2.3 §21.3 `avatars/{uid}.jpg` in the default Storage bucket.
  @override
  Future<String> uploadAvatar(Uint8List jpeg) async {
    final uid = this.uid;
    if (uid == null) return '';
    final storage = app == null
        ? FirebaseStorage.instance
        : FirebaseStorage.instanceFor(app: app!);
    final ref = storage.ref(VersusConfig.avatarPath(uid));
    await ref.putData(
      jpeg,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=86400',
      ),
    );
    return ref.getDownloadURL();
  }

  @override
  Future<void> resetAnalytics() =>
      FirebaseAnalytics.instance.resetAnalyticsData();

  /// Firestore values → plain Dart ([Timestamp] → UTC [DateTime]).
  static Object? plain(Object? v) {
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is Map) {
      return {for (final e in v.entries) e.key: plain(e.value)};
    }
    if (v is List) return [for (final e in v) plain(e)];
    return v;
  }
}

/// PRD-2.3.1 §2.4 the outcomes of the link / account switch.
enum LinkOutcome {
  linked('linked'),
  switched('switched'),
  switchFailed('switch_failed'),
  fallbackAnon('fallback_anon'),

  /// A link error other than `credential-already-in-use` (the guest stays).
  failed('failed');

  const LinkOutcome(this.key);
  final String key;
}

/// PRD-2.3.1 §2.4 the error code of a link log line: a Firebase error
/// code, `timeout`, a given code string, or `none` — never a message, a
/// token or an auth code (only `[a-z0-9_-]`, ≤ 40 chars).
String linkErrorCode(Object? error) {
  final raw = switch (error) {
    null => 'none',
    String() => error,
    FirebaseException(:final code) => code,
    TimeoutException() => 'timeout',
    _ => 'error',
  };
  final safe = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
  if (safe.isEmpty) return 'error';
  return safe.length > 40 ? safe.substring(0, 40) : safe;
}
