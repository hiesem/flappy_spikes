// region P26-G4a
import 'dart:async';
// endregion
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
// region P26-G4a
import '../../game/sound.dart';
// endregion
import '../../levels/levels.dart';
import '../../skins/look.dart';
import '../../skins/catalog.dart';
import '../skins/item_art.dart';
import '../skins/item_tile.dart';
import '../../run/effects/coin_icon.dart';
import '../home/menu_primitives.dart';
import '../look_component.dart';
import '../menu_screen_chrome.dart';
import '../ui/live_effects.dart';
import '../ui/mystery_box.dart';
import 'emblem_view.dart';
// region P26-G4b
import 'tabs/worlds_tab.dart';
// endregion

// region P26-G4a
import 'tabs/levels_tabs.dart';
// endregion

// region P26-J6
/// The LEVELS screen (PRD-home-v3 §4.4, build74 `.lvscr`), opened from the
/// home emblem: the shared menu chrome (back button top-left, title
/// LEVELS; no coin pill), a fixed header card with the current emblem +
/// bird, rank name, "BEST n · GAMES n" and the progress bar, and the
/// scrolling list of the ten ranks (EGG at the top), opened scrolled so
/// the current row is in view.
///
/// Row emblems are static pictures recorded once ([recordEmblem]); only
/// the header and the current row animate (one idle clock, paused under
/// popups / ads, frozen under reduce motion). Enters with a fade + 14 pt
/// rise over 0.22 s (§3.3).
class LevelsScreen extends MenuScreen {
  LevelsScreen({required super.onBack}) : super(title: 'LEVELS');

  // region P26-G4b
  @override
  List<String> get contentImages => const ['menu/check.png', 'menu/lock.png'];
  // endregion

  late final LevelsHeader header;
  final List<LevelRow> rows = [];
  late final LiveClock clock;

  double _enterT = 0;

  /// Vertical offset of the enter rise right now (tests).
  double get rise => position.y;

  // region P26-G4a
  late final LevelsTabs tabs;
  LevelsTab get selectedTab => tabs.selected;

  // The existing Levels content remains mounted until J6 replaces it.
  // Later packages install their own header and scrolling body here.
  final Map<LevelsTab, MenuScrollArea> _tabScrolls = {};
  final Map<LevelsTab, void Function()> _onTabOpen = {};

  @override
  bool isActive() =>
      super.isActive() && (!built || selectedTab == LevelsTab.levels);

  bool tabIsActive(LevelsTab tab) => active && !locked && selectedTab == tab;

  @override
  Rect scrollViewportFor(double viewHeight) =>
      LevelsTabsLayout.viewport(viewHeight);

  /// Hosts a tab using the same fixed header and list band as LEVELS.
  /// Interactive children should use `() => tabIsActive(tab)`.
  MenuScrollArea installTabContent(
    LevelsTab tab, {
    required PositionComponent header,
    required Iterable<Component> rows,
    required double contentBottom,
    void Function()? onOpen,
  }) {
    assert(tab != LevelsTab.levels && !_tabScrolls.containsKey(tab));
    header
      ..position = LevelsTabsLayout.header.topLeft.toVector2()
      ..size = LevelsTabsLayout.header.size.toVector2()
      ..decorator.addLast(LevelsTabVisibility(() => selectedTab == tab));
    final area = MenuScrollArea(
      viewport: scrollViewportFor(game.viewHeight),
      bleedBottom: Config.menuSpikeToothDepth,
      isActive: () => tabIsActive(tab),
    )..contentBottom = contentBottom;
    area.decorator.addLast(LevelsTabVisibility(() => selectedTab == tab));
    area.content.addAll(rows);
    _tabScrolls[tab] = area;
    if (onOpen != null) _onTabOpen[tab] = onOpen;
    addAll([
      header,
      area,
      MenuScrollTapGate(
        scroll: area,
        position: area.visibleRect.topLeft.toVector2(),
        size: area.visibleRect.size.toVector2(),
        priority: 1 << 20,
      ),
    ]);
    return area;
  }

