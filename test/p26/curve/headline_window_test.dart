import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/run/director/headline_window.dart';

void main() {
  test('a second headline due inside the window waits', () {
    final window = HeadlineWindow();

    expect(window.allows('ride', 10), isTrue);
    window.add('ride', 10);

    for (var hoop = 11; hoop < 18; hoop++) {
      expect(window.allows('squeeze', hoop), isFalse);
    }
    expect(window.delayedUntil('squeeze', 13), 18);
    expect(window.allows('squeeze', 18), isTrue);
  });

  test('a blocked due item is released after five hoops', () {
    final window = HeadlineWindow();
    window.add('ride', 20);

    expect(window.allows('first-meet', 21), isFalse);
    expect(window.delayedUntil('first-meet', 21), 26);
    expect(window.allows('first-meet', 25), isFalse);
    expect(window.allows('first-meet', 26), isTrue);
    window.add('first-meet', 26);

    expect(window.allows('bonus', 33), isFalse);
    expect(window.allows('bonus', 34), isTrue);
  });

  test('items outside the window and first headlines run immediately', () {
    final window = HeadlineWindow();
    expect(window.delayedUntil('introduction', 7), 7);

    window.add('introduction', 7);
    expect(window.delayedUntil('big-bonus', 15), 15);
    expect(window.allows('big-bonus', 15), isTrue);
  });
}
