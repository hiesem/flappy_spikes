import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/paints.dart' show layerPaint;
import '../game/sound.dart' show Sfx;
import '../game/tintable.dart';
import 'home/menu_primitives.dart';
import 'menu_screen_chrome.dart' show MenuScrollArea, MenuScrollTapGate;
import '../versus/custom_name.dart' show CustomNameReason;
import 'settings_player_card.dart';
import 'skins/celebration.dart' show keyframe;

/// Images the Settings screen draws (PRD-2.3 §20.1: game assets only).
const List<String> kSettingsImages = [
  'soundbutton.png',
  'mutebutton.png',
  'music_note.png',
  'menu/back.png',
];

/// The Settings screen (PRD-2.3 §20, approved design
/// `design/settings_v23/settings_final.html`), opened from the home gear or
/// the pause screen. Top to bottom:
/// - the back button (the game's shared corner box; [backButton] is the
///   transparent tap target over it) and the `SETTINGS` title;
/// - WP-NAME PLAYER: the player card (sticker + name, edit in place,
///   [SettingsPlayerCard]); everything below moves down by its height,
///   unchanged, and the body scrolls ([MenuScrollArea]) when it no longer
///   fits above the bottom spikes;
/// - SOUND: three pink tiles — SOUND, MUSIC, RUMBLE — each with its icon,
///   label and ON / OFF tag, grey when off;
/// - the MUSIC VOLUME card: 8 bars, tap or drag across them (0–8);
/// - the GAME card: Support, Restore purchases, Redeem code (no Rate row,
///   §20.2);
/// - the PRIVACY & DATA card: Privacy policy, Privacy options (only when
///   [onPrivacyOptions] is set: the consent SDK requires it), Delete my
///   data;
/// - the footer: the music credit (`Melody by ElectroBaptist`; the name opens
///   the artist's page in the in-app browser, [creditLink]) and
///   `Flappy Spikes v<version> (<build>)`.
///
/// The spike strips are the game's own (they follow the stage tint); the
/// tiles and cards keep their fixed colours. A full-screen blocker behind
/// everything consumes stray taps so they cannot start the game. The whole
/// screen fades as one layer ([GroupOpacity]).
///
/// Setters are safe to call before [onLoad] has run: values are stored and
/// applied once the children exist.
class SettingsPanel extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity
    implements Tintable {
  SettingsPanel({
    required this.muted,
    required this.musicVolume,
    required this.onToggleSound,
    required this.onMusicVolume,
    required this.onBack,
    required this.onPrivacyPolicy,
    this.onRestorePurchases,
    this.rumble = true,
    this.onToggleRumble,
    this.onDeleteMyData,
    this.onPrivacyOptions,
    this.onSupport,
    this.onRedeemCode,
  }) : super(priority: 20);

  bool muted;
  double musicVolume;

  /// The RUMBLE switch (PRD-2 §3.33).
  bool rumble;

  /// RUMBLE tile tap (the game flips the setting and calls [setRumble]).
  final void Function()? onToggleRumble;
  final void Function() onToggleSound;

  /// A new volume (level / 8) from the bars or the MUSIC tile.
  final void Function(double volume) onMusicVolume;
  final void Function() onBack;
  final void Function() onPrivacyPolicy;

  /// GAME → Restore purchases; hidden when null.
  final void Function()? onRestorePurchases;

  /// PRIVACY & DATA → Delete my data (the confirm dialog); hidden when null.
  final void Function()? onDeleteMyData;

  /// PRIVACY & DATA → Privacy options: only shown when the UMP privacy
  /// options are required (EEA/UK); null otherwise (§20.2).
  final void Function()? onPrivacyOptions;

  /// GAME → Support (`Config.supportUrl`); hidden when null.
  final void Function()? onSupport;

  /// GAME → Redeem code (PRD-2.3 §22.2: the store's redeem screen); hidden
  /// when null.
  final void Function()? onRedeemCode;

  /// The MUSIC tile's remembered level while muted (kept for the app
  /// session, so a reopened screen still restores it).
  static int _lastMusicLevel = 0;

  /// Resets [_lastMusicLevel] (tests).
  static void debugResetMusicMemory() => _lastMusicLevel = 0;

  late SettingsLayout layout;

  /// The back button's tap target (over the shared corner box).
  late final MenuButton backButton;
  late final MenuText titleText;
  late final SettingsTile soundTile;
  late final SettingsTile musicTile;
  late final SettingsTile rumbleTile;
  late final RumbleToggle _rumbleButton;
  late final MusicNoteIcon _musicIcon;
  late final SpriteComponent _soundIcon;
  late final VolumeBars volumeBars;
  late final SettingsCard gameCard;
  late final SettingsCard privacyCard;

  /// WP-NAME the PLAYER card, the scrolling body and the rows under the
  /// card (moved down by it, dimmed while the name is edited).
  late final SettingsPlayerCard playerCard;
  late final MenuScrollArea scroll;
  late final SettingsBodyRest rest;
  late final MenuText playerCaption;

  /// GAME rows (null when their callback is).
  SettingsRow? supportRow;
  SettingsRow? restoreRow;
  SettingsRow? redeemRow;

  /// PRIVACY & DATA rows.
  late final SettingsRow privacyRow;
  SettingsRow? privacyOptionsRow;
  SettingsRow? deleteRow;

  /// Footer lines: "Melody by " and the name (the link, [creditLink]), and
  /// the version line.
  late final MenuText creditLead;
  late final MenuText creditText;
  late final MenuButton creditLink;
  late final MenuText versionText;

  /// The RUMBLE tile's icon (tests).
  RumbleToggle get rumbleButton => _rumbleButton;

  /// Every row, top to bottom (tests).
  List<SettingsRow> get rows => [...gameCard.rows, ...privacyCard.rows];

  late Sprite _soundSprite;
  late Sprite _muteSprite;

  int get _level => levelFor(musicVolume);

  /// §20.2 migration: a stored volume shows as the nearest of the 9 steps.
  static int levelFor(double volume) =>
      (volume.clamp(0.0, 1.0) * Config.settingsVolumeLevels).round();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final images = game.images;
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    _soundSprite = Sprite(await images.load('soundbutton.png'));
    _muteSprite = Sprite(await images.load('mutebutton.png'));
    final note = Sprite(await images.load('music_note.png'));
    final chevron = Sprite(await images.load('menu/back.png'));

    final gameRows = <SettingsRow>[
      if (onSupport case final cb?)
        supportRow = SettingsRow('Support', chevron: chevron, onPressed: cb),
      if (onRestorePurchases case final cb?)
        restoreRow = SettingsRow(
          'Restore purchases',
          chevron: chevron,
          onPressed: cb,
        ),
      if (onRedeemCode case final cb?)
        redeemRow = SettingsRow('Redeem code', chevron: chevron, onPressed: cb),
    ];
    final privacyRows = <SettingsRow>[
      privacyRow = SettingsRow(
        'Privacy policy',
        chevron: chevron,
        onPressed: onPrivacyPolicy,
      ),
      if (onPrivacyOptions case final cb?)
        privacyOptionsRow = SettingsRow(
          'Privacy options',
          chevron: chevron,
          onPressed: cb,
        ),
      if (onDeleteMyData case final cb?)
        deleteRow = SettingsRow(
          'Delete my data',
          chevron: chevron,
          danger: true,
          onPressed: cb,
        ),
    ];
    layout = SettingsLayout.fit(
      viewHeight: h,
      gameRows: gameRows.length,
      privacyRows: privacyRows.length,
    );
    final l = layout;
    const left = Config.settingsBodyLeft;
    const width = Config.settingsBodyWidth;

    // First child = bottom-most: swallows every tap the buttons miss so the
    // tap catcher cannot start the game behind the open screen.
    add(_TapBlocker(size: Vector2(Config.worldWidth, h)));

    final backRect = Config.menuScreenBackRectFor(h);
    backButton = MenuButton(
      position: backRect.topLeft.toVector2(),
      size: backRect.size.toVector2(),
      onPressed: onBack,
      priority: 1,
    );
    titleText = MenuText(
      'SETTINGS',
      fontSize: Config.settingsTitleFontSize,
      color: Config.settingsInk,
      letterSpacingEm: 0.06,
      anchor: Anchor.center,
      position: Vector2(Config.worldWidth / 2, Config.settingsTitleCenterY),
    );
    final soundCaption = _caption('SOUND', Vector2(left, l.soundCaptionY));

    // --- tiles ---
    final tileW = (width - 2 * Config.settingsTileGap) / 3;
    final icon = l.tileIcon;
    Vector2 tileAt(int i) =>
        Vector2(left + i * (tileW + Config.settingsTileGap), l.tilesY);
    _soundIcon = SpriteComponent(
      sprite: muted ? _muteSprite : _soundSprite,
      size: Vector2.all(icon),
    )..paint.filterQuality = kMenuFilterQuality;
    soundTile = SettingsTile(
      label: 'SOUND',
      icon: _soundIcon,
      on: !muted,
      layout: l,
      position: tileAt(0),
      size: Vector2(tileW, l.tileHeight),
      onPressed: onToggleSound,
    );
    _musicIcon = MusicNoteIcon(note, size: Vector2.all(icon))
      ..off = _level == 0;
    musicTile = SettingsTile(
      label: 'MUSIC',
      icon: _musicIcon,
      on: _level > 0,
      layout: l,
      position: tileAt(1),
      size: Vector2(tileW, l.tileHeight),
      onPressed: toggleMusic,
    );
    _rumbleButton =
        RumbleToggle(
            on: rumble,
            position: Vector2.zero(),
            onPressed: () {},
            interactive: false,
          )
          ..anchor = Anchor.topLeft
          ..scale = Vector2.all(icon / 30);
    rumbleTile = SettingsTile(
      label: 'RUMBLE',
      icon: _SizedIcon(_rumbleButton, icon),
      on: rumble,
      layout: l,
      position: tileAt(2),
      size: Vector2(tileW, l.tileHeight),
      onPressed: () {
        _click();
        onToggleRumble?.call();
      },
    );

    // --- music volume ---
    volumeBars = VolumeBars(
      level: _level,
      layout: l,
      position: Vector2(left, l.volumeY),
      size: Vector2(width, l.volumeHeight),
      onLevel: _onBarLevel,
    );

    // --- cards ---
    gameCard = SettingsCard(
      caption: 'GAME',
      rows: gameRows,
      layout: l,
      position: Vector2(left, l.gameCardY),
      size: Vector2(width, l.cardHeight(gameRows.length)),
    );
    privacyCard = SettingsCard(
      caption: 'PRIVACY & DATA',
      rows: privacyRows,
      layout: l,
      position: Vector2(left, l.privacyCardY),
      size: Vector2(width, l.cardHeight(privacyRows.length)),
    );

    // --- footer ---
    final footerTop = l.footerY;
    creditLead = MenuText(
      'Melody by ',
      fontSize: Config.settingsFooterFontSize,
      color: Config.settingsFooter,
      letterSpacingEm: 0.08,
    );
    creditText = MenuText(
      'ElectroBaptist',
      fontSize: Config.settingsFooterFontSize,
      color: Config.settingsInk,
      letterSpacingEm: 0.08,
    );
    // The name is the link: a transparent tap box (no press effect, the look
    // is the design's), placed by [_placeCreditLink] once the footer is final.
    creditLink = MenuButton(
      onPressed: () => game.openMusicCredit(),
      pressedTo: 1,
      pressShade: false,
      priority: 1,
    );
    final creditW = creditLead.width + creditText.width;
    final lineTop = footerTop + (l.footerLine - creditLead.height) / 2;
    creditLead.position = Vector2((Config.worldWidth - creditW) / 2, lineTop);
    creditText.position = Vector2(creditLead.x + creditLead.width, lineTop);
    versionText = MenuText(
      'Flappy Spikes',
      fontSize: Config.settingsFooterFontSize,
      color: Config.settingsFooter,
      letterSpacingEm: 0.08,
      anchor: Anchor.topCenter,
      position: Vector2(Config.worldWidth / 2, lineTop + l.footerLine),
    );

    // --- WP-NAME the PLAYER card on top; the rest moves down under it ---
    playerCaption = _caption('PLAYER', Vector2(left, l.bodyTop));
    playerCard = SettingsPlayerCard(
      position: Vector2(
        left,
        l.bodyTop + Config.settingsCaptionHeight + l.captionGap,
      ),
      onLayout: _relayout,
      initialError: CustomNameReason.fromKey(
        game.storage.versusCustomNameError,
      ),
    );
    rest = SettingsBodyRest(isBlocked: () => playerCard.editing)
      ..addAll([
        soundCaption,
        soundTile,
        musicTile,
        rumbleTile,
        volumeBars,
        gameCard,
        privacyCard,
        creditLead,
        creditText,
        creditLink,
        versionText,
      ]);
    scroll = MenuScrollArea(
      viewport: Rect.fromLTRB(
        0,
        l.bodyTop - Config.settingsScrollTopGap,
        Config.worldWidth,
        h - Config.menuSpikeHeight,
      ),
      // The body shows between the bottom teeth (the game lifts the ground
      // strip over the panel while it is mounted, as over the Shop).
      bleedBottom: Config.menuSpikeToothDepth,
    );
    scroll.content.addAll([playerCaption, playerCard, rest]);
    // At rest the footer stays at the bottom of the screen when there is
    // room, else right under the cards (the end of the scrolled body).
    _bodyBuilt = true;
    final shift = _restShift();
    final footerTopRest = math.max(
      l.footerY - shift,
      l.cardsBottom + l.footerGap,
    );
    for (final t in [creditLead, creditText, versionText]) {
      t.y += footerTopRest - l.footerY;
    }
    _footerBottom = footerTopRest + 2 * l.footerLine;
    _placeCreditLink(l);
    _relayout();

    addAll([
      titleText,
      scroll,
      backButton,
      MenuScrollTapGate(
        scroll: scroll,
        position: scroll.visibleRect.topLeft.toVector2(),
        size: scroll.visibleRect.size.toVector2(),
        priority: 1 << 20,
      ),
    ]);
    _loadVersion();
  }

  /// The rows' offset under the card now (0 = where they were before the
  /// card existed).
  double _restShift() =>
      playerCard.y +
      playerCard.blockHeight +
      Config.settingsCardGap -
      layout.bodyTop;

  /// The footer's bottom in [rest] coordinates.
  double _footerBottom = 0;
  bool _bodyBuilt = false;

  void _relayout() {
    if (!_bodyBuilt) return;
    rest.y = _restShift();
    scroll.contentBottom =
        rest.y + _footerBottom + layout.bottomInset - Config.menuSpikeHeight;
    // Editing: the card in view (it is at the top).
    if (playerCard.editing) scroll.scrollTo(0, animate: false);
  }

  @override
  void onMount() {
    super.onMount();
    game.holdGroundOverMenus(true); // WP-NAME
  }

  @override
  void onRemove() {
    game.holdGroundOverMenus(false);
    super.onRemove();
  }

  /// The music credit's tap box: the name's width and
  /// [Config.settingsCreditHitHeight] tall (the touch minimum), centred on
  /// the name's line as far as the PRIVACY & DATA card above allows; its top
  /// never reaches up over that card, whose rows take the taps there.
  void _placeCreditLink(SettingsLayout l) {
    final mid = creditText.y + creditText.height / 2;
    final top = math.max(
      l.cardsBottom,
      mid - Config.settingsCreditHitHeight / 2,
    );
    creditLink
      ..position = Vector2(creditText.x, top)
      ..size = Vector2(creditText.width, Config.settingsCreditHitHeight);
  }

  /// Sets the footer's version when the read is done. No mounted check: a
  /// read that is already done lands before the next frame mounts this
  /// panel (every reopen after the first read), and the text of a panel that
  /// has closed meanwhile is harmless.
  Future<void> _loadVersion() async {
    final version = await game.appInfo.load();
    if (version != null) versionText.text = version.footer;
  }

  MenuText _caption(String text, Vector2 position) => MenuText(
    text,
    fontSize: Config.settingsCaptionFontSize,
    color: Config.settingsCaption,
    letterSpacingEm: 0.22,
    position: position,
  );

  void _click() {
    if (game.soundReady) game.sound.play(Sfx.click);
  }

  /// MUSIC tile: mutes (remembering the level) or restores it (from 0
  /// with nothing remembered: 5 of 8).
  void toggleMusic() {
    _click();
    final level = _level;
    if (level > 0) {
      _lastMusicLevel = level;
      _setLevel(0);
    } else {
      _setLevel(
        _lastMusicLevel > 0
            ? _lastMusicLevel
            : Config.settingsMusicRestoreLevel,
      );
    }
  }

  void _onBarLevel(int level) {
    _click();
    _setLevel(level, fromBars: true);
  }

  void _setLevel(int level, {bool fromBars = false}) {
    final volume = level / Config.settingsVolumeLevels;
    musicVolume = volume;
    if (isLoaded) {
      if (!fromBars) volumeBars.setLevel(level);
      _syncMusic();
    }
    onMusicVolume(volume);
  }

  void _syncMusic() {
    final on = _level > 0;
    musicTile.on = on;
    _musicIcon.off = !on;
    if (volumeBars.level != _level) volumeBars.setLevel(_level);
  }

  void setMuted(bool value) {
    muted = value;
    if (isLoaded) {
      _soundIcon.sprite = value ? _muteSprite : _soundSprite;
      soundTile.on = !value;
    }
  }

  /// The RUMBLE switch changed: the tile and icon follow; switching on
  /// buzzes it.
  void setRumble(bool value) {
    rumble = value;
    if (isLoaded) {
      _rumbleButton.setOn(value, buzz: value);
      rumbleTile.on = value;
    }
  }

  /// The music volume changed (bars, tile, Delete my data's reset).
  void setMusicVolume(double value) {
    musicVolume = value;
    if (isLoaded) _syncMusic();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // §20.2: a spinner replaces Restore's chevron while the restore runs.
    final restore = restoreRow;
    if (restore != null) restore.busy = game.purchasesRestoring;
  }

  /// §20.4: the screen keeps its fixed colours; the spike strips (the
  /// game's) follow the stage tint.
  @override
  void setTint(Color color) {}
}

