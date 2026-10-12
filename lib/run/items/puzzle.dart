import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import '../../game/sound.dart';
import '../../game/storage.dart';
import '../../menu/wallet.dart';
import '../config/feather_config.dart';
import '../config/puzzle_config.dart';
import '../effects/coin_icon.dart';
import '../effects/easing.dart';
import '../effects/fetch_flight.dart';
import '../elements.dart';
import '../hud/collect_layer.dart';
import '../pickups/puzzle_piece_pickup.dart';
import '../../versus/timeline.dart' show PointFlags;
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';
import '../../game/paints.dart';

/// Puzzle pieces in the run (PRD-2 §3.16, §5.15).
///
/// A touched piece is **banked at once**: its bit joins `storage
/// .puzzlePieces` (persistent), `col4_puzzle_get`,
/// `puzzle_piece_collected {piece 1–4, count 1–4, round 1-based}`. The 4th
/// piece completes the picture **at that moment, in the run**: the bonus
/// (`director.rollPuzzleBonus()`, uniform 50–250 step 5) goes to the wallet
/// (source `puzzle`) and into YOUR REWARD, and the mask goes to 0 with the
/// round + 1 (`storage.beginPuzzleCompletion()`), all at once —
/// `puzzle_completed {round, coins}`. The piece then flies (the shared
/// [FetchFlight]) into the puzzle pill ([PuzzlePillItem]).
class PuzzleFeature extends RunFeature {
  RunContext? _c;

