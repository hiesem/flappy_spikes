// region P26-G5b
import '../../progression/weekly_course.dart';
// endregion P26-G5b
import 'dart:ui';
// region P26-K
import 'dart:math' as math;
import '../../game/sound.dart';
import '../effects/gold_sticker.dart';
import '../effects/perfect_burst.dart';
// endregion

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../config/hud_config.dart';
import '../run_controller.dart';
import '../run_scaled_world.dart';
import 'banner_layer.dart';
import 'banners.dart';
import 'fit_name.dart';
import 'heart_indicator.dart';
import 'pause_button.dart';
import 'versus_bar.dart';

/// The run HUD (PRD-2 §5.7, ARCH §1.10): lives in `camera.viewport`, so it
/// runs in real time — the Hourglass time scale does not slow it and run
/// shakes do not move it. Screen coordinates (320 × viewHeight).
///
/// Holds the top row — heart indicator (x 14), versus bar + name chips
/// (only with an opponent, driven by `RunSetup.opponent`; WP-5b fills the
/// live parts) and the pause button (right edge 306). No coin total (§5.7).
/// The row shows while the run is playing or paused and fades out on a death
/// (the revive screen has its own balance pill). The banner band ([banners],
/// master #7) is not in the HUD any more:
/// PRD-2.2 §12 moved it to the world's [bannerLayer], behind the gameplay.
class RunHud extends PositionComponent with HasGameReference<FlappySpikesGame> {
  RunHud(this.run) : super(priority: 10);

  final RunController run;

  static final Expando<RunHud> _huds = Expando('RunHud');

  /// The run's HUD, created in the viewport the first time (features that
  /// attach before the game adds it — the streak's banners — call this).
  static RunHud ensureFor(RunController run) {
    final existing = _huds[run];
    if (existing != null && !existing.isRemoving && !existing.isRemoved) {
      return existing;
    }
    final hud = RunHud(run);
    _huds[run] = hud;
    // WP-TAB: the HUD sits on the run column (right-aligned on a wide
    // screen, like the run world).
    hud.position.x = run.game.extraWidth;
    run.game.camera.viewport.add(hud);
    run.game.world.add(RunScaledWorld.inRunColumn(hud.bannerLayer));
    return hud;
  }

  /// The HUD of [run] if one was created.
  static RunHud? of(RunController run) => _huds[run];

  /// The run's banner layer (PRD-2.2 §12.2): a screen-space layer in the
  /// world, drawn behind the bird, the hoops and the pickups.
  late final RunBannerLayer bannerLayer = RunBannerLayer(
    game: run.game,
    hud: this,
  );

  /// The shared banner band (streak, FEVER, element and switch banners);
  /// it lives in [bannerLayer].
  BannerHost get banners => bannerLayer.banners;

  late final HeartIndicator heart = HeartIndicator(this);
  late final PauseButton pauseButton = PauseButton(this);
  VersusBar? versus;

  /// The row's opacity (0..1), fading with the run.
  double rowOpacity = 0;

  // region P26-K
  // region P26-G5b
  late HudText _bestLabel = HudText(
    run.setup.weekly ? 'WEEKLY' : 'BEST',
    size: 10.5,
    spacing: 1.5 / 10.5,
    color: Config.uiAccent,
  );
  // endregion P26-G5b
  bool _paintedGold = false;
  HudText? _bestNumber;
  int _paintedBest = -1;
  GoldSticker? bestSticker;
  double? _bestAge;
  double _pointAge = 1;
  int _lastBestScore = -1;
  // region P26-G5b
  String _weeklyCountdownValue = '';
  HudText? _weeklyCountdown;
  bool get bestChipVisible => run.setup.weekly ? run.countsForUpload : run.bestGoalEligible;
  // endregion P26-G5b
  double get _bestFlipProgress =>
      (((_bestAge ?? -1) - HudConfig.bestFlipDelay) / .22).clamp(0.0, 1.0);
  bool get bestChipGold => _bestFlipProgress >= .5;
  // region P26-G5b
  int get bestChipScore => run.setup.weekly ? run.state.hoopsPassed : (bestChipGold ? run.state.score : run.bestBefore);
  // endregion P26-G5b

