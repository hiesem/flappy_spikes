import 'dart:convert';

import 'package:flappy_spikes/levels/level_track.dart';

/// PRD-2.6 J5: explicit 2.6 test setup, never a product migration.
/// Keeps old keys in fixtures so tests also catch accidental old-key writes.
Map<String, Object> trackPrefs(Map<String, Object> old) {
  final index = old['lvlIndex'] as int? ?? old['playerLevel'] as int? ?? 0;
  final claimed = (old['claimedLevels'] as List?)?.toSet() ?? {};
  return {
    ...old,
    'lvlIndex': index,
    'lvlPending':
        old['lvlPending'] ??
        jsonEncode([
          for (var l = 1; l <= index; l++)
            if (!old.containsKey('lvlIndex') && !claimed.contains('$l'))
              {
                'lvl': l,
                'coins': trackLevelDef(l)!.coins,
                'item': null,
                'extraCoins': 0,
                'fallback': 'none',
              },
        ]),
  };
}
