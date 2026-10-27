import 'dart:math';

/// PRD-2.6 WP-H: baked, device-assigned arms; never a remote switch.
abstract final class AbArms {
  /// One arm until an experiment has >= 1,500 new installs per arm.
  /// Values use the same strict parsing as other tuning overrides.
  static const profiles = <String, Map<String, String>>{'0': {}};

  static const allowedPrefixes = [
    'showcase_',
    'ads_grace_',
    'ads_interstitial_',
    'ui_unlock_',
    'mission_target_',
  ];
  static const allowedKeys = {'gate_saw', 'gate_squeeze', 'rate_min_runs'};
  static const forbiddenPrefixes = [
    'curve_',
    'point_',
    'spawn_',
    'squeeze_',
    'ride_',
    'coin_',
    'revive_',
    'hazard_',
    'calm_',
    'level_',
  ];

  static bool allows(String key) =>
      !forbiddenPrefixes.any(key.startsWith) &&
      (allowedKeys.contains(key) || allowedPrefixes.any(key.startsWith));

  /// Checked in release builds too, before any value reaches the config.
  static void validate(Map<String, String> overrides) {
    for (final key in overrides.keys) {
      if (!allows(key)) {
        throw ArgumentError.value(key, 'arm override', 'not a lifetime key');
      }
    }
  }

  /// Called only for an unassigned install, even when there is just one arm.
  static String draw({Random? random}) {
    final arms = profiles.keys.toList(growable: false);
    return arms[(random ?? Random.secure()).nextInt(arms.length)];
  }

  /// Keep unknown stored ids (e.g. a downgrade), using the control values.
  static Map<String, String> overridesFor(String arm) =>
      profiles[arm] ?? profiles['0']!;
}
