import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/hud/fit_name.dart';
import 'package:flappy_spikes/run/hud/name_chip.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../share/share_card_golden_test.dart' show loadCardFonts;

/// Every valid generated nickname, with the widest digits of each family.
Iterable<String> _generated() sync* {
  for (final adjective in kNicknameAdjectives) {
    for (final bird in kNicknameBirds) {
      if (adjective.length + bird.length > kNicknameWordsMax) continue;
      for (final d in ['000', '222', '444', '888', '999']) {
        yield '$adjective$bird$d';
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCardFonts);

  test(
    'S8-08 §21.2 every generated nickname keeps its three digits in the HUD',
    () {
      final cut = <String>[];
      for (final name in _generated()) {
        if (NameChip(name, 0).shown != name) cut.add(name);
      }
      expect(
        cut,
        isEmpty,
        reason: 'Generated nicknames must be shown in full, digits included',
      );
    },
  );

  test('S8-08 §21.2 every generated nickname is whole on the VS intro plate '
      '(room before the emblem), the results columns and the share card', () {
    final fred = measureName(
      fontFamily: HudConfig.nameFont,
      fontWeight: FontWeight.w600,
    );
    final plateRoom =
        VersusConfig.oppPlate.width -
        VersusConfig.plateSlot / 2 -
        VersusConfig.plateEmblemHalf -
        VersusConfig.plateNameGap -
        VersusConfig.plateSlot -
        VersusConfig.plateNameLeft;
    final cut = <String>[];
    for (final name in _generated()) {
      for (final (where, room, size) in [
        ('plate', plateRoom, VersusConfig.plateNameSize),
        ('results', ResultsConfig.nameRoomVersus, ResultsConfig.nameFontSize),
        ('share', 380.0, 40.0),
      ]) {
        final f = fitName(name, room, size, fred);
        if (f.text != name) cut.add('$where:$name');
      }
    }
    expect(cut, isEmpty);
  });
}
