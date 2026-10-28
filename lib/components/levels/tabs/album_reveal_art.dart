import 'dart:ui';
import 'package:flame/components.dart';
import '../../../game/config.dart';
import '../../../run/config/puzzle_config.dart';
import '../../../run/pickups/puzzle_piece_pickup.dart';
import '../../../run/screens/results_screen.dart';

/// Album presentation: the existing puzzle pictures and results ray master.
class AlbumRevealArt extends PositionComponent {
  AlbumRevealArt({required this.reduceMotion});
  final bool Function() reduceMotion;
  double time = 0;
  @override
  void update(double dt) {
    super.update(dt);
    if (!reduceMotion()) time += dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, Config.p1PopupWidth, 385));
    ResultsScreen.paintCardStickerRays(
      canvas,
      const Offset(Config.p1PopupWidth / 2, 160),
      160,
      time,
    );
    canvas.restore();
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(20 + i * 34.0, 61);
      canvas.scale(.48);
      for (var k = 0; k < 4; k++) {
        PuzzleArt.paintPiece(canvas, k, PuzzleConfig.themes[i]);
      }
      canvas.drawRect(
        const Rect.fromLTWH(-25, -25, 50, 50),
        Paint()
          ..color = Config.menuGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.restore();
    }
  }
}
