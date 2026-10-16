import 'backdrop_ctx.dart';

/// PRD-2.4 §3.3 the four bands of a scene, drawn back to front, plus
/// [front]: the pass a seam's set pieces get after the slab (`'front'` in
/// the prototype; scenes never draw it).
enum Band {
  sky,
  far,
  mid,
  near,
  front;

  /// The four scene bands in drawing order (`BANDS`).
  static const List<Band> layers = [sky, far, mid, near];
}

/// PRD-2.4 §3.3 One of the ten scenes: a port of one `draw<Scene>` function
/// of `docs/p24/endless_vertical.html`. [draw] paints one band in design
/// coordinates (320 × 568; the screen top is `c.yTop`), reading the camera,
/// clock and stage from [Ctx]. A scene is stateless; caches it builds once
/// (paths, pictures) may live in fields.
abstract class BackdropScene {
  const BackdropScene();

  /// The scene's name (PRD §3.3 list).
  String get name;

  /// Paints [band] (one of [Band.layers]).
  void draw(Ctx c, Band band);
}

/// A scene not ported yet: draws nothing over the plain sky (the
/// backdrop's base fill), so the world still runs while WP-W2 / WP-W3 fill
/// it in.
class StubScene extends BackdropScene {
  const StubScene(this.name);

  @override
  final String name;

  @override
  void draw(Ctx c, Band band) {}
}
