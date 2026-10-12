import 'dart:ui' show Canvas;

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../config/streak_config.dart';
import '../run_layers.dart';
import '../run_scaled_world.dart';
import 'banners.dart';
import 'run_hud.dart';

/// The run's banner layer (PRD-2.2 §12.2): a screen-space layer **in the
/// world** at [RunLayer.banners] (−60). The bird, the hoops, the pickups and
/// the spike strips draw over every banner; the big score circle (−100)
/// stays behind it. It holds the run's one [BannerHost] (streak tiers,
/// FEVER, element and switch banners) and the collect stickers ("BONUS
/// UNLOCKED!", "PICTURE COMPLETE"), which are added to it by the collect
/// layer.
///
/// Timing (PRD-2.2 §12.2): the banners keep real time, so the Hourglass does
/// not slow them (the world runs at `dt × timeScale`, this layer undoes it),
/// and they freeze with the world while the run is paused (the world passes
/// dt 0). Position: the world is moved by the camera shake, so the layer
/// cancels the viewfinder offset and the bands stay screen-anchored at y 190.
/// It follows the HUD: nothing is drawn while the HUD is hidden (a settings
/// or revive-shop screen over the run), and the layer is removed with it.
class RunBannerLayer extends PositionComponent {
  RunBannerLayer({required this.game, required this.hud})
    : super(priority: RunLayer.banners);

  final FlappySpikesGame game;

  /// The HUD of the run this layer belongs to.
  final RunHud hud;

  /// The run's one banner host (PRD-2 §3.0.9 #7): every banner shows here.
  /// Above the collect stickers, as the HUD's band was.
  final BannerHost banners = BannerHost(priority: StreakConfig.bannerPriority);

  @override
  Future<void> onLoad() async {
    add(banners);
  }

  @override
  void updateTree(double dt) {
    // The world passes dt × its time scale (Hourglass); undo it so the
    // banners run in real time. A paused world passes 0, so they freeze.
    final world = parent;
    final scale = world is RunScaledWorld ? world.timeScale : 1.0;
    super.updateTree(scale > 0 ? dt / scale : dt);
  }

  @override
  void renderTree(Canvas canvas) {
    // The game's flags, not `hud.hidden`: the HUD's game reference is only
    // set once it is mounted, and the layer can draw before that.
    if (game.runSettingsOpen || game.reviveShopOpen) return;
    if (!identical(game.run, hud.run)) return;
    // The world is drawn through the camera's viewfinder, which the run's
    // screen shake moves; cancel that offset to keep the bands on screen.
    final offset = game.camera.viewfinder.position;
    canvas.save();
    canvas.translate(offset.x, offset.y);
    super.renderTree(canvas);
    canvas.restore();
  }
}
