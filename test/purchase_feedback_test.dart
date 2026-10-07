import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, TapUpDetails;
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/noads_celebration.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/ui/coin_reward.dart';
import 'package:flappy_spikes/components/ui/confetti.dart';
import 'package:flappy_spikes/components/ui/p1_popup.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'shop_flow_test.dart' as shop_flow show escape;
import 'shop_flow_test.dart' show openShop, settle, shopTest, toastText;

/// Steps [seconds] in 50 ms chunks, mounting what each chunk spawned;
/// [onStep] sees every frame (e.g. the pill's number).
Future<void> run(
  FlappySpikesGame game,
  double seconds, {
  void Function()? onStep,
}) async {
  for (var t = 0.0; t < seconds - 1e-9; t += .05) {
    stepGame(game, .05);
    await flushAndMount(game);
    onStep?.call();
  }
}

/// Steps until [sound] played (at most 1 s).
Future<void> untilSound(
  FlappySpikesGame game,
  List<Sfx> sounds,
  Sfx sound,
) async {
  for (var i = 0; i < 20 && !sounds.contains(sound); i++) {
    await run(game, .05);
  }
  expect(sounds, contains(sound));
}

Iterable<String> texts(Component c) =>
    c.descendants().whereType<MenuText>().map((t) => t.text);

Iterable<String> paragraphs(Component c) =>
    c.descendants().whereType<MenuParagraph>().map((t) => t.text);