  void selectTab(LevelsTab tab) {
    if (!active || locked || tab == selectedTab) return;
    game.sound.play(Sfx.skTab);
    tabs.selected = tab;
    titleText
      ..text = tab.title
      ..fontSize = tab.title.length > 8
          ? Config.levelsTabTitleCompactFontSize
          : Config.levelsTabTitleFontSize
      ..position.y = tab.title.length > 8
          ? Config.levelsTabTitleCompactTop
          : Config.levelsTabTitleTop;
    // Content can animate an unseen entry before the shell marks it seen.
    _onTabOpen[tab]?.call();
    if (tab == LevelsTab.worlds) {
      unawaited(game.storage.saveWorldsSeen(game.storage.worldsReached));
    } else if (tab == LevelsTab.guide) {
      unawaited(
        game.storage.saveGuideSeenCount(game.storage.metElements.length),
      );
    }
    tabs.sync(game.storage);
  }

  @override
  void sync({bool force = false}) => tabs.sync(game.storage);
  // endregion

  /// The row of the current level (null while unranked).
  LevelRow? get currentRow {
    final level = game.menu.levels.level;
    return level >= 1 ? rows[(level - 1).clamp(0, rows.length - 1)] : null;
  }

  @override
  Future<void> buildContent() async {
    final game = this.game;
    final levels = game.menu.levels;
    final level = levels.level;
    final look = game.menu.items.look;
    // region P26-G4a
    titleText.position.y = Config.levelsTabTitleTop;
    titleText.fontSize = Config.levelsTabTitleFontSize;
    tabs = LevelsTabs(onSelect: selectTab, isActive: () => active && !locked);
    add(tabs);
    // Q26: opening the shell clears only the Home hint, not tab dots.
    unawaited(game.storage.saveHomeLevelsTag(false));
    // endregion
    clock = LiveClock(
      paused: () => game.liveMotionPaused,
      still: () => game.reduceMotion,
    );
    header = LevelsHeader(
      level: level,
      best: levels.best,
      points: levels.points,
      games: game.storage.gamesPlayed,
      look: look,
      coin: sprite('menu/coin.png'),
    );
    final rewardByLevel = {for (final row in levels.rewardLog) row['lvl']: row};
    for (final def in [...kTrackLevels, kEternalWing]) {
      rows.add(
        LevelRow(
          def: def,
          state: def.level < level && def.level != 32
              ? LevelRowState.reached
              : def.level == level || (def.level == 32 && level >= 32)
              ? LevelRowState.current
              : LevelRowState.locked,
          look: look,
          coin: sprite('menu/coin.png'),
          points: levels.points,
          isNext: def.level == level + 1,
          reward: rewardByLevel[def.level],
          eternalRewards: def.level == 32 && level >= 32
              ? [
                  for (var n = level; n >= 32; n--)
                    rewardByLevel[n] ?? {'lvl': n, 'coins': kEternalWing.coins},
                ]
              : const [],
          scroll: scroll,
        ),
      );
    }
    // region P26-G4a
    final listShift = LevelsTabsLayout.listTop - Config.levelsListTop;
    for (final row in rows) {
      row.position.y += listShift;
    }
    header.position = LevelsTabsLayout.header.topLeft.toVector2();
    header.decorator.addLast(
      LevelsTabVisibility(() => selectedTab == LevelsTab.levels),
    );
    scroll.decorator.addLast(
      LevelsTabVisibility(() => selectedTab == LevelsTab.levels),
    );
    // endregion
    scroll.content.add(LevelsListContent(rows));
    scroll.contentBottom = Config.levelsRowTop(kTrackLevels.length + 1) +
        listShift + Config.levelsListPadBottom + (level >= 32 ? 100 : 0);
    // The live emblems: the header's and the current row's.
    final current = currentRow;
    clock.bind((t, still) {
      for (final view in [header.emblem, ?current?.liveEmblem]) {
        view
          ..t = still ? 0 : t
          ..shine = !still;
      }
      current?.pulse = still ? 0 : LiveCurves.pulse(t);
      final paused = game.liveMotionPaused;
      header.bird.paused = paused;
      current?.bird?.paused = paused;
    });
    addAll([clock, header]);
    _scrollToCurrent();
    // region P26-G4b
    WorldsTab.install(this);
    // endregion
  }

