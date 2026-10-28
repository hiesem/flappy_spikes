import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/config.dart';
import '../../../game/sound.dart';
import '../../../run/backdrop/backdrop_ctx.dart';
import '../../../run/backdrop/backdrop_palette.dart';
import '../../../run/backdrop/backdrop_scene.dart';
import '../../../run/backdrop/backdrop_tables.dart';
import '../../home/menu_primitives.dart';
import '../../look_component.dart';
import '../../menu_screen_chrome.dart';
import '../../../run/effects/collect_fx.dart';
import '../levels_screen.dart';
import 'levels_tabs.dart';

/// G4 / O87: a finite 1 → 10 map, driven by actual hoops, ending at SPACE.
/// The shell owns the pending dot and marks it seen after [open].
class WorldsTab {
  WorldsTab._(this.screen);
  final LevelsScreen screen;
  late final MenuScrollArea scroll;
  final List<WorldCard> cards = [];
  int get reached => screen.game.storage.worldsReached.clamp(1, 10);
  int get best => screen.game.storage.bestHoops;

  static WorldsTab install(LevelsScreen screen) {
    final tab = WorldsTab._(screen);
    final storage = screen.game.storage;
    for (var i = 0; i < 10; i++) {
      tab.cards.add(
        WorldCard(
          index: i,
          reached: i < tab.reached,
          current: i == tab.reached - 1,
          next: i == tab.reached,
          best: tab.best,
          unseen: i >= storage.worldsSeen && i < storage.worldsReached,
          screen: screen,
        ),
      );
    }
    tab.scroll = screen.installTabContent(
      LevelsTab.worlds,
      header: _WorldHeader(tab),
      rows: [
        MenuText(
          'START · HOOP 0',
          fontSize: 10,
          color: const Color(0xFFA8A8A8),
          letterSpacingEm: .2,
          anchor: Anchor.topCenter,
          position: Vector2(160, 276),
        ),
        ...tab.cards,
      ],
      contentBottom: WorldCard.top(9) + 96 + 40,
      onOpen: tab.open,
    );
    return tab;
  }

  void open() {
    final current = cards[reached - 1];
    scroll.scrollTo(
      current.y + 48 - scroll.viewport.height / 2,
      animate: false,
    );
    final unseen = cards.where((c) => c.unseen).toList();
    if (unseen.isEmpty) return;
    screen.game.sound.play(Sfx.lvUp);
    for (final card in unseen) {
      card.reveal();
    }
    if (!screen.game.reduceMotion) {
      final burst = CollectBursts()
        ..burst(
          at: Offset(160, current.y + 48),
          colors: [Config.menuGold, Config.menuPink, const Color(0xFFFFFFFF)],
          pieces: 22,
          speed: 100,
          life: .9,
        );
      scroll.content.add(burst);
    }
  }
}

const _names = [
  'NEST CANOPY',
  'SKY & HILLS',
  'CITY SKYLINE',
  'CLOCKWORK',
  "GIANT'S DESK",
  'CANDY LAND',
  'PAPER ORIGAMI',
  'UNDERWATER',
  'DREAMLAND',
  'SPACE',
];
// House palettes from worlds_map.html WPAL, independent of colour stage.
const _sky = [
  0xFFE3F3D9,
  0xFFFFEBDC,
  0xFFE8E4F8,
  0xFFF7EDD6,
  0xFFDCEAFA,
  0xFFFFE2EF,
  0xFFE9F1F8,
  0xFFBEEBEC,
  0xFFECE2FB,
  0xFF1D2352,
];
const _near = [
  0xFF5DA653,
  0xFFD9875E,
  0xFF7D6CC6,
  0xFFA87A32,
  0xFFB07440,
  0xFFF0559F,
  0xFF6F93B6,
  0xFF2B8E86,
  0xFF8B6ED8,
  0xFF5560A8,
];

/// A cached view of the existing run scene master; no duplicate scene art.
class WorldScenePreview extends PositionComponent {
  WorldScenePreview(this.index, {required Vector2 size}) : super(size: size);
  final int index;
  double colour = 1;
  Picture? _picture;

  @override
  Future<void> onLoad() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final ctx = Ctx()
      ..canvas = canvas
      ..env = index
      ..cam = 1200;
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 568),
      Paint()..color = const Color(0xFFF1F1F1),
    );
    for (final band in Band.layers) {
      kScenes[index].draw(ctx, band);
    }
    _picture = recorder.endRecording();
    ctx.clearStrips();
  }

  @override
  void render(Canvas canvas) {
    final picture = _picture;
    if (picture == null) return;
    final bg = Color.lerp(const Color(0xFFE2E2E2), Color(_sky[index]), colour)!;
    final fg = Color.lerp(
      const Color(0xFFA9A9A9),
      Color(_near[index]),
      colour,
    )!;
    canvas.save();
    canvas.clipRect(size.toRect());
    // Crop the real scene at its landmark, preserving its aspect ratio.
    const focusY = [
      365.0,
      450.0,
      400.0,
      420.0,
      420.0,
      440.0,
      430.0,
      370.0,
      300.0,
      260.0,
    ];
    final zoom = math.max(width / 320, height / 240);
    canvas.translate(width / 2, height / 2);
    canvas.scale(zoom);
    canvas.translate(-160, -focusY[index]);
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, 320, 568),
      Paint()..colorFilter = ColorFilter.matrix(palMatrix(bg, fg)),
    );
    canvas.drawPicture(picture);
    canvas.restore();
    canvas.restore();
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }
}

class _WorldHeader extends PositionComponent {
  _WorldHeader(this.tab);
  final WorldsTab tab;
  late final MenuText barText;
  late final double progress;

