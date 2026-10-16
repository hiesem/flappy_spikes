import '../backdrop_ctx.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 4, The cuckoo (Clockwork → Giant's Desk; `slabCuckoo` + `pieceCuckoo`).
///
/// STUB (WP-W2 ports the slab and the piece): the move's numbers are the
/// prototype's (`LINKS[3]`), the floor draws nothing yet.
class CuckooSeam extends FloorSeam {
  const CuckooSeam();

  @override
  String get title => 'The cuckoo';
  @override
  int get dir => 1;
  @override
  double get yF => 540;
  @override
  double get thickness => 80;
  @override
  double get hang => 210;
  @override
  double get travel => 870;

  @override
  void slab(Ctx c, SeamFrame s) {}
}