  /// Scrolls so the current row sits mid-viewport (build74: `scrollTop =
  /// cur.offsetTop - clientHeight / 2 + 36`); unranked stays at the top.
  void _scrollToCurrent() {
    final level = game.menu.levels.level;
    if (level < 1) return;
    final viewport = scroll.viewport;
    // region P26-G4a
    final rowMid =
        Config.levelsRowTop((level - 1).clamp(0, 31)) +
        (LevelsTabsLayout.listTop - Config.levelsListTop) +
        Config.levelsRowHeight / 2;
    // endregion
    scroll.scrollTo(rowMid - viewport.height / 2, animate: !game.reduceMotion);
  }

  @override
  void onTint(Color color) {
    final bg = game.stageBackground;
    header.setColors(fg: color, bg: bg);
    for (final row in rows) {
      row.setColors(fg: color, bg: bg);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_enterT < Config.levelsEnterDuration) {
      _enterT += dt;
      final u = (_enterT / Config.levelsEnterDuration).clamp(0.0, 1.0);
      position.y = Config.levelsEnterRise * (1 - Curves.easeOut.transform(u));
    }
  }
}

/// Hostable list contents; the parent supplies clipping and vertical scrolling.
class LevelsListContent extends PositionComponent {
  LevelsListContent(this.rows);
  final List<LevelRow> rows;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    addAll(rows);
  }
}

/// How a [LevelRow] is drawn (§4.4).
enum LevelRowState { reached, current, locked }

/// Fills [rect] with [paint] (shared by the header and the rows).
void _fillRect(Canvas canvas, Rect rect, Paint paint) =>
    canvas.drawRect(rect, paint);

/// The fixed header card (x 14, y 150, 292 x 84): the current emblem +
/// bird, rank name (20 pt), "BEST 640 · GAMES 34" (11 pt) and the progress
/// bar (186 x 16, soft-pink track, pink fill) "160 TO HAWK" / "MAX LEVEL".
class LevelsHeader extends PositionComponent {
  LevelsHeader({
    required this.level,
    // region P26-J2
    this.points = 0,
    // endregion
    required this.best,
    this.points = 0,
    required this.games,
    required Look look,
    required Sprite coin,
  }) : super(
         position: Config.levelsHeaderRect.topLeft.toVector2(),
         size: Config.levelsHeaderRect.size.toVector2(),
       ) {
    const box = Config.levelsHeaderEmblemBox;
    final centre = Vector2(box / 2, Config.levelsHeaderEmblemY);
    emblem = EmblemView(
      // region P26-J2
      progression: true,
      // endregion
      level: level,
      artScale: Config.levelsHeaderEmblemScale * (level >= 32 ? 70 / 88 : 1),
      position: centre,
    );
    bird = LookComponent(
      look: look,
      artScale:
          Config.levelsHeaderEmblemScale *
          Config.levelsBirdOnEmblem *
          (level >= 32 ? 70 / 88 : 1),
      anchor: Anchor.center,
      position: centre.clone(),
    )..flapOverride = false;
  }

  final int level;
  // region P26-J2
  final int points;
  // endregion
  final int best;
  final int points;
  final int games;

  late final EmblemView emblem;
  late final LookComponent bird;
  late final MenuText nameText;
  late final MenuText statsText;
  late final MenuText barText;

  /// Progress fill 0..1 (tests).
  late final double progress;

  final Paint _card = Paint();
  final Paint _track = Paint()..color = Config.menuSoft;
  final Paint _fill = Paint()..color = Config.menuPink;

  static const double _textX = Config.levelsHeaderEmblemBox;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final def = trackLevelDef(level);
    final next = trackLevelDef(level + 1);
    // region P26-J2
    // PRD-2.6 J3: points accumulate across counting runs.
    final need = needFor(level);
    progress = (points / need).clamp(0.0, 1.0);
    // endregion

