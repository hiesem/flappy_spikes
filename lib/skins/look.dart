import 'dart:ui' show Color;

// region P26-F9a
/// The five wardrobe layers plus versus cards (PRD F9).
// endregion
///
/// [key] is the persisted / analytics name and the `<layer>` part of the
/// `"layer:id"` owned-item keys and the `item:<layer>:<id>` wallet reason.
enum SkinLayer {
  bird('bird', 'BIRDS'),
  gear('gear', 'GEAR'),
  hat('hat', 'HATS'),
  hoop('hoop', 'HOOPS'),
  trail('trail', 'TRAILS'),
  // region P26-F9a
  card('card', 'CARDS');

  // endregion

  const SkinLayer(this.key, this.tabLabel);

  final String key;
  final String tabLabel;

  static SkinLayer? fromKey(String key) {
    for (final layer in values) {
      if (layer.key == key) return layer;
    }
    return null;
  }
}

/// Item rarity (PRD-menu-v2 §3.2). [price] is the standard coin price;
/// common plain-colour birds 2–10 cost 150 (see the catalogue).
enum Rarity {
  common('COMMON', Color(0xFF9A9A9A), 250),
  rare('RARE', Color(0xFF1E9BE0), 750),
  epic('EPIC', Color(0xFF9B30D9), 2000),
  legendary('LEGENDARY', Color(0xFFFFB529), 5000);

  const Rarity(this.label, this.color, this.price);

  final String label;
  final Color color;
  final int price;
}

/// Id of the "nothing equipped" entry on the Gear and Hat layers.
const String kNoneId = 'none';

/// One complete equipped look: one item id per layer. Ids are the ones in
/// `design/menu_v2/skin_art.js` (e.g. bird `classic`, gear `windup`,
/// hat `crown`, hoop `pink`, trail `flame`).
class Look {
  const Look({
    this.bird = 'classic',
    this.gear = kNoneId,
    this.hat = kNoneId,
    this.hoop = 'pink',
    this.trail = 'flame',
    // region P26-F9a
    this.card = '',
    // endregion
  });

  /// The free default look.
  static const Look defaults = Look();

  final String bird;
  final String gear;
  final String hat;
  final String hoop;
  final String trail;
  // region P26-F9a
  /// Empty for legacy looks; otherwise frame|name|sticker, with empty slots.
  final String card;

  String cardIdFor(CardKind kind) {
    final slots = card.split('|');
    return slots.length == 3 ? slots[kind.index] : '';
  }

  Look withCardItem(CardKind kind, String id) {
    final slots = [for (final slot in CardKind.values) cardIdFor(slot)];
    slots[kind.index] = id;
    return withItem(
      SkinLayer.card,
      slots.every((s) => s.isEmpty) ? '' : slots.join('|'),
    );
  }
  // endregion

  String idFor(SkinLayer layer) => switch (layer) {
    SkinLayer.bird => bird,
    SkinLayer.gear => gear,
    SkinLayer.hat => hat,
    SkinLayer.hoop => hoop,
    SkinLayer.trail => trail,
    // region P26-F9a
    SkinLayer.card => card,
    // endregion
  };

  Look withItem(SkinLayer layer, String id) => Look(
    bird: layer == SkinLayer.bird ? id : bird,
    gear: layer == SkinLayer.gear ? id : gear,
    hat: layer == SkinLayer.hat ? id : hat,
    hoop: layer == SkinLayer.hoop ? id : hoop,
    trail: layer == SkinLayer.trail ? id : trail,
    // region P26-F9a
    card: layer == SkinLayer.card ? id : card,
    // endregion
  );

  // region P26-F9a
  /// Equipped ids and the card slots, keyed by layer (recorded runs, analytics).
  // endregion
  Map<String, String> toJson() => {
    for (final layer in SkinLayer.values) layer.key: idFor(layer),
  };

  factory Look.fromJson(Map<String, Object?> json) {
    String read(SkinLayer layer) {
      final value = json[layer.key];
      return value is String ? value : Look.defaults.idFor(layer);
    }

    return Look(
      bird: read(SkinLayer.bird),
      gear: read(SkinLayer.gear),
      hat: read(SkinLayer.hat),
      hoop: read(SkinLayer.hoop),
      trail: read(SkinLayer.trail),
      // region P26-F9a
      card: read(SkinLayer.card),
      // endregion
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Look &&
      other.bird == bird &&
      other.gear == gear &&
      other.hat == hat &&
      other.hoop == hoop &&
      other.trail == trail &&
      // region P26-F9a
      other.card == card;
  // endregion

  // region P26-F9a
  @override
  int get hashCode => Object.hash(bird, gear, hat, hoop, trail, card);
  // endregion

  @override
  String toString() => 'Look($bird, $gear, $hat, $hoop, $trail)';
}

// region P26-F9a
/// The ordered slots in the single persisted versus-card field.
enum CardKind { frame, name, sticker }
// endregion
