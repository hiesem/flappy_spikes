import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_tables.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/seams/seam.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.4 §4 test 7: the scene index by hoop (world distance 300 per hoop,
/// hoop h at the screen centre ⇔ world distance 300·h).
void main() {
  double at(num hoop) => hoop * kPerHoop;

  test('hoops 0–39 are Nest Canopy (no Homecoming in the first loop)', () {
    for (var h = 0; h < 40; h++) {
      expect(BackdropWorld.sceneAt(at(h)), 0, reason: 'hoop $h');
    }
    // the run starts a little before hoop 0's plane reaches the centre
    expect(BackdropWorld.sceneAt(-126), 0);
  });

  test('the seam into Sky & Hills is centred on hoop 40', () {
    final s = BackdropWorld.seamAt(at(40));
    expect(s.j, 1);
    expect(s.d, 0);
    expect(kSeams[s.j - 1], isA<FloorSeam>());
    expect(kSeams[s.j - 1].title, 'Treetop waterfall');
    expect(BackdropWorld.sceneAt(at(40) - 1), 0);
    expect(BackdropWorld.sceneAt(at(40) + 1), 1);
    // its window spans hoops 35–45
    expect(kVWIN / kPerHoop, 10);
  });

  test('scene k spans hoops 40k–40k+39; seam k centred on hoop 40k', () {
    for (var k = 1; k < 10; k++) {
      expect(BackdropWorld.sceneAt(at(40 * k + 20)), k, reason: 'scene $k');
      expect(BackdropWorld.seamAt(at(40 * k)).d, 0);
      expect(BackdropWorld.seamAt(at(40 * k)).j, k);
    }
    expect(kScenes.map((s) => s.name), [
      'Nest Canopy',
      'Sky & Hills',
      'City Skyline',
      'Clockwork',
      "Giant's Desk",
      'Candy Land',
      'Paper Origami',
      'Underwater',
      'Dreamland',
      'Space',
    ]);
  });

  test('after hoop 400 the world is back in Nest Canopy (Homecoming plays)', () {
    expect(BackdropWorld.sceneAt(at(399)), 9);
    final s = BackdropWorld.seamAt(at(400));
    expect(s.j, 10);
    expect(kSeams[(s.j - 1) % 10].title, 'Homecoming');
    expect(BackdropWorld.sceneAt(at(401)), 0);
    for (var h = 410; h < 440; h++) {
      expect(BackdropWorld.sceneAt(at(h)), 0, reason: 'hoop $h');
    }
    expect(BackdropWorld.sceneAt(at(440 + 20)), 1);
    expect(BackdropWorld.sceneAt(at(800 + 20)), 0);
  });
}
