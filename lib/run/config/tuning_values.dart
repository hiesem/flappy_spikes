// region P26-H
/// The resolved gameplay values the config getters read (pure Dart).
///
/// Audit 17 (2026-10-19): the remote tuning of PRD-2.3 §15 is gone. The
/// values are the baked constants of `tuning_defaults.dart` (= the live
/// Remote Config values of 2026-10-19), with a baked lifetime-only arm
/// overlay at storage load. 2.6 has one arm with no overrides.
/// Tests can pin values with [TuningValues.resolve] (e.g. a 2.3 calibration).
// endregion
library;

// region P26-H
import 'ab_arms.dart';
// endregion
import 'tuning_defaults.dart';
import 'tuning_types.dart';

/// One immutable set of tuning values (key → value + source).
class TuningValues {
  TuningValues._(this._values, this.defs);

  /// The baked values ([kTuningDefaults]).
  factory TuningValues.defaults([List<TuningDef> defs = kTuningDefaults]) =>
      TuningValues._({for (final d in defs) d.key: d.value}, defs);

  /// Tests only: [overrides] (key → value as a string, parsed like the
  /// former Remote Config strings) over the baked values. An unknown key or
  /// a value that does not parse throws, so a typo never passes silently.
  factory TuningValues.resolve(
    Map<String, String> overrides, {
    List<TuningDef> defs = kTuningDefaults,
  }) {
    final known = {for (final d in defs) d.key};
    for (final k in overrides.keys) {
      if (!known.contains(k)) {
        throw ArgumentError.value(k, 'overrides', 'unknown tuning key');
      }
    }
    final values = <String, Object>{};
    for (final d in defs) {
      final raw = overrides[d.key];
      if (raw == null) {
        values[d.key] = d.value;
        continue;
      }
      final v = d.type.parse(raw, d.value);
      if (v == null) {
        throw ArgumentError.value(raw, d.key, 'does not parse as ${d.type}');
      }
      values[d.key] = v;
    }
    return TuningValues._(values, defs);
  }

  // region P26-H
  /// The set the game reads: baked defaults plus the stored arm at load.
  /// Tests can assign a pinned baseline before applying the arm.
  static TuningValues current = TuningValues.defaults();

  /// Overlay a baked arm on this baseline (including explicit test pins).
  TuningValues withArm(String arm) =>
      withArmOverrides(AbArms.overridesFor(arm));

  /// The only arm overlay entry point: reject forbidden, unknown and malformed
  /// keys before changing any values. Mission rewards are deliberately excluded.
  TuningValues withArmOverrides(Map<String, String> overrides) {
    AbArms.validate(overrides);
    if (overrides.isEmpty) return this;
    final parsed = TuningValues.resolve(overrides, defs: defs);
    return TuningValues._({
      ..._values,
      for (final key in overrides.keys) key: parsed.raw(key),
    }, defs);
  }
  // endregion

  final Map<String, Object> _values;

  /// Every key, in [kTuningDefaults] order.
  final List<TuningDef> defs;

  final Map<String, Keyframes> _curves = {};

  Object _get(String key) {
    final v = _values[key];
    if (v == null) throw ArgumentError.value(key, 'key', 'unknown tuning key');
    return v;
  }

  /// The raw value of [key] (tests).
  Object raw(String key) => _get(key);

  /// An int value.
  int i(String key) => (_get(key) as num).toInt();

  /// A double value.
  double d(String key) => (_get(key) as num).toDouble();

  /// A bool value.
  bool b(String key) => _get(key) as bool;

  /// A list of ints.
  List<int> ints(String key) => [for (final x in _get(key) as List) x as int];

  /// An inclusive int range stored as `[min, max]`.
  (int, int) range(String key) {
    final l = ints(key);
    return (l[0], l[1]);
  }

  /// A keyframe table (parsed once per set).
  Keyframes curve(String key) => _curves[key] ??= Keyframes([
    for (final p in _get(key) as List) [for (final x in p as List) x as num],
  ]);

  /// An object (spawn row, weight table): name → number.
  Map<String, num> obj(String key) => {
    for (final e in (_get(key) as Map).entries) e.key as String: e.value as num,
  };
}

/// Short alias for the config getters: `tuning.i('coin_jar')`.
TuningValues get tuning => TuningValues.current;
