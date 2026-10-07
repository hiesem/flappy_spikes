import 'dart:ui';

import 'package:flame/components.dart';

import '../../levels/emblem_painter.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/look.dart';

/// Records [EmblemPainter.paint] (plus an optional static [look] on top)
/// into a [Picture], in emblem art units with the plate centre at the
/// origin. The bird is drawn at [birdScale] art units per bird art unit
/// with its art-box centre on the plate centre (build74 `paintEmb`).
Picture recordEmblem(
  int level, {
  double t = 0,
  bool shine = false,
  bool grey = false,
  Look? look,
  double birdScale = 1.4,
}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  EmblemPainter.paint(canvas, level, t: t, shine: shine, grey: grey);
  if (look != null) {
    canvas.save();
    canvas.scale(birdScale);
    LookPainter.paint(canvas, look);
    canvas.restore();
  }
  return recorder.endRecording();
}

/// One level emblem, drawn with its plate centre on this component's
/// position (size 0, so a parent places it by the plate centre) at
/// [artScale] points per emblem art unit, times [popScale].
///
/// [t] drives the idle animation (pennants, flames, stars, rays, the plate
/// sweep when [shine]); the owner advances it (frozen = paused / reduce
/// motion). Whenever the emblem is visually static — levels 1-6 outside the
/// sweep, or [t] not moving — it draws a cached [Picture] instead of
/// re-running the painter (PRD-home-v3 §11 performance).
class EmblemView extends PositionComponent {
  EmblemView({
    required int level,
    required this.artScale,
    this.grey = false,
    this.shine = true,
    super.position,
    super.priority,
  }) : _level = level; // ignore: prefer_initializing_formals

  int _level;
  double artScale;
  bool grey;

  /// Whether the plate light sweep runs (off under reduce motion).
  bool shine;

  /// Animation clock (s).
  double t = 0;

  /// Extra scale (the LEVEL UP upgrade pop).
  double popScale = 1;

  /// The level drawn (0 = unranked).
  int get level => _level;
  set level(int value) {
    if (value == _level) return;
    _level = value;
    _dropFrozen();
  }

  /// Static pictures (t = 0, no sweep) per (level, grey), shared by every
  /// view: the painter's shapes are deterministic.
  static final Map<(int, bool), Picture> _static = {};

  Picture? _frozen;
  double? _frozenT;
  bool _frozenShine = false;
  double? _lastT;

  /// Whether the last frame was drawn from a cached picture (tests).
  bool get drewCached => _drewCached;
  bool _drewCached = false;

  void _dropFrozen() {
    _frozen?.dispose();
    _frozen = null;
    _frozenT = null;
  }

  @override
  void onRemove() {
    _dropFrozen();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final scale = artScale * popScale;
    if (scale <= 0) return;
    canvas.save();
    canvas.scale(scale);
    final sweep = shine && EmblemPainter.sweepActive(t);
    if (!sweep && !EmblemPainter.animates(_level)) {
      canvas.drawPicture(
        _static.putIfAbsent(
          (_level, grey),
          () => recordEmblem(_level, grey: grey),
        ),
      );
      _drewCached = true;
    } else if (t == _lastT) {
      // Frozen clock (popup / ad on top, reduce motion): one picture of
      // this exact frame.
      if (_frozen == null || _frozenT != t || _frozenShine != sweep) {
        _dropFrozen();
        _frozen = recordEmblem(_level, t: t, shine: sweep, grey: grey);
        _frozenT = t;
        _frozenShine = sweep;
      }
      canvas.drawPicture(_frozen!);
      _drewCached = true;
    } else {
      EmblemPainter.paint(canvas, _level, t: t, shine: sweep, grey: grey);
      _drewCached = false;
    }
    _lastT = t;
    canvas.restore();
  }
}