    const nameLine = Config.levelsHeaderNameFontSize * kNormalLineHeight;
    const statsLine = Config.levelsHeaderStatsFontSize * kNormalLineHeight;
    const block = nameLine + 3 + statsLine + 7 + Config.levelsBarHeight; // 65.8
    const top = (Config.levelsHeaderEmblemBox - block) / 2;
    nameText = MenuText(
      def?.name ?? 'UNRANKED',
      fontSize: Config.levelsHeaderNameFontSize,
      color: const Color(0xFF828282),
      letterSpacingEm: 0.06,
      position: Vector2(_textX, top),
    );
    if (level > 0) {
      final badgeWidth =
          MenuText(
            '$level',
            fontSize: 12,
            fontFamily: 'Fredoka',
            color: const Color(0xFFFFFFFF),
          ).width +
          10;
      nameText.fitWidth(nameText.text, 202 - badgeWidth - 6);
    }
    statsText = MenuText(
      'BEST ${formatCoins(best)} · GAMES ${formatCoins(games)}',
      fontSize: Config.levelsHeaderStatsFontSize,
      color: const Color(0xFF828282),
      letterSpacingEm: 0.12,
      position: Vector2(_textX, top + nameLine + 3),
    );
    barText = MenuText(
      '${formatCoins((need - points).clamp(0, need))} TO '
      '${level >= 32 ? 'LEVEL ${level + 1}' : next!.name}',
      fontSize: Config.levelsBarFontSize,
      color: Config.menuPlum,
      letterSpacingEm: 0.1,
      lineHeight: 17 / Config.levelsBarFontSize,
    );
    final barTop = top + nameLine + 3 + statsLine + 7;
    barText.position = Vector2(
      _textX + (Config.levelsBarWidth - barText.width) / 2,
      barTop,
    );
    _barRect = Rect.fromLTWH(
      _textX,
      barTop,
      Config.levelsBarWidth,
      Config.levelsBarHeight,
    );
    addAll([emblem, bird, nameText, statsText, _BarFill(this), barText]);
    if (level > 0) {
      add(
        MenuTag(
          '$level',
          fontSize: 12,
          fontFamily: 'Fredoka',
          fillColor: Config.menuPink,
          position: Vector2(_textX + nameText.width + 6, top),
        ),
      );
    }
    _built = true;
    _applyColors();
  }

  late final Rect _barRect;

  /// The progress bar track (local coordinates; tests).
  Rect get barRect => _barRect;

  Color _fg = const Color(0xFF828282);
  bool _built = false;

  void setColors({required Color fg, required Color bg}) {
    _fg = fg;
    _card.color = Color.lerp(bg, fg, Config.levelsHeaderMix)!;
    if (_built) _applyColors();
  }

  void _applyColors() {
    nameText.color = _fg;
    statsText.color = _fg.withValues(alpha: .85);
  }

  @override
  void render(Canvas canvas) => _fillRect(canvas, size.toRect(), _card);
}

/// The header's progress bar (track + fill), drawn under its label.
class _BarFill extends Component {
  _BarFill(this._header);

  final LevelsHeader _header;

  @override
  void render(Canvas canvas) {
    final r = _header._barRect;
    canvas.drawRect(r, _header._track);
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width * _header.progress, r.height),
      _header._fill,
    );
  }
}

/// One rank of the list (292 x 72 at [Config.levelsRowTop]): emblem (+
/// the bird once reached), rank name 17 pt, "REACH 600" 11 pt and the
/// reward chip on the right.
/// - reached: ✓ + coin + reward in the stage fg at 70 % (claimed);
/// - current: reached style, a 3 pt pink inner outline and the "YOU" tag;
/// - locked: greyed emblem without bird, lock icon, dimmed text, the chip
///   soft pink with plum text.
class LevelRow extends PositionComponent {
  LevelRow({
    required this.def,
    required this.state,
    required this.look,
    required this.coin,
    this.points = 0,
    this.isNext = false,
    this.reward,
    this.eternalRewards = const [],
    this.scroll,
  }) : super(
         position: Vector2(
           Config.homeMargin,
           Config.levelsRowTop(def.level - 1),
         ),
         size: Vector2(
           Config.shopRowWidth,
           Config.levelsRowHeight +
               (def.level == 32 && state == LevelRowState.current ? 100 : 0),
         ),
       );

