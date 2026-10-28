import 'dart:io';

// analyzer is a transitive dependency of flutter_test.
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/analysis/utilities.dart';
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/ast/ast.dart';
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flappy_spikes/run/items/analytics_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.6 WP-A2: event names are snake_case and at most 40 characters;
/// every event has at most 25 parameters. `run_fail` has the PRD's 22.
void main() {
  test('WP-K best_beaten is a literal event with its four PRD parameters', () {
    final source = File('lib/run/run_controller.dart').readAsStringSync();
    expect(source, contains("ctx.track('best_beaten', {"));
    for (final key in ['mode', 'hoop', 'best_before', 'games']) {
      expect(source, contains("'$key':"));
    }
    expect(
      _fixture(
        "track('best_beaten', {'mode': 'free_fly', 'hoop': 3, 'best_before': 42, 'games': 1})",
      ),
      isEmpty,
    );
  });

  test('run_fail has exactly the 22 PRD parameters in order', () {
    expect(AnalyticsRouter.failKeys, [
      'hoop',
      'hb',
      'cause',
      'elem',
      'tilt_deg',
      'motion',
      'opening',
      'dy_pt',
      'squeeze_idx',
      'calm',
      'hazard_x10',
      'since_calm',
      'formation',
      'ride_exit',
      'new_elem',
      'outcome',
      'run_no',
      'gb',
      'level',
      'mode',
      'showcase',
      'speed',
    ]);
    expect(AnalyticsRouter.failKeys, hasLength(22));
  });

  test('every analytics call in lib obeys the A2/A3 names and limits', () {
    final sources = <String, String>{
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        file.path: file.readAsStringSync(),
    };
    final audit = _Audit(sources);
    expect(audit.check(), isEmpty);
    // Prevent a broken traversal from silently passing an empty audit.
    expect(audit.events, greaterThan(100));
    expect(audit.properties, greaterThanOrEqualTo(5));
    expect(AnalyticsRouter.hoopKeys.length, lessThanOrEqualTo(25));
    expect(AnalyticsRouter.itemKeys.length, lessThanOrEqualTo(25));
    // run_director_hoops / _items add rim_touches + perfect_pct.
    expect(AnalyticsRouter.hoopKeys.length + 2, lessThanOrEqualTo(25));
    expect(AnalyticsRouter.itemKeys.length, lessThanOrEqualTo(25));
  });

  test('audit catches a planted 26-param map for each event API', () {
    final params = List.generate(
      26,
      (i) => "'key_$i': nested(1, {'x': 2})",
    ).join(',');
    for (final call in [
      "track('valid_event', {$params})",
      "_track('valid_event', <String, Object>{$params})",
      "_analytics('valid_event', {$params})",
      "sdk.logEvent(name: 'valid_event', parameters: {$params})",
      "logEvent('valid_event', {$params})",
    ]) {
      expect(_fixture(call), contains(contains('26 parameters')), reason: call);
    }
    expect(
      _fixture(
        "track('valid_event', {${List.generate(25, (i) => "'k_$i': 0").join(',')}})",
      ),
      isEmpty,
    );
  });

  test('audit validates names and property lengths at the boundaries', () {
    for (final name in [
      'BadName',
      'has__gap',
      'bad-name',
      '1event',
      'x' * 41,
    ]) {
      expect(_fixture("track('$name')"), contains(contains('invalid event')));
    }
    expect(_fixture("track('${'x' * 40}')"), isEmpty);
    expect(_fixture("setUserProperty('${'x' * 24}', '0')"), isEmpty);
    expect(
      _fixture("sdk.setUserProperty(name: '${'x' * 25}', value: '0')"),
      contains(contains('invalid user property')),
    );
  });

  test('allow-listed map helpers still reject a planted 26th parameter', () {
    final params = List.generate(26, (i) => "'k_$i': 0").join(',');
    final audit = _Audit({
      'lib/services/game_services.dart':
          '''
        class Services {
          Map<String, Object> _itemParams() => {$params};
          void send() => logEvent('item_equip', _itemParams());
        }
      ''',
      'lib/run/items/analytics_router.dart':
          '''
        class Router {
          Object _snapshotFail() => Snapshot({$params});
          void send() => c.track('run_fail', snapshot.params);
        }
      ''',
    });
    expect(audit.check(), hasLength(2));
    expect(audit.errors, everyElement(contains('26 parameters')));
  });

  test('audit fails closed on dynamic names, params, spreads and loops', () {
    for (final call in [
      'track(event, params)',
      "track('event_\$suffix')",
      "track('valid_event', params)",
      "track('valid_event', {'key': 0, ...extra})",
      "track('valid_event', {for (final k in keys) k: 0})",
      'setUserProperty(property, value)',
    ]) {
      expect(_fixture(call), isNotEmpty, reason: call);
    }
  });

  test(
    'audit handles comments, strings, nested values and collection branches',
    () {
      expect(
        _fixture('''
      // track('BadName', bogus);
      final text = "logEvent('BadName')";
      track('valid_event', {
        'nested': {'a': 1, 'b': 2},
        if (flag) 'yes': 1 else 'no': 0,
        ...{'spread_key': callback(1, 2)},
      })
    '''),
        isEmpty,
      );
      final tooMany = List.generate(26, (i) => "'k_$i': 0").join(',');
      expect(
        _fixture("track('valid_event', {...{$tooMany}})"),
        contains(contains('26 parameters')),
      );
      expect(
        _fixture("track('valid_event', {if (flag) ...{$tooMany}})"),
        contains(contains('26 parameters')),
      );
    },
  );
}

