import 'package:flappy_spikes/versus/brackets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§3.13 best-score brackets', () {
    test('§3.13 the thresholds are the 2.5 pool thresholds, unchanged', () {
      expect(kBestBrackets, [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000]);
      expect(kBestBrackets, hasLength(10));
    });

    test('§3.13 bracketFor covers brackets 0–10 at the boundaries', () {
      expect(bracketFor(0), 0);
      for (var i = 0; i < kBestBrackets.length; i++) {
        expect(bracketFor(kBestBrackets[i] - 1), i, reason: 'below ${kBestBrackets[i]}');
        expect(bracketFor(kBestBrackets[i]), i + 1, reason: 'at ${kBestBrackets[i]}');
      }
      expect(bracketFor(99999), 10);
    });
  });
}