  /// Bonuses rolled in this run, before the chick's ×2 (tests: exactly
  /// once per completed picture).
  final List<int> paid = [];

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<PickupCollected>(_onPickup);
  }

  void _onPickup(PickupCollected e) {
    if (e.element != ElementId.puzzlePiece) return;
    final c = _c;
    if (c == null) return;
    final storage = c.game.storage;
    final round = storage.puzzleRound;
    final theme = PuzzleConfig.themeFor(round);
    final before = storage.puzzlePieces & 0xF;
    final p = e.pickup;
    var piece = p is PuzzlePiecePickup ? p.piece : -1;
    if (piece < 0 || before & (1 << piece) != 0) {
      // A piece the player already holds (only a debug force can plan two
      // in one run): it fills the first missing place instead.
      piece = -1;
      for (var b = 0; b < PuzzleConfig.pieces; b++) {
        if (before & (1 << b) == 0) {
          piece = b;
          break;
        }
      }
      if (piece < 0) return;
    }
    final mask = before | (1 << piece);
    final count = _bits(mask);
    c.sfx(Sfx.col4PuzzleGet);
    c.track('puzzle_piece_collected', {
      'piece': piece + 1,
      'count': count,
      'round': round + 1,
    });
    int? reward;
    if (count >= PuzzleConfig.pieces) {
      final rolled = c.director.rollPuzzleBonus();
      reward = _complete(c, rolled);
      paid.add(rolled);
      c.track('puzzle_completed', {'round': round + 1, 'coins': reward});
    } else {
      unawaited(storage.savePuzzlePieces(mask));
    }

    final layer = CollectLayer.ensureFor(c.run);
    layer.slot.request(
      PuzzlePillItem(
        layer: layer,
        theme: theme,
        before: before,
        piece: piece,
        reward: reward,
        random: c.cosmetic,
      ),
    );
    if (p == null) return;
    final s = c.s;
    final from = Offset(p.position.x - s.camX, p.position.y - s.camY);
    final centre = PuzzleArt.centreOf(piece);
    final to = Offset(
      CollectConfig.slotX + PuzzleConfig.boardX + centre.dx,
      CollectConfig.slotY + centre.dy,
    );
    layer.add(
      FetchFlight(
        from: from,
        to: to,
        spec: FetchSpec(
          growBy: FetchSpec.puzzlePiece.growBy,
          controlDx: FetchSpec.puzzlePiece.controlDx,
          scaleFrom: FetchSpec.puzzlePiece.scaleFrom,
          scaleTo: FetchSpec.puzzlePiece.scaleTo,
          trailJitter: FetchSpec.puzzlePiece.trailJitter,
          trailMax: FetchSpec.puzzlePiece.trailMax,
          // §5.15 the trail: the round's body colour, gold and pink.
          trailColors: [
            theme.body,
            theme.body,
            const Color(0xFFFFB529),
            const Color(0xFFEC008C),
          ],
        ),
        pool: layer.pool,
        random: c.cosmetic,
        priority: 4,
        art: (canvas, scale, rotation) {
          canvas.save();
          canvas.rotate(rotation);
          canvas.scale(scale);
          PuzzleArt.paintPieceCentred(canvas, piece, theme);
          canvas.restore();
        },
      ),
    );
  }

  /// §3.16 the 4/4 bonus: wallet (source `puzzle`), YOUR REWARD and
  /// [CoinsEarned]. PRD-2.2 §13.1 (fix S7-03): the chick doubles it like
  /// every other row, in coins **and** points (up to 2 × 250 = 500; the
  /// points entry carries [PointFlags.puzzle] for the server cap).
  ///
  /// (call, S6-62) Completion is recoverable, as the level-reward claim
  /// (S6-22): the payout record (the balance to reach) goes out with the
  /// mask reset + round advance *before* the coin write, and is cleared
  /// only after the coin write landed. A kill in between is paid by
  /// [settlePayout] at the next start — never lost, never paid twice.
  /// Returns the amount paid (the doubled one with the chick).
  static int _complete(RunContext c, int rolled) {
    final storage = c.game.storage;
    final wallet = c.game.menu.wallet;
    final x2 = c.s.egg?.stage == EggStage.chick;
    final coins = x2 ? rolled * 2 : rolled;
    c.s.coinsThisRun += coins;
    unawaited(storage.beginPuzzleCompletion(payout: wallet.balance + coins));
    unawaited(
      wallet
          .add(coins, CoinSource.puzzle)
          .then((_) => storage.endPuzzlePayout()),
    );
    c.emit(CoinsEarned(coins, CoinSource.puzzle, eggX2: x2));
    // PRD-2.2 §13.1 the same (already doubled) amount in points.
    c.addScore(
      coins,
      flags: PointFlags.bonus | PointFlags.puzzle,
      chickX2: false,
    );
    return coins;
  }

  /// §3.16 (call, S6-62) Pays the part of an interrupted 4/4 bonus the
  /// wallet has not received ([GameStorage.puzzlePayout] minus the
  /// balance) and clears the record. Returns what was paid; a second call
  /// pays nothing. Run at app start, before the level-reward recovery.
  static Future<int> settlePayout(GameStorage storage, Wallet wallet) async {
    final target = storage.puzzlePayout;
    if (target <= 0) return 0;
    final due = target - wallet.balance;
    if (due > 0) await wallet.add(due, CoinSource.puzzle);
    await storage.endPuzzlePayout();
    return due > 0 ? due : 0;
  }

  static int _bits(int m) {
    var n = 0;
    for (var b = 0; b < 4; b++) {
      if (m & (1 << b) != 0) n++;
    }
    return n;
  }

  @override
  void detach() {
    _c?.events.off<PickupCollected>(_onPickup);
    _c = null;
  }
}

/// §5.15 the puzzle pill in the collect slot: 140 × 64 panel, the board at
/// x −32 (held pieces in colour, missing ones as grey silhouettes) and
/// "n/4". The new piece lands 0.76 s after the touch (punch, ring 6 → 30,
/// sparkles, `col4_puzzle_slotN` by the count held). 4/4: flash, bounces,
/// board pop + gold frame, confetti, ring 20 → 100, PICTURE COMPLETE, then
/// the coin badge counting up the bonus; the pill holds until 4.6 s.
class PuzzlePillItem extends CollectTimeline {
  PuzzlePillItem({
    required this.layer,
    required this.theme,
    required this.before,
    required this.piece,
    required this.reward,
    required math.Random random,
  }) : _r = random,
       count = PuzzleFeature._bits(before | (1 << piece));

