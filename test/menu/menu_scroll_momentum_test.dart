import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../home_layout_test.dart' show loadFonts;
import '../shop_flow_test.dart' show openShop, shopTest;
import '../skin_shop_flow_test.dart' show openSkinShop;

/// Menu list momentum scrolling (product decision 2026-10-07): every menu
/// scroll list flings after a release, rubber-bands past its edges and springs
/// back, and the touch that stops it presses nothing.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  // --- skin shop grid --------------------------------------------------------

  shopTest(
    'fling: the release keeps the grid moving and it decelerates to rest',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;
      expect(scroll.offset, 0);
      expect(scroll.scrollable, isTrue);

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 60),
      );
      expect(scroll.isGliding, isTrue, reason: 'a release flings');
      expect(scroll.offset, greaterThan(0));
      final released = scroll.offset;

      stepGame(game, 0.12);
      final mid = scroll.offset;
      expect(mid, greaterThan(released), reason: 'it keeps moving on its own');
      expect(scroll.isGliding, isTrue, reason: 'and slows down, not stops');

      stepGame(game, 5);
      expect(scroll.isBusy, isFalse, reason: 'it comes to rest');
      expect(scroll.offset, greaterThan(mid));
      expect(scroll.offset, inInclusiveRange(0, scroll.maxOffset));
      expect(scroll.isOverScrolled, isFalse);
    },
  );

  shopTest(
    'fling: a faster release travels further',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 200),
      );
      stepGame(game, 5);
      final slow = scroll.offset;
      expect(scroll.isBusy, isFalse);

      scroll.offset = 0;
      expect(scroll.offset, 0);
      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 60),
      );
      stepGame(game, 5);
      final fast = scroll.offset;

      expect(slow, greaterThan(0));
      expect(fast, greaterThan(slow + 100), reason: '$fast vs $slow');
      expect(fast, lessThan(scroll.maxOffset));
    },
  );

  shopTest(
    'fling: frame rate does not change the distance travelled',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;

      Future<double> flingAndMeasure(double dt) async {
        scroll.offset = 0;
        await tester.timedDragFrom(
          const ui.Offset(160, 500),
          const ui.Offset(0, -60),
          const Duration(milliseconds: 60),
        );
        final released = scroll.offset;
        stepGame(game, 0.3, dt: dt);
        return scroll.offset - released;
      }

      final at60 = await flingAndMeasure(1 / 60);
      final at120 = await flingAndMeasure(1 / 120);
      expect(at60, greaterThan(20));
      expect((at60 - at120).abs() / at60, lessThan(0.05));
    },
  );

  shopTest(
    'fling into the bottom edge: rubber-band bounce, then it rests at the end',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -120),
        const Duration(milliseconds: 40),
      );
      var furthest = scroll.offset;
      for (var i = 0; i < 900; i++) {
        stepGame(game, 1 / 60);
        furthest = math.max(furthest, scroll.offset);
      }
      expect(
        furthest,
        greaterThan(scroll.maxOffset),
        reason: 'the fling overshoots into the rubber band',
      );
      expect(scroll.isBusy, isFalse);
      expect(scroll.isOverScrolled, isFalse);
      expect(scroll.offset, closeTo(scroll.maxOffset, 1e-9));
    },
  );

  shopTest(
    'release past the top edge: springs back to exactly the top',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 360),
        const ui.Offset(0, 120),
        const Duration(milliseconds: 40),
      );
      expect(scroll.offset, lessThan(0), reason: 'overscrolled past the top');
      expect(scroll.isSpringing, isTrue);
      stepGame(game, 5);
      expect(scroll.isBusy, isFalse);
      expect(scroll.offset, 0);
    },
  );

  shopTest(
    'a pointer down stops a spring without selecting; the spring resumes',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final screen = await openSkinShop(game);
      final scroll = screen.scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 360),
        const ui.Offset(0, 120),
        const Duration(milliseconds: 40),
      );
      expect(scroll.offset, lessThan(0), reason: 'overscrolled past the top');
      expect(scroll.isSpringing, isTrue);
      stepGame(game, 0.08);
      final stopped = scroll.offset;
      expect(stopped, lessThan(0), reason: 'still on its way back');

      await tester.pump();
      final gesture = await tester.startGesture(const ui.Offset(160, 300));
      await tester.pump();
      expect(scroll.isBusy, isFalse, reason: 'the touch stops the spring');
      expect(scroll.isOverScrolled, isTrue, reason: 'held where it stopped');
      expect(scroll.offset, closeTo(stopped, 1e-9));
      expect(screen.tryOnId, isNull, reason: 'and presses nothing under it');

      await gesture.up();
      await tester.pump();
      expect(scroll.isSpringing, isTrue, reason: 'the spring resumes on lift');
      stepGame(game, 2);
      expect(scroll.isBusy, isFalse);
      expect(scroll.offset, 0);

      // Past the tap recognizer's 40 ms double-tap window.
      await tester.pump(const Duration(milliseconds: 60));
    },
  );

  shopTest(
    'dragging past the edge resists more the further it goes',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;
      // A pumped frame: the game's drag recognizer reaches the GameWidget's
      // gesture detector on the next rebuild (the harness opens screens with
      // game.update, not tester.pump).
      await tester.pump();

      final gesture = await tester.startGesture(const ui.Offset(160, 400));
      final overscroll = <double>[];
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const ui.Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
        overscroll.add(-scroll.offset);
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      // 160 pt of finger travel shows much less content...
      expect(overscroll.last, lessThan(60));
      // ...and each 40 pt step shows less than the previous one.
      for (var i = 1; i < overscroll.length; i++) {
        final step = overscroll[i] - overscroll[i - 1];
        final previous = i == 1 ? overscroll[0] : overscroll[i - 1] - overscroll[i - 2];
        expect(step, lessThan(previous), reason: 'step $i of $overscroll');
      }
      expect(scroll.isSpringing, isTrue, reason: 'release springs back');
      stepGame(game, 5);
      expect(scroll.offset, 0);
    },
  );

  shopTest(
    'a tap that stops the glide presses nothing; the next tap works',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final screen = await openSkinShop(game);
      final scroll = screen.scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 60),
      );
      stepGame(game, 0.12);
      expect(scroll.isGliding, isTrue);

      final tile = screen.tiles.firstWhere((t) {
        if (t.current.owned) return false;
        final centre = t.absolutePositionOfAnchor(Anchor.center);
        return centre.y > scroll.viewport.top + 10 &&
            centre.y < scroll.viewport.bottom - 10;
      });
      final centre = tile.absolutePositionOfAnchor(Anchor.center);

      await tester.tapAt(ui.Offset(centre.x, centre.y));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scroll.isBusy, isFalse, reason: 'the touch stops the glide');
      expect(tile.pressed, isFalse);
      expect(screen.tryOnId, isNull, reason: 'and presses nothing under it');

      // Stopped where it was, in range.
      final stopped = scroll.offset;
      stepGame(game, 0.5);
      expect(scroll.offset, closeTo(stopped, 1e-9));

      await tester.tapAt(ui.Offset(centre.x, centre.y));
      await tester.pump(const Duration(milliseconds: 60));
      expect(screen.tryOnId, tile.item.id);
    },
  );

  shopTest(
    'a small drag (under the slop) is still a tap',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final screen = await openSkinShop(game);
      await tester.pump();
      final scroll = screen.scroll;
      final tile = screen.tileFor('sky');
      expect(tile.current.owned, isFalse);

      final centre = tile.absolutePositionOfAnchor(Anchor.center);
      final gesture = await tester.startGesture(ui.Offset(centre.x, centre.y));
      await gesture.moveBy(const ui.Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      // Past the tap recognizer's 40 ms double-tap window.
      await tester.pump(const Duration(milliseconds: 60));

      expect(screen.tryOnId, 'sky');
      expect(scroll.offset, 0);
      expect(scroll.isBusy, isFalse);
    },
  );

  shopTest(
    'scrollTo cancels a glide (animated and instant)',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final scroll = (await openSkinShop(game)).scroll;

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -120),
        const Duration(milliseconds: 40),
      );
      expect(scroll.isGliding, isTrue);
      scroll.scrollTo(0, animate: false);
      expect(scroll.isBusy, isFalse);
      expect(scroll.offset, 0);
      stepGame(game, 1);
      expect(scroll.offset, 0);

      await tester.timedDragFrom(
        const ui.Offset(160, 500),
        const ui.Offset(0, -120),
        const Duration(milliseconds: 40),
      );
      expect(scroll.isGliding, isTrue);
      scroll.scrollTo(0);
      expect(scroll.isBusy, isFalse);
      expect(scroll.target, 0);
      stepGame(game, 1);
      expect(scroll.offset, 0);
    },
  );

  // --- the other lists -------------------------------------------------------

  shopTest(
    'the Shop list flings into its end and settles',
    height: 568,
    exactSurface: true,
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      final scroll = shop.scroll;
      expect(scroll.scrollable, isTrue);

      await tester.timedDragFrom(
        const ui.Offset(160, 400),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 60),
      );
      expect(scroll.isGliding, isTrue);
      stepGame(game, 5);
      expect(scroll.isBusy, isFalse);
      expect(scroll.offset, closeTo(scroll.maxOffset, 1e-9));
    },
  );

  shopTest(
    'the LEVELS list flings and settles',
    height: 568,
    exactSurface: true,
    prefs: {
      'bestScore': 640,
      'gamesPlayed': 34,
      'claimedLevels': ['1', '2', '3', '4', '5', '6'],
    },
    verify: (game, spy, ads, iap, tester) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);
      final scroll = game.levelsScreen!.scroll;
      final opened = scroll.offset;
      expect(scroll.scrollable, isTrue);

      await tester.timedDragFrom(
        const ui.Offset(160, 400),
        const ui.Offset(0, -60),
        const Duration(milliseconds: 60),
      );
      expect(scroll.isGliding, isTrue);
      final released = scroll.offset;
      stepGame(game, 0.12);
      expect(scroll.offset, greaterThan(released));
      stepGame(game, 5);
      expect(scroll.isBusy, isFalse);
      expect(scroll.offset, greaterThan(opened));
      expect(scroll.offset, inInclusiveRange(0, scroll.maxOffset));
    },
  );
}