/// The vertical geometry of the Settings screen (PRD-2.3 §20.2): the
/// design's stack at 711 pt; when it does not fit the playfield (568 pt),
/// it shrinks in the PRD's order — card gaps, row height to 34, tile height
/// to 88 — and then, as far as still needed (call: the PRD's three steps
/// alone free 46 of the ~100–137 pt needed at 568), the top band, rows to
/// 30, tiles to 64, the inner paddings and the bottom inset. Each step
/// shrinks only as much as needed, so the extra space at 711 goes above the
/// footer, as on the page.
class SettingsLayout {
  SettingsLayout._({
    required this.viewHeight,
    required this.gameRows,
    required this.privacyRows,
  });

  /// The layout for [viewHeight] with these row counts.
  factory SettingsLayout.fit({
    required double viewHeight,
    required int gameRows,
    required int privacyRows,
  }) {
    final l = SettingsLayout._(
      viewHeight: viewHeight,
      gameRows: gameRows,
      privacyRows: privacyRows,
    );
    for (final step in _steps) {
      final deficit = l.contentBottom - l.limit;
      if (deficit <= 0.001) break;
      final full = step.saving(l);
      final k = full <= 0 ? 0.0 : math.min(1.0, deficit / full);
      step.apply(l, k);
    }
    return l;
  }

