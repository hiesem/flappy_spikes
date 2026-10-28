/// PRD-2.2 §2 the Home mode button: VERSUS (the default, a real player's
/// run as the opponent) or FREE FLY (a solo run, no opponent).
enum HomeMode {
  versus('versus', 'versus'),
  freeFly('freeFly', 'free_fly');

  const HomeMode(this.key, this.analytics);

  /// The `homeMode` storage value.
  final String key;

  // region P26-G5a
  /// Home-mode analytics (`mode_changed.mode`, `run_start.mode`). Weekly
  /// course starts report `weekly` independently of the selected Home mode.
  // endregion
  final String analytics;

  /// The other mode (a tap on the button).
  HomeMode get toggled => this == versus ? freeFly : versus;

  /// The stored [key]; anything unknown (or nothing) is [versus].
  static HomeMode parse(String? key) =>
      key == freeFly.key ? freeFly : versus;
}
