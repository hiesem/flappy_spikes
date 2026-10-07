// S2-71: localized store prices always fit their boxes (pack price buttons,
// the Remove-ads price chip, the No-ads popup price button).
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'e2e/menu_v4_qa_helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;
import 'services/store_iap_service_test.dart' show FakeStore;
import 'shop_flow_test.dart' show openShop;

class _PriceStore extends FakeStore {
  _PriceStore(this.price);

  final String price;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          for (final id in ids)
            ProductDetails(
              id: id,
              title: id,
              description: id,
              price: price,
              rawPrice: 1,
              currencyCode: 'XXX',
            ),
        ],
        notFoundIDs: const [],
      );
}

void main() {
  setUpAll(loadFonts);

  const prices = ['Rp 1.599.000,00', '₫2.079.000', 'CHF 72.00', r'$3.49'];
  for (final height in [568.0, 711.0]) {
    for (final (i, price) in prices.indexed) {
      v4Journey(
        '($height) "$price" fits packs, banner chip and popup button',
        height: height,
        eligible: true,
        iap: StoreIapService(store: _PriceStore(price)),
        (game, rig, tester) async {
          final popup = game.noAdsPopup!;
          expect(popup.priceLabel.text, price);
          expect(
            popup.priceLabel.width,
            lessThanOrEqualTo(popup.priceButton.width - 32),
          );
          expect(popup.priceLabel.position.x, greaterThanOrEqualTo(16));
          expect(
            popup.priceLabel.fontSize,
            greaterThanOrEqualTo(popup.priceLabel.baseFontSize * 0.6),
          );
          game.handleBack();
          await v4Settle(game, tester);

          final shop = await openShop(game);
          if (i == 0) {
            await tester.runAsync(
              () => captureShot(game, 1.5, 's2_71_fit_$height'),
            );
          }
          for (final pack in shop.packs) {
            final label = pack.priceLabel;
            expect(label.text, price);
            expect(label.width, lessThanOrEqualTo(pack.priceButton.width - 16));
            expect(label.position.x, greaterThanOrEqualTo(8));
            expect(
              label.fontSize,
              greaterThanOrEqualTo(label.baseFontSize * 0.6),
            );
          }
          final banner = shop.banner;
          final chip = banner.priceChip!;
          expect(banner.priceLabel!.text, price);
          expect(
            chip.position.x,
            greaterThanOrEqualTo(
              banner.label!.position.x + banner.label!.width + 8,
            ),
            reason: 'the price chip must not cover REMOVE ADS',
          );
          expect(chip.position.x + chip.width, lessThanOrEqualTo(banner.width));
          final chipLabel = banner.priceLabel!;
          expect(chipLabel.position.x, greaterThanOrEqualTo(0));
          expect(
            chipLabel.position.x + chipLabel.width,
            lessThanOrEqualTo(chip.width),
          );
          expect(
            chipLabel.fontSize,
            greaterThanOrEqualTo(chipLabel.baseFontSize * 0.6 - 0.01),
          );
          expect(
            banner.label!.fontSize,
            greaterThanOrEqualTo(banner.label!.baseFontSize * 0.6 - 0.01),
          );
          if (price == r'$3.49') {
            expect(chipLabel.fontSize, chipLabel.baseFontSize);
            expect(shop.packs.first.priceLabel.fontSize, 20);
          }
        },
      );
    }
  }
}
