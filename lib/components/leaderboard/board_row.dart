import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import '../../leaderboard/lb_models.dart';
import '../../skins/art/card_frame_art.dart';
import '../../skins/art/card_name_art.dart';
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
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    p.paint(c, at);
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
    text(
      canvas,
      formatBoardRank(row.rank, approximate: approximate),
      const Offset(5, 12),
      approximate ? 9 : 15,
      own ? pink : plum,
      maxWidth: 36,
    );
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
      center: const Offset(146, 13),
      fontSize: 13,
      maxWidth: 124,
    );
    text(canvas, statusText, const Offset(84, 25), 8.5, plum);
    if (own) text(canvas, 'YOU', const Offset(202, 26), 8, pink);
    final score = TextPainter(
      text: TextSpan(
        text: '${row.points}',
        style: const TextStyle(
          color: Color(0xffffffff),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillWidth = (score.width + 16).clamp(46.0, 100.0);
    canvas.drawRect(
      Rect.fromLTWH(284 - pillWidth, 12, pillWidth, 20),
      Paint()..color = pink,
    );
    score.paint(canvas, Offset(284 - pillWidth / 2 - score.width / 2, 13));
  }

  @override
  void onRemove() {
    avatars.clear();
    super.onRemove();
  }
}

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
