import 'dart:ui';

/// PRD-2.2 §33.4 item 6: shared scratch paints for per-frame draw calls,
/// instead of a new `Paint` every frame. A canvas call copies the paint
/// when it is made, so one object can serve every caller in turn; each
/// helper sets every field its callers use (here: only the colour).
final Paint _layer = Paint();
final Paint _fill = Paint();

/// The paint of a `saveLayer` that fades its contents to [alpha].
Paint layerPaint(double alpha) =>
    _layer..color = Color.fromRGBO(0, 0, 0, alpha);

/// A plain fill in [color] (no stroke, shader or filter).
Paint fillPaint(Color color) => _fill..color = color;
