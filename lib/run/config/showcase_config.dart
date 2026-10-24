/// PRD-2.6 WP-B constants for the invisible showcase safety net.
///
/// Wave 1 publishes the shared numbers only. No gameplay code reads them yet;
/// WP-B replaces the no-op planner without changing this contract.
abstract final class ShowcaseConfig {
  /// Highlight ids in step order; internal only, never player-facing.
  static const List<String> highlightIds = ['portal', 'comet', 'fever'];

  /// Every showcase run arms Big Hoops and a shield.
  static const List<String> starters = ['bigHoops', 'shield'];

  /// Big Hoops duration in seconds for scripted step 1.
  static const double portalBigHoopsSeconds = 60;

  /// Scripted slot/gap positions by attempt (`1`, `2`, `3+`).
  static const Map<String, Map<String, List<int>>> scripts = {
    'portal': {
      '1': [7],
      '2': [5],
      '3': [3],
    },
    'comet': {
      '1': [9],
      '2': [6],
      '3': [4],
    },
    'fever': {
      '1': [5],
      '2': [4],
      '3': [3],
    },
  };
}
