import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 6, Up the book's pages (Candy Land → Paper Origami; `slabBook` + `pieceWrappers`).
///
/// STUB (WP-W2 ports the slab and the piece): the move's numbers are the
/// prototype's (`LINKS[5]`), the floor draws nothing yet.
class BookSeam extends FloorSeam {
  const BookSeam();

  @override
  String get title => 'Up the book\'s pages';
  @override
  int get dir => -1;
  @override
  double get yF => 540;
  @override
  double get thickness => 250;
  @override
  double get hang => 130;
  @override
  double get travel => 960;

  @override
  void slab(Ctx c, SeamFrame s) {}

  /// `g(S)`: the paper peaks pop up from the page (`fold`).
  @override
  double? fold(SeamFrame s) => smooth((s.u - .55) / .35);
}
