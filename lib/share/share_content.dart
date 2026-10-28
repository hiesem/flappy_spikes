import 'dart:math';

import '../game/config.dart';
import '../skins/look.dart';
import 'share_card.dart';

/// The random picks of PRD-2.3 §2.0 / §2.2 and the [ShareCardData] they
/// produce. Every pick is uniform and independent, with no memory between
/// taps; [random] is injectable so tests can fix it.
class ShareContent {
  ShareContent([Random? random]) : random = random ?? Random();

  final Random random;

  /// The Spotlight card for [score] with the stored [best] (already counting
  /// the run), the equipped [look] and the [name] (§4.1): one of the 5 share
  /// texts (§3.1) and one of the 5 banners (§3.2). Used by the results-page
  /// share button and, with the last score, by the Invite tile.
  ShareCardData spotlight({
    required int score,
    required int best,
    required int level,
    required Look look,
    required String name,
  }) {
    final textIndex = random.nextInt(Config.shareTexts.length);
    final bannerIndex = random.nextInt(Config.shareBanners.length);
    return ShareCardData(
      kind: ShareCardKind.spotlight,
      progression: true,
      score: score,
      best: best,
      level: level,
      look: look,
      name: name,
      banner: Config.shareBanners[bannerIndex],
      bannerId: bannerIndex + 1,
      text: Config.shareTexts[textIndex].replaceAll('{score}', '$score'),
      textId: textIndex + 1,
    );
  }

  /// A new player's invite (§2.2, best = 0): Dodge the spikes or Pick your
  /// bird (1 in 2), one of the 5 banners and one of the 3 new-player texts.
  ShareCardData newcomer({required Look look, required String name}) {
    final kind = random.nextBool() ? ShareCardKind.dodge : ShareCardKind.flock;
    final bannerIndex = random.nextInt(Config.shareBanners.length);
    final textIndex = random.nextInt(Config.inviteTexts.length);
    return ShareCardData(
      kind: kind,
      score: 0,
      best: 0,
      level: 0,
      look: look,
      name: name,
      banner: Config.shareBanners[bannerIndex],
      bannerId: bannerIndex + 1,
      text: Config.inviteTexts[textIndex],
      textId: textIndex + 1,
    );
  }

  /// The Invite tile's card (§2.2): with a best > 0 the Spotlight card of
  /// the last run ([lastScore], or the best when none is stored), else a
  /// new-player card.
  ShareCardData invite({
    required int best,
    required int? lastScore,
    required int level,
    required Look look,
    required String name,
  }) => best > 0
      ? spotlight(
          score: lastScore ?? best,
          best: best,
          level: level,
          look: look,
          name: name,
        )
      : newcomer(look: look, name: name);
}