  void showNewBest() {
    if (_bestAge != null) return;
    _bestAge = 0;
    bestSticker = GoldSticker.newBest(
      // region P26-G5b
      text: run.setup.weekly ? 'NEW WEEK BEST!' : 'NEW BEST!',
      // endregion P26-G5b
      position: Vector2(160, HudConfig.bestStickerY),
    );
    add(_BestStickerClock(this, bestSticker!));
    const gold = [HudConfig.gold, Color(0xFFFFD54A), Color(0xFFFFFFFF)];
    final bird = run.game.runBirdPosition ?? run.geo.normalBirdPosition();
    final random = math.Random(run.setup.seed);
    for (final screen in [bird, Vector2(bird.x, 106)]) {
      final at = run.geo.toTrack(screen);
      PerfectBurst.emit(
        run.particles,
        Offset(at.x, at.y),
        1,
        random,
        palette: gold,
      );
    }
    run.game.sound.play(Sfx.perfect1);
  }

  void _updateBest(double dt) {
    if (game.state == GameState.paused || !rowWanted) return;
    if (_lastBestScore != run.state.score) {
      _lastBestScore = run.state.score;
      _pointAge = 0;
    }
    _pointAge += dt;
    if (_bestAge != null) {
      _bestAge = _bestAge! + dt;
      final sticker = bestSticker;
      if (sticker != null) {
        final exit = ((_bestAge! - .95) / .25).clamp(0.0, 1.0);
        sticker.opacity = 1 - exit;
        sticker.scale.setAll(1 - .12 * exit);
        sticker.position.y = HudConfig.bestStickerY - 6 * exit;
        if (_bestAge! >= HudConfig.bestMomentLength || !bestChipVisible) {
          sticker.parent?.removeFromParent();
          bestSticker = null;
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!bestChipVisible || rowOpacity <= 0) return;
    final gold = bestChipGold;
    final color = gold ? HudConfig.plum : Config.uiAccent;
    if (_paintedGold != gold) {
      _paintedGold = gold;
      _paintedBest = -1;
      _bestLabel = HudText(
        // region P26-G5b
        run.setup.weekly ? 'WEEKLY' : 'BEST',
        // endregion P26-G5b
        size: 10.5,
        spacing: 1.5 / 10.5,
        color: color,
      );
    }
    final label = _bestLabel;
    if (_paintedBest != bestChipScore) {
      _paintedBest = bestChipScore;
      _bestNumber = HudText(
        '$bestChipScore',
        size: 21,
        font: Config.scoreFont,
        color: color,
      );
    }
    final number = _bestNumber!;
    final width = math.max(84.0, label.width + 7 + number.width + 22);
    final flip = _bestFlipProgress;
    final sy = flip > 0 && flip < 1 ? math.cos(flip * math.pi).abs() : 1.0;
    final pop = gold && _pointAge < .22
        ? 1 + .1 * math.sin(math.pi * _pointAge / .22)
        : 1.0;
    canvas.save();
    canvas.translate(160, HudConfig.bestChipY);
    canvas.scale(pop, sy * pop);
    canvas.drawRect(
      Rect.fromLTWH(
        -width / 2,
        -HudConfig.bestChipHeight / 2,
        width,
        HudConfig.bestChipHeight,
      ),
      Paint()
        ..color = (gold ? HudConfig.gold : const Color(0xFFFFFFFF)).withValues(
          alpha: rowOpacity,
        ),
    );
    final left = -(label.width + 7 + number.width) / 2;
    // region P26-G5b
    if (run.setup.weekly && !gold) {
      canvas.drawRect(Rect.fromLTRB(-width / 2, -HudConfig.bestChipHeight / 2,
          left + label.width + 3.5, HudConfig.bestChipHeight / 2),
          Paint()..color = HudConfig.gold.withValues(alpha: rowOpacity));
    }
    // endregion P26-G5b
    label.paintCentred(
      canvas,
      Offset(left + label.width / 2, 1),
      opacity: rowOpacity,
      // region P26-G5b
      colorOverride: run.setup.weekly ? HudConfig.plum : color,
      // endregion P26-G5b
    );
    number.paintCentred(
      canvas,
      Offset(left + label.width + 7 + number.width / 2, 2.5),
      opacity: rowOpacity,
      colorOverride: color,
    );
    canvas.restore();
    // region P26-G5b
    if (run.setup.weekly) {
      final now = game.storage.now();
      final value = WeeklyWeek.at(now).countdown(now);
      if (_weeklyCountdown == null || value != _weeklyCountdownValue) {
        _weeklyCountdownValue = value;
        _weeklyCountdown = HudText(value, size: 8, color: Config.uiAccent);
      }
      _weeklyCountdown!.paintCentred(canvas, Offset(160, HudConfig.bestChipY + HudConfig.bestChipHeight / 2 + 8), opacity: rowOpacity);
    }
    // endregion P26-G5b
  }
  // endregion

  bool _cleared = false;

  /// Hidden entirely while a menu screen sits over the paused run (the
  /// settings from the pause card, the Shop from the revive offer).
  bool get hidden => game.runSettingsOpen || game.reviveShopOpen;

  @override
  void renderTree(Canvas canvas) {
    if (hidden) return;
    super.renderTree(canvas);
  }

  /// The row is wanted on screen now.
  bool get rowWanted {
    final s = game.state;
    return !run.dying &&
        !run.ended &&
        (s == GameState.playing || s == GameState.paused);
  }

  @override
  Future<void> onLoad() async {
    size = Vector2(320, game.viewHeight);
    add(heart);
    if (run.setup.opponent != null) add(versus = VersusBar(this));
    add(pauseButton);
  }

  @override
  void onRemove() {
    bannerLayer.removeFromParent();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (run.isRemoved || !identical(game.run, run)) {
      removeFromParent();
      return;
    }
    // A death clears the banner band (the revive offer / results come up
    // over the frozen game).
    if (run.dying && !_cleared) {
      _cleared = true;
      banners.clear();
      for (final c in children.toList()) {
        if (c != heart && c != pauseButton && c != versus) {
          c.removeFromParent();
        }
      }
    } else if (!run.dying) {
      _cleared = false;
    }
    // region P26-K
    _updateBest(dt);
    // endregion
    final target = rowWanted ? 1.0 : 0.0;
    final step = dt / HudConfig.rowFade;
    rowOpacity = rowOpacity < target
        ? (rowOpacity + step).clamp(0.0, target)
        : (rowOpacity - step).clamp(target, 1.0);
  }
}

// region P26-K
/// Only K's sticker uses this clock; other HUD features keep their own timing.
class _BestStickerClock extends Component {
  _BestStickerClock(this.hud, GoldSticker sticker) : super(children: [sticker]);

  final RunHud hud;

  @override
  void updateTree(double dt) {
    super.updateTree(hud.game.state == GameState.paused ? 0 : dt);
  }
}
// endregion

/// One-line text for the HUD and run screens (Opificio unless [font]).
class HudText {
  /// PRD-2.3 §21.2 a name tag: [name] fitted into [maxWidth] by [fitName]
  /// (shrunk down to 70 %, then cut with "…").
  factory HudText.name(
    String name, {
    required double maxWidth,
    required double size,
    required Color color,
    double spacing = 0,
    String? font,
  }) {
    final f = fitName(
      name,
      maxWidth,
      size,
      measureName(
        fontFamily: font ?? Config.uiFont,
        letterSpacingEm: spacing,
        fontWeight: font == HudConfig.nameFont ? FontWeight.w600 : null,
        trimTrailingSpacing: true,
      ),
    );
    return HudText(
      f.text,
      size: f.size,
      color: color,
      spacing: spacing,
      font: font,
    );
  }

  HudText(
    this.text, {
    required this.size,
    required this.color,
    this.spacing = 0,
    this.font,
    this.maxWidth,
  });

  final String text;
  final double size;
  final Color color;

  /// Letter spacing (em).
  final double spacing;
  final String? font;

  /// Ellipsis beyond this width (pt).
  final double? maxWidth;

  TextPainter? _tp;
  Color? _paintedColor;

  TextPainter _painter(Color c) {
    if (_tp != null && _paintedColor == c) return _tp!;
    _paintedColor = c;
    return _tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: font ?? _uiFont,
          fontSize: size,
          letterSpacing: size * spacing,
          color: c,
          height: 1,
          fontWeight: font == HudConfig.nameFont ? FontWeight.w600 : null,
        ),
      ),
      textDirection: p.TextDirection.ltr,
      maxLines: 1,
      ellipsis: maxWidth != null ? '…' : null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
  }

  static const String _uiFont = Config.uiFont;

  /// Visible width (without the trailing letter spacing).
  double get width {
    final tp = _painter(color);
    return tp.width - size * spacing;
  }

  double get height => _painter(color).height;

  /// Draws centred on [c]; [opacity] multiplies [color]'s alpha.
  void paintCentred(
    Canvas canvas,
    Offset c, {
    double opacity = 1,
    Color? colorOverride,
  }) {
    final col = (colorOverride ?? color);
    final tp = _painter(col.withValues(alpha: col.a * opacity.clamp(0.0, 1.0)));
    // The same width as [width], read from this layout: [width] would lay
    // the text out again in the base colour on every faded frame (A2-11).
    final w = tp.width - size * spacing;
    tp.paint(canvas, Offset(c.dx - w / 2, c.dy - tp.height / 2));
  }
}
