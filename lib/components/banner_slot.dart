import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/playfield.dart';

/// PRD-2.2 §7.5.2 / §7.10: the strip under the `GameWidget` in the app
/// shell (`Column(Expanded(game), BannerSlot)`).
///
/// Height 0 while the game's [FlappySpikesGame.bannerState] is
/// [BannerState.off] (menus, NO ADS, no consent); the banner's height in dp
/// during a run. The strip is painted in the spike grey
/// ([FlappySpikesGame.bannerStripColor], §7.5.4) and the ad fades in on it
/// ([Config.bannerFadeIn]) once the bird flies and the banner is loaded.
/// The ad is a native platform view OUTSIDE the game: taps on it never reach
/// the game and game taps never reach it (§7.5.3).
class BannerSlot extends StatelessWidget {
  const BannerSlot({super.key, required this.game});

  final FlappySpikesGame game;

  @override
  Widget build(BuildContext context) {
    final banner = game.monetization.banner;
    return ValueListenableBuilder<BannerState>(
      valueListenable: game.bannerState,
      builder: (context, state, _) {
        final height = banner.heightDp;
        if (state == BannerState.off || height == null) {
          return const SizedBox(width: double.infinity, height: 0);
        }
        return SizedBox(
          width: double.infinity,
          height: height,
          child: ValueListenableBuilder<Color>(
            valueListenable: game.bannerStripColor,
            builder: (context, color, child) =>
                ColoredBox(color: color, child: child),
            child: state == BannerState.showing
                ? ValueListenableBuilder<bool>(
                    valueListenable: banner.loaded,
                    builder: (context, loaded, _) {
                      final ad = loaded ? banner.buildAd() : null;
                      return _FadeIn(
                        visible: ad != null,
                        cover: game.bannerStripColor,
                        child: ad == null
                            ? const SizedBox.shrink()
                            : Center(child: ad),
                      );
                    },
                  )
                : const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// Fades the ad in over [Config.bannerFadeIn]: a strip-grey cover on top
/// of the ad fades out and is then dropped, so the platform view itself is
/// never drawn through an `Opacity` layer.
class _FadeIn extends StatelessWidget {
  const _FadeIn({
    required this.visible,
    required this.child,
    required this.cover,
  });

  final bool visible;
  final Widget child;
  final ValueListenable<Color> cover;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1, end: visible ? 0 : 1),
    duration: Duration(milliseconds: (Config.bannerFadeIn * 1000).round()),
    child: child,
    // One Stack for the whole life of the ad (the platform view is never
    // re-parented); the cover drops out once it is transparent.
    builder: (context, coverOpacity, child) => Stack(
      fit: StackFit.expand,
      children: [
        child!,
        if (coverOpacity > 0)
          IgnorePointer(
            child: ValueListenableBuilder<Color>(
              valueListenable: cover,
              builder: (context, color, _) =>
                  ColoredBox(color: color.withValues(alpha: coverOpacity)),
            ),
          ),
      ],
    ),
  );
}
