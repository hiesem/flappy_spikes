/// PRD-2.3 §15.3 the types of the gameplay value table, pure Dart.
///
/// A value has a key (`<group>_<name>`, snake_case), a [TuningType] and its
/// baked value ([TuningDef], listed in `tuning_defaults.dart`). Audit 17
/// removed the Remote Config read: [TuningType.parse] is only used by tests
/// that pin an override (`TuningValues.resolve`).
library;

import 'dart:convert';

/// PRD-2.3 §15.3 the value types.
enum TuningType {
  /// A whole number (`8`).
  integer,

  /// A number (`0.02`, `150`).
  decimal,

  /// `true` / `false`.
  boolean,

  /// A JSON array of ints (`[25,25,50]`): prize lists, ladders, ranges.
  intList,

  /// A keyframe table, a JSON array of `[hoop, value]` pairs with
  /// ascending hoops (`[[1,88],[100,66]]`), see [Keyframes].
  curve,

  /// A JSON object with exactly the keys of its default and number values
  /// (one spawn-table row, a weight table).
  object;

  /// Parses an override string against [fallback] (the default, for the
  /// object's key set). Null = rejected (wrong type, broken JSON).
  Object? parse(String raw, Object fallback) {
    final s = raw.trim();
    try {
      switch (this) {
        case TuningType.integer:
          final v = num.tryParse(s);
          if (v == null || v != v.roundToDouble()) return null;
          return v.toInt();
        case TuningType.decimal:
          return double.tryParse(s);
        case TuningType.boolean:
          return switch (s) {
            'true' => true,
            'false' => false,
            _ => null,
          };
        case TuningType.intList:
          return validate(jsonDecode(s), fallback);
        case TuningType.curve:
          return validate(jsonDecode(s), fallback);
        case TuningType.object:
          return validate(jsonDecode(s), fallback);
      }
    } on FormatException {
      return null;
    }
  }

  /// Checks a decoded JSON value ([v]) and returns it in its canonical Dart
  /// form, or null when it does not fit this type.
  Object? validate(Object? v, Object fallback) {
    switch (this) {
      case TuningType.integer:
        return v is num && v == v.roundToDouble() ? v.toInt() : null;
      case TuningType.decimal:
        return v is num ? v.toDouble() : null;
      case TuningType.boolean:
        return v is bool ? v : null;
      case TuningType.intList:
        if (v is! List) return null;
        final out = <int>[];
        for (final x in v) {
          if (x is! num || x != x.roundToDouble()) return null;
          out.add(x.toInt());
        }
        return out;
      case TuningType.curve:
        if (v is! List || v.isEmpty) return null;
        final out = <List<num>>[];
        num? last;
        for (final p in v) {
          if (p is! List || p.length != 2) return null;
          final h = p[0], y = p[1];
          if (h is! num || y is! num || h != h.roundToDouble()) return null;
          if (last != null && h < last) return null;
          last = h;
          out.add([h.toInt(), y]);
        }
        return out;
      case TuningType.object:
        if (v is! Map || fallback is! Map) return null;
        if (v.length != fallback.length) return null;
        final out = <String, num>{};
        for (final k in fallback.keys) {
          final x = v[k];
          if (x is! num) return null;
          out[k as String] = x;
        }
        return out;
    }
  }
}

/// PRD-2.3 §15.2 one gameplay value: its key, type, baked value, the PRD
/// section it implements and a short description.
class TuningDef {
  const TuningDef(this.key, this.type, this.value, this.section, this.doc);

  /// `<group>_<name>` (§15.3).
  final String key;
  final TuningType type;

  /// The in-app default (int, double, bool, `List<int>`,
  /// `List<List<num>>` or `Map<String, num>`).
  final Object value;

  /// The PRD section (e.g. `14.2`).
  final String section;

  /// One line: what the value is.
  final String doc;
}

/// PRD-2.3 §14.4 / §15.3 a keyframe table `[[hoop, value], …]`: linear
/// between keys, the first value before the first key and the last value
/// after the last key. A step is two keys one hoop apart; a plateau is two
/// keys with the same value.
class Keyframes {
  Keyframes(List<List<num>> pairs)
    : _h = [for (final p in pairs) p[0].toDouble()],
      _v = [for (final p in pairs) p[1].toDouble()];

  final List<double> _h;
  final List<double> _v;

  /// The value at hoop [x].
  double at(num x) {
    final h = x.toDouble();
    if (h <= _h.first) return _v.first;
    if (h >= _h.last) return _v.last;
    for (var k = 1; k < _h.length; k++) {
      if (h <= _h[k]) {
        final a = _h[k - 1], b = _h[k];
        if (b == a) return _v[k];
        return _v[k - 1] + (_v[k] - _v[k - 1]) * (h - a) / (b - a);
      }
    }
    return _v.last;
  }
}
