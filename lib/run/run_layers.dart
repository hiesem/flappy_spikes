import 'package:flame/components.dart';

/// Z constants of a run (ARCH §1.1). World-level priorities: the
/// [RunTrack] layers are direct children of the world so they sort against
/// the bird (10) and the spike strips (−5).
abstract final class RunLayer {
  static const int backdrop = -1000;
  static const int scoreCircle = -100;
  /// PRD-2.2 §12.2: every run banner and the collect stickers, screen-anchored
  /// (`RunBannerLayer`): above the score circle, below the guides and the bird.
  static const int banners = -60;
  static const int guides = -20;
  static const int hoopBack = -10;
  static const int deadBird = -7;
  static const int items = -6;
  static const int strips = -5;
  static const int bird = 10;
  static const int rideCannon = 11;
  static const int hoopFront = 12;
  static const int fx = 15;
}

/// One scrolling layer in track coordinates: x along the course, y = screen
/// y. Its position is (−camX, −camY) (ARCH §0).
class RunTrack extends PositionComponent {
  RunTrack({required super.priority, this.name = ''});

  final String name;

  void follow(double camX, double camY) => position.setValues(-camX, -camY);
}

/// The four track layers of a run.
class RunLayers {
  RunLayers()
    : back = RunTrack(priority: RunLayer.hoopBack, name: 'back'),
      items = RunTrack(priority: RunLayer.items, name: 'items'),
      front = RunTrack(priority: RunLayer.hoopFront, name: 'front'),
      fx = RunTrack(priority: RunLayer.fx, name: 'fx');

  final RunTrack back;
  final RunTrack items;
  final RunTrack front;
  final RunTrack fx;

  List<RunTrack> get all => [back, items, front, fx];

  void follow(double camX, double camY) {
    for (final l in all) {
      l.follow(camX, camY);
    }
  }
}
