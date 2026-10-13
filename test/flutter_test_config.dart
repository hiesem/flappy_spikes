import 'dart:async';

import 'package:flappy_spikes/services/tuning.dart';

/// Runs before every test file (the flutter_test hook).
///
/// PRD-2.3 §26: the Shop and Skins content tests were written for the open
/// menus of 2.2, so they run with the unlock best at 0 (`ui_unlock_best`).
/// The lock has its own tests (`test/p23/s26_menu_lock_test.dart`), which
/// reset the owner's default of 25 at the start of their file.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The run start hands `Tuning.instance.active` to the config getters, so the
  // override has to live in the service, not only in `TuningValues.current`.
  Tuning.instance = Tuning(
    active: TuningValues.resolve({'ui_unlock_best': '0'}),
  );
  TuningValues.current = Tuning.instance.active;
  await testMain();
}
