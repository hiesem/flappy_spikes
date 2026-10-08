import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../director/plans.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

class _Bumper {
  _Bumper(this.x, this.y, this.s);
  final double x, y, s;
  double lit = -9;
}

/// Pinball machine (PRD-2 §5.12b, `ride_pinball_1/2/3.png`, `rides84.js`
/// #4): a neon table with a violet grid and pink frame, a zig-zag of
/// straight lanes with sharp bounces, seven bumpers that flash white and pop
/// "+500" as the ball passes; the bird spins like a ball. Exit: drop to the
/// flippers, the right flipper smacks it into the gold jackpot loop
/// ("JACKPOT!" blinking), up the plunger lane and the plunger fires it out
/// of the table; the table falls away.
class PinballTheme extends RideTheme {
  @override
  RideId get id => RideId.pinball;

  static const List<double> _lanes = [520, 470, 500, 470, 500, 460, 520];

  @override
  RidePath buildPath() => RidePath.segments(const [
    RideSeg.arc(40, -70),
    RideSeg.line(520),
    RideSeg.arc(34, 125),
    RideSeg.line(470),
    RideSeg.arc(34, -130),
    RideSeg.line(500),
    RideSeg.arc(34, 135),
    RideSeg.line(470),
    RideSeg.arc(34, -130),
    RideSeg.line(500),
    RideSeg.arc(34, 130),
    RideSeg.line(460),
    RideSeg.arc(34, -125),
    RideSeg.line(520),
    RideSeg.arc(40, 60),
    RideSeg.line(300),
  ]);

  @override
  (Color, Color) get washTint => (const Color(0xFFD3CFF3), const Color(0xFFE8D8F3));

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.bumper: Sfx.rdPinBumper,
    RideCue.flipper: Sfx.rdPinFlipper,
    RideCue.jackpot: Sfx.rdPinJackpot,
    RideCue.plunger: Sfx.rdPinPlunger,
  };

  @override
  bool get spin => true;

  @override
  bool get exitFill => true;

  @override
  double get exitDuration => 2.0;

  @override
  double get worldFadeIn => 1.2;

  @override
  Offset launchPoint(RideView v) => const Offset(281, 150);

  final List<_Bumper> _bumps = [];

  @override
  void init(RideView v) {
    var s = 40 * 70 * math.pi / 180;
    for (final l in _lanes) {
      s += l;
      final p = v.path.at(s + 30), h = v.path.headingAt(s + 30);
      _bumps.add(_Bumper(p.x + math.cos(h) * 36, p.y + math.sin(h) * 36, s + 20));
      s += 34 * 130 * math.pi / 180;
    }
  }

  /// The flippers' y (bottom-anchored; 600 at 711).
  double _flipY(RideView v) => v.fromBottom(600);

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    c.drawRect(Rect.fromLTWH(0, 0, v.w, v.h), fillOf(const Color(0xFF141640)));
    final grid = strokeOf(const Color(0x2E7C4DFF), 1);
    final ox = -((cam.x * .6) % 40), oy = -((cam.y * .6) % 40);
    for (var x = ox; x < v.w; x += 40) {
      c.drawLine(Offset(x, 0), Offset(x, v.h), grid);
    }
    for (var y = oy; y < v.h; y += 40) {
      c.drawLine(Offset(0, y), Offset(v.w, y), grid);
    }
    c.drawRect(
      Rect.fromLTWH(10, 64, v.w - 20, v.h - 128),
      strokeOf(const Color(0xFFFF4FB7), 4),
    );
    for (final b in _bumps) {
      final x = b.x - cam.x, y = b.y - cam.y;
      if (x < -50 || x > v.w + 50 || y < -50 || y > v.h + 50) continue;
      final lit = (1 - (v.rt - b.lit) / .35).clamp(0.0, 1.0);
      final r = 24 + lit * 4;
      c
        ..drawCircle(
          Offset(x, y),
          r,
          fillOf(lit > 0 ? const Color(0xFFFFFFFF) : const Color(0xFFEC008C)),
        )
        ..drawCircle(Offset(x, y), 13, fillOf(const Color(0xFFFFB529)))
        ..drawCircle(Offset(x, y), r, strokeOf(const Color(0xFFFFFFFF), 3));
    }
  }

  @override
  void tick(RideView v, double dt) {
    if (v.phase != RidePhase.ride) return;
    for (final b in _bumps) {
      if (v.s >= b.s && b.lit < 0) {
        b.lit = v.rt;
        v.cue(RideCue.bumper);
        v.blobs.add(
          RideBlob(
            RideBlobKind.text,
            x: b.x - v.cam.x,
            y: b.y - v.cam.y - 30,
            vy: -50,
            life: .8,
            text: '+500',
            color: const Color(0xFFFFB529),
          ),
        );
      }
    }
  }

  @override
  void paintExit(Canvas c, RideView v, double et, Offset off) {
    c.drawRect(Rect.fromLTWH(0, 0, v.w, v.h), fillOf(const Color(0xFF0E1030)));
    c
      ..save()
      ..translate(-off.dx, -off.dy)
      ..drawRect(
        Rect.fromLTWH(10, 64, v.w - 20, v.h - 128),
        fillOf(const Color(0xFF141640)),
      )
      ..drawRect(
        Rect.fromLTWH(10, 64, v.w - 20, v.h - 128),
        strokeOf(const Color(0xFFFF4FB7), 4),
      );
    final smack = et > .55 && et < .75;
    final fy = _flipY(v);
    _flip(c, Offset(100, fy), .45 - (smack ? .7 : 0));
    _flip(c, Offset(220, fy), math.pi - .45 + (smack ? .7 : 0));
    c.drawCircle(const Offset(160, 300), 90, strokeOf(const Color(0xFFFFB529), 6));
    final lane = strokeOf(const Color(0xFF22E6FF), 3);
    c
      ..drawLine(Offset(292, fy + 20), const Offset(292, 90), lane)
      ..drawLine(Offset(270, fy + 20), const Offset(270, 180), lane);
    if (et > .8 && et < 2.0 && (et * 8).floor().isOdd) {
      paintText(
        c,
        'JACKPOT!',
        const Offset(160, 300),
        size: 34,
        color: const Color(0xFFFFB529),
      );
    }
    c.restore();
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    final drop = Offset(226, v.fromBottom(575));
    if (et < .55) {
      final k = easeIn(et / .55);
      return BirdPose(lerpO(v.lastBird, drop, k), rot: et * 20);
    }
    if (et < .8) {
      if (v.once('flipper')) v.cue(RideCue.flipper);
      final k = easeOut((et - .55) / .25);
      return BirdPose(lerpO(drop, const Offset(160, 390), k), rot: et * 20);
    }
    if (et < 1.7) {
      if (v.once('jackpot')) v.cue(RideCue.jackpot);
      final k = (et - .8) / .9, a = math.pi / 2 - k * 2 * math.pi;
      return BirdPose(
        Offset(160 + math.cos(a) * 90, 300 + math.sin(a) * 90),
        rot: -k * 4 * math.pi,
      );
    }
    final k = easeOut((et - 1.7) / .3);
    return BirdPose(lerpO(const Offset(160, 210), const Offset(281, 150), k));
  }

  @override
  void onLaunch(RideView v) => v.cue(RideCue.plunger);

  static void _flip(Canvas c, Offset at, double a) {
    c
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(a)
      ..drawPath(poly(const [0, -8, 70, -3, 70, 3, 0, 8]), fillOf(const Color(0xFFEC008C)))
      ..drawCircle(Offset.zero, 9, fillOf(const Color(0xFFFFB529)))
      ..restore();
  }
}
