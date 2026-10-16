import '../backdrop_ctx.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 5, Falling gumballs (Giant's Desk → Candy Land; `slabDesk` + `pieceGumballs`).
///
/// STUB (WP-W2 ports the slab and the piece): the move's numbers are the
/// prototype's (`LINKS[4]`), the floor draws nothing yet.
class GumballsSeam extends FloorSeam {
  const GumballsSeam();

  @override
  String get title => 'Falling gumballs';
  @override
  int get dir => 1;
  @override
  double get yF => 540;
  @override
  double get thickness => 190;
  @override
  double get hang => 60;
  @override
  double get travel => 830;

  @override
  void slab(Ctx c, SeamFrame s) {}
}
