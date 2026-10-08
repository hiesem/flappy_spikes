import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../run/config/versus_config.dart';
import '../versus/run_entry.dart';
import '../versus/upload_queue.dart';
import 'e2e.dart';
import 'identity.dart';
import 'versus_service.dart';

/// The FlutterFire calls of the versus service (PRD-2 §3.13, ARCH §6):
/// App Check, anonymous Auth + the Play Games link, the `players/{uid}`
/// write (one new run per write, in a transaction), the pool read and the
/// `deleteMyData` callable. Only [FirebaseVersusService] calls it, and only
/// after `Firebase.initializeApp` (done by `GameServices.initialize`).
class FirebaseVersusBackend implements VersusBackend {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static bool _appCheck = false;

  /// ARCH §6.5: Play Integrity in release; the debug provider in debug and
  /// `FS_E2E` builds (its debug secret is printed to logcat by the native
  /// SDK — "Enter this debug secret into the allow list …" — for the
  /// orchestrator to register; a `FS_APPCHECK_DEBUG_TOKEN` dart-define
  /// passes a registered one). iOS: App Attest with DeviceCheck fallback.
  /// [debugToken] overrides the dart-define (the P6 live versus e2e prints
  /// and passes its own, WP-6a).
  static Future<void> activateAppCheck({String? debugToken}) async {
    if (_appCheck) return;
    _appCheck = true;
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
    if (debug) {
      debugPrint(
        'versus: App Check debug provider active — register the debug '
        'secret logged by DebugAppCheckProvider (adb logcat | grep '
        '"debug secret") in Firebase console → App Check → Manage debug '
        'tokens.',
      );
    }
  }

  @override
  Future<String> start() async {
    await activateAppCheck();
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    final uid = user?.uid;
    if (uid == null) throw StateError('no Firebase user');
    return uid;
  }

  @override
  String? get uid => _auth.currentUser?.uid;

  @override
  String get photoUrl {
    final url = _auth.currentUser?.photoURL ?? '';
    return url.length > VersusConfig.avatarMax ? '' : url;
  }

  @override
  bool get linkedToPlatform =>
      _auth.currentUser?.providerData.any(
        (p) => p.providerId == PlayGamesAuthProvider.PROVIDER_ID,
      ) ??
      false;

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    final snap = await _db.collection('pools').doc(id).get();
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

  @override
  Future<void> link(PlatformIdentity identity) async {
    final cred = await identity.firebaseCredential();
    if (cred == null) return;
    final user = _auth.currentUser;
    if (user == null) {
      await _auth.signInWithCredential(cred);
      return;
    }
    if (linkedToPlatform) return;
    try {
      await user.linkWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'credential-already-in-use') rethrow;
      // The account that already owns the Play Games id wins (ARCH §6.4).
      // A server auth code is single-use: ask for a fresh one.
      final again = e.credential ?? await identity.firebaseCredential();
      if (again != null) await _auth.signInWithCredential(again);
    }
  }

  @override
  Future<bool> deleteMyData() async {
    final result = await FirebaseFunctions.instanceFor(
      region: VersusConfig.functionsRegion,
    ).httpsCallable(VersusConfig.deleteFunction).call<Object?>();
    final data = result.data;
    await _auth.signOut();
    return data is Map && data['ok'] == true;
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