List<String> _fixture(String call) =>
    _Audit({'fixture.dart': 'void fixture() { $call; }'}).check();

bool _validName(String name, int max) =>
    name.length <= max &&
    RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(name);

/// Parse Dart rather than matching text: comments, multiline calls, nested
/// expressions and named Firebase arguments must all behave like real code.
class _Audit {
  _Audit(Map<String, String> sources) {
    for (final entry in sources.entries) {
      final parsed = parseString(content: entry.value, path: entry.key);
      units[entry.key] = parsed.unit;
    }
  }

  final units = <String, CompilationUnit>{};
  final errors = <String>[];
  int events = 0;
  int properties = 0;

  // Exact forwarding sites, not file-wide exemptions. New dynamic calls fail
  // until reviewed here. Their literal callers are scanned independently.
  static const _dynamicCalls = {
    'lib/run/run_context.dart|track|game.services.track(event, params)':
        'RunContext forwards the audited event and params unchanged.',
    'lib/run/screens/revive_screen.dart|_track|game.services.track(name, p)':
        'Revive helper forwards its audited literal callers.',
    'lib/services/game_services.dart|track|logEvent(name, redactParams(parameters))':
        'Redacting forwarding wrapper; literal callers are audited.',
    'lib/services/game_services.dart|logEvent|_analytics?.logEvent(name: name, parameters: params)':
        'Firebase sink; upstream track/logEvent callers are audited.',
    'lib/services/game_services.dart|setUserProperty|_analytics?.setUserProperty(name: name, value: value)':
        'Firebase sink; upstream property callers are audited.',
    'lib/services/firebase_versus_backend.dart|_firebaseAnalytics|FirebaseAnalytics.instance.logEvent(name: name, parameters: params)':
        'Versus analytics callback forwards backend telemetry.',
    'lib/game/storage.dart|load|IntegrityGuard.instance.track(base)':
        'Not analytics: schedules an integrity Future.',
    'lib/services/integrity_guard.dart|start|track(_check())':
        'Not analytics: schedules an integrity Future.',
    'lib/run/items/streak.dart|attach|_track(h)':
        'Not analytics: tracks a Hoop subscription.',
    'lib/run/items/streak.dart|_onSpawned|_track(e.hoop)':
        'Not analytics: tracks a Hoop subscription.',
  };

  List<String> check() {
    for (final entry in units.entries) {
      entry.value.accept(_Calls((call) => _checkCall(entry.key, call)));
    }
    return errors;
  }