  final double viewHeight;
  final int gameRows;
  final int privacyRows;

  double bodyTop = Config.settingsBodyTop;
  double captionGap = Config.settingsCaptionGap;
  double tileHeight = Config.settingsTileHeight;
  double volumeGap = Config.settingsVolumeGap;
  double volumePadTop = Config.settingsVolumePadTop;
  double volumeHeadGap = Config.settingsVolumeHeadGap;
  double barsHeight = Config.settingsBarsHeight;
  double cardGap = Config.settingsCardGap;
  double cardCaptionTop = Config.settingsCardCaptionTop;
  double rowHeight = Config.settingsRowHeight;
  double footerGap = Config.settingsFooterGap;
  double footerLine = Config.settingsFooterLine;
  double bottomInset = Config.settingsBottomInset;

  /// The tiles' icon: 40 pt, smaller only in a tile under 80 pt.
  double get tileIcon => math.min(Config.settingsTileIcon, tileHeight / 2);
  double get tileIconGap => tileHeight >= 80 ? Config.settingsTileIconGap : 5;

  double get soundCaptionY => bodyTop;
  double get tilesY => bodyTop + Config.settingsCaptionHeight + captionGap;
  double get volumeY => tilesY + tileHeight + volumeGap;
  double get volumeHeight =>
      volumePadTop +
      Config.settingsVolumeHeadHeight +
      volumeHeadGap +
      barsHeight +
      Config.settingsVolumePadBottom;