  final CollectLayer layer;
  final PuzzleTheme theme;

  /// The mask before this piece, and this piece (0..3).
  final int before, piece;

  /// Pieces held with this one (1..4).
  final int count;

  /// The 4/4 bonus, or null.
  final int? reward;
  final math.Random _r;

  final List<double?> _punch = [null, null, null, null];
  double? _done;

  bool get complete => count >= PuzzleConfig.pieces;

  static const double doneTime =
      PuzzleConfig.landAt + PuzzleConfig.completeDelay;
  static const double badgeTime = doneTime + PuzzleConfig.badgeDelay;

  late final List<double> _coinX = [
    for (var i = 0; i < PuzzleConfig.badgeCoins; i++)
      -40 + 80 * _r.nextDouble(),
  ];

  @override
  double get fadeAt =>
      complete ? PuzzleConfig.fadeAtComplete : PuzzleConfig.fadeAt;

  bool have(int k, double t) =>
      before & (1 << k) != 0 || (k == piece && t >= PuzzleConfig.landAt);

  /// The badge's number at [t] (0 → reward over 0.8 s).
  int badgeCount(double t) {
    final r = reward ?? 0;
    final u =
        ((t - badgeTime - PuzzleConfig.countStart) / PuzzleConfig.countLength)
            .clamp(0.0, 1.0);
    return (r * u).round();
  }

  double get _badgeY => PuzzleConfig.pillHeight / 2 + PuzzleConfig.badgeGap;

  @override
  void cues(CollectLayer layer, double prev, double t) {
    bool at(double x) => CollectTimeline.crossed(prev, t, x);
    final centre = layer.slotCentre;
    if (at(PuzzleConfig.landAt)) {
      layer.game.sound.play(switch (count) {
        1 => Sfx.col4PuzzleSlot1,
        2 => Sfx.col4PuzzleSlot2,
        3 => Sfx.col4PuzzleSlot3,
        _ => Sfx.col4PuzzleSlot4,
      });
      _punch[piece] = t;
      final p =
          centre +
          const Offset(PuzzleConfig.boardX, 0) +
          PuzzleArt.centreOf(piece);
      layer.ring(
        p,
        from: PuzzleConfig.landRingFrom,
        to: PuzzleConfig.landRingTo,
      );
      layer.sparkles(p);
    }
    if (!complete) return;
    if (at(doneTime)) {
      _done = t;
      layer.confetti(centre, PuzzleConfig.confetti, _r);
      layer.ring(
        centre,
        from: PuzzleConfig.completeRingFrom,
        to: PuzzleConfig.completeRingTo,
        stroke: 4,
        length: .6,
      );
    }
    for (var k = 0; k < 4; k++) {
      if (at(doneTime + k * PuzzleConfig.bounceGap)) _punch[k] = t;
    }
    if (at(doneTime + PuzzleConfig.stickerDelay)) {
      sticker(
        layer,
        PuzzleConfig.stickerText,
        Offset(
          CollectConfig.slotX,
          CollectConfig.slotY +
              PuzzleConfig.pillHeight / 2 +
              PuzzleConfig.stickerGap,
        ),
      );
    }
    if (at(badgeTime)) layer.game.sound.play(Sfx.col4Coins);
  }

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// PRD-2.2 §12.1: the "n/4" count and the badge's "+N" are drawn by the
  /// banner layer ([paintBanner]), behind the gameplay. The pill's panel and
  /// the badge keep a window over each text (1 pt around it), and the banner
  /// layer paints the same colour under it (3 pt around it, so the window's
  /// edge never shows the background).
  static const double _windowPad = 1;
  static const double _backingPad = 3;

  static const Color _plum = Color(0xFF7A0044);
  static const double _badgeSize = 24;

