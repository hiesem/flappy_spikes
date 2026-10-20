import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PRD-2.5 §3.4 WP-SAVE: the device key behind the tamper-evident save.
///
/// Android keeps a non-exportable AndroidKeyStore HMAC key and computes the
/// MACs natively; iOS hands a Keychain key to Dart, which computes them.
/// Every method fails soft: null / false means "no sealing", never an
/// exception.
abstract class SaveSealer {
  /// Makes sure the key exists. True = it existed already, false = it was
  /// just created, null = sealing is unavailable.
  Future<bool?> ensureKey();

  /// HMAC-SHA256 of each payload with the key (null on failure).
  /// [SealMacs.rekeyed]: the old key was unusable and a new one was made,
  /// so MACs made earlier can no longer verify.
  Future<SealMacs?> mac(List<Uint8List> payloads);

  /// Deletes the key (best effort): the next start takes the
  /// "key absent" path (trusted).
  Future<void> drop();
}

class SealMacs {
  const SealMacs(this.macs, {this.rekeyed = false});

  final List<String> macs;
  final bool rekeyed;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The native sealer on the `flappy_spikes/device` channel
/// (MainActivity.kt / AppDelegate.swift: `sealKey`, `seal`, `sealDrop`).
class PlatformSaveSealer implements SaveSealer {
  PlatformSaveSealer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('flappy_spikes/device');

  final MethodChannel _channel;

  /// iOS: the Keychain key (MACs in Dart). Android: null (MACs native).
  List<int>? _key;

  @override
  Future<bool?> ensureKey() async {
    try {
      final r = await _channel.invokeMapMethod<Object?, Object?>('sealKey');
      if (r == null) return null;
      final key = r['key'];
      if (key is Uint8List && key.length >= 16) _key = key;
      final existed = r['existed'];
      return existed is bool ? existed : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SealMacs?> mac(List<Uint8List> payloads) async {
    final key = _key;
    if (key != null) {
      final h = Hmac(sha256, key);
      return SealMacs([for (final p in payloads) _hex(h.convert(p).bytes)]);
    }
    try {
      final r = await _channel.invokeMapMethod<Object?, Object?>(
        'seal',
        payloads,
      );
      final macs = r?['macs'];
      if (macs is! List || macs.length != payloads.length) return null;
      final out = <String>[];
      for (final m in macs) {
        if (m is! Uint8List) return null;
        out.add(_hex(m));
      }
      return SealMacs(out, rekeyed: r?['rekeyed'] == true);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> drop() async {
    _key = null;
    try {
      await _channel.invokeMethod<void>('sealDrop');
    } catch (_) {}
  }
}

/// An in-memory sealer (tests): the key lives as long as the object.
@visibleForTesting
class MemorySaveSealer implements SaveSealer {
  MemorySaveSealer({this.available = true});

  bool available;
  List<int>? key;
  int macCalls = 0;
  bool failMacs = false;

  @override
  Future<bool?> ensureKey() async {
    if (!available) return null;
    if (key != null) return true;
    final r = Random(7);
    key = [for (var i = 0; i < 32; i++) r.nextInt(256)];
    return false;
  }

  @override
  Future<SealMacs?> mac(List<Uint8List> payloads) async {
    final k = key;
    if (!available || k == null || failMacs) return null;
    macCalls++;
    final h = Hmac(sha256, k);
    return SealMacs([for (final p in payloads) _hex(h.convert(p).bytes)]);
  }

  @override
  Future<void> drop() async => key = null;
}

/// One sealed snapshot: a short hash per covered field, the sticky
/// untrusted flag and the MAC over both.
class SealSnapshot {
  SealSnapshot(this.hashes, {required this.untrusted, this.mac = ''});

  final Map<String, String> hashes;
  final bool untrusted;
  final String mac;

  /// The canonical bytes the MAC covers (sorted keys).
  Uint8List payload() {
    final keys = hashes.keys.toList()..sort();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'h': {for (final k in keys) k: hashes[k]},
          'u': untrusted,
        }),
      ),
    );
  }

  SealSnapshot withMac(String m) =>
      SealSnapshot(hashes, untrusted: untrusted, mac: m);

  Map<String, Object> toJson() => {'h': hashes, 'u': untrusted, 'm': mac};

  static SealSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final h = raw['h'];
    final u = raw['u'];
    final m = raw['m'];
    if (h is! Map || u is! bool || m is! String) return null;
    final hashes = <String, String>{};
    for (final e in h.entries) {
      if (e.key is! String || e.value is! String) return null;
      hashes[e.key as String] = e.value as String;
    }
    return SealSnapshot(hashes, untrusted: u, mac: m);
  }
}

/// The stored seal: the latest snapshot and the one before it.
class SealRecord {
  const SealRecord(this.cur, this.prev);

  final SealSnapshot cur;
  final SealSnapshot? prev;

  String encode() => jsonEncode({'cur': cur.toJson(), 'prev': prev?.toJson()});

  /// Null when [raw] is not a well-formed record.
  static SealRecord? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final cur = SealSnapshot.fromJson(j['cur']);
      if (cur == null) return null;
      final p = j['prev'];
      final prev = p == null ? null : SealSnapshot.fromJson(p);
      if (p != null && prev == null) return null;
      return SealRecord(cur, prev);
    } catch (_) {
      return null;
    }
  }
}

/// The canonical hash of one covered field's value (sets sorted by the
/// caller, JSON, SHA-256, first 128 bits).
String sealFieldHash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString().substring(0, 32);
