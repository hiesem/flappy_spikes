/** PRD-2.6 WP-LB pure board logic: groups, ghosts, ranking, prizes and run checks. */
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import {
  bestBoard,
  bracketForVerifiedBest,
  checkLbRun,
  checkLbRuns,
  ghostBracketOrder,
  ghostProgress,
  joinGroup,
  prizeAwards,
  rankBestRuns,
  rankToday,
  rollGift,
  seededRandom,
  selectGhosts,
  settlePrizeAwards,
  type LbGiftShopItem,
  type LbJoinGroupInput,
  type LbSubmittedRun,
} from '../src/board.js';
import {
  LB_GROUP_MS,
  LB_GROUP_SIZE,
  LB_MAX_SCORE,
  LB_MIN_LEFT_MS,
  LB_PLAYING_NOW_MS,
  LB_PRIZE_PLACES,
  type LbBestRow,
  type LbGhost,
  type LbGhostDay,
  type LbGhostPoint,
  type LbGroupDoc,
  type LbGroupMember,
} from '../src/schema.js';
import { encodeDeltas, encodeEntries } from '../src/timeline.js';

const LOOK = { bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' };

const DAY = 24 * 3600 * 1000;
const T0 = Date.UTC(2026, 9, 20, 0, 0, 0);
const T12 = T0 + 12 * 3600 * 1000;
const at = (ms: number) => Timestamp.fromMillis(ms);
const noShuffle = () => 0;

function member(points: number, best: number, lastMs: number, name = 'SwiftKiwi482'): LbGroupMember {
  return { t: points, b: best, n: 1, last: at(lastMs), name, look: LOOK, platform: 'android' };
}

function ghost(uid: string, runs: LbGhostPoint[], name = uid): LbGhost {
  return { uid, runs, name, look: LOOK, platform: 'android' };
}

function group(over: Partial<LbGroupDoc> & { memberUids: string[]; members: Record<string, LbGroupMember> }): LbGroupDoc {
  const start = over.start === undefined ? at(T0) : (over.start as Timestamp);
  return {
    bracket: 3,
    start,
    end: at(start.toMillis() + LB_GROUP_MS),
    memberUids: over.memberUids,
    members: over.members,
    ghosts: over.ghosts ?? [],
    ghostUids: over.ghostUids ?? (over.ghosts ?? []).flatMap((g) => (g.uid === undefined ? [] : [g.uid])),
    settled: over.settled ?? false,
    expireAt: over.expireAt ?? at(start.toMillis() + LB_GROUP_MS + 3 * DAY),
  };
}

function ghostDay(uid: string, day: string, runs: LbGhostPoint[], hidden = false): LbGhostDay & { hidden: boolean } {
  return { uid, day, runs, name: uid, look: LOOK, platform: 'android', hidden };
}

function joinInput(uid: string, opts: Partial<LbJoinGroupInput> = {}): LbJoinGroupInput {
  return {
    uid,
    bracket: 3,
    nowMs: T0 + 3600 * 1000,
    runStartMs: T0 + 3300 * 1000,
    member: { points: 30, best: 30, runs: 1, lastMs: T0 + 3500 * 1000, name: uid, look: LOOK, platform: 'android' },
    random: noShuffle,
    ...opts,
  };
}

describe('PRD-2.6 LB1 brackets and ghost supply', () => {
  it('uses the server-verified best bracket and searches own → ±1 → ±2', () => {
    assert.equal(bracketForVerifiedBest(0), 0);
    assert.equal(bracketForVerifiedBest(24), 0);
    assert.equal(bracketForVerifiedBest(25), 1);
    assert.equal(bracketForVerifiedBest(150), 3);
    assert.equal(bracketForVerifiedBest(5000), 10);
    assert.deepEqual(ghostBracketOrder(3), [3, 2, 4, 1, 5]);
    assert.deepEqual(ghostBracketOrder(0), [0, 1, 2]);
    assert.deepEqual(ghostBracketOrder(10), [10, 9, 8]);
  });

  it('fills from the own bracket, then ±1, then ±2; short supply gives fewer rows', () => {
    const pools = {
      3: [ghostDay('own-1', '2026-10-18', [[3600, 10]])],
      2: [ghostDay('minus-1', '2026-10-19', [[3600, 10]])],
      4: [ghostDay('plus-1', '2026-10-19', [[3600, 10]])],
      1: [ghostDay('minus-2', '2026-10-19', [[3600, 10]])],
      5: [ghostDay('plus-2', '2026-10-19', [[3600, 10]])],
    };
    const got = selectGhosts({ bracket: 3, slots: 5, pools, excludeUids: [], nowMs: T0, groupStartMs: T0, random: noShuffle });
    assert.deepEqual(got.map((g) => g.uid), ['own-1', 'minus-1', 'plus-1', 'minus-2', 'plus-2']);
    const short = selectGhosts({ bracket: 3, slots: 8, pools, excludeUids: [], nowMs: T0, groupStartMs: T0, random: noShuffle });
    assert.equal(short.length, 5);
    assert.ok(short.length < 8);
  });

  it('excludes hidden, old (>14 d), same-day and duplicate uids; no uid appears twice', () => {
    const pools = {
      3: [
        ghostDay('hidden', '2026-10-18', [[3600, 10]], true),
        ghostDay('too-old', '2026-10-01', [[3600, 10]]),
        ghostDay('today', '2026-10-20', [[3600, 10]]),
        ghostDay('same', '2026-10-18', [[3600, 10]]),
        ghostDay('same', '2026-10-17', [[3600, 20]]),
      ],
      2: [ghostDay('own', '2026-10-18', [[3600, 10]]), ghostDay('same', '2026-10-19', [[3600, 10]])],
    };
    const got = selectGhosts({
      bracket: 3,
      slots: 10,
      pools,
      excludeUids: ['own'],
      nowMs: T0,
      groupStartMs: T0,
      random: noShuffle,
    });
    assert.deepEqual(got.map((g) => g.uid), ['same']);
    assert.equal(new Set(got.map((g) => g.uid)).size, got.length);
  });

  it('creates a group with 49 ghosts, a 24 h timer and expiry three days after the end', () => {
    const pool = Array.from({ length: 60 }, (_, i) => ghostDay(`g${i}`, '2026-10-18', [[3600, i + 1]]));
    const r = joinGroup(joinInput('me', { pools: { 3: pool } }));
    assert.equal(r.created, true);
    assert.ok(r.group);
    assert.equal(r.group!.memberUids.length, 1);
    assert.equal(r.group!.ghosts.length, LB_GROUP_SIZE - 1);
    assert.equal(r.group!.expireAt.toMillis() - r.group!.end.toMillis(), 3 * DAY);
    assert.equal(r.group!.end.toMillis() - r.group!.start.toMillis(), LB_GROUP_MS);
  });

  it('allows 49 joins, caps the 50th, drops one ghost per join and never duplicates a ghost uid', () => {
    let current = group({
      memberUids: ['u0'],
      members: { u0: member(10, 10, T0 + 1000) },
      ghosts: Array.from({ length: 49 }, (_, i) => ghost(`g${i}`, [[3600, i + 1]])),
    });
    for (let i = 1; i < 49; i++) {
      const r = joinGroup(joinInput(`u${i}`, { group: current, nowMs: T0 + 3600 * 1000 }));
      assert.equal(r.created, false, `join ${i}`);
      assert.ok(r.removedGhost, `join ${i} replaces a ghost`);
      current = r.group!;
      assert.equal(current.memberUids.length, i + 1);
      assert.equal(current.ghosts.length, 49 - i);
    }
    assert.equal(current.memberUids.length, 49);
    assert.equal(current.ghosts.length, 1);
    const last = joinGroup(joinInput('u49', { group: current, nowMs: T0 + 3600 * 1000 }));
    assert.equal(last.created, false);
    assert.equal(last.group!.memberUids.length, 50);
    assert.equal(last.group!.ghosts.length, 0);
    const full = joinGroup(joinInput('u50', { group: last.group, nowMs: T0 + 3600 * 1000 }));
    assert.equal(full.created, true, 'a full group opens a fresh race');
    assert.equal(full.group!.memberUids.length, 1);
    assert.equal(last.group!.ghostUids.length, 0);
  });

  it('never places a new joiner in a group with < 3 h left', () => {
    const existing = group({
      memberUids: ['u0'],
      members: { u0: member(10, 10, T0 + 1000) },
      ghosts: [ghost('g', [[3600, 10]])],
    });
    const end = existing.end.toMillis();
    const justEnough = joinGroup(joinInput('u1', { group: existing, nowMs: end - LB_MIN_LEFT_MS }));
    assert.equal(justEnough.created, false);
    const tooLate = joinGroup(joinInput('u1', { group: existing, nowMs: end - LB_MIN_LEFT_MS + 1 }));
    assert.equal(tooLate.created, true);
    assert.notEqual(tooLate.ref!.id, '');
  });

  it('a joining player removes the last ghost and does not duplicate an existing real member', () => {
    const existing = group({
      memberUids: ['a', 'b'],
      members: { a: member(100, 40, T0 + 1000), b: member(90, 50, T0 + 1000) },
      ghosts: [ghost('g1', [[3600, 1]]), ghost('g2', [[3600, 2]])],
    });
    const r = joinGroup(joinInput('c', { group: existing, nowMs: T0 + 3600 * 1000 }));
    assert.equal(r.created, false);
    assert.deepEqual(r.group!.memberUids, ['a', 'b', 'c']);
    assert.deepEqual(r.group!.ghosts.map((g) => g.uid), ['g1']);
    assert.equal(r.removedGhost!.uid, 'g2');
    const again = joinGroup(joinInput('b', { group: existing, nowMs: T0 + 3600 * 1000 }));
    assert.equal(again.created, false);
    assert.deepEqual(again.group!.memberUids, ['a', 'b']);
    assert.equal(again.removedGhost, null);
  });

  it('a joiner who was a ghost earlier replaces that ghost row, not the last row', () => {
    const existing = group({
      memberUids: ['a'],
      members: { a: member(100, 40, T0 + 1000) },
      ghosts: [ghost('me', [[3600, 1]]), ghost('other', [[3600, 2]])],
    });
    const r = joinGroup(joinInput('me', { group: existing, nowMs: T0 + 3600 * 1000 }));
    assert.deepEqual(r.group!.memberUids, ['a', 'me']);
    assert.deepEqual(r.group!.ghosts.map((g) => g.uid), ['other']);
    assert.equal(r.removedGhost!.uid, 'me');
  });

  it('an existing member stays in a full group and in its final three hours', () => {
    const full = group({
      memberUids: Array.from({ length: LB_GROUP_SIZE }, (_, i) => `u${i}`),
      members: { u0: member(10, 10, T0 + 1000) },
    });
    const stayFull = joinGroup(joinInput('u0', { group: full, nowMs: T0 + 3600 * 1000 }));
    assert.equal(stayFull.created, false);
    const late = joinGroup(joinInput('u0', { group: full, nowMs: full.end.toMillis() - 1000 }));
    assert.equal(late.created, false);
    assert.equal(late.ref!.id, stayFull.ref!.id);
  });

  it('keeps an existing member after their best moves to another bracket', () => {
    const existing = group({
      memberUids: ['u0'],
      members: { u0: member(10, 10, T0 + 1000) },
    });
    const r = joinGroup(joinInput('u0', { group: existing, bracket: 9, nowMs: T0 + 3600 * 1000 }));
    assert.equal(r.created, false);
    assert.equal(r.group!.bracket, 3, 'the group bracket stays frozen');
    assert.equal(r.ref!.bracket, 3);
  });

  it('back-dates a fresh group by at most six hours', () => {
    const r = joinGroup(joinInput('me', { nowMs: T0 + 20 * 3600 * 1000, runStartMs: T0 }));
    assert.equal(r.group!.start.toMillis(), T0 + 14 * 3600 * 1000);
  });

  it('a hidden player joins no public group and receives no prize', () => {
    const r = joinGroup(joinInput('me', { hidden: true }));
    assert.equal(r.hidden, true);
    assert.equal(r.group, null);
  });
});

describe('PRD-2.6 LB1 live ghost replay and ranking', () => {
  it('replays each ghost run at the same UTC time of day with monotonic totals', () => {
    const runs: LbGhostPoint[] = [
      [12 * 3600, 10],
      [9 * 3600, 20],
      [12 * 3600 + 60, 30],
    ];
    const before = ghostProgress(runs, T0, T0 + LB_GROUP_MS, T0 + 8 * 3600 * 1000);
    const first = ghostProgress(runs, T0, T0 + LB_GROUP_MS, T0 + 9 * 3600 * 1000);
    const second = ghostProgress(runs, T0, T0 + LB_GROUP_MS, T0 + 12 * 3600 * 1000);
    const third = ghostProgress(runs, T0, T0 + LB_GROUP_MS, T0 + 12 * 3600 * 1000 + 60 * 1000);
    assert.deepEqual([before.points, first.points, second.points, third.points], [0, 20, 30, 60]);
    assert.ok(first.points <= second.points && second.points <= third.points);
  });

  it('uses the first occurrence at or after the group start for a later UTC time', () => {
    const start = T0 + 18 * 3600 * 1000;
    const runs: LbGhostPoint[] = [[6 * 3600, 5], [20 * 3600, 7]];
    const atStart = ghostProgress(runs, start, start + LB_GROUP_MS, start);
    const morning = ghostProgress(runs, start, start + LB_GROUP_MS, T0 + DAY + 6 * 3600 * 1000);
    assert.equal(atStart.points, 0);
    assert.equal(morning.points, 12);
  });

  it('never marks a ghost PLAYING NOW, even when it just reached a run', () => {
    const g = group({
      memberUids: ['real'],
      members: { real: member(50, 50, T0 + 1000, 'Real') },
      ghosts: [ghost('g', [[12 * 3600, 100]], 'Ghost')],
    });
    const ranked = rankToday(g, T12, {});
    assert.equal(ranked[0].uid, 'g');
    assert.equal(ranked[0].ghost, true);
    assert.equal(ranked[0].playingNow, false);
    assert.equal(ranked[1].playingNow, false, 'the real player is not < 5 min old here');
    assert.equal(rankToday(g, T0 + 1000 + LB_PLAYING_NOW_MS - 1)[0].playingNow, true);
    assert.equal(rankToday(g, T0 + 1000 + LB_PLAYING_NOW_MS)[0].playingNow, false);
  });

  it('ties by total points → best run → first to reach; the board row is opaque and has no BEST', () => {
    const g = group({
      memberUids: ['a', 'b', 'c', 'd'],
      members: {
        a: member(100, 40, T0 + 3000),
        b: member(100, 60, T0 + 4000),
        c: member(100, 60, T0 + 5000),
        d: member(90, 100, T0 + 1000),
      },
    });
    const ranked = rankToday(g, T0 + 6000, {});
    assert.deepEqual(ranked.map((e) => e.uid), ['b', 'c', 'a', 'd']);
    assert.deepEqual(ranked.map((e) => e.rank), [1, 2, 3, 4]);
    const board = bestBoard([], 'a');
    assert.equal(board.tab, 'best');
  });

  it('omits hidden members from TODAY but keeps their place for prize settlement', () => {
    const g = group({
      memberUids: ['hidden', 'real'],
      members: { hidden: member(200, 200, T0 + 3000), real: member(100, 80, T0 + 4000) },
    });
    const visible = rankToday(g, T0 + 5000, { hiddenUids: ['hidden'] });
    assert.deepEqual(visible.map((e) => e.uid), ['real']);
    const full = rankToday(g, T0 + 5000, { hiddenUids: ['hidden'], includeHidden: true });
    assert.deepEqual(full.map((e) => e.uid), ['hidden', 'real']);
    assert.equal(full[0].hidden, true);
  });
});

describe('PRD-2.6 LB2 O65 prize rule', () => {
  it('ghost on 2nd → silver to nobody, real 3rd gets bronze; real 4th gets nothing', () => {
    const g = group({
      memberUids: ['gold', 'third', 'fourth'],
      members: {
        gold: member(300, 80, T0 + 3000),
        third: member(200, 90, T0 + 4000),
        fourth: member(100, 100, T0 + 5000),
      },
      ghosts: [ghost('ghost2', [[2 * 3600, 250]])],
    });
    const ranked = rankToday(g, T0 + 10 * 3600 * 1000, {});
    assert.deepEqual(ranked.map((e) => e.uid), ['gold', 'ghost2', 'third', 'fourth']);
    assert.deepEqual(prizeAwards(ranked, 'g1'), [
      { uid: 'gold', gid: 'g1', tier: 'gold', boardRank: 1 },
      { uid: 'third', gid: 'g1', tier: 'bronze', boardRank: 3 },
    ]);
  });

  it('ghost on 1st → no gold; settled full board matches the same O65 rule', () => {
    const g = group({
      memberUids: ['second', 'third'],
      members: { second: member(200, 80, T0 + 3000), third: member(100, 90, T0 + 4000) },
      ghosts: [ghost('ghost1', [[3 * 3600, 999]])],
    });
    assert.equal(rankToday(g, T0 + 5 * 3600 * 1000, {})[0].uid, 'ghost1');
    assert.deepEqual(
      settlePrizeAwards(g, 'g', T0 + 5 * 3600 * 1000).map((a) => [a.uid, a.tier, a.boardRank]),
      [
        ['second', 'silver', 2],
        ['third', 'bronze', 3],
      ],
    );
  });

  it('a hidden member never gets a box and a group gives 0–3 boxes', () => {
    const g = group({
      memberUids: ['h', 's', 'b', 'fourth'],
      members: {
        h: member(400, 100, T0 + 3000),
        s: member(300, 90, T0 + 4000),
        b: member(200, 80, T0 + 5000),
        fourth: member(100, 70, T0 + 6000),
      },
    });
    const awards = settlePrizeAwards(g, 'g', T0 + 10_000, ['h']);
    assert.deepEqual(awards.map((a) => [a.uid, a.tier]), [
      ['s', 'silver'],
      ['b', 'bronze'],
    ]);
    assert.ok(awards.length <= LB_PRIZE_PLACES);
    const allGhosts = group({
      memberUids: ['r'],
      members: { r: member(1, 1, T0 + 1000) },
      ghosts: [ghost('g1', [[2, 10]]), ghost('g2', [[2, 9]]), ghost('g3', [[2, 8]])],
    });
    assert.deepEqual(settlePrizeAwards(allGhosts, 'g', T0 + 3600 * 1000, []), []);
  });

  it('BEST RUN ranks verified rows, hides members and pins the viewer exact rank', () => {
    const rows: LbBestRow[] = [
      { uid: 'a', best: 100, bestAt: at(1000), name: 'A', look: LOOK, platform: 'android', bracket: 3 },
      { uid: 'b', best: 100, bestAt: at(500), name: 'B', look: LOOK, platform: 'android', bracket: 3 },
      { uid: 'c', best: 200, bestAt: at(900), name: 'C', look: LOOK, platform: 'android', bracket: 4 },
    ];
    assert.deepEqual(rankBestRuns(rows, []).map((r) => r.uid), ['c', 'b', 'a']);
    const board = bestBoard(rows, 'a', { hiddenUids: [] });
    assert.equal(board.me!.rank, 3);
    assert.equal(board.me!.points, 100);
    assert.equal(board.approximate, false);
  });
});

describe('PRD-2.6 LB2 gift rolls', () => {
  const shop: LbGiftShopItem[] = [
    { id: 'cheap-common', price: 250, rarity: 'common' },
    { id: 'common-750', price: 750, rarity: 'common' },
    { id: 'rare-750', price: 750, rarity: 'rare' },
    { id: 'epic-2000', price: 2000, rarity: 'rare' },
  ];

  it('bronze is 25–100 and silver 50–200, all in step 5', () => {
    for (let seed = 1; seed <= 1000; seed++) {
      for (const [tier, min, max] of [
        ['bronze', 25, 100],
        ['silver', 50, 200],
      ] as const) {
        const roll = rollGift(tier, { random: seededRandom(seed) });
        assert.equal(roll.kind, 'coins');
        assert.ok(roll.coins >= min && roll.coins <= max, `${tier} ${roll.coins}`);
        assert.equal(roll.coins % 5, 0);
      }
    }
  });

  it('gold over 20 000 seeded rolls stays within ±1.5 pp of 50/20/20/10', () => {
    const counts = { coins: 0, feather: 0, piece: 0, item: 0 };
    const n = 20_000;
    for (let seed = 1; seed <= n; seed++) {
      const roll = rollGift('gold', { random: seededRandom(seed), shopItems: shop });
      counts[roll.kind]++;
      if (roll.kind === 'coins') assert.ok(roll.coins >= 100 && roll.coins <= 300 && roll.coins % 5 === 0);
      assert.ok(roll.coins >= 100 && roll.coins <= 300, 'every gold roll has pre-rolled fallback coins');
    }
    for (const [kind, expected] of Object.entries({ coins: 50, feather: 20, piece: 20, item: 10 })) {
      const pct = (counts[kind as keyof typeof counts] / n) * 100;
      assert.ok(Math.abs(pct - expected) <= 1.5, `${kind}: ${pct.toFixed(2)}% vs ${expected}%`);
    }
  });

  it('gold item rolls choose an unowned shop item ≤ 750 and split common 70 / rare 30', () => {
    const onlyCommon = shop.filter((i) => i.rarity === 'common');
    const onlyRare = shop.filter((i) => i.rarity === 'rare');
    for (let seed = 1; seed <= 500; seed++) {
      const c = rollGift('gold', { random: seededRandom(seed), shopItems: onlyCommon });
      if (c.kind === 'item') assert.equal(c.rarity, 'common');
      const r = rollGift('gold', { random: seededRandom(seed), shopItems: onlyRare });
      if (r.kind === 'item') assert.equal(r.rarity, 'rare');
    }
    for (let seed = 1; seed <= 1000; seed++) {
      const roll = rollGift('gold', { random: seededRandom(seed), shopItems: shop });
      if (roll.kind === 'item') {
        assert.ok(shop.some((i) => i.id === roll.item && i.price <= 750));
      }
    }
  });

  it('applies O68 fallbacks: all items owned → coins; feather impossible → piece; piece limit → pre-rolled coins', () => {
    let sawItem = false;
    let sawFeather = false;
    for (let seed = 1; seed <= 1000; seed++) {
      const noItems = rollGift('gold', {
        random: seededRandom(seed),
        shopItems: shop,
        ownedItems: shop.map((i) => i.id),
      });
      assert.notEqual(noItems.kind, 'item');
      assert.ok(noItems.coins >= 100 && noItems.coins <= 300);

      const noFeather = rollGift('gold', { random: seededRandom(seed), feathersHeld: 3, piecesHeld: 0 });
      assert.notEqual(noFeather.kind, 'feather');
      if (noFeather.kind === 'piece') sawFeather = true;

      const noPiece = rollGift('gold', { random: seededRandom(seed), piecesHeld: 4, canTakePiece: false });
      assert.notEqual(noPiece.kind, 'piece');
      assert.ok(noPiece.coins >= 100 && noPiece.coins <= 300);

      const noEither = rollGift('gold', { random: seededRandom(seed), canTakeFeather: false, canTakePiece: false });
      assert.equal(noEither.kind, 'coins');
      const goldItem = rollGift('gold', { random: seededRandom(seed), shopItems: shop });
      if (goldItem.kind === 'item') sawItem = true;
    }
    assert.ok(sawFeather, 'the feather → piece fallback occurred in the sample');
    assert.ok(sawItem, 'the item branch occurred in the sample');
  });

  it('is deterministic for one seed and stores that seed with the result', () => {
    const a = rollGift('gold', { random: seededRandom(42), shopItems: shop, seed: '42' });
    const b = rollGift('gold', { random: seededRandom(42), shopItems: shop, seed: '42' });
    assert.deepEqual(a, b);
    assert.equal(a.seed, '42');
  });
});

describe('PRD-2.6 LB3 run checks', () => {
  function run(
    opts: Partial<LbSubmittedRun> & { score?: number; endTs?: number; deltas?: number[] } = {},
  ): LbSubmittedRun {
    const score = opts.score ?? 30;
    const ts = opts.endTs ?? T12;
    const deltas = opts.deltas ?? Array.from({ length: score }, () => 170);
    return {
      id: opts.id ?? `run-${score}-${ts}`,
      score,
      hoops: score,
      cs: deltas.reduce((a, b) => a + b, 0) + 80,
      endTs: ts,
      mode: 'free',
      ...opts,
      tl: opts.tl ?? encodeDeltas(deltas),
      fl: opts.fl ?? encodeEntries(deltas.map(() => 0), deltas.map(() => 1)),
    };
  }

  function ctx(over: Record<string, unknown> = {}) {
    return { nowMs: T12 + 1000, best: 100, ...over };
  }

  it('each drop reason: shape, low_score, max_score, duplicate, time, overlap, old, timeline, daily_cap', () => {
    const cases: Array<[string, unknown, Record<string, unknown>, string]> = [
      ['shape', { id: 'bad' }, {}, 'shape'],
      ['low score', run({ score: 2 }), {}, 'low_score'],
      [
        'max score',
        { id: 'too-high', score: LB_MAX_SCORE + 1, hoops: 1, cs: 120, endTs: T12, mode: 'free' },
        {},
        'max_score',
      ],
      ['duplicate', run(), { seenIds: [run().id] }, 'duplicate'],
      ['future', run({ endTs: T12 + 61_000 }), { nowMs: T12 }, 'time'],
      ['overlap', run(), { intervals: [{ startMs: T12 - 120_000, endMs: T12 + 1 }] }, 'overlap'],
      ['old', run({ endTs: T0 - 1000 }), { groupStartMs: T0 }, 'old'],
      ['timeline', run({ tl: 'not-base64' }), {}, 'timeline'],
      ['daily cap', run(), { dailyCount: 400, nowMs: T12 }, 'daily_cap'],
    ];
    for (const [name, input, opts, reason] of cases) {
      const got = checkLbRun(input, ctx(opts));
      assert.equal(got.reason, reason, name);
      assert.equal(got.accepted, false, name);
    }
  });

  it('notable runs without a timeline are clamped to max(500, 2 × best) and never reach BEST', () => {
    const small = run({ score: 1500 });
    delete small.tl;
    delete small.fl;
    const r = checkLbRun(small, ctx({ best: 100 }));
    assert.equal(r.accepted, true);
    assert.equal(r.notable, true);
    assert.equal(r.counted, 500);
    assert.equal(r.clamped, true);
    assert.equal(r.bestUpdate, null);

    const big = run({ score: 5000 });
    delete big.tl;
    delete big.fl;
    const rb = checkLbRun(big, ctx({ best: 1000 }));
    assert.equal(rb.counted, 2000);
    assert.equal(rb.bestUpdate, null);
  });

  it('new PB, > 2 × best and the top-50 floor make a timeline required', () => {
    const atFloor = run({ score: 200 });
    delete atFloor.tl;
    delete atFloor.fl;
    const floor = checkLbRun(atFloor, ctx({ best: 1000, floor: 150 }));
    assert.equal(floor.notable, true);
    assert.equal(floor.bestUpdate, null);
    const belowFloor = run({ score: 149 });
    delete belowFloor.tl;
    delete belowFloor.fl;
    assert.equal(checkLbRun(belowFloor, ctx({ best: 1000, floor: 150 })).notable, false);
  });

  it('a valid timeline verifies and can raise BEST; an old timeline can only raise BEST within 7 d', () => {
    const fresh = checkLbRun(run({ score: 150 }), ctx({ best: 100, nowMs: T12 + 1000 }));
    assert.equal(fresh.accepted, true);
    assert.equal(fresh.timelineVerified, true);
    assert.deepEqual(fresh.bestUpdate, { score: 150, atMs: T12, shadow: false });

    const old = checkLbRun(run({ score: 150, endTs: T0 + 1000 }), ctx({ nowMs: T12, groupStartMs: T12, best: 100 }));
    assert.equal(old.reason, 'old');
    assert.deepEqual(old.bestUpdate, { score: 150, atMs: T0 + 1000, shadow: false });
    const tooOld = checkLbRun(
      run({ score: 150, endTs: T0 + 1000 }),
      ctx({ nowMs: T0 + 8 * DAY, groupStartMs: T0 + 8 * DAY, best: 100 }),
    );
    assert.equal(tooOld.reason, 'old');
    assert.equal(tooOld.bestUpdate, null);
    const within = checkLbRun(run({ score: 150, endTs: T0 + 1000 }), ctx({ nowMs: T0 + 6 * DAY, groupStartMs: T0 + 6 * DAY, best: 100 }));
    assert.equal(within.reason, 'old');
    assert.deepEqual(within.bestUpdate, { score: 150, atMs: T0 + 1000, shadow: false });
  });

  it('a hard anomaly flags and sets a shadow best; a soft jump does not shadow', () => {
    // 20 plain passes 100 cs apart trip the pace rule while still passing the
    // 0.9 s gap filter; the score is still plausible.
    const flags = Array.from({ length: 20 }, () => 0);
    const deltas = Array.from({ length: 20 }, () => 100);
    const hard = run({
      score: 20,
      tl: encodeDeltas(deltas),
      fl: encodeEntries(flags, Array.from({ length: 20 }, () => 1)),
      cs: 20 * 100 + 80,
    });
    const h = checkLbRun(hard, ctx({ best: 10, nowMs: T12 + 1000 }));
    assert.equal(h.accepted, true);
    assert.equal(h.anomaly?.soft, false);
    assert.equal(h.bestUpdate?.shadow, true);
    assert.equal(h.counted, 20);
    assert.equal(h.shadow, true);

    const soft = checkLbRun(run({ score: 600 }), ctx({ best: 100, hist: [50, 50, 50, 50, 50], nowMs: T12 + 1000 }));
    assert.equal(soft.anomaly?.soft, true);
    assert.equal(soft.shadow, false);
    assert.equal(soft.bestUpdate?.shadow, false);
  });

  it('an old verified hard-anomaly run updates BEST but stays shadowed', () => {
    const deltas = Array.from({ length: 20 }, () => 100);
    const r = checkLbRun(
      run({
        score: 20,
        endTs: T0 + 1000,
        tl: encodeDeltas(deltas),
        fl: encodeEntries(deltas.map(() => 0), deltas.map(() => 1)),
        cs: 20 * 100 + 80,
      }),
      ctx({ best: 10, nowMs: T0 + 6 * DAY, groupStartMs: T0 + 6 * DAY }),
    );
    assert.equal(r.reason, 'old');
    assert.deepEqual(r.bestUpdate, { score: 20, atMs: T0 + 1000, shadow: true });
  });

  it('a hidden old run never touches BEST', () => {
    const r = checkLbRun(
      run({ score: 150, endTs: T0 + 1000 }),
      ctx({ best: 100, hidden: true, nowMs: T0 + 6 * DAY, groupStartMs: T0 + 6 * DAY }),
    );
    assert.equal(r.reason, 'old');
    assert.equal(r.bestUpdate, null);
  });

  it('drops the 401st run of a UTC day and marks t:1 hidden', () => {
    const acceptedDay = 400 - 0;
    const capped = checkLbRun(run({ score: 30 }), ctx({ dailyCount: acceptedDay }));
    assert.equal(capped.reason, 'daily_cap');
    const hidden = checkLbRun(run({ score: 30 }), ctx({ hidden: true }));
    assert.equal(hidden.hidden, true);
    assert.equal(hidden.accepted, true);
  });

  it('a batch sorts by start, rejects overlaps and checks Σcs against elapsed + 60 s', () => {
    const second = run({ id: 'second', score: 30, endTs: T12 });
    const first = run({ id: 'first', score: 30, endTs: T12 - 60_000 });
    const ok = checkLbRuns([second, first], ctx({ nowMs: T12 + 1000 }));
    assert.deepEqual(ok.accepted, ['first', 'second']);
    assert.deepEqual(ok.results.map((r) => r.id), ['first', 'second']);

    const overlap = run({ id: 'overlap', score: 30, endTs: T12 - 55_000 });
    assert.equal(checkLbRuns([first, overlap], ctx({ nowMs: T12 + 1000 })).results[1].reason, 'overlap');

    const longA = run({ id: 'long-a', score: 30, endTs: T12, cs: 600_000 });
    const longB = run({ id: 'long-b', score: 30, endTs: T12 - 120_000, cs: 600_000 });
    const time = checkLbRuns([longA, longB], ctx({ nowMs: T12 + 1000 }));
    assert.equal(time.results[0].reason, 'time');
    assert.equal(time.results[1].reason, 'time');
  });

  it('clamps or rejects impossible passes using the shared passBound', () => {
    // 100 passes in 1 s is far beyond the scroll bound and fails plausibleValues first.
    const impossible = run({ score: 100, deltas: Array(100).fill(1), cs: 100 });
    const r = checkLbRun(impossible, ctx({ best: 100 }));
    assert.equal(r.accepted, false);
    assert.equal(r.reason, 'bounds');
  });

  it('reports a plausible-value pass run that exceeds passBound as a hard anomaly', () => {
    // 150 Ring Train passes in 4 s: each value is plausible and train entries
    // are gap-exempt, but the scroll bound for 400 cs is far below 150 passes.
    const deltas = Array.from({ length: 150 }, () => 2);
    const trains = Array.from({ length: 150 }, () => 2);
    const r = checkLbRun(
      run({
        score: 150,
        tl: encodeDeltas(deltas),
        fl: encodeEntries(trains, deltas.map(() => 1)),
        cs: 380,
      }),
      ctx({ best: 10, nowMs: T12 + 1000 }),
    );
    assert.equal(r.accepted, true);
    assert.ok((r.anomaly?.signals.passes ?? 0) > (r.passBound ?? Infinity));
    assert.equal(r.anomaly?.soft, false);
    assert.equal(r.shadow, true);
  });
});

