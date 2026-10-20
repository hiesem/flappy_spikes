import 'dart:async';
import 'dart:convert';

import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/purchase_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scriptable `verifyPurchase`: answers per token (default [fallback]),
/// throws while [offline]; records every call.
class FakeServer {
  final Map<String, PurchaseVerdict> answers = {};
  PurchaseVerdict fallback = PurchaseVerdict.valid;
  bool offline = false;
  final List<(String, String, String)> calls = [];

  Future<PurchaseVerdict> call(
    String platform,
    String productId,
    String token,
  ) async {
    calls.add((platform, productId, token));
    if (offline) throw StateError('offline');
    return answers[token] ?? fallback;
  }
}

/// PRD-2.5 §3.8 WP-IAP client: grant first, verify later, refunds and fakes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late DateTime now;
  late List<String> untrusted;

  PurchaseVerifier makeVerifier({bool callsAllowed = true}) => PurchaseVerifier(
    call: server.call,
    platform: 'android',
    clock: () => now,
    markUntrusted: untrusted.add,
    callsAllowed: callsAllowed,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeServer();
    now = DateTime(2026, 10, 20, 12);
    untrusted = [];
  });

  /// A Play delivery of [product] with order id + purchase token.
  IapEvent play(
    IapProduct product,
    String token, {
    IapStatus status = IapStatus.purchased,
    bool? acknowledged = true,
  }) => IapEvent.store(
    product,
    status,
    transactionIds: ['id:GPA.$token', 'token:$token'],
    granted: Completer<void>(),
    acknowledged: acknowledged,
  );

  Future<
    ({
      Purchases purchases,
      MenuState menu,
      FakeIapService iap,
      PurchaseVerifier verifier,
    })
  >
  rig({PurchaseVerifier? verifier}) async {
    final storage = GameStorage(clock: () => now);
    await storage.load();
    final menu = MenuState(storage);
    final iap = FakeIapService();
    final v = verifier ?? makeVerifier();
    final purchases = Purchases(
      iap: iap,
      menu: menu,
      services: GameServices(),
      toast: (_) {},
      clock: () => now,
      verifier: v,
    )..start();
    addTearDown(purchases.dispose);
    return (purchases: purchases, menu: menu, iap: iap, verifier: v);
  }

  Future<void> settle(PurchaseVerifier v) async {
    await pumpEventQueue();
    await v.drain();
    await pumpEventQueue();
  }

  test(
    'the offline queue survives a restart and is sent when online',
    () async {
      server.offline = true;
      final r = await rig();
      r.iap.deliver(play(IapProduct.coins10000, 'T1'));
      await settle(r.verifier);
      expect(r.menu.wallet.balance, 10000, reason: 'granted at once, offline');
      expect(server.calls, hasLength(1));
      expect(server.calls.single, ('android', 'coins_10000', 'T1'));
      expect(r.verifier.pending.single.token, 'T1');
      final raw = (await SharedPreferences.getInstance()).getString(
        kIapVerifyQueueKey,
      );
      expect(raw, contains('T1'));

      // "Restart": a fresh verifier reads the persisted queue.
      server.offline = false;
      final again = makeVerifier();
      await again.load();
      expect(again.pending.single.productId, 'coins_10000');
      await again.drain();
      expect(server.calls, hasLength(1), reason: 'offline backoff not over');
      now = now.add(const Duration(minutes: 16));
      await again.drain();
      expect(server.calls, hasLength(2));
      expect(again.pending, isEmpty, reason: 'valid → dropped');
    },
  );

  test('unknown stays queued and is asked again after a day', () async {
    server.fallback = PurchaseVerdict.unknown;
    final r = await rig();
    r.iap.deliver(play(IapProduct.coins1000, 'U1'));
    await settle(r.verifier);
    expect(server.calls, hasLength(1));
    expect(r.verifier.pending, hasLength(1));
    // Launch / resume within the day: no new call.
    r.purchases.sync();
    await settle(r.verifier);
    now = now.add(const Duration(hours: 23));
    await r.verifier.drain();
    expect(server.calls, hasLength(1));
    now = now.add(const Duration(hours: 2));
    server.fallback = PurchaseVerdict.valid;
    await r.verifier.drain();
    expect(server.calls, hasLength(2));
    expect(r.verifier.pending, isEmpty);
    expect(r.menu.wallet.balance, 1000);
    expect(untrusted, isEmpty);
  });

  test('a duplicate delivery is queued once', () async {
    server.offline = true;
    final r = await rig();
    r.iap.deliver(play(IapProduct.coins1000, 'D1'));
    r.iap.deliver(play(IapProduct.coins1000, 'D1'));
    await settle(r.verifier);
    expect(r.verifier.pending, hasLength(1));
    expect(r.menu.wallet.balance, 1000, reason: 'S1-71 once per id');
  });

  test('revoked no_ads turns No Ads off and blocks the next restored '
      're-grant', () async {
    final r = await rig();
    server.answers['N1'] = PurchaseVerdict.revoked;
    server.offline = true;
    r.iap.deliver(play(IapProduct.noAds, 'N1', status: IapStatus.restored));
    await settle(r.verifier);
    expect(r.menu.noAds, isTrue, reason: 'granted first');
    server.offline = false;
    now = now.add(const Duration(hours: 1));
    await r.verifier.drain();
    expect(r.menu.noAds, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kRevokedPurchasesKey), ['token:N1']);
    // The launch sync re-delivers it: not granted again, still completed.
    final again = play(IapProduct.noAds, 'N1', status: IapStatus.restored);
    r.iap.deliver(again);
    await settle(r.verifier);
    expect(r.menu.noAds, isFalse);
    expect(again.granted!.isCompleted, isTrue);
    // Also after a restart (fresh verifier, persisted set).
    final fresh = await rig(verifier: makeVerifier());
    final third = play(IapProduct.noAds, 'N1', status: IapStatus.restored);
    fresh.iap.deliver(third);
    await settle(fresh.verifier);
    expect(fresh.menu.noAds, isFalse);
    expect(prefs.getBool(kIapFakeKey), isNull, reason: 'a refund is no fake');
    expect(untrusted, isEmpty);
    // A NEW No-Ads purchase (another token) is granted normally.
    server.answers['N2'] = PurchaseVerdict.valid;
    unawaited(fresh.purchases.buy(IapProduct.noAds));
    await pumpEventQueue();
    fresh.iap.deliver(play(IapProduct.noAds, 'N2', acknowledged: false));
    await settle(fresh.verifier);
    expect(fresh.menu.noAds, isTrue);
  });

  test('revoked consumable changes nothing on the phone', () async {
    final r = await rig();
    server.answers['C1'] = PurchaseVerdict.revoked;
    await r.menu.setNoAds(true);
    r.iap.deliver(play(IapProduct.coins17000, 'C1'));
    await settle(r.verifier);
    expect(server.calls, hasLength(1));
    expect(r.menu.wallet.balance, 17000, reason: 'coins never clawed back');
    expect(r.menu.noAds, isTrue);
    expect(untrusted, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getBool(kIapFakeKey),
      isNull,
    );
  });

  test('invalid keeps the coins and No Ads and sets iapFake', () async {
    final r = await rig();
    server.answers['F1'] = PurchaseVerdict.invalid;
    server.answers['F2'] = PurchaseVerdict.invalid;
    r.iap.deliver(play(IapProduct.coins100000, 'F1'));
    unawaited(r.purchases.buy(IapProduct.noAds));
    await pumpEventQueue();
    r.iap.deliver(play(IapProduct.noAds, 'F2', acknowledged: false));
    await settle(r.verifier);
    expect(server.calls.map((c) => c.$3), containsAll(['F1', 'F2']));
    expect(r.menu.wallet.balance, 100000 + kNoAdsBonusCoins);
    expect(r.menu.noAds, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kIapFakeKey), isTrue);
    expect(untrusted, contains(kIapFakeReason));
    expect(r.verifier.fakeSeen, isTrue);
    expect(r.verifier.pending, isEmpty);
  });

  test('two No-Ads tokens with one revoked keeps No Ads', () async {
    final r = await rig();
    // A paid no_ads and a No Ads gift code, both verified.
    r.iap.deliver(play(IapProduct.noAds, 'A1', status: IapStatus.restored));
    r.iap.deliver(
      play(
        IapProduct.giftNoAdsCoins10000,
        'A2',
        status: IapStatus.restored,
        acknowledged: false,
      ),
    );
    await settle(r.verifier);
    expect(r.menu.noAds, isTrue);
    expect(r.verifier.noAdsTokens, unorderedEquals(['A1', 'A2']));
    // A1 is refunded; seen at the 7-day re-check.
    server.answers['A1'] = PurchaseVerdict.revoked;
    now = now.add(const Duration(days: 7, minutes: 1));
    r.purchases.sync();
    await settle(r.verifier);
    expect(server.calls.where((c) => c.$3 == 'A1'), hasLength(2));
    expect(r.verifier.noAdsTokens, ['A2']);
    expect(r.menu.noAds, isTrue, reason: 'A2 still owns No Ads');
    // A2 too, a week later: now No Ads goes.
    server.answers['A2'] = PurchaseVerdict.revoked;
    now = now.add(const Duration(days: 7, minutes: 1));
    await r.verifier.drain();
    expect(r.menu.noAds, isFalse);
  });

  test('owned No Ads is re-checked at most once per 7 days', () async {
    final r = await rig();
    r.iap.deliver(play(IapProduct.noAds, 'W1', status: IapStatus.restored));
    await settle(r.verifier);
    expect(server.calls, hasLength(1));
    // Every launch sync re-delivers it: no new call within the week.
    for (var day = 1; day < 7; day++) {
      now = now.add(const Duration(days: 1));
      r.iap.deliver(play(IapProduct.noAds, 'W1', status: IapStatus.restored));
      await settle(r.verifier);
    }
    expect(server.calls, hasLength(1));
    now = now.add(const Duration(days: 1, minutes: 1));
    await r.verifier.drain();
    expect(server.calls, hasLength(2));
  });

  test('a verified No Ads later called invalid is no fake', () async {
    final r = await rig();
    r.iap.deliver(play(IapProduct.noAds, 'V1', status: IapStatus.restored));
    await settle(r.verifier);
    server.answers['V1'] = PurchaseVerdict.invalid;
    now = now.add(const Duration(days: 8));
    await r.verifier.drain();
    expect(untrusted, isEmpty);
    expect(r.menu.noAds, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(kIapFakeKey),
      isNull,
    );
  });

  test('a request the server refuses is dropped, never fake', () async {
    final r = await rig(
      verifier: PurchaseVerifier(
        call: (_, _, _) async => throw const PurchaseVerifyRefused(),
        platform: 'android',
        clock: () => now,
        markUntrusted: untrusted.add,
      ),
    );
    r.iap.deliver(play(IapProduct.coins1000, 'R1'));
    await settle(r.verifier);
    expect(r.verifier.pending, isEmpty);
    expect(untrusted, isEmpty);
  });

  test('non-release builds never call (the queue waits)', () async {
    final r = await rig(verifier: makeVerifier(callsAllowed: false));
    r.iap.deliver(play(IapProduct.coins1000, 'P1'));
    await settle(r.verifier);
    expect(server.calls, isEmpty);
    expect(r.verifier.pending, hasLength(1));
    expect(r.menu.wallet.balance, 1000);
    expect(kPurchaseVerifyCallsAllowed, isFalse, reason: 'tests run in debug');
  });

  test('purchases without a store token (fakes, iOS-less ids) are not '
      'queued', () async {
    final r = await rig();
    r.iap.deliver(
      IapEvent.store(
        IapProduct.coins1000,
        IapStatus.purchased,
        transactionIds: const ['id:GPA.only'],
        granted: Completer<void>(),
      ),
    );
    await settle(r.verifier);
    expect(r.verifier.pending, isEmpty);
    expect(server.calls, isEmpty);
  });

  test('iOS sends the StoreKit transaction id', () async {
    final v = PurchaseVerifier(
      call: server.call,
      platform: 'ios',
      clock: () => now,
      markUntrusted: untrusted.add,
    );
    final r = await rig(verifier: v);
    r.iap.deliver(
      IapEvent.store(
        IapProduct.coins1000,
        IapStatus.purchased,
        transactionIds: const ['id:2000000000000001'],
        granted: Completer<void>(),
      ),
    );
    await settle(v);
    expect(server.calls.single, ('ios', 'coins_1000', '2000000000000001'));
  });

  test('the queue is capped at 50 (oldest dropped)', () async {
    server.offline = true;
    final v = makeVerifier(callsAllowed: false);
    for (var i = 0; i < 55; i++) {
      await v.enqueue(IapProduct.coins1000, ['token:Q$i']);
    }
    expect(v.pending, hasLength(PurchaseVerifier.maxQueue));
    expect(v.pending.first.token, 'Q5');
  });

  test('the no-op default touches nothing', () async {
    final v = PurchaseVerifier.noop();
    await v.enqueue(IapProduct.coins1000, ['token:Z']);
    await v.drain();
    expect(v.isRevoked(['token:Z']), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    expect(PurchaseVerifier.instance.enabled, isFalse);
  });

  test('corrupt stored state is ignored, never thrown', () async {
    SharedPreferences.setMockInitialValues({
      kIapVerifyQueueKey: '{not json',
      kIapNoAdsTokensKey: jsonEncode([
        {'pid': 1},
      ]),
    });
    final v = makeVerifier();
    await v.load();
    expect(v.pending, isEmpty);
    expect(v.noAdsTokens, isEmpty);
    await v.drain();
  });
}
