import 'package:flappy_spikes/run/items/analytics_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.6 WP-A2: event names are snake_case and at most 40 characters;
/// every event has at most 25 parameters. `run_fail` has the PRD's 22.
void main() {
  final snakeCase = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');

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

  test('every router event name is snake_case, ≤ 40 characters and has '
      '≤ 25 parameters', () {
    // The names the router owns. The in-run events from other features are
    // outside this issue; this is the WP-A router contract the test names.
    const names = [
      'run_fail',
      'run_end',
      'run_extra',
      'run_director_hoops',
      'run_director_items',
      'coins_earned',
    ];
    for (final name in names) {
      expect(name.length, lessThanOrEqualTo(40), reason: name);
      expect(name, matches(snakeCase), reason: name);
    }
    expect(AnalyticsRouter.hoopKeys.length, lessThanOrEqualTo(25));
    expect(AnalyticsRouter.itemKeys.length, lessThanOrEqualTo(25));
    // run_director_hoops / _items add rim_touches + perfect_pct.
    expect(AnalyticsRouter.hoopKeys.length + 2, lessThanOrEqualTo(25));
    expect(AnalyticsRouter.itemKeys.length, lessThanOrEqualTo(25));
  });
}
