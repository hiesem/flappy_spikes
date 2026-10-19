// PRD-2.2 §7.8 / §28 device pass (WP-7b) on the Pixel 8: a debug build of
// the game with the REAL AdMob rewarded ad (Google TEST unit in debug), the
// real audio (SoundService enabled) and the Android AudioFocus watcher.
//
//   flutter run -d <PIXEL8_SERIAL> -t integration_test/p22_audio_ads_device_main.dart
//   adb -s <PIXEL8_SERIAL> logcat -s flutter | grep P7B
//
// Scenario (logs every step with `P7B`):
// 1. a run with the chick flying (hatched through the run's events), 6
//    hoops (debug passes), death → revive offer → the heart → the TEST
//    rewarded ad (close it with its ×) → phoenix; every egg_peep request is
//    logged with the audio state, so a peep under the ad shows up;
// 2. a second death with 3 feathers → decline the 250 offer → the balloon
//    bonus → 3 pops → the "▶ feather ×3" offer (logs wait_ms / outcome)
//    → the TEST ad again → 3 feathers back;
// 3. Home, idle: the music state is logged every second, for the
//    interruption (ringtone / alarm) and own-music checks driven from adb.
// Its own SharedPreferences prefix keeps the owner's game data untouched.
import 'dart:async';

import 'package:flame/game.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/audio_focus.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _log(String s) => debugPrint('P7B $s');

Future<void> _wait(bool Function() done, {int seconds = 120}) async {
  for (var i = 0; i < seconds * 10 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _sleep(double s) =>
    Future<void>.delayed(Duration(milliseconds: (s * 1000).round()));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('p7b.');
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  } catch (_) {}
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final worldHeight = 320 * view.physicalSize.height / view.physicalSize.width;
  final consent = AdMobAdsConsent();
  final ads = AdMobRewardedAds(consent: consent);
  final monetization = Monetization(
    ads: ads,
    interstitial: NoopInterstitialAds(),
    banner: NoopBannerAds(),
    consent: consent,
    iap: FakeIapService(),
  );
  final game = FlappySpikesGame(
    worldHeight: worldHeight,
    monetization: monetization,
  )..audioFocus = PlatformAudioFocus();
  runApp(GameWidget(game: game));
  await monetization.initialize();
  await game.loaded;
  final s = game.sound;
  s.onMusic = (e) => _log('music $e');
  s.onPlay = (sfx) {
    if (sfx == Sfx.eggPeep) {
      _log(
        'egg_peep requested state=${game.state.name} '
        'suspended=${s.suspended}',
      );
    }
  };
  var lastState = '';
  Timer.periodic(const Duration(milliseconds: 250), (_) {
    final st =
        'game=${game.state.name} suspended=${s.suspended} '
        'interrupted=${s.interrupted} ownMusicSkipped=${s.ownMusicSkipped} '
        'musicPlaying=${s.musicPlaying} loops=${s.activeLoops.length} '
        'dropped=${s.droppedPlays}';
    if (st != lastState) {
      lastState = st;
      _log('state $st');
    }
  });
  _log('start consent=${consent.canRequestAds.value}');
  await _wait(() => ads.isAvailable, seconds: 60);
  _log('rewarded loaded=${ads.isAvailable}');

  if (const bool.fromEnvironment('P7B_AUDIO_ONLY')) {
    Timer.periodic(const Duration(seconds: 2), (_) async {
      _log('otherMusicActive=${await game.audioFocus.isOtherMusicActive()}');
    });
    _log('home: idle for the interruption / own-music checks');
    return;
  }
  // ---------------------------------------------------------------- 1
  game.onScreenTap(); // START
  await _wait(() => game.state == GameState.playing && game.run != null);
  final run = game.run!;
  game.runDebug.god = true;
  run.events.emit(PickupCollected(ElementId.egg, null));
  for (var i = 0; i < 5; i++) {
    run.events.emit(HoopPassed(null, perfect: true));
  }
  _log('chick=${run.state.egg?.stage == EggStage.chick}');
  for (var i = 0; i < 6; i++) {
    run.debugPass(perfect: true);
  }
  await _sleep(3); // hear the chick peep while flying
  game.runDebug.god = false;
  run.state
    ..invulnerable = 0
    ..shield = false;
  game.onBirdHit(MistakeCause.spikes);
  _log('died; chick=${run.state.egg}');
  await _wait(() => game.reviveScreen?.ui == 1);
  _log('revive offer=${game.reviveScreen?.offer}');
  await _sleep(2);
  game.reviveScreen!.tapHeart();
  _log('heart tapped: the TEST rewarded ad should show; close it with ×');
  await _wait(() => game.state == GameState.playing, seconds: 180);
  game.runDebug.god = true;
  _log('revived; music=${s.musicPlaying}');

  // ---------------------------------------------------------------- 2
  await game.storage.saveFeathers(3);
  await _sleep(2);
  game.runDebug.god = false;
  run.state.invulnerable = 0;
  game.onBirdHit(MistakeCause.spikes);
  await _wait(() => game.reviveScreen?.ui == 1);
  _log('2nd offer=${game.reviveScreen?.offer} → No thanks');
  game.reviveScreen!.tapNoThanks();
  await _wait(() => game.bonusScreen != null);
  final b = game.bonusScreen!;
  await _sleep(1);
  _log('bonus: ad loaded now=${ads.isAvailable}');
  for (final i in [0, 1, 2]) {
    b.tapTile(i);
    await _sleep(1.3);
  }
  await _wait(() => b.phase != BonusPhase.pick, seconds: 10);
  final t0 = DateTime.now();
  _log('bonus offer=${b.offer.name} waiting=${b.adWaiting}');
  await _wait(() => !b.adWaiting, seconds: 10);
  _log(
    'bonus offer active after '
    '${DateTime.now().difference(t0).inMilliseconds} ms, phase=${b.phase.name}',
  );
  if (b.phase == BonusPhase.offer) {
    unawaited(b.tapOffer());
    _log('bonus ad: the TEST rewarded ad should show; close it with ×');
    await _wait(() => b.phase == BonusPhase.pick, seconds: 180);
    await _sleep(2);
    _log('bonus refilled feathers=${b.feathers}');
  }
  await _wait(() => game.state == GameState.bonus, seconds: 2);
  for (var i = 0; i < 40 && game.state == GameState.bonus; i++) {
    if (b.phase == BonusPhase.pick && b.feathers > 0) {
      for (var k = 0; k < 9; k++) {
        if (b.tapTile(k)) break;
      }
    }
    b.tapNoThanks();
    b.tapNext();
    await _sleep(1.2);
  }
  await _wait(() => game.state == GameState.results, seconds: 10);
  await _sleep(2);
  game.goHome();
  await _wait(() => game.state == GameState.start, seconds: 10);

  // ---------------------------------------------------------------- 3
  _log('home: idle for the interruption / own-music checks');
}