  /// Top of the bars inside the volume card.
  double get barsTop =>
      volumePadTop + Config.settingsVolumeHeadHeight + volumeHeadGap;

  /// Height of a card with [rows] rows.
  double cardHeight(int rows) =>
      Config.settingsCardPadY +
      cardCaptionTop +
      Config.settingsCaptionHeight +
      rows * rowHeight +
      Config.settingsCardPadY;

  /// Top of the first row inside a card.
  double get cardRowsTop =>
      Config.settingsCardPadY + cardCaptionTop + Config.settingsCaptionHeight;

  double get gameCardY => volumeY + volumeHeight + cardGap;
  double get privacyCardY => gameCardY + cardHeight(gameRows) + cardGap;
  double get cardsBottom => privacyCardY + cardHeight(privacyRows);

  /// Lowest the content may reach (the footer's bottom).
  double get limit => viewHeight - bottomInset;

  /// Where the footer would end if it sat right under the cards.
  double get contentBottom => cardsBottom + footerGap + 2 * footerLine;

  /// The footer's top: at the bottom of the body (extra space above it).
  double get footerY => limit - 2 * footerLine;

  /// Whether everything fits above [limit].
  bool get fits => contentBottom <= limit + 0.01;

  static final List<_Shrink> _steps = [
    // 1. card gaps (PRD §20.2)
    _Shrink([
      (get: (l) => l.cardGap, set: (l, v) => l.cardGap = v, to: 4, n: (l) => 2),
      (
        get: (l) => l.volumeGap,
        set: (l, v) => l.volumeGap = v,
        to: 4,
        n: (l) => 1,
      ),
    ]),
    // 2. row height to 34 (PRD)
    _Shrink([
      (
        get: (l) => l.rowHeight,
        set: (l, v) => l.rowHeight = v,
        to: 34,
        n: (l) => (l.gameRows + l.privacyRows).toDouble(),
      ),
    ]),
    // 3. tile height to 88 (PRD)
    _Shrink([
      (
        get: (l) => l.tileHeight,
        set: (l, v) => l.tileHeight = v,
        to: 88,
        n: (l) => 1,
      ),
    ]),
    // 4.– call: beyond the PRD's list (568 needs more).
    _Shrink([
      (
        get: (l) => l.bodyTop,
        set: (l, v) => l.bodyTop = v,
        to: 104,
        n: (l) => 1,
      ),
    ]),
    _Shrink([
      (
        get: (l) => l.rowHeight,
        set: (l, v) => l.rowHeight = v,
        to: 30,
        n: (l) => (l.gameRows + l.privacyRows).toDouble(),
      ),
    ]),
    _Shrink([
      (
        get: (l) => l.tileHeight,
        set: (l, v) => l.tileHeight = v,
        to: 64,
        n: (l) => 1,
      ),
    ]),
    _Shrink([
      (
        get: (l) => l.captionGap,
        set: (l, v) => l.captionGap = v,
        to: 3,
        n: (l) => 1,
      ),
      (
        get: (l) => l.cardCaptionTop,
        set: (l, v) => l.cardCaptionTop = v,
        to: 5,
        n: (l) => 2,
      ),
      (
        get: (l) => l.volumePadTop,
        set: (l, v) => l.volumePadTop = v,
        to: 6,
        n: (l) => 1,
      ),
      (
        get: (l) => l.volumeHeadGap,
        set: (l, v) => l.volumeHeadGap = v,
        to: 3,
        n: (l) => 1,
      ),
      (
        get: (l) => l.barsHeight,
        set: (l, v) => l.barsHeight = v,
        to: 24,
        n: (l) => 1,
      ),
      (
        get: (l) => l.footerGap,
        set: (l, v) => l.footerGap = v,
        to: 2,
        n: (l) => 1,
      ),
    ]),
    _Shrink([
      (
        get: (l) => l.bottomInset,
        set: (l, v) => l.bottomInset = v,
        to: Config.menuSpikeHeight,
        n: (l) => 1,
      ),
      (
        get: (l) => l.footerLine,
        set: (l, v) => l.footerLine = v,
        to: 14,
        n: (l) => 2,
      ),
    ]),
  ];
}

