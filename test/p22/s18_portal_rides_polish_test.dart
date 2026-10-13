import 'dart:ui';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/items/sound_preload.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/rides/themes/themes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_audio.dart';

/// PRD-2.2 §18 portal rides polish: the score circle and the banners in
/// the scene (50 %, the scene's colours, between backdrop and objects), the
/// way-back crossfade without disappearing, the automatic flap at control
/// return, the first ring 2 s after control returns, and the preloaded
/// ride sounds.
PortalRideFeature _feature(RunController r) =>
    r.features.whereType<PortalRideFeature>().single;

FlameTester<FlappySpikesGame> _tester(double h) => FlameTester<FlappySpikesGame>(
  () => createRunTestGame(worldHeight: h, seed: 5),
  gameSize: Vector2(320, h),
);

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// The approved table (PRD-2.2 §18.1).
const Map<RideId, (Color, Color)> _table = {
  RideId.cannon: (Color(0xFF7C4DFF), Color(0xFF3B2A8A)),
  RideId.space: (Color(0xFF6E5BD6), Color(0xFF1F1252)),
  RideId.volcano: (Color(0xFFC2410C), Color(0xFF2A140D)),
  RideId.sea: (Color(0xFF7FC8EE), Color(0xFF0B3A6B)),
  RideId.pinball: (Color(0xFF7C4DFF), Color(0xFF141640)),
  RideId.storm: (Color(0xFF8C97AB), Color(0xFF252C3A)),
};

/// Flies with the bot to the forced portal (until the ride starts).
Future<PortalRide> _toRide(FlappySpikesGame game, RunController run) async {
  final bot = Autopilot(run);
  final f = _feature(run);
  for (var i = 0; i < 60 * 60 && f.ride == null; i++) {
    if (bot.shouldFlap()) game.onScreenTap();
    game.update(1 / 60);
    if (i % 10 == 0) await flushAndMount(game);
  }
  expect(f.ride, isNotNull, reason: 'the bot reaches the portal');
  return f.ride!;
}