  void _checkCall(String path, MethodInvocation call) {
    final method = call.methodName.name;
    if (!{
      'track',
      '_track',
      '_analytics',
      'logEvent',
      'setUserProperty',
    }.contains(method)) {
      return;
    }
    final member =
        call.thisOrAncestorOfType<MethodDeclaration>()?.name.lexeme ??
        call.thisOrAncestorOfType<FunctionDeclaration>()?.name.lexeme ??
        '';
    final key = '$path|$member|${call.toSource()}';
    if (_dynamicCalls.containsKey(key)) return;
    final location =
        '$path:${units[path]!.lineInfo.getLocation(call.offset).lineNumber}';
    final args = call.argumentList.arguments;
    final positional = args.where((a) => a is! NamedExpression).toList();
    Expression? named(String name) {
      for (final arg in args.whereType<NamedExpression>()) {
        if (arg.name.label.name == name) return arg.expression;
      }
      return null;
    }

    final name = named('name') ?? positional.firstOrNull;
    final property = method == 'setUserProperty';
    if (name is! StringLiteral || name.stringValue == null) {
      errors.add(
        '$location: unlisted dynamic $method call: ${call.toSource()}',
      );
    } else if (!_validName(name.stringValue!, property ? 24 : 40)) {
      errors.add(
        '$location: invalid ${property ? 'user property' : 'event'} name ${name.toSource()}',
      );
    }
    if (property) {
      properties++;
      return;
    }
    events++;
    final params =
        named('parameters') ?? (positional.length > 1 ? positional[1] : null);
    try {
      final count = params == null ? 0 : _count(path, params);
      if (count > 25) errors.add('$location: $count parameters (maximum 25)');
    } on StateError catch (e) {
      errors.add('$location: ${e.message}');
    }
  }

  int _count(String path, Expression expression) {
    if (expression is NullLiteral) return 0;
    if (expression is ParenthesizedExpression) {
      return _count(path, expression.expression);
    }
    if (expression is SetOrMapLiteral) {
      return expression.elements.fold(0, (n, e) => n + _elementCount(path, e));
    }
    // Explicit dynamic map allow-list, resolved to the actual source map so
    // adding a 26th key in a helper is caught as well as at the call site.
    final source = expression.toSource();
    if (path == 'lib/run/items/analytics_router.dart' &&
        {'snapshot.params', 'pending.params'}.contains(source)) {
      return _memberMapCount(path, '_snapshotFail');
    }
    if (path == 'lib/game/flappy_game.dart' && source == 'data.analytics') {
      return _memberMapCount('lib/share/share_card.dart', 'analytics');
    }
    if (path == 'lib/services/game_services.dart') {
      if (expression is MethodInvocation &&
          expression.methodName.name == '_itemParams') {
        return _memberMapCount(path, '_itemParams');
      }
      if (source == 'extra') {
        // logShareScore's documented extra is ShareCardData.analytics.
        return _memberMapCount('lib/share/share_card.dart', 'analytics');
      }
    }
    throw StateError('unlisted dynamic parameter map: $source');
  }

  int _memberMapCount(String path, String member) {
    final maps = <SetOrMapLiteral>[];
    units[path]!.accept(
      _Maps((map) {
        if (map.thisOrAncestorOfType<MethodDeclaration>()?.name.lexeme ==
            member) {
          maps.add(map);
        }
      }),
    );
    if (maps.length != 1) {
      throw StateError(
        'review dynamic map $path::$member (${maps.length} maps)',
      );
    }
    return _count(path, maps.single);
  }

  int _elementCount(String path, CollectionElement element) {
    if (element is MapLiteralEntry) return 1;
    if (element is SpreadElement) return _count(path, element.expression);
    if (element is IfElement) {
      final yes = _elementCount(path, element.thenElement);
      final no = element.elseElement == null
          ? 0
          : _elementCount(path, element.elseElement!);
      return yes > no ? yes : no;
    }
    if (element is ForElement &&
        path == 'lib/run/items/analytics_router.dart') {
      final parts = element.forLoopParts.toSource();
      if (parts == 'var tier = 1; tier <= 10; tier++') {
        return 10 * _elementCount(path, element.body);
      }
      for (final entry in {
        'final k in hoopKeys': AnalyticsRouter.hoopKeys.length,
        'final k in itemKeys': AnalyticsRouter.itemKeys.length,
      }.entries) {
        if (parts == entry.key) {
          return entry.value * _elementCount(path, element.body);
        }
      }
    }
    throw StateError('unlisted dynamic map element: ${element.toSource()}');
  }
}

class _Calls extends RecursiveAstVisitor<void> {
  _Calls(this.onCall);
  final void Function(MethodInvocation) onCall;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onCall(node);
    super.visitMethodInvocation(node);
  }
}

class _Maps extends RecursiveAstVisitor<void> {
  _Maps(this.onMap);
  final void Function(SetOrMapLiteral) onMap;

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    onMap(node);
    super.visitSetOrMapLiteral(node);
  }
}
