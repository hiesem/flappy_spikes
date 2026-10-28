import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/components/sticker_avatar.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/art/hoop_painter.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('skill look extents and avatar colours reflect their art', () {
    for (final id in ['skycrown', 'nest', 'jackpot']) {
      final (top, _) = LookPainter.extentOf(Look(hat: id));
      expect(top, lessThan(-30), reason: id);
    }
    expect(LookPainter.gearRise.keys, containsAll(['peacock', 'goggles']));
    for (final id in ['magpie', 'prism', 'daynight']) {
      expect(StickerAvatars.tintOf(id), isNot(StickerAvatars.tintOf('classic')), reason: id);
    }
  });
  test('PRD F10 skill item achievement mapping', () {
    const expected = <String, AchievementId>{
      'bird:magpie': AchievementId.itemAll, 'bird:prism': AchievementId.hoops100,
      'bird:daynight': AchievementId.daily30, 'gear:goggles': AchievementId.rideAll,
      'gear:hoopchain': AchievementId.hoops50, 'gear:peacock': AchievementId.skinAll,
      'hat:skycrown': AchievementId.skyHigh, 'hat:nest': AchievementId.masterHatch,
      'hat:jackpot': AchievementId.masterJackpot, 'hoop:spikes': AchievementId.rankSpikeAce,
      'hoop:phoenixring': AchievementId.rankPhoenix, 'hoop:legend': AchievementId.rankLegend,
      'trail:thread': AchievementId.bullseye, 'trail:constellation': AchievementId.masterStars,
      'trail:fireflies': AchievementId.masterJar, 'card:pecking': AchievementId.vs10,
      'card:roost': AchievementId.vs50, 'card:prey': AchievementId.birdOfPrey,
      'card:n_sky': AchievementId.secondWind, 'card:n_thunder': AchievementId.albatross,
      'card:n_marquee': AchievementId.threeLittleBirds, 'card:s_unstop': AchievementId.ironBeak,
      'card:s_flawless': AchievementId.flawless, 'card:s_topflock': AchievementId.topBird,
    };
    expect({for (final item in allItems.where((i) => i.isSkillOnly)) item.key: item.unlock}, expected);
  });

  test(
    'PRD F10: every skill item uses its painter through the normal dispatch',
    () async {
      Future<Uint8List> render(SkinLayer layer, String id) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        if (layer == SkinLayer.hoop) {
          HoopPainter.paintHalf(
            canvas,
            id,
            const ui.Offset(90, 65),
            30,
            .7,
            front: true,
            rx: 14,
            lineWidth: 5,
          );
        } else if (layer == SkinLayer.trail) {
          final trail = TrailEmitter(id);
          trail.emit(const ui.Offset(90, 65), .016);
          trail.step(.016);
          trail.paint(canvas);
        } else {
          canvas.translate(90, 65);
          LookPainter.paint(canvas, Look.defaults.withItem(layer, id), t: .7);
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(180, 130);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        picture.dispose();
        return bytes!.buffer.asUint8List();
      }

      for (final item in allItems.where(
        (i) => i.isSkillOnly && i.layer != SkinLayer.card,
      )) {
        final actual = await render(item.layer, item.id);
        final fallback = await render(item.layer, defaultItemId(item.layer));
        expect(actual, isNot(orderedEquals(fallback)), reason: item.key);
      }
    },
  );
  test(
    'PRD F10 O81: achievement state alone owns all 24 skill items',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final items = ItemStore(storage, Wallet(storage));
      final skills = allItems.where((item) => item.isSkillOnly).toList();
      expect(skills, hasLength(24));
      expect(kCollectibleTotal, 223);
      expect(kSoldCollectibleTotal, 199);
      for (final item in skills) {
        expect(item.unlock, isNotNull);
        expect(item.rarity, Rarity.legendary);
        expect(items.isOwned(item.layer, item.id), isFalse);
        storage.ownedItems.add(item.key);
        expect(items.isOwned(item.layer, item.id), isFalse);
        expect(
          await items.purchase(item.layer, item.id),
          ItemPurchaseResult.unknown,
        );
        storage.ach.unlocked.add(item.unlock!.key);
        expect(items.isOwned(item.layer, item.id), isTrue);
      }
      expect(items.ownedCount, 27);
      expect(items.soldOwnedCount, 3);
      await items.equip(SkinLayer.bird, 'magpie');
      expect(items.look.bird, 'magpie');
      storage.ach.unlocked.clear();
      expect(items.look.bird, 'classic');
      expect(() => items.grant('bird:magpie'), throwsArgumentError);
    },
  );
}
