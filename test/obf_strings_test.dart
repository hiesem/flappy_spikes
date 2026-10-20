// PRD-2.5 §3.5 WP-STRINGS: the masked anchor strings decode to exactly the
// literals they replaced (no stored key, product id or callable changes),
// and the committed lib/services/obf_strings.g.dart is in sync with
// tool/gen_obf_strings.dart.
import 'dart:io';

import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flappy_spikes/services/purchase_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/gen_obf_strings.dart';

void main() {
  group('PRD-2.5 §3.5 WP-STRINGS', () {
    test('every Obf value decodes to its table literal', () {
      expect(Obf.debugValues, kObfStrings.values.toList());
    });

    test('regenerating gives the committed file (run '
        '`dart run tool/gen_obf_strings.dart` after a table change)', () {
      expect(File(kObfOutput).readAsStringSync(), generateObfSource());
    });

    test('the masked data is not the plain text', () {
      final src = File(kObfOutput).readAsStringSync();
      for (final v in kObfStrings.values) {
        expect(src.contains("'$v'"), isFalse, reason: v);
        expect(
          src.contains(v.codeUnits.join(', ')),
          isFalse,
          reason: '$v as plain code units',
        );
      }
    });

    test('the consumers keep the old literals', () {
      expect(
        [for (final p in IapProduct.values) p.storeId],
        [
          'coins_1000',
          'coins_10000',
          'coins_17000',
          'coins_100000',
          'no_ads',
          'gift_coins_10000',
          'gift_noads_coins_10000',
        ],
      );
      expect(InterstitialSkip.noAds.analyticsName, 'no_ads');
      expect(
        InterstitialSkip.rewardedThisRun.analyticsName,
        'rewarded_this_run',
      );
      expect(VersusConfig.deleteFunction, 'deleteMyData');
      expect(VersusConfig.setNameFunction, 'setVersusName');
      expect(VersusConfig.getNameFunction, 'getVersusName');
      expect(VersusConfig.pgSaltKey, 'versus_pg_salt');
      expect(kVerifyPurchaseFunction, 'verifyPurchase');
      expect(kIapVerifyQueueKey, 'iapVerifyQueue');
      expect(kRevokedPurchasesKey, 'revokedPurchases');
      expect(kIapNoAdsTokensKey, 'iapNoAdsTokens');
      expect(kIapFakeKey, 'iapFake');
      expect(IntegrityGuard.iapFakeKey, 'iapFake');
      expect(IntegrityGuard.appleTeamId, 'TF9VESMTKV');
      expect(
        IntegrityGuard.playCertSha256,
        '324311eff3c0134cf41d7b82162d836f3c5e2824e65b410e6392e287667e328f',
      );
      expect(Obf.colPlayers, 'players');
      expect(Obf.colPools, 'pools');
      expect(
        [Obf.chIntegrity, Obf.chSealKey, Obf.chSeal, Obf.chSealDrop],
        ['integrity', 'sealKey', 'seal', 'sealDrop'],
      );
    });

    test(
      'GameStorage still reads and writes the old preference names',
      () async {
        SharedPreferences.setMockInitialValues({
          'bestScore': 41,
          'coins': 1234,
          'noAds': true,
          'ownedItems': ['hat:crown'],
          'equippedItem.hat': 'crown',
          'freeCoinsCount': 2,
        });
        final storage = GameStorage();
        await storage.load();
        expect(storage.bestScore, 41);
        expect(storage.coins, 1234);
        expect(storage.noAds, isTrue);
        expect(storage.ownedItems, contains('hat:crown'));
        await storage.saveCoins(99);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('coins'), 99);
      },
    );
  });
}
