import '../skins/look.dart';
import '../versus/run_entry.dart' show lookToMap;

/// Callable payloads mirror functions/src/board.ts. Row ids are opaque;
/// neither player ids nor ghost identities belong in the client contract.
enum LbBoardTab { today, best }

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value as Map);
int _int(Object? value) => (value as num).toInt();
int? _optionalInt(Object? value) => value == null ? null : _int(value);

/// Admin Firestore Timestamps are JSON objects in callable responses, not
/// Flutter Firestore Timestamp instances. Numeric fields elsewhere are ms.
DateTime? lbTimestamp(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  final json = _map(value);
  final seconds = _int(json['_seconds'] ?? json['seconds']);
  final nanos = _int(json['_nanoseconds'] ?? json['nanoseconds'] ?? 0);
  return DateTime.fromMicrosecondsSinceEpoch(
    seconds * Duration.microsecondsPerSecond + nanos ~/ 1000,
    isUtc: true,
  );
}

class LbBoardRow {
  const LbBoardRow({
    required this.rid,
    required this.rank,
    required this.name,
    required this.look,
    required this.points,
    this.card,
    this.best,
    this.lastAt,
    this.playingNow,
  });

  factory LbBoardRow.fromJson(Map<String, Object?> json) => LbBoardRow(
    rid: json['rid'] as String,
    rank: _int(json['rank']),
    name: json['name'] as String,
    look: Look.fromJson(_map(json['look'])),
    points: _int(json['points']),
    card: json['card'] as String?,
    best: _optionalInt(json['best']),
    lastAt: _optionalInt(json['lastAt']),
    playingNow: json['playingNow'] as bool?,
  );

  final String rid;

  /// BEST rank zero means the owner is not ranked; never turn it into #1.
  final int rank;
  final String name;
  final Look look;
  final String? card;
  final int points;
  final int? best;
  final int? lastAt;
  final bool? playingNow;
}

class LbBoardGroup {
  const LbBoardGroup({
    required this.bracket,
    required this.start,
    required this.end,
  });
  factory LbBoardGroup.fromJson(Map<String, Object?> json) => LbBoardGroup(
    bracket: _int(json['bracket']),
    start: lbTimestamp(json['start'])!,
    end: lbTimestamp(json['end'])!,
  );
  final int bracket;
  final DateTime start;
  final DateTime end;
}

class LbGiftRoll {
  const LbGiftRoll({
    required this.kind,
    required this.coins,
    this.item,
    this.rarity,
    this.seed,
  });
  factory LbGiftRoll.fromJson(Map<String, Object?> json) => LbGiftRoll(
    kind: json['kind'] as String,
    coins: _int(json['coins']),
    item: json['item'] as String?,
    rarity: json['rarity'] as String?,
    seed: json['seed'] as String?,
  );
  final String kind;
  final int coins;
  final String? item;
  final String? rarity;
  final String? seed;
}

/// A board gift stub or a full gift from a submit response.
class LbGift {
  const LbGift({
    required this.gid,
    required this.tier,
    required this.boardRank,
    this.claimedAt,
    this.rolled,
    this.expireAt,
    // region P26-LB7
    this.createdAt,
    this.finalBoard = const [],
    this.playerCount = 0,
    // endregion
  });
  factory LbGift.fromJson(Map<String, Object?> json) => LbGift(
    gid: json['gid'] as String,
    tier: json['tier'] as String,
    boardRank: _int(json['boardRank']),
    claimedAt: lbTimestamp(json['claimedAt']),
    rolled: json['rolled'] == null
        ? null
        : LbGiftRoll.fromJson(_map(json['rolled'])),
    expireAt: lbTimestamp(json['expireAt']),
    // region P26-LB7
    createdAt: lbTimestamp(json['createdAt']),
    finalBoard: List.unmodifiable(
      (json['finalBoard'] as List? ?? []).map((row) {
        final data = _map(row);
        if (data['name'] == null || data['look'] == null) {
          return LbBoardRow(
            rid: data['rid'] as String,
            rank: _int(data['rank']),
            name: 'PLAYER',
            look: Look.defaults,
            points: _int(data['points']),
          );
        }
        return LbBoardRow.fromJson(data);
      }),
    ),
    playerCount: _optionalInt(json['playerCount']) ?? 0,
    // endregion
  );
  final String gid;
  final String tier;
  final int boardRank;
  final DateTime? claimedAt;
  final LbGiftRoll? rolled;
  final DateTime? expireAt;
  // region P26-LB7
  final DateTime? createdAt;
  final List<LbBoardRow> finalBoard;
  final int playerCount;
  // endregion
}

class LbBoardPayload {
  const LbBoardPayload({
    required this.tab,
    required this.rows,
    this.me,
    this.floor,
    this.approximate = false,
    this.group,
    this.gifts = const [],
  });
  factory LbBoardPayload.fromJson(Map<String, Object?> json) {
    final tab = LbBoardTab.values.byName(json['tab'] as String);
    LbBoardRow row(Object? value) {
      final data = _map(value);
      // O62: discard even a legacy server's BEST field on TODAY.
      if (tab == LbBoardTab.today) data.remove('best');
      return LbBoardRow.fromJson(data);
    }

    return LbBoardPayload(
      tab: tab,
      rows: List.unmodifiable((json['rows'] as List).map(row)),
      me: json['me'] == null ? null : row(json['me']),
      floor: _optionalInt(json['floor']),
      approximate: json['approximate'] == true,
      group: json['group'] == null
          ? null
          : LbBoardGroup.fromJson(_map(json['group'])),
      gifts: List.unmodifiable(
        (json['gifts'] as List? ?? []).map((v) => LbGift.fromJson(_map(v))),
      ),
    );
  }
  final LbBoardTab tab;
  final List<LbBoardRow> rows;
  final LbBoardRow? me;
  final int? floor;
  final bool approximate;
  final LbBoardGroup? group;
  final List<LbGift> gifts;
}

