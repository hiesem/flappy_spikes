import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/puzzle_config.dart';
import '../director/plans.dart';
import '../effects/particle_pool.dart';
import '../effects/pickup_touch_fx.dart';
import '../effects/twinkle.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The puzzle piece kind (PRD-2 §3.16): the director's piece `GapItemPlan`
/// (§3.0.3: once per run in the gap after hoop 14–25, placed like the
/// feather; `extra` = the missing piece 0..3, picked at random) becomes a
/// [PuzzlePiecePickup] in the colours of the open round. What a piece
/// *does* (mask, pill, 4/4 bonus) is `PuzzleFeature` (items/puzzle.dart).
class PuzzlePieceKind extends PickupKind {
  @override
  ElementId get element => ElementId.puzzlePiece;

  @override
  Pickup build(GapItemPlan p, RunContext c) {
    c.s.pieceSpawned = true;
    final extra = p.extra;
    final piece = extra is int ? extra.clamp(0, 3) : 0;
    return PuzzlePiecePickup(
      p,
      c,
      piece: piece,
      theme: PuzzleConfig.themeFor(c.game.storage.puzzleRound),
    );
  }
}

/// §5.15 the puzzle piece in the field: ×2.1, behind it a radial glow and
/// 8 rotating gold rays; bobs, pulses and rocks, with a twinkle every
/// 0.22 s on a 36 pt radius (world pool). A touch plays the shared
/// [PickupTouchFx] (`PickupTouchSpec.puzzlePiece` with the round's body
/// colour). Hit radius 22 (§3.0.3).
class PuzzlePiecePickup extends Pickup {
  PuzzlePiecePickup(
    GapItemPlan p,
    this.c, {
    required this.piece,
    required this.theme,
  }) : super(
         id: ElementId.puzzlePiece,
         hitRadius: PickupRadii.puzzlePiece,
         plan: p,
         position: Vector2(p.trackX, p.y ?? 0),
         size: Vector2.all(2 * PuzzleConfig.glowRadius * 1.15),
       );

  final RunContext c;

  /// Which piece (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right).
  final int piece;
  final PuzzleTheme theme;

  static final _touch = PickupTouchFx.newPool();

  double _t = 0;
  double _spark = 0;

  /// §5.15 idle pose at [t]: (dy, scale, rotation).
  static (double, double, double) poseAt(double t) {
    const tau = 2 * math.pi;
    final bob = PuzzleConfig.bob * math.sin(t * tau * PuzzleConfig.bobHz);
    final s = PuzzleConfig.pickupScale *
        (1 + PuzzleConfig.pulse * math.sin(t * tau * PuzzleConfig.pulseHz));
    final r = PuzzleConfig.rock * math.sin(t * tau * PuzzleConfig.rockHz);
    return (bob, s, r);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _spark -= dt;
    if (_spark <= 0 && !collected) {
      _spark = PuzzleConfig.twinkleEvery;
      final r = c.cosmetic;
      final a = r.nextDouble() * math.pi * 2;
      final size = PuzzleConfig.twinkleMin +
          r.nextDouble() * (PuzzleConfig.twinkleMax - PuzzleConfig.twinkleMin);
      c.run.particles.spawn(
        shape: ParticleShape.twinkle,
        x: position.x + math.cos(a) * PuzzleConfig.twinkleRadius,
        y: position.y + math.sin(a) * PuzzleConfig.twinkleRadius,
        w: size * 2.8,
        color: r.nextBool()
            ? const Color(0xFFFFFFFF)
            : const Color(0xFFFFD54A),
        life: .6,
        spin: 3,
      );
    }
  }

  @override
  void onCollect(RunContext c) {
    c.layers.fx.add(
      _touch.obtain().play(
        Offset(position.x, position.y),
        PickupTouchSpec.puzzlePiece.withBodyColor(theme.body),
        pool: c.run.particles,
        random: c.cosmetic,
      ),
    );
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final (dy, s, r) = poseAt(_t);
    final centre = Offset(size.x / 2, size.y / 2 + dy);
    PuzzleArt.paintRays(canvas, centre, _t, PuzzleConfig.glowRadius);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(r);
    canvas.scale(s);
    PuzzleArt.paintPieceCentred(canvas, piece, theme);
    canvas.restore();
  }
}

/// The 2 × 2 bird picture and its jigsaw cut (§5.15; `collect4.js`
/// `PIECE` / `picture` / `drawPiece` / `rays`). The board is 48 × 48
/// centred on the origin; piece k: column k % 2, row k ~/ 2. The same four
/// clip paths serve every colour round.
abstract final class PuzzleArt {
  static const List<double> _sv = [1, -1], _sh = [-1, 1];

  static void _edge(Path p, double x0, double y0, double x1, double y1, double s) {
    if (s == 0) {
      p.lineTo(x1, y1);
      return;
    }
    final l = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final tx = (x1 - x0) / l, ty = (y1 - y0) / l;
    final nx = ty, ny = -tx;
    final mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    final r = l * PuzzleConfig.tabBulb, h = r * PuzzleConfig.tabDepth * s;
    final ax = mx - tx * r, ay = my - ty * r;
    final bx = mx + tx * r, by = my + ty * r;
    p
      ..lineTo(ax, ay)
      ..cubicTo(
        ax - tx * r * 1.2 + nx * h,
        ay - ty * r * 1.2 + ny * h,
        bx + tx * r * 1.2 + nx * h,
        by + ty * r * 1.2 + ny * h,
        bx,
        by,
      )
      ..lineTo(x1, y1);
  }

