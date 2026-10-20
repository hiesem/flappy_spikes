import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../run/config/versus_config.dart';
import 'firebase_versus_backend.dart';
import 'iap_service.dart';
import 'integrity_guard.dart';
import 'tester.dart';
import 'obf_strings.g.dart';

/// PRD-2.5 §3.8 WP-IAP: the server's answer for one purchase.
enum PurchaseVerdict { valid, revoked, invalid, unknown }

/// One server check: `{platform, productId, token}` → the verdict. Throws
/// when the server could not be asked (offline, App Check, timeout); a
/// [PurchaseVerifyRefused] when it refused the request itself.
typedef PurchaseVerifyCall =
    Future<PurchaseVerdict> Function(
      String platform,
      String productId,
      String token,
    );

/// The server refused the request as malformed (`invalid-argument`): it
/// can never succeed, so the item is dropped (never treated as fake).
class PurchaseVerifyRefused implements Exception {
  const PurchaseVerifyRefused();
}

/// The callable's name (masked: PRD-2.5 §3.5 WP-STRINGS).
final String kVerifyPurchaseFunction = Obf.fnVerifyPurchase;

// New shared_preferences keys (PRD-2.5 §3.8; no existing key is renamed).
/// Purchases waiting for their server check (JSON list, survives restarts).
final String kIapVerifyQueueKey = Obf.prefIapVerifyQueue;

/// Refunded purchase ids, in the `IapEvent.transactionIds` form
/// (`token:<Play token>` / `id:<StoreKit transaction id>`).
final String kRevokedPurchasesKey = Obf.prefRevokedPurchases;

/// Verified No-Ads purchases, re-checked every [PurchaseVerifier.noAdsRecheck]
/// so a later refund is seen (JSON list).
final String kIapNoAdsTokensKey = Obf.prefIapNoAdsTokens;

/// Sticky: the server called one of this install's purchases fake. WP-GUARD
/// reads it at start as the untrusted reason `iap_fake`.
final String kIapFakeKey = Obf.prefIapFake;

/// The WP-GUARD reason for a fake purchase.
const String kIapFakeReason = 'iap_fake';

/// Release builds only: FS_TESTER / debug / profile builds (other package
/// signing, test noise) never call the server; their queue just waits.
const bool kPurchaseVerifyCallsAllowed = kReleaseMode && !kTester;

/// Server purchase verification, client side (PRD-2.5 §3.8).
///
/// Purchases are granted at once exactly as before; afterwards
/// `Purchases` [enqueue]s the store identity. [drain] (launch, every
/// resume, right after an enqueue) asks `verifyPurchase` in the background
/// — never awaited by gameplay or the buy flow, every failure swallowed:
/// - `valid` → done (a No-Ads token is kept and re-checked every 7 days);
/// - `unknown` / not reachable → stays queued with a backoff (at most about
///   one call per item per day once the server answered `unknown`);
/// - `revoked` → the id is remembered ([isRevoked]: a later re-delivery is
///   not granted again) and a refunded No Ads turns No Ads off, unless
///   another No-Ads purchase that is not revoked is known. Coins are never
///   taken back;
/// - `invalid` → nothing is taken back; the sticky [kIapFakeKey] is set and
///   the [IntegrityGuard] marks the install untrusted (`iap_fake`).
///
/// The default [instance] is a no-op ([PurchaseVerifier.noop]): tests,
/// Linux, FS_E2E and soak builds never touch Firebase. `main.dart` installs
/// [PurchaseVerifier.firebase] on the mobile products.
class PurchaseVerifier {
  PurchaseVerifier({
    required PurchaseVerifyCall call,
    required this.platform,
    DateTime Function()? clock,
    void Function(String reason)? markUntrusted,
    this.callsAllowed = true,
  }) : _send = call,
       _clock = clock ?? DateTime.now,
       _markUntrusted = markUntrusted ?? IntegrityGuard.instance.markUntrusted,
       enabled = true;

  /// Does nothing: no queue, nothing revoked, no calls.
  PurchaseVerifier.noop()
    : _send = null,
      platform = 'android',
      _clock = DateTime.now,
      _markUntrusted = _ignore,
      callsAllowed = false,
      enabled = false;

