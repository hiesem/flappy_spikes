import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import '../../game/config.dart';
import '../../leaderboard/lb_models.dart';
import '../../skins/art/card_frame_art.dart';
import '../../skins/art/card_name_art.dart';
import '../home/menu_primitives.dart' show MenuTag;
import '../sticker_avatar.dart';
import 'podium.dart' show lastRunTag;

class BoardRow extends PositionComponent {
  BoardRow(
    this.row, {
    required this.own,
    this.approximate = false,
    super.position,
    super.priority,
  }) : super(size: Vector2(292, 44));
  final LbBoardRow row;
  final bool own, approximate;
  bool visible = true;
  double time = 0;
  final StickerAvatars avatars = StickerAvatars();
  String get statusText =>
      row.playingNow == true ? 'PLAYING NOW' : lastRunTag(row.lastAt);
  List<String> get displayedText => [
    formatBoardRank(row.rank, approximate: approximate),
    row.name,
    statusText,
    if (own) 'YOU',
    '${row.points}',
  ];
  void text(
    Canvas c,
    String value,
    Offset at,
    double fontSize,
    Color color, {
    double maxWidth = 124,
    String fontFamily = Config.uiFont,
    double? centerX,
    double? centerY,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    p.paint(
      c,
      Offset(
        centerX == null ? at.dx : centerX - p.width / 2,
        centerY == null ? at.dy : centerY - p.height / 2,
      ),
    );
    p.dispose();
  }

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    const pink = Color(0xffec008c), plum = Color(0xff7a0044);
    canvas.drawRect(
      size.toRect(),
      Paint()..color = own ? const Color(0xffffd9ee) : const Color(0xffffffff),
    );
    if (own) {
      canvas.drawRect(
        size.toRect().deflate(1),
        Paint()
          ..color = pink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // region P26-FIX3
    final rank = formatBoardRank(row.rank, approximate: approximate);
    text(
      canvas,
      rank,
      Offset.zero,
      _boardRowRankFontSize(rank),
      own ? pink : plum,
      maxWidth: 36,
      centerX: 20,
      centerY: 23,
    );
    // endregion P26-FIX3
    paintBoardAvatar(
      canvas,
      avatars,
      row,
      const Rect.fromLTWH(43, 7, 30, 30),
      time,
    );
    CardNameArt.paint(
      canvas,
      cardSlot(row, 1),
      row.name,
      t: time,
      // region P26-FIX3
      center: const Offset(84, 14.5),
      start: true,
      // endregion P26-FIX3
      fontSize: 13,
      maxWidth: 124,
    );
    // region P26-FIX3
    if (own) {
      MenuTag.paintTag(
        canvas,
        'YOU',
        const Offset(84, 32),
        fillColor: const Color(0xffffc233),
        textColor: plum,
      );
    } else if (row.playingNow == true) {
      MenuTag.paintTag(
        canvas,
        statusText,
        const Offset(84, 32),
        fillColor: pink,
        textColor: const Color(0xffffffff),
        dot: true,
        time: time,
      );
    } else {
      MenuTag.paintTag(
        canvas,
        statusText,
        const Offset(84, 32),
        fillColor: const Color(0xffe4e4e4),
        textColor: const Color(0xff7e7e7e),
      );
    }
    // endregion P26-FIX3
    final score = TextPainter(
      text: TextSpan(
        text: '${row.points}',
        style: const TextStyle(
          color: Color(0xffffffff),
          // region P26-FIX3
          fontSize: 15,
          fontFamily: Config.uiFont,
          // endregion P26-FIX3
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillWidth = (score.width + 16).clamp(46.0, 284.0);
    canvas.drawRect(
      Rect.fromLTWH(284 - pillWidth, 12, pillWidth, 20),
      Paint()..color = pink,
    );
    score.paint(
      canvas,
      Offset(284 - pillWidth / 2 - score.width / 2, 22.8 - score.height / 2),
    );
    score.dispose();
  }

  @override
  void onRemove() {
    avatars.clear();
    super.onRemove();
  }
}

// region P26-FIX3
double _boardRowRankFontSize(String rank) => rank.length > 4
    ? 11
    : rank.length > 3
    ? 12.5
    : rank.length > 2
    ? 14
    : 17;

// endregion P26-FIX3

String cardSlot(LbBoardRow row, int slot) {
  final parts = (row.card ?? row.look.card).split('|');
  return parts.length == 3 ? parts[slot] : '';
}

void paintBoardAvatar(
  Canvas canvas,
  StickerAvatars avatars,
  LbBoardRow row,
  Rect rect,
  double time,
) {
  final id = cardSlot(row, 0);
  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  CardFrameArt.paintBack(canvas, id, size: rect.width, t: time);
  canvas.restore();
  avatars.paint(canvas, rect, row.look);
  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  CardFrameArt.paintFront(canvas, id, size: rect.width, t: time);
  canvas.restore();
}

String formatBoardRank(int rank, {bool approximate = false}) {
  if (rank <= 0) return '–';
  if (!approximate) return '$rank';
  final masked = rank >= 100 ? '${rank ~/ 100}xx' : '$rank';
  final parts = <String>[];
  var end = masked.length;
  while (end > 3) {
    parts.insert(0, masked.substring(end - 3, end));
    end -= 3;
  }
  parts.insert(0, masked.substring(0, end));
  return '#~${parts.join('\u2009')}';
}
