import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/settings_player_card.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/app_info.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/custom_name.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;
import '../share/share_card_golden_test.dart' show loadCardFonts;
import '../run/shots/versus_shots_test.dart' as shots show rival;
import 'support/tablet.dart' show canvasFor, renderGame, worldHeightFor;

/// WP-NAME the PLAYER card in Settings (design A, edit in place): "You" by
/// default, the custom name once set; editing with the system keyboard
/// (a hidden EditableText overlay), ✓ / ✕ / back, the inline errors, the
/// server answer (accepted / refused / offline); the rows below move down
/// unchanged and the body scrolls when it does not fit. Evidence PNGs land
/// in $FS_EVIDENCE_DIR (default build/menu_shots).
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  await loadCardFonts();

  final outDir =
      Platform.environment['FS_EVIDENCE_DIR'] ?? 'build/menu_shots/name';

  Future<void> shot(FlappySpikesGame g, String name) async {
    const scale = 2.0;
    final size = Vector2(320 * scale, (g.viewHeight * scale).roundToDouble());
    g.onGameResize(size);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.x, size.y),
      ui.Paint()..color = g.backgroundColor(),
    );
    g.render(canvas);
    final image = await recorder.endRecording().toImage(
      size.x.toInt(),
      size.y.toInt(),
    );
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    final file = File('$outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  late FakeVersusService versus;

  FlappySpikesGame make({
    double h = 568,
    Map<String, Object> prefs = const {},
  }) {
    versus = FakeVersusService(
      profile: const VersusProfile(name: 'BraveParrot907'),
    );
    SettingsPanel.debugResetMusicMemory();
    final g = createRunTestGame(
      worldHeight: h,
      prefs: {
        'ownedItems': ['bird:owl'],
        'equippedItem.bird': 'owl',
        ...prefs,
      },
      versus: versus,
    );
    g.appInfo = const FixedAppInfo(AppVersion('2.4.0', '36'));
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

  Future<void> settle(FlappySpikesGame g) async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.value();
    }
    await flushAndMount(g);
  }

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => make(h: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'WP-NAME ($h) the PLAYER card is on top ("You"); the rows below keep '
      'their sizes and move down by the card; the body scrolls to the '
      'footer',
      setUp: boot,
      verify: (g, tester) async {
        final panel = await open(g);
        final card = panel.playerCard;
        expect(card.shownName, 'You');
        expect(card.editing, isFalse);
        final l = panel.layout;
        // The pre-card layout, unchanged (no extra shrinking for the card).
        final before = SettingsLayout.fit(
          viewHeight: h,
          gameRows: l.gameRows,
          privacyRows: l.privacyRows,
        );
        expect(l.tileHeight, before.tileHeight);
        expect(l.rowHeight, before.rowHeight);
        expect(l.cardGap, before.cardGap);
        final c = card.toAbsoluteRect();
        expect(c.left, closeTo(Config.settingsBodyLeft, 1e-4));
        expect(c.width, closeTo(Config.settingsBodyWidth, 1e-4));
        expect(c.height, closeTo(SettingsPlayerCard.cardHeight, 1e-4));
        expect(c.top, greaterThan(panel.titleText.toAbsoluteRect().bottom));
        final shift =
            SettingsPlayerCard.cardHeight +
            Config.settingsCaptionHeight +
            l.captionGap +
            Config.settingsCardGap;
        final tiles = panel.soundTile.toAbsoluteRect();
        expect(tiles.top, closeTo(l.tilesY + shift, 1e-3));
        expect(tiles.top, greaterThan(c.bottom));
        expect(tiles.height, closeTo(l.tileHeight, 1e-3));
        expect(
          panel.gameCard.toAbsoluteRect().top,
          closeTo(l.gameCardY + shift, 1e-6),
        );
        // Too tall for the screen: it scrolls, and at the end the footer
        // sits above the bottom spikes with DELETE MY DATA in view.
        expect(panel.scroll.scrollable, isTrue);
        await tester.runAsync(() => shot(g, 'name_settings_${h.toInt()}'));
        panel.scroll.offset = panel.scroll.maxOffset;
        await flushAndMount(g);
        final bottom = h - Config.menuSpikeHeight;
        expect(
          panel.versionText.toAbsoluteRect().bottom,
          lessThanOrEqualTo(bottom + 1e-3),
        );
        expect(
          panel.deleteRow!.toAbsoluteRect().bottom,
          lessThanOrEqualTo(bottom),
        );
        await tester.runAsync(
          () => shot(g, 'name_settings_${h.toInt()}_scrolled'),
        );
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => make(h: 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-NAME edit in place: keyboard overlay, inline errors, ✓ saves to '
    'the phone and the server, back / ✕ cancel, an empty name is "You"',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      final card = panel.playerCard;
      final tilesTop = panel.soundTile.toAbsoluteRect().top;
      card.tapTarget.onPressed();
      await flushAndMount(g);
      expect(card.editing, isTrue);
      expect(card.draft, '');
      expect(g.overlays.isActive(kPlayerNameOverlay), isTrue);
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      // The rows make room for the taller card and the hint, dimmed and
      // without taps.
      expect(panel.soundTile.toAbsoluteRect().top, greaterThan(tilesTop));
      expect(panel.rest.isBlocked(), isTrue);

      // Typing through the system keyboard reaches the card.
      await tester.enterText(find.byType(EditableText), 'Wise Owl');
      await tester.pump();
      expect(card.draft, 'Wise Owl');
      expect(card.error, CustomNameReason.chars);
      await tester.runAsync(() => shot(g, 'name_settings_568_error'));

      card.setDraft('Wi');
      await card.commit();
      expect(card.error, CustomNameReason.length);
      expect(card.editing, isTrue);
      expect(versus.sentNames, isEmpty, reason: 'format checked first');

      card.setDraft('WiseOwl');
      expect(card.error, isNull);
      stepGame(g, .1);
      await tester.runAsync(() => shot(g, 'name_settings_568_editing'));
      await card.commit();
      await settle(g);
      expect(versus.sentNames, ['WiseOwl']);
      expect(card.editing, isFalse);
      expect(g.overlays.isActive(kPlayerNameOverlay), isFalse);
      expect(g.storage.versusCustomName, 'WiseOwl');
      expect(g.storage.versusCustomNameSyncedFor('fake'), 'WiseOwl');
      expect(card.shownName, 'WiseOwl');
      expect(g.myVersusName, 'WiseOwl');
      expect(panel.soundTile.toAbsoluteRect().top, tilesTop);
      await tester.runAsync(() => shot(g, 'name_settings_568_custom'));

      // ✕ and back cancel: nothing changes.
      card.startEditing();
      card.setDraft('Other1');
      card.cancel.onPressed();
      expect(card.editing, isFalse);
      card.startEditing();
      expect(card.draft, 'WiseOwl');
      card.setDraft('Other2');
      expect(g.handleSystemBack(), isTrue);
      expect(card.editing, isFalse);
      expect(g.storage.versusCustomName, 'WiseOwl');
      expect(g.menuScene, isNot(MenuScene.home), reason: 'Settings stays');

      // An empty name clears it: "You" again (opponents: the nickname).
      card.startEditing();
      card.setDraft('');
      await card.commit();
      await settle(g);
      expect(versus.sentNames.last, '');
      expect(g.storage.versusCustomName, '');
      expect(card.shownName, 'You');
      expect(g.myVersusName, 'You');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(h: 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-NAME a name the server refuses shows its reason and is not saved; '
    'offline it is kept on the phone (to be sent later)',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      final card = panel.playerCard;
      versus.nameAnswer = const CustomNameRefused(CustomNameReason.blocked);
      card.startEditing();
      card.setDraft('Badword1');
      await card.commit();
      await settle(g);
      expect(card.editing, isTrue);
      expect(card.error, CustomNameReason.blocked);
      expect(g.storage.versusCustomName, '');
      await tester.runAsync(() => shot(g, 'name_settings_568_refused'));

      // SAVING… while the server answers.
      final gate = Completer<void>();
      versus
        ..nameAnswer = const CustomNameOffline()
        ..nameDelay = gate.future;
      card.setDraft('Flyer99');
      final saving = card.commit();
      await Future<void>.value();
      expect(card.saving, isTrue);
      gate.complete();
      await saving;
      await settle(g);
      expect(card.editing, isFalse);
      expect(g.storage.versusCustomName, 'Flyer99');
      expect(g.storage.versusCustomNameSync, '', reason: 'not confirmed');
      expect(g.myVersusName, 'Flyer99');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(h: 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '2.4.0 (38) while the server answers: frames keep coming, the ✓ / ✕ '
    'make way for the spinner, the field is read-only and taps / back do '
    'nothing; a refusal restores the buttons and the field with the reason; '
    'an accepted name closes the card',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      final card = panel.playerCard;
      final evidence =
          Platform.environment['FS_NAME_EVIDENCE'] ?? '$outDir/saving';
      Future<void> grab(String name) => tester.runAsync(() async {
        await shot(g, name);
        final f = File('$outDir/$name.png');
        await Directory(evidence).create(recursive: true);
        await f.copy('$evidence/$name.png');
      });
      bool readOnly() =>
          tester.widget<EditableText>(find.byType(EditableText)).readOnly;

      card.startEditing();
      await flushAndMount(g);
      await tester.pump();
      card.setDraft('Flyer99');
      stepGame(g, .1);
      expect(card.confirm.isMounted, isTrue);
      expect(card.cancel.isMounted, isTrue);
      expect(readOnly(), isFalse);
      await grab('name_save_1_editing');

      // A slow server: the ✓ waits.
      var gate = Completer<void>();
      versus
        ..nameAnswer = const CustomNameRefused(CustomNameReason.blocked)
        ..nameDelay = gate.future;
      card.confirm.onPressed();
      await Future<void>.value();
      await flushAndMount(g);
      expect(card.saving, isTrue);
      expect(card.confirm.isMounted, isFalse, reason: '✓ hidden');
      expect(card.cancel.isMounted, isFalse, reason: '✕ hidden');
      await tester.pump();
      expect(readOnly(), isTrue, reason: 'no typing while saving');

      // The game loop keeps running: real frames (the GameWidget's ticker)
      // advance the spinner while the save is pending.
      final spin0 = card.spin;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(card.saving, isTrue);
      expect(card.spin, greaterThan(spin0 + .2));

      // Taps, typing and back change nothing while saving.
      card.fieldTarget.onPressed();
      card.cancelEditing();
      expect(g.handleSystemBack(), isTrue);
      card.setDraft('Other');
      expect(card.editing, isTrue);
      expect(card.saving, isTrue);
      expect(card.draft, 'Flyer99');
      stepGame(g, .25);
      await grab('name_save_2_saving');

      // Refused: the buttons, the field and the keyboard come back with the
      // reason; nothing is saved.
      gate.complete();
      await settle(g);
      await tester.pump();
      expect(card.saving, isFalse);
      expect(card.editing, isTrue);
      expect(card.error, CustomNameReason.blocked);
      expect(card.confirm.isMounted, isTrue);
      expect(card.cancel.isMounted, isTrue);
      expect(readOnly(), isFalse);
      expect(g.storage.versusCustomName, '');
      await grab('name_save_3_refused');

      // Accepted after a wait: the card closes with the name, as before.
      gate = Completer<void>();
      versus
        ..nameAnswer = null
        ..nameDelay = gate.future;
      card.setDraft('Flyer99');
      final saving = card.commit();
      await Future<void>.value();
      expect(card.saving, isTrue);
      gate.complete();
      await saving;
      await settle(g);
      expect(card.editing, isFalse);
      expect(card.saving, isFalse);
      expect(card.pencil.isMounted, isTrue);
      expect(g.overlays.isActive(kPlayerNameOverlay), isFalse);
      expect(g.storage.versusCustomName, 'Flyer99');
      expect(card.shownName, 'Flyer99');
      await grab('name_save_4_saved');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(h: 568, prefs: {'versusCustomNameError': 'blocked'}),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-NAME a name refused after an offline save is reported once in the '
    'card',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      expect(panel.playerCard.error, CustomNameReason.blocked);
      expect(panel.playerCard.shownName, 'You');
      await settle(g);
      expect(g.storage.versusCustomNameError, '');
    },
  );

  // Tablets (3:4) play on a 568 pt high playfield, menus a centred column.
  final tab = canvasFor(3, 4);
  FlameTester<FlappySpikesGame>(
    () => make(h: worldHeightFor(3, 4)),
    gameSize: tab,
  ).testGameWidget(
    'WP-NAME (tablet 3:4) the card sits in the centred column, the body '
    'scrolls to the footer and the name can be edited',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      expect(g.viewHeight, 568);
      final card = panel.playerCard;
      final c = card.toAbsoluteRect();
      final tiles = panel.soundTile.toAbsoluteRect();
      expect(c.left, closeTo(tiles.left, 1e-3));
      expect(c.right, closeTo(panel.rumbleTile.toAbsoluteRect().right, 1e-3));
      expect(panel.scroll.scrollable, isTrue);
      Future<void> save(String name) => tester.runAsync(() async {
        final img = await renderGame(g, tab);
        final bytes = (await img.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        img.dispose();
        final file = File('$outDir/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      });
      await save('name_settings_tablet_3x4');
      card.startEditing();
      card.setDraft('WiseOwl7');
      await flushAndMount(g);
      await save('name_settings_tablet_3x4_editing');
      await card.commit();
      await settle(g);
      expect(g.storage.versusCustomName, 'WiseOwl7');
    },
  );

  // A versus screen with the own name "You" (evidence).
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: 568,
      prefs: {
        'bestScore': 640,
        'playerLevel': 6,
        'ownedItems': ['bird:owl'],
        'equippedItem.bird': 'owl',
      },
      versus: FakeVersusService(
        pool: [
          shots.rival(
            name: 'DuckTurbo111',
            look: const Look(bird: 'sky', hat: 'cap'),
          ),
        ],
        profile: const VersusProfile(name: 'SwiftKiwi482'),
      ),
    ),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-NAME the VS intro shows "You" for the own plate, the opponent\'s '
    'name for theirs',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      g.onScreenTap();
      await flushAndMount(g);
      final intro = g.versusIntro!;
      for (var i = 0; i < 600 && intro.time < intro.lockAt + .8; i++) {
        g.update(1 / 60);
        await Future<void>.value();
      }
      expect(intro.youPlate.name, 'You');
      expect(intro.oppPlate.name, 'DuckTurbo111');
      await tester.runAsync(() => shot(g, 'name_vs_intro_568'));
      await finishVersusIntro(g);
      for (var i = 0; i < 40; i++) {
        g.update(1 / 60);
      }
      await flushAndMount(g);
      expect(g.runHud!.versus!.you.name, 'You');
      await tester.runAsync(() => shot(g, 'name_vs_hud_568'));
    },
  );
}
