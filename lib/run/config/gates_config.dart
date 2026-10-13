import '../elements.dart';
import 'tuning_values.dart';

/// PRD-2.3 §14.6 lifetime unlock gates: an element can appear only once
/// `Storage.gamesPlayed` (every finished run, in every mode) is at least its
/// gate (`gate_*` tuning keys). The in-run rules (from-hoop, weights,
/// first-meet) apply on top; first-meet fires the first time a gate is
/// open (the director only knows the open elements). Not gated: normal,
/// angled and moving hoops (difficulty, §14.4), the squeeze and the home
/// slot (Big Hoops / shield). Pure Dart.
abstract final class GatesConfig {
  /// PRD-2.3 §14.6 the gate key of every gated element.
  static const Map<ElementId, String> keys = {
    ElementId.heart: 'gate_heart',
    ElementId.starTrail: 'gate_star_trail',
    ElementId.bullseye: 'gate_bullseye',
    ElementId.switchRing: 'gate_switch',
    ElementId.train: 'gate_train',
    ElementId.comet: 'gate_comet',
    ElementId.portal: 'gate_portal',
    ElementId.capsule: 'gate_capsule',
    ElementId.hourglass: 'gate_capsule',
    ElementId.miniBird: 'gate_capsule',
    ElementId.coinFrenzy: 'gate_capsule',
    ElementId.shield: 'gate_shield',
    ElementId.spring: 'gate_spring',
    ElementId.pair: 'gate_pair',
    ElementId.egg: 'gate_egg',
    ElementId.feather: 'gate_feather',
    ElementId.puzzlePiece: 'gate_puzzle',
    ElementId.piggy: 'gate_piggy',
    ElementId.piggyCoins: 'gate_piggy',
    ElementId.jar: 'gate_jar',
    ElementId.fireflySwarm: 'gate_jar',
    ElementId.fever: 'gate_fever',
    ElementId.luckySpin: 'gate_lucky_spin',
    ElementId.saw: 'gate_saw',
  };

  /// PRD-2.3 §14.6 the `gamesPlayed` [e] needs (0 = not gated).
  static int gateFor(ElementId e) {
    final k = keys[e];
    return k == null ? 0 : TuningValues.current.i(k);
  }

  /// PRD-2.3 §14.6 whether [e] is open at [gamesPlayed] finished runs.
  static bool isOpen(ElementId e, int gamesPlayed) =>
      gamesPlayed >= gateFor(e);

  /// PRD-2.3 §14.6 [elements] without the ones still gated at
  /// [gamesPlayed]. [keep] (the debug force queue) stays: a debug force
  /// ignores the unlock (§3.0.8), so a forced capsule type keeps its
  /// capsule too.
  static Set<ElementId> filter(
    Set<ElementId> elements,
    int gamesPlayed, {
    Iterable<ElementId> keep = const [],
  }) {
    final kept = {...keep, if (keep.any((e) => e.isCapsuleType)) ElementId.capsule};
    return {
      for (final e in elements)
        if (kept.contains(e) || isOpen(e, gamesPlayed)) e,
    };
  }

  /// PRD-2.3 §14.2 the golden feather / puzzle piece never come in two
  /// runs in a row: [lastRun] is the `gamesPlayed` of the run that last
  /// showed one (`lastFeatherRun` / `lastPieceRun`, −1 = never).
  static bool shownLastRun(int lastRun, int gamesPlayed) =>
      lastRun >= 0 && gamesPlayed - lastRun <= 1;
}