  /// The production verifier (`verifyPurchase` in europe-west1, App Check).
  factory PurchaseVerifier.firebase({
    required Future<bool> Function() ensureFirebase,
  }) => PurchaseVerifier(
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    callsAllowed: kPurchaseVerifyCallsAllowed,
    call: (platform, productId, token) =>
        _firebaseCall(ensureFirebase, platform, productId, token),
  );

  static void _ignore(String _) {}

  /// The app's verifier (no-op until `main.dart` installs the real one).
  static PurchaseVerifier instance = PurchaseVerifier.noop();

  /// Queue cap (oldest dropped first).
  static const int maxQueue = 50;

  /// Remembered refunded ids cap.
  static const int maxRevoked = 100;

  /// A verified No Ads is asked again after this long (refunds).
  static const Duration noAdsRecheck = Duration(days: 7);

  /// After the server answered `unknown`.
  static const Duration unknownBackoff = Duration(days: 1);

  /// First retry after the server could not be reached (doubles, capped
  /// at [unknownBackoff]).
  static const Duration offlineBackoff = Duration(minutes: 15);

  /// Items still undecided after this long are dropped (nothing changes).
  static const Duration maxAge = Duration(days: 60);

  /// Upper bound for one server call.
  static const Duration callTimeout = Duration(seconds: 20);

  final PurchaseVerifyCall? _send;
  final DateTime Function() _clock;
  final void Function(String reason) _markUntrusted;

  /// `android` / `ios`: which store the tokens belong to.
  final String platform;

  /// False = [drain] never calls the server (non-release builds).
  final bool callsAllowed;

  /// False for [PurchaseVerifier.noop].
  final bool enabled;

  /// Turns No Ads off after a refund (set by `Purchases.start`).
  Future<void> Function()? onNoAdsRevoked;

  SharedPreferences? _prefs;
  List<_QueueItem> _queue = [];
  List<_NoAdsToken> _noAds = [];
  List<String> _revoked = [];
  Future<void>? _loading;
  Future<void>? _draining;

  /// Whether the persisted state is in memory (always for the no-op).
  bool get loaded => !enabled || _prefs != null;

