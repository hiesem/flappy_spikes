import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../config/hud_config.dart';
import '../run_controller.dart';
import 'banner_layer.dart';
import 'banners.dart';
import 'heart_indicator.dart';
import 'pause_button.dart';
import 'versus_bar.dart';

/// The run HUD (PRD-2 §5.7, ARCH §1.10): lives in `camera.viewport`, so it
/// runs in real time — the Hourglass time scale does not slow it and run
/// shakes do not move it. Screen coordinates (320 × viewHeight).
///
/// Holds the top row — heart indicator (x 14), versus bar + name chips
/// (only with an opponent, driven by `RunSetup.opponent`; WP-5b fills the
/// live parts) and the pause button (right edge 306) — plus the graze
/// notice. No coin total (§5.7). The row shows while the run is playing or
/// paused and fades out on a death (the revive screen has its own balance
/// pill). The banner band ([banners], master #7) is not in the HUD any more:
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
    run.game.camera.viewport.add(hud);
    run.game.world.add(hud.bannerLayer);
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
    // A death clears the banner band and the graze notice (the revive
    // offer / results come up over the frozen game).
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
    final target = rowWanted ? 1.0 : 0.0;
    final step = dt / HudConfig.rowFade;
    rowOpacity = rowOpacity < target
        ? (rowOpacity + step).clamp(0.0, target)
        : (rowOpacity - step).clamp(target, 1.0);
  }
}

/// One-line text for the HUD and run screens (Opificio unless [font]).
class HudText {
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
    tp.paint(canvas, Offset(c.dx - width / 2, c.dy - tp.height / 2));
  }
}
