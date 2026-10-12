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
/// "Privacy Policy", clear of RESTORE PURCHASES and DELETE MY DATA at 568.
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
      expect(panel.privacyOptionsLink, isNull);
      expect(panel.privacyLink.position, Config.privacyLinkPositionFor(355.5));
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
        final options = panel.privacyOptionsLink!;
        expect(options.label.text, 'Privacy options');
        final policy = panel.privacyLink.toRect();
        final opt = options.toRect();
        final restore = panel.restoreLink!.toRect();
        final delete = panel.deleteIcon!.toRect();
        expect(opt.top, greaterThan(panel.privacyLink.position.y));
        expect(opt.center.dy, greaterThan(policy.center.dy));
        expect(opt.bottom, lessThanOrEqualTo(restore.top));
        // The glyphs never overlap (the tap boxes may touch).
        final optText = options.label.toAbsoluteRect();
        final policyText = panel.privacyLink.label.toAbsoluteRect();
        expect(optText.top, greaterThan(policyText.bottom));
        expect(optText.bottom, lessThan(restore.top + 6));
        expect(policyText.top, greaterThan(delete.bottom));
        // Clear of the bottom spike strip.
        expect(restore.bottom, lessThanOrEqualTo(h - Config.spikeHeight + 1));
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
