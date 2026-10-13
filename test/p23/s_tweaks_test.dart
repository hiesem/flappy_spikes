import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/menu_lock_overlay.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/rim_collision.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Owner requests 2026-10-13 (WP-TWEAKS, 2.3.0+13): bullseye pays 2, the
/// fullscreen 90 % lock overlay, the soft rim bump from inside the hoop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The owner's default (the lock is on); see test/flutter_test_config.dart.
  Tuning.instance = Tuning();
  TuningValues.current = TuningValues.defaults();

  // --- 1. Bullseye pays +2 -------------------------------------------------

  test('tweak 1: coin_bullseye defaults to 2', () {
    expect(BullseyeConfig.coins, 2);
  });

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'tweak 1: a bullseye hit pays 2 coins and 2 points, banner "+2 coins"',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 6,
        force: [ElementId.bullseye],
      );
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      expect(
        await flyUntil(
          game,
          (_) => firstHoopOf(game, HoopKindId.bullseye) != null,
        ),
        isTrue,
      );
      final h = firstHoopOf(game, HoopKindId.bullseye)!;
      final before = run.state.score;
      expect(await passHoopAt(game, h, dy: 0), isTrue);
      // A perfect pass at streak 1 (2) plus the bullseye's 2.
      expect(run.state.score - before, 2 + 2);
      final bonus = events
          .whereType<CoinsEarned>()
          .where((e) => e.source == CoinSource.bullseye)
          .toList();
      expect(bonus.single.amount, 2);
      final banner = RunHud.of(run)?.banners.current;
      expect((banner! as ElementBanner).subtitle, '+2 coins');
    },
  );

  // --- 2. Fullscreen 90 % lock overlay -------------------------------------

  test('tweak 2: the lock dim is #000000 at 90 %', () {
    expect(Config.menuLockDimColor.toARGB32(), 0xE6000000);
    expect(MenuLockOverlay.dimColor, Config.menuLockDimColor);
    expect(
      Config.menuLockOverlayPriority,
      greaterThan(FlappySpikesGame.groundOverMenusPriority),
    );
    expect(
      Config.menuLockPillPriority,
      greaterThan(Config.menuLockOverlayPriority),
    );
  });

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {
          'bestScore': 24,
          'claimedLevels': ['1'],
        },
        worldHeight: h,
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'tweak 2 (${h.round()} pt): the lock covers the whole screen incl. both '
      'strips; back button and coin pill stay bright (pixel sample)',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
      },
      verify: (g, t) async {
        g.openShop();
        await flushAndMount(g);
        stepGame(g, 0.6);
        await flushAndMount(g);
        final shop = g.shopScreen!;
        final o = shop.lockOverlay!;
        expect(o.isMounted, isTrue);
        expect(o.parent, same(g.world));
        expect(o.position, Vector2.zero());
        expect(o.size, Vector2(320, g.viewHeight));
        expect(o.priority, greaterThan(g.groundStripPriority));
        expect(g.coinPill.priority, greaterThan(o.priority));

        final px = await t.runAsync(() async {
          final size = Vector2(320, g.viewHeight);
          g.onGameResize(size);
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.drawRect(
            ui.Rect.fromLTWH(0, 0, size.x, size.y),
            ui.Paint()..color = g.backgroundColor(),
          );
          g.render(c);
          final img = await rec.endRecording().toImage(
            size.x.toInt(),
            size.y.toInt(),
          );
          final data = (await img.toByteData())!;
          img.dispose();
          return (int x, int y) {
            final i = (y * size.x.toInt() + x) * 4;
            return (
              data.getUint8(i),
              data.getUint8(i + 1),
              data.getUint8(i + 2),
            );
          };
        });
        bool dark((int, int, int) p) => p.$1 < 40 && p.$2 < 40 && p.$3 < 40;
        final vh = g.viewHeight.round();
        // Both spike strips (base rows) and the content: dimmed.
        for (final (x, y) in [
          (160, 2),
          (5, 4),
          (315, vh - 3),
          (160, vh - 2),
          (160, vh ~/ 2 + 80),
        ]) {
          expect(dark(px!(x, y)), isTrue, reason: '($x, $y) ${px(x, y)}');
        }
        // The back button (pink corner box) is bright.
        final back = Config.menuScreenBackRectFor(g.viewHeight);
        final b = px!(back.left.round() + 3, back.top.round() + 3);
        expect(b.$1, greaterThan(200), reason: 'back $b');
        // The coin pill is bright (its right edge, pink).
        final pill = g.coinPill.toRect();
        final p = px((pill.right - 3).round(), (pill.top + 3).round());
        expect(p.$1, greaterThan(150), reason: 'pill $p');

        g.closeShop();
        await flushAndMount(g);
        stepGame(g, 0.6);
        await flushAndMount(g);
        expect(o.isMounted, isFalse, reason: 'removed with its screen');
        expect(g.coinPill.priority, FlappySpikesGame.groundOverMenusPriority);
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  }

  // --- 3. Soft rim bump from inside the hoop -------------------------------

  group('tweak 3: soft rim bump', () {
    final r = RunConfig.birdRadius;
    final f = HoopFrame(centre: Vector2(400, 355), opening: 118);
    // Rim ends at y 289 (top) and 421 (bottom); contact distance 21.75.

    test('a rising bird on the top rim from inside ends with vy ≈ +bump', () {
      final res = collideRims(
        f,
        BirdCircle(Vector2(402, 289 + 20), r),
        Vector2(180, -350),
      )!;
      expect(res.bounced, isTrue);
      expect(res.contacts.single.inside, isTrue);
      expect(res.velocity.y, closeTo(RunConfig.rimSoftBump, 1e-6));
      expect(res.velocity.x, closeTo(180, 1e-6), reason: 'forward kept');
    });

    test(
      'a falling bird on the bottom rim from inside ends with vy ≈ −bump',
      () {
        final res = collideRims(
          f,
          BirdCircle(Vector2(398, 421 - 20), r),
          Vector2(180, 400),
        )!;
        expect(res.bounced, isTrue);
        expect(res.velocity.y, closeTo(-RunConfig.rimSoftBump, 1e-6));
        expect(res.velocity.x, closeTo(180, 1e-6));
      },
    );

    test('a tilted hoop: the push is along the ring, forward (local) kept', () {
      final tilted = HoopFrame(
        centre: Vector2(400, 355),
        opening: 118,
        tilt: .3,
      );
      final end = tilted.rimEnd(0, -1);
      // Just inside the top end, along the ring axis.
      final axis = (tilted.rimEnd(0, 1) - end).normalized();
      final res = collideRims(
        tilted,
        BirdCircle(end + axis * 20, r),
        axis * -300,
      )!;
      final local = Vector2(
        res.velocity.x * .955336 + res.velocity.y * .29552,
        -res.velocity.x * .29552 + res.velocity.y * .955336,
      );
      expect(local.y, closeTo(RunConfig.rimSoftBump, 1e-3));
      expect(local.x, closeTo(0, 1e-3));
    });

    test('a slanted hit from inside (70° off the axis) is soft too', () {
      // Bird behind and below the top rim end: the normal points forward
      // and into the gap, far more than 60° off the ring axis.
      final res = collideRims(
        f,
        BirdCircle(Vector2(400 + 20.4, 289 + 7.4), r),
        Vector2(0, -350),
      )!;
      expect(res.bounced, isTrue);
      expect(res.velocity.y, closeTo(RunConfig.rimSoftBump, 1e-6));
      expect(res.velocity.x, closeTo(0, 1e-6));
    });

    test('the bump is remote (curve_rim_soft_bump, default 20)', () {
      expect(RunConfig.rimSoftBump, 20);
    });

    test('soft hits are flagged (the rim hang follows them)', () {
      final soft = collideRims(
        f,
        BirdCircle(Vector2(402, 289 + 20), r),
        Vector2(180, -350),
      )!;
      expect(soft.contacts.single.soft, isTrue);
      final hard = collideRims(
        f,
        BirdCircle(Vector2(400, 289 - 20), r),
        Vector2(180, 300),
      )!;
      expect(hard.contacts.single.soft, isFalse);
    });

    test('the rim hang is remote: 0.25 s at 25 % gravity by default', () {
      expect(RunConfig.rimHangSeconds, .25);
      expect(RunConfig.rimHangGravity, .25);
    });

    test('an outside hit (from above the top rim) is unchanged', () {
      final res = collideRims(
        f,
        BirdCircle(Vector2(400, 289 - 20), r),
        Vector2(180, 300),
      )!;
      expect(res.contacts.single.inside, isFalse);
      // Reflected with restitution 0.85: vy = 300 − 1.85 × 300.
      expect(res.velocity.y, closeTo(300 - 1.85 * 300, 1e-6));
    });

    test('a head-on hit (bird level with the rim end) is unchanged', () {
      final res = collideRims(
        f,
        BirdCircle(Vector2(400 - 20, 289 + 2), r),
        Vector2(150, -40),
      )!;
      final n = res.contacts.single.normal;
      final vn = 150 * n.x + -40 * n.y;
      expect(vn, lessThan(0));
      expect(res.velocity.x, closeTo(150 - 1.85 * vn * n.x, 1e-3));
      expect(res.velocity.y, closeTo(-40 - 1.85 * vn * n.y, 1e-3));
    });

    test('a moving ring: the push is relative to the rim\'s own speed', () {
      final moving = HoopFrame(
        centre: Vector2(400, 355),
        opening: 118,
        velocity: Vector2(0, 100), // rim moving down into the bird
      );
      final res = collideRims(
        moving,
        BirdCircle(Vector2(400, 289 + 20), r),
        Vector2.zero(),
      )!;
      expect(res.velocity.y, closeTo(100 + RunConfig.rimSoftBump, 1e-6));
    });
  });
}
