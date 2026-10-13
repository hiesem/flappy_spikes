/// PRD-2.3 §15.2 the resolved tuning values the game reads (pure Dart).
///
/// [TuningValues.current] is the set the config getters read. The `Tuning`
/// service (`lib/services/tuning.dart`) sets it once at startup (after
/// Remote Config's `activate()`) and again at every run start
/// (`Tuning.beginRun`), so a value never changes during a run. Without
/// `FS_TUNING` it stays [TuningValues.defaults] (the in-app defaults of
/// `tuning_defaults.dart`).
library;

import 'tuning_defaults.dart';
import 'tuning_types.dart';

/// PRD-2.3 §15.4 where an active value came from.
enum TuningSource {
  /// From the console (Remote Config).
  remote('remote'),

  /// No remote value: the in-app default.
  defaultValue('default'),

  /// A remote value was rejected (wrong type, broken JSON): the default.
  rejected('default*');

  const TuningSource(this.label);

  /// The TUNING page label.
  final String label;
}

/// One immutable set of tuning values (key → value + source).
class TuningValues {
  TuningValues._(this._values, this._sources, this.defs);

  /// The in-app defaults ([kTuningDefaults]).
  factory TuningValues.defaults([List<TuningDef> defs = kTuningDefaults]) =>
      TuningValues._(
        {for (final d in defs) d.key: d.value},
        {for (final d in defs) d.key: TuningSource.defaultValue},
        defs,
      );

  /// PRD-2.3 §15.2 "fallback only": [remote] (key → the console's string)
  /// over the defaults. A missing key keeps its default; a wrong type or
  /// broken JSON keeps the default too, marked [TuningSource.rejected] and
  /// reported once through [onReject]. Remote keys the app doesn't know are
  /// ignored. No min/max clamps.
  factory TuningValues.resolve(
    Map<String, String> remote, {
    List<TuningDef> defs = kTuningDefaults,
    void Function(String key, String raw)? onReject,
  }) {
    final values = <String, Object>{};
    final sources = <String, TuningSource>{};
    for (final d in defs) {
      final raw = remote[d.key];
      if (raw == null) {
        values[d.key] = d.value;
        sources[d.key] = TuningSource.defaultValue;
        continue;
      }
      final v = d.type.parse(raw, d.value);
      if (v == null) {
        values[d.key] = d.value;
        sources[d.key] = TuningSource.rejected;
        onReject?.call(d.key, raw);
      } else {
        values[d.key] = v;
        sources[d.key] = TuningSource.remote;
      }
    }
    return TuningValues._(values, sources, defs);
  }

  /// The set the game reads (see the library doc).
  static TuningValues current = TuningValues.defaults();

  final Map<String, Object> _values;
  final Map<String, TuningSource> _sources;

  /// Every key, in [kTuningDefaults] order.
  final List<TuningDef> defs;

  final Map<String, Keyframes> _curves = {};

  Object _get(String key) {
    final v = _values[key];
    if (v == null) throw ArgumentError.value(key, 'key', 'unknown tuning key');
    return v;
  }

  /// The source of [key] (TUNING page).
  TuningSource sourceOf(String key) =>
      _sources[key] ?? TuningSource.defaultValue;

  /// The raw active value of [key] (TUNING page, analytics).
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