  final TrackLevelDef def;
  final LevelRowState state;
  final Look look;
  final Sprite coin;
  final int points;
  final bool isNext;
  final Map<String, Object?>? reward;
  final List<Map<String, Object?>> eternalRewards;
  final MenuScrollArea? scroll;
  SkinItem? get rewardItem =>
      allItems.where((item) => item.key == reward?['item']).firstOrNull;

  bool get reached => state != LevelRowState.locked;
  bool get isCurrent => state == LevelRowState.current;

  /// The animated emblem of the current row (null for the static rows).
  EmblemView? liveEmblem;

  /// The bird on the current row's emblem (null otherwise).
  LookComponent? bird;

  /// The static emblem picture of the other rows (null for the current).
  Picture? picture;

  late final MenuText nameText;
  late final MenuText reachText;
  late final PositionComponent chip;
  late final MenuText chipText;

  bool _built = false;
  final Paint _row = Paint();
  final Paint _outline = Paint()
    ..color = Config.menuPink
    ..style = PaintingStyle.stroke
    ..strokeWidth = Config.levelsCurrentOutline;
  Color _fg = const Color(0xFF828282);
  double pulse = 0;

  static const Offset _emblemCentre = Offset(
    Config.levelsRowEmblemWidth / 2,
    Config.levelsRowEmblemY,
  );

  double get _emblemScale =>
      Config.levelsRowEmblemScale *
      (def.level == 32
          ? 60 / 74
          : def.level == 28
          ? 64 / 74
          : 1);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (isCurrent) {
      liveEmblem = EmblemView(
        // region P26-J2
        progression: true,
        // endregion
        level: def.level,
        artScale: _emblemScale,
        position: _emblemCentre.toVector2(),
      );
      bird = LookComponent(
        look: look,
        artScale: _emblemScale * Config.levelsBirdOnEmblem,
        anchor: Anchor.center,
        position: _emblemCentre.toVector2(),
      )..flapOverride = false;
      addAll([liveEmblem!, bird!]);
    } else {
      picture = recordEmblem(
        def.level,
        // region P26-J2
        progression: true,
        // endregion
        grey: !reached,
        look: reached ? look : null,
        birdScale: Config.levelsBirdOnEmblem,
      );
    }

    const top = 9.0;
    nameText = MenuText(
      def.name,
      fontSize: 15,
      color: _fg,
      letterSpacingEm: 0.06,
      position: Vector2(78, top),
    );
    reachText = MenuText(
      def.level == 32
          ? '${formatCoins(def.points)} PTS EACH'
          : '${formatCoins(def.points)} PTS',
      fontSize: 10,
      color: _fg,
      letterSpacingEm: 0.14,
      position: Vector2(78, 30),
    );
    chip = _RewardChip(
      reward: reward?['coins'] as int? ?? def.coins,
      claimed: reached && def.level != 32,
      coin: coin,
      rowWidth: width,
      listPosition: true,
    );
    addAll([
      nameText,
      if (!isNext && !(def.level == 32 && isCurrent)) reachText,
      chip,
    ]);
    if (isNext || (def.level == 32 && isCurrent)) {
      add(_RowProgress(points: points, need: def.points));
    }
    if (isCurrent) addAll([_CurrentOutline(this), _YouTag()]);
    if (isNext) {
      add(
        MenuTag(
          'NEXT',
          fontSize: 9,
          letterSpacingEm: .14,
          fillColor: Config.menuSoft,
          textColor: Config.menuPlum,
          position: Vector2(6, -7),
          priority: 5,
        ),
      );
    }
    if (!reached && !isNext) add(_LockIcon(this));
    final item = rewardItem;
    if (reached && def.level < 32 && item != null) {
      addAll([
        _RewardItemName(item, chip),
        _EarnedItem(
          item: item,
          isNew:
              reward?['equipped'] != true && look.idFor(item.layer) != item.id,
        ),
      ]);
    }
    if (def.level == 32 && isCurrent) {
      add(
        MenuText(
          'EARNED · ${eternalRewards.length}',
          fontSize: 9.5,
          color: _fg,
          position: Vector2(78, 79),
        ),
      );
      add(LevelRewardCarousel(eternalRewards, coin: coin, scroll: scroll));
    }
    _built = true;
    _applyColors();
  }

  @override
  void onRemove() {
    picture?.dispose();
    picture = null;
    super.onRemove();
  }

  /// Reward chip text (tests).
  String get chipLabel => (chip as _RewardChip).text.text;

  Color get fg => _fg;

  void setColors({required Color fg, required Color bg}) {
    _fg = fg;
    _row.color = Color.lerp(bg, fg, Config.levelsRowMix)!;
    if (_built) _applyColors();
  }

  void _applyColors() {
    final dim = reached ? 1.0 : .55;
    nameText.color = _fg.withValues(alpha: dim);
    reachText.color = _fg.withValues(alpha: .8 * dim);
    (chip as _RewardChip).fg = _fg;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _row);
    final pic = picture;
    if (!reached || def.level == 32) {
      canvas.save();
      canvas.translate(width - 33, 38);
      MysteryBox.paint(canvas, MysteryBoxLook.levelBox, size: 50);
      canvas.restore();
    }
    if (pic != null) {
      canvas.save();
      canvas.translate(_emblemCentre.dx, _emblemCentre.dy);
      canvas.scale(_emblemScale);
      canvas.drawPicture(pic);
      canvas.restore();
    }
  }
}

