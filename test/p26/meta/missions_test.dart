import 'dart:convert';

import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/versus/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

MissionEligibility eligibility({
  int best = 100,
  bool online = true,
  bool rival = true,
  Set<ElementId>? met,
}) => MissionEligibility(
  bestHoops: best,
  online: online,
  lastVersusHadRival: rival,
  metElements: met ?? ElementId.values.toSet(),
);

Missions roll(int day, {int best = 100, MissionEligibility? context}) =>
    Missions().roll(
      today: day,
      gamesPlayed: 3,
      eligibility: context ?? eligibility(best: best),
    );

Missions restore(Missions state) => Missions.fromRecords(
  day: state.day,
  tier: state.tier,
  rerollDay: state.rerollDay,
  records: (jsonDecode(jsonEncode(state.toRecords())) as List)
      .map((r) => Map<String, Object?>.from(r as Map))
      .toList(),
);

Missions withTemplates(List<MissionTemplate> templates, {int tier = 0}) =>
    Missions(
      day: 20,
      tier: tier,
      missions: [
        for (final t in templates)
          MissionProgress(template: t, target: t.targets[tier]),
      ],
    );

void main() {
  test('M10 online evidence is shared and rejects offline or unavailable search', () {
    bool online(VersusSearchInfo info, {bool ready = true, bool held = false}) =>
        onlineFromSearch(ready: ready, holdsOpponent: held, search: info);
    expect(online(const VersusSearchInfo(state: VersusSearchState.found)), isTrue);
    expect(online(const VersusSearchInfo(reason: VersusSoloReason.noRival)), isTrue);
    expect(online(const VersusSearchInfo(reason: VersusSoloReason.offline)), isFalse);
    expect(online(const VersusSearchInfo(), held: true), isTrue);
    expect(online(const VersusSearchInfo(), held: true, ready: false), isFalse);
  });
  test('approved M01–M15 target table and text IDs, PRD §8.3-14', () {
    const expected = [
      [3, 3, 4, 5],
      [40, 80, 150, 300],
      [15, 30, 60, 120],
      [40, 80, 150, 300],
      [2, 3, 4, 6],
      [1, 1, 2, 3],
      [1, 1, 1, 2],
      [1, 2, 3, 5],
      [2, 3, 5, 8],
      [1, 1, 2, 3],
      [10, 20, 40, 80],
      [4, 6, 10, 15],
      [5, 10, 20, 35],
      [0, 1, 2, 3],
      [0, 20, 40, 80],
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(MissionTemplate.values[i].targets, expected[i]);
      expect(
        MissionTemplate.values[i].textId(2),
        'M${(i + 1).toString().padLeft(2, '0')}-T2',
      );
    }
  });

  test('unlocks before game 4, never earlier', () {
    for (var games = 0; games < 3; games++) {
      expect(
        Missions()
            .roll(today: 10, gamesPlayed: games, eligibility: eligibility())
            .missions,
        isEmpty,
      );
    }
    expect(roll(10).missions, hasLength(3));
  });

  test('stable daily roll, independent of construction and reload', () {
    for (var day = 1; day <= 100; day++) {
      final state = roll(day);
      expect(roll(day).toRecords(), state.toRecords());
      expect(restore(state).toRecords(), state.toRecords());
      expect(
        restore(state)
            .roll(
              today: day,
              gamesPlayed: 50,
              eligibility: eligibility(best: 0),
            )
            .toRecords(),
        state.toRecords(),
      );
    }
    expect(
      {for (var d = 1; d < 50; d++) jsonEncode(roll(d).toRecords())}.length,
      greaterThan(5),
    );
  });

  test('tier boundaries and tier frozen at first roll', () {
    for (final entry in {
      0: 0,
      14: 0,
      15: 1,
      39: 1,
      40: 2,
      99: 2,
      100: 3,
    }.entries) {
      final state = roll(9, best: entry.key);
      expect(state.tier, entry.value);
      for (final m in state.missions) {
        expect(m.target, m.template.targets[entry.value]);
      }
      expect(
        state.roll(today: 9, gamesPlayed: 90, eligibility: eligibility()).tier,
        entry.value,
      );
    }
  });

  test('local civil days survive DST, year and midnight boundaries', () {
    expect(
      Missions.localDay(DateTime(2026, 10, 26)) -
          Missions.localDay(DateTime(2026, 10, 25)),
      1,
    );
    expect(
      Missions.localDay(DateTime(2027, 1, 1)) -
          Missions.localDay(DateTime(2026, 12, 31, 23, 59)),
      1,
    );
    expect(
      Missions.localDay(DateTime(2026, 3, 30)) -
          Missions.localDay(DateTime(2026, 3, 29)),
      1,
    );
  });

  test(
    'rollback never resets missions, tier, progress, paid or reroll allowance',
    () {
      final state = roll(20)
          .advance(
            const MissionRunCounts(
              gamesPlayedBefore: 3,
              hoops: 100,
              inRunCoins: 1000,
              perfectPasses: 1000,
              maxNoRimChain: 100,
              maxPerfectStreak: 100,
              squeezesSurvived: 10,
            ),
          )
          .claimCoins()
          .state;
      final loaded = restore(state);
      expect(
        loaded
            .roll(today: 19, gamesPlayed: 50, eligibility: eligibility(best: 0))
            .toRecords(),
        state.toRecords(),
      );
      expect(
        loaded.reroll(index: 0, today: 19, eligibility: eligibility()),
        same(loaded),
      );
      expect(
        loaded
            .roll(today: 21, gamesPlayed: 50, eligibility: eligibility(best: 0))
            .tier,
        0,
      );
    },
  );

  test('met element gates, M10 conjunction and M15 world boundary', () {
    final empty = eligibility(best: 100, met: {}, online: false, rival: false);
    for (final template in [
      MissionTemplate.m05,
      MissionTemplate.m06,
      MissionTemplate.m07,
      MissionTemplate.m08,
      MissionTemplate.m09,
      MissionTemplate.m10,
      MissionTemplate.m14,
    ]) {
      expect(template.available(3, empty), isFalse, reason: template.id);
    }
    const gates = {
      MissionTemplate.m05: [
        ElementId.hourglass,
        ElementId.miniBird,
        ElementId.coinFrenzy,
        ElementId.capsule,
        ElementId.shield,
        ElementId.comet,
        ElementId.pair,
      ],
      MissionTemplate.m06: [ElementId.comet, ElementId.portal],
      MissionTemplate.m07: [ElementId.feather, ElementId.puzzlePiece],
      MissionTemplate.m08: [ElementId.bullseye],
      MissionTemplate.m09: [ElementId.switchRing],
      MissionTemplate.m14: [ElementId.squeeze],
    };
    for (final gate in gates.entries) {
      for (final element in gate.value) {
        expect(gate.key.available(3, eligibility(met: {element})), isTrue);
      }
    }
    expect(
      MissionTemplate.m05.available(
        3,
        eligibility(met: {ElementId.heart, ElementId.bigHoops}),
      ),
      isFalse,
    );
    for (final online in [false, true]) {
      for (final rival in [false, true]) {
        expect(
          MissionTemplate.m10.available(
            0,
            eligibility(online: online, rival: rival),
          ),
          online && rival,
        );
      }
    }
    expect(MissionTemplate.m14.available(0, eligibility()), isFalse);
    expect(MissionTemplate.m15.available(0, eligibility()), isFalse);
    for (var tier = 1; tier <= 3; tier++) {
      final target = MissionTemplate.m15.targets[tier];
      expect(
        MissionTemplate.m15.available(tier, eligibility(best: target - 1)),
        isFalse,
      );
      expect(
        MissionTemplate.m15.available(tier, eligibility(best: target)),
        isTrue,
      );
    }
  });

  test('roll rules across tiers, days, sparse/full met sets and rerolls', () {
    for (final best in [0, 15, 20, 40, 100]) {
      for (final met in [<ElementId>{}, ElementId.values.toSet()]) {
        final context = eligibility(best: best, met: met);
        var state = Missions();
        for (var day = 1; day <= 100; day++) {
          final oldHard = state.missions.lastOrNull?.template;
          state = state.roll(today: day, gamesPlayed: 3, eligibility: context);
          final templates = state.missions.map((m) => m.template).toList();
          expect(templates.toSet(), hasLength(3));
          expect(templates.map((t) => t.difficulty), MissionDifficulty.values);
          expect(templates, isNot(contains(oldHard)));
          expect(
            templates.where((t) => t.modeOnly).length,
            lessThanOrEqualTo(1),
          );
          for (final m in state.missions) {
            expect(m.template.available(state.tier, context), isTrue);
          }
          for (var index = 0; index < 3; index++) {
            final swapped = state.reroll(
              index: index,
              today: day,
              eligibility: context,
            );
            // PRD G1 / round-2 orchestrator decision: a swapped-away M12
            // does not block M13; only the other current rows are checked.
            expect(state.canReroll(index, day, eligibility: context), isTrue);
            expect(
              swapped.missions[index].template,
              isNot(state.missions[index].template),
            );
            expect(swapped.missions[index].template, isNot(oldHard));
            expect(
              swapped.missions[index].template.difficulty,
              state.missions[index].template.difficulty,
            );
            expect(
              swapped.missions.any((m) => m.template == MissionTemplate.m12) &&
                  swapped.missions.any(
                    (m) => m.template == MissionTemplate.m13,
                  ),
              isFalse,
            );
          }
        }
      }
    }
  });

  test('all cumulative counts and one-run maxima, including O32 powerups', () {
    final state = withTemplates(MissionTemplate.values);
    const run = MissionRunCounts(
      gamesPlayedBefore: 3,
      hoops: 3,
      perfectPasses: 2,
      inRunCoins: 4,
      hourglasses: 1,
      miniBirds: 1,
      coinFrenzies: 1,
      shieldPickups: 1,
      cometStars: 1,
      pairGifts: 1,
      cometRides: 1,
      portalRides: 2,
      feathers: 1,
      pieces: 1,
      bullseyes: 1,
      openedSwitches: 1,
      versusWins: 1,
      maxPerfectStreak: 2,
      maxNoRimChain: 3,
      squeezesSurvived: 1,
    );
    // T0 M14/M15 are never assigned; check their counters directly instead.
    expect(run.count(MissionTemplate.m14), 1);
    expect(run.count(MissionTemplate.m15), 3);
    final next = state.advance(run).advance(run);
    const counts = [1, 3, 2, 4, 6, 3, 2, 1, 1, 1, 3, 2, 3];
    for (var i = 0; i < counts.length; i++) {
      final template = MissionTemplate.values[i];
      expect(
        next.missions[i].progress,
        (counts[i] * (template.oneRun ? 1 : 2)).clamp(0, template.targets[0]),
        reason: template.id,
      );
    }
    expect(
      const MissionRunCounts(gamesPlayedBefore: 3).count(MissionTemplate.m05),
      0,
    );
    expect(
      const MissionRunCounts(
        gamesPlayedBefore: 3,
        inRunCoins: -10,
      ).count(MissionTemplate.m04),
      0,
    );
  });

  test(
    'one-run missions never sum separate attempts and world uses hoops, not score',
    () {
      final state = withTemplates([
        MissionTemplate.m11,
        MissionTemplate.m12,
        MissionTemplate.m13,
        MissionTemplate.m15,
      ], tier: 1);
      const run = MissionRunCounts(
        gamesPlayedBefore: 3,
        hoops: 19,
        maxPerfectStreak: 5,
        maxNoRimChain: 9,
      );
      final attempted = state.advance(run).advance(run);
      expect(attempted.missions.every((m) => !m.complete), isTrue);
      final done = attempted.advance(
        const MissionRunCounts(
          gamesPlayedBefore: 3,
          hoops: 20,
          maxPerfectStreak: 6,
          maxNoRimChain: 10,
        ),
      );
      expect(done.missions.every((m) => m.complete), isTrue);
    },
  );

  test(
    'debug and first three runs count nothing; game 4 and revives count fully',
    () {
      final state = withTemplates([MissionTemplate.m02]);
      for (var before = 0; before < 3; before++) {
        expect(
          state.advance(
            MissionRunCounts(gamesPlayedBefore: before, hoops: 100),
          ),
          same(state),
        );
      }
      expect(
        state.advance(
          const MissionRunCounts(
            gamesPlayedBefore: 50,
            debug: true,
            hoops: 100,
          ),
        ),
        same(state),
      );
      // Caller aggregates the entire run, including all revive segments. Mode
      // never gates the model: free fly, weekly and solo versus share this path.
      expect(
        state
            .advance(const MissionRunCounts(gamesPlayedBefore: 3, hoops: 40))
            .missions
            .single
            .complete,
        isTrue,
      );
    },
  );

  test(
    'completion claims 20/35/55 once, serialized paid state survives kill',
    () {
      var state = withTemplates([
        MissionTemplate.m02,
        MissionTemplate.m04,
        MissionTemplate.m11,
      ]);
      expect(state.claimCoins().coins, 0);
      state = state.advance(
        const MissionRunCounts(gamesPlayedBefore: 3, hoops: 40, inRunCoins: 40),
      );
      final claim = state.claimCoins();
      expect(claim.coins, 110);
      expect(claim.completed, [
        MissionTemplate.m02,
        MissionTemplate.m04,
        MissionTemplate.m11,
      ]);
      state = restore(claim.state);
      expect(state.claimCoins().coins, 0);
      expect(
        state
            .advance(
              const MissionRunCounts(
                gamesPlayedBefore: 3,
                hoops: 100,
                inRunCoins: 100,
              ),
            )
            .claimCoins()
            .coins,
        0,
      );
      expect(state.chestPending, isTrue);
      final opened = state.claimChest(feathers: 0, pieces: 0);
      expect(opened.reward?.kind, MissionChestKind.feather);
      expect(
        restore(opened.state).claimChest(feathers: 0, pieces: 0).reward,
        isNull,
      );
    },
  );

  test('partial completions paid separately and only once', () {
    final state = withTemplates([
      MissionTemplate.m01,
      MissionTemplate.m04,
      MissionTemplate.m11,
    ]);
    final first = state
        .advance(const MissionRunCounts(gamesPlayedBefore: 3, hoops: 10))
        .claimCoins();
    expect(first.coins, 55);
    expect(first.state.chestPending, isFalse);
    final second = restore(first.state)
        .advance(const MissionRunCounts(gamesPlayedBefore: 4, inRunCoins: 40))
        .claimCoins();
    expect(second.coins, 35);
    final third = restore(
      second.state,
    ).advance(const MissionRunCounts(gamesPlayedBefore: 5)).claimCoins();
    expect(third.coins, 20);
    expect(third.state.chestPending, isTrue);
  });

  test('chest fallback inclusive feather/piece thresholds and 40 coins', () {
    for (final feathers in [0, 1, 2, 3]) {
      for (final pieces in [0, 1, 2, 3, 4]) {
        final reward = Missions.chestReward(feathers: feathers, pieces: pieces);
        expect(
          reward.kind,
          feathers <= 1
              ? MissionChestKind.feather
              : pieces <= 2
              ? MissionChestKind.piece
              : MissionChestKind.coins,
        );
        expect(reward.amount, feathers > 1 && pieces > 2 ? 40 : 1);
      }
    }
    expect(roll(20).claimChest(feathers: 0, pieces: 0).reward, isNull);
  });

  test(
    'reroll any unfinished slot once, reset progress, preserve other rows after reload',
    () {
      final context = eligibility();
      for (var index = 0; index < 3; index++) {
        final state = roll(20).advance(
          const MissionRunCounts(
            gamesPlayedBefore: 3,
            hoops: 1,
            inRunCoins: 1,
            perfectPasses: 1,
          ),
        );
        final swapped = state.reroll(
          index: index,
          today: 20,
          eligibility: context,
        );
        expect(restore(swapped).toRecords(), swapped.toRecords());
        expect(swapped.rerollDay, 20);
        expect(swapped.missions[index].progress, 0);
        expect(swapped.tier, state.tier);
        for (var other = 0; other < 3; other++) {
          if (other != index) {
            expect(swapped.missions[other], same(state.missions[other]));
          }
          final loaded = restore(swapped);
          expect(
            loaded.reroll(index: other, today: 20, eligibility: context),
            same(loaded),
          );
        }
        final tomorrow = restore(
          swapped,
        ).roll(today: 21, gamesPlayed: 5, eligibility: context);
        expect(tomorrow.canReroll(index, 21, eligibility: context), isTrue);
      }
    },
  );

  test('completed, invalid and stale-day swaps do nothing', () {
    final state = withTemplates([
      MissionTemplate.m02,
      MissionTemplate.m04,
      MissionTemplate.m11,
    ]).advance(const MissionRunCounts(gamesPlayedBefore: 3, hoops: 40));
    expect(
      state.reroll(index: 0, today: 20, eligibility: eligibility()),
      same(state),
    );
    for (final index in [-1, 3]) {
      expect(
        state.reroll(index: index, today: 20, eligibility: eligibility()),
        same(state),
      );
    }
    expect(
      state.reroll(index: 1, today: 21, eligibility: eligibility()),
      same(state),
    );
    expect(state.rerollDay, -1);
  });
  test(
    'earned chest survives midnight, app kills and repeated rolls exactly once',
    () {
      var state =
          withTemplates([
                MissionTemplate.m02,
                MissionTemplate.m04,
                MissionTemplate.m11,
              ])
              .advance(
                const MissionRunCounts(
                  gamesPlayedBefore: 3,
                  hoops: 40,
                  inRunCoins: 40,
                ),
              )
              .claimCoins()
              .state;
      expect(state.chestPending, isTrue);
      state = restore(
        state,
      ).roll(today: 21, gamesPlayed: 4, eligibility: eligibility());
      expect(state.allDone, isFalse);
      expect(state.chestsOwed, 1);
      expect(state.chestPending, isTrue);
      state = restore(
        state,
      ).roll(today: 21, gamesPlayed: 4, eligibility: eligibility());
      expect(state.chestsOwed, 1);
      state = restore(
        state,
      ).roll(today: 23, gamesPlayed: 4, eligibility: eligibility());
      expect(state.chestsOwed, 1);
      final claim = restore(state).claimChest(feathers: 2, pieces: 3);
      expect(claim.reward?.kind, MissionChestKind.coins);
      expect(claim.reward?.amount, 40);
      final loaded = restore(claim.state);
      expect(loaded.chestPending, isFalse);
      expect(loaded.claimChest(feathers: 0, pieces: 0).reward, isNull);
      expect(
        restore(
          loaded.roll(today: 24, gamesPlayed: 4, eligibility: eligibility()),
        ).chestPending,
        isFalse,
      );
    },
  );

  test('an older owed chest and the current board chest both pay once', () {
    var state = Missions(
      day: 20,
      chestsOwed: 1,
      missions: [
        for (final t in [
          MissionTemplate.m02,
          MissionTemplate.m04,
          MissionTemplate.m11,
        ])
          MissionProgress(
            template: t,
            target: t.targets[0],
            progress: t.targets[0],
          ),
      ],
    );
    state = restore(state.claimChest(feathers: 0, pieces: 0).state);
    expect(state.chestsOwed, 0);
    expect(state.chestPending, isTrue);
    state = restore(state.claimChest(feathers: 0, pieces: 0).state);
    expect(state.chestPending, isFalse);
    expect(state.claimChest(feathers: 0, pieces: 0).reward, isNull);
    expect(
      state
          .roll(today: 21, gamesPlayed: 4, eligibility: eligibility())
          .chestPending,
      isFalse,
    );
  });

  test('roll accumulates each earned chest without replacing an older one', () {
    final state = Missions(
      day: 20,
      chestsOwed: 1,
      missions: [
        for (final t in [
          MissionTemplate.m02,
          MissionTemplate.m04,
          MissionTemplate.m11,
        ])
          MissionProgress(
            template: t,
            target: t.targets[0],
            progress: t.targets[0],
          ),
      ],
    ).roll(today: 21, gamesPlayed: 4, eligibility: eligibility());
    expect(state.chestsOwed, 2);
    final first = restore(state).claimChest(feathers: 0, pieces: 0);
    expect(first.reward, isNotNull);
    final second = restore(first.state).claimChest(feathers: 0, pieces: 0);
    expect(second.reward, isNotNull);
    expect(
      restore(second.state).claimChest(feathers: 0, pieces: 0).reward,
      isNull,
    );
  });

  test('unknown/corrupt rows load leniently and rebuild on the same day', () {
    final valid = withTemplates([
      MissionTemplate.m02,
      MissionTemplate.m04,
      MissionTemplate.m11,
    ]).toRecords();
    final invalidRows = <Map<String, Object?>>[
      {'id': 'M16', 'target': 1},
      {'id': 'M01'},
      {'id': 'M01', 'target': '3'},
      {'id': 'M01', 'target': 3.0},
      {'id': 'M01', 'target': -1},
      {'id': 'M01', 'target': 3, 'progress': '2'},
      {'id': 'M01', 'target': 3, 'progress': -1},
      {'id': 'M01', 'target': 3, 'paid': 'true'},
      {'id': 'M01', 'target': 3, 'paid': true, 'progress': 1},
      {'id': 'M01', 'target': 999},
    ];
    for (final bad in invalidRows) {
      final loaded = Missions.fromRecords(
        day: 20,
        tier: 0,
        rerollDay: 20,
        records: [valid[0], valid[1], bad],
      );
      expect(loaded.missions, hasLength(2));
      // Invalid rows make the day unrolled without removing the rollback
      // watermark. The normal roll rebuilds a complete board on day 20.
      expect(
        loaded.roll(today: 19, gamesPlayed: 4, eligibility: eligibility()),
        same(loaded),
      );
      final rebuilt = loaded.roll(
        today: 20,
        gamesPlayed: 4,
        eligibility: eligibility(),
      );
      expect(rebuilt.missions, hasLength(3));
      expect(
        rebuilt.missions.map((m) => m.template.difficulty).toSet(),
        MissionDifficulty.values.toSet(),
      );
      expect(rebuilt.rerollDay, 20);
      expect(rebuilt.missions.every((m) => m.progress == 0), isTrue);
    }
  });

  test(
    'corrupt metadata and duplicate rows are safe; owed metadata survives empty rows',
    () {
      final valid = withTemplates([
        MissionTemplate.m02,
        MissionTemplate.m04,
        MissionTemplate.m11,
      ]).toRecords();
      for (final meta in <Object?>[
        null,
        'invalid',
        42,
        {'used': 'bad', 'chestsOwed': 'bad'},
        {
          'used': [null, 'M16'],
          'chestsOwed': -1,
        },
      ]) {
        final state = Missions.fromRecords(
          day: 20,
          tier: 0,
          rerollDay: -1,
          records: [
            {...valid[0], 'meta': meta},
            ...valid.skip(1),
          ],
        );
        expect(state.missions, hasLength(3));
        expect(state.chestsOwed, 0);
      }
      final duplicate = Missions.fromRecords(
        day: 20,
        tier: 0,
        rerollDay: -1,
        records: [valid[0], valid[0], valid[1]],
      );
      expect(duplicate.missions, hasLength(2));
      expect(
        duplicate
            .roll(today: 20, gamesPlayed: 4, eligibility: eligibility())
            .missions,
        hasLength(3),
      );
      final empty = Missions.fromRecords(
        day: 20,
        tier: 9,
        rerollDay: -1,
        records: [
          {
            'id': 'M16',
            'meta': {'chestsOwed': 1},
          },
        ],
      );
      expect(empty.missions, isEmpty);
      expect(empty.tier, 0);
      final claim = restore(empty).claimChest(feathers: 0, pieces: 0);
      expect(claim.reward?.kind, MissionChestKind.feather);
      expect(restore(claim.state).chestPending, isFalse);
    },
  );

  test('T0 M12 swaps to M13 with yesterday M11, once after reload', () {
    // PRD G1 / round-2 orchestrator decision: M12/M13 exclusion applies
    // only to OTHER current rows, allowing the old row to be replaced.
    final state = Missions(
      day: 20,
      previousHard: MissionTemplate.m11,
      missions: [
        for (final t in [
          MissionTemplate.m01,
          MissionTemplate.m03,
          MissionTemplate.m12,
        ])
          MissionProgress(template: t, target: t.targets[0]),
      ],
    );
    final context = eligibility(best: 0, met: {});
    expect(state.rerollCandidates(2, 20, context), [MissionTemplate.m13]);
    expect(state.canReroll(2, 20, eligibility: context), isTrue);
    final swapped = state.reroll(index: 2, today: 20, eligibility: context);
    expect(swapped.missions.last.template, MissionTemplate.m13);
    expect(
      swapped.usedTemplates,
      containsAll([MissionTemplate.m12, MissionTemplate.m13]),
    );
    expect(restore(swapped).canReroll(2, 20, eligibility: context), isFalse);
  });

  test(
    'SWAP is hidden with no eligible replacement and allowance remains unused',
    () {
      // PRD G1:879 / §8.3 item 18: the predicate used by UI checks the pool,
      // not just completion and the day's ad allowance.
      final state = Missions(
        day: 20,
        usedTemplates: {MissionTemplate.m01, MissionTemplate.m02},
        missions: [MissionProgress(template: MissionTemplate.m01, target: 3)],
      );
      final context = eligibility();
      expect(state.canReroll(0, 20, eligibility: context), isFalse);
      expect(state.rerollCandidates(0, 20, context), isEmpty);
      expect(
        state.reroll(index: 0, today: 20, eligibility: context),
        same(state),
      );
      expect(state.rerollDay, -1);
      expect(state.canReroll(-1, 20, eligibility: context), isFalse);
      expect(state.canReroll(0, 19, eligibility: context), isFalse);
    },
  );
  test('same-day corrupt-board recovery retains yesterday hard exclusion', () {
    for (var day = 1; day <= 50; day++) {
      final loaded = Missions.fromRecords(
        day: day,
        tier: 0,
        rerollDay: -1,
        records: [
          {
            'id': 'M16',
            'meta': {'previousHard': 'M11'},
          },
        ],
      );
      final rebuilt = loaded.roll(
        today: day,
        gamesPlayed: 4,
        eligibility: eligibility(best: 0, met: {}),
      );
      expect(rebuilt.previousHard, MissionTemplate.m11);
      expect(rebuilt.missions.last.template, isNot(MissionTemplate.m11));
    }
  });
}