typedef _Knob = ({
  double Function(SettingsLayout l) get,
  void Function(SettingsLayout l, double v) set,
  double to,
  double Function(SettingsLayout l) n,
});

/// One shrink step: lowers its knobs together, by fraction k of the way to
/// their floors.
class _Shrink {
  const _Shrink(this.knobs);
  final List<_Knob> knobs;

  double saving(SettingsLayout l) =>
      knobs.fold(0, (sum, k) => sum + math.max(0, k.get(l) - k.to) * k.n(l));

  void apply(SettingsLayout l, double fraction) {
    for (final k in knobs) {
      final v = k.get(l);
      if (v > k.to) k.set(l, v - (v - k.to) * fraction);
    }
  }
}

/// A component of fixed [size] that holds [child] (scaled icons).
class _SizedIcon extends PositionComponent {
  _SizedIcon(PositionComponent child, double size)
    : super(size: Vector2.all(size), children: [child]);
}

/// One audio tile (§20.2): pink, the icon over its label, the ON / OFF tag
/// top right; off = the page's `grayscale(1) brightness(1.18)
/// contrast(.8)` over the whole tile. A tap shrinks it to 95 % and runs
/// [onPressed] with the menu knock.
class SettingsTile extends MenuButton {
  SettingsTile({
    required this.label,
    required this.icon,
    required this._on,
    required this.layout,
    required super.position,
    required super.size,
    required super.onPressed,
  }) : super(color: Config.menuPink, pressedTo: 0.95, pressShade: false);

  final String label;
  final PositionComponent icon;
  final SettingsLayout layout;

  bool _on;
  bool get on => _on;
  set on(bool value) {
    _on = value;
    if (isLoaded) tag.text = value ? 'ON' : 'OFF';
  }

  late final MenuText labelText;
  late final MenuText tag;
  late final _TagBox _tagBox;

