import 'dart:async';

import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';

import 'menu_e2e_test.dart' show RecordingServices;

// Exercise the production adapter, with every platform call intercepted.
// Native callbacks are delivered through the plugin's real message handler;
// no device, actual SDK, consent form or network is involved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ump = MethodChannel(
    'plugins.flutter.io/google_mobile_ads/ump',
    StandardMethodCodec(UserMessagingCodec()),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late int loadedId;
  late AdMobRewardedAds ads;

  Future<void> event(
    String name, [
    Map<String, Object> extra = const {},
  ]) async {
    final channel = instanceManager.channel;
    final response = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall('onAdEvent', {
          'adId': loadedId,
          'eventName': name,
          ...extra,
        }),
      ),
      response.complete,
    );
    channel.codec.decodeEnvelope((await response.future)!);
    await Future<void>.value();
  }

  setUp(() async {
    messenger.setMockMethodCallHandler(
      ump,
      (call) async =>
          call.method == 'ConsentInformation#canRequestAds' ? true : null,
    );
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      if (call.method == 'MobileAds#initialize') {
        return InitializationStatus({});
      }
      if (call.method == 'loadRewardedAd') {
        loadedId = call.arguments['adId'] as int;
      }
      return null;
    });
    ads = AdMobRewardedAds();
    await ads.initialize();
    await event('onAdLoaded');
    expect(ads.isAvailable, isTrue);
  });

  tearDown(() async {
    final remaining = instanceManager.adFor(loadedId);
    if (remaining != null) await remaining.dispose();
    messenger.setMockMethodCallHandler(ump, null);
    messenger.setMockMethodCallHandler(instanceManager.channel, null);
  });

  for (final placement in [AdPlacement.homeSlot, AdPlacement.shopFreeCoins]) {
    test('S2-02 mobile logs impression on display ${placement.name}', () async {
      final spy = RecordingServices();
      final g = FlappySpikesGame(
        soundEnabled: false,
        services: spy,
        monetization: Monetization(ads: ads),
      );
      final pending = g.showRewardedAd(placement);
      await Future<void>.value();
      await event('onAdShowedFullScreenContent');
      final whileVisible = spy.params('ad_rewarded_shown').toList();
      expect(spy.params('ad_reward_earned'), isEmpty);
      // Close and drain everything before asserting, so failures leave no
      // unresolved ad and distinguish missing timing from missing totals.
      await event('onAdDismissedFullScreenContent');
      expect(await pending, AdResult.dismissed);
      expect(spy.params('ad_rewarded_shown').single, {
        'placement': placement.analyticsName,
      });
      expect(
        whileVisible,
        [
          {'placement': placement.analyticsName},
        ],
        reason:
            'DECISIONS #16 requires on display. The real mobile callback '
            'was delivered; currently the event waits until dismissal.',
      );
    });
  }

  for (final outcome in ['completed', 'dismissed', 'failed']) {
    test('R2 mobile ad outcome and reward analytics $outcome', () async {
      final spy = RecordingServices();
      final g = FlappySpikesGame(
        soundEnabled: false,
        services: spy,
        monetization: Monetization(ads: ads),
      );
      final pending = g.showRewardedAd(AdPlacement.homeSlot);
      await Future<void>.value();
      if (outcome == 'failed') {
        await event('onFailedToShowFullScreenContent', {
          'error': AdError(0, 'qa', 'Scripted show failure'),
        });
      } else {
        await event('onAdShowedFullScreenContent');
        if (outcome == 'completed') {
          await event('onRewardedAdUserEarnedReward', {
            'rewardItem': RewardItem(1, 'qa'),
          });
        }
        await event('onAdDismissedFullScreenContent');
      }
      expect(await pending, switch (outcome) {
        'completed' => AdResult.completed,
        'dismissed' => AdResult.dismissed,
        _ => AdResult.failed,
      });
      expect(
        spy.params('ad_rewarded_shown').length,
        outcome == 'failed' ? 0 : 1,
      );
      expect(
        spy.params('ad_reward_earned').length,
        outcome == 'completed' ? 1 : 0,
      );
    });
  }
}