/// The current row's 3 pt pink inner outline (CSS `box-shadow: inset 0 0
/// 0 3px`), drawn over the row content.
class _CurrentOutline extends Component {
  _CurrentOutline(this._row) : super(priority: 4);

  final LevelRow _row;

  @override
  void render(Canvas canvas) {
    const half = Config.levelsCurrentOutline / 2;
    canvas.drawRect(_row.size.toRect().deflate(half), _row._outline);
    if (_row.pulse > 0) {
      canvas.drawRect(
        _row.size.toRect().inflate(_row.pulse * 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Config.menuPink.withValues(alpha: .16 * _row.pulse),
      );
    }
  }
}

/// The reward chip (mock `.rw`): right 8, top 22, 28 high, 9 pt padding,
/// [✓] coin "+reward" 15 pt with 5 pt gaps. Claimed: transparent, stage fg
/// at 70 %; locked: soft pink with plum text.
class _RewardChip extends PositionComponent {
  _RewardChip({
    required this.reward,
    required this.claimed,
    required this.coin,
    required this.rowWidth,
    this.listPosition = false,
  });

  final int reward;
  final bool claimed;
  final Sprite coin;
  final double rowWidth;
  final bool listPosition;

  late final MenuText text;
  late final MenuIcon coinIcon;
  final Paint _bg = Paint()..color = Config.menuSoft;
  final Paint _check = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeJoin = StrokeJoin.miter;

  static const double _checkWidth = 10;
  static const double _checkGap = 8; // "✓ " + the 5 pt flex gap

  Color _fg = const Color(0xFF828282);
  bool _built = false;
  set fg(Color value) {
    _fg = value;
    if (!_built || !claimed) return;
    final c = value.withValues(alpha: .7);
    text.color = c;
    _check.color = c;
    coinIcon.paint.color = Color.fromRGBO(255, 255, 255, .7);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    text = MenuText(
      '+${formatCoins(reward)}',
      fontSize: listPosition ? 12 : Config.levelsChipFontSize,
      color: claimed ? _fg.withValues(alpha: .7) : Config.menuPlum,
    );
    final coinSize = listPosition ? 12.0 : Config.levelsChipCoinSize;
    coinIcon = MenuIcon(coin, size: Vector2.all(coinSize));
    final pad = listPosition ? 5.0 : Config.levelsChipPad;
    final lead = claimed ? _checkWidth + _checkGap : 0.0;
    final w = pad + lead + coinSize + 4 + text.width + pad;
    size = Vector2(w, listPosition ? 20 : Config.levelsChipHeight);
    position = Vector2(
      listPosition ? 78 : rowWidth - Config.levelsChipRight - w,
      listPosition ? 45 : Config.levelsChipTop,
    );
    coinIcon.position = Vector2(pad + lead, (height - coinSize) / 2);
    text.position = Vector2(
      pad + lead + coinSize + 4,
      (height - text.height) / 2,
    );
    addAll([coinIcon, text]);
    _built = true;
    fg = _fg;
  }

