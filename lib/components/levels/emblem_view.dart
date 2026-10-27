import 'dart:async';
import 'dart:ui';

import 'package:flutter/painting.dart' show AssetImage, ImageConfiguration;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'package:flame/components.dart';

import '../../levels/emblem_painter.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/look.dart';

/// Records [EmblemPainter.paint] (plus an optional static [look] on top)
/// into a [Picture], in emblem art units with the plate centre at the
/// origin. The bird is drawn at [birdScale] art units per bird art unit
/// with its art-box centre on the plate centre (build74 `paintEmb`).
/// [progression] opts into track art; existing callers keep the legacy ranks.
Picture recordEmblem(
  int level, {
  double t = 0,
  bool shine = false,
  bool grey = false,
  Look? look,
  double birdScale = 1.4,
  bool reduceMotion = false,
  bool progression = false,
  Image? image,
}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  if (progression) {
    EmblemPainter.paintTrack(
      canvas,
      level,
      t: t,
      shine: shine,
      grey: grey,
      reduceMotion: reduceMotion,
      image: image,
    );
  } else {
    EmblemPainter.paint(
      canvas,
      level,
      t: reduceMotion ? 0 : t,
      shine: shine && !reduceMotion,
      grey: grey,
    );
  }
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
/// [t] is advanced by the owner (frozen while paused). [reduceMotion] and
/// the OS preference disable all idle motion. Static frames use cached
/// pictures; PNGs load once per slot and share the painter's idle layers.
/// [progression] opts into the track renderer; the default keeps legacy ranks.
/// The equipped bird remains a separate LookComponent on the plate centre.
class EmblemView extends PositionComponent {
  EmblemView({
    required int level,
    required this.artScale,
    this.grey = false,
    this.shine = true,
    this.reduceMotion = false,
    this.progression = false,
    this.imageLoader,
    super.position,
    super.priority,
  }) : _level = level; // ignore: prefer_initializing_formals

  int _level;
  double artScale;
  bool grey;

  /// Whether the plate light sweep runs (off under reduce motion).
  bool shine;

  // region P26-J7
  /// Explicit still state plus the OS reduced-motion preference.
  bool reduceMotion;

  /// Opt into the cumulative 32-slot track (PRD-2.6 §8.3-16). Existing
  /// ten-rank callers retain their original art and animation until J2.
  final bool progression;
  bool get _still =>
      reduceMotion ||
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Optional asset source for tests / hosts. Returned images belong to the
  /// source, and must outlive the view; the default source caches for app life.
  final Future<Image?> Function(int slot)? imageLoader;
  Image? _image;
  Future<void>? _imageReady;

  /// Completes after the current asset attempt. The fallback can mount and
  /// render while this is pending; exports/tests may explicitly wait for it.
  Future<void> get imageReady => _imageReady ?? Future<void>.value();
  int _imageRequest = 0;
  bool _removed = false;
  bool _started = false;
  static final Map<int, Future<Image?>> _images = {};
  static Future<AssetManifest>? _manifest;

  /// Shared by off-screen exports and Flame views. Images live for app life.
  static Future<Image?> loadImageForLevel(int level) =>
      _loadImage(EmblemPainter.slotFor(level));

  static Future<Image?> _loadImage(
    int slot,
  ) => _images.putIfAbsent(slot, () async {
    final path = EmblemPainter.assetFor(slot);
    if (path == null) return null;
    try {
      final manifest = await (_manifest ??= AssetManifest.loadFromAssetBundle(
        rootBundle,
      ));
      if (!manifest.listAssets().contains(path)) return null; // J13 fallback.
      final key = await AssetImage(path).obtainKey(
        ImageConfiguration(
          devicePixelRatio:
              PlatformDispatcher.instance.views.firstOrNull?.devicePixelRatio ??
              1,
        ),
      );
      final bytes = await key.bundle.load(key.name);
      final codec = await instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null; // Missing / corrupt art never hides the player's emblem.
    }
  });

  Future<void> _resolveImage() async {
    final request = ++_imageRequest;
    final slot = EmblemPainter.slotFor(_level);
    Image? image;
    try {
      image = slot == 0 ? null : await (imageLoader ?? _loadImage)(slot);
    } catch (_) {
      image = null;
    }
    if (_removed || request != _imageRequest) return;
    _image = image;
    _dropFrozen();
    _lastT = null;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _started = true;
    // Mount the fallback immediately. Asset I/O must never hold up later
    // siblings (including tap targets) in Flame's lifecycle queue.
    if (progression) unawaited(_imageReady = _resolveImage());
  }
  // endregion

  /// Animation clock (s).
  double t = 0;

  /// Extra scale (the LEVEL UP upgrade pop).
  double popScale = 1;

  /// The level drawn (0 = unranked).
  int get level => _level;
  set level(int value) {
    if (value == _level) return;
    _level = value;
    _image = null;
    _dropFrozen();
    _lastT = null;
    _imageRequest++;
    if (_started && progression) unawaited(_imageReady = _resolveImage());
  }

  /// Static pictures (t = 0, no sweep) per (level, grey, progression), shared
  /// by every view: the painter's shapes are deterministic.
  static final Map<(int, bool, bool), Picture> _static = {};

  Picture? _frozen;
  double? _frozenT;
  bool _frozenShine = false;
  bool _frozenGrey = false;
  Image? _frozenImage;
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
    _removed = true;
    _imageRequest++;
    _dropFrozen();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final scale = artScale * popScale;
    if (scale <= 0) return;
    canvas.save();
    canvas.scale(scale);
    final clock = _still ? 0.0 : t;
    final sweep =
        !_still &&
        shine &&
        EmblemPainter.sweeps(_level) &&
        EmblemPainter.sweepActive(clock);
    final animated =
        !_still &&
        (progression
            ? EmblemPainter.trackAnimates(_level)
            : EmblemPainter.animates(_level));
    if (!sweep && !animated && _image == null) {
      canvas.drawPicture(
        _static.putIfAbsent(
          (
            progression
                ? EmblemPainter.slotFor(_level)
                : _level.clamp(0, EmblemPainter.maxLevel),
            grey,
            progression,
          ),
          () => recordEmblem(
            _level,
            grey: grey,
            reduceMotion: true,
            progression: progression,
          ),
        ),
      );
      _drewCached = true;
    } else if (clock == _lastT) {
      if (_frozen == null ||
          _frozenT != clock ||
          _frozenShine != sweep ||
          _frozenGrey != grey ||
          _frozenImage != _image) {
        _dropFrozen();
        _frozen = recordEmblem(
          _level,
          t: clock,
          shine: sweep,
          grey: grey,
          reduceMotion: _still,
          image: _image,
          progression: progression,
        );
        _frozenT = clock;
        _frozenShine = sweep;
        _frozenGrey = grey;
        _frozenImage = _image;
      }
      canvas.drawPicture(_frozen!);
      _drewCached = true;
    } else {
      if (progression) {
        EmblemPainter.paintTrack(
          canvas,
          _level,
          t: clock,
          shine: sweep,
          grey: grey,
          reduceMotion: _still,
          image: _image,
        );
      } else {
        EmblemPainter.paint(canvas, _level, t: clock, shine: sweep, grey: grey);
      }
      _drewCached = false;
    }
    _lastT = clock;
    canvas.restore();
  }
}
