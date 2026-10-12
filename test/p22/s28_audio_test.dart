import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flappy_spikes/run/config/egg_config.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A rewarded ad the test holds open (displayed at once).
class _HeldRewardedAds extends FakeRewardedAds {
  Completer<void>? hold;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async {
    if (mode == FakeAdMode.unavailable) return AdResult.unavailable;
    shown++;
    placements.add(placement);
    if (mode == FakeAdMode.fail) return AdResult.failed;
    onShown?.call();
    await hold?.future;
    return AdResult.completed;
  }
}

/// PRD-2.2 §28 game audio around ads, death and other apps.
void main() {
  // ------------------------------------------------------------ the service
  group('§28 SoundService', () {
    late SoundService sound;
    late List<Sfx> audible;
    late List<String> music;

    setUp(() {
      sound = SoundService(enabled: false);
      audible = [];
      music = [];
      sound
        ..onAudible = audible.add
        ..onMusic = music.add;
    });

    test('§28.2 suspend: plays dropped (never queued), loops stopped, music '
        'paused; resume: music resumes (same track, not restarted), nothing '
        'dropped plays late', () async {
      await sound.startMusic();
      expect(music, ['start']);
      final loop = sound.loop(SfxLoop.cometLoop);
      sound.play(Sfx.flap);
      expect(audible, [Sfx.flap]);
      sound.suspend();
      expect(sound.suspended, isTrue);
      expect(loop.stopped, isTrue);
      expect(sound.activeLoops, isEmpty);
      expect(music, ['start', 'pause']);
      expect(sound.musicPlaying, isFalse);
      sound.play(Sfx.eggPeep);
      sound.play(Sfx.point);
      expect(audible, [Sfx.flap]);
      expect(sound.droppedPlays, 2);
      // A loop asked for under the ad never starts (the feature retries).
      expect(sound.loop(SfxLoop.feverLoop).stopped, isTrue);
      sound.resume();
      expect(sound.suspended, isFalse);
      expect(music, ['start', 'pause', 'resume']);
      expect(sound.musicPlaying, isTrue);
      expect(audible, [Sfx.flap], reason: 'no dropped sound plays late');
      expect(loop.stopped, isTrue, reason: 'interrupted loops stay off');
      sound.play(Sfx.click);
      expect(audible.last, Sfx.click);
    });

    test('§28.2 reference-counted; clearSuspend drops a stale suspend', () {
      sound
        ..suspend()
        ..suspend()
        ..resume();
      expect(sound.suspended, isTrue);
      sound.resume();
      expect(sound.suspended, isFalse);
      sound.resume(); // never below zero
      sound.suspend();
      sound.clearSuspend();
      expect(sound.suspended, isFalse);
    });

    test('§28.3 a transient interruption pauses the music and mutes SFX '
        '(loops quiet, not stopped); its end resumes the music', () async {
      await sound.startMusic();
      final loop = sound.loop(SfxLoop.sqHold);
      sound.setInterrupted(true);
      expect(music, ['start', 'pause']);
      sound.play(Sfx.flap);
      expect(audible, isEmpty);
      expect(loop.stopped, isFalse);
      sound.setInterrupted(false);
      expect(music, ['start', 'pause', 'resume']);
      sound.play(Sfx.flap);
      expect(audible, [Sfx.flap]);
    });

    test('§28.3 own music at launch: the game music never starts, SFX play; '
        'only a scene change with the other music gone starts it', () async {
      sound.setOtherMusicActive(true);
      await sound.startMusic();
      expect(music, isEmpty);
      expect(sound.ownMusicSkipped, isTrue);
      sound.play(Sfx.flap);
      expect(audible, [Sfx.flap]);
      sound.setOtherMusicActive(false); // e.g. a foreground check
      expect(music, isEmpty, reason: 'never mid-run');
      sound.setOtherMusicActive(false, sceneChange: true);
      expect(music, ['start']);
      // Coming back to it later: paused, then resumed from where it was.
      sound.setOtherMusicActive(true);
      sound.setOtherMusicActive(false, sceneChange: true);
      expect(music, ['start', 'pause', 'resume']);
    });

    test('§28.3 the background pauses the music; the music volume setting is '
        'unchanged by any of it', () async {
      await sound.setMusicVolume(.4);
      await sound.startMusic();
      sound
        ..setBackground(true)
        ..setOtherMusicActive(true)
        ..suspend()
        ..setInterrupted(true);
      expect(music, ['start', 'pause']);
      sound
        ..setBackground(false)
        ..resume()
        ..setInterrupted(false);
      expect(music, ['start', 'pause'], reason: 'own music still playing');
      expect(sound.musicVolume, .4);
    });

    test('§28.3 the game audio context mixes with others (no focus request) '
        'and is tagged USAGE_GAME', () {
      final c = SoundService.gameAudioContext();
      expect(c.android.audioFocus.name, 'none');
      expect(c.android.usageType.name, 'game');
    });
  });

  // ------------------------------------------------------------ in game
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    Monetization? monetization,
    AudioFocus? focus,
    DateTime Function()? clock,
    int seed = 7,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      final g = createRunTestGame(
        prefs: prefs,
        services: spy,
        worldHeight: 711,
        monetization: monetization,
        clock: clock,
        seed: seed,
      );
      if (focus != null) g.audioFocus = focus;
      return g;
    },
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  List<Sfx> audibleLog(FlappySpikesGame g) {
    final log = <Sfx>[];
    g.sound.onAudible = log.add;
    return log;
  }

  List<String> musicLog(FlappySpikesGame g) {
    final log = <String>[];
    g.sound.onMusic = log.add;
    return log;
  }

  void hatchChick(RunController run) {
    run.events.emit(PickupCollected(ElementId.egg, null));
    for (var i = 0; i < EggConfig.rings; i++) {
      run.events.emit(HoopPassed(null, perfect: true));
    }
    expect(run.state.egg!.stage, EggStage.chick);
  }

  tester().testGameWidget(
    '§28.1 control: the flying chick peeps while the run is live',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      g.runDebug.god = true;
      hatchChick(run);
      final log = audibleLog(g);
      await stepSeconds(g, EggConfig.peepEvery * 2 + .2);
      expect(log, contains(Sfx.eggPeep));
    },
  );

  // Every death path through the one mistake pipeline (ARCH §2.6): the
  // missed hoop, the spike strips (also the squeeze walls), a closed switch,
  // a missed pair.
  for (final cause in [
    MistakeCause.missedHoop,
    MistakeCause.spikes,
    MistakeCause.closedSwitch,
    MistakeCause.pairMissed,
  ]) {
    tester().testGameWidget(
      '§28.1 death (${cause.analyticsName}) with the chick: RunDied, the '
      'chick is gone, every loop stops, no egg_peep afterwards',
      setUp: boot,
      verify: (g, _) async {
        final run = await startRun(g);
        hatchChick(run);
        final died = <RunDied>[];
        run.events.on<RunDied>(died.add);
        final loop = g.sound.loop(SfxLoop.feverLoop);
        final stops = g.sound.stopAllLoopsCalls;
        final log = audibleLog(g);
        run.state.invulnerable = 0;
        run.state.shield = false;
        run.mistake(Mistake(cause));
        expect(died, hasLength(1));
        expect(run.state.egg, isNull);
        expect(loop.stopped, isTrue);
        expect(g.sound.stopAllLoopsCalls, greaterThan(stops));
        await stepSeconds(g, 4);
        expect(log, isNot(contains(Sfx.eggPeep)));
      },
    );
  }

  for (final design in SawDesign.values) {
    tester(seed: 9).testGameWidget(
      '§28.1 themed death (${design.name}) with the chick: no egg_peep and '
      'no saw hum afterwards',
      setUp: boot,
      verify: (g, _) async {
        final run = await startRun(
          g,
          startHoopIndex: 20,
          force: [ElementId.saw],
        );
        final h = await flyToHoop(
          g,
          HoopKindId.saw,
          ElementId.saw,
          where: (h) => SawHoopKind.designOf(h) == design,
        );
        expect(h, isNotNull);
        hatchChick(run);
        final died = <RunDied>[];
        run.events.on<RunDied>(died.add);
        final ry = h!.opening / 2 + h.kind.rimRadius(h);
        await glideInto(
          g,
          h,
          h.position.y + ry,
          seconds: .2,
          until: (r) => r.dying,
        );
        expect(died.single.mistake.themed, isNotNull);
        expect(run.state.egg, isNull);
        expect(g.sound.activeLoops, isEmpty);
        final log = audibleLog(g);
        final loops = <SfxLoop>[];
        g.sound.onLoop = (l, _) => loops.add(l);
        await stepSeconds(g, 4);
        expect(log, isNot(contains(Sfx.eggPeep)));
        expect(loops, isEmpty, reason: 'no loop restarts after the death');
      },
    );
  }

  tester().testGameWidget(
    '§28.1 the revive page keeps its own sounds (locked shake) after a death '
    'with the chick',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      hatchChick(run);
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      run.state.invulnerable = 0;
      run.state.shield = false;
      // The ad step used: a coin offer the wallet cannot pay.
      run.state.adStepAvailableThisGame = false;
      killRunThroughSaves(g);
      for (var i = 0; i < 600 && g.state == GameState.dying; i++) {
        g.update(1 / 60);
      }
      await flushAndMount(g);
      final screen = g.reviveScreen!;
      await g.menu.wallet.spend(g.menu.wallet.balance, 'test');
      for (var i = 0; i < 30; i++) {
        g.update(1 / 60);
      }
      final log = audibleLog(g);
      screen.tapHeart();
      expect(log, [Sfx.rvLocked]);
      await stepSeconds(g, 3);
      expect(log, isNot(contains(Sfx.eggPeep)));
    },
  );

  final held = _HeldRewardedAds();
  tester(monetization: Monetization(ads: held)).testGameWidget(
    '§28.2 rewarded ad (revive): suspended while displayed (plays dropped, '
    'loops stopped, music paused, the chick silent); resumed after',
    setUp: boot,
    verify: (g, _) async {
      final music = musicLog(g);
      final run = await startRun(g);
      g.runDebug.god = true;
      hatchChick(run);
      final loop = g.sound.loop(SfxLoop.cometLoop);
      final log = audibleLog(g);
      held.hold = Completer<void>();
      final ad = g.showRewardedAd(AdPlacement.revive);
      await flushAndMount(g);
      expect(g.sound.suspended, isTrue);
      expect(loop.stopped, isTrue);
      expect(music.last, 'pause');
      g.sound.play(Sfx.flap);
      await stepSeconds(g, EggConfig.peepEvery * 3);
      expect(log, isEmpty, reason: 'nothing audible under the ad');
      held.hold!.complete();
      expect(await ad, AdResult.completed);
      expect(g.sound.suspended, isFalse);
      expect(music.last, 'resume');
      expect(music.where((m) => m == 'start'), isEmpty);
      expect(log, isEmpty, reason: 'no dropped sound plays late');
    },
  );

  tester(
    monetization: Monetization(ads: FakeRewardedAds()..mode = FakeAdMode.fail),
  ).testGameWidget(
    '§28.2 an ad that fails to show leaves the audio running',
    setUp: boot,
    verify: (g, _) async {
      final music = musicLog(g);
      expect(await g.showRewardedAd(AdPlacement.revive), AdResult.failed);
      expect(g.sound.suspended, isFalse);
      expect(music, isNot(contains('pause')));
    },
  );

  var now = DateTime(2026, 10, 12, 12);
  final interstitial = FakeInterstitialAds(mode: FakeAdMode.succeed);
  tester(
    prefs: {'gamesPlayed': 5},
    clock: () => now,
    monetization: Monetization(interstitial: interstitial),
  ).testGameWidget(
    '§28.2 interstitial: suspended while it shows, resumed (music from where '
    'it was) when it closes',
    setUp: boot,
    verify: (g, _) async {
      final music = musicLog(g);
      await startRun(g);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      stepGame(g, 1);
      expect(g.state, GameState.results);
      final done = Completer<void>();
      interstitial.hold = done.future;
      g.goHome();
      await flushAndMount(g);
      expect(interstitial.shown, 1);
      expect(g.sound.suspended, isTrue);
      expect(music.last, 'pause');
      final log = audibleLog(g);
      g.sound.play(Sfx.click);
      expect(log, isEmpty);
      done.complete();
      await flushAndMount(g);
      expect(g.sound.suspended, isFalse);
      expect(music.last, 'resume');
    },
  );

  tester(
    monetization: Monetization()..showFakeAdOverlay = true,
  ).testGameWidget(
    '§28.2 the desktop fake ad overlay suspends on mount, resumes on close',
    setUp: boot,
    verify: (g, _) async {
      final ad = g.showRewardedAd(AdPlacement.homeSlot);
      await flushAndMount(g);
      expect(g.fakeAdOverlay, isNotNull);
      expect(g.sound.suspended, isTrue);
      g.fakeAdOverlay!.close();
      await ad;
      expect(g.sound.suspended, isFalse);
    },
  );

  tester().testGameWidget(
    '§28.2 safety: a suspend without its resume is cleared on app resume '
    'and on a scene change',
    setUp: boot,
    verify: (g, _) async {
      g.sound.suspend();
      g.lifecycleStateChange(AppLifecycleState.paused);
      expect(g.sound.suspended, isTrue);
      g.lifecycleStateChange(AppLifecycleState.resumed);
      expect(g.sound.suspended, isFalse);
      g.sound.suspend();
      await startRun(g);
      expect(g.sound.suspended, isFalse);
    },
  );

  final focus = FakeAudioFocus();
  tester(focus: focus).testGameWidget(
    '§28.3 a focus-loss event (call / alarm) pauses the music and mutes the '
    'SFX; its end resumes the music',
    setUp: boot,
    verify: (g, _) async {
      final music = musicLog(g);
      final log = audibleLog(g);
      focus.interrupt(true);
      await flushAndMount(g);
      expect(g.sound.interrupted, isTrue);
      expect(music, ['pause']);
      g.sound.play(Sfx.click);
      expect(log, isEmpty);
      focus.interrupt(false);
      await flushAndMount(g);
      expect(music, ['pause', 'resume']);
      g.sound.play(Sfx.click);
      expect(log, [Sfx.click]);
    },
  );

  final ownMusic = FakeAudioFocus()..otherMusic = true;
  tester(focus: ownMusic).testGameWidget(
    '§28.3 own music at launch: the game music does not start, SFX play; it '
    'starts at the next scene change after the other music stopped',
    setUp: boot,
    verify: (g, _) async {
      await flushAndMount(g);
      expect(g.sound.ownMusicSkipped, isTrue);
      expect(g.sound.musicPlaying, isFalse);
      final log = audibleLog(g);
      g.sound.play(Sfx.click);
      expect(log, [Sfx.click]);
      // Still playing at the run start: stays off.
      await startRun(g);
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse);
      // The other music stops: not mid-run …
      ownMusic.otherMusic = false;
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse);
      // … but at the next scene change (Home arrival).
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      stepGame(g, 1);
      expect(g.state, GameState.results);
      g.goHome();
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isTrue);
      // Back to the foreground with someone else's music on: off again.
      ownMusic.otherMusic = true;
      g.lifecycleStateChange(AppLifecycleState.paused);
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await flushAndMount(g);
      expect(g.sound.musicPlaying, isFalse);
    },
  );
}
