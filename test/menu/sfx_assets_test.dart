import 'dart:io';

import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Sfx maps to one unique file', () {
    final names = SoundService.audioFiles.values.toList();
    expect(SoundService.audioFiles.keys.toSet(), Sfx.values.toSet());
    expect(names.toSet().length, names.length);
  });

  test('every Sfx file exists in assets/audio', () {
    for (final sfx in Sfx.values) {
      final file = SoundService.audioFiles[sfx]!;
      expect(File('assets/audio/$file').existsSync(), isTrue,
          reason: '$sfx -> assets/audio/$file');
    }
  });

  test('the menu sfx are the approved design/menu_v2 files', () {
    expect(SoundService.audioFiles[Sfx.skTab], 'sk_tab.mp3');
    expect(SoundService.audioFiles[Sfx.skTap], 'sk_tap.mp3');
    expect(SoundService.audioFiles[Sfx.skEquip], 'sk_equip.mp3');
    expect(SoundService.audioFiles[Sfx.skBuyCommon], 'sk_buy_common.mp3');
    expect(SoundService.audioFiles[Sfx.skBuyRare], 'sk_buy_rare.mp3');
    expect(SoundService.audioFiles[Sfx.skBuyEpic], 'sk_buy_epic.mp3');
    expect(SoundService.audioFiles[Sfx.skBuyLegendary], 'sk_buy_legendary.mp3');
    expect(SoundService.audioFiles[Sfx.skProgress], 'sk_progress.mp3');
    expect(SoundService.audioFiles[Sfx.skNoCoins], 'sk_nocoins.mp3');
    expect(SoundService.audioFiles[Sfx.skHoop], 'sk_hoop.mp3');
    expect(SoundService.audioFiles[Sfx.skFire], 'sk_fire.mp3');
    expect(SoundService.audioFiles[Sfx.skClose], 'sk_close.mp3');
    expect(SoundService.audioFiles[Sfx.skDialog], 'sk_dialog.mp3');
    expect(SoundService.audioFiles[Sfx.bnAdBtn], 'bn_adbtn.mp3');
    expect(SoundService.audioFiles[Sfx.bnCoin], 'bn_coin.mp3');
    // PRD-home-v3 §5 / §7.
    expect(SoundService.audioFiles[Sfx.skTick], 'sk_tick.mp3');
    expect(SoundService.audioFiles[Sfx.noadsUnlock], 'noads_unlock.mp3');
    expect(SoundService.audioFiles[Sfx.noadsStamp], 'noads_stamp.mp3');
  });
}
