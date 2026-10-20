import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/diag.dart';
import 'tester.dart';
import 'obf_strings.g.dart';

/// PRD-2.5 §3.3 WP-GUARD: the install's integrity verdict.
///
/// [trusted] is true until something proves otherwise (D1: a failed check
/// only ever skips versus uploads and leaderboard submits, silently; it
/// never crashes, wipes or shows anything). Sources of "untrusted":
/// - `sig`: Android signing certificate is not the Play app-signing cert;
/// - `ios_team`: an embedded provisioning profile of another team;
/// - `save`: the tamper-evident save seal failed (WP-SAVE, `GameStorage`);
/// - `iap_fake`: a purchase the server called fake (WP-IAP; sticky through
///   the `iapFake` pref).
///
/// The default instance is trusted and does nothing until [start] runs
/// (main.dart only): tests, Linux, a missing plugin or any channel error
/// stay trusted (fail-open). Debug, profile and FS_TESTER builds never
/// enforce: they are signed with the upload key.
class IntegrityGuard {
  IntegrityGuard({
    bool? enforce,
    MethodChannel? channel,
    Future<SharedPreferences> Function()? prefs,
    this.platformOverride,
  }) : enforce = enforce ?? (kReleaseMode && !kTester),
       _channel = channel ?? const MethodChannel('flappy_spikes/device'),
       _prefs = prefs ?? SharedPreferences.getInstance;

  /// The app's guard. Replaceable in tests.
  static IntegrityGuard instance = IntegrityGuard();

  /// The Play app-signing certificate (SHA-256 of the DER cert).
  static final String playCertSha256 = Obf.playCertSha256;

  /// The Apple Developer team that signs our own builds.
  static final String appleTeamId = Obf.appleTeamId;

  /// WP-IAP's sticky marker (written by the purchase verifier).
  static final String iapFakeKey = Obf.prefIapFake;

  /// The bound of [waitReady] (PRD §3.3 "Race").
  static const Duration readyTimeout = Duration(seconds: 2);

  /// False in debug / profile / FS_TESTER builds: [trusted] is then always
  /// true (reasons are still recorded for the debug log).
  final bool enforce;
  final MethodChannel _channel;
  final Future<SharedPreferences> Function() _prefs;

  /// Tests: 'android' / 'ios' instead of the real platform.
  final String? platformOverride;

  String? _reason;
  bool _reported = false;
  bool _started = false;
  Future<void> _ready = Future<void>.value();

  /// The analytics sink of the one `integrity_untrusted` event per process
  /// (main.dart wires it to GameServices). Only called when [enforce].
  void Function(String reason)? onUntrusted;

  /// Whether versus uploads and leaderboard submits may go out.
  bool get trusted => !enforce || _reason == null;

  /// The first reason this install is untrusted (null = none).
  String? get reason => _reason;

  /// Completes when the start checks (and any [track]ed check, like the
  /// save seal) are done. Never fails.
  Future<void> get ready => _ready;

  /// [ready], bounded by [readyTimeout]: on a timeout the current value of
  /// [trusted] applies. Never throws.
  Future<void> waitReady() async {
    try {
      await _ready.timeout(readyTimeout);
    } catch (_) {}
  }

  /// Marks the install untrusted for this process (the first reason wins).
  void markUntrusted(String reason) {
    if (_reason != null) return;
    _reason = reason;
    diag('FS-Guard untrusted ($reason${enforce ? '' : ', not enforced'})');
    if (!enforce || _reported) return;
    _reported = true;
    try {
      onUntrusted?.call(reason);
    } catch (_) {}
  }

  /// Adds [check] to [ready] (errors are swallowed).
  void track(Future<void> check) {
    final before = _ready;
    final safe = check.catchError((Object _) {});
    _ready = Future.wait([before, safe]).then((_) {});
  }

  /// Runs the platform checks once (main.dart, after GameServices.initialize
  /// was started). Never awaited by gameplay.
  Future<void> start() {
    if (_started) return _ready;
    _started = true;
    if (!enforce) return _ready;
    track(_check());
    return _ready;
  }

  String get _os {
    final o = platformOverride;
    if (o != null) return o;
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  Future<void> _check() async {
    try {
      final prefs = await _prefs();
      if (prefs.getBool(iapFakeKey) ?? false) markUntrusted('iap_fake');
    } catch (_) {}
    final os = _os;
    if (os != 'android' && os != 'ios') return;
    Map<Object?, Object?>? info;
    try {
      info = await _channel.invokeMapMethod<Object?, Object?>(Obf.chIntegrity);
    } catch (e) {
      // MissingPluginException / PlatformException: fail-open.
      diag('FS-Guard check unavailable');
      return;
    }
    if (info == null) return;
    if (os == 'android') {
      _android(info);
    } else {
      _ios(info);
    }
  }

  void _android(Map<Object?, Object?> info) {
    final raw = info['certs'];
    final certs = raw is List
        ? [
            for (final c in raw)
              if (c is String) c.toLowerCase(),
          ]
        : const <String>[];
    final installer = info['installer'];
    if (installer != 'com.android.vending') {
      // Logged only (REVIEW 19): device transfers / restores are honest.
      diag('FS-Guard installer_other');
    }
    // No certificate read at all is an error, not a verdict.
    if (certs.isEmpty) return;
    if (!certs.contains(playCertSha256)) markUntrusted('sig');
  }

  void _ios(Map<Object?, Object?> info) {
    final team = info['provisionTeam'];
    if (info['sandboxReceipt'] == true) diag('FS-Guard sandbox receipt');
    if (team is String && team.isNotEmpty && team != appleTeamId) {
      markUntrusted('ios_team');
    }
  }
}
