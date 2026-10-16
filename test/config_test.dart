import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('world & physics constants (SPEC.md)', () {
    test('virtual resolution is the original 320x568 canvas', () {
      expect(Config.worldWidth, 320);
      expect(Config.worldHeight, 568);
    });

    test('gravity targets ~1250 pt/s^2 downward', () {
      expect(Config.gravity, 1250);
    });

    test('flap delta-v is ~370 pt/s (tuned for the 45-65 pt rise band)', () {
      // SPEC allows tuning around 370 so the calibration band holds.
      expect(Config.flapVelocity, greaterThan(330));
      expect(Config.flapVelocity, lessThan(410));
    });

    test('§3.0.1 terminal velocity caps the fall speed at 650 pt/s', () {
      expect(Config.maxFallSpeed, 650);
      expect(Config.maxFallSpeed, RunConfig.maxFallSpeed);
      expect(Config.maxFallSpeed, greaterThan(Config.flapVelocity));
    });

    test('§3.0.1 the world scrolls at the cruise; PRD-2.3 §14.4: by hoop '
        'index, 150 → 172.5 at hoop 50 → 187.5 from hoop 150', () {
      expect(RunConfig.cruise(0), 150);
      expect(RunConfig.cruise(50), 172.5);
      expect(RunConfig.cruise(150), 187.5);
      expect(RunConfig.cruise(300), 187.5);
    });

    test('collision categories mirror the original bitmasks', () {
      expect(Config.categoryBird, 0x1);
      expect(Config.categoryWorld, 0x2);
    });
  });

  group('bird geometry', () {
    test('§3.0.1 bird sits at x = 70, vertically centered', () {
      expect(Config.birdX, 70);
      expect(Config.birdX, RunConfig.birdX);
      expect(Config.birdY, Config.worldHeight / 2);
    });

    test('bird body radius is half the sprite height', () {
      expect(Config.birdRadius, Config.birdSize.y / 2);
      expect(Config.birdRadius, 14.75);
      expect(Config.birdSize.x, 46.5);
      expect(Config.birdSize.y, 29.5);
    });
  });

  group('PRD-2 hoop course (WP-1a: replaces the pipe math)', () {
    test('§3.0.1 / PRD-2.3 §14.4 / PRD-2.4 §1 opening 118 at hoop 0, the '
        'v23 curve from hoop 1 (118 → 66 at hoop 100), flat after; rides '
        'follow it (PRD-2.4 §2)', () {
      expect(RunConfig.openingFor(0), 118);
      expect(RunConfig.openingFor(1), 118);
      expect(RunConfig.openingFor(50), closeTo(81, .2));
      expect(RunConfig.openingFor(100), 66);
      expect(RunConfig.openingFor(200), 66);
    });

    test('§3.0.1 spacing 310 pt, first hoop 60 pt past the right edge', () {
      expect(RunConfig.spacing, 310);
      expect(RunConfig.firstHoopOffscreen, 60);
      // 320 + 60 − 70 = one spacing to the bird.
      expect(Config.worldWidth + RunConfig.firstHoopOffscreen - Config.birdX,
          RunConfig.spacing);
    });

    test('§3.0.2 band rule: the same margin (7 + 18) on both sides', () {
      expect(RunConfig.rimRadius + RunConfig.bandMargin, 25);
    });
  });

  group('spike strips', () {
    test('§3.0.9 #1 strips are 44 pt tall (band 26 + teeth 18)', () {
      expect(Config.spikeHeight, 44);
      expect(Config.spikeHeight, RunConfig.stripHeight);
      expect(Config.spikeTileWidth, 384);
    });
  });

  group('playfield height & UI accent', () {
    test('view height clamps to [568, 730]', () {
      expect(Config.minViewHeight, 568);
      expect(Config.maxViewHeight, 730);
      expect(Config.worldHeight, Config.minViewHeight,
          reason: 'the design height is the minimum');
    });

    test('center-Y position helpers reproduce the 568 layout at 284', () {
      expect(Config.titlePositionFor(284).y, closeTo(175.25, 1e-9));
      expect(Config.bestLabelPositionFor(284).y, 404);
      expect(Config.gamesLabelPositionFor(284).y, 434);
      expect(Config.scoreHudPositionFor(284).y, 319);
      expect(Config.pointsfieldPositionFor(284).y, 243);
      expect(Config.replayButtonPositionFor(284).y, 309.25);
      expect(Config.shareButtonPositionFor(284).y, 353.75);
    });

    test('UI accent is the artwork pink; score nudge is upward', () {
      expect(Config.uiAccent.toARGB32(), 0xFFFF4FB7);
      expect(Config.scoreLabelNudgeY, lessThan(0));
    });
  });
}
