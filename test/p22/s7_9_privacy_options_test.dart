import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §7.9 the "Privacy options" row in Settings (Google's EU consent
/// policy): shown only when the UMP privacy options are required, under
/// "Privacy policy" (PRD-2.3 §20.2: a row of the PRIVACY & DATA card).
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester(FakeAdsConsent consent, double h) =>
      FlameTester<FlappySpikesGame>(
        () {
          spy.events.clear();
          return createRunTestGame(
            services: spy,
            worldHeight: h,
            monetization: Monetization(consent: consent),
          );
        },
        gameSize: Vector2(320, h),
      );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  Future<SettingsPanel> open(FlappySpikesGame g) async {
    g.openSettings();
    await flushAndMount(g);
    stepGame(g, .5);
    await flushAndMount(g);
    return g.world.children.query<SettingsPanel>().single;
  }

  tester(FakeAdsConsent(), 711).testGameWidget(
    '§7.9 hidden when not required (also iOS / Linux: their consent never '
    'requires it); Privacy Policy keeps its place',
    setUp: boot,
    verify: (g, _) async {
      final panel = await open(g);
      expect(g.privacyOptionsShown, isFalse);
      // PRD-2.3 §20.2: the PRIVACY & DATA card has two rows.
      expect(panel.privacyOptionsRow, isNull);
      expect(panel.privacyCard.rows, hasLength(2));
    },
  );

  for (final h in [568.0, 711.0]) {
    final consent = FakeAdsConsent(privacyOptionsRequired: true)
      ..privacyFormResult = false;
    tester(consent, h).testGameWidget(
      '§7.9 ($h) required: "Privacy options" under Privacy Policy, no '
      'overlap with RESTORE PURCHASES / DELETE MY DATA; a tap opens the '
      'form (privacy_options_opened) and a withdrawal turns the banner off',
      setUp: boot,
      verify: (g, tester) async {
        final panel = await open(g);
        // PRD-2.3 §20.2: a row of the PRIVACY & DATA card, between
        // Privacy policy and Delete my data, inside the screen.
        final options = panel.privacyOptionsRow!;
        expect(options.labelText.text, 'PRIVACY OPTIONS');
        expect(panel.privacyCard.rows, [
          panel.privacyRow,
          options,
          panel.deleteRow,
        ]);
        expect(
          options.toAbsoluteRect().top,
          greaterThanOrEqualTo(panel.privacyRow.toAbsoluteRect().bottom),
        );
        // WP-NAME the body scrolls (PLAYER card on top): at its end the
        // card is inside the screen.
        panel.scroll.offset = panel.scroll.maxOffset;
        expect(
          panel.privacyCard.toAbsoluteRect().bottom,
          lessThanOrEqualTo(h - Config.spikeHeight),
        );
        await tester.runAsync(
          () => captureShot(g, 2, 'p22_s7_9_privacy_options_${h.toInt()}'),
        );

        await g.openPrivacyOptions();
        expect(consent.privacyFormsShown, 1);
        expect(
          spy.events.map((e) => e.$1),
          contains('privacy_options_opened'),
        );
        // Withdrawn: the next START has no banner.
        expect(g.monetization.consent.canRequestAds.value, isFalse);
        expect(g.monetization.banner.canShow, isFalse);
      },
    );
  }

  test('§7.9 the FakeAdsConsent default never requires the row', () {
    expect(FakeAdsConsent().privacyOptionsRequired, isFalse);
    expect(Monetization().consent.privacyOptionsRequired, isFalse);
  });
}
