import 'dart:async';

import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [GameServices] whose plugin seams are scripted to throw or hang and
/// whose analytics calls are recorded — no plugin is ever touched, honoring
/// the "tests never touch plugins" invariant.
class FakeGameServices extends GameServices {
  final List<Map<String, Object?>> events = [];

  Object? signInError;
  Object? showError;
  Object? submitError;

  /// When set, [signInPlugin] waits on this completer (simulates a hang).
  Completer<void>? signInHang;

  int signInCalls = 0;
  int showCalls = 0;
  int submitCalls = 0;

  /// 2.4.0 (24): what the silent Play Games check answers, and how often
  /// it was asked.
  bool authenticated = false;
  bool authThrows = false;
  int authChecks = 0;

  @override
  Future<bool> isAuthenticatedPlugin() async {
    authChecks++;
    if (authThrows) throw StateError('pgs');
    return authenticated;
  }

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add({'name': name, ...?parameters});
  }

  @override
  Future<void> signInPlugin() async {
    signInCalls++;
    if (signInHang != null) {
      await signInHang!.future;
    }
    if (signInError != null) {
      throw signInError!;
    }
  }

  @override
  Future<void> showLeaderboardsPlugin() async {
    showCalls++;
    if (showError != null) {
      throw showError!;
    }
  }

  @override
  Future<void> submitScorePlugin(int value) async {
    submitCalls++;
    if (submitError != null) {
      throw submitError!;
    }
  }
}

void main() {
  group('pgs_error telemetry (Fixes A and C)', () {
    test(
      'a thrown PlatformException is logged and does not escape '
      'showLeaderboards',
      () async {
        final s = FakeGameServices()..markInitialized();
        s.signInError = PlatformException(code: 'failed_to_authenticate');

        final result = await s.showLeaderboards();

        expect(result, ShowLeaderboardResult.signInFailed);
        expect(s.events, hasLength(1));
        expect(s.events.single['name'], 'pgs_error');
        expect(s.events.single['op'], 'sign_in');
        expect(s.events.single['code'], 'failed_to_authenticate');
        expect(
          s.showCalls,
          0,
          reason: 'the leaderboard UI must not open after a failed sign-in',
        );
      },
    );

    test('submitBestScore logs op submit_score and never throws', () async {
      final s = FakeGameServices()..markInitialized();
      s.submitError = PlatformException(
        code: 'failed_to_send_score',
        message: 'boom',
      );

      await s.submitBestScore(42);

      expect(s.submitCalls, 1);
      expect(s.events, hasLength(1));
      expect(s.events.single['name'], 'pgs_error');
      expect(s.events.single['op'], 'submit_score');
      expect(s.events.single['code'], 'failed_to_send_score');
    });

    test(
      'a leaderboard-UI failure is attributed separately from sign-in',
      () async {
        final s = FakeGameServices()..markInitialized();
        s.showError = PlatformException(code: 'leaderboard_not_found');

        final result = await s.showLeaderboards();

        expect(result, ShowLeaderboardResult.leaderboardFailed);
        expect(s.signInCalls, 1, reason: 'sign-in is attempted first');
        expect(s.events.single['op'], 'show_leaderboards');
        expect(s.events.single['code'], 'leaderboard_not_found');
      },
    );

    test('long error messages are truncated to 90 chars', () async {
      final s = FakeGameServices()..markInitialized();
      s.signInError = PlatformException(code: 'x', message: 'a' * 200);

      await s.showLeaderboards();

      expect((s.events.single['message']! as String).length, 90);
    });
  });

  group('double-tap guard and timeouts (Fix D)', () {
    test(
      'two rapid showLeaderboards calls produce exactly one plugin sign-in',
      () async {
        final s = FakeGameServices()..markInitialized();
        s.signInHang = Completer<void>();

        final first = s.showLeaderboards();
        final second = await s.showLeaderboards();

        expect(second, ShowLeaderboardResult.busy);
        expect(s.signInCalls, 1);

        s.signInHang!.complete();
        expect(await first, ShowLeaderboardResult.opened);

        // The guard is released once the first call finishes.
        expect(await s.showLeaderboards(), ShowLeaderboardResult.opened);
        expect(s.signInCalls, 1, reason: 'still signed in: no second sign-in');
        expect(s.showCalls, 2);
      },
    );

    test('a hanging plugin call times out into a pgs_error timeout event', () async {
      final s = FakeGameServices()..markInitialized();
      s.pluginTimeout = const Duration(milliseconds: 50);
      s.signInHang = Completer<void>(); // never completed

      final result = await s.showLeaderboards();

      expect(result, ShowLeaderboardResult.signInFailed);
      expect(s.events.single['name'], 'pgs_error');
      expect(s.events.single['code'], 'timeout');
    });
  });

  group('item analytics (PRD-menu-v2 §7.3)', () {
    test('each item event carries its layer, id and optional fields', () {
      final s = FakeGameServices();
      s.logItemTryOn(SkinLayer.gear, 'windup', Rarity.rare);
      s.logItemPurchase(SkinLayer.hat, 'crown', Rarity.legendary, 5000);
      s.logItemEquip(SkinLayer.bird, 'ghost');
      s.logItemNoCoins(SkinLayer.hoop, 'blackhole', 4000);
      s.logSkinShopTab(SkinLayer.trail);

      expect(s.events[0], {
        'name': 'item_try_on',
        'layer': 'gear',
        'id': 'windup',
        'rarity': 'RARE',
      });
      expect(s.events[1], {
        'name': 'item_purchase',
        'layer': 'hat',
        'id': 'crown',
        'rarity': 'LEGENDARY',
        'price': 5000,
      });
      expect(s.events[2], {
        'name': 'item_equip',
        'layer': 'bird',
        'id': 'ghost',
      });
      expect(s.events[3], {
        'name': 'item_no_coins',
        'layer': 'hoop',
        'id': 'blackhole',
        'shortfall': 4000,
      });
      expect(s.events[4], {'name': 'skin_shop_tab', 'layer': 'trail'});
    });

    test('a rarity-less none entry omits the rarity key', () {
      final s = FakeGameServices();
      s.logItemTryOn(SkinLayer.gear, 'none', null);
      expect(s.events.single,
          {'name': 'item_try_on', 'layer': 'gear', 'id': 'none'});
    });
  });

  group('no-op by default', () {
    test('an uninitialized service never touches plugins', () async {
      final s = FakeGameServices(); // no markInitialized()

      expect(await s.showLeaderboards(), ShowLeaderboardResult.unavailable);
      await s.submitBestScore(5);

      expect(s.signInCalls + s.showCalls + s.submitCalls, 0);
      expect(s.events, isEmpty);
    });
  });
}