  /// CSS `grayscale(1) brightness(1.18) contrast(.8)` as one matrix.
  static final ColorFilter offFilter = () {
    const b = 1.18 * 0.8;
    const o = 0.1 * 255; // contrast's (1 - .8) / 2
    const r = 0.2126 * b, g = 0.7152 * b, bl = 0.0722 * b;
    return const ColorFilter.matrix([
      r, g, bl, 0, o, //
      r, g, bl, 0, o, //
      r, g, bl, 0, o, //
      0, 0, 0, 1, 0, //
    ]);
  }();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    const white = Color(0xFFFFFFFF);
    labelText = MenuText(
      label,
      fontSize: Config.settingsTileLabelFontSize,
      color: white,
      letterSpacingEm: 0.14,
      anchor: Anchor.topCenter,
    );
    final column = icon.height + layout.tileIconGap + labelText.height;
    final top = (height - column) / 2;
    icon.position = Vector2((width - icon.width) / 2, top);
    labelText.position = Vector2(
      width / 2,
      top + icon.height + layout.tileIconGap,
    );
    tag = MenuText(
      _on ? 'ON' : 'OFF',
      fontSize: Config.settingsTileTagFontSize,
      color: white,
      letterSpacingEm: 0.1,
      position: Vector2(4, 2),
    );
    _tagBox = _TagBox(tag, right: width - 6, top: 6);
    addAll([icon, labelText, _tagBox]);
  }

  final Paint _offPaint = Paint()..colorFilter = offFilter;

  @override
  void renderTree(Canvas canvas) {
    if (_on) {
      super.renderTree(canvas);
      return;
    }
    canvas.saveLayer(null, _offPaint);
    super.renderTree(canvas);
    canvas.restore();
  }
}

/// The tile's ON / OFF tag: white 25 % behind 9 pt text, 2 / 4 pt padding,
/// right-aligned at [right].
class _TagBox extends PositionComponent {
  _TagBox(this.text, {required this.right, required double top})
    : super(position: Vector2(0, top));

  final MenuText text;
  final double right;
  final Paint _paint = Paint()..color = const Color(0x40FFFFFF);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(text);
  }

  @override
  void update(double dt) {
    super.update(dt);
    size = Vector2(text.width + 8, text.height + 4);
    x = right - width;
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// The MUSIC tile's icon: `music_note.png`; [off] draws the game's off
/// stroke over it (the page: soft #FCD9EE, 4.4 / 60 of the icon, from
/// (12, 50) to (48, 10) in 60-unit space).
class MusicNoteIcon extends SpriteComponent {
  MusicNoteIcon(Sprite sprite, {required super.size}) : super(sprite: sprite) {
    paint.filterQuality = kMenuFilterQuality;
  }

  bool off = false;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt
    ..color = Config.menuSoft;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!off) return;
    final k = width / 60;
    _stroke.strokeWidth = 4.4 * k;
    canvas.drawLine(Offset(12 * k, 50 * k), Offset(48 * k, 10 * k), _stroke);
  }
}

/// The MUSIC VOLUME card (§20.2): white, `MUSIC VOLUME` left and the % in
/// pink right, 8 bars rising from 32 % to 100 % — pink up to the level,
/// the rest #DADADA. A tap or a drag anywhere on the card sets the level
/// from x (the page's `ceil(u * 8 - .15)`, clamped 0–8: the far left gives
/// 0). Each new step calls [onLevel] and pops its bar.
class VolumeBars extends PositionComponent with TapCallbacks, DragCallbacks {
  VolumeBars({
    required this._level,
    required this.layout,
    required super.position,
    required super.size,
    required this.onLevel,
  });

  final SettingsLayout layout;
  final void Function(int level) onLevel;

  int _level;
  int get level => _level;

  late final MenuText valueText;

  /// The bar that pops and how far into its pop (tests).
  int _popBar = -1;
  double _popT = 0;

  /// Bars area, local.
  double get barsLeft => Config.settingsVolumePadX;
  double get barsWidth => width - 2 * Config.settingsVolumePadX;
  double get barWidth =>
      (barsWidth - (Config.settingsVolumeLevels - 1) * Config.settingsBarGap) /
      Config.settingsVolumeLevels;

  /// Bar [i]'s rect, local (0-based).
  Rect barRect(int i) {
    final h =
        layout.barsHeight *
        (Config.settingsBarMinHeight +
            (1 - Config.settingsBarMinHeight) *
                i /
                (Config.settingsVolumeLevels - 1));
    final bottom = layout.barsTop + layout.barsHeight;
    return Rect.fromLTWH(
      barsLeft + i * (barWidth + Config.settingsBarGap),
      bottom - h,
      barWidth,
      h,
    );
  }

