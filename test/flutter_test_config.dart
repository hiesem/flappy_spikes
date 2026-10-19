import 'dart:async';

import 'package:flappy_spikes/run/config/tuning_values.dart';

/// Runs before every test file (the flutter_test hook).
///
/// PRD-2.3 §26: the Shop and Skins content tests were written for the open
/// menus of 2.2, so they run with the unlock best at 0 (`ui_unlock_best`).
/// The lock has its own tests (`test/p23/s26_menu_lock_test.dart`), which
/// reset the owner's default of 25 at the start of their file.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TuningValues.current = TuningValues.resolve({'ui_unlock_best': '0'});
  await testMain();
}