  /// Reads the persisted state once. Never throws.
  Future<void> load() {
    if (loaded) return Future<void>.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _queue = _decodeList(
        prefs.getString(kIapVerifyQueueKey),
      ).map(_QueueItem.fromJson).whereType<_QueueItem>().toList();
      _noAds = _decodeList(
        prefs.getString(kIapNoAdsTokensKey),
      ).map(_NoAdsToken.fromJson).whereType<_NoAdsToken>().toList();
      _revoked = List.of(prefs.getStringList(kRevokedPurchasesKey) ?? []);
      _prefs = prefs;
    } catch (e) {
      _log('load failed: ${e.runtimeType}');
    }
  }

  static List<Object?> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        kIapVerifyQueueKey,
        jsonEncode([for (final i in _queue) i.toJson()]),
      );
      await prefs.setString(
        kIapNoAdsTokensKey,
        jsonEncode([for (final t in _noAds) t.toJson()]),
      );
      await prefs.setStringList(kRevokedPurchasesKey, _revoked);
    } catch (e) {
      _log('save failed: ${e.runtimeType}');
    }
  }

  /// The id form of [token] (as in `IapEvent.transactionIds`).
  String _idOf(String token) =>
      platform == 'ios' ? 'id:$token' : 'token:$token';

  /// The token the server checks: the Play purchase token on Android, the
  /// StoreKit transaction id on iOS (from `transactionIdsOf`).
  String? tokenOf(List<String> transactionIds) {
    final prefix = platform == 'ios' ? 'id:' : 'token:';
    for (final id in transactionIds) {
      if (id.startsWith(prefix) && id.length > prefix.length) {
        return id.substring(prefix.length);
      }
    }
    return null;
  }

  /// Whether any of [transactionIds] was refunded. [load] first (false
  /// until loaded).
  bool isRevoked(List<String> transactionIds) =>
      enabled && transactionIds.any(_revoked.contains);

  /// Whether the server called a purchase of this install fake.
  bool get fakeSeen => _prefs?.getBool(kIapFakeKey) ?? false;

  /// The purchases waiting for their check (tests / diagnostics).
  List<({String productId, String token})> get pending => [
    for (final i in _queue) (productId: i.productId, token: i.token),
  ];

  /// The verified No-Ads tokens (tests / diagnostics).
  List<String> get noAdsTokens => [for (final t in _noAds) t.token];

  /// Queues [product]'s store identity for a server check (dedup; cap
  /// [maxQueue]) and starts a [drain]. Call after the grant persisted.
  /// Never throws.
  Future<void> enqueue(IapProduct product, List<String> transactionIds) async {
    if (!enabled) return;
    try {
      await load();
      if (_prefs == null) return;
      final token = tokenOf(transactionIds);
      if (token == null) return;
      if (_revoked.contains(_idOf(token))) return;
      if (_queue.any((i) => i.token == token)) return;
      if (_noAds.any((t) => t.token == token)) return;
      final now = _clock().millisecondsSinceEpoch;
      _queue.add(
        _QueueItem(
          productId: product.storeId,
          token: token,
          addedMs: now,
          nextMs: now,
          attempts: 0,
        ),
      );
      while (_queue.length > maxQueue) {
        _queue.removeAt(0);
      }
      await _save();
    } catch (e) {
      _log('enqueue failed: ${e.runtimeType}');
      return;
    }
    unawaited(drain());
  }

  /// Checks every due item with the server (one drain at a time). Never
  /// throws; never awaited by gameplay.
  Future<void> drain() {
    if (!enabled || !callsAllowed || _send == null) return Future.value();
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    try {
      await load();
      if (_prefs == null) return;
      var now = _clock().millisecondsSinceEpoch;
      // Owned No Ads: asked again every 7 days (a refund turns it off).
      var changed = false;
      for (final t in _noAds) {
        if (now - t.checkedMs < noAdsRecheck.inMilliseconds) continue;
        if (_queue.any((i) => i.token == t.token)) continue;
        _queue.add(
          _QueueItem(
            productId: t.productId,
            token: t.token,
            addedMs: now,
            nextMs: now,
            attempts: 0,
          ),
        );
        changed = true;
      }
      if (changed) await _save();
      for (final item in List.of(_queue)) {
        now = _clock().millisecondsSinceEpoch;
        if (item.nextMs > now) continue;
        if (now - item.addedMs > maxAge.inMilliseconds) {
          _log('${item.productId}: undecided for too long, dropped');
          _queue.remove(item);
          await _save();
          continue;
        }
        await _check(item, now);
      }
    } catch (e) {
      _log('drain failed: ${e.runtimeType}');
    }
  }

  Future<void> _check(_QueueItem item, int now) async {
    PurchaseVerdict verdict;
    try {
      verdict = await _send!(
        platform,
        item.productId,
        item.token,
      ).timeout(callTimeout);
    } on PurchaseVerifyRefused {
      _log('${item.productId}: refused by the server, dropped');
      _queue.remove(item);
      await _save();
      return;
    } catch (e) {
      // Not reachable (offline, App Check, timeout): retry with backoff.
      final wait = offlineBackoff * (1 << item.attempts.clamp(0, 10));
      item
        ..attempts += 1
        ..nextMs =
            now +
            (wait > unknownBackoff ? unknownBackoff : wait).inMilliseconds;
      _log('${item.productId}: not reachable (${e.runtimeType}), retry later');
      await _save();
      return;
    }
    _log('${item.productId}: ${verdict.name}');
    final product = _productOf(item.productId);
    final noAds = product?.grantsNoAds ?? false;
    switch (verdict) {
      case PurchaseVerdict.valid:
        _queue.remove(item);
        if (noAds) {
          _noAds
            ..removeWhere((t) => t.token == item.token)
            ..add(
              _NoAdsToken(
                productId: item.productId,
                token: item.token,
                checkedMs: now,
              ),
            );
        }
        await _save();
      case PurchaseVerdict.unknown:
        item
          ..attempts += 1
          ..nextMs = now + unknownBackoff.inMilliseconds;
        await _save();
      case PurchaseVerdict.revoked:
        _queue.remove(item);
        _noAds.removeWhere((t) => t.token == item.token);
        final id = _idOf(item.token);
        _revoked
          ..remove(id)
          ..add(id);
        while (_revoked.length > maxRevoked) {
          _revoked.removeAt(0);
        }
        await _save();
        if (noAds) {
          // Another No-Ads purchase that is not revoked (verified, or
          // still waiting) keeps No Ads on.
          final other =
              _noAds.isNotEmpty ||
              _queue.any((i) => _productOf(i.productId)?.grantsNoAds ?? false);
          if (other) {
            _log('No Ads refund: another No-Ads purchase keeps it on');
          } else {
            try {
              await onNoAdsRevoked?.call();
            } catch (e) {
              _log('No Ads off failed: ${e.runtimeType}');
            }
          }
        }
      // Consumables: coins are never taken back (log only).
      case PurchaseVerdict.invalid
          when _noAds.any((t) => t.token == item.token):
        // Verified before: a later "invalid" (an expired store record) is
        // never proof of a fake. Asked again at the next re-check.
        _queue.remove(item);
        await _save();
      case PurchaseVerdict.invalid:
        _queue.remove(item);
        await _save();
        // Never take the grant back (D1 silent): the install only stops
        // reaching other players.
        try {
          await _prefs?.setBool(kIapFakeKey, true);
        } catch (_) {}
        try {
          _markUntrusted(kIapFakeReason);
        } catch (_) {}
    }
  }

  static IapProduct? _productOf(String storeId) {
    for (final p in IapProduct.values) {
      if (p.storeId == storeId) return p;
    }
    return null;
  }

  static void _log(String message) => iapLog('verify: $message');

  static Future<PurchaseVerdict> _firebaseCall(
    Future<bool> Function() ensureFirebase,
    String platform,
    String productId,
    String token,
  ) async {
    if (!await ensureFirebase()) throw StateError('Firebase not ready');
    await FirebaseVersusBackend.activateAppCheck();
    final HttpsCallableResult<Object?> result;
    try {
      result =
          await FirebaseFunctions.instanceFor(
            region: VersusConfig.functionsRegion,
          ).httpsCallable(kVerifyPurchaseFunction).call<Object?>({
            'platform': platform,
            'productId': productId,
            'token': token,
          });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'invalid-argument') throw const PurchaseVerifyRefused();
      rethrow;
    }
    final data = result.data;
    final status = data is Map ? data['status'] : null;
    for (final v in PurchaseVerdict.values) {
      if (v.name == status) return v;
    }
    return PurchaseVerdict.unknown;
  }
}

