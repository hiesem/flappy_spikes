import 'dart:math' as math;
import 'dart:ui';

import '../../game/config.dart';
import '../../skins/art/hoop_painter.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/art/trail.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';

/// Paints [look] for the trail emitters' Afterimage copies.
void paintLookForTrail(Canvas canvas, Look look, double t, bool flap) =>
    LookPainter.paint(canvas, look, t: t, flap: flap);

/// The grid-tile art of every item (the `drawThumb` branch of
/// `design/menu_v2/skin_shop.js`), drawn into a
/// [Config.skinShopArtWidth] x [Config.skinShopArtHeight] box at the origin:
/// birds alone, gear and hats on the grey mannequin, hoops as a ring tilted
/// 10°, trails as a mini trail behind a small glowing orb, "none" as a grey
/// circle-slash.
abstract final class ItemArt {
  static const double w = Config.skinShopArtWidth;
  static const double h = Config.skinShopArtHeight;

  /// Whether [item]'s tile art changes over time when not flapping: the
  /// animated items and every trail. Everything else is drawn once.
  static bool isAnimated(SkinItem item) =>
      !item.isNone && (item.animated || item.layer == SkinLayer.trail);

  /// Where a trail tile's orb is at tile clock [t] (bobbing, `drawThumb`).
  static Offset trailOrb(double t) =>
      Offset(w * .74, h / 2 + math.sin(t * 4) * h * .08);

  /// Advances a trail tile's [emitter] by [dt] at tile clock [t] (emit at
  /// the orb, then age the particles). Done in update so the art does not
  /// depend on the render rate.
  static void advanceTrail(TrailEmitter emitter, double t, double dt) {
    if (dt <= 0) return;
    emitter.emit(trailOrb(t), dt, k: TrailEmitter.tileScale, vx: -90);
    emitter.step(dt);
  }

  /// Draws [item] at tile clock [t]. [flap] (equipped / tried-on birds)
  /// bobs and flaps the bird. Trails need their [emitter], advanced by [dt]
  /// (0 = redraw without emitting).
  static void paint(
    Canvas canvas,
    SkinItem item, {
    double t = 0,
    bool flap = false,
    TrailEmitter? emitter,
    double dt = 0,
  }) {
    if (item.layer == SkinLayer.trail) {
      if (emitter == null) return;
      TrailEmitter.paintTrailTile(canvas, emitter, trailOrb(t), dt, t);
      return;
    }
    canvas.save();
    canvas.translate(w / 2, h / 2);
    if (item.isNone) {
      LookPainter.paintNone(canvas, math.min(w, h) * .24);
    } else {
      switch (item.layer) {
        case SkinLayer.bird:
          final k = math.min(w / 56, h / 44);
          canvas.translate(0, flap ? math.sin(t * 5) * 2 : 0);
          canvas.scale(k);
          LookPainter.paint(
            canvas,
            Look(bird: item.id),
            t: t,
            flap: flap && (t * 5.5) % 1 < .4,
          );
        case SkinLayer.gear:
          final k = math.min(w / 62, h / 52);
          canvas.scale(k);
          LookPainter.paintOnMannequin(canvas, item.layer, item.id, t: t);
        case SkinLayer.hat:
          final k = math.min(w / 62, h / 64);
          canvas.translate(0, h * .13);
          canvas.scale(k);
          LookPainter.paintOnMannequin(canvas, item.layer, item.id, t: t);
        case SkinLayer.hoop:
          HoopPainter.paintHoopTile(canvas, item.id, Offset.zero, h * .34, t);
        // region P26-F9a
        case SkinLayer.card:
          break;
        // endregion
        case SkinLayer.trail:
          break;
      }
    }
    canvas.restore();
  }
}

/// Per-screen cache of tile art: one recorded [Picture] per static item
/// (drawn once, replayed every frame) and one [TrailEmitter] per trail tile,
/// kept across tab switches. [dispose] when the screen goes away.
class ItemArtCache {
  final Map<String, Picture> _pictures = {};
  final Map<String, Picture> _lockedPictures = {};
  final Map<String, TrailEmitter> _emitters = {};

  /// Number of recorded static pictures (tests).
  int get pictureCount => _pictures.length;

  Picture pictureFor(SkinItem item) => _pictures.putIfAbsent(item.key, () {
    final recorder = PictureRecorder();
    ItemArt.paint(Canvas(recorder), item);
    return recorder.endRecording();
  });

  /// [pictureFor] with the locked tiles' 42 % alpha baked in, recorded once:
  /// a settled locked static tile then replays a single picture instead of
  /// compositing a fresh `saveLayer` every frame (§4.3 static-art caching).
  Picture lockedPictureFor(SkinItem item) =>
      _lockedPictures.putIfAbsent(item.key, () {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.saveLayer(
          null,
          Paint()
            ..color = const Color.fromRGBO(
              0,
              0,
              0,
              Config.skinShopLockedOpacity,
            ),
        );
        ItemArt.paint(canvas, item);
        canvas.restore();
        return recorder.endRecording();
      });

  TrailEmitter emitterFor(SkinItem item) => _emitters.putIfAbsent(
    item.key,
    () => TrailEmitter(item.id, lookPainter: paintLookForTrail),
  );

  void dispose() {
    for (final picture in [..._pictures.values, ..._lockedPictures.values]) {
      picture.dispose();
    }
    _pictures.clear();
    _lockedPictures.clear();
    _emitters.clear();
  }
}
