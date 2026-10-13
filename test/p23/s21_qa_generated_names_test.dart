import 'package:flappy_spikes/run/hud/name_chip.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flutter_test/flutter_test.dart';

import '../share/share_card_golden_test.dart' show loadCardFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCardFonts);

  test(
    'S8-08 §21.2 every generated nickname keeps its three digits in the HUD',
    () {
      final cut = <String>[];
      for (final adjective in kNicknameAdjectives) {
        for (final bird in kNicknameBirds) {
          if (adjective.length + bird.length > kNicknameWordsMax) continue;
          final name = '$adjective${bird}999';
          if (NameChip(name, 0).shown != name) cut.add(name);
        }
      }
      expect(
        cut,
        isEmpty,
        reason: 'Generated nicknames must be shown in full, digits included',
      );
    },
    skip: 'S8-08',
  );
}