  /// The "+N" text's left edge from the badge's left edge (pt).
  static const double _badgeTextX = 34;

  /// Pieces held at [t] (the landing one counts from its landing time).
  int _held(double t) {
    var n = 0;
    for (var k = 0; k < 4; k++) {
      if (have(k, t)) n++;
    }
    return n;
  }

  /// The "n/4" text's box at [n] held, in pill coordinates (centre 0).
  Rect _countBox(int n) {
    final label = CollectText.of('$n/4', PuzzleConfig.countSize, layer.fg);
    return Rect.fromLTWH(
      PuzzleConfig.countX - label.width / 2,
      2 - label.height / 2,
      label.width,
      label.height,
    );
  }

  /// [rect] without [window], as one path so no seam shows at the window.
  static Path _outside(Rect rect, Rect window) => Path.combine(
    PathOperation.difference,
    Path()..addRect(rect),
    Path()..addRect(window),
  );

  @override
  void paint(Canvas canvas, double alpha, double t) {
    fadeStickers(alpha);
    canvas.saveLayer(null, layerPaint(alpha));
    const w = PuzzleConfig.pillWidth, h = PuzzleConfig.pillHeight;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final done = _done;
    final dk = done != null && t >= done ? math.exp(-(t - done) * 3) : 0.0;
    final panel = _outside(rect, _countBox(_held(t)).inflate(_windowPad));
    canvas.drawPath(panel, _fill..color = layer.mix(PuzzleConfig.panelMix));
    if (dk > 0) {
      _fill.color = const Color(0xFFFFB529).withValues(alpha: dk * .85);
      canvas.drawPath(panel, _fill);
    }
    canvas.save();
    canvas.translate(PuzzleConfig.boardX, 0);
    if (done != null) canvas.scale(1 + PuzzleConfig.boardPop * dk);
    final ghost = layer.mix(PuzzleConfig.ghostMix);
    final seam = layer.mix(PuzzleConfig.seamMix);
    for (var k = 0; k < 4; k++) {
      if (!have(k, t)) {
        PuzzleArt.paintPiece(canvas, k, theme, ghost: ghost, seam: seam);
      }
    }
    for (var k = 0; k < 4; k++) {
      if (!have(k, t)) continue;
      final c = PuzzleArt.centreOf(k);
      final s = CollectTimeline.punch(
        t,
        _punch[k],
        PuzzleConfig.punch,
        PuzzleConfig.punchLength,
      );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(s);
      canvas.translate(-c.dx, -c.dy);
      PuzzleArt.paintPiece(canvas, k, theme);
      canvas.restore();
    }
    if (done != null) {
      canvas.drawRect(
        const Rect.fromLTWH(-25, -25, 50, 50),
        _stroke
          ..color = const Color(0xFFFFB529)
          ..strokeWidth = PuzzleConfig.frame,
      );
      if (dk > .05) {
        _fill.color = const Color(0xFFFFFFFF).withValues(alpha: dk);
        canvas.drawRect(const Rect.fromLTWH(-25, -25, 50, 50), _fill);
      }
    }
    canvas.restore();
    if (complete) _paintBadge(canvas, t);
    canvas.restore();
  }

  /// PRD-2.2 §12.1: the "n/4" count and the coin badge's "+N", drawn by the
  /// run's banner layer ([CollectLabels]) at the slot's centre and fade, on
  /// the backing that the HUD leaves out (see [_windowPad]).
  @override
  void paintBanner(Canvas canvas, double alpha, double t) {
    canvas.saveLayer(null, layerPaint(alpha));
    final done = _done;
    final dk = done != null && t >= done ? math.exp(-(t - done) * 3) : 0.0;
    final n = _held(t);
    final box = _countBox(n);
    final backing = box.inflate(_backingPad);
    canvas.drawRect(backing, _fill..color = layer.mix(PuzzleConfig.panelMix));
    if (dk > 0) {
      _fill.color = const Color(0xFFFFB529).withValues(alpha: dk * .85);
      canvas.drawRect(backing, _fill);
    }
    final label = CollectText.of(
      '$n/4',
      PuzzleConfig.countSize,
      done != null ? _plum : layer.fg,
    );
    label.paint(canvas, box.topLeft);
    if (complete) _paintBadgeText(canvas, t);
    canvas.restore();
  }

