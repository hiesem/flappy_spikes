import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/music_log.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3 §13: the music sometimes disappears (investigate and fix).
/// Fake `AudioFocus` and the game clock (§13.5).
void main() {
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester(FakeAudioFocus focus) =>
      FlameTester<FlappySpikesGame>(() {
        spy.events.clear();
        return createRunTestGame(services: spy, worldHeight: 711)
          ..audioFocus = focus;
      }, gameSize: Vector2(320, 711));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  /// Steps [seconds] of game time in 0.1 s slices, flushing the async
  /// checks in between (like frames on the phone).
  Future<void> advance(FlappySpikesGame g, double seconds) async {
    var t = 0.0;
    while (t < seconds - 1e-9) {
      stepGame(g, .1);
      t += .1;
      await flushAndMount(g);
    }
  }

  /// Advances until [done] or [limit] s; returns the time it took.
  Future<double> until(
    FlappySpikesGame g,
    bool Function() done, {
    double limit = 10,
  }) async {
    var t = 0.0;
    while (!done() && t < limit) {
      await advance(g, .1);
      t += .1;
    }
    return t;
  }

  List<String> musicLog(FlappySpikesGame g) {
    final log = <String>[];
    g.sound.onMusic = log.add;
    return log;
  }

  List<Map<String, Object>?> held() => [
    for (final e in spy.events)
      if (e.$1 == 'music_held') e.$2,
  ];

  // ----------------------------------------------------------- own music

  final launch = FakeAudioFocus()..otherMusic = true;
  tester(launch).testGameWidget(
    '§13.5 "other music" for 0.5 s at launch: the music plays on Home '
    'within 3 s',
    setUp: boot,
    verify: (g, _) async {
      expect(g.sound.musicPlaying, isFalse, reason: 'first yes: waits 1 s');
      await advance(g, .5);
      launch.otherMusic = false;
      final t = await until(g, () => g.sound.musicPlaying);
      expect(g.sound.musicPlaying, isTrue);
      expect(t + .5, lessThanOrEqualTo(3));
      expect(g.sound.ownMusicSkipped, isFalse, reason: 'second check: no');
      expect(g.state, GameState.start);
    },
  );

  final fg = FakeAudioFocus();
  tester(fg).testGameWidget(
    '§13.5 "other music" for 0.5 s on return to the foreground: the music '
    'plays on Home within 3 s, with no scene change',
    setUp: boot,
    verify: (g, _) async {
      expect(g.sound.musicPlaying, isTrue);
      g.lifecycleStateChange(AppLifecycleState.paused);
      expect(g.sound.musicPlaying, isFalse);
      fg.otherMusic = true;
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse, reason: 'checked 1 s later');
      await advance(g, .5);
      fg.otherMusic = false;
      final t = await until(g, () => g.sound.musicPlaying);
      expect(g.sound.musicPlaying, isTrue);
      expect(t + .5, lessThanOrEqualTo(3));
      expect(g.sound.ownMusicSkipped, isFalse);
      expect(g.state, GameState.start);
      expect(g.menuScene, MenuScene.home);
    },
  );

  final keeps = FakeAudioFocus()..otherMusic = true;
  tester(keeps).testGameWidget(
    '§13.5 "other music" that keeps playing: the music stays off, then '
    'comes back within 3 s of it stopping, on Home (re-check every 2 s)',
    setUp: boot,
    verify: (g, _) async {
      await advance(g, 8);
      expect(g.sound.ownMusicSkipped, isTrue);
      expect(g.sound.musicPlaying, isFalse);
      final before = keeps.checks;
      await advance(g, 4);
      expect(
        keeps.checks - before,
        inInclusiveRange(2, 3),
        reason: 'every 2 s',
      );
      keeps.otherMusic = false;
      final t = await until(g, () => g.sound.musicPlaying);
      expect(g.sound.musicPlaying, isTrue);
      expect(t, lessThanOrEqualTo(3));
      expect(g.menuScene, MenuScene.home);
    },
  );

  final already = FakeAudioFocus()..otherMusic = true;
  tester(already).testGameWidget(
    '§13.5 other music already playing at the run start: no music until the '
    'run ends (PRD-2.2 §28.3 holds)',
    setUp: boot,
    verify: (g, _) async {
      await settleMusicChecks(g);
      expect(g.sound.ownMusicSkipped, isTrue);
      await startRun(g);
      g.runDebug.god = true;
      await advance(g, 1);
      already.otherMusic = false;
      await advance(g, 6);
      expect(g.state, GameState.playing);
      expect(g.sound.musicPlaying, isFalse, reason: 'never mid-run');
      g.runDebug.god = false;
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      // The results page is a menu: the re-check brings it back.
      final t = await until(g, () => g.sound.musicPlaying, limit: 4);
      expect(g.sound.musicPlaying, isTrue);
      expect(t, lessThanOrEqualTo(3));
    },
  );

  final midRun = FakeAudioFocus();
  tester(midRun).testGameWidget(
    '§13.5 other music starting mid-run: no music until the run ends',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      g.runDebug.god = true;
      await advance(g, .5);
      expect(g.sound.musicPlaying, isTrue);
      // The player starts their own music (a media player that keeps
      // playing) while the game is in the foreground.
      midRun.otherMusic = true;
      midRun.push(const AudioWatchState(media: true, players: ['1:1']));
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse, reason: 'paused at once');
      await advance(g, Config.musicMediaSoundOwnAfter + .2);
      expect(g.sound.ownMusicSkipped, isTrue, reason: 'it kept playing');
      // It stops mid-run: the music stays off until the run ends.
      midRun.otherMusic = false;
      midRun.push(const AudioWatchState());
      await advance(g, 5);
      expect(g.state, GameState.playing);
      expect(g.sound.musicPlaying, isFalse);
      g.runDebug.god = false;
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      await until(g, () => g.sound.musicPlaying, limit: 4);
      expect(g.sound.musicPlaying, isTrue);
    },
  );

  // ------------------------------------------------- suspend and watchdog

  final quiet = FakeAudioFocus();
  tester(quiet).testGameWidget(
    '§13.5 an ad suspend without its resume, with no ad showing: cleared '
    'within 5 s on Home',
    setUp: boot,
    verify: (g, _) async {
      g.sound.suspend();
      expect(g.sound.musicPlaying, isFalse);
      await advance(g, 4.5);
      expect(g.sound.suspended, isTrue);
      final t = await until(g, () => !g.sound.suspended);
      expect(g.sound.suspended, isFalse);
      expect(4.5 + t, lessThanOrEqualTo(5.2));
      expect(g.sound.musicPlaying, isTrue);
      expect(g.sound.musicLog.events, contains('clear-suspend'));
    },
  );

  final dead = FakeAudioFocus();
  tester(dead).testGameWidget(
    '§13.5 a dead music player (the fake reports stopped): the watchdog '
    'restarts it within 5 s and logs player_dead',
    setUp: boot,
    verify: (g, _) async {
      expect(g.sound.musicPlaying, isTrue);
      final music = musicLog(g);
      var state = 'stopped';
      g.sound.musicStateProbe = () => state;
      final t = await until(g, () => music.isNotEmpty);
      expect(t, lessThanOrEqualTo(5.05));
      expect(music, ['start'], reason: 'from the start of the loop');
      expect(g.sound.musicLog.events, contains('player_dead'));
      state = 'playing';
      await advance(g, 6);
      expect(music, ['start'], reason: 'a live player is left alone');
    },
  );

  // ----------------------------------------------------------- music_held

  final heldFocus = FakeAudioFocus()..otherMusic = true;
  tester(heldFocus).testGameWidget(
    '§13.5 music_held fires once per Home visit with the right reason',
    setUp: boot,
    verify: (g, _) async {
      await advance(g, 9);
      expect(held(), isEmpty);
      await advance(g, 2.5);
      expect(held(), [
        {'reason': 'own_music', 'source': 'launch'},
      ]);
      await advance(g, 15);
      expect(held(), hasLength(1), reason: 'once per Home visit');
      expect(
        g.sound.musicLog.events.where((e) => e.startsWith('music_held')),
        hasLength(1),
      );
    },
  );

  final mutedHeld = FakeAudioFocus()..otherMusic = true;
  tester(mutedHeld).testGameWidget(
    '§13.3 music_held needs the music setting on (volume above 0)',
    setUp: boot,
    verify: (g, _) async {
      await g.sound.setMusicVolume(0);
      await advance(g, 12);
      expect(held(), isEmpty);
    },
  );

  // -------------------------------------------------------- notifications

  final notif = FakeAudioFocus();
  tester(notif).testGameWidget(
    '§13.5 a notification sound (a NOTIFICATION player for 1.5 s, then '
    'listed but no longer playing): the music pauses, then resumes within '
    '1 s of it ending, with no navigation; sound effects stay on',
    setUp: boot,
    verify: (g, _) async {
      final music = musicLog(g);
      final audible = <Sfx>[];
      g.sound.onAudible = audible.add;
      notif.push(const AudioWatchState(notification: true, players: ['5:1']));
      await flushAndMount(g);
      expect(music, ['pause']);
      expect(g.sound.interrupted, isFalse, reason: 'not a call');
      g.sound.play(Sfx.click);
      expect(audible, [Sfx.click], reason: 'SFX keep playing');
      await advance(g, 1.5);
      // The ding ended; the player stays listed and no callback fires.
      notif.push(const AudioWatchState(players: ['5:0']), notify: false);
      final t = await until(g, () => g.sound.musicPlaying);
      expect(t, lessThanOrEqualTo(1));
      expect(music, ['pause', 'resume'], reason: 'position kept');
      expect(g.sound.ownMusicSkipped, isFalse);
      expect(g.state, GameState.start);
      expect(
        g.sound.musicLog.events,
        containsAllInOrder(['notify', 'notify-end']),
      );
    },
  );

  final notifRun = FakeAudioFocus();
  tester(notifRun).testGameWidget(
    '§13.4 a notification mid-run pauses the music and it comes back '
    'within 1 s, mid-run',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      g.runDebug.god = true;
      await advance(g, .3);
      expect(g.sound.musicPlaying, isTrue);
      notifRun.push(
        const AudioWatchState(notification: true, players: ['10:1']),
      );
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse);
      await advance(g, 1);
      notifRun.push(const AudioWatchState());
      final t = await until(g, () => g.sound.musicPlaying);
      expect(t, lessThanOrEqualTo(1));
      expect(g.state, GameState.playing);
    },
  );

  final ding = FakeAudioFocus();
  tester(ding).testGameWidget(
    '§13.5 a 1.5 s MEDIA player starting in the foreground (a plain '
    'MediaPlayer notification) with inactive -> resumed around it: no '
    '"own music" skip, the music is back within 1 s',
    setUp: boot,
    verify: (g, _) async {
      ding.otherMusic = true; // listed as another app's media player
      ding.push(const AudioWatchState(media: true, players: ['1:1']));
      g.lifecycleStateChange(AppLifecycleState.inactive);
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse, reason: 'paused for the ding');
      await advance(g, .2);
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await advance(g, 1.3);
      ding.otherMusic = false;
      ding.push(const AudioWatchState(players: ['1:0']), notify: false);
      final t = await until(g, () => g.sound.musicPlaying);
      expect(t, lessThanOrEqualTo(1));
      await advance(g, 3);
      expect(g.sound.ownMusicSkipped, isFalse);
      expect(g.sound.musicPlaying, isTrue);
      expect(g.sound.musicLog.events, isNot(contains('skip')));
    },
  );

  final lingering = FakeAudioFocus();
  tester(lingering).testGameWidget(
    '§13.5 a finished player that stays listed: the interruption clears '
    'within 0.5 s',
    setUp: boot,
    verify: (g, _) async {
      lingering.interrupt(true);
      await flushAndMount(g);
      expect(g.sound.interrupted, isTrue);
      expect(g.sound.musicPlaying, isFalse);
      // The alarm stopped but its player is still listed: no callback.
      lingering.push(const AudioWatchState(players: ['4:0']), notify: false);
      final t = await until(g, () => !g.sound.interrupted);
      expect(g.sound.interrupted, isFalse);
      expect(t, lessThanOrEqualTo(.5 + 1e-6));
      expect(g.sound.musicPlaying, isTrue);
    },
  );

  final unknown = FakeAudioFocus();
  tester(unknown).testGameWidget(
    '§13.4 a listed notification player whose state the platform cannot '
    'give stops holding the music after 5 s',
    setUp: boot,
    verify: (g, _) async {
      unknown.push(
        const AudioWatchState(
          notification: true,
          stateKnown: false,
          players: ['5:?'],
        ),
      );
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse);
      await advance(g, Config.musicUnknownNotificationMaxHold + .6);
      expect(g.sound.musicPlaying, isTrue);
    },
  );

  // --------------------------------------------------------------- the log

  final panel = FakeAudioFocus();
  tester(panel).testGameWidget(
    '§13.3 the debug panel shows the music log (MUSIC LOG page)',
    setUp: boot,
    verify: (g, _) async {
      g.sound.suspend();
      g.openDebugPanel();
      await flushAndMount(g);
      final p = g.debugPanel!;
      final open = p.actions.indexWhere((a) => a.label() == 'MUSIC LOG >');
      expect(open, greaterThanOrEqualTo(0));
      await p.press(open);
      final labels = [for (final a in p.actions) a.label()];
      expect(labels.first, startsWith('pause susp=1'), reason: 'newest first');
      expect(labels, contains(startsWith('suspend susp=1')));
      expect(labels, contains(startsWith('start ')));
      expect(labels.last, '< Back');
      await p.press(p.actions.length - 1);
      expect(p.actions.any((a) => a.label() == 'MUSIC LOG >'), isTrue);
    },
  );

  group('§13.3 the music diagnostic log', () {
    test('a ring buffer of the last 50 entries, each line to the sink', () {
      final log = MusicLog();
      final lines = <String>[];
      log.sink = lines.add;
      for (var i = 0; i < 60; i++) {
        log.add(
          MusicLogEntry(
            time: DateTime(2026, 10, 13, 3, 4, 5, 6),
            event: 'e$i',
            flags: 'susp=0',
            watch: '[5:1] music=0',
            player: 'playing',
          ),
        );
      }
      expect(log.entries, hasLength(Config.musicLogSize));
      expect(log.events.first, 'e10');
      expect(lines, hasLength(60));
      expect(
        lines.last,
        '03:04:05.006 e59 | susp=0 | watch [5:1] music=0 | player playing',
      );
    });

    test('every music transition and hold change is logged with the hold '
        'flags, the AudioWatch answer and the player state', () async {
      final sound = SoundService(enabled: false)
        ..musicWatchLine = (() => '[5:1] music=1')
        ..musicStateProbe = (() => 'playing');
      await sound.startMusic();
      sound
        ..suspend()
        ..resume()
        ..setInterrupted(true)
        ..setInterrupted(false)
        ..setOtherSound(true)
        ..setOtherSound(false)
        ..setOtherMusicActive(true)
        ..setOtherMusicActive(false, sceneChange: true)
        ..setBackground(true)
        ..setBackground(false);
      expect(sound.musicLog.events, [
        'start',
        'suspend',
        'pause',
        'resume-ad',
        'resume',
        'interrupt',
        'pause',
        'interrupt-end',
        'resume',
        'notify',
        'pause',
        'notify-end',
        'resume',
        'skip',
        'pause',
        'unskip',
        'resume',
        'background',
        'pause',
        'foreground',
        'resume',
      ]);
      final line = sound.musicLog.entries[1].line;
      expect(line, contains('suspend | susp=1 int=0 own=0 bg=0 notif=0'));
      expect(line, contains('watch [5:1] music=1'));
      expect(line, contains('player playing'));
    });

    test('AudioWatchState reads the platform map (and a 2.2 bool)', () {
      final s = AudioWatchState.fromPlatform({
        'interrupted': false,
        'notification': true,
        'media': false,
        'musicActive': true,
        'stateKnown': false,
        'players': ['5:1', '14:?'],
      });
      expect(s.notification, isTrue);
      expect(s.musicActive, isTrue);
      expect(s.stateKnown, isFalse);
      expect(s.logLine, '[5:1,14:?] music=1 known=0');
      expect(AudioWatchState.fromPlatform(true).interrupted, isTrue);
    });
  });
}