  @override
  Future<void> onLoad() async {
    final k = tab.reached - 1;
    final next = tab.reached < 10;
    progress = next ? ((tab.best - k * 20) / 20).clamp(0.0, 1.0) : 1;
    final picture = WorldScenePreview(k, size: Vector2.all(84));
    barText = MenuText(
      next
          ? '${tab.reached * 20 - tab.best} HOOPS TO ${_names[k + 1]}'
          : 'ALL 10 WORLDS · SPACE FLYER',
      fontSize: 8,
      color: Config.menuPlum,
      anchor: Anchor.center,
      position: Vector2(188, 65),
    );
    addAll([
      picture,
      MenuText(
        _names[k],
        fontSize: 17,
        color: const Color(0xFF828282),
        position: Vector2(94, 10),
      ),
      MenuText(
        'WORLD ${k + 1} / 10 · BEST ${tab.best} HOOPS',
        fontSize: 9,
        color: const Color(0xFF828282),
        position: Vector2(94, 36),
      ),
      barText,
    ]);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFFE8E8E8));
    canvas.drawRect(
      const Rect.fromLTWH(94, 57, 188, 16),
      Paint()..color = Config.menuSoft,
    );
    canvas.drawRect(
      Rect.fromLTWH(94, 57, 188 * progress, 16),
      Paint()..color = tab.reached == 10 ? Config.menuGold : Config.menuPink,
    );
  }
}

class WorldCard extends PositionComponent {
  WorldCard({
    required this.index,
    required this.reached,
    required this.current,
    required this.next,
    required this.best,
    required this.unseen,
    required this.screen,
  }) : super(position: Vector2(14, top(index)), size: Vector2(292, 96));
  final int index, best;
  final bool reached, current, next;
  bool unseen;
  final LevelsScreen screen;
  late final WorldScenePreview scene;
  LookComponent? bird;
  MenuText? nameText;
  double _reveal = -1;
  static double top(int index) => 298 + index * 122.0;

  @override
  Future<void> onLoad() async {
    scene = WorldScenePreview(index, size: size.clone())
      ..colour = reached && !unseen ? 1 : 0;
    addAll([scene, _WorldCardDecorations(this)]);
    if (reached || next) {
      nameText = MenuText(
        _names[index],
        fontSize: 12.5,
        color: const Color(0xFF6E6E6E),
        position: Vector2(8, 76),
      );
      add(nameText!);
    }
    add(
      MenuText(
        '${index + 1}',
        fontSize: 14,
        color: reached ? Config.menuPink : const Color(0xFFA9A9A9),
        position: Vector2(8, 7),
      ),
    );
    if (current || next) {
      add(
        MenuTag(
          current ? 'YOU' : 'NEXT',
          fontSize: 9,
          fillColor: current ? Config.menuPink : Config.menuSoft,
          textColor: current ? Config.menuSoft : Config.menuPlum,
          position: Vector2(30, -8),
        ),
      );
    }
    if (current) {
      bird = LookComponent(
        look: screen.game.menu.items.look,
        artScale: .8,
        position: Vector2(58, 38),
      )..flapOverride = false;
      bird!.opacity = unseen ? 0 : 1;
      add(bird!);
    }
    if (reached) {
      add(
        MenuIcon(
          screen.sprite('menu/check.png'),
          size: Vector2.all(11),
          recolor: const Color(0xFF9A9A9A),
          position: Vector2(nameText!.width + 15, 78),
        ),
      );
    } else if (next) {
      add(
        MenuText(
          '$best / ${index * 20}',
          fontSize: 9.5,
          color: Config.menuPlum,
          anchor: Anchor.topRight,
          position: Vector2(284, 78),
        ),
      );
    }
    if (!reached && !next) {
      add(
        MenuIcon(
          screen.sprite('menu/lock.png'),
          size: Vector2.all(12),
          recolor: const Color(0xFFA9A9A9),
          position: Vector2(8, 78),
        ),
      );
    }
  }

  void reveal() {
    unseen = false;
    _reveal = screen.game.reduceMotion ? .9 : 0;
    scene.colour = screen.game.reduceMotion ? 1 : 0;
    bird?.opacity = 1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_reveal >= 0 &&
        _reveal < .9 &&
        screen.tabIsActive(LevelsTab.worlds) &&
        !screen.game.liveMotionPaused) {
      _reveal += dt;
      scene.colour = (_reveal / .9).clamp(0.0, 1.0);
    }
  }

  @override
  void render(Canvas canvas) {
    // Connector is outside the card; the scroll area clips the whole list.
    if (index > 0) {
      final p = Paint()
        ..color = reached ? Config.menuPink : const Color(0xFFC9C9C9);
      for (var y = -23.0; y < -3; y += 7) {
        canvas.drawRect(Rect.fromLTWH(145, y, 2, 3), p);
      }
    }
  }

  void paintDecorations(Canvas canvas) {
    final p = Paint()..color = const Color(0xEEFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 72, reached || next ? 292 : 28, 24), p);
    if (current) {
      p
        ..color = Config.menuPink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(size.toRect().deflate(1.5), p);
    }
    if (next) {
      p
        ..style = PaintingStyle.fill
        ..color = Config.menuSoft;
      canvas.drawRect(const Rect.fromLTWH(182, 79, 48, 10), p);
      p.color = Config.menuPink;
      canvas.drawRect(
        Rect.fromLTWH(182, 79, 48 * (best / (index * 20)).clamp(0, 1), 10),
        p,
      );
    }
  }
}

class _WorldCardDecorations extends Component {
  _WorldCardDecorations(this.card);
  final WorldCard card;
  @override
  void render(Canvas canvas) => card.paintDecorations(canvas);
}
