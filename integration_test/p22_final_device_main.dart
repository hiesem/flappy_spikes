// QA-only Pixel harness: native renderer/audio/test ads; isolated game prefs,
// no accounts, store purchases, cloud writes or reminders. Host setup commands
// live in code_cache/qa_command.json. Actual taps/swipes go through adb input.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame/game.dart';
import 'package:flappy_spikes/components/banner_slot.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/audio_counter.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/main.dart' show SystemBackObserver;
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void log(String s) => debugPrint('QADEV $s');
final watch = Stopwatch()..start();

class _QaAudio extends CountingAudioPlatform {
  _QaAudio(super.inner);
  final sources = <String, String>{};
  final started = <String, int>{};

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) {
    sources[playerId] = url.split('/').last;
    return super.setSourceUrl(
      playerId,
      url,
      isLocal: isLocal,
      mimeType: mimeType,
    );
  }

  @override
  Future<void> resume(String playerId) {
    started[playerId] = watch.elapsedMilliseconds;
    log('native-start ${sources[playerId]} $playerId');
    return super.resume(playerId);
  }

  @override
  Future<void> stop(String playerId) {
    final at = started.remove(playerId);
    if (at != null) {
      log(
        'native-stop ${sources[playerId]} ms=${watch.elapsedMilliseconds - at}',
      );
    }
    return super.stop(playerId);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same fresh-default preference path as release_e2e; never clears data.
  SharedPreferences.setMockInitialValues({
    'firstSessionDone': true,
    'bestScore': 0,
    'coins': 0,
    'gamesPlayed': 10,
    'metElements': ElementId.values.map((e) => e.storageId).toList(),
  });
  final audio = _QaAudio(AudioplayersPlatformInterface.instance);
  AudioplayersPlatformInterface.instance = audio;
  CountingAudioPlatform.installed = audio;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  // Google TEST units only. Scripted consent avoids changing the owner's UMP
  // choice; this harness does not certify the consent form or live mediation.
  await MobileAds.instance.initialize();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final consent = FakeAdsConsent();
  final monetization = Monetization(
    consent: consent,
    ads: AdMobRewardedAds(consent: consent),
    interstitial: AdMobInterstitialAds(consent: consent),
    banner: AdMobBannerAds(
      consent: consent,
      widthDp: view.physicalSize.width / view.devicePixelRatio,
    ),
    iap: FakeIapService(),
  );
  final game = FlappySpikesGame(
    worldHeight: 320 * view.physicalSize.height / view.physicalSize.width,
    monetization: monetization,
  )..audioFocus = PlatformAudioFocus();
  SystemBackObserver(game).install();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RepaintBoundary(child: GameWidget(game: game)),
          ),
          BannerSlot(game: game),
        ],
      ),
    ),
  );
  await game.loaded;
  game.idleFrames
    ..enabled = true
    ..attach();
  game.sound.onMusic = (s) => log('music $s');
  game.sound.onPlay = (s) => log('cue ${s.name}');
  game.sound.debugOnStop = (f, ms) => log('sfx-stop $f $ms');
  await monetization.initialize();
  log(
    'ready screen=${game.screenHeight} volume=${game.storage.musicVolume} '
    'applied=${game.sound.musicVolume} bannerDp=${monetization.banner.heightDp}',
  );

  var seq = -1;
  var busy = false;
  RunController? attached;
  String? previousRide;
  String? previousState;
  double? returnedAt;
  var waitingForRing = false;
  final input = File('${Directory.systemTemp.path}/qa_command.json');
  final output = File('${Directory.systemTemp.path}/qa_state.json');
  Timer.periodic(const Duration(milliseconds: 100), (_) async {
    if (busy) return;
    busy = true;
    try {
      final run = game.run;
      if (run != null && run != attached) {
        attached = run;
        returnedAt = null;
        waitingForRing = false;
        run.events.onAny((e) {
          final wall = watch.elapsedMilliseconds / 1000;
          var extra = '';
          if (e is HoopPassed) {
            final h = e.hoop;
            extra =
                'kind=${h?.plan.kind.name} motion=${h?.plan.motion?.type.name} '
                'perfect=${e.perfect} rim=${e.rimTouched} offset=${h?.passOffset} '
                'ride=${e.duringRide} opening=${h?.opening}';
            if (waitingForRing && !e.duringRide) {
              log('first-ring-after-control delay=${wall - returnedAt!}');
              waitingForRing = false;
            }
          } else if (e is HoopSpawned) {
            extra =
                'kind=${e.plan.kind.name} motion=${e.plan.motion?.type.name} '
                'centre=${e.plan.centreY} opening=${e.plan.opening}';
          } else if (e is PickupCollected) {
            extra = 'element=${e.element.storageId}';
          } else if (e is RimTouched) {
            extra =
                'kind=${e.hoop.plan.kind.name} egg=${run.state.egg?.stage.name}';
          } else if (e is HoopMissed) {
            extra =
                'kind=${e.hoop.plan.kind.name} motion=${e.hoop.plan.motion?.type.name}';
          }
          log('event ${e.runtimeType} wall=$wall $extra');
        });
      }
      final ride = run?.state.ride;
      final rideState = ride == null
          ? null
          : '${ride.kind.name}/${ride.rideId?.name}/${ride.phase}';
      if (previousRide != rideState) {
        log(
          'ride $previousRide -> $rideState y=${game.runBirdPosition?.y} '
          'vy=${game.runBirdVelocityY} scale=${run?.state.timeScale}',
        );
        if (previousRide != null && rideState == null) {
          returnedAt = watch.elapsedMilliseconds / 1000;
          waitingForRing = previousRide!.startsWith('portal');
        }
        previousRide = rideState;
      }
      final stateKey =
          '${game.state.name}/${game.menuScene.name}'
          '/${game.modalPopupOpen}/${game.sound.suspended}';
      if (previousState != stateKey) {
        log('state $stateKey');
        previousState = stateKey;
      }
      if (await input.exists()) {
        final c =
            jsonDecode(await input.readAsString()) as Map<String, dynamic>;
        if (c['seq'] != seq) {
          seq = c['seq'] as int;
          log('command $seq ${c['op']} $c');
          switch (c['op']) {
            case 'open':
              switch (c['screen']) {
                case 'settings':
                  game.openSettings();
                case 'delete_confirm':
                  game.openDeleteDataConfirm();
                case 'shop':
                  game.openShop();
                case 'skins':
                  game.openSkins();
                case 'levels':
                  game.openLevels();
                case 'debug':
                  game.openDebugPanel();
                case 'no_ads':
                  game.openNoAdsPopup(reason: 'forced');
                case 'level_up':
                  await game.storage.saveBestScore(0);
                  await game.storage.savePlayerLevel(0); // WP-L
                  await game.menu.levels.debugForceLevelUp();
                  game.openLevelUpPopup();
                case 'purchase_cancelled':
                  game.openPurchaseResultPopup(
                    IapProduct.coins1000,
                    PurchaseProblem.cancelled,
                    null,
                  );
                case 'purchase_failed':
                  game.openPurchaseResultPopup(
                    IapProduct.coins1000,
                    PurchaseProblem.failed,
                    null,
                  );
                case 'celebration':
                  game.openNoAdsCelebration();
                case 'run_settings':
                  game.openRunSettings();
              }
            case 'prepare':
              game.runSeed = (c['seed'] as int?) ?? 7;
              game.runDebug
                ..startHoopIndex = (c['index'] as int?) ?? 0
                ..bot = c['bot'] != false
                ..god = c['god'] != false;
              game.runDebug.force.clear();
              game.runDebug.forcedRide = null;
              if (c['ride'] != null) {
                game.debugForceRide(RideId.values.byName(c['ride']));
              }
              for (final f in (c['force'] as List?) ?? []) {
                final e = ElementId.values.firstWhere((e) => e.storageId == f);
                await ForceMenu.actions(game)
                    .firstWhere(
                      (a) => a.label().startsWith('Force: ${e.storageId}'),
                    )
                    .run();
              }
            case 'kill':
              game.runDebug.god = false;
              if (run != null) {
                run.state
                  ..invulnerable = 0
                  ..hearts = 0
                  ..shield = false
                  ..extraLife = false;
                game.onBirdHit(MistakeCause.spikes);
              }
            case 'passes':
              for (var i = 0; i < (c['count'] as int); i++) {
                run?.debugPass(perfect: c['perfect'] != false);
              }
            case 'pickup':
              final e = ElementId.values.firstWhere(
                (e) => e.storageId == c['element'],
              );
              run?.events.emit(PickupCollected(e, null));
            case 'rim':
              if (run != null && run.spawner.hoops.isNotEmpty) {
                final h = run.spawner.hoops.first;
                run.events.emit(
                  RimTouched(h, h.position.clone(), Vector2(1, 0)),
                );
              }
            case 'rim_setup':
              // Place an egg-carrying bird in a real rim overlap; the next
              // normal physics step must produce the contact (no event injected).
              final h = run?.spawner.nextHoopAhead();
              final b = game.runBird;
              if (h != null && b != null && run != null) {
                game.runDebug.bot = false;
                run.state.invulnerable = 0;
                final p =
                    run.geo.toScreen(h.frame().rimEnd(0, -1)) + Vector2(-14, 8);
                b.body.setTransform(p, 0);
                b.body.linearVelocity = Vector2.zero();
              }
            case 'position_y':
              final b = game.runBird;
              if (b != null) {
                b.body.setTransform(
                  Vector2(Config.birdX, (c['y'] as num).toDouble()),
                  0,
                );
                b.body.linearVelocity = Vector2.zero();
              }
            case 'engine':
              if (c['value'] == true) {
                game.resumeEngine();
              } else {
                game.pauseEngine();
              }
            case 'force':
              final id = c['element'] as String;
              await ForceMenu.actions(
                game,
              ).firstWhere((a) => a.label().startsWith('Force: $id')).run();
            case 'pieces':
              await game.storage.savePuzzlePieces(c['mask'] as int);
            case 'consent':
              consent.canRequest = c['value'] == true;
            case 'feathers':
              await game.storage.saveFeathers(c['count'] as int);
            case 'no_ads':
              await game.menu.setNoAds(c['value'] == true);
            case 'games':
              game.storage.gamesPlayed = c['count'] as int;
            case 'best':
              await game.storage.saveBestScore(c['score'] as int);
              // WP-L the stored level follows the forced best here.
              await game.storage.savePlayerLevel(levelFor(c['score'] as int));
            case 'score':
              if (run != null) {
                run.ctx.addScore((c['score'] as int) - run.state.score);
              }
            case 'stage':
              game.applyRunStage(c['stage'] as int);
            case 'pause':
              game.pause();
            case 'resume':
              game.resume();
            case 'bot':
              game.runDebug.bot = c['value'] == true;
            case 'music_skip':
              game.sound.setOtherMusicActive(true);
            case 'cue':
              final sfx = Sfx.values.byName(c['name']);
              game.sound.preload([sfx]);
              await Future<void>.delayed(const Duration(seconds: 2));
              game.sound.play(sfx);
            case 'home':
              game.goHome();
            case 'close':
              game.handleBack();
          }
        }
      }
      final s = game.run?.state;
      final rect = Config.homeStartRectFor(game.viewHeight);
      final modeRect = Config.homeModeRectFor(game.viewHeight);
      await output.writeAsString(
        jsonEncode({
          'seq': seq,
          'wall': watch.elapsedMilliseconds / 1000,
          'state': game.state.name,
          'menu': game.menuScene.name,
          'modal': game.modalPopupOpen,
          'mode': game.homeMode.name,
          'debug': game.debugPanel != null,
          'popup': game.levelUpPopup != null
              ? 'level_up'
              : game.noAdsPopup != null
              ? 'no_ads'
              : game.purchaseResultPopup != null
              ? 'purchase'
              : null,
          'volume': game.storage.musicVolume,
          'appliedVolume': game.sound.musicVolume,
          'music': game.sound.musicPlaying,
          'skipped': game.sound.ownMusicSkipped,
          'suspended': game.sound.suspended,
          'stats': game.sound.debugStats(),
          'height': game.viewHeight,
          'visible': game.visibleHeight,
          'screenHeight': game.screenHeight,
          'bottomInset': game.bottomStripInset,
          'banner': game.runHasBanner,
          'bannerLoaded': monetization.banner.loaded.value,
          'rewardedLoaded': monetization.ads.isAvailable,
          'interstitialLoaded': monetization.interstitial.isAvailable,
          'interstitial': game.interstitialShowing,
          'interstitialGuard': game.interstitialSkipReason()?.name,
          'rewardedWatched': game.rewardedWatchedThisRun,
          'lastAd': game.lastFullScreenAdClosedAt?.toIso8601String(),
          'score': s?.score,
          'hoops': s?.hoopsPassed,
          'rings': [
            for (final h in game.run?.spawner.hoops ?? const <Hoop>[])
              {
                'kind': h.plan.kind.name,
                'motion': h.plan.motion?.type.name,
                'x': h.frame().centre.x - (s?.camX ?? 0),
                'y': h.frame().centre.y - (s?.camY ?? 0),
                'opening': h.opening,
                'resolved': h.resolved,
                'touched': h.touched,
              },
          ],
          'streak': s?.streak,
          'fire': s?.onFire,
          'activity': s?.activity?.name,
          'ride': rideState,
          'timeScale': s?.timeScale,
          'egg': s?.egg?.stage.name,
          'eggCracks': s?.egg?.cracks,
          'birdY': game.runBirdPosition?.y,
          'vy': game.runBirdVelocityY,
          'rumble': game.rumble.fired.isEmpty
              ? null
              : game.rumble.fired.last.name,
          'runSettings': game.runSettingsOpen,
          'reviveUi': game.reviveScreen?.ui,
          'bonusPhase': game.bonusScreen?.phase.name,
          'bonusOffer': game.bonusScreen?.offer.name,
          'canContinue': game.resultsScreen?.canContinue,
          'start': [rect.center.dx, rect.center.dy],
          'modeTap': [modeRect.center.dx, modeRect.center.dy],
        }),
      );
    } catch (e, st) {
      log('harness error $e $st');
    } finally {
      busy = false;
    }
  });
}
