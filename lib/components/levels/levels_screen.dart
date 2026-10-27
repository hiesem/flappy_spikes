// region P26-G4a
import 'dart:async';
// endregion
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
// region P26-G4a
import '../../game/sound.dart';
// endregion
import '../../levels/levels.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../look_component.dart';
import '../menu_screen_chrome.dart';
import '../ui/live_effects.dart';
import 'emblem_view.dart';
// region P26-G4b
import 'tabs/worlds_tab.dart';
// endregion

// region P26-G4a
import 'tabs/levels_tabs.dart';
// endregion

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
    return level >= 1 ? rows[level - 1] : null;
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
      games: game.storage.gamesPlayed,
      look: look,
      coin: sprite('menu/coin.png'),
    );
    for (final def in kLevels) {
      rows.add(
        LevelRow(
          def: def,
          state: def.level < level
              ? LevelRowState.reached
              : def.level == level
              ? LevelRowState.current
              : LevelRowState.locked,
          look: look,
          coin: sprite('menu/coin.png'),
        ),
      );
    }
    // region P26-G4a
    // The old list started at 242; move its content to the new 264 band.
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
    scroll.content.addAll(rows);
    // region P26-G4a
    scroll.contentBottom =
        Config.levelsRowTop(kLevels.length) +
        listShift +
        Config.levelsListPadBottom;
    // endregion
    // The live emblems: the header's and the current row's.
    final current = currentRow;
    clock.bind((t, still) {
      for (final view in [header.emblem, ?current?.liveEmblem]) {
        view
          ..t = still ? 0 : t
          ..shine = !still;
      }
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
        Config.levelsRowTop(level - 1) +
        (LevelsTabsLayout.listTop - Config.levelsListTop) +
        Config.levelsRowHeight / 2;
    // endregion
    scroll.scrollTo(rowMid - viewport.height / 2, animate: false);
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
    required this.best,
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
      level: level,
      artScale: Config.levelsHeaderEmblemScale,
      position: centre,
    );
    bird = LookComponent(
      look: look,
      artScale: Config.levelsHeaderEmblemScale * Config.levelsBirdOnEmblem,
      anchor: Anchor.center,
      position: centre.clone(),
    )..flapOverride = false;
  }

  final int level;
  final int best;
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
    final def = levelDef(level);
    final next = nextLevel(level);
    // Owner 2026-10-17 (WP-L): the level is stored and steps up one per
    // run; the next one needs its threshold in a single run, so the bar is
    // empty below LEGEND and the label names that score.
    progress = next == null ? 1 : 0;

    const nameLine = Config.levelsHeaderNameFontSize * kNormalLineHeight;
    const statsLine = Config.levelsHeaderStatsFontSize * kNormalLineHeight;
    const block =
        nameLine + 3 + statsLine + 7 + Config.levelsBarHeight; // 65.8
    const top = (Config.levelsHeaderEmblemBox - block) / 2;
    nameText = MenuText(
      def?.name ?? 'UNRANKED',
      fontSize: Config.levelsHeaderNameFontSize,
      color: const Color(0xFF828282),
      letterSpacingEm: 0.06,
      position: Vector2(_textX, top),
    );
    statsText = MenuText(
      'BEST ${formatCoins(best)} · GAMES ${formatCoins(games)}',
      fontSize: Config.levelsHeaderStatsFontSize,
      color: const Color(0xFF828282),
      letterSpacingEm: 0.12,
      position: Vector2(_textX, top + nameLine + 3),
    );
    barText = MenuText(
      next == null
          ? 'MAX LEVEL'
          : '${formatCoins(next.threshold)} TO ${next.name}',
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
  }) : super(
         position: Vector2(
           Config.homeMargin,
           Config.levelsRowTop(def.level - 1),
         ),
         size: Vector2(Config.shopRowWidth, Config.levelsRowHeight),
       );

  final LevelDef def;
  final LevelRowState state;
  final Look look;
  final Sprite coin;

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

  static const Offset _emblemCentre = Offset(
    Config.levelsRowEmblemWidth / 2,
    Config.levelsRowEmblemY,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (isCurrent) {
      liveEmblem = EmblemView(
        level: def.level,
        artScale: Config.levelsRowEmblemScale,
        position: _emblemCentre.toVector2(),
      );
      bird = LookComponent(
        look: look,
        artScale: Config.levelsRowEmblemScale * Config.levelsBirdOnEmblem,
        anchor: Anchor.center,
        position: _emblemCentre.toVector2(),
      )..flapOverride = false;
      addAll([liveEmblem!, bird!]);
    } else {
      picture = recordEmblem(
        def.level,
        grey: !reached,
        look: reached ? look : null,
        birdScale: Config.levelsBirdOnEmblem,
      );
    }

    const nameLine = Config.levelsRowNameFontSize * kNormalLineHeight;
    const reachLine = Config.levelsRowReachFontSize * kNormalLineHeight;
    const top = (Config.levelsRowHeight - nameLine - 3 - reachLine) / 2;
    nameText = MenuText(
      def.name,
      fontSize: Config.levelsRowNameFontSize,
      color: _fg,
      letterSpacingEm: 0.06,
      position: Vector2(Config.levelsRowEmblemWidth, top),
    );
    reachText = MenuText(
      'REACH ${formatCoins(def.threshold)}',
      fontSize: Config.levelsRowReachFontSize,
      color: _fg,
      letterSpacingEm: 0.14,
      position: Vector2(Config.levelsRowEmblemWidth, top + nameLine + 3),
    );
    chip = _RewardChip(
      reward: def.reward,
      claimed: reached,
      coin: coin,
      rowWidth: width,
    );
    addAll([nameText, reachText, chip]);
    if (isCurrent) addAll([_CurrentOutline(this), _YouTag()]);
    if (!reached) add(_LockIcon(this));
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
    if (pic != null) {
      canvas.save();
      canvas.translate(_emblemCentre.dx, _emblemCentre.dy);
      canvas.scale(Config.levelsRowEmblemScale);
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
  });

  final int reward;
  final bool claimed;
  final Sprite coin;
  final double rowWidth;

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
      fontSize: Config.levelsChipFontSize,
      color: claimed ? _fg.withValues(alpha: .7) : Config.menuPlum,
    );
    coinIcon = MenuIcon(coin, size: Vector2.all(Config.levelsChipCoinSize));
    const pad = Config.levelsChipPad;
    final lead = claimed ? _checkWidth + _checkGap : 0.0;
    final w =
        pad + lead + Config.levelsChipCoinSize + 5 + text.width + pad;
    size = Vector2(w, Config.levelsChipHeight);
    position = Vector2(
      rowWidth - Config.levelsChipRight - w,
      Config.levelsChipTop,
    );
    coinIcon.position = Vector2(
      pad + lead,
      (height - Config.levelsChipCoinSize) / 2,
    );
    text.position = Vector2(
      pad + lead + Config.levelsChipCoinSize + 5,
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
