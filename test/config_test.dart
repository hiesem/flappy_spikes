import 'package:flappy_spikes/game/config.dart';
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

    test('terminal velocity caps the fall speed (Flappy Bird feel)', () {
      expect(Config.maxFallSpeed, 500);
      expect(Config.maxFallSpeed, greaterThan(Config.flapVelocity));
    });

    test('world scrolls at a constant 200 pt/s', () {
      expect(Config.scrollSpeed, 200);
    });

    test('collision categories mirror the original bitmasks', () {
      expect(Config.categoryBird, 0x1);
      expect(Config.categoryWorld, 0x2);
      expect(Config.categoryPipe, 0x4);
      expect(Config.categoryScore, 0x8);
    });
  });

  group('bird geometry', () {
    test('bird sits at x = width / 4, vertically centered', () {
      expect(Config.birdX, Config.worldWidth / 4);
      expect(Config.birdY, Config.worldHeight / 2);
    });

    test('bird body radius is half the sprite height', () {
      expect(Config.birdRadius, Config.birdSize.y / 2);
      expect(Config.birdRadius, 14.75);
      expect(Config.birdSize.x, 46.5);
      expect(Config.birdSize.y, 29.5);
    });
  });

  group('pipe math (SPEC.md "Pipes")', () {
    test('gap ramps from 145 pt at score 0 down to the final 105 pt', () {
      expect(Config.pipeGapStart, 145);
      expect(Config.pipeGap, 105);
      expect(Config.difficultyRampScore, 25);

      expect(Config.gapForScore(0), Config.pipeGapStart);
      expect(
        Config.gapForScore(Config.difficultyRampScore),
        closeTo(Config.pipeGap, 1e-9),
      );
      expect(
        Config.gapForScore(999),
        Config.pipeGap,
        reason: 'gap must clamp at the final 105 pt past the ramp',
      );

      // Strictly shrinking across the whole ramp.
      var previous = Config.gapForScore(0);
      for (var score = 1; score <= Config.difficultyRampScore; score++) {
        final gap = Config.gapForScore(score);
        expect(gap, lessThan(previous), reason: 'gap must shrink at $score');
        previous = gap;
      }
    });

    test('gap-bottom y range is [72 + 130, 568 - 72 - gap - 40]', () {
      expect(Config.gapBottomMin, 202);
      expect(Config.gapBottomMax, 351);
      expect(
        Config.gapBottomMin,
        Config.spikeHeight + 130,
        reason: 'spike strip + min flyable window',
      );
      expect(
        Config.gapBottomMax,
        Config.worldHeight - Config.spikeHeight - Config.pipeGap - 40,
      );
      expect(
        Config.gapBottomMaxFor(Config.pipeGap),
        Config.gapBottomMax,
        reason: 'at the final gap the per-gap bound equals the constant',
      );
      expect(
        Config.gapBottomMaxFor(Config.pipeGapStart),
        311,
        reason: 'the bigger start gap narrows the spawn band',
      );
      expect(
        Config.gapBottomMaxFor(Config.pipeGap, 711),
        711 - Config.spikeHeight - Config.pipeGap - 40,
        reason: 'the band scales with the playfield height',
      );
      expect(
        Config.maxGapJump,
        140,
        reason: 'consecutive gaps are clamped to a flyable jump',
      );
    });

    test('pair enters at x = 320 + pipeWidth / 2', () {
      expect(Config.pipeSpawnX, 364);
      expect(Config.pipeSpawnX, Config.worldWidth + Config.pipeWidth / 2);
    });

    test('score sensor sits 111 pt right of the pipe center', () {
      expect(Config.sensorOffsetX, 111);
    });

    test('spawn interval 1.5 s at 200 pt/s gives 300 pt spacing', () {
      expect(Config.pipeSpawnInterval, 1.5);
      expect(Config.pipeSpawnInterval * Config.scrollSpeed, 300);
    });

    test('pipe sprites are 88x513.5 pt', () {
      expect(Config.pipeWidth, 88);
      expect(Config.pipeHeight, 513.5);
    });
  });

  group('spike strips', () {
    test('strips are 72 pt tall and tiled with the 384 pt texture', () {
      expect(Config.spikeHeight, 72);
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
