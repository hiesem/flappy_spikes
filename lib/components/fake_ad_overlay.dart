import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../services/ads_service.dart';
import 'home/menu_primitives.dart';

/// Images the fake ad overlay draws (under `assets/images/`).
const List<String> kFakeAdOverlayImages = ['menu/close.png'];

/// Stand-in for a rewarded ad on the Linux / desktop build, where the ads
/// are in-memory fakes that would otherwise complete instantly (see
/// [FlappySpikesGame.showRewardedAd]; never used on mobile or in the
/// default test setup).
///
/// A dark full-screen dim with a menu-style card: pink "TEST AD" header,
/// the placement name, a [Config.fakeAdCountdown] countdown, then
/// "REWARD GRANTED" -> [AdResult.completed]. With [fails] it shows "Ad
/// failed to load" briefly -> [AdResult.failed]. [close] (Esc, the × or a
/// tap on the dim) ends it early: [AdResult.failed] unless the reward was
/// already granted. Swallows every tap so nothing below reacts.
class FakeAdOverlay extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  FakeAdOverlay({required this.placement, required this.fails})
    : super(priority: 950);

  final AdPlacement placement;

  /// Plays the "failed to load" variant.
  final bool fails;

  static const Color dimColor = Color(0xF014141E); // rgba(20,20,30,.94)

  final Completer<AdResult> _result = Completer<AdResult>();
  double _time = 0;
  bool _granted = false;

  /// Completes once the overlay is done (the game then fades it out).
  Future<AdResult> get result => _result.future;

  /// True once the countdown finished (closing now still rewards).
  bool get granted => _granted;

  bool get done => _result.isCompleted;

  /// Big centre text: the countdown digit, "REWARD GRANTED" or the failure.
  late final MenuText message;
  late final MenuButton closeButton;

  final Paint _dimPaint = Paint()..color = dimColor;
  final Paint _cardPaint = Paint()..color = Config.menuSoft;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    final close = Sprite(await game.images.load(kFakeAdOverlayImages[0]));
    final rect = Config.fakeAdCardRectFor(h);
    final w = rect.width;

    final header = RectangleComponent(
      size: Vector2(w, Config.fakeAdHeaderHeight),
      paint: Paint()..color = Config.menuPink,
      children: [
        MenuText(
          'TEST AD',
          fontSize: Config.fakeAdTitleFontSize,
          color: Config.menuSoft,
          letterSpacingEm: 0.14,
          position: Vector2(w / 2, Config.fakeAdHeaderHeight / 2),
          anchor: Anchor.center,
        ),
      ],
    );
    // A stand-in for the real ad UI, which never knocks.
    closeButton = MenuButton(
      color: Config.menuPinkDark,
      position: Vector2(w - Config.noAdsCloseSize, 0),
      size: Vector2.all(Config.noAdsCloseSize),
      onPressed: this.close,
      isActive: () => !done,
      knocks: false,
      children: [
        MenuIcon(
          close,
          size: Vector2.all(18),
          position: Vector2.all(Config.noAdsCloseSize / 2),
          anchor: Anchor.center,
        ),
      ],
    );
    final placementLabel = MenuText(
      placement.analyticsName.toUpperCase(),
      fontSize: Config.fakeAdPlacementFontSize,
      color: Config.menuPlum.withValues(alpha: 0.75),
      letterSpacingEm: 0.1,
      position: Vector2(w / 2, Config.fakeAdHeaderHeight + 14),
      anchor: Anchor.topCenter,
    );
    message = MenuText(
      _messageText,
      fontSize: _messageSize,
      color: _messageColor,
      position: Vector2(w / 2, rect.height / 2 + 16),
      anchor: Anchor.center,
    );
    final hint = MenuText(
      'ESC / × TO CLOSE · NO REWARD',
      fontSize: Config.fakeAdHintFontSize,
      color: Config.menuPlum.withValues(alpha: 0.6),
      letterSpacingEm: 0.06,
      position: Vector2(w / 2, rect.height - 14),
      anchor: Anchor.bottomCenter,
    );
    add(
      RectangleComponent(
        position: rect.topLeft.toVector2(),
        size: rect.size.toVector2(),
        paint: _cardPaint,
        children: [header, closeButton, placementLabel, message, hint],
      ),
    );
  }

  /// Seconds left on the countdown, rounded up (3, 2, 1).
  int get secondsLeft =>
      (Config.fakeAdCountdown - _time).ceil().clamp(0, 1 << 20);

  String get _messageText => fails
      ? 'Ad failed to load'
      : _granted
      ? 'REWARD GRANTED'
      : '$secondsLeft';

  double get _messageSize => fails || _granted
      ? Config.fakeAdMessageFontSize
      : Config.fakeAdCountFontSize;

  // Gold countdown digit; the result lines in pink (gold text on the soft
  // card is too faint at 20 pt).
  Color get _messageColor =>
      fails || _granted ? Config.menuPink : Config.menuGold;

  /// Exposed for tests.
  String get messageText => _messageText;

  @override
  void update(double dt) {
    super.update(dt);
    if (done) return;
    _time += dt;
    if (fails) {
      if (_time >= Config.fakeAdFailHold) _finish(AdResult.failed);
      return;
    }
    if (!_granted && _time >= Config.fakeAdCountdown) {
      _granted = true;
      message.textRenderer = TextPaint(
        style: menuTextStyle(fontSize: _messageSize, color: _messageColor),
      );
    }
    if (isLoaded) message.text = _messageText;
    if (_time >= Config.fakeAdCountdown + Config.fakeAdResultHold) {
      _finish(AdResult.completed);
    }
  }

  /// Closes the ad early (Esc, ×, dim tap).
  void close() => _finish(_granted ? AdResult.completed : AdResult.failed);

  void _finish(AdResult result) {
    if (!done) _result.complete(result);
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _dimPaint);

  @override
  bool containsLocalPoint(Vector2 point) =>
      !done && super.containsLocalPoint(point);

  // Swallow every tap; one on the dim (outside the card) closes the ad.
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    final card = Config.fakeAdCardRectFor(game.viewHeight);
    if (!card.contains(event.localPosition.toOffset())) close();
  }
}
