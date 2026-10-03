import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingAds extends NoopRewardedAds {
  @override
  Future<void> initialize() async => throw StateError('boom');
}

class _ThrowingIap extends NoopIapService {
  @override
  Future<void> initialize() async => throw StateError('boom');
}

void main() {
  test('defaults are the fakes', () {
    final m = Monetization();
    expect(m.ads, isA<FakeRewardedAds>());
    expect(m.iap, isA<FakeIapService>());
    expect(m.isFake, isTrue);
  });

  test('isFake is false unless both services are fakes', () {
    expect(Monetization(ads: NoopRewardedAds()).isFake, isFalse);
    expect(Monetization(iap: NoopIapService()).isFake, isFalse);
    expect(
      Monetization(ads: NoopRewardedAds(), iap: NoopIapService()).isFake,
      isFalse,
    );
  });

  test('forPlatform on the (non-mobile) test host uses the fakes', () {
    final m = Monetization.forPlatform();
    expect(m.isFake, isTrue);
  });

  test('initialize never throws, even when a service does', () async {
    await Monetization().initialize();
    await Monetization(ads: _ThrowingAds(), iap: _ThrowingIap()).initialize();
  });

  test('full fake flow works without any plugin', () async {
    final m = Monetization();
    await m.initialize();
    expect(m.ads.isAvailable, isTrue);
    expect(await m.ads.show(AdPlacement.homeSlot), AdResult.completed);
    final events = <IapEvent>[];
    final sub = m.iap.events.listen(events.add);
    await m.iap.buy(IapProduct.noAds);
    await m.iap.restore();
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.status), [
      IapStatus.pending,
      IapStatus.purchased,
      IapStatus.restored,
    ]);
    await sub.cancel();
  });
}
