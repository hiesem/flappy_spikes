import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// A band → vertical offset (pt) used when an older move draws a stage.
typedef BandOffset = double Function(Band b);

/// What a seam may ask of the world: draw stage [env]'s [bands], each
/// shifted down by [dy] (`drawGroup(c, cluster(env), …, bands, dy)`).
abstract class SceneDrawer {
  void group(Ctx c, int env, List<Band> bands, [BandOffset? dy]);
}

/// PRD-2.4 §3.3 one of the ten seams (`LINKS[i]`): seam `i + 1` joins
/// scene `i + 1` to scene `i + 2` (scene 10 → scene 1 for seam 10).
sealed class Seam {
  const Seam();

  /// The seam's title in the prototype's list.
  String get title;
}

/// PRD-2.4 §3.3 a floor move (`kind: 'v'`, seams 1–6), drawn by the world's
/// `vmove`: the camera passes through a floor. Going down it is the floor
/// of the scene it leaves, going up the floor of the scene it arrives in.
abstract class FloorSeam extends Seam {
  const FloorSeam();

  /// 1 = the camera sinks, −1 = it rises.
  int get dir;

  /// The floor's top at rest (design y).
  double get yF;

  /// The floor's thickness.
  double get thickness;

  /// How far the floor's underside hangs below it.
  double get hang;

  /// The camera's travel (design; `vmove` adds the extra height of a taller
  /// view so floors and set pieces still clear the screen, PRD §3.3).
  double get travel;

  /// `slab(c, S)`: the floor with its underside.
  void slab(Ctx c, SeamFrame s);

  /// `piece(c, S, band)`: the set piece, called after each band and once
  /// more with [Band.front] after the slab.
  void piece(Ctx c, SeamFrame s, Band band) {}

  /// `g(S)`: the switch the arriving scene is drawn with (seam 6's
  /// `fold`); null = none.
  double? fold(SeamFrame s) => null;
}

/// PRD-2.4 §3.3 an older move (`dive` / `emerge` / `ascend` / `descend`,
/// seams 7–10), centred on the seam over the [kVWIN] window. [q] is the
/// eased progress `smooth((d + VWIN / 2) / VWIN)`.
abstract class OlderSeam extends Seam {
  const OlderSeam();

  void move(Ctx c, SceneDrawer w, int ga, int gb, double q);
}

/// `S` of the prototype's `vmove`: the state of one floor move this frame
/// (reused, never allocated per frame).
class SeamFrame {
  /// The window's progress (`u`, < 0 before, > 1 after) and its ease (`q`).
  double u = 0, q = 0;

  /// The camera's travel so far (`Y`) and in all (`D`, view-adjusted).
  double y = 0, travel = 0;

  /// The floor's top and bottom on screen (design y).
  double sT = 0, sB = 0;

  /// The seam's world distance (`sc`), the camera (`cam`) and clock (`t`).
  double sc = 0, cam = 0, t = 0;

  /// The leaving (`A`) and arriving (`B`) stages (absolute indices).
  int a = 0, b = 0;

  /// 1 down, −1 up.
  int dir = 1;

  /// `VV`: the share of the camera's travel each band moves.
  static double vv(Band b) => switch (b) {
        Band.sky => .15,
        Band.far => .35,
        Band.mid => .65,
        Band.near || Band.front => 1,
      };

  /// `oA(b)`: band [b]'s offset in the leaving scene.
  double oA(Band b) => -dir * y * vv(b);

  /// `oB(b)`: band [b]'s offset in the arriving scene.
  double oB(Band b) => dir * (travel - y) * vv(b);

  /// `hx(S, hf, dx)`: a piece's x, anchored to its seam, moving at [hf].
  double hx(double hf, double dx) => kANCH + dx - (cam - sc) * hf;
}
