// PRD-2.3.1 §12.6 / §12.9 the iOS kit matches the catalog exactly (the iOS
// ids in the code are the ones App Store Connect receives), with a 1024 px
// RGB icon per achievement and a 512 px Play icon.
import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/ach_ios_kit.dart' as kit;

void main() {
  const dir = 'store/achievements/ios';

  test('§12.9 the committed kit equals the one generated from the catalog', () {
    expect(File('$dir/achievements_ios.csv').readAsStringSync(), kit.kitCsv());
    expect(File('$dir/achievements_ios.json').readAsStringSync(), kit.kitJson());
    final rows = (jsonDecode(kit.kitJson()) as List).cast<Map>();
    expect(rows.map((r) => r['Achievement ID']),
        AchievementId.values.map((a) => 'fs_ach_${a.key}'));
    expect(rows.where((r) => r['Hidden'] == 'yes'), hasLength(17)); // §19.3
    expect(rows.fold<int>(0, (s, r) => s + (r['Points'] as int)), 755);
  });

  test('§12.6 every key has its 1024 iOS (RGB, no alpha) and 512 Play icon',
      () {
    int u32(List<int> b, int o) =>
        (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    for (final a in AchievementId.values) {
      for (final (path, size, rgb) in [
        ('$dir/ach_${a.key}.png', 1024, true),
        ('store/achievements/play/ach_${a.key}.png', 512, false),
      ]) {
        final b = File(path).readAsBytesSync();
        // PNG IHDR: width, height, then bit depth and colour type (2 = RGB).
        expect(u32(b, 16), size, reason: path);
        expect(u32(b, 20), size, reason: path);
        if (rgb) expect(b[25], 2, reason: '$path is RGB without alpha');
        expect(b.length, lessThan(1024 * 1024), reason: '$path ≤ 1 MB');
      }
    }
  });
}