  /// The level a touch at local [x] sets.
  int levelAt(double x) {
    final u = (x - barsLeft) / barsWidth;
    return (u * Config.settingsVolumeLevels - .15).ceil().clamp(
      0,
      Config.settingsVolumeLevels,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final head = MenuText(
      'MUSIC VOLUME',
      fontSize: Config.settingsCaptionFontSize,
      color: Config.settingsCaption,
      letterSpacingEm: 0.2,
    );
    valueText = MenuText(
      _percent,
      fontSize: 12,
      color: Config.menuPink,
      letterSpacingEm: 0.08,
      anchor: Anchor.topRight,
    );
    final headTop = layout.volumePadTop;
    final headMid = headTop + Config.settingsVolumeHeadHeight / 2;
    head.position = Vector2(
      Config.settingsVolumePadX,
      headMid - head.height / 2,
    );
    valueText.position = Vector2(
      width - Config.settingsVolumePadX,
      headMid - valueText.height / 2,
    );
    addAll([head, valueText]);
  }

  String get _percent =>
      '${(_level / Config.settingsVolumeLevels * 100).round()}%';

  /// Sets the shown level (no callback).
  void setLevel(int value) {
    _level = value.clamp(0, Config.settingsVolumeLevels);
    if (isLoaded) valueText.text = _percent;
  }

  int _lastTouched = -1;

  void _touch(double x) {
    if (x.isNaN) return;
    final next = levelAt(x);
    if (next == _lastTouched) return;
    _lastTouched = next;
    if (next == _level) return;
    setLevel(next);
    _popBar = next - 1;
    _popT = 0;
    onLevel(next);
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _lastTouched = -1;
    _touch(event.localPosition.x);
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    _lastTouched = -1;
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    event.handled = true;
    _touch(event.localPosition.x);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    event.handled = true;
    // Outside the card the local position is NaN: map the canvas position
    // instead (the far left gives 0).
    final local = event.localEndPosition.x;
    _touch(local.isNaN ? absoluteToLocal(event.canvasEndPosition).x : local);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _lastTouched = -1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_popBar >= 0) {
      _popT += dt;
      if (_popT >= Config.settingsBarPop) _popBar = -1;
    }
  }

  final Paint _card = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _bar = Paint();

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _card);
    for (var i = 0; i < Config.settingsVolumeLevels; i++) {
      var r = barRect(i);
      if (i == _popBar) {
        final u = Curves.easeOut.transform(
          (_popT / Config.settingsBarPop).clamp(0.0, 1.0),
        );
        final s = 1 + (Config.settingsBarPopScale - 1) * math.sin(u * math.pi);
        r = Rect.fromLTRB(r.left, r.bottom - r.height * s, r.right, r.bottom);
      }
      _bar.color = i < _level ? Config.menuPink : Config.settingsBarOff;
      canvas.drawRect(r, _bar);
    }
  }
}

/// A white card with a caption and its rows (§20.2 design A).
class SettingsCard extends PositionComponent {
  SettingsCard({
    required this.caption,
    required this.rows,
    required this.layout,
    required super.position,
    required super.size,
  });

  final String caption;
  final List<SettingsRow> rows;
  final SettingsLayout layout;

  late final MenuText captionText;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    captionText = MenuText(
      caption,
      fontSize: Config.settingsCaptionFontSize,
      color: Config.settingsCaption,
      letterSpacingEm: 0.22,
    );
    final capMid =
        Config.settingsCardPadY +
        layout.cardCaptionTop +
        Config.settingsCaptionHeight / 2;
    captionText.position = Vector2(
      Config.settingsCardPadX,
      capMid - captionText.height / 2,
    );
    add(captionText);
    var y = layout.cardRowsTop;
    for (final (i, row) in rows.indexed) {
      row
        ..position = Vector2(Config.settingsCardPadX, y)
        ..size = Vector2(width - 2 * Config.settingsCardPadX, layout.rowHeight)
        ..divider = i < rows.length - 1;
      y += layout.rowHeight;
    }
    addAll(rows);
  }

  final Paint _paint = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// One card row (§20.2): uppercase 13 pt label left, the mirrored grey
/// `menu/back.png` chevron right, a thin divider under it (not under the
/// last row). [danger] = red text with a pale red chevron. [busy] swaps
/// the chevron for a spinner and stops taps. Fires on tap-up with the
/// menu knock; pressed = #FAFAFA.
class SettingsRow extends MenuButton {
  SettingsRow(
    this.label, {
    required Sprite chevron,
    required super.onPressed,
    this.danger = false,
  }) : _chevronSprite = chevron,
       super(pressedTo: 1, pressShade: false);

  final String label;
  final bool danger;
  final Sprite _chevronSprite;

  bool divider = true;

  late final MenuText labelText;
  late final MenuIcon chevron;

  bool _busy = false;
  bool get busy => _busy;
  set busy(bool value) {
    _busy = value;
    tappable = !value;
  }

  double _spin = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    labelText = MenuText(
      label.toUpperCase(),
      fontSize: Config.settingsRowFontSize,
      color: danger ? Config.settingsRed : Config.settingsInk,
      letterSpacingEm: 0.1,
      anchor: Anchor.centerLeft,
      position: Vector2(0, height / 2),
    );
    const s = Config.settingsChevronSize;
    chevron = MenuIcon(
      _chevronSprite,
      size: Vector2.all(s),
      recolor: danger ? Config.settingsRedChevron : Config.settingsChevron,
      anchor: Anchor.center,
      position: Vector2(width - s / 2, height / 2),
    )..scale = Vector2(-1, 1);
    addAll([labelText, chevron]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isLoaded) chevron.scale = _busy ? Vector2.zero() : Vector2(-1, 1);
    if (_busy) _spin += dt;
  }

  final Paint _line = Paint()..color = Config.settingsLine;
  final Paint _pressedPaint = Paint()..color = Config.settingsRowPressed;
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void render(Canvas canvas) {
    if (pressed) {
      canvas.drawRect(
        Rect.fromLTWH(
          -Config.settingsCardPadX,
          0,
          width + 2 * Config.settingsCardPadX,
          height,
        ),
        _pressedPaint,
      );
    }
    if (divider) {
      canvas.drawRect(Rect.fromLTWH(0, height - 1, width, 1), _line);
    }
    if (_busy) {
      // The page's 14 pt spinner: a soft ring with a pink top, 0.7 s/turn.
      final c = Offset(width - 8, height / 2);
      const r = 6.0;
      _ring.color = Config.menuSoft;
      canvas.drawCircle(c, r, _ring);
      _ring.color = Config.menuPink;
      final a = _spin / 0.7 * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi * 3 / 4 + a,
        math.pi / 2,
        false,
        _ring,
      );
    }
  }
}

