import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 5, Giant's Desk (`drawDesk`, "8. Giant's Desk"):
/// windows far behind, a shelf of giant books, letter blocks, pencil cups
/// and spinning tops on the desk, a wind-up train, and the ruler in front.
///
/// The static parts (windows, books, desk top, blocks, cups, ruler) are
/// cached strips (PRD §3.4); the spinning tops and the train are drawn every
/// frame. The tops come from the same tiles as the blocks and cups (same
/// seed, same `r()` order), so splitting them off draws the same picture.
class DeskScene extends BackdropScene {
  const DeskScene();

  @override
  String get name => "Giant's Desk";

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        c.strip(501, cam * .04, (off) {
          each(c, off, 420, 901, (x, r, k) {
            final wx = x + 40;
            const wy = 80.0;
            c.fillStyle = const Color(0xFFF7F7F7);
            c.fillRect(wx, wy, 170, 230);
            c.fillStyle = const Color(0xFFE8E8E8);
            c.fillRect(wx + 83, wy, 4, 230);
            c.fillRect(wx, wy + 113, 170, 4);
            c.strokeStyle = const Color(0xFFE4E4E4);
            c.lineWidth = 6;
            c.strokeRect(wx, wy, 170, 230);
          });
        });
      case Band.far:
        c.strip(502, cam * .06, (off) {
          // a shelf of giant books
          each(c, off, 24, 911, (x, r, k) {
            if (r() < .18) return;
            final w = 16 + r() * 8, h = 150 + r() * 120;
            c.fillStyle = _books[(r() * 3).floor()];
            c.fillRect(x, 470 - h, w, h);
            c.fillStyle = const Color(0xFFDDDDDD);
            c.fillRect(x, 470 - h + 14, w, 3);
            c.fillRect(x, 470 - h + 22, w, 2);
            c.fillRect(x, 452, w, 3);
          });
          c.fillStyle = const Color(0xFFE8E8E8);
          gfillCut(c, 478, kVH + 40 - 478);
          c.fillStyle = const Color(0xFFE3E3E3);
          gfillCut(c, 470, 8);
        });
      case Band.mid:
        final off = cam * .18;
        c.strip(503, off, (off) {
          c.fillStyle = const Color(0xFFDCDCDC);
          gfillCut(c, 506, 100);
          c.fillStyle = const Color(0xFFD3D3D3);
          gfillCut(c, 506, 2);
          each(c, off, 110, 921, (x, r, k) {
            final kind = r(), bx = x + r() * 30;
            if (kind < .38) {
              // letter blocks
              final n = 1 + (r() * 3).floor();
              const s = 30.0;
              for (var i = 0; i < n; i++) {
                final bX = bx + (i % 2) * 6, bY = 506 - s * (i + 1);
                c.fillStyle = const Color(0xFFD3D3D3);
                c.beginPath();
                c.moveTo(bX + s, bY);
                c.lineTo(bX + s + 6, bY - 5);
                c.lineTo(bX + s + 6, bY + s - 5);
                c.lineTo(bX + s, bY + s);
                c.fill();
                c.fillStyle = const Color(0xFFE4E4E4);
                c.beginPath();
                c.moveTo(bX, bY);
                c.lineTo(bX + 6, bY - 5);
                c.lineTo(bX + s + 6, bY - 5);
                c.lineTo(bX + s, bY);
                c.fill();
                c.fillStyle = const Color(0xFFDCDCDC);
                c.fillRect(bX, bY, s, s);
                c.strokeStyle = const Color(0xFFD2D2D2);
                c.lineWidth = 1.2;
                c.strokeRect(bX + 3, bY + 3, s - 6, s - 6);
                _text(c, _letters[(r() * 5).floor()], bX + s / 2, bY + s / 2 + 6,
                    center: true);
              }
            } else if (kind < .62) {
              // pencil cup
              for (var j = 0; j < 3; j++) {
                final l = 90 + r() * 30;
                c.save();
                c.translate(bx + 10 + j * 10, 480);
                c.rotate(-.2 + j * .2);
                c.fillStyle = j.isOdd ? const Color(0xFFE6E6E6) : const Color(0xFFE0E0E0);
                c.fillRect(-3.5, -l, 7, l);
                c.fillStyle = const Color(0xFFEDEDED);
                c.beginPath();
                c.moveTo(-3.5, -l);
                c.lineTo(0, -l - 11);
                c.lineTo(3.5, -l);
                c.fill();
                c.fillStyle = const Color(0xFFC4C4C4);
                c.beginPath();
                c.moveTo(-1.2, -l - 7);
                c.lineTo(0, -l - 11);
                c.lineTo(1.2, -l - 7);
                c.fill();
                c.restore();
              }
              c.fillStyle = const Color(0xFFD8D8D8);
              c.fillRect(bx, 448, 40, 58);
              c.fillStyle = const Color(0xFFD0D0D0);
              c.fillRect(bx - 2, 446, 44, 5);
            }
          });
        });
        // spinning tops (the animated tiles of the same layer)
        each(c, off, 110, 921, (x, r, k) {
          final kind = r(), bx = x + r() * 30;
          if (kind < .62 || kind >= .82) return;
          final tX = bx + 20, ph = t * 6;
          c.save();
          c.translate(tX, 506);
          c.rotate(math.sin(t * 4 + k) * .1);
          c.fillStyle = const Color(0xFFD8D8D8);
          c.beginPath();
          c.moveTo(0, 0);
          c.lineTo(-18, -20);
          c.quadraticCurveTo(0, -27, 18, -20);
          c.closePath();
          c.fill();
          c.strokeStyle = const Color(0xFFCDCDCD);
          c.lineWidth = 2;
          for (var j = 0; j < 3; j++) {
            final a = ph + j * 2.1;
            if (math.cos(a) > 0) {
              final sx = math.sin(a) * 16;
              c.beginPath();
              c.moveTo(sx, -20);
              c.lineTo(sx * .1, -2);
              c.stroke();
            }
          }
          c.fillStyle = const Color(0xFFE2E2E2);
          c.beginPath();
          c.ellipse(0, -20, 18, 5, 0, 0, kTau);
          c.fill();
          c.fillStyle = const Color(0xFFD0D0D0);
          c.fillRect(-2, -32, 4, 12);
          c.restore();
        });
        _train(c, t, cam);
      case Band.near:
        // ruler: mm ticks, numbered every cm
        c.strip(504, cam * .3, (off) {
          c.fillStyle = const Color(0xFFE9E9E9);
          gfillCut(c, 512, 14);
          c.fillStyle = const Color(0xFFCFCFCF);
          each(c, off, 6, 941, (x, r, k) {
            c.fillRect(x, 512, 1, k % 10 == 0 ? 8 : (k % 5 == 0 ? 5 : 3));
            if (k % 10 == 0) _text(c, _numbers[modI(k ~/ 10, 30)], x + 2, 524);
          });
        });
      case Band.front:
        return;
    }
  }

  /// The wind-up train driving along the desk.
  static void _train(Ctx c, double t, double cam) {
    final x = modD(t * 28 - cam * .3, kVW + 700) - 250;
    if (!(x > -40 && x < kVW + 120)) return;
    final wa = (t * 28 - cam * .3) / 5;
    void wheel(double wx, double wy) {
      c.fillStyle = const Color(0xFFCBCBCB);
      c.circ(wx, wy, 5);
      c.strokeStyle = const Color(0xFFE2E2E2);
      c.lineWidth = 1;
      c.beginPath();
      c.moveTo(wx - math.cos(wa) * 4, wy - math.sin(wa) * 4);
      c.lineTo(wx + math.cos(wa) * 4, wy + math.sin(wa) * 4);
      c.stroke();
    }

    for (var j = 0; j < 4; j++) {
      final age = modD(t * 1.2 + j / 4, 1);
      c.globalAlpha = 1 - age;
      c.fillStyle = const Color(0xFFFAFAFA);
      c.strokeStyle = const Color(0xFFE0E0E0);
      c.lineWidth = 1;
      c.beginPath();
      c.arc(x + 29 - age * 18, 466 - age * 34, 3 + age * 6, 0, kTau);
      c.fill();
      c.stroke();
    }
    c.globalAlpha = 1;
    for (var cx0 = x - 80; cx0 <= x - 40; cx0 += 40) {
      c.fillStyle = const Color(0xFFD8D8D8);
      c.beginPath();
      c.roundRect(cx0 + 2, 484, 34, 14, 2);
      c.fill();
      wheel(cx0 + 10, 501);
      wheel(cx0 + 28, 501);
    }
    c.fillStyle = const Color(0xFFD2D2D2);
    c.beginPath();
    c.roundRect(x, 480, 34, 18, 3);
    c.fill();
    c.fillRect(x, 468, 14, 14);
    c.fillRect(x + 25, 469, 6, 11);
    c.fillStyle = const Color(0xFFE6E6E6);
    c.fillRect(x + 3, 471, 8, 6);
    wheel(x + 8, 501);
    wheel(x + 26, 501);
    c.globalAlpha = 1;
  }

  static const List<Color> _books = [
    Color(0xFFE7E7E7),
    Color(0xFFE2E2E2),
    Color(0xFFEAEAEA),
  ];

  static const String _flapy = 'FLAPY';

  /// The block letters (`'600 17px Fredoka'`, #C9C9C9, centred) and the
  /// ruler's numbers (`'600 6px system-ui'`, #CFCFCF, left), laid out once.
  static final List<Paragraph> _letters = [
    for (var i = 0; i < _flapy.length; i++)
      _para(_flapy[i], 17, const Color(0xFFC9C9C9), 'Fredoka'),
  ];
  static final List<Paragraph> _numbers = [
    for (var i = 0; i < 30; i++) _para('$i', 6, const Color(0xFFCFCFCF), null),
  ];

  static Paragraph _para(String s, double size, Color col, String? family) {
    final b = ParagraphBuilder(ParagraphStyle(fontFamily: family))
      ..pushStyle(TextStyle(
        color: col,
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFamily: family,
      ))
      ..addText(s);
    return b.build()..layout(const ParagraphConstraints(width: double.infinity));
  }

  /// `fillText(s, x, y)` with the baseline at [y] (text drawn in the
  /// paragraph's own colour; the scene never fades it).
  static void _text(Ctx c, Paragraph p, double x, double y, {bool center = false}) {
    final w = p.maxIntrinsicWidth;
    c.canvas.drawParagraph(p, Offset(center ? x - w / 2 : x, y - p.alphabeticBaseline));
  }
}
