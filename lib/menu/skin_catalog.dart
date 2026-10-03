import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../game/storage.dart';
import 'wallet.dart';

/// One purchasable bird skin, drawn as two layers (WP3 manifest,
/// `assets/images/skins/manifest.json`): a greyscale *tinted* layer drawn
/// through a modulate ColorFilter of [tintFor] and an untinted *overlay*
/// (beak, eye, fixed-colour accessory) on top. Every skin, the default pink
/// included, uses the same 46.5 x 46.5 pt canvas whose [anchor] sits on the
/// 1.0 bird body centre, so hitbox and physics never change.
class SkinDef {
  const SkinDef({
    required this.id,
    required this.name,
    required this.price,
    required this.mockColor,
    this.accessory = false,
  });

  final String id;
  final String name;
  final int price;

  /// The skin's identity colour (the approved mocks): the tint at blend 0.
  final Color mockColor;

  /// Whether the overlay carries an accessory (crown, hat, ...).
  final bool accessory;

  /// Sprite canvas in points (93 x 93 px at 2 px/pt: 17 pt of headroom above
  /// the original 46.5 x 29.5 bird for hats).
  static const double spriteWidth = 46.5;
  static const double spriteHeight = 46.5;

  /// Relative anchor of the bird body centre inside the canvas.
  static const double anchorX = 0.5;
  static const double anchorY = 0.682796;

  // Tinted layer, frames idle / flap / dead.
  String get normal => 'skins/$id.png';
  String get flap => 'skins/${id}_flap.png';
  String get dead => 'skins/${id}_dead.png';

  // Untinted overlay, frames idle / flap / dead.
  String get overlay => 'skins/${id}_acc.png';
  String get overlayFlap => 'skins/${id}_acc_flap.png';
  String get overlayDead => 'skins/${id}_acc_dead.png';

  List<String> get tintedFrames => [normal, flap, dead];
  List<String> get overlayFrames => [overlay, overlayFlap, overlayDead];

  /// Every image this skin draws.
  List<String> get images => [...tintedFrames, ...overlayFrames];

  /// Full-colour menu previews (48 x 52 pt) for the Shop / Skins screens.
  String get preview => 'skins/${id}_preview.png';
  String get previewLocked => 'skins/${id}_preview_locked.png';

  /// Tint for the layer: the identity colour blended toward the stage
  /// foreground by [blend] (0 in menus and stage 0, see
  /// `Config.skinStageBlend`).
  Color tintFor(Color stageForeground, double blend) =>
      blend <= 0 ? mockColor : Color.lerp(mockColor, stageForeground, blend)!;
}

/// Display order and prices (BRIEF.md); mock colours from the WP3 manifest.
const List<SkinDef> kSkins = [
  SkinDef(id: 'pink', name: 'Pink', price: 0, mockColor: Color(0xFFEC008C)),
  SkinDef(id: 'blue', name: 'Sky', price: 100, mockColor: Color(0xFF29B6F6)),
  SkinDef(id: 'green', name: 'Lime', price: 150, mockColor: Color(0xFF7CB342)),
  SkinDef(
      id: 'purple', name: 'Grape', price: 200, mockColor: Color(0xFF8E24AA)),
  SkinDef(id: 'grey', name: 'Stone', price: 300, mockColor: Color(0xFF37474F)),
  SkinDef(id: 'sand', name: 'Sand', price: 800, mockColor: Color(0xFFFFB300)),
  SkinDef(
      id: 'crown',
      name: 'King',
      price: 1000,
      mockColor: Color(0xFFEC008C),
      accessory: true),
  SkinDef(
      id: 'tophat',
      name: 'Gentleman',
      price: 600,
      mockColor: Color(0xFFFAFAFA),
      accessory: true),
  SkinDef(
      id: 'sunglasses',
      name: 'Cool',
      price: 500,
      mockColor: Color(0xFFFF7043),
      accessory: true),
  SkinDef(
      id: 'headband',
      name: 'Ninja',
      price: 700,
      mockColor: Color(0xFF212121),
      accessory: true),
  SkinDef(
      id: 'partyhat',
      name: 'Party',
      price: 450,
      mockColor: Color(0xFF26A69A),
      accessory: true),
  SkinDef(id: 'ghost', name: 'Ghost', price: 900, mockColor: Color(0xFFECEFF1)),
];

SkinDef? skinById(String id) {
  for (final skin in kSkins) {
    if (skin.id == id) return skin;
  }
  return null;
}

enum SkinPurchaseResult { purchased, alreadyOwned, insufficientCoins, unknown }

/// Owned/equipped skins plus purchases, persisted through [GameStorage].
class SkinStore extends ChangeNotifier {
  SkinStore(this._storage, this._wallet);

  final GameStorage _storage;
  final Wallet _wallet;

  String get equipped => _storage.equippedSkin;

  SkinDef get equippedSkin => skinById(equipped) ?? kSkins.first;

  bool isOwned(String id) => _storage.ownedSkins.contains(id);

  bool isEquipped(String id) => equipped == id;

  /// Not owned yet, affordable with the current balance and not seen.
  bool isNew(String id) {
    final skin = skinById(id);
    if (skin == null || isOwned(id)) return false;
    return skin.price <= _wallet.balance && !_storage.seenSkins.contains(id);
  }

  bool get hasNewBadge => kSkins.any((skin) => isNew(skin.id));

  /// Equips [id] when owned; unowned ids are ignored.
  Future<void> equip(String id) async {
    if (!isOwned(id)) return;
    await _storage.saveEquippedSkin(id);
    notifyListeners();
  }

  /// Buys [id] and auto-equips it on success.
  Future<SkinPurchaseResult> purchase(String id) async {
    final skin = skinById(id);
    if (skin == null) return SkinPurchaseResult.unknown;
    if (isOwned(id)) return SkinPurchaseResult.alreadyOwned;
    if (_wallet.balance < skin.price) {
      return SkinPurchaseResult.insufficientCoins;
    }
    final spent = await _wallet.spend(skin.price, 'skin:$id');
    if (!spent) return SkinPurchaseResult.insufficientCoins;
    await _storage.saveOwnedSkins({..._storage.ownedSkins, id});
    await _storage.saveEquippedSkin(id);
    notifyListeners();
    return SkinPurchaseResult.purchased;
  }

  /// Marks every currently-new skin as seen (clears the NEW badge).
  Future<void> markAllSeen() async {
    await _storage.saveSeenSkins({
      ..._storage.seenSkins,
      for (final skin in kSkins)
        if (isNew(skin.id)) skin.id,
    });
    notifyListeners();
  }
}
