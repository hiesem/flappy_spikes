import 'dart:ui' show Color;

/// The five customisation layers of the 2.0 skin shop (PRD-menu-v2 §1).
///
/// [key] is the persisted / analytics name and the `<layer>` part of the
/// `"layer:id"` owned-item keys and the `item:<layer>:<id>` wallet reason.
enum SkinLayer {
  bird('bird', 'BIRDS'),
  gear('gear', 'GEAR'),
  hat('hat', 'HATS'),
  hoop('hoop', 'HOOPS'),
  trail('trail', 'TRAILS');

  const SkinLayer(this.key, this.tabLabel);

  final String key;
  final String tabLabel;

  /// Gear and Hat have a free "none" entry; the other layers do not.
  bool get hasNone => this == gear || this == hat;

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
  });

  /// The free default look.
  static const Look defaults = Look();

  final String bird;
  final String gear;
  final String hat;
  final String hoop;
  final String trail;

  String idFor(SkinLayer layer) => switch (layer) {
    SkinLayer.bird => bird,
    SkinLayer.gear => gear,
    SkinLayer.hat => hat,
    SkinLayer.hoop => hoop,
    SkinLayer.trail => trail,
  };

  Look withItem(SkinLayer layer, String id) => Look(
    bird: layer == SkinLayer.bird ? id : bird,
    gear: layer == SkinLayer.gear ? id : gear,
    hat: layer == SkinLayer.hat ? id : hat,
    hoop: layer == SkinLayer.hoop ? id : hoop,
    trail: layer == SkinLayer.trail ? id : trail,
  );

  /// Five ids, keyed by [SkinLayer.key] (recorded runs, analytics).
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Look &&
      other.bird == bird &&
      other.gear == gear &&
      other.hat == hat &&
      other.hoop == hoop &&
      other.trail == trail;

  @override
  int get hashCode => Object.hash(bird, gear, hat, hoop, trail);

  @override
  String toString() => 'Look($bird, $gear, $hat, $hoop, $trail)';
}
