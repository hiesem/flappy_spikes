import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import 'ui/fadable_text.dart';
import 'ui/sprite_button.dart';

/// Game-over panel: gameover_title, pointsfield with the current score,
/// replay/share/leaderboard buttons, best/games labels. Builds with a
/// staggered fade-in chain (pointsfield 0.2 s, replay 0.2 s, share 0.2 s)
/// while the whole node fades in over 0.5 s. The leaderboard button sits at
/// the right edge of the pointsfield and fades in with it, like the original.
///
/// The title and labels use the fixed UI accent pink (NOT the stage
/// foreground): with the pipe tint they vanished behind the frozen pipes.
class GameOverPanel extends PositionComponent {
  GameOverPanel({
    required this.score,
    required this.bestScore,
    required this.gamesPlayed,
    required this.onReplay,
    required this.onShare,
    required this.onLeaderboard,
  }) : super(priority: 20);

  final int score;
  final int bestScore;
  final int gamesPlayed;
  final void Function() onReplay;
  final void Function() onShare;
  final void Function() onLeaderboard;

  late final SpriteComponent _title;
  late final SpriteComponent _pointsfield;
  late final FadableTextComponent _scoreLabel;
  late final SpriteButton _replayButton;
  late final SpriteButton _shareButton;
  late final SpriteButton _gameCenterButton;
  late final FadableTextComponent _bestLabel;
  late final FadableTextComponent _gamesLabel;

  double _time = 0;
  static const double _totalFade =
      Config.uiFadeDuration + 2 * Config.staggerDuration;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final images = findGame()!.images;
    final centerY = (findGame()! as FlappySpikesGame).viewHeight / 2;
    // Concurrent loads: five sequential cache-hit awaits would need noticeably
    // more event-loop turns before the panel can mount.
    final loaded = await Future.wait([
      images.load('gameover_title.png'),
      images.load('pointsfield.png'),
      images.load('replaybutton.png'),
      images.load('sharebutton.png'),
      images.load('gamecenter_gameover.png'),
    ]);

    _title = SpriteComponent(
      sprite: Sprite(loaded[0]),
      size: Config.titleSize,
      position: Config.titlePositionFor(centerY),
      anchor: Anchor.center,
    );
    _pointsfield = SpriteComponent(
      sprite: Sprite(loaded[1]),
      size: Config.pointsfieldSize,
      position: Config.pointsfieldPositionFor(centerY),
      anchor: Anchor.center,
    );
    _scoreLabel = FadableTextComponent(
      text: '$score',
      style: const TextStyle(
        fontFamily: Config.uiFont,
        fontSize: 45,
        color: Color(0xFFFFFFFF),
      ),
      position: Config.pointsfieldPositionFor(centerY) +
          Vector2(0, Config.scoreLabelNudgeY),
      anchor: Anchor.center,
    );
    _replayButton = SpriteButton(
      sprite: Sprite(loaded[2]),
      size: Config.buttonSize,
      position: Config.replayButtonPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onReplay,
    );
    _shareButton = SpriteButton(
      sprite: Sprite(loaded[3]),
      size: Config.buttonSize,
      position: Config.shareButtonPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onShare,
    );
    _gameCenterButton = SpriteButton(
      sprite: Sprite(loaded[4]),
      size: Config.gameCenterGameoverButtonSize,
      position: Config.gameCenterGameoverButtonPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onLeaderboard,
    );
    _bestLabel = FadableTextComponent(
      text: 'Best Score: $bestScore',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 25),
      position: Config.bestLabelPositionFor(centerY),
      anchor: Anchor.center,
    );
    _gamesLabel = FadableTextComponent(
      text: 'Games Played: $gamesPlayed',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 25),
      position: Config.gamesLabelPositionFor(centerY),
      anchor: Anchor.center,
    );
    addAll([
      _title,
      _pointsfield,
      _scoreLabel,
      _replayButton,
      _shareButton,
      _gameCenterButton,
      _bestLabel,
      _gamesLabel,
    ]);
    _applyAccent();
    _applyFades();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_time < _totalFade) {
      _time += dt;
      _applyFades();
    }
  }

  void _applyFades() {
    final overall = (_time / Config.uiFadeDuration).clamp(0.0, 1.0);
    double stagger(int index) =>
        ((_time - index * Config.staggerDuration) / Config.staggerDuration)
            .clamp(0.0, 1.0);

    _title.opacity = overall;
    _bestLabel.opacity = overall;
    _gamesLabel.opacity = overall;
    _pointsfield.opacity = stagger(0);
    _scoreLabel.opacity = stagger(0);
    _gameCenterButton.opacity = stagger(0);
    _replayButton.opacity = stagger(1);
    _shareButton.opacity = stagger(2);
  }

  /// Applies the UI accent pink to the title sprite and the best/games
  /// labels (constant across color stages). The pointsfield and replay/share
  /// buttons are natively colored already.
  void _applyAccent() {
    _title.paint.colorFilter =
        ColorFilter.mode(Config.uiAccent, BlendMode.modulate);
    _bestLabel.setColor(Config.uiAccent);
    _gamesLabel.setColor(Config.uiAccent);
  }
}
