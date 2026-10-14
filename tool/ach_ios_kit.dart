// PRD-2.3.1 §12.6 the Game Center upload kit, generated from the catalog
// (never by hand): store/achievements/ios/achievements_ios.csv and .json.
// The 1024 px icons next to them come from tool/export_achievement_icons.py.
//
//   dart run tool/ach_ios_kit.dart
import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';

/// One kit row per achievement (the App Store Connect fields).
List<Map<String, Object>> kitRows() => [
  for (final a in AchievementId.values)
    {
      'Reference Name': a.title,
      'Achievement ID': a.iosId,
      'Points': a.points,
      'Hidden': a.hidden ? 'yes' : 'no',
      'Achievable More Than Once': 'no',
      'Localization': 'English (U.S.)',
      'Title': a.title,
      'Pre-earned Description': a.description,
      'Earned Description': a.earned,
      'Image': 'ach_${a.key}.png',
    },
];

String _csvCell(Object v) {
  final s = '$v';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String kitCsv() {
  final rows = kitRows();
  final head = rows.first.keys.toList();
  return [
    head.map(_csvCell).join(','),
    for (final r in rows) head.map((k) => _csvCell(r[k]!)).join(','),
  ].join('\n') + '\n';
}

String kitJson() =>
    '${const JsonEncoder.withIndent('  ').convert(kitRows())}\n';

void main() {
  const dir = 'store/achievements/ios';
  Directory(dir).createSync(recursive: true);
  File('$dir/achievements_ios.csv').writeAsStringSync(kitCsv());
  File('$dir/achievements_ios.json').writeAsStringSync(kitJson());
  stdout.writeln('wrote $dir/achievements_ios.{csv,json} '
      '(${AchievementId.values.length} achievements)');
}
