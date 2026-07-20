import 'dart:ui';

/// Implemented by components that are tinted with the current foreground
/// color (pipes, spike strips, title sprites, score circle).
abstract class Tintable {
  void setTint(Color color);
}
