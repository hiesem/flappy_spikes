import '../config/parts_config.dart';

/// The invulnerability flash (ARCH §3 "InvulnFlash", PRD §5.5): after a save
/// (extra life, shield) or the phoenix rise the bird blinks between 100 % and
/// 25 % opacity every 0.1 s for 2 s, starting at 100 %. Pure timing — the
/// owner feeds [opacity] to the bird's `LookComponent.opacity`.
class InvulnFlash {
  InvulnFlash({this.length = PartsConfig.invulnDuration});

  /// Total flash time (s).
  final double length;

  double _t = 0;
  bool _running = false;

  bool get running => _running;
  double get time => _t;

  void start() {
    _t = 0;
    _running = true;
  }

  void stop() => _running = false;

  void update(double dt) {
    if (!_running) return;
    _t += dt;
    if (_t >= length) _running = false;
  }

  /// The bird opacity now (1 when not running).
  double get opacity => opacityAt(_running ? _t : length);

  /// Opacity at [t] seconds after the start.
  double opacityAt(double t) {
    if (t < 0 || t >= length) return 1;
    return (t / PartsConfig.invulnStep).floor().isOdd ? PartsConfig.invulnLow : 1;
  }
}