class LbGetBoardResult {
  const LbGetBoardResult({
    required this.today,
    required this.best,
    this.bestAllTime,
  });
  factory LbGetBoardResult.fromJson(Map<String, Object?> json) =>
      LbGetBoardResult(
        today: LbBoardPayload.fromJson(_map(json['today'])),
        best: LbBoardPayload.fromJson(_map(json['best'])),
        bestAllTime: _optionalInt(json['bestAllTime']),
      );
  final LbBoardPayload today;
  final LbBoardPayload best;
  final int? bestAllTime;
}

class LbGroupRef {
  const LbGroupRef({
    required this.id,
    required this.end,
    required this.bracket,
  });
  factory LbGroupRef.fromJson(Map<String, Object?> json) => LbGroupRef(
    id: json['id'] as String,
    end: _int(json['end']),
    bracket: _int(json['bracket']),
  );
  final String id;
  final int end;
  final int bracket;
}

class LbRankChange {
  const LbRankChange({this.before, this.after});
  factory LbRankChange.fromJson(Map<String, Object?> json) => LbRankChange(
    before: _optionalInt(json['before']),
    after: _optionalInt(json['after']),
  );
  final int? before;
  final int? after;
}

class LbDroppedRun {
  const LbDroppedRun({required this.id, required this.reason});
  factory LbDroppedRun.fromJson(Map<String, Object?> json) =>
      LbDroppedRun(id: json['id'] as String, reason: json['reason'] as String);
  final String id;
  final String reason;
}

class LbSubmitRunResult {
  const LbSubmitRunResult({
    required this.accepted,
    required this.dropped,
    this.group,
    this.rank,
    this.board,
    this.gifts,
  });
  factory LbSubmitRunResult.fromJson(Map<String, Object?> json) =>
      LbSubmitRunResult(
        accepted: List.unmodifiable((json['accepted'] as List).cast<String>()),
        dropped: List.unmodifiable(
          (json['dropped'] as List).map((v) => LbDroppedRun.fromJson(_map(v))),
        ),
        group: json['group'] == null
            ? null
            : LbGroupRef.fromJson(_map(json['group'])),
        rank: json['rank'] == null
            ? null
            : LbRankChange.fromJson(_map(json['rank'])),
        board: json['board'] == null
            ? null
            : LbBoardPayload.fromJson(_map(json['board'])),
        gifts: json['gifts'] == null
            ? null
            : List.unmodifiable(
                (json['gifts'] as List).map((v) => LbGift.fromJson(_map(v))),
              ),
      );
  final List<String> accepted;
  final List<LbDroppedRun> dropped;
  final LbGroupRef? group;
  final LbRankChange? rank;
  final LbBoardPayload? board;
  final List<LbGift>? gifts;
}

class LbClaimGiftResult {
  const LbClaimGiftResult({required this.ok, this.id, this.tier, this.prize});
  factory LbClaimGiftResult.fromJson(Map<String, Object?> json) =>
      LbClaimGiftResult(
        ok: json['ok'] as bool,
        id: json['id'] as String?,
        tier: json['tier'] as String?,
        prize: json['prize'] == null
            ? null
            : LbGiftRoll.fromJson(_map(json['prize'])),
      );
  final bool ok;
  final String? id;
  final String? tier;
  final LbGiftRoll? prize;
}

class LbClaimGiftRequest {
  const LbClaimGiftRequest({required this.id, this.owned});
  final String id;
  final List<String>? owned;
  Map<String, Object?> toJson() => {
    'id': id,
    if (owned != null) 'owned': owned,
  };
}

/// Mirrors board.ts:58–80. cs is the full run duration, not the tail delta.
class LbSubmittedRun {
  const LbSubmittedRun({
    required this.id,
    required this.score,
    required this.hoops,
    required this.cs,
    required this.endTs,
    required this.mode,
    this.tl,
    this.fl,
  });
  final String id;
  final int score, hoops, cs, endTs;
  final String mode;
  final String? tl, fl;
  factory LbSubmittedRun.fromJson(Map<String, Object?> json) => LbSubmittedRun(
    id: json['id'] as String,
    score: _int(json['score']),
    hoops: _int(json['hoops']),
    cs: _int(json['cs']),
    endTs: _int(json['endTs']),
    mode: json['mode'] as String,
    tl: json['tl'] as String?,
    fl: json['fl'] as String?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'score': score,
    'hoops': hoops,
    'cs': cs,
    'endTs': endTs,
    'mode': mode,
    if (tl != null) 'tl': tl,
    if (fl != null) 'fl': fl,
  };
}

class LbSubmitRunRequest {
  const LbSubmitRunRequest({
    required this.runs,
    this.name,
    this.look,
    this.card,
    this.platform,
    this.t,
  });
  final List<LbSubmittedRun> runs;
  final String? name, card, platform;
  final Look? look;
  final int? t;
  Map<String, Object?> toJson() => {
    'runs': runs.map((r) => r.toJson()).toList(),
    if (name != null) 'name': name,
    if (look != null) 'look': lookToMap(look!),
    if (card != null) 'card': card,
    if (platform != null) 'platform': platform,
    if (t != null) 't': t,
  };
}
