import 'package:flappy_spikes/components/star_road/star_road_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('track viewport fits both supported heights and all 25 rows', () {
    for (final height in [568.0, 711.0]) {
      final viewport = StarRoadLayout.viewport(height);
      expect(viewport.top, 252);
      expect(viewport.bottom, height);
      expect(StarRoadLayout.header.bottom, lessThan(viewport.top));
    }
    for (var tier = 1; tier < 25; tier++) {
      expect(
        StarRoadLayout.rowTop(tier + 1),
        greaterThan(StarRoadLayout.rowTop(tier)),
      );
    }
  });
}
