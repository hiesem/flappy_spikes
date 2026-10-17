import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';

/// Audit HIDE (2026-10-17, owner rule): everything worn on or following the
/// run bird hides while the bird is hidden and is back exactly when the bird
/// is. The one signal is [Bird.presented] (via
/// [FlappySpikesGame.runBirdPresented]): the bird art's drawn opacity > 0.
/// Every source of a hidden bird lands there — a portal ride's
/// `placeRide(hidden:)` (cannon barrel, volcano, space rocket: exit and the
/// projectile part of the flight), the Black Hole swallow, the phoenix's
/// no-body start — so attachments never test ride phases themselves.
///
/// Mix this into every component drawn relative to the bird:
/// * a component that is wholly worn (heart badge, shield ring) keeps
///   [hidesWholly] true and its whole subtree is skipped while the bird is
///   hidden;
/// * a component that also draws free parts (particles already left behind,
///   a departing chick, hourglass ghosts) sets [hidesWholly] false and gates
///   its worn parts — and any emission at the bird — with [birdPresented].
///
/// Only visibility follows the bird; positions, timers and state keep
/// running, so an attachment comes back exactly where and as it would be.
mixin BirdAttachment on Component {
  /// The game whose run bird this is worn on (null: no run, hidden).
  FlappySpikesGame? get birdGame;

  /// Whether the bird — and so this attachment — is drawn this frame.
  bool get birdPresented => birdGame?.runBirdPresented ?? false;

  /// True: nothing of this component draws while the bird is hidden.
  bool get hidesWholly => true;

  @override
  void renderTree(Canvas canvas) {
    if (hidesWholly && !birdPresented) return;
    super.renderTree(canvas);
  }
}
