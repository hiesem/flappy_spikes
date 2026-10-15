import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// iOS round 2: one release-visible diagnostic line.
///
/// `print` reaches the device log in release builds too (iOS: the
/// `flutter:` lines of the device console; Android: logcat tag `flutter`),
/// unlike `debugPrint` behind `kDebugMode`. Every line starts with an
/// `FS-…` tag (`FS-Audio`, `FS-GC`, `FS-Ach`, `FS-Rumble`) so one filter
/// finds them. Quiet under `flutter test` (the suites would drown in it);
/// never personal data.
void diag(String line) {
  if (_underTest) return;
  // ignore: avoid_print
  print(line);
}

final bool _underTest =
    !kIsWeb && kDebugMode && Platform.environment.containsKey('FLUTTER_TEST');