  /// Width of the badge: the full reward's text plus the padding, so the
  /// badge does not grow while the number counts up.
  double get _badgeWidth =>
      CollectText.of('+${reward ?? 0}', _badgeSize, _plum).width +
      PuzzleConfig.badgePad;

  /// The "+N" text's box in the badge's own coordinates (badge centre 0).
  static Rect _badgeTextBox(double bw, double width, double height) =>
      Rect.fromLTWH(-bw / 2 + _badgeTextX, 2 - height / 2, width, height);

  /// The coin badge's scale [ub] seconds after 4/4: the pop, times the count's
  /// bump at the end of the count.
  static double _badgeScale(double ub) {
    final s = CollectText.eob(ub / PuzzleConfig.badgePop);
    final land = ub - PuzzleConfig.countStart - PuzzleConfig.countLength;
    final bump = land > 0 && land < PuzzleConfig.bumpLength
        ? 1 +
              PuzzleConfig.bump *
                  math.sin(math.pi * land / PuzzleConfig.bumpLength)
        : 1.0;
    return s * bump;
  }

  void _paintBadgeText(Canvas canvas, double t) {
    final ub = t - badgeTime;
    if (ub <= 0) return;
    final bw = _badgeWidth;
    final text = CollectText.of('+${badgeCount(t)}', _badgeSize, _plum);
    canvas.save();
    canvas.translate(0, _badgeY);
    canvas.scale(_badgeScale(ub));
    final box = _badgeTextBox(bw, text.width, text.height);
    canvas.drawRect(
      box.inflate(_backingPad),
      _fill..color = const Color(0xFFFFFFFF),
    );
    text.paint(canvas, box.topLeft);
    canvas.restore();
  }

  void _paintBadge(Canvas canvas, double t) {
    final ub = t - badgeTime;
    if (ub <= 0) return;
    final coin = layer.coin;
    // 7 coins arc from the pill into the badge.
    for (var i = 0; i < PuzzleConfig.badgeCoins; i++) {
      final life = .45 + i * .05;
      final u = ub / life;
      if (u >= 1 || coin == null) continue;
      final e = Ease.cubicInOut(u);
      final x0 = _coinX[i], y0 = 0.0, x1 = 0.0, y1 = _badgeY;
      final cx = (x0 + x1) / 2 + 40, cy = math.min(y0, y1) - 20;
      final w = 1 - e;
      final p = Offset(
        w * w * x0 + 2 * w * e * cx + e * e * x1,
        w * w * y0 + 2 * w * e * cy + e * e * y1,
      );
      CoinIcon.paint(canvas, coin, p, 14);
    }
    final bw = _badgeWidth;
    final text = CollectText.of('+${badgeCount(t)}', _badgeSize, _plum);
    canvas.save();
    canvas.translate(0, _badgeY);
    canvas.scale(_badgeScale(ub));
    // The white badge keeps a window over its "+N" (drawn by the banner
    // layer, see [paintBanner]).
    final badge = Rect.fromCenter(
      center: Offset.zero,
      width: bw,
      height: PuzzleConfig.badgeHeight,
    );
    final window = _badgeTextBox(
      bw,
      text.width,
      text.height,
    ).inflate(_windowPad);
    canvas.drawPath(
      _outside(badge, window),
      _fill..color = const Color(0xFFFFFFFF),
    );
    if (coin != null) {
      CoinIcon.paint(
        canvas,
        coin,
        Offset(-bw / 2 + 17, 0),
        PuzzleConfig.badgeCoin,
      );
    }
    canvas.restore();
  }
}
