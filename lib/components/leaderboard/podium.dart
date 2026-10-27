import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import '../../leaderboard/lb_models.dart';
import '../../skins/art/card_name_art.dart';
import 'board_row.dart' show cardSlot, paintBoardAvatar;
import '../sticker_avatar.dart';
import '../ui/mystery_box.dart';

/// Three prize places, in the approved 2 / 1 / 3 arrangement.
class BoardPodium extends PositionComponent {
  BoardPodium(this.rows, {required this.today, this.ownId})
    : super(position: Vector2(0, 145), size: Vector2(320, 179));
  final List<LbBoardRow> rows;
  final bool today;
  final String? ownId;
  double time = 0;
  final StickerAvatars avatars = StickerAvatars();
  static const _plum = Color(0xff7a0044), _pink = Color(0xffec008c);
  void label(
    Canvas canvas,
    String value,
    double x,
    double y,
    double fontSize,
    Color color, {
    double maxWidth = 84,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(
      canvas,
      Offset(x - painter.width / 2, y - painter.height / 2),
    );
  }

  @override
  void render(Canvas canvas) {
    for (final rank in [2, 1, 3]) {
      final found = rows.where((r) => r.rank == rank);
      final row = found.isEmpty ? null : found.first;
      final x = rank == 2
          ? 60.0
          : rank == 1
          ? 160.0
          : 260.0;
      final top = rank == 2
          ? 81.0
          : rank == 1
          ? 63.0
          : 89.0;
      final tier = MysteryBoxTier.values[rank - 1];
      canvas.drawRect(
        Rect.fromLTWH(x - 46, top, 92, 179 - top),
        Paint()..color = tier.main.withValues(alpha: row == null ? .35 : 1),
      );
      if (row?.rid == ownId && row != null) {
        canvas.drawRect(
          Rect.fromLTWH(x - 44.5, top + 1.5, 89, 176 - top),
          Paint()
            ..color = _pink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (row != null) {
        final s = rank == 1 ? 46.0 : 40.0;
        paintBoardAvatar(
          canvas,
          avatars,
          row,
          Rect.fromCenter(
            center: Offset(x, top - s / 2 - 7),
            width: s,
            height: s,
          ),
          time,
        );
        canvas.drawRect(
          Rect.fromLTWH(x - 42, 101, 84, 19),
          Paint()..color = const Color(0xffffffff),
        );
        CardNameArt.paint(
          canvas,
          cardSlot(row, 1),
          row.name,
          t: time,
          center: Offset(x, 110.5),
          fontSize: 12,
          maxWidth: 78,
        );
        canvas.drawRect(
          Rect.fromLTWH(x - 23, 125, 46, 20),
          Paint()..color = _pink,
        );
        label(canvas, '${row.points}', x, 135, 15, const Color(0xffffffff));
        label(
          canvas,
          row.playingNow == true ? 'PLAYING NOW' : lastRunTag(row.lastAt),
          x,
          158,
          8,
          _plum,
        );
      } else {
        label(canvas, '?', x, top - 25, 18, const Color(0xffbdbdbd));
      }
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, top + 5), width: 22, height: 22),
        Paint()..color = tier.dark,
      );
      label(canvas, '$rank', x, top + 5, 14, const Color(0xffffffff));
      if (today) {
        canvas.save();
        canvas.translate(x + 33, top - 11);
        MysteryBox.paint(
          canvas,
          MysteryBoxLook.colours(
            tier.main,
            tier.dark,
            label: null,
            ribbon: _pink,
          ),
          size: 30,
        );
        canvas.restore();
      }
    }
  }

  @override
  void onRemove() {
    avatars.clear();
    super.onRemove();
  }
}

String lastRunTag(int? lastAt) {
  if (lastAt == null) return '';
  final mins = ((DateTime.now().millisecondsSinceEpoch - lastAt) ~/ 60000)
      .clamp(0, 99999999);
  if (mins < 60) return '${mins}m ago';
  if (mins < 1440) return '${mins ~/ 60}h ago';
  return '${mins ~/ 1440}d ago';
}