  @override
  void render(Canvas canvas) {
    if (!claimed) {
      canvas.drawRect(size.toRect(), _bg);
      return;
    }
    // A thin check where the mock's "✓ " sits.
    final y = height / 2;
    const x = Config.levelsChipPad;
    canvas.drawPath(
      Path()
        ..moveTo(x, y)
        ..lineTo(x + 3.5, y + 3.5)
        ..lineTo(x + _checkWidth, y - 4),
      _check,
    );
  }
}

/// The current row's "YOU" tag (mock `.you`): left 6, top -7, pink with
/// soft 9 pt text, 0.14 em, padding 2 / 5 / 1.
class _YouTag extends PositionComponent {
  _YouTag() : super(position: Vector2(6, -7), priority: 5);

  final Paint _paint = Paint()..color = Config.menuPink;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final label = MenuText(
      'YOU',
      fontSize: 9,
      color: Config.menuSoft,
      letterSpacingEm: 0.14,
      position: Vector2(5, 2),
    );
    size = Vector2(label.width + 10, label.height + 3);
    add(label);
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// The locked row's lock (mock `.lk`: 13 x 13 at left 6 / top 6, the
/// 24-unit glyph in the stage fg).
class _LockIcon extends PositionComponent {
  _LockIcon(this._row)
    : super(position: Vector2(6, 6), size: Vector2.all(13), priority: 5);

  final LevelRow _row;
  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6;

  static final Path _shackle = Path()
    ..moveTo(8, 10)
    ..lineTo(8, 7)
    ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
    ..lineTo(16, 10);

  @override
  void render(Canvas canvas) {
    _fill.color = _row.fg;
    _stroke.color = _row.fg;
    canvas.save();
    canvas.scale(13 / 24);
    canvas.drawRect(const Rect.fromLTWH(4, 10, 16, 12), _fill);
    canvas.drawPath(_shackle, _stroke);
    canvas.restore();
  }
}

class _RowProgress extends PositionComponent {
  _RowProgress({required this.points, required this.need})
    : super(position: Vector2(78, 29), size: Vector2(130, 12));
  final int points, need;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final text = MenuText(
      '${formatCoins(points)} / ${formatCoins(need)}',
      fontSize: 9,
      color: Config.menuPlum,
    );
    text.position = Vector2((width - text.width) / 2, 0);
    add(text);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = Config.menuSoft);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * (points / need).clamp(0.0, 1.0), height),
      Paint()..color = Config.menuPink,
    );
  }
}

class _RewardItemName extends MenuText {
  _RewardItemName(SkinItem item, this.chip)
    : super(
        item.name.toUpperCase(),
        fontSize: 12,
        fontFamily: 'Fredoka',
        color: item.rarity?.color ?? const Color(0xFF999999),
        position: Vector2(78, 47),
      );
  final PositionComponent chip;
  bool _positioned = false;
  @override
  void update(double dt) {
    super.update(dt);
    if (!_positioned && chip.width > 0) {
      position.x = chip.position.x + chip.width + 5;
      _positioned = true;
    }
  }
}

class _EarnedItem extends PositionComponent {
  _EarnedItem({required this.item, required this.isNew})
    : super(position: Vector2(234, 9), size: Vector2.all(50));
  final SkinItem item;
  final bool isNew;
  final ItemArtCache art = ItemArtCache();
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final color = item.rarity?.color ?? const Color(0xFF999999);
    add(_rewardTile(item, 50, art));
    add(
      MenuText(
        item.rarity?.label ?? '',
        fontSize: 8,
        color: color,
        anchor: Anchor.topCenter,
        position: Vector2(25, 55),
      ),
    );
    if (isNew) add(MenuTag('NEW', fontSize: 9, position: Vector2(30, -6)));
  }

  @override
  void onRemove() {
    art.dispose();
    super.onRemove();
  }
}