class _QueueItem {
  _QueueItem({
    required this.productId,
    required this.token,
    required this.addedMs,
    required this.nextMs,
    required this.attempts,
  });

  static _QueueItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'], t = j['t'], at = j['at'], next = j['next'];
    if (pid is! String || t is! String || at is! int || next is! int) {
      return null;
    }
    final n = j['n'];
    return _QueueItem(
      productId: pid,
      token: t,
      addedMs: at,
      nextMs: next,
      attempts: n is int ? n : 0,
    );
  }

  final String productId;
  final String token;
  final int addedMs;
  int nextMs;
  int attempts;

  Map<String, Object> toJson() => {
    'pid': productId,
    't': token,
    'at': addedMs,
    'next': nextMs,
    'n': attempts,
  };
}

class _NoAdsToken {
  _NoAdsToken({
    required this.productId,
    required this.token,
    required this.checkedMs,
  });

  static _NoAdsToken? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'], t = j['t'], chk = j['chk'];
    if (pid is! String || t is! String || chk is! int) return null;
    return _NoAdsToken(productId: pid, token: t, checkedMs: chk);
  }

  final String productId;
  final String token;
  final int checkedMs;

  Map<String, Object> toJson() => {
    'pid': productId,
    't': token,
    'chk': checkedMs,
  };
}
