import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/showcase_config.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Events {
  final events = <({String name, Map<String, Object> params})>[];

  void track(String name, Map<String, Object> params) {
    events.add((name: name, params: params));
  }

  List<({String name, Map<String, Object> params})> named(String name) => [
    for (final event in events)
      if (event.name == name) event,
  ];
}

Future<(GameStorage, ShowcaseShow, _Events)> _show([
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = GameStorage();
  await storage.load();
  final events = _Events();
  final show = ShowcaseShow(storage: storage, tracker: events.track);
  return (storage, show, events);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ShowcaseShow.resetProcessMemoryForTests);

  test('A increments at START and is saved', () async {
    final (storage, show, events) = await _show();

    final first = show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    expect(first, isNotNull);
    expect(first!.attempt, 1);
    expect(storage.showcaseAttempt, 1);
    await show.writesSettled;
    expect(events.named('showcase_start').single.params, {
      'step': 1,
      'attempt': 1,
    });

    final saved = GameStorage();
    await saved.load();
    expect(saved.showcaseAttempt, 1);

    // The same step after a death before the highlight is A = 2.
    show.onRunEnd(gamesPlayed: 1, hoopsPassed: 2);
    final second = show.atStart(
      gamesPlayed: 1,
      seen: saved.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    expect(second!.attempt, 2);
    expect(second.step, 0);
    expect(second.portalHoops, [5]);
    expect(storage.showcaseAttempt, 2);
    await show.writesSettled;
  });

  test('a highlight bit survives a kill / new Storage, and the next START '
      'moves to the next step at A = 1', () async {
    final (storage, show, _) = await _show();
    show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onHighlight('portal', scripted: true, hoop: 7);
    expect(storage.showcaseSeen & 1, 1);
    await show.writesSettled;

    // Process kill: a fresh storage reads the exact same bits.
    final restarted = GameStorage();
    await restarted.load();
    expect(restarted.showcaseSeen & 1, 1);
    expect(restarted.showcaseAttempt, 0);
    final next = ShowcaseShow(storage: restarted);
    final plan = next.atStart(
      gamesPlayed: 1,
      seen: restarted.showcaseSeen,
      attempt: restarted.showcaseAttempt,
      forced: false,
    );
    expect(plan, isNotNull);
    expect(plan!.step, 1);
    expect(plan.highlightId, 'comet');
    expect(plan.attempt, 1);
    expect(restarted.showcaseAttempt, 1);
    await next.writesSettled;
  });

  test('a recognized organic highlight sets its own bit', () async {
    final (storage, show, events) = await _show();
    show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onHighlight('portal', scripted: false, hoop: 20);
    expect(storage.showcaseSeen, 1);
    expect(storage.showcaseAttempt, 0);
    expect(events.named('highlight_seen').single.params, {
      'id': 'portal',
      'scripted': 0,
      'run_no': 1,
      'hoop': 20,
    });
    await show.writesSettled;

    final restarted = GameStorage();
    await restarted.load();
    expect(restarted.showcaseSeen, 1);
  });

  test('an organic other-step highlight is recorded without completing the '
      'planned highlight', () async {
    final (storage, show, events) = await _show();
    show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onHighlight('comet', scripted: false, hoop: 12);
    expect(storage.showcaseSeen, 1 << 1);
    expect(storage.showcaseAttempt, 1);
    expect(events.named('highlight_seen'), isEmpty);

    show.onRunEnd(
      gamesPlayed: 1,
      hoopsPassed: 12,
      score: 13,
      cause: 'spikes',
      shieldUsed: true,
      reviveUsed: true,
    );
    expect(events.named('showcase_end').single.params, {
      'step': 1,
      'attempt': 1,
      'hoops': 12,
      'highlight': 0,
      'score': 13,
      'cause': 'spikes',
      'shield_used': 1,
      'revive_used': 1,
    });
    await show.writesSettled;
  });

  test('done via all: all bits set -> done at run end', () async {
    final (storage, show, events) = await _show();
    storage.showcaseSeen = 0x3; // portal and comet seen
    show.atStart(
      gamesPlayed: 4,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onHighlight('fever', scripted: true, hoop: 5);
    expect(show.done, isFalse);
    show.onRunEnd(gamesPlayed: 5, hoopsPassed: 20);
    expect(show.done, isTrue);
    expect(storage.showcaseDoneAt, 5);
    expect(storage.showcaseSeen & (1 << ShowcaseConfig.doneBit), isNot(0));
    expect(storage.showcaseRuns, 1);
    final done = events.named('showcase_done').single.params;
    expect(done['runs'], 1);
    expect(done['via'], 'all');
    expect(done.containsKey('s_since_install'), isTrue);
    await show.writesSettled;
  });

  test('done via cap: gamesPlayed >= 6', () async {
    final (storage, show, events) = await _show();
    storage.showcaseSeen = 0x1;
    final plan = show.atStart(
      gamesPlayed: 5,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    expect(plan, isNotNull);
    show.onRunEnd(gamesPlayed: 6, hoopsPassed: 10);
    expect(show.done, isTrue);
    expect(storage.showcaseDoneAt, 6);
    expect(events.named('showcase_done').single.params['via'], 'cap');
    await show.writesSettled;
  });

  test('done via fast: a showcase run passing 40 hoops', () async {
    final (storage, show, events) = await _show();
    show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onRunEnd(gamesPlayed: 1, hoopsPassed: 40);
    expect(show.done, isTrue);
    expect(storage.showcaseDoneAt, 1);
    expect(events.named('showcase_done').single.params['via'], 'fast');
    await show.writesSettled;
  });

  test('showcase_done is emitted once with runs and s_since_install', () async {
    final (storage, show, events) = await _show({'playtimeSeconds': 123});
    show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    show.onRunEnd(gamesPlayed: 1, hoopsPassed: 40);
    show.onRunEnd(gamesPlayed: 1, hoopsPassed: 40); // no active plan
    show.atStart(
      gamesPlayed: 1,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    final done = events.named('showcase_done');
    expect(done, hasLength(1));
    expect(done.single.params['runs'], 1);
    expect(done.single.params['s_since_install'], 123);
    expect(done.single.params.containsKey('via'), isTrue);
    await show.writesSettled;
  });

  test('a tester / existing install with gamesPlayed >= 3 and no showcase '
      'key is done and gets no plan', () async {
    final (storage, show, events) = await _show({'gamesPlayed': 3});
    expect(show.isTesterInstall, isTrue);
    expect(show.adoptLegacyDone(), isTrue);
    expect(show.adoptLegacyDone(), isFalse);
    expect(show.done, isTrue);
    final plan = show.atStart(
      gamesPlayed: 3,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    expect(plan, isNull);
    expect(show.active, isFalse);
    expect(show.done, isTrue);
    expect(storage.showcaseDoneAt, 3);
    expect(storage.showcaseSeen & (1 << ShowcaseConfig.doneBit), isNot(0));
    expect(events.named('showcase_done').single.params['via'], 'all');
    await show.writesSettled;
  });

  test('the tester fallback uses the atStart gamesPlayed argument', () async {
    final (_, show, _) = await _show();
    final plan = show.atStart(
      gamesPlayed: 3,
      seen: 0,
      attempt: 0,
      forced: false,
    );
    expect(plan, isNull);
    expect(show.storage.showcaseDoneAt, 3);
    await show.writesSettled;
  });

  test('forced runs never build or advance the showcase', () async {
    final (storage, show, events) = await _show();
    final plan = show.atStart(
      gamesPlayed: 0,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: true,
    );
    expect(plan, isNull);
    expect(storage.showcaseAttempt, 0);
    expect(events.events, isEmpty);
  });

  test('Delete my data (cleared keys) returns to step 1 and A = 1', () async {
    SharedPreferences.setMockInitialValues({
      'gamesPlayed': 6,
      'showcaseSeen': 0x7 | (1 << ShowcaseConfig.doneBit),
      'showcaseDoneAt': 5,
    });
    final storage = GameStorage();
    await storage.load();
    final show = ShowcaseShow(storage: storage);
    // A completed showcase run: this model has seen showcase state, so the
    // legacy install fallback is no longer relevant.
    expect(show.done, isTrue);
    expect(show.isTesterInstall, isFalse);
    await show.writesSettled;

    await storage.resetVersusData();
    // Delete my data keeps gamesPlayed. The live model saw the state before
    // the reset, so the legacy-install fallback must not swallow the replay.
    final plan = show.atStart(
      gamesPlayed: storage.gamesPlayed,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: false,
    );
    expect(plan, isNotNull);
    expect(plan!.step, 0);
    expect(plan.attempt, 1);
    expect(plan.portalHoops, [7]);
    await show.writesSettled;
  });

  test(
    'Delete my data replays after a process restart at gamesPlayed 3, 5 and 6',
    () async {
      for (final gamesPlayed in [3, 5, 6]) {
        ShowcaseShow.resetProcessMemoryForTests();
        SharedPreferences.setMockInitialValues({
          'gamesPlayed': gamesPlayed,
          'showcaseSeen': 0x7 | (1 << ShowcaseConfig.doneBit),
          'showcaseAttempt': 1,
          'showcaseRuns': 3,
          'showcaseDoneAt': gamesPlayed,
        });
        final storage = GameStorage();
        await storage.load();
        final before = ShowcaseShow(storage: storage);
        expect(before.done, isTrue);

        await storage.resetVersusData();
        ShowcaseShow.resetProcessMemoryForTests();
        final fresh = GameStorage();
        await fresh.load();
        final restarted = ShowcaseShow(storage: fresh);
        final plan = restarted.atStart(
          gamesPlayed: fresh.gamesPlayed,
          seen: fresh.showcaseSeen,
          attempt: fresh.showcaseAttempt,
          forced: false,
        );
        expect(
          plan,
          isNotNull,
          reason: 'Deletion must survive a process restart',
        );
        expect(plan!.step, 0);
        expect(plan.attempt, 1);
        expect(plan.portalHoops, [7]);
        await restarted.writesSettled;
      }
    },
  );

  test(
    'queued showcase writes cannot restore keys cleared by Delete my data',
    () async {
      final (storage, show, _) = await _show();
      show.atStart(
        gamesPlayed: 0,
        seen: storage.showcaseSeen,
        attempt: storage.showcaseAttempt,
        forced: false,
      );
      show.onHighlight('portal', scripted: true, hoop: 7);
      show.onRunEnd(gamesPlayed: 1, hoopsPassed: 40);

      await storage.resetVersusData();
      await show.writesSettled;

      final fresh = GameStorage();
      await fresh.load();
      expect(fresh.showcaseSeen, 0);
      expect(fresh.showcaseAttempt, 0);
      expect(fresh.showcaseRuns, 0);
      expect(fresh.showcaseDoneAt, isNull);
    },
  );

  test(
    'a second storage instance after reset starts at step 1, A = 1',
    () async {
      SharedPreferences.setMockInitialValues({'gamesPlayed': 0});
      final storage = GameStorage();
      await storage.load();
      final show = ShowcaseShow(storage: storage);
      show.atStart(
        gamesPlayed: 0,
        seen: storage.showcaseSeen,
        attempt: storage.showcaseAttempt,
        forced: false,
      );
      show.onHighlight('portal', scripted: true, hoop: 7);
      await show.writesSettled;
      await storage.resetVersusData();
      await storage.saveGamesPlayed(0);

      final fresh = GameStorage();
      await fresh.load();
      final restarted = ShowcaseShow(storage: fresh);
      final plan = restarted.atStart(
        gamesPlayed: fresh.gamesPlayed,
        seen: fresh.showcaseSeen,
        attempt: fresh.showcaseAttempt,
        forced: false,
      );
      expect(plan!.step, 0);
      expect(plan.attempt, 1);
      await restarted.writesSettled;
    },
  );
}