ItemTile _rewardTile(SkinItem item, double size, ItemArtCache art) => ItemTile(
  item: item,
  rect: Rect.fromLTWH(0, 0, size, size),
  state: () => const ItemTileState(
    owned: true,
    equipped: false,
    tryingOn: false,
    isNew: false,
  ),
  onPressed: () {},
  art: art,
  cardColor: () => const Color(0xFFF4F4F4),
  tint: () => const Color(0xFF828282),
  reduceMotion: () => true,
  rewardTile: true,
);

/// Horizontal reward strip. Vertical drags are passed to the enclosing list.
class LevelRewardCarousel extends PositionComponent with DragCallbacks {
  LevelRewardCarousel(this.rewards, {required this.coin, required this.scroll})
    : super(position: Vector2(78, 94), size: Vector2(204, 84));
  final List<Map<String, Object?>> rewards;
  final Sprite coin;
  final MenuScrollArea? scroll;
  final ItemArtCache art = ItemArtCache();
  late final PositionComponent _content;
  double _offset = 0;
  double get offset => _offset;
  set offset(double value) {
    _offset = value;
    _content.position.x = -value;
  }

  bool? _horizontal;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _content = PositionComponent();
    for (var i = 0; i < rewards.length; i++) {
      _content.add(
        _CarouselEntry(rewards[i], coin: coin, art: art, x: i * 62.0 + 7),
      );
    }
    add(_content);
  }

  @override
  void onRemove() {
    art.dispose();
    super.onRemove();
  }

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(position.x, position.y, width, height));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _horizontal = null;
    _start = event;
    event.handled = true;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    _horizontal ??= event.localDelta.x.abs() > event.localDelta.y.abs();
    if (_horizontal!) {
      offset = (offset - event.localDelta.x).clamp(
        0.0,
        ((rewards.length * 62) - width).clamp(0.0, double.infinity),
      );
      event.handled = true;
    } else {
      // Start the parent on the first vertical update.
      if (!_verticalStarted) {
        scroll?.onDragStart(_start!);
        _verticalStarted = true;
      }
      scroll?.onDragUpdate(event);
    }
  }

  DragStartEvent? _start;
  bool _verticalStarted = false;
  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_horizontal == true) {
      offset = ((offset / 62).round() * 62.0).clamp(
        0.0,
        ((rewards.length * 62) - width).clamp(0.0, double.infinity),
      );
    } else if (_verticalStarted) {
      scroll?.onDragEnd(event);
    }
    _verticalStarted = false;
  }
}

class _CarouselEntry extends PositionComponent {
  _CarouselEntry(
    this.row, {
    required this.coin,
    required this.art,
    required double x,
  }) : super(position: Vector2(x, 8), size: Vector2(40, 76));
  final Map<String, Object?> row;
  final Sprite coin;
  final ItemArtCache art;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final item = allItems.where((item) => item.key == row['item']).firstOrNull;
    if (item != null) add(_rewardTile(item, 40, art));
    add(
      MenuTag(
        'LV ${row['lvl']}',
        fontSize: 9,
        fontFamily: 'Fredoka',
        fillColor: Config.menuPink,
        position: Vector2(20, -7),
        anchor: Anchor.topCenter,
      ),
    );
    final name = MenuText(
      item?.name.toUpperCase() ?? '',
      fontSize: 10.5,
      fontFamily: 'Fredoka',
      color: item?.rarity?.color ?? const Color(0xFF999999),
      anchor: Anchor.topCenter,
      position: Vector2(20, 42),
    );
    name.fitWidth(name.text, 54);
    add(name);
    add(_CarouselAmount(coin, row['coins'] as int? ?? 2500));
  }
}

class _CarouselAmount extends PositionComponent {
  _CarouselAmount(this.coin, this.coins) : super(position: Vector2(-5, 57));
  final Sprite coin;
  final int coins;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final label = MenuText(
      '+${formatCoins(coins)}',
      fontSize: 9,
      color: const Color(0xFF828282),
      position: Vector2(22, 0),
    );
    add(label);
    size = Vector2(22 + label.width, 12);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 5)
        ..lineTo(3.5, 8.5)
        ..lineTo(10, 1),
      Paint()
        ..color = const Color(0xFF828282)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.miter,
    );
    CoinIcon.paint(canvas, coin.image, const Offset(16, 6), 9);
  }
}
// endregion
