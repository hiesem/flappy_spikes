import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';
import 'ui/fadable_text.dart';
import 'ui/sprite_button.dart';

/// Start scene UI: title sprite, best/games labels, settings button and the
/// leaderboard button. (The privacy-policy link moved to the settings screen
/// on 2026-07-22.)
///
/// Setters are safe to call before [onLoad] has run: values are stored and
/// applied once the children exist.
class StartPanel extends PositionComponent implements OpacityProvider, Tintable {
  StartPanel({
    required this.onOpenSettings,
    required this.onLeaderboard,
    required this.bestScore,
    required this.gamesPlayed,
  }) : super(priority: 20);

  final void Function() onOpenSettings;
  final void Function() onLeaderboard;
  int bestScore;
  int gamesPlayed;

  late final SpriteComponent _title;
  late final FadableTextComponent _bestLabel;
  late final FadableTextComponent _gamesLabel;
  late final SpriteButton _settingsButton;
  late final SpriteButton _gameCenterButton;

  double _opacity = 1;
  Color _tint = const Color(0xFF828282);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final images = findGame()!.images;
    final centerY = (findGame()! as FlappySpikesGame).viewHeight / 2;

    _title = SpriteComponent(
      sprite: Sprite(await images.load('title.png')),
      size: Config.titleSize,
      position: Config.titlePositionFor(centerY),
      anchor: Anchor.center,
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
    _settingsButton = SpriteButton(
      sprite: Sprite(await images.load('settings_gear.png')),
      size: Config.settingsButtonSize,
      position: Config.settingsButtonPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onOpenSettings,
    );
    _gameCenterButton = SpriteButton(
      sprite: Sprite(await images.load('gamcenter.png')),
      size: Config.gameCenterButtonSize,
      position: Config.gameCenterButtonPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onLeaderboard,
    );
    addAll([
      _title,
      _bestLabel,
      _gamesLabel,
      _settingsButton,
      _gameCenterButton,
    ]);
    _apply();
  }

  void _apply() {
    _bestLabel.text = 'Best Score: $bestScore';
    _gamesLabel.text = 'Games Played: $gamesPlayed';
    _title.opacity = _opacity;
    _bestLabel.opacity = _opacity;
    _gamesLabel.opacity = _opacity;
    _settingsButton.opacity = _opacity;
    _gameCenterButton.opacity = _opacity;
    _title.paint.colorFilter = ColorFilter.mode(_tint, BlendMode.modulate);
    _bestLabel.setColor(_tint);
    _gamesLabel.setColor(_tint);
  }

  void setStats({required int bestScore, required int gamesPlayed}) {
    this.bestScore = bestScore;
    this.gamesPlayed = gamesPlayed;
    if (isLoaded) {
      _bestLabel.text = 'Best Score: $bestScore';
      _gamesLabel.text = 'Games Played: $gamesPlayed';
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (isLoaded) {
      _title.paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
      _bestLabel.setColor(color);
      _gamesLabel.setColor(color);
    }
  }

  @override
  double get opacity => _opacity;

  @override
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    if (isLoaded) {
      _title.opacity = _opacity;
      _bestLabel.opacity = _opacity;
      _gamesLabel.opacity = _opacity;
      _settingsButton.opacity = _opacity;
      _gameCenterButton.opacity = _opacity;
    }
  }
}
