import "package:flappy_spikes/skins/look.dart";
import "dart:ui";
import "package:flame/components.dart";
import 'package:flappy_spikes/components/skins/shop_widgets.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all 24 skill rewards are legendary and have an achievement', () {
    final items = allItems.where((item) => item.isSkillOnly).toList();
    expect(items, hasLength(24));
    expect(items.every((item) => item.unlock != null && item.rarity == Rarity.legendary), isTrue);
  });
  test('skill action exposes the secret sheet prompt', () {
    final action = ShopActionButton(bottomRight: Vector2.zero(),
      kind: () => ShopActionKind.skillOnly, price: () => 0,
      affordable: () => true, tint: () => const Color(0xff000000),
      reduceMotion: () => true, onPressed: () {});
    action.update(0);
    // PRD-2.6 F10: the full secret prompt is in the separate stage strip.
    expect(action.label, 'SKILL ONLY');
  });
}