void main() {
  group('Coin-pack celebration (PRD-home-v3 §5)', () {
    shopTest(
      '17 000 pack from the Shop: coins burst from its stack, count-up, '
      'payoff sounds, no toast',
      prefs: const {'coins': 100},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        game.coinFlyRandom = math.Random(1);
        final stack = shop.packs[2].artRect!;
        shop.packs[2].onPressed();
        await settle(game);
        expect(game.menu.wallet.balance, 17100);
        final reward = game.coinReward!;
        expect(reward.amount, 17000);
        expect(reward.from, stack);
        expect(reward.coins, 12);
        // The pill waits for the coins.
        expect(game.coinPill.shownBalance, 100);
        var maxShown = 0;
        await run(
          game,
          3.5,
          onStep: () =>
              maxShown = math.max(maxShown, game.coinPill.shownBalance),
        );
        expect(maxShown, 17100, reason: 'never counts past the balance');
        expect(game.coinPill.shownBalance, 17100);
        expect(sounds.where((s) => s == Sfx.bnCoin), hasLength(12));
        expect(sounds, contains(Sfx.skTick));
        expect(sounds, contains(Sfx.skBuyEpic));
        expect(sounds.last, Sfx.skProgress);
        expect(toastText(game), isNot(contains('coins')));
        expect(game.purchaseResultPopup, isNull);
      },
    );

    shopTest(
      'a late pack callback off the Shop plays from the screen centre',
      verify: (game, spy, ads, iap, tester) async {
        // Bought on home (e.g. the store answered after the player left).
        unawaited(game.purchases.buy(IapProduct.coins1000));
        await settle(game);
        final reward = game.coinReward!;
        expect(reward.from.center, Offset(160, game.viewHeight / 2));
        await run(game, 2.5);
        expect(game.coinPill.shownBalance, 1000);
      },
    );
  });

  group('Purchase result popup (PRD-home-v3 §6)', () {
    shopTest(
      'FAILED: texts, sk_nocoins, iap_error kept, ✕ closes with sk_close',
      iapMode: FakeIapMode.fail,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        shop.packs[0].onPressed();
        await settle(game);
        final popup = game.purchaseResultPopup!;
        expect(popup.problem, PurchaseProblem.failed);
        expect(sounds, contains(Sfx.skNoCoins));
        expect(texts(popup), containsAll(['PURCHASE FAILED', 'OK']));
        expect(paragraphs(popup), [
          'Your purchase could not be completed.',
          'You have not been charged. Please try again later.',
        ]);
        expect(spy.last('iap_error'), {
          'product': 'coins_1000',
          'reason': 'Fake error',
          'code': 'fake',
        });
        expect(spy.last('purchase_result_popup'), {
          'product': 'coins_1000',
          'outcome': 'failed',
          'code': 'fake',
        });
        // P1 geometry: 280 pt card centred, 38 pt ✕ top-right.
        expect(popup.card.width, 280);
        expect(popup.card.x, 20);
        expect(
          popup.card.y + popup.card.height / 2,
          closeTo(game.viewHeight / 2, 1),
        );
        expect(popup.closeButton.toRect(), const Rect.fromLTWH(242, 0, 38, 38));
        expect(popup.okButton.width, 248);
        expect(popup.okButton.height, 50);
        // Pop-in .82 -> 1.04 -> 1 and the badge spinning in.
        await run(game, .1);
        expect(popup.cardPose.scale, greaterThan(.82));
        await run(game, .5);
        expect(popup.cardPose.scale, 1);
        expect(popup.badgeScale, 1);
        // The balance and the buttons are unchanged.
        expect(game.menu.wallet.balance, 0);
        expect(shop.packs[0].tappable, isTrue);
        sounds.clear();
        popup.closeButton.onPressed();
        await flushAndMount(game);
        expect(game.purchaseResultPopup, isNull);
        expect(sounds, [Sfx.skClose]);
        await run(game, .2);
        expect(popup.isMounted, isFalse);
        expect(game.menuScene, MenuScene.shop);
      },
    );

    shopTest(
      'CANCELLED always shows (user back-out); OK, dim and Esc close it',
      iapMode: FakeIapMode.cancel,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        Future<void> buy() async {
          shop.packs[1].onPressed();
          await settle(game);
        }

        await buy();
        var popup = game.purchaseResultPopup!;
        expect(texts(popup), contains('PURCHASE CANCELLED'));
        expect(paragraphs(popup), [
          'The purchase was cancelled.',
          'You have not been charged.',
        ]);
        expect(spy.last('purchase_result_popup'), {
          'product': 'coins_10000',
          'outcome': 'cancelled',
        });
        expect(spy.names, isNot(contains('iap_error')));
        popup.okButton.onPressed();
        await run(game, .2);
        expect(game.purchaseResultPopup, isNull);

        await buy();
        popup = game.purchaseResultPopup!;
        popup.onTapUp(
          TapUpEvent(1, game, TapUpDetails(kind: PointerDeviceKind.touch)),
        ); // the dim
        await run(game, .2);
        expect(game.purchaseResultPopup, isNull);

        await buy();
        expect(game.purchaseResultPopup, isNotNull);
        game.onKeyEvent(shop_flow.escape(), {});
        await run(game, .2);
        expect(game.purchaseResultPopup, isNull);
        expect(game.menuScene, MenuScene.shop, reason: 'Esc only closed it');
        expect(spy.count('purchase_result_popup'), 3);
      },
    );

    shopTest(
      'No ads cancelled from the home tile shows the popup too',
      iapMode: FakeIapMode.cancel,
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.noAdsTile.onPressed();
        await settle(game);
        expect(game.purchaseResultPopup!.problem, PurchaseProblem.cancelled);
        expect(spy.last('purchase_result_popup'), {
          'product': 'no_ads',
          'outcome': 'cancelled',
        });
        expect(game.noAdsCelebration, isNull);
      },
    );

    shopTest(
      'pending: no popup (it completes later)',
      iapMode: FakeIapMode.pending,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.packs[0].onPressed();
        await settle(game);
        expect(game.purchaseResultPopup, isNull);
        expect(toastText(game), 'Purchase pending…');
        expect(spy.names, isNot(contains('purchase_result_popup')));
      },
    );
  });

  group('No-ads celebration (PRD-home-v3 §7)', () {
    shopTest(
      'fresh purchase from the Shop: jingle, flash, shake, confetti; CLAIM '
      'counts the bonus once; banner flips, then GET loses its icon',
      prefs: const {'coins': 250},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        game.coinFlyRandom = math.Random(2);
        shop.banner.onPressed();
        await settle(game);
        final popup = game.noAdsCelebration!;
        expect(sounds, contains(Sfx.noadsUnlock));
        expect(spy.last('noads_celebration_shown'), {'source': 'shop_banner'});
        expect(game.world.children.query<ScreenFlash>(), hasLength(1));
        expect(game.world.children.query<ScreenShake>(), hasLength(1));
        // Texts (§7).
        expect(
          texts(popup),
          containsAll([
            "YOU'RE AD-FREE!",
            'No more forced ads.',
            '+1 000 BONUS COINS',
            'CLAIM',
            '+1 000',
          ]),
        );
        expect(paragraphs(popup), ['Thanks for supporting Flappy Spikes!']);
        // Flag and bonus are granted at once; the looks and the pill wait.
        expect(game.menu.noAds, isTrue);
        expect(game.menu.wallet.balance, 1250);
        expect(game.coinPill.shownBalance, 250);
        expect(shop.banner.owned, isFalse);
        expect(shop.freeCoins.chipText, 'GET');
        // Swing-in, stamp at 0.33 s, confetti at 0.43 s.
        await run(game, .7);
        expect(popup.stamped, isTrue);
        expect(game.world.children.query<ConfettiBurst>(), hasLength(2));
        expect(game.world.children.query<ConfettiBurst>().map((c) => c.count), [
          90,
          90,
        ]);
        expect(popup.cardPose.scale, 1);
        expect(game.camera.viewfinder.position, Vector2.zero());
        expect(game.coinPill.shownBalance, 250);

        sounds.clear();
        final claim = popup.claimRect;
        popup.claimButton.onPressed();
        await flushAndMount(game);
        expect(game.noAdsCelebration, isNull);
        expect(spy.count('noads_bonus_claimed'), 1);
        final reward = game.coinReward!;
        expect(reward.amount, 1000);
        expect(reward.from, claim);
        var maxShown = 0;
        await run(
          game,
          2.9,
          onStep: () =>
              maxShown = math.max(maxShown, game.coinPill.shownBalance),
        );
        expect(maxShown, 1250, reason: 'the bonus is counted once');
        expect(sounds, contains(Sfx.skProgress));
        expect(sounds, isNot(contains(Sfx.noadsStamp)));
        // 0.25 s after the count-up: noads_stamp + banner flip.
        await untilSound(game, sounds, Sfx.noadsStamp);
        final flip = shop.banner.flipDriver;
        expect(flip, isNotNull);
        expect(shop.banner.owned, isFalse, reason: 'still flipping out');
        await run(game, .5);
        expect(shop.banner.owned, isTrue);
        expect(shop.banner.labelText, 'AD-FREE');
        expect(shop.banner.thanksLabel!.text, 'THANK YOU');
        expect(shop.banner.color, Config.noAdsOwnedFill);
        expect(shop.banner.dimmed, isFalse);
        expect(shop.banner.tappable, isFalse);
        // 0.7 s after the banner: GET's video icon shrinks, then CLAIM.
        await run(game, .5);
        expect(shop.freeCoins.chipText, 'CLAIM');
        expect(shop.freeCoins.videoIcon, isNull);
        expect(toastText(game), isNot(startsWith('Ads removed')));
      },
    );

    shopTest(
      'from the home tile: ✕ also collects; the tile flips to AD-FREE and '
      'the slot loses its video icon',
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final home = game.homeScreen!;
        home.noAdsTile.onPressed();
        await settle(game);
        expect(spy.last('noads_celebration_shown'), {'source': 'tile'});
        game.update(0);
        expect(home.noAdsTile.owned, isFalse);
        expect(home.slotButton.showsVideo, isTrue);
        await run(game, .6);
        game.noAdsCelebration!.closeButton.onPressed();
        await flushAndMount(game);
        expect(game.noAdsCelebration, isNull);
        expect(sounds, contains(Sfx.skClose));
        expect(game.coinReward, isNotNull, reason: 'the bonus is never lost');
        await run(game, 2.9);
        await untilSound(game, sounds, Sfx.noadsStamp);
        expect(home.noAdsTile.flipDriver, isNotNull);
        await run(game, .6);
        expect(home.noAdsTile.owned, isTrue);
        expect(home.noAdsTile.label.text, 'AD-FREE');
        expect(home.noAdsTile.color, Config.noAdsOwnedFill);
        expect(home.slotButton.showsVideo, isFalse);
        expect(game.coinPill.shownBalance, 1000);
      },
    );

    shopTest(
      'from the launch popup: Esc collects; the popup closes for the '
      'celebration',
      verify: (game, spy, ads, iap, tester) async {
        game.openNoAdsPopup();
        await flushAndMount(game);
        game.noAdsPopup!.priceButton.onPressed();
        await settle(game);
        expect(game.noAdsPopup, isNull);
        expect(spy.last('noads_celebration_shown'), {'source': 'popup'});
        game.onKeyEvent(shop_flow.escape(), {});
        await flushAndMount(game);
        expect(game.noAdsCelebration, isNull);
        expect(spy.count('noads_bonus_claimed'), 1);
        expect(game.menuScene, MenuScene.home);
      },
    );

    shopTest(
      'never on restore or a store re-delivery',
      verify: (game, spy, ads, iap, tester) async {
        // A fresh purchase (started in this session) celebrates once.
        unawaited(game.purchases.buy(IapProduct.noAds));
        await settle(game);
        expect(game.noAdsCelebration, isNotNull);
        game.handleBack();
        await run(game, 4);
        expect(spy.count('noads_celebration_shown'), 1);
        // Owned on "another device": restore brings it back silently.
        await game.menu.setNoAds(false);
        await game.restorePurchases();
        await settle(game);
        expect(game.menu.noAds, isTrue);
        expect(game.noAdsCelebration, isNull);
        expect(toastText(game), 'Purchases restored');
        // Re-delivery of the owned purchase (e.g. at launch).
        unawaited(iap.buy(IapProduct.noAds));
        await settle(game);
        expect(game.noAdsCelebration, isNull);
        expect(spy.count('noads_celebration_shown'), 1);
        expect(game.menu.wallet.balance, 1000);
        // Owners see the owned looks straight away.
        game.update(0);
        expect(game.homeScreen!.noAdsTile.owned, isTrue);
      },
    );

    shopTest(
      'a purchased No ads not started this session only restores ownership',
      verify: (game, spy, ads, iap, tester) async {
        // An old receipt replayed as `purchased` (reinstall): no buy was
        // started in this session.
        unawaited(iap.buy(IapProduct.noAds));
        await settle(game);
        await run(game, 1);
        expect(game.menu.noAds, isTrue);
        expect(game.noAdsCelebration, isNull);
        expect(game.queuedPopups, 0);
        expect(game.menu.wallet.balance, 0, reason: 'no fresh bonus');
        expect(game.coinPill.reserved, 0);
        expect(spy.count('noads_celebration_shown'), 0);
        game.update(0);
        expect(game.homeScreen!.noAdsTile.owned, isTrue);
      },
    );

    shopTest(
      'a running LEVEL UP count never includes the reserved No-ads bonus',
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.noAdsTile.onPressed();
        await settle(game);
        expect(game.noAdsCelebration, isNotNull);
        expect(game.menu.wallet.balance, 1000);
        expect(game.coinPill.reserved, 1000);
        // A second reward counting meanwhile counts only its own coins.
        final reward = game.playCoinReward(
          CoinRewardAnimation.levelReward(50, 1),
        );
        await game.menu.wallet.add(50, CoinSource.levelReward);
        await run(game, 4);
        expect(reward.finished, isTrue);
        expect(game.coinPill.shownBalance, 50);
        game.noAdsCelebration!.claimButton.onPressed();
        await run(game, 5);
        expect(game.coinPill.reserved, 0);
        expect(game.coinPill.shownBalance, 1050);
      },
    );

    shopTest(
      'reduce motion: no flash, shake or confetti; no swing; still claims',
      verify: (game, spy, ads, iap, tester) async {
        game.reduceMotionOverride = true;
        game.homeScreen!.noAdsTile.onPressed();
        await settle(game);
        final popup = game.noAdsCelebration!;
        await run(game, .6);
        expect(game.world.children.query<ScreenFlash>(), isEmpty);
        expect(game.world.children.query<ScreenShake>(), isEmpty);
        expect(game.world.children.query<ConfettiBurst>(), isEmpty);
        expect(popup.cardPose.scale, 1);
        expect(popup.stamped, isTrue);
        popup.claimButton.onPressed();
        await run(game, 4);
        expect(game.coinPill.shownBalance, 1000);
        expect(game.homeScreen!.noAdsTile.owned, isTrue);
      },
    );

    shopTest(
      'P1 card: 280 pt, 170 pt header, centred',
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.noAdsTile.onPressed();
        await settle(game);
        await run(game, .5);
        final popup = game.noAdsCelebration!;
        expect(popup, isA<NoAdsCelebration>());
        expect(popup.card.x, 20);
        expect(popup.card.width, 280);
        expect(
          popup.card.y + popup.card.height / 2,
          closeTo(game.viewHeight / 2, 1),
        );
        expect(popup.closeButton.toRect(), const Rect.fromLTWH(242, 0, 38, 38));
        expect(popup.claimButton.height, Config.noAdsCelebrationClaimHeight);
        expect(popup.claimButton.width, 248);
        expect(
          popup.claimButton.y + popup.claimButton.height + 16,
          popup.card.height,
        );
      },
    );
  });
}