void main() {
  group('§18 rules (pure)', () {
    test('§18.1 the circle / digit colours per scene, 50 %', () {
      expect(PortalConfig.sceneCircleOpacity, .5);
      for (final e in _table.entries) {
        final t = rideThemeFor(e.key);
        expect(t.circleColor, e.value.$1, reason: '${e.key}');
        expect(t.circleDigits, e.value.$2, reason: '${e.key}');
      }
    });

    test('§18.5 layer order: backdrop < circle < banner < objects < hoop '
        'backs < bird; over the wash on the way back', () {
      expect(PortalConfig.backdropPriority, lessThan(RunLayer.scoreCircle));
      expect(PortalConfig.sceneBannerPriority, greaterThan(RunLayer.scoreCircle));
      expect(PortalConfig.worldPriority,
          greaterThan(PortalConfig.sceneBannerPriority));
      expect(PortalConfig.worldPriority, lessThan(RunLayer.guides));
      expect(PortalConfig.circleOverWashPriority,
          greaterThan(PortalConfig.worldPriority));
      expect(PortalConfig.bannerOverWashPriority,
          greaterThan(PortalConfig.circleOverWashPriority));
      expect(PortalConfig.bannerOverWashPriority, lessThan(RunLayer.hoopBack));
      expect(RunLayer.hoopBack, lessThan(RunLayer.bird));
    });

    test('§18.3 the first ring 2 s after control returns', () {
      expect(PortalConfig.firstRingAfterControl, 2.0);
      // 3.1 s of glide + settle and 2 s at cruise. PRD-2.3 §14.4: the
      // cruise follows the hoop index (hoop 60 here).
      expect(
        PortalRide.cruiseDistance(60, 5.1),
        closeTo(RunConfig.cruise(60) * 5.1, .5),
      );
    });

    test('§18.4 a portal preloads pu_portal, pu_land, flap and all its '
        'theme cues (the cannon\'s aim / shot too)', () {
      for (final id in RideId.values) {
        final t = rideThemeFor(id);
        final cues = SoundPreloadFeature.portalCues(t);
        expect(cues, containsAll([Sfx.puPortal, Sfx.puLand, Sfx.flap]));
        expect(cues, containsAll(t.sounds.values));
      }
      expect(
        SoundPreloadFeature.portalCues(rideThemeFor(RideId.cannon)),
        containsAll([Sfx.puCannonAim, Sfx.puCannonShot]),
      );
    });
  });

  group('§18 portal rides in a run', () {
    for (final h in [568.0, 711.0]) {
      for (final id in RideId.values) {
        _tester(h).testGameWidget(
          '§18 ${id.name} at $h pt: circle + banner in the scene at 50 % in '
          'the theme colours, never gone on the way back, normal at glide '
          'start; one flap at control return; first ring 2 s later',
          setUp: _setUp,
          verify: (game, _) async {
            final run = await startRun(game, startHoopIndex: 25, ride: id);
            final ride = await _toRide(game, run);
            final hud = game.scoreHud;
            final banners = game.runHud!.banners;
            final theme = rideThemeFor(id);
            expect(banners.drawnByScene, isTrue);
            // Ride start: the normal circle fades out as the scene fades in.
            var minVisible = 1.0;
            var sawFull = false;
            final samples = <String, double>{};
            RidePhase? last;
            var flyStartVisible = -1.0;
            double? controlAt;
            var t = 0.0;
            final sfx = sfxLog(game);
            final bird = game.runBird!;
            for (var i = 0; i < 60 * 30 && !ride.done; i++) {
              sfx.clear();
              final textsBefore = _texts(game);
              game.update(1 / 60);
              t += 1 / 60;
              if (i % 15 == 0) await flushAndMount(game);
              if (ride.done) {
                controlAt = t;
                // §18.2 one normal flap, no text.
                expect(bird.inRide, isFalse);
                expect(game.runBirdVelocityY,
                    closeTo(-Config.flapVelocity, 1e-6));
                expect(sfx.where((e) => e == Sfx.flap.name).length, 1);
                expect(_texts(game), textsBefore);
                break;
              }
              final v = hud.visibleOpacity;
              if (v < minVisible) minVisible = v;
              final ph = ride.phase;
              if (ph == RidePhase.ride || ph == RidePhase.exit) {
                expect(hud.priority, RunLayer.scoreCircle);
                expect(ride.bannerLayer!.priority,
                    PortalConfig.sceneBannerPriority);
                expect(ride.backdropLayer!.priority,
                    lessThan(hud.priority));
                expect(ride.objectsLayer!.priority,
                    greaterThan(ride.bannerLayer!.priority));
              } else {
                expect(hud.priority, PortalConfig.circleOverWashPriority);
                expect(ride.bannerLayer!.priority,
                    PortalConfig.bannerOverWashPriority);
              }
              if (ph == RidePhase.ride && hud.sceneMix >= 1) {
                sawFull = true;
                expect(hud.sceneCircleColor, theme.circleColor);
                expect(hud.sceneDigitColor, theme.circleDigits);
                expect(hud.sceneAlpha, .5);
                expect(ride.bannerOpacity, closeTo(.5, 1e-9));
              }
              if (ph != last) {
                if (ph == RidePhase.fly) flyStartVisible = v;
                if (ph == RidePhase.glide) {
                  samples['glide start'] = v;
                  expect(hud.sceneMix, 0);
                }
                last = ph;
              }
              if (ph == RidePhase.fly) {
                final ft = ride.view.ft;
                if ((ft - .85).abs() < 1 / 120) samples['fly mid'] = v;
                if (ft > PortalConfig.flyTime - .1) samples['fly end'] = v;
              }
            }
            expect(controlAt, isNotNull, reason: 'the ride ended');
            expect(sawFull, isTrue);
            expect(minVisible, greaterThanOrEqualTo(.5 - 1e-9));
            expect(flyStartVisible, greaterThanOrEqualTo(.5 - 1e-9));
            for (final e in samples.entries) {
              expect(e.value, greaterThanOrEqualTo(.5 - 1e-9), reason: e.key);
            }
            expect(samples['glide start'], closeTo(1, 1e-9));
            // After the ride: the one circle is back to normal.
            expect(hud.sceneMix, 0);
            expect(hud.priority, RunLayer.scoreCircle);
            expect(banners.drawnByScene, isFalse);
            // §18.3 the first ring's plane reaches the bird 2.0 s after
            // control returns; the second follows the spacing.
            // (The slot planned during the glide is still a ride slot: full
            // size, plain.)
            final plans = run.spawner.slotLog
                .where((p) => p.kind != HoopKindId.portal)
                .toList();
            final firstIndex = plans.indexWhere(
              (p) => p.trackX > run.state.camX + RunConfig.birdX,
            );
            expect(firstIndex, greaterThanOrEqualTo(0));
            final first = plans[firstIndex];
            var tc = 0.0;
            final bot = Autopilot(run);
            for (var i = 0; i < 60 * 4; i++) {
              if (run.state.camX + RunConfig.birdX >= first.trackX) break;
              if (bot.shouldFlap()) game.onScreenTap();
              game.update(1 / 60);
              tc += 1 / 60;
            }
            expect(tc, closeTo(2.0, .1));
            if (plans.length > firstIndex + 1) {
              expect(
                plans[firstIndex + 1].trackX - first.trackX,
                closeTo(run.director.spacing, 1e-6),
              );
            } else {
              await flushAndMount(game);
              game.update(1 / 60);
              // PRD-2.3 §14.4 the faster cruise plans further ahead in the
              // 2 s: take the slot right after the first one.
              final next = run.spawner.slotLog.firstWhere(
                (p) => p.index == first.index + 1,
              );
              expect(next.trackX - first.trackX,
                  closeTo(run.director.spacing, 1e-6));
            }
          },
        );
      }
    }

    _tester(711).testGameWidget(
      '§18.1 a banner during the ride is handed to the scene layer at 50 %',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.sea);
        final ride = await _toRide(game, run);
        for (var i = 0; i < 120; i++) {
          game.update(1 / 60);
        }
        final host = game.runHud!.banners;
        host.show(ElementBanner('TEST'));
        await flushAndMount(game);
        expect(host.drawnByScene, isTrue);
        expect(ride.bannerOpacity, closeTo(.5, 1e-9));
        expect(host.current, isNotNull);
        expect(ride.bannerLayer!.isMounted, isTrue);
      },
    );
  });

  group('§18.4 ride sounds always play (fake pools)', () {
    setUpAll(() {
      // Ride loops also use audioplayers; keep the whole audio backend fake.
      AudioplayersPlatformInterface.instance = FakeAudioPlatform();
      GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioPlatform();
      FlameAudio.audioCache = FakeAudioCache();
    });
    for (final id in [RideId.cannon, RideId.storm, RideId.sea]) {
      _tester(711).testGameWidget(
        '§18.4 ${id.name}: the portal spawn requests every cue\'s pool; each '
        'first play in the ride then plays',
        setUp: _setUp,
        verify: (game, tester) async {
          await tester.runAsync(() async {
            final audio = FakeAudio();
            final sound = game.sound
              ..enabled = true
              ..muted = false
              ..voiceFactory = audio.create;
            final played = <Sfx>[];
            sound.onPlay = played.add;
            final run = await startRun(game, startHoopIndex: 25, ride: id);
            final pre = run.features.whereType<SoundPreloadFeature>().single;
            final bot = Autopilot(run);
            final cues = SoundPreloadFeature.portalCues(rideThemeFor(id));
            bool spawned() =>
                run.spawner.hoops.any((h) => h.plan.kind == HoopKindId.portal);
            for (var i = 0; i < 60 * 60 && !spawned(); i++) {
              if (bot.shouldFlap()) game.onScreenTap();
              game.update(1 / 60);
            }
            expect(spawned(), isTrue);
            expect(pre.requests.any((r) => r.containsAll(cues)), isTrue);
            await flushAudio();
            for (final cue in cues) {
              expect(sound.poolRequested(cue), isTrue, reason: '$cue');
              expect(sound.poolOf(cue), isNotNull, reason: '$cue');
            }
            // Fly the ride; every cue played in it starts a voice.
            final f = _feature(run);
            var seen = false;
            played.clear();
            for (var i = 0; i < 60 * 40; i++) {
              if (f.ride != null) seen = true;
              if (seen && f.ride == null) break;
              if (!seen && bot.shouldFlap()) game.onScreenTap();
              game.update(1 / 60);
              if (i % 5 == 0) await flushAudio();
            }
            await flushAudio();
            expect(seen, isTrue);
            final ridePlayed = played.where(cues.contains).toSet();
            expect(ridePlayed, containsAll([Sfx.puPortal, Sfx.puLand]));
            for (final cue in ridePlayed) {
              final file = SoundService.audioFiles[cue]!;
              final starts = audio
                  .of(file)
                  .fold<int>(0, (n, v) => n + v.starts);
              expect(starts, greaterThan(0), reason: '$cue was dropped');
            }
            await sound.dispose();
            sound
              ..enabled = false
              ..voiceFactory = null;
          });
        },
      );
    }
  });
}

/// Text-like components in the world and the viewport (the auto flap adds
/// none).
int _texts(FlappySpikesGame g) =>
    g.world.descendants().whereType<TextComponent>().length +
    g.camera.viewport.descendants().whereType<TextComponent>().length;
