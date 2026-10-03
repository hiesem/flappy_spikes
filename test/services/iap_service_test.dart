import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects every event emitted on [service] while [body] runs (plus one
/// event-loop turn for the broadcast controller to deliver).
Future<List<IapEvent>> collect(
  IapService service,
  Future<void> Function() body,
) async {
  final events = <IapEvent>[];
  final sub = service.events.listen(events.add);
  await body();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return events;
}

List<IapStatus> statuses(List<IapEvent> events) =>
    events.map((e) => e.status).toList();

void main() {
  group('IapProduct', () {
    test('store ids', () {
      expect(IapProduct.values.map((p) => p.storeId), [
        'coins_500',
        'coins_1800',
        'coins_5000',
        'coins_12000',
        'no_ads',
      ]);
    });

    test('coins, consumable and placeholder prices', () {
      expect(IapProduct.values.map((p) => p.coins), [
        500,
        1800,
        5000,
        12000,
        0,
      ]);
      expect(IapProduct.values.map((p) => p.consumable), [
        true,
        true,
        true,
        true,
        false,
      ]);
      expect(IapProduct.values.map((p) => p.placeholderPrice), [
        '€0.99',
        '€2.99',
        '€6.99',
        '€14.99',
        '€2.99',
      ]);
      expect(kNoAdsBonusCoins, 1000);
    });
  });

  group('NoopIapService', () {
    test(
      'unavailable, placeholder prices, buy fails, restore is silent',
      () async {
        final iap = NoopIapService();
        await iap.initialize();
        expect(iap.isAvailable, isFalse);
        for (final p in IapProduct.values) {
          expect(iap.priceOf(p), p.placeholderPrice);
        }
        final events = await collect(iap, () => iap.buy(IapProduct.coins500));
        expect(events, hasLength(1));
        expect(events.single.product, IapProduct.coins500);
        expect(events.single.status, IapStatus.failed);
        expect(await collect(iap, iap.restore), isEmpty);
      },
    );
  });

  group('FakeIapService', () {
    test('defaults: available, succeed mode, placeholder prices', () async {
      final iap = FakeIapService();
      await iap.initialize();
      expect(iap.isAvailable, isTrue);
      expect(iap.mode, FakeIapMode.succeed);
      expect(iap.priceOf(IapProduct.coins12000), '€14.99');
    });

    test('succeed: pending then purchased', () async {
      final iap = FakeIapService();
      final events = await collect(iap, () => iap.buy(IapProduct.coins1800));
      expect(statuses(events), [IapStatus.pending, IapStatus.purchased]);
      expect(events.every((e) => e.product == IapProduct.coins1800), isTrue);
      expect(iap.purchases, [IapProduct.coins1800]);
    });

    test('fail: pending then failed with a message', () async {
      final iap = FakeIapService()..mode = FakeIapMode.fail;
      final events = await collect(iap, () => iap.buy(IapProduct.coins500));
      expect(statuses(events), [IapStatus.pending, IapStatus.failed]);
      expect(events.last.message, isNotNull);
    });

    test('cancel: pending then canceled', () async {
      final iap = FakeIapService()..mode = FakeIapMode.cancel;
      final events = await collect(iap, () => iap.buy(IapProduct.coins5000));
      expect(statuses(events), [IapStatus.pending, IapStatus.canceled]);
    });

    test('pending: only pending', () async {
      final iap = FakeIapService()..mode = FakeIapMode.pending;
      final events = await collect(iap, () async {
        await iap.buy(IapProduct.noAds);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(statuses(events), [IapStatus.pending]);
      expect(iap.ownsNoAds, isFalse);
    });

    test(
      'restore emits restored noAds only after a successful purchase',
      () async {
        final iap = FakeIapService();
        expect(await collect(iap, iap.restore), isEmpty);

        // A failed / canceled noAds purchase does not count as owned.
        iap.mode = FakeIapMode.fail;
        await iap.buy(IapProduct.noAds);
        iap.mode = FakeIapMode.cancel;
        await iap.buy(IapProduct.noAds);
        expect(await collect(iap, iap.restore), isEmpty);

        // Consumables are never restored.
        iap.mode = FakeIapMode.succeed;
        await iap.buy(IapProduct.coins500);
        expect(await collect(iap, iap.restore), isEmpty);

        await iap.buy(IapProduct.noAds);
        expect(iap.ownsNoAds, isTrue);
        final restored = await collect(iap, iap.restore);
        expect(restored, hasLength(1));
        expect(restored.single.product, IapProduct.noAds);
        expect(restored.single.status, IapStatus.restored);
      },
    );

    test('delay separates pending from the result', () async {
      final iap = FakeIapService()..delay = const Duration(milliseconds: 30);
      final events = <IapEvent>[];
      final sub = iap.events.listen(events.add);
      final purchase = iap.buy(IapProduct.coins500);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(statuses(events), [IapStatus.pending]);
      await purchase;
      await Future<void>.delayed(Duration.zero);
      expect(statuses(events), [IapStatus.pending, IapStatus.purchased]);
      await sub.cancel();
    });

    test('events is a broadcast stream', () async {
      final iap = FakeIapService();
      final a = <IapEvent>[];
      final b = <IapEvent>[];
      final subA = iap.events.listen(a.add);
      final subB = iap.events.listen(b.add);
      await iap.buy(IapProduct.coins500);
      await Future<void>.delayed(Duration.zero);
      expect(a, hasLength(2));
      expect(b, hasLength(2));
      await subA.cancel();
      await subB.cancel();
    });
  });
}
