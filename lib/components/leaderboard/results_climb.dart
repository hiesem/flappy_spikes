import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../leaderboard/lb_config.dart';
import '../../leaderboard/lb_models.dart';
import '../../run/config/results_config.dart';
import '../../run/effects/easing.dart';
import '../../run/effects/gold_sticker.dart';
import '../home/menu_primitives.dart';
import 'board_row.dart';
import 'board_screen.dart' show BoardTimerChip, formatBoardTime;
import 'podium.dart';

/// The transient TODAY board over the results page (PRD LB1 / O53, O62).
class ResultsClimb extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  ResultsClimb._(this.board, this.from, this.to) : super(priority: 100);

  static ResultsClimb? fromSubmit(
    LbSubmitRunResult? result, {
    required int gamesPlayed,
  }) {
    final rank = result?.rank;
    final from = rank?.before, to = rank?.after;
    final board = result?.board;
    if (gamesPlayed <= LbConfig.resultsMinGames ||
        from == null ||
        to == null ||
        to < 1 ||
        from <= to ||
        board == null ||
        board.tab != LbBoardTab.today ||
        board.me == null) {
      return null;
    }
    return ResultsClimb._(board, from, to);
  }

  final LbBoardPayload board;
  final int from, to;
  int get spots => from - to;
  double get climbDuration => spots == 1
      ? .55
      : spots <= 3
      ? 1.1
      : 2.3;
  double get end => 1.45 + climbDuration;
  String get stickerText =>
      spots == 1 ? 'YOU CLIMBED 1 SPOT!' : 'YOU CLIMBED $spots SPOTS!';
  double _time = 0;
  double? _dismiss;
  int _ticks = 0;
  int _shownRank = -1;
  bool _whoosh = false, _chime = false;
  late PositionComponent _card;
  late PositionComponent _list;
  late BoardRow _own;
  late GoldSticker _sticker;
  late MenuText _tap;
  MenuText? _timer;
  final List<(BoardRow, int)> _others = [];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(320, game.viewHeight);
    final k = ResultsConfig.scaleFor(game.viewHeight);
    final top =
        ResultsConfig.topFor(game.viewHeight) - ResultsConfig.contentTop * k;
    final column = PositionComponent(
      position: Vector2(160 * (1 - k), top),
      scale: Vector2.all(k),
      size: Vector2(320, 711),
    );
    add(column);
    _card = PositionComponent(size: Vector2(320, 711));
    column.add(_card);
    _card.add(_Panel());
    _card.add(
      MenuText(
        'LEADERBOARD',
        fontSize: 19,
        color: const Color(0xffffd9ee),
        position: Vector2(22, 104),
      ),
    );
    if (board.group != null) {
      final chip = BoardTimerChip()
        ..position = Vector2(250, 116)
        ..chipWidth = 96
        ..visible = true
        ..stopwatch = true;
      _card.add(chip);
      _timer = MenuText(
        '',
        fontSize: 11,
        color: const Color(0xff7a0044),
        position: Vector2(256, 116),
        anchor: Anchor.center,
      );
      _card.add(_timer!);
    }
    final podium = BoardPodium(board.rows, today: true, ownId: board.me!.rid)
      ..position = Vector2(35, 135)
      ..scale = Vector2.all(.78);
    _card.add(podium);
    _list = _ClippedList()..position = Vector2(0, 283);
    _card.add(_list);
    for (final row in board.rows) {
      if (row.rid == board.me!.rid || row.rank < 4) continue;
      final original = row.rank > to && row.rank <= from
          ? row.rank - 1
          : row.rank;
      final item = BoardRow(row, own: false);
      _others.add((item, original));
      _list.add(item);
    }
    _shownRank = from;
    _own = BoardRow(_withRank(board.me!, from), own: true);
    _list.add(_own);
    _sticker = GoldSticker.collect(stickerText, position: Vector2(160, 64))
      ..opacity = 0;
    _card.add(_sticker);
    _tap = MenuText(
      'TAP TO CONTINUE',
      fontSize: 17,
      color: Config.menuPink,
      letterSpacingEm: .12,
      position: Vector2(160, 612),
      anchor: Anchor.center,
    );
    _tap.text = '';
    _card.add(_tap);
    game.services.track('lb_board_open', {
      'source': 'results',
      'tab': 'today',
      'rank': to,
    });
    game.services.track('lb_climb', {'from': from, 'to': to, 'shown': true});
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final group = board.group;
    if (group != null) {
      _timer?.text = formatBoardTime(
        group.end.difference(game.storage.now()).inSeconds,
      );
    }
    if (!_whoosh && _time >= .5) {
      _whoosh = true;
      game.sound.play(Sfx.vsWhoosh);
    }
    final entrance = Ease.outQuad(((_time - .5) / .5).clamp(0.0, 1.0));
    final out = _dismiss == null
        ? 0.0
        : ((_time - _dismiss!) / .35).clamp(0.0, 1.0);
    _card.position.y = (1 - entrance) * 640 + out * 720;
    final u = ((_time - 1.45) / climbDuration).clamp(0.0, 1.0);
    final progress = Ease.cubicInOut(u);
    final rank = from - spots * progress;
    final window = (rank - 4).clamp(4.0, 45.0);
    double y(double place) => 3 + (place - window) * 48;
    final shownRank = rank.round();
    if (_shownRank != shownRank) {
      _shownRank = shownRank;
      _own.removeFromParent();
      _own = BoardRow(_withRank(board.me!, shownRank), own: true);
      _list.add(_own);
    }
    _own.position = Vector2(14, y(rank));
    for (final (row, original) in _others) {
      final slot = original >= to && original < from
          ? original + (original + 1 - rank).clamp(0.0, 1.0)
          : original.toDouble();
      row.position = Vector2(14, y(slot));
    }
    final due = math.min(spots, (progress * spots + .5).floor());
    while (_ticks < due) {
      _ticks++;
      game.sound.play(Sfx.vsTick);
    }
    if (!_chime && _time >= end) {
      _chime = true;
      _sticker.opacity = 1;
      _sticker.restart();
      game.sound.play(Sfx.vsChime);
    }
    _tap.text = _time >= end + .6 && _dismiss == null ? 'TAP TO CONTINUE' : '';
    if (out >= 1) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final out = _dismiss == null
        ? 0.0
        : ((_time - _dismiss!) / .35).clamp(0.0, 1.0);
    final a = ((_time - .5) / .3).clamp(0.0, 1.0) * .72 * (1 - out);
    canvas.drawRect(
      size.toRect(),
      Paint()..color = const Color(0xff282830).withValues(alpha: a),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    dismiss();
  }

  void dismiss() {
    if (_time >= end + .6 && _dismiss == null) {
      _dismiss = _time;
      game.sound.play(Sfx.skTap);
    }
  }
}

class _Panel extends PositionComponent {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(10, 96, 300, 552),
      Paint()..color = const Color(0xfff1f1f1),
    );
    canvas.drawRect(
      const Rect.fromLTWH(10, 96, 300, 40),
      Paint()..color = Config.menuPink,
    );
  }
}

class _ClippedList extends PositionComponent {
  _ClippedList() : super(size: Vector2(320, 289));
  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(position.toOffset() & size.toSize());
    super.renderTree(canvas);
    canvas.restore();
  }
}

LbBoardRow _withRank(LbBoardRow row, int rank) => LbBoardRow(
  rid: row.rid,
  rank: rank,
  name: row.name,
  look: row.look,
  points: row.points,
  card: row.card,
  lastAt: row.lastAt,
  playingNow: row.playingNow,
);
