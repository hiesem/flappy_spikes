/// A minimal manual fade runner: interpolates a value from 0 to 1 over
/// [duration] seconds and reports progress through [onUpdate].
class Fade {
  Fade({
    required this.duration,
    required this.onUpdate,
    this.onComplete,
    this.target,
  });

  final double duration;
  final void Function(double value) onUpdate;
  final void Function()? onComplete;

  /// Optional identity of the object being faded; a new [Fade] on the same
  /// target replaces the old one.
  final Object? target;

  double _time = 0;
  bool done = false;

  void update(double dt) {
    if (done) {
      return;
    }
    _time += dt;
    final value = (_time / duration).clamp(0.0, 1.0);
    onUpdate(value);
    if (value >= 1.0) {
      done = true;
      onComplete?.call();
    }
  }
}