/// The RUMBLE icon (PRD-home-v3 §8, mock build73 `PHONE`; reused unchanged
/// in the 2.3 RUMBLE tile, §20.1): a 30 pt pink square (like
/// soundbutton.png) with a soft phone outline; on = vibration marks either
/// side, off = a slash. [setOn] with `buzz` shakes the phone and pops the
/// marks in ([Config.settingsRumbleBuzz]). With [interactive] it fires on
/// tap-down (a menu knock follows); the tile owns the taps otherwise.
class RumbleToggle extends PositionComponent with TapCallbacks {
  RumbleToggle({
    required bool on,
    required super.position,
    required this.onPressed,
    this.interactive = true,
  }) : super(size: Vector2.all(30), anchor: Anchor.center) {
    _on = on;
  }

  final void Function() onPressed;

  /// False inside the RUMBLE tile: taps go to the tile.
  final bool interactive;

  late bool _on;
  bool get on => _on;

  double _opacity = 1;
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  /// Seconds into the buzz (-1 = idle).
  double _buzzT = -1;

  /// Whether the buzz is running (tests).
  bool get buzzing => _buzzT >= 0;

  static const List<(double, double)> _shake = [
    (0, 0),
    (.12, -1.6),
    (.25, 1.6),
    (.37, -1.4),
    (.5, 1.4),
    (.62, -1),
    (.75, 1),
    (.87, -.5),
    (1, 0),
  ];

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _glyph = Paint();

  void setOn(bool value, {bool buzz = false}) {
    _on = value;
    if (buzz) _buzzT = 0;
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      interactive && super.containsLocalPoint(point);

  @override
  void update(double dt) {
    super.update(dt);
    if (_buzzT < 0) return;
    _buzzT += dt;
    if (_buzzT >= Config.settingsRumbleBuzz) _buzzT = -1;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    withMenuKnock(this, onPressed);
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    final soft = Config.menuSoft.withValues(alpha: _opacity);
    _fill.color = Config.menuPink.withValues(alpha: _opacity);
    _stroke.color = soft;
    _glyph.color = soft;
    canvas.drawRect(size.toRect(), _fill);
    final u = _buzzT < 0 ? 1.0 : _buzzT / Config.settingsRumbleBuzz;
    // Phone body (translateX keyframes while buzzing).
    canvas.save();
    canvas.translate(_buzzT < 0 ? 0 : keyframe(_shake, u), 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10.5, 5.5, 9, 19),
        const Radius.circular(1.5),
      ),
      _stroke..strokeWidth = 2,
    );
    canvas.drawRect(const Rect.fromLTWH(13.5, 21, 3, 1.4), _glyph);
    canvas.restore();
    if (_on) {
      // Vibration marks; while buzzing they pop in about the centre
      // (opacity 0 -> 1, scale .6 -> 1.15 -> 1, ease-out).
      final e = Curves.easeOut.transform(u);
      final k = _buzzT < 0 ? 1.0 : math.min(1.0, e / .4);
      final scale = _buzzT < 0
          ? 1.0
          : keyframe(const [(0, .6), (.4, 1.15), (1, 1)], e);
      canvas.save();
      canvas.translate(15, 15);
      canvas.scale(scale);
      canvas.translate(-15, -15);
      _stroke
        ..strokeWidth = 2
        ..color = Config.menuSoft.withValues(alpha: _opacity * k);
      for (final (x, top, bottom) in const [
        (7.0, 11.0, 19.0),
        (4.0, 13.0, 17.0),
        (23.0, 11.0, 19.0),
        (26.0, 13.0, 17.0),
      ]) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), _stroke);
      }
      canvas.restore();
    } else {
      canvas.drawLine(
        const Offset(6, 25),
        const Offset(24, 5),
        _stroke..strokeWidth = 2.2,
      );
    }
  }
}

/// Invisible full-screen tap target behind the panel's controls: consumes
/// taps that no button claimed so they cannot reach the [TapCatcher] (which
/// would start the game) while the settings panel is open.
class _TapBlocker extends PositionComponent with TapCallbacks {
  _TapBlocker({super.size});

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}

/// WP-NAME the Settings rows under the PLAYER card, as one group moved down
/// by the card (positions inside are the pre-card layout). While the name
/// is edited ([isBlocked]) they are dimmed to 35 % (the design's `.dim`)
/// and take no taps.
class SettingsBodyRest extends PositionComponent {
  SettingsBodyRest({required this.isBlocked});

  final bool Function() isBlocked;

  static const double dimOpacity = .35;

  @override
  void renderTree(Canvas canvas) {
    if (!isBlocked()) {
      super.renderTree(canvas);
      return;
    }
    canvas.saveLayer(null, layerPaint(dimOpacity));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  Iterable<Component> componentsAtLocation<T>(
    T locationContext,
    List<T>? nestedContexts,
    T? Function(CoordinateTransform, T) transformContext,
    bool Function(Component, T) checkContains,
  ) {
    if (isBlocked()) return const [];
    return super.componentsAtLocation(
      locationContext,
      nestedContexts,
      transformContext,
      checkContains,
    );
  }
}
