import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/delete_data_popup.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/app_info.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.3 §20 the new Settings screen (design/settings_v23/
/// settings_final.html): layout at 568 / 711 with and without Privacy
/// options, the off states, the three tiles, the 8 volume bars, the rows
/// and their links (§20.3), the footer version. Shots land in
/// build/menu_shots/p23_s20_*.png for comparison with the approved page.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  // Every link the game asked to open, with its launch mode.
  late List<(Uri, LaunchMode)> opened;
  late AnalyticsSpy spy;

  FlappySpikesGame make({
    double h = 711,
    Map<String, Object> prefs = const {},
    bool options = false,
    AppInfo info = const FixedAppInfo(AppVersion('2.3.0', '10')),
  }) {
    opened = [];
    spy = AnalyticsSpy();
    SettingsPanel.debugResetMusicMemory();
    final g = createRunTestGame(
      prefs: prefs,
      worldHeight: h,
      services: spy,
      monetization: Monetization(
        consent: FakeAdsConsent(privacyOptionsRequired: options),
      ),
    );
    g.urlOpener = (uri, mode) async => opened.add((uri, mode));
    g.appInfo = info;
    return g;
  }

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  Future<SettingsPanel> open(FlappySpikesGame g) async {
    g.openSettings();
    await flushAndMount(g);
    stepGame(g, .6);
    await flushAndMount(g);
    return g.world.children.query<SettingsPanel>().single;
  }

  /// Opens the screen the way the app does: the open's microtasks all run
  /// (the panel loads and an already-resolved version lands) before the
  /// next frame's game tick mounts the panel. [flushAndMount] would tick in
  /// between and hide that order.
  Future<SettingsPanel> openLikeTheApp(FlappySpikesGame g) async {
    g.openSettings();
    for (var i = 0; i < 30; i++) {
      await Future<void>.value();
    }
    g.update(0); // the next frame mounts the panel
    stepGame(g, .6);
    await flushAndMount(g);
    return g.world.children.query<SettingsPanel>().single;
  }

  Future<void> flushPrefs() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.value();
    }
  }

  // --- §20.5 layout goldens -------------------------------------------------

  for (final h in [568.0, 711.0]) {
    for (final options in [false, true]) {
      final name = 'p23_s20_settings_${h.toInt()}${options ? '_options' : ''}';
      FlameTester<FlappySpikesGame>(
        () => make(h: h, options: options),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§20.5 layout ($h, Privacy options ${options ? 'shown' : 'hidden'}) '
        'fits between the strips (WP-NAME: scrolled to its end)',
        setUp: boot,
        verify: (g, tester) async {
          final panel = await open(g);
          final l = panel.layout;
          expect(l.fits, isTrue);
          // Title, tiles, volume, cards, footer: top to bottom, no overlap.
          final tiles = panel.soundTile.toAbsoluteRect();
          final vol = panel.volumeBars.toAbsoluteRect();
          final game = panel.gameCard.toAbsoluteRect();
          final privacy = panel.privacyCard.toAbsoluteRect();
          expect(
            tiles.top,
            greaterThan(panel.titleText.toAbsoluteRect().bottom),
          );
          expect(vol.top, greaterThanOrEqualTo(tiles.bottom));
          expect(game.top, greaterThanOrEqualTo(vol.bottom));
          expect(privacy.top, greaterThanOrEqualTo(game.bottom));
          final footerTop = panel.creditText.toAbsoluteRect().top;
          expect(footerTop, greaterThanOrEqualTo(privacy.bottom));
          // WP-NAME the PLAYER card pushes the rows down: the body scrolls,
          // and scrolled to its end the footer clears the bottom spikes.
          final scroll = panel.scroll;
          expect(scroll.scrollable, isTrue);
          scroll.offset = scroll.maxOffset;
          expect(
            panel.versionText.toAbsoluteRect().bottom,
            lessThanOrEqualTo(h - Config.menuSpikeHeight + 1e-3),
          );
          scroll.offset = 0;
          // Three tiles in a row, equal width, 8 pt gaps, 292 pt body.
          final m = panel.musicTile.toAbsoluteRect();
          final r = panel.rumbleTile.toAbsoluteRect();
          expect(tiles.left, 14);
          expect(r.right, closeTo(306, 1e-6));
          expect(m.left - tiles.right, closeTo(8, 1e-6));
          expect(m.width, closeTo(tiles.width, 1e-6));
          expect(panel.privacyCard.rows, hasLength(options ? 3 : 2));
          expect(panel.privacyOptionsRow != null, options);
          if (h == 711) {
            // The page's own sizes: nothing shrinks at 711.
            expect(l.tileHeight, Config.settingsTileHeight);
            expect(l.rowHeight, Config.settingsRowHeight);
            expect(l.cardGap, Config.settingsCardGap);
            // WP-NAME + 99: the PLAYER caption (15 + 6), card (68), gap 10.
            expect(tiles.top, closeTo(135 + 99, 1e-3));
            expect(game.top, closeTo(325 + 99, 1e-3));
          } else {
            // §20.2 order: card gaps first, then rows, then tiles.
            expect(l.cardGap, lessThan(Config.settingsCardGap));
            expect(l.rowHeight, lessThanOrEqualTo(34));
            expect(l.rowHeight, greaterThanOrEqualTo(30));
          }
          await tester.runAsync(() => captureShot(g, 2, name));
        },
      );
    }
  }

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => make(
        h: h,
        prefs: const {'muteSound': true, 'musicVolume': 0.0, 'rumble': false},
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§20.5 off states ($h): sound off, music at 0 (the off stroke), rumble '
      'off — grey tiles with OFF tags',
      setUp: boot,
      verify: (g, tester) async {
        final panel = await open(g);
        for (final tile in [
          panel.soundTile,
          panel.musicTile,
          panel.rumbleTile,
        ]) {
          expect(tile.on, isFalse);
          expect(tile.tag.text, 'OFF');
        }
        expect(panel.volumeBars.level, 0);
        expect(panel.volumeBars.valueText.text, '0%');
        expect(panel.rumbleButton.on, isFalse);
        await tester.runAsync(
          () => captureShot(g, 2, 'p23_s20_settings_${h.toInt()}_off'),
        );
      },
    );
  }

  // --- §20.5 toggles ----------------------------------------------------------

  FlameTester<FlappySpikesGame>(
    () => make(prefs: const {'muteSound': false}),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§20.5 each tile flips its state, its tag and its stored value',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      // SOUND
      expect(panel.soundTile.tag.text, 'ON');
      panel.soundTile.onPressed();
      expect(g.sound.muted, isTrue);
      expect(panel.soundTile.on, isFalse);
      expect(panel.soundTile.tag.text, 'OFF');
      await flushPrefs();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('muteSound'), isTrue);
      panel.soundTile.onPressed();
      expect(panel.soundTile.tag.text, 'ON');
      // RUMBLE
      stepGame(g, .2);
      panel.rumbleTile.onPressed();
      expect(g.rumble.on, isFalse);
      expect(panel.rumbleTile.tag.text, 'OFF');
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rumble'), isFalse);
      stepGame(g, .2);
      panel.rumbleTile.onPressed();
      expect(panel.rumbleTile.tag.text, 'ON');
      expect(panel.rumbleButton.buzzing, isTrue, reason: 'on buzzes');
      // MUSIC
      expect(panel.musicTile.tag.text, 'ON');
      panel.musicTile.onPressed();
      expect(panel.musicTile.tag.text, 'OFF');
      expect(g.sound.musicVolume, 0);
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), 0);
      expect(g.state, GameState.start, reason: 'no tap leak');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(prefs: const {'musicVolume': 6 / 8}),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§20.5 the MUSIC tile mutes and restores the last level; from 0 with '
    'nothing remembered it uses 5 of 8',
    setUp: boot,
    verify: (g, tester) async {
      var panel = await open(g);
      expect(panel.volumeBars.level, 6);
      panel.musicTile.onPressed();
      expect(panel.volumeBars.level, 0);
      expect(g.storage.musicVolume, 0);
      panel.musicTile.onPressed();
      expect(panel.volumeBars.level, 6);
      expect(g.storage.musicVolume, 6 / 8);
      // Mute, leave, come back: still remembered this session.
      panel.musicTile.onPressed();
      g.closeSettings();
      stepGame(g, .6);
      await flushAndMount(g);
      g.openSettings();
      await flushAndMount(g);
      panel = g.world.children.query<SettingsPanel>().single;
      panel.musicTile.onPressed();
      expect(panel.volumeBars.level, 6);
      // Nothing remembered: 5 of 8.
      SettingsPanel.debugResetMusicMemory();
      panel.volumeBars.onLevel(0);
      expect(panel.volumeBars.level, 0);
      panel.musicTile.onPressed();
      expect(panel.volumeBars.level, 5);
      expect(g.storage.musicVolume, 5 / 8);
    },
  );

  // --- §20.5 volume bars ------------------------------------------------------

  final exact = FlameTester<FlappySpikesGame>(
    () => make(),
    pumpWidget: (gameWidget, tester) async {
      tester.view
        ..physicalSize = const Size(320, 711)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(gameWidget);
    },
  );

  exact.testGameWidget(
    '§20.5 a tap on bar n sets level n; a drag across sets each level in '
    'turn; a drag to the far left gives 0; stored = level / 8',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      final bars = panel.volumeBars;
      final origin = bars.absolutePosition.toOffset();
      Offset bar(int n) => Offset(
        origin.dx + bars.barRect(n - 1).center.dx,
        origin.dy + bars.barRect(7).center.dy,
      );

      for (final n in [1, 4, 8, 3]) {
        await tester.tapAt(bar(n));
        await tester.pump(const Duration(milliseconds: 100));
        expect(bars.level, n, reason: 'tap on bar $n');
        expect(g.storage.musicVolume, n / 8);
        expect(g.sound.musicVolume, n / 8, reason: 'music follows live');
        expect(bars.valueText.text, '${(n / 8 * 100).round()}%');
      }

      // Drag from bar 1 across to bar 8 in small steps: every level in
      // turn (each new level is recorded once, in order).
      final seen = <int>[];
      void look() {
        if (seen.isEmpty || seen.last != bars.level) seen.add(bars.level);
      }

      final start = bar(1);
      final end = bar(8);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 16));
      for (var x = start.dx; x <= end.dx; x += 8) {
        await gesture.moveTo(Offset(x, start.dy));
        await tester.pump(const Duration(milliseconds: 16));
        look();
      }
      await gesture.moveTo(end);
      await tester.pump(const Duration(milliseconds: 16));
      look();
      // ... and on to the far left (past the card): 0.
      await gesture.moveTo(Offset(origin.dx - 10, start.dy));
      await tester.pump(const Duration(milliseconds: 16));
      look();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, [1, 2, 3, 4, 5, 6, 7, 8, 0]);
      expect(g.storage.musicVolume, 0);
      expect(panel.musicTile.on, isFalse);
      await flushPrefs();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), 0);
      expect(g.state, GameState.start);
    },
  );

  for (final (stored, level) in [(0.25, 2), (0.3, 2), (0.44, 4), (0.9, 7)]) {
    FlameTester<FlappySpikesGame>(
      () => make(prefs: {'musicVolume': stored}),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§20.5 a 2.2 volume of $stored shows as level $level and stays '
      'stored untouched',
      setUp: boot,
      verify: (g, tester) async {
        final panel = await open(g);
        expect(panel.volumeBars.level, level);
        expect(SettingsPanel.levelFor(stored), level);
        expect(g.storage.musicVolume, stored);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('musicVolume'), stored);
      },
    );
  }

  // --- §20.5 rows and links ---------------------------------------------------

  test('§20.3 the four URLs (and the music credit, WP-SET)', () {
    expect(Config.supportUrl, 'https://flappyspikes.com/support');
    expect(Config.privacyPolicyUrl, 'https://flappyspikes.com/privacy');
    expect(Config.deleteDataUrl, 'https://flappyspikes.com/delete-data');
    expect(Config.siteUrl, 'https://flappyspikes.com');
    expect(Config.redeemCodeUrl, 'https://play.google.com/redeem?code=');
    expect(Config.musicCreditUrl, 'https://soundcloud.com/electrobaptist');
  });

  // WP-SET (owner 2026-10-19): the name opens the artist's page in the
  // in-app browser, with a tap box of at least 44 pt that never climbs over
  // the cards above.
  for (final h in [568.0, 711.0]) {
    final tapHarness = FlameTester<FlappySpikesGame>(
      () => make(h: h),
      pumpWidget: (gameWidget, tester) async {
        tester.view
          ..physicalSize = Size(320, h)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(gameWidget);
      },
    );
    tapHarness.testGameWidget(
      'WP-SET ($h): a tap on the name opens SoundCloud in the in-app browser; '
      'a tap on "Melody by" opens nothing; the tap box is 44 pt tall and '
      'stays clear of the cards',
      setUp: boot,
      verify: (g, tester) async {
        final panel = await open(g);
        panel.scroll.offset = panel.scroll.maxOffset; // the footer's place
        stepGame(g, .1);
        await flushAndMount(g);

        final link = panel.creditLink.toAbsoluteRect();
        final name = panel.creditText.toAbsoluteRect();
        final lead = panel.creditLead.toAbsoluteRect();
        final privacy = panel.privacyCard.toAbsoluteRect();
        expect(link.left, closeTo(name.left, 1e-6));
        expect(link.width, closeTo(name.width, 1e-6));
        expect(link.contains(name.center), isTrue);
        expect(
          link.height,
          greaterThanOrEqualTo(Config.settingsCreditHitHeight),
        );
        expect(link.top, greaterThanOrEqualTo(privacy.bottom - 1e-6));
        expect(
          link.bottom,
          lessThanOrEqualTo(
            h - Config.menuSpikeHeight + Config.menuSpikeToothDepth,
          ),
        );

        await tester.tapAt(lead.center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(opened, isEmpty, reason: '"Melody by" is not the link');

        await tester.tapAt(link.center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(opened, [
          (
            Uri.parse('https://soundcloud.com/electrobaptist'),
            LaunchMode.inAppBrowserView,
          ),
        ]);
        expect(g.state, GameState.start, reason: 'no tap leak');
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => make(options: true),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§20.5 each row calls its callback; the links are those of §20.3; the '
    'GAME card has no Rate row',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      expect(panel.gameCard.rows.map((r) => r.labelText.text), [
        'SUPPORT',
        'RESTORE PURCHASES',
        'REDEEM CODE',
      ]);
      expect(panel.privacyCard.rows.map((r) => r.labelText.text), [
        'PRIVACY POLICY',
        'PRIVACY OPTIONS',
        'DELETE MY DATA',
      ]);
      expect(
        panel.rows.where((r) => r.labelText.text.contains('RATE')),
        isEmpty,
      );

      panel.supportRow!.onPressed();
      panel.privacyRow.onPressed();
      panel.redeemRow!.onPressed();
      await flushAndMount(g);
      // Web pages open in the in-app browser (owner 2026-10-19); the redeem
      // link stays in the Play Store app (PRD-2.3 §22.2).
      expect(opened, [
        (
          Uri.parse('https://flappyspikes.com/support'),
          LaunchMode.inAppBrowserView,
        ),
        (
          Uri.parse('https://flappyspikes.com/privacy'),
          LaunchMode.inAppBrowserView,
        ),
        (
          Uri.parse('https://play.google.com/redeem?code='),
          LaunchMode.externalApplication,
        ),
      ]);
      expect(spy.events.map((e) => e.$1), contains('redeem_code_opened'));

      // Restore: the spinner replaces the chevron while it runs.
      panel.restoreRow!.onPressed();
      await flushAndMount(g);
      expect(g.purchases.restoring, isTrue);
      g.update(0);
      expect(panel.restoreRow!.busy, isTrue);
      stepGame(g, Config.restoreTimeout + .1);
      await flushAndMount(g);
      expect(panel.restoreRow!.busy, isFalse);

      // Privacy options: the consent form.
      final consent = g.monetization.consent as FakeAdsConsent;
      panel.privacyOptionsRow!.onPressed();
      await flushAndMount(g);
      expect(consent.privacyFormsShown, 1);

      // Delete my data: the confirm dialog, naming the website's page.
      panel.deleteRow!.onPressed();
      await flushAndMount(g);
      final popup = g.deleteDataPopup!;
      expect(popup.step, DeleteDataStep.confirm);
      expect(
        popup.webText!.text,
        'You can also request this at flappyspikes.com/delete-data.',
      );
      stepGame(g, .4);
      await flushAndMount(g);
      await tester.runAsync(
        () => captureShot(g, 2, 'p23_s20_delete_confirm_711'),
      );
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(h: 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§20.5 Privacy options shows only when privacyOptionsShown',
    setUp: boot,
    verify: (g, tester) async {
      expect(g.privacyOptionsShown, isFalse);
      final panel = await open(g);
      expect(panel.privacyOptionsRow, isNull);
      expect(panel.privacyCard.rows.map((r) => r.labelText.text), [
        'PRIVACY POLICY',
        'DELETE MY DATA',
      ]);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§20.5 the footer shows the music credit and the version from '
    'package_info_plus (faked)',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      expect(panel.creditLead.text, 'Melody by ');
      expect(panel.creditText.text, 'ElectroBaptist');
      expect(panel.versionText.text, 'Flappy Spikes v2.3.0 (10)');
      expect(
        const AppVersion('2.3.0', '10').footer,
        'Flappy Spikes v2.3.0 (10)',
      );
    },
  );

  // --- WP-SET the footer version ----------------------------------------------

  // Bug (2.4.0 (36) report): the version was dropped on reopen. PluginAppInfo
  // hands back one cached, already-resolved future; the panel's load ran
  // before the frame that mounts it, and `isMounted` then skipped the text.
  FlameTester<FlappySpikesGame>(
    () => make(h: 568, info: _CachedAppInfo(const AppVersion('2.4.0', '36'))),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-SET the footer shows the version on every open, also when the '
    'version was already resolved before the panel opened',
    setUp: boot,
    verify: (g, tester) async {
      final first = await openLikeTheApp(g);
      expect(
        first.versionText.text,
        'Flappy Spikes v2.4.0 (36)',
        reason: '1st',
      );
      g.closeSettings();
      stepGame(g, .6);
      await flushAndMount(g);
      final second = await openLikeTheApp(g);
      expect(
        second.versionText.text,
        'Flappy Spikes v2.4.0 (36)',
        reason: '2nd',
      );
      // The footer sits under the cards: scroll to its end for the shot.
      second.scroll.offset = second.scroll.maxOffset;
      stepGame(g, .1);
      await flushAndMount(g);
      await tester.runAsync(
        () => captureShot(g, 2, 'p23_s20_footer_568_reopen'),
      );
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(h: 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-SET the footer version also arrives when the read finishes after '
    'the panel is mounted (first read of the session)',
    setUp: boot,
    verify: (g, tester) async {
      final late = _LateAppInfo();
      g.appInfo = late;
      g.openSettings();
      for (var i = 0; i < 30; i++) {
        await Future<void>.value();
      }
      g.update(0); // mounted; the read is still in flight
      late.finish(const AppVersion('2.4.0', '36'));
      await flushAndMount(g);
      stepGame(g, .6);
      await flushAndMount(g);
      final panel = g.world.children.query<SettingsPanel>().single;
      expect(panel.versionText.text, 'Flappy Spikes v2.4.0 (36)');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§20.4 the same screen opens over a paused run (back returns to the '
    'pause card)',
    setUp: boot,
    verify: (g, tester) async {
      await startRun(g);
      stepGame(g, .2);
      g.pause();
      await flushAndMount(g);
      g.openRunSettings();
      await flushAndMount(g);
      stepGame(g, .4);
      await flushAndMount(g);
      final panel = g.world.children.query<SettingsPanel>().single;
      expect(panel.redeemRow, isNotNull);
      expect(panel.supportRow, isNotNull);
      g.closeSettings();
      stepGame(g, .4);
      await flushAndMount(g);
      expect(g.runSettingsOpen, isFalse);
      expect(g.state, GameState.paused);
    },
  );
}

/// PluginAppInfo after its first read: every call hands back the same,
/// already completed future.
class _CachedAppInfo extends AppInfo {
  _CachedAppInfo(AppVersion version) : _future = Future.value(version);

  final Future<AppVersion?> _future;

  @override
  Future<AppVersion?> load() => _future;
}

/// A read still in flight until [finish] (the first read of a session).
class _LateAppInfo extends AppInfo {
  final Completer<AppVersion?> _completer = Completer<AppVersion?>();

  @override
  Future<AppVersion?> load() => _completer.future;

  void finish(AppVersion version) => _completer.complete(version);
}
