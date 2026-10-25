import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every element switched on and already met (no first-meet forcing).
final Set<ElementId> all = ElementId.values.toSet();

RunDirector director({
  int seed = 7,
  Set<ElementId>? enabled,
  Set<ElementId>? met,
  int startHoopIndex = 0,
}) => RunDirector(
  seed: seed,
  enabled: enabled ?? all,
  met: met ?? all,
  startHoopIndex: startHoopIndex,
);

List<(SlotPlan, GapPlan)> fly(
  RunDirector d,
  int n, {
  DirectorContext Function(int i)? ctxFor,
}) {
  final out = <(SlotPlan, GapPlan)>[];
  for (var k = 0; k < n; k++) {
    final ctx = ctxFor?.call(d.hoopIndex) ?? DirectorContext.open(711);
    final s = d.nextSlot(ctx);
    out.add((s, d.nextGap(ctx, s)));
  }
  return out;
}

/// PRD-2.3 §14.4 difficulty and §14.5 rides (all by hoop index).
void main() {
  group('§14.4 curves', () {
    test('opening 118 at hoop 0, 118 at hoop 1, 83 at hoop 50 and 70 from '
        'hoop 150; the ride size is the same curve (PRD-2.4 §2)', () {
      expect(RunConfig.openingFor(0), 118);
      expect(RunConfig.openingFor(1), 118);
      expect(RunConfig.openingFor(50), 83);
      expect(RunConfig.openingFor(70), closeTo(76.7, .04));
      expect(RunConfig.openingFor(100), 72.5);
      expect(RunConfig.openingFor(150), 70);
      expect(RunConfig.openingFor(300), 70);
    });

    test('speed 150, 172.5 and 187.5 at hoops 0, 50 and 150, and 187.5 at '
        'hoop 300', () {
      expect(RunConfig.cruise(0), 150);
      expect(RunConfig.cruise(50), 172.5);
      expect(RunConfig.cruise(150), 187.5);
      expect(RunConfig.cruise(300), 187.5);
      expect(RunConfig.cruise(100), closeTo(180, 1e-9));
    });

    test('the moving-hoop chance at every key (a jump at hoop 25, then a '
        'ramp); tilt follows the D2 curve', () {
      final t = DirectorTables.prd2;
      expect(t.movingChance(0), 0);
      expect(t.movingChance(24), 0);
      expect(t.movingChance(25), .15);
      expect(t.movingChance(34), .15);
      expect(t.movingChance(35), .25);
      expect(t.movingChance(60), closeTo(.42, 1e-9));
      expect(t.movingChance(100), .52);
      expect(t.movingChance(150), .58);
      expect(t.movingChance(200), .58);
      expect(t.movingChance(47), closeTo(.25 + .17 * 12 / 25, 1e-9));
      for (final (i, v) in [
        (0, 0.0),
        (9, 0.0),
        (10, .30),
        (49, .35),
        (50, .50),
        (99, .598),
        (100, .60),
        (149, .649),
        (150, .65),
        (250, .65),
      ]) {
        expect(t.tiltChance(i), v, reason: 'hoop $i');
      }
    });

    test('the director uses the curves: hoop 0 at 118, then the opening '
        'curve; Big Hoops ×1.5 from hoop 0 (177 at hoops 0 and 1; owner '
        '2026-10-19, deviation from §0 item 3)', () {
      final plain = fly(director(), 60);
      expect(plain[0].$1.opening, 118);
      expect(plain[1].$1.opening, 118);
      for (final (s, _) in plain.skip(1)) {
        if (s.kind != HoopKindId.normal || s.duringRide) continue;
        expect(s.opening, closeTo(RunConfig.openingFor(s.index), 1e-9));
      }
      final big = fly(
        director(),
        2,
        ctxFor: (_) => DirectorContext.open(711, bigHoopsMult: 1.5),
      );
      expect(big[0].$1.opening, closeTo(177, 1e-9));
      expect(big[1].$1.opening, closeTo(177, 1e-9));
    });

    test('over seeded runs the moving rate follows the curve (none before '
        'hoop 25)', () {
      var early = 0, mid = 0, midN = 0;
      for (var seed = 1; seed <= 120; seed++) {
        for (final (s, _) in fly(director(seed: seed), 34)) {
          if (s.kind != HoopKindId.normal || s.cometHang) continue;
          if (s.index < 25 && s.motion != null) early++;
          if (s.index >= 25 && s.index < 35) {
            midN++;
            if (s.motion != null) mid++;
          }
        }
      }
      expect(early, 0);
      // The chance is a 0.15 plateau over hoops 25–34.
      expect(mid / midN, inInclusiveRange(.08, .23));
    });
  });

  group('§14.4 squeeze in hoops', () {
    test('first at a random hoop 25–40, hold 5–10 hoops, next 25–45 hoops '
        'after the previous ended (the hoops at their cruise)', () {
      final d = director();
      final firsts = <double>{}, holds = <double>{}, gaps = <double>{};
      for (var k = 0; k < 300; k++) {
        final f = d.rollSqueezeAt(0, hoop: 0, first: true);
        expect(
          f,
          inInclusiveRange(
            RunConfig.secondsForHoops(0, 25) - 1e-9,
            RunConfig.secondsForHoops(0, 40) + 1e-9,
          ),
        );
        firsts.add(f);
        final h = d.rollSqueezeHold(hoop: 60);
        expect(
          h,
          inInclusiveRange(
            RunConfig.secondsForHoops(60, 5) - 1e-9,
            RunConfig.secondsForHoops(60, 10) + 1e-9,
          ),
        );
        holds.add(h);
        final g = d.rollSqueezeAt(100, hoop: 70);
        expect(
          g - 100,
          inInclusiveRange(
            RunConfig.secondsForHoops(70, 25) - 1e-9,
            RunConfig.secondsForHoops(70, 45) + 1e-9,
          ),
        );
        gaps.add(g);
      }
      // Every whole hoop count comes up.
      expect(firsts.length, 16);
      expect(holds.length, 6);
      expect(gaps.length, 21);
      // A steady rhythm: the cooldown is the same hoop count later in the
      // run (only the seconds shrink as the speed grows).
      expect(
        RunConfig.secondsForHoops(200, 30),
        closeTo(30 * 310 / 187.5, 1e-9),
      );
    });
  });

  group('§14.5 rides', () {
    // PRD-2.3.1 §0 live RC v21: 4 % from hoop 8, spacing 18 (was 2 %, 10,
    // 25).
    test('over 200 seeded runs the comet comes with ≈ 4 % per eligible '
        'normal hoop from hoop 8, never within 18 hoops of the previous '
        'comet', () {
      var comets = 0, eligible = 0;
      for (var seed = 1; seed <= 200; seed++) {
        final d = director(seed: seed);
        var last = -99;
        var lastPortal = -99;
        final plans = fly(d, 200);
        final portals = [
          for (final (s, _) in plans)
            if (s.kind == HoopKindId.portal) s.index,
        ];
        for (final (s, _) in plans) {
          if (s.kind == HoopKindId.portal) lastPortal = s.index;
          if (s.cometHang) {
            expect(s.index, greaterThanOrEqualTo(8));
            expect(
              s.index - last,
              greaterThanOrEqualTo(18),
              reason: 'seed $seed',
            );
          }
          // Eligible: a normal slot from 8, ≥ 18 after the last comet, not
          // within 10 hoops of a portal.
          final nextPortal = portals.firstWhere(
            (p) => p > s.index,
            orElse: () => 1 << 30,
          );
          final ok =
              s.kind == HoopKindId.normal &&
              !s.duringRide &&
              s.index >= 8 &&
              s.index - last >= 18 &&
              s.index - lastPortal >= RunConfig.cometPortalDistance &&
              nextPortal - s.index >= RunConfig.cometPortalDistance;
          if (ok) eligible++;
          if (s.cometHang) {
            comets++;
            last = s.index;
          }
        }
      }
      final rate = comets / eligible;
      // PRD-2.6 D3 can downgrade a planned special to a normal hoop after
      // the comet roll point, so the final-plan denominator is ≈ 3 % while
      // the chance roll itself remains 4 %.
      expect(rate, closeTo(.03, .01), reason: '$comets / $eligible');
    });

    // PRD-2.3.1 §0 live RC v21: first 12–25, then 80–90 (was 40–60, 60–80);
    // §17 at most 2 per run.
    test('the portal: first at hoop 12–25, then every 80–90, at most 2', () {
      final firsts = <int>[];
      for (var seed = 1; seed <= 200; seed++) {
        final d = director(seed: seed);
        expect(d.portalAt, inInclusiveRange(12, 25));
        final portals = [
          for (final (s, _) in fly(d, 260))
            if (s.kind == HoopKindId.portal) s.index,
        ];
        expect(portals, isNotEmpty);
        // A portal may wait (comet distance, the squeeze, an activity), so
        // it is never earlier than its schedule.
        expect(portals.first, greaterThanOrEqualTo(12));
        expect(portals.length, lessThanOrEqualTo(2));
        firsts.add(portals.first);
        for (var k = 1; k < portals.length; k++) {
          expect(portals[k] - portals[k - 1], greaterThanOrEqualTo(80));
        }
      }
      expect(firsts.where((f) => f <= 25).length, greaterThan(150));
      expect(firsts.toSet().length, greaterThan(10));
    });

    test('tuning: a remote comet chance and portal schedule reach the '
        'director', () {
      TuningValues.current = TuningValues.resolve({
        'ride_comet_chance': '1',
        'ride_comet_spacing': '30',
        'ride_portal_first': '[100,100]',
      });
      addTearDown(
        () => TuningValues.current = TuningValues.resolve({
          'ui_unlock_best': '0',
        }),
      );
      final d = director();
      expect(d.portalAt, 100);
      final comets = [
        for (final (s, _) in fly(d, 80))
          if (s.cometHang) s.index,
      ];
      expect(comets.first, inInclusiveRange(8, 13)); // ride_comet_from 8
      expect(comets[1] - comets[0], greaterThanOrEqualTo(30));
    });
  });
}
