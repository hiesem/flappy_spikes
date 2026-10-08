/// §5.13 hoop miss flash "C · Shock ring" timings (`screen_miss_flash.html`
/// design C). Every member's doc starts with its PRD section (ARCH §4).
abstract final class MissFlashConfig {
  /// §5.13 White flash length (s).
  static const double whiteSeconds = 0.12;

  /// §5.13 White flash stroke (pt).
  static const double whiteStroke = 8;

  /// §5.13 White flash glow blur (pt).
  static const double whiteGlowBlur = 24;

  /// §5.13 Drain to grey: from the end of the flash over this long (s;
  /// 0.12 – 0.52).
  static const double drainSeconds = 0.4;

  /// §5.13 The ghost's opacity once drained (≈ 35 % grey).
  static const double ghostAlpha = 0.35;

  /// §5.13 The ring turns dashed from this fraction of the drain.
  static const double dashFrom = 0.3;

  /// §5.13 Ghost dash (6 pt dash, 6 pt gap).
  static const List<double> dash = [6, 6];
}
