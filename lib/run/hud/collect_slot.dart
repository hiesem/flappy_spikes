import 'dart:collection';
import 'dart:ui';

import 'package:flame/components.dart';

import '../effects/easing.dart';
import 'banners.dart';

/// One occupant of the collect slot (the feather tray of §5.14, the puzzle
/// pill of §5.15). The owner draws it; the slot positions and fades it.
abstract class CollectSlotItem {
  /// Seconds after it appears at which the fade-out starts (§3.15 / §3.16:
  /// 2.15 s normally, 3.4 s for the 3rd feather, 4.6 s for the 4th piece).
  double get fadeAt;

  /// Paints the item centred at the origin with [alpha] (0..1). [t] is the
  /// time since it appeared.
  void paint(Canvas canvas, double alpha, double t);

  /// Called when the item has fully faded out.
  void onGone() {}
}

/// The shared HUD collect slot (ARCH §1.10, PRD §3.15 / §3.16, Q37 / Q42):
/// a single place centred at (160, 230) (y ≈ 206–254) where the feather tray
/// and the puzzle pill appear **one at a time**. The second request waits
/// until the first has fully faded; every request also waits while a banner
/// is on the y-190 band ([banners] busy).
///
/// Timeline of an item: fade in 0 → 1 over 0.2 s while sliding down 10 pt
/// (y offset −10 · (1 − eio(alpha))), hold, then from [CollectSlotItem.fadeAt]
/// fade out over 0.3 s sliding back up.
class CollectSlot extends PositionComponent {
  CollectSlot({this.banners, Vector2? centre, super.priority})
    : super(position: centre ?? Vector2(160, 230));

  /// Fade-in time (s).
  static const double fadeIn = .2;

  /// Fade-out time (s).
  static const double fadeOut = .3;

  /// Slide distance (pt).
  static const double slide = 10;

  final BannerHost? banners;
  final Queue<CollectSlotItem> _queue = Queue();
  CollectSlotItem? _item;
  double _t = 0;

  CollectSlotItem? get current => _item;
  int get waiting => _queue.length;
  double get time => _t;

  /// Queues [item]; it shows as soon as the slot and the banner band are
  /// free.
  void request(CollectSlotItem item) {
    _queue.add(item);
    _tryNext();
  }

  /// Alpha of the current item at [t] seconds.
  double alphaAt(CollectSlotItem item, double t) {
    if (t < fadeIn) return (t / fadeIn).clamp(0.0, 1.0);
    if (t < item.fadeAt) return 1;
    return (1 - (t - item.fadeAt) / fadeOut).clamp(0.0, 1.0);
  }

  /// Y offset (pt) for an alpha.
  static double offsetFor(double alpha) => -slide * (1 - Ease.cubicInOut(alpha));

  void _tryNext() {
    if (_item != null || _queue.isEmpty) return;
    if (banners?.busy ?? false) return;
    _item = _queue.removeFirst();
    _t = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final item = _item;
    if (item == null) {
      _tryNext();
      return;
    }
    _t += dt;
    if (_t >= item.fadeAt + fadeOut) {
      _item = null;
      item.onGone();
      _tryNext();
    }
  }

  @override
  void render(Canvas canvas) {
    final item = _item;
    if (item == null) return;
    final a = alphaAt(item, _t);
    if (a <= 0) return;
    canvas.save();
    canvas.translate(0, offsetFor(a));
    item.paint(canvas, a, _t);
    canvas.restore();
  }
}
