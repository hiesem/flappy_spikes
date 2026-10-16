import '../backdrop_ctx.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 3, The bell ringer's rope (City Skyline → Clockwork; `slabTimber` + `(none)`).
///
/// STUB (WP-W2 ports the slab and the piece): the move's numbers are the
/// prototype's (`LINKS[2]`), the floor draws nothing yet.
class BellRopeSeam extends FloorSeam {
  const BellRopeSeam();

  @override
  String get title => 'The bell ringer\'s rope';
  @override
  int get dir => -1;
  @override
  double get yF => 540;
  @override
  double get thickness => 70;
  @override
  double get hang => 560;
  @override
  double get travel => 750;

  @override
  void slab(Ctx c, SeamFrame s) {}
}