  static final List<Path> paths = List.generate(4, (k) {
    final cx = k % 2, cy = k ~/ 2;
    const c = PuzzleConfig.cell;
    final x0 = -c + c * cx, y0 = -c + c * cy, x1 = x0 + c, y1 = y0 + c;
    final p = Path()..moveTo(x0, y0);
    _edge(p, x0, y0, x1, y0, cy == 1 ? -_sh[cx] : 0);
    _edge(p, x1, y0, x1, y1, cx == 0 ? _sv[cy] : 0);
    _edge(p, x1, y1, x0, y1, cy == 0 ? _sh[cx] : 0);
    _edge(p, x0, y1, x0, y0, cx == 1 ? -_sv[cy] : 0);
    return p..close();
  });

  /// The centre of piece [k]'s cell on the board.
  static Offset centreOf(int k) => Offset(
    -PuzzleConfig.cell / 2 + PuzzleConfig.cell * (k % 2),
    -PuzzleConfig.cell / 2 + PuzzleConfig.cell * (k ~/ 2),
  );

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  static Path _poly(List<(double, double)> pts) {
    final p = Path()..moveTo(pts[0].$1, pts[0].$2);
    for (final q in pts.skip(1)) {
      p.lineTo(q.$1, q.$2);
    }
    return p..close();
  }

  static final Path _tail = _poly([(0, 8), (9, 14), (0, 20)]);
  static final Path _wing = _poly([(12, 9), (24, 17), (12, 17)]);
  static final Path _beak = _poly([(36, 14), (44, 20), (36, 26)]);

  /// The whole picture in [t]'s colours: card, two sparkles, the bird.
  static void paintPicture(Canvas canvas, PuzzleTheme t) {
    canvas.drawRect(const Rect.fromLTWH(-26, -26, 52, 52), _fill..color = t.card);
    Twinkle.paint(canvas, const Offset(-15, -15), 10, t.sparkle,
        waist: Twinkle.pickupWaist);
    Twinkle.paint(canvas, const Offset(16, 15), 8, t.sparkle,
        rotation: .4, waist: Twinkle.pickupWaist);
    canvas.save();
    canvas.translate(-1 - 22, 2 - 18);
    canvas.drawPath(_tail, _fill..color = t.wing);
    canvas.drawRect(const Rect.fromLTWH(6, 3, 30, 30), _fill..color = t.body);
    canvas.drawPath(_wing, _fill..color = t.wing);
    canvas.drawRect(
      const Rect.fromLTWH(26, 10, 4, 4),
      _fill..color = const Color(0xFFFFFFFF),
    );
    canvas.drawPath(_beak, _fill..color = t.beak);
    canvas.restore();
  }

  /// Piece [k] on the board (board coordinates): the picture clipped to
  /// its outline, a white 4 pt outline and the 1.1 pt edge line; or, with
  /// [ghost], a silhouette with a [seam] line.
  static void paintPiece(
    Canvas canvas,
    int k,
    PuzzleTheme t, {
    Color? ghost,
    Color? seam,
  }) {
    final p = paths[k];
    if (ghost != null) {
      canvas.drawPath(p, _fill..color = ghost);
      if (seam != null) {
        canvas.drawPath(p, _stroke
          ..color = seam
          ..strokeWidth = PuzzleConfig.seam);
      }
      return;
    }
    canvas.drawPath(p, _stroke
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = PuzzleConfig.outline);
    canvas.save();
    canvas.clipPath(p);
    paintPicture(canvas, t);
    canvas.restore();
    canvas.drawPath(p, _stroke
      ..color = t.edge.withValues(alpha: PuzzleConfig.edgeAlpha)
      ..strokeWidth = PuzzleConfig.edgeLine);
  }

  /// Piece [k] centred on its own cell centre (pickup, flight).
  static void paintPieceCentred(Canvas canvas, int k, PuzzleTheme t) {
    final c = centreOf(k);
    canvas.save();
    canvas.translate(-c.dx, -c.dy);
    paintPiece(canvas, k, t);
    canvas.restore();
  }

  static final Paint _glow = Paint();
  static final Path _ray = Path();

  /// §5.15 the glow (white → gold 35 % → clear, r [radius]) and 8 gold
  /// rays (22 %) turning at 0.6 rad/s.
  static void paintRays(Canvas canvas, Offset c, double t, double radius) {
    _glow.shader = Gradient.radial(
      c,
      radius,
      const [Color(0xF2FFFFFF), Color(0x59FFD54A), Color(0x00FFD54A)],
      const [0, .45, 1],
    );
    canvas.drawCircle(c, radius, _glow);
    _glow.shader = null;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * PuzzleConfig.rayOmega);
    _ray
      ..reset()
      ..moveTo(0, 0)
      ..lineTo(-7, -radius * 1.15)
      ..lineTo(7, -radius * 1.15)
      ..close();
    _fill.color = const Color(0x38FFD54A);
    for (var i = 0; i < 8; i++) {
      canvas.rotate(math.pi / 4);
      canvas.drawPath(_ray, _fill);
    }
    canvas.restore();
  }
}
