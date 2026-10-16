import 'dart:async';
import 'dart:io' show Platform;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'audio_counter.dart';
import 'config.dart';
import 'diag.dart';
import 'music_backend.dart';
import 'music_log.dart';
import 'native_loops.dart';
import 'sfx_pool.dart';
import 'sound_durations.g.dart';

/// Sound effects used by the game (files live in assets/audio/).
///
/// The first four are the 1.0 gameplay sounds; the `sk*` / `bn*` entries are
/// the PRD-menu-v2 / PRD-home-v3 menu sounds (`design/menu_v2/sfx/`).
enum Sfx {
  flap,
  point,
  gameover,
  click,
  skTab,
  skTap,
  skEquip,
  skBuyCommon,
  skBuyRare,
  skBuyEpic,
  skBuyLegendary,
  skProgress,
  skNoCoins,
  skHoop,
  skFire,
  skClose,
  skDialog,
  bnAdBtn,
  bnCoin,
  skTick,
  noadsUnlock,
  noadsStamp,
  // region WP-0b — approved PRD-2 run sounds (design/menu_v2/sfx; §3.4, §3.9,
  // §5.9, §5.10, §3.15, §3.16, §5.16, §5.12b, §5.13)
  perfect1,
  perfect2,
  perfect3,
  puHeart1,
  puHeart2,
  puHeartUse,
  puShieldGet,
  puShieldHit,
  puCometGet,
  puCometEnd,
  puPortal,
  puCannonAim,
  puCannonShot,
  puLand,
  missShock,
  rvPay,
  rvIgnite,
  rvBurst,
  rvLocked,
  lvBar,
  lvUp,
  lvUpBig,
  lvClaim,
  colFeatherGet,
  colFeatherSlot1,
  colFeatherSlot2,
  colFeatherSlot3,
  bnBalloonOpen,
  bnPrizeS,
  bnPrizeM,
  bnPrizeBig,
  col4PuzzleGet,
  col4PuzzleSlot1,
  col4PuzzleSlot2,
  col4PuzzleSlot3,
  col4PuzzleSlot4,
  col4Coins,
  sqWarn,
  sqClose,
  sqLock,
  sqTick,
  sqOpen,
  rdPinBumper,
  rdPinFlipper,
  rdPinJackpot,
  rdPinPlunger,
  rdSeaBubble,
  rdSeaSplash,
  rdSeaSpout,
  rdSeaWhale,
  rdSpaceLand,
  rdSpacePop,
  rdSpaceRocket,
  rdStormThunder,
  rdStormUmbrella,
  rdStormWind,
  rdVolcErupt,
  rdVolcRumble,
  // endregion WP-0b
  // region WP-3h — generated PRD-2 sound pack (design/menu_v2/gen_sfx15.py)
  // §5.8 versus intro (whoosh, ticks, chime, rocket, pop/crackle, thud, boing)
  vsWhoosh,
  vsTick,
  vsChime,
  vsRocket,
  vsPop,
  vsThud,
  vsBoing,
  // §5.17 saw rings: deaths (hums are SfxLoop, below)
  sawWireZap,
  sawWireThunder,
  sawWireCrackle,
  sawFrostCrunch,
  sawFrostHiss,
  sawFrostCrack,
  sawFrostTink,
  sawFrostShatter,
  sawHoleInhale,
  sawHoleRoar,
  sawHoleBoom,
  sawHoleSubdrop,
  // §5.18 FEVER: pass + fire out (fever_loop is an SfxLoop)
  feverPass,
  feverOut,
  // §5.19 switch rings, all 5 designs: touched / opening / crash + the shared clear chord
  swLockTouch,
  swLockOpen,
  swLockCrash,
  swLaserTouch,
  swLaserOpen,
  swLaserCrash,
  swIrisTouch,
  swIrisOpen,
  swIrisCrash,
  swSnoozeTouch,
  swSnoozeOpen,
  swSnoozeCrash,
  swGiftTouch,
  swGiftOpen,
  swGiftCrash,
  swClear,
  // §5.20 pair gifts: box opens, one per reward, ring skipped
  pairBoxOpen,
  pairShield,
  pairComet,
  pairCoins,
  pairScore,
  pairFever,
  pairSkipped,
  // §5.21 Ring Train (C5/E5/G5 + rising finish)
  trainNote1,
  trainNote2,
  trainNote3,
  trainFinish,
  // §5.22 Spring Ring (up / down)
  springUp,
  springDown,
  // §5.23 Bullseye Ring (dart thunk + bright chord)
  bullThunk,
  bullChord,
  // §5.24 Lucky Spin (ticks, pass whoosh, win chord)
  luckyTick,
  luckyWhoosh,
  luckyWin,
  // §5.25 Star Trail (C major C5 -> C6, pop, bright chord)
  trailNote1,
  trailNote2,
  trailNote3,
  trailNote4,
  trailNote5,
  trailNote6,
  trailNote7,
  trailNote8,
  trailPop,
  trailChord,
  // §5.26 Egg (pickup, crack, hatch, peeps, goodbye)
  eggPickup,
  eggCrack,
  eggHatch,
  eggPeep,
  eggBye,
  // §5.27 Piggy Bank (oink, coin clinks, missed blip, smash + cascade + chord)
  piggyOink,
  piggyCoin,
  piggyMiss,
  piggySmash,
  // §5.28 Firefly Jar (pickup, twinkle, escape blip, crack, full chord)
  jarPickup,
  jarTwinkle,
  jarEscape,
  jarBreak,
  jarFull,
  // §3.0.4 rim "tonk" (rim bounce; placeholder was sk_tap before WP-3h)
  rimTonk,
  // §5.29 Hourglass (slowdown, tick-tock, speed-up)
  hourglassStart,
  hourglassTick,
  hourglassEnd,
  // §5.30 Mini Bird (shrink potion start / end)
  miniStart,
  miniEnd,
  // §5.31 Coin Frenzy (jackpot run, per-ring cascade, end tone)
  frenzyStart,
  frenzyRing,
  frenzyEnd,
  // endregion WP-3h
  // region anchors — append below (one value per WP, with a `// WP-x` note)
  // P22-2 — PRD-2.2 §2.2 Home mode button (design/menu_v2/gen_sfx16.py):
  // swipe down into the bubble pop (VERSUS) / swipe up, lighter pop (FREE FLY)
  modeToVs,
  modeToFf,
  // endregion anchors
}

/// Looping sounds (PRD-2 §3.9, §5.16): one looping player each, owned by
/// [SoundService.loop]. Shipped as .wav so the loop is seamless (mp3
/// padding clicks) and plays on iOS too.
enum SfxLoop {
  cometLoop('pu_comet_loop.wav'),
  sqHold('sq_hold.wav'),
  // region WP-3h — §5.17 saw hums + §5.18 FEVER burning crackle (gen_sfx15.py)
  sawWireHum('saw_wire_hum.wav'),
  sawFrostHum('saw_frost_hum.wav'),
  sawHoleHum('saw_hole_hum.wav'),
  feverLoop('fever_loop.wav')
  // endregion WP-3h
  // region anchors — append below (one value per WP, with a `// WP-x` note)
  // endregion anchors
  ;

  const SfxLoop(this.file);
  final String file;
}

/// A running loop; [stop] is idempotent.
abstract class LoopHandle {
  SfxLoop get loop;
  bool get stopped;

  /// Whether the loop is heard: false when SFX are muted or the service is
  /// disabled (a silent recorder). PRD-2.2 §21.1: loops follow the SFX
  /// switch.
  bool get audible;

  /// The volume last set (0..1).
  double get volume;
  Future<void> setVolume(double volume);
  Future<void> stop();
}

class SoundService {
  SoundService({this.muted = false, this.enabled = true});

  static const Map<Sfx, String> _files = {
    Sfx.flap: 'flap.mp3',
    Sfx.point: 'point.mp3',
    Sfx.gameover: 'gameover.mp3',
    Sfx.click: 'click.mp3',
    Sfx.skTab: 'sk_tab.mp3',
    Sfx.skTap: 'sk_tap.mp3',
    Sfx.skEquip: 'sk_equip.mp3',
    Sfx.skBuyCommon: 'sk_buy_common.mp3',
    Sfx.skBuyRare: 'sk_buy_rare.mp3',
    Sfx.skBuyEpic: 'sk_buy_epic.mp3',
    Sfx.skBuyLegendary: 'sk_buy_legendary.mp3',
    Sfx.skProgress: 'sk_progress.mp3',
    Sfx.skNoCoins: 'sk_nocoins.mp3',
    Sfx.skHoop: 'sk_hoop.mp3',
    Sfx.skFire: 'sk_fire.mp3',
    Sfx.skClose: 'sk_close.mp3',
    Sfx.skDialog: 'sk_dialog.mp3',
    Sfx.bnAdBtn: 'bn_adbtn.mp3',
    Sfx.bnCoin: 'bn_coin.mp3',
    Sfx.skTick: 'sk_tick.mp3',
    Sfx.noadsUnlock: 'noads_unlock.mp3',
    Sfx.noadsStamp: 'noads_stamp.mp3',
    // region WP-0b
    Sfx.perfect1: 'perfect_1.mp3',
    Sfx.perfect2: 'perfect_2.mp3',
    Sfx.perfect3: 'perfect_3.mp3',
    Sfx.puHeart1: 'pu_heart_1.mp3',
    Sfx.puHeart2: 'pu_heart_2.mp3',
    Sfx.puHeartUse: 'pu_heart_use.mp3',
    Sfx.puShieldGet: 'pu_shield_get.mp3',
    Sfx.puShieldHit: 'pu_shield_hit.mp3',
    Sfx.puCometGet: 'pu_comet_get.mp3',
    Sfx.puCometEnd: 'pu_comet_end.mp3',
    Sfx.puPortal: 'pu_portal.mp3',
    Sfx.puCannonAim: 'pu_cannon_aim.mp3',
    Sfx.puCannonShot: 'pu_cannon_shot.mp3',
    Sfx.puLand: 'pu_land.mp3',
    Sfx.missShock: 'miss_shock.mp3',
    Sfx.rvPay: 'rv_pay.mp3',
    Sfx.rvIgnite: 'rv_ignite.mp3',
    Sfx.rvBurst: 'rv_burst.mp3',
    Sfx.rvLocked: 'rv_locked.mp3',
    Sfx.lvBar: 'lv_bar.mp3',
    Sfx.lvUp: 'lv_up.mp3',
    Sfx.lvUpBig: 'lv_up_big.mp3',
    Sfx.lvClaim: 'lv_claim.mp3',
    Sfx.colFeatherGet: 'col_feather_get.mp3',
    Sfx.colFeatherSlot1: 'col_feather_slot1.mp3',
    Sfx.colFeatherSlot2: 'col_feather_slot2.mp3',
    Sfx.colFeatherSlot3: 'col_feather_slot3.mp3',
    Sfx.bnBalloonOpen: 'bn_balloon_open.mp3',
    Sfx.bnPrizeS: 'bn_prize_s.mp3',
    Sfx.bnPrizeM: 'bn_prize_m.mp3',
    Sfx.bnPrizeBig: 'bn_prize_big.mp3',
    Sfx.col4PuzzleGet: 'col4_puzzle_get.mp3',
    Sfx.col4PuzzleSlot1: 'col4_puzzle_slot1.mp3',
    Sfx.col4PuzzleSlot2: 'col4_puzzle_slot2.mp3',
    Sfx.col4PuzzleSlot3: 'col4_puzzle_slot3.mp3',
    Sfx.col4PuzzleSlot4: 'col4_puzzle_slot4.mp3',
    Sfx.col4Coins: 'col4_coins.mp3',
    Sfx.sqWarn: 'sq_warn.mp3',
    Sfx.sqClose: 'sq_close.mp3',
    Sfx.sqLock: 'sq_lock.mp3',
    Sfx.sqTick: 'sq_tick.mp3',
    Sfx.sqOpen: 'sq_open.mp3',
    Sfx.rdPinBumper: 'rd_pin_bumper.mp3',
    Sfx.rdPinFlipper: 'rd_pin_flipper.mp3',
    Sfx.rdPinJackpot: 'rd_pin_jackpot.mp3',
    Sfx.rdPinPlunger: 'rd_pin_plunger.mp3',
    Sfx.rdSeaBubble: 'rd_sea_bubble.mp3',
    Sfx.rdSeaSplash: 'rd_sea_splash.mp3',
    Sfx.rdSeaSpout: 'rd_sea_spout.mp3',
    Sfx.rdSeaWhale: 'rd_sea_whale.mp3',
    Sfx.rdSpaceLand: 'rd_space_land.mp3',
    Sfx.rdSpacePop: 'rd_space_pop.mp3',
    Sfx.rdSpaceRocket: 'rd_space_rocket.mp3',
    Sfx.rdStormThunder: 'rd_storm_thunder.mp3',
    Sfx.rdStormUmbrella: 'rd_storm_umbrella.mp3',
    Sfx.rdStormWind: 'rd_storm_wind.mp3',
    Sfx.rdVolcErupt: 'rd_volc_erupt.mp3',
    Sfx.rdVolcRumble: 'rd_volc_rumble.mp3',
    // endregion WP-0b
    // region WP-3h — generated PRD-2 sound pack (§5.8-§5.31, §3.0.4)
    Sfx.vsWhoosh: 'vs_whoosh.mp3',
    Sfx.vsTick: 'vs_tick.mp3',
    Sfx.vsChime: 'vs_chime.mp3',
    Sfx.vsRocket: 'vs_rocket.mp3',
    Sfx.vsPop: 'vs_pop.mp3',
    Sfx.vsThud: 'vs_thud.mp3',
    Sfx.vsBoing: 'vs_boing.mp3',
    Sfx.sawWireZap: 'saw_wire_zap.mp3',
    Sfx.sawWireThunder: 'saw_wire_thunder.mp3',
    Sfx.sawWireCrackle: 'saw_wire_crackle.mp3',
    Sfx.sawFrostCrunch: 'saw_frost_crunch.mp3',
    Sfx.sawFrostHiss: 'saw_frost_hiss.mp3',
    Sfx.sawFrostCrack: 'saw_frost_crack.mp3',
    Sfx.sawFrostTink: 'saw_frost_tink.mp3',
    Sfx.sawFrostShatter: 'saw_frost_shatter.mp3',
    Sfx.sawHoleInhale: 'saw_hole_inhale.mp3',
    Sfx.sawHoleRoar: 'saw_hole_roar.mp3',
    Sfx.sawHoleBoom: 'saw_hole_boom.mp3',
    Sfx.sawHoleSubdrop: 'saw_hole_subdrop.mp3',
    Sfx.feverPass: 'fever_pass.mp3',
    Sfx.feverOut: 'fever_out.mp3',
    Sfx.swLockTouch: 'sw_lock_touch.mp3',
    Sfx.swLockOpen: 'sw_lock_open.mp3',
    Sfx.swLockCrash: 'sw_lock_crash.mp3',
    Sfx.swLaserTouch: 'sw_laser_touch.mp3',
    Sfx.swLaserOpen: 'sw_laser_open.mp3',
    Sfx.swLaserCrash: 'sw_laser_crash.mp3',
    Sfx.swIrisTouch: 'sw_iris_touch.mp3',
    Sfx.swIrisOpen: 'sw_iris_open.mp3',
    Sfx.swIrisCrash: 'sw_iris_crash.mp3',
    Sfx.swSnoozeTouch: 'sw_snooze_touch.mp3',
    Sfx.swSnoozeOpen: 'sw_snooze_open.mp3',
    Sfx.swSnoozeCrash: 'sw_snooze_crash.mp3',
    Sfx.swGiftTouch: 'sw_gift_touch.mp3',
    Sfx.swGiftOpen: 'sw_gift_open.mp3',
    Sfx.swGiftCrash: 'sw_gift_crash.mp3',
    Sfx.swClear: 'sw_clear.mp3',
    Sfx.pairBoxOpen: 'pair_box_open.mp3',
    Sfx.pairShield: 'pair_shield.mp3',
    Sfx.pairComet: 'pair_comet.mp3',
    Sfx.pairCoins: 'pair_coins.mp3',
    Sfx.pairScore: 'pair_score.mp3',
    Sfx.pairFever: 'pair_fever.mp3',
    Sfx.pairSkipped: 'pair_skipped.mp3',
    Sfx.trainNote1: 'train_note1.mp3',
    Sfx.trainNote2: 'train_note2.mp3',
    Sfx.trainNote3: 'train_note3.mp3',
    Sfx.trainFinish: 'train_finish.mp3',
    Sfx.springUp: 'spring_up.mp3',
    Sfx.springDown: 'spring_down.mp3',
    Sfx.bullThunk: 'bull_thunk.mp3',
    Sfx.bullChord: 'bull_chord.mp3',
    Sfx.luckyTick: 'lucky_tick.mp3',
    Sfx.luckyWhoosh: 'lucky_whoosh.mp3',
    Sfx.luckyWin: 'lucky_win.mp3',
    Sfx.trailNote1: 'trail_note1.mp3',
    Sfx.trailNote2: 'trail_note2.mp3',
    Sfx.trailNote3: 'trail_note3.mp3',
    Sfx.trailNote4: 'trail_note4.mp3',
    Sfx.trailNote5: 'trail_note5.mp3',
    Sfx.trailNote6: 'trail_note6.mp3',
    Sfx.trailNote7: 'trail_note7.mp3',
    Sfx.trailNote8: 'trail_note8.mp3',
    Sfx.trailPop: 'trail_pop.mp3',
    Sfx.trailChord: 'trail_chord.mp3',
    Sfx.eggPickup: 'egg_pickup.mp3',
    Sfx.eggCrack: 'egg_crack.mp3',
    Sfx.eggHatch: 'egg_hatch.mp3',
    Sfx.eggPeep: 'egg_peep.mp3',
    Sfx.eggBye: 'egg_bye.mp3',
    Sfx.piggyOink: 'piggy_oink.mp3',
    Sfx.piggyCoin: 'piggy_coin.mp3',
    Sfx.piggyMiss: 'piggy_miss.mp3',
    Sfx.piggySmash: 'piggy_smash.mp3',
    Sfx.jarPickup: 'jar_pickup.mp3',
    Sfx.jarTwinkle: 'jar_twinkle.mp3',
    Sfx.jarEscape: 'jar_escape.mp3',
    Sfx.jarBreak: 'jar_break.mp3',
    Sfx.jarFull: 'jar_full.mp3',
    Sfx.rimTonk: 'rim_tonk.mp3',
    Sfx.hourglassStart: 'hourglass_start.mp3',
    Sfx.hourglassTick: 'hourglass_tick.mp3',
    Sfx.hourglassEnd: 'hourglass_end.mp3',
    Sfx.miniStart: 'mini_start.mp3',
    Sfx.miniEnd: 'mini_end.mp3',
    Sfx.frenzyStart: 'frenzy_start.mp3',
    Sfx.frenzyRing: 'frenzy_ring.mp3',
    Sfx.frenzyEnd: 'frenzy_end.mp3',
    // endregion WP-3h
    // P22-2 — PRD-2.2 §2.2
    Sfx.modeToVs: 'mode_to_vs.mp3',
    Sfx.modeToFf: 'mode_to_ff.mp3',
  };

  /// The bundled file for every [Sfx] (asserted by the asset test).
  static const Map<Sfx, String> audioFiles = _files;

  /// The 1.0 gameplay sounds keep their deeper pools; the menu sounds only
  /// ever overlap a couple at a time (PRD-menu-v2 WP-A).
  static const Set<Sfx> _legacyPool = {
    Sfx.flap,
    Sfx.point,
    Sfx.gameover,
    Sfx.click,
  };

  /// The coin-reward count-up (PRD-home-v3 §5) fires these in bursts: up
  /// to 16 `bn_coin` landings 55 ms apart and up to 24 `sk_tick`s, so
  /// their pools keep more warm players (a pool that runs dry creates a
  /// fresh player mid-animation).
  static const Set<Sfx> _burstPool = {Sfx.bnCoin, Sfx.skTick, Sfx.piggyCoin};

  /// PRD-2.3 §16.3: the seamless 56-bar OGG loop on Android and the Linux
  /// desktop build. iOS (no OGG Vorbis) plays the same loop as AAC, a
  /// Runner bundle resource (not a Flutter asset) played by the runner's
  /// `LoopMusic` ([NativeLoopMusic], iOS round 2 §1).
  static String musicFileFor({required bool isIOS}) =>
      isIOS ? iosMusicFile : 'HappyBeat_loop_56bars.ogg';

  /// The iOS music loop in `ios/Runner/` (`tool/make_music_loop_ios.py`).
  static const String iosMusicFile = 'HappyBeat_loop_56bars.m4a';

  static String get _musicFile =>
      musicFileFor(isIOS: !kIsWeb && Platform.isIOS);

  bool muted;

  /// Master switch for audio output. Headless tests set this to false so no
  /// calls reach the audioplayers platform channel (which has no test
  /// backend and would throw [MissingPluginException]).
  bool enabled;

  double _musicVolume = Config.defaultMusicVolume;
  bool _musicStarted = false;

  /// Low-latency pools, one per SFX ([SfxPool], `sfx_pool.dart`). Without
  /// pools, FlameAudio.play creates a brand-new AudioPlayer (decoder +
  /// AudioTrack + audio-focus request) for EVERY effect — that made flap
  /// sounds laggy and churned CPU on the Pixel 8 (2026-07-22).
  ///
  /// The voices use SoundPool mode ([PlayerMode.lowLatency]): sounds are
  /// decoded ONCE and each play is a sub-millisecond queue on an open
  /// stream. The default MediaPlayer mode made every play open+close an
  /// audio route, which stalled frames on the Pixel 8 (2026-07-22). SoundPool
  /// never reports completion or duration, so each play is stopped after the
  /// file's length from the generated table (PRD-2.2 §22) + 100 ms.
  ///
  /// PRD-2.2 §33.4: every pool has a fixed, hard-capped voice set (oldest
  /// copy stolen when all are busy), voices are disposed (never released)
  /// and idle pools are evicted ([_trimPools]); [prewarmed] always stays.
  ///
  /// PRD-2 has ~170 cues, so pools are created lazily (WP-P1int): only
  /// [prewarmed] warms up at start; every other pool is created on its first
  /// [play] or on [preload].
  final Map<Sfx, SfxPool> _pools = {};
  bool _poolsStarted = false;

  /// One creation per sound (also when it failed: no retry storm). An
  /// evicted pool's entry is removed so it can be created again.
  final Map<Sfx, Future<void>> _creating = {};

  /// iOS round 2: when a pool's first voice last failed to load; its sound
  /// tries again after [Config.sfxRetryFailedMs].
  final Map<Sfx, int> _failedAtMs = {};

  /// First plays of lazily created pools, waiting for their pool (when the
  /// request was made).
  final Map<Sfx, DateTime> _pendingFirst = {};

  /// PRD-2.2 §33.4 / §33.7 (S7-10): bumped by [dispose]. A pool creation or
  /// warm-up that started in an older generation publishes nothing and
  /// disposes the voices it created meanwhile.
  int _generation = 0;

  /// Pools whose creation runs now (not yet published or given up): they
  /// count towards the live-pool cap at admission (S7-11).
  final Set<Sfx> _inflight = {};

  /// PRD-2.2 §18.4 / §33.4 item 3 (S7-11): the cues of the latest [preload]
  /// (the ride / power-up about to happen). The cap never evicts them.
  Set<Sfx> _reserved = const {};

  /// Monotonic clock for pool use / eviction.
  final Stopwatch _clock = Stopwatch()..start();
  int get _nowMs => clockMs?.call() ?? _clock.elapsedMilliseconds;

  /// Test seam: replaces the monotonic ms clock (idle-eviction tests).
  @visibleForTesting
  int Function()? clockMs;
  int _lastTrimMs = 0;

  /// The core run sounds, warmed up at start (PRD-2 §7, WP-P1int): flap,
  /// point, the rim tonk, the perfect / streak set — plus the 1.0 game-over
  /// and the menu click, which every session plays. Never evicted
  /// (PRD-2.2 §33.4 item 3).
  static const Set<Sfx> prewarmed = {
    Sfx.flap,
    Sfx.point,
    Sfx.gameover,
    Sfx.click,
    Sfx.rimTonk,
    Sfx.perfect1,
    Sfx.perfect2,
    Sfx.perfect3,
  };

  /// PRD-2.2 §33.6 (S7-19): the session sound set. Besides the core run
  /// set ([prewarmed]) these are the cues that (nearly) every session plays
  /// game after game: the post-run count-up, coin landings and ticks, the
  /// balloon bonus, LEVEL UP / CLAIM, the feather slots and the star trail.
  /// [warmSession] creates them once, right after the core, and from then
  /// on they are never evicted, so the native player count no longer goes
  /// up and down with the run-to-run mix of cues (flat from game 2, §33.6).
  /// Every other cue is run-scoped: created on its first play / preload and
  /// disposed at the end of its run ([endRun]).
  static const Set<Sfx> sessionWarm = {
    Sfx.skTick,
    Sfx.bnCoin,
    Sfx.bnAdBtn,
    Sfx.lvBar,
    Sfx.lvUp,
    Sfx.lvUpBig,
    Sfx.lvClaim,
    Sfx.bnBalloonOpen,
    Sfx.bnPrizeS,
    Sfx.bnPrizeM,
    Sfx.bnPrizeBig,
    Sfx.colFeatherGet,
    Sfx.colFeatherSlot1,
    Sfx.colFeatherSlot2,
    Sfx.colFeatherSlot3,
    Sfx.trailNote1,
    Sfx.trailNote2,
    Sfx.trailNote3,
    Sfx.trailNote4,
    Sfx.trailNote5,
    Sfx.trailNote6,
    Sfx.trailNote7,
    Sfx.trailNote8,
    Sfx.trailPop,
    Sfx.trailChord,
  };

  /// True once [warmSession] ran: [sessionWarm] is pinned like [prewarmed].
  bool _sessionPinned = false;

  /// The pools that are never evicted now ([prewarmed], plus [sessionWarm]
  /// once [warmSession] ran).
  bool _pinned(Sfx sfx) =>
      prewarmed.contains(sfx) || (_sessionPinned && sessionWarm.contains(sfx));

  /// Run-scoped pools still ringing when their run ended ([endRun]); each
  /// is disposed by [maintain] once its last copy has finished.
  final Set<Sfx> _runEnded = {};

  /// A lazily created pool plays its first request once it is ready, unless
  /// that took longer than this (a late sound is worse than none).
  static const Duration firstPlayLateLimit = Duration(milliseconds: 250);

  /// PRD-2.2 §22: the designed length of [file] from the generated table
  /// (`tool/gen_sound_durations.py`), never the plugin's `getDuration()`
  /// (null on Android SoundPool, which cut every effect at 0.6 s). A missing
  /// file asserts in debug and plays 1 s in release.
  static Duration lengthOf(String file) {
    final entry = kSoundDurations[file];
    assert(
      entry != null,
      '$file is missing from kSoundDurations: run '
      'python3 -I tool/gen_sound_durations.py',
    );
    return Duration(milliseconds: entry?.$1 ?? Config.sfxMissingLengthMs);
  }

  /// PRD-2.2 §22.1: the fixed number of players for [sfx] (hard cap).
  static int voicesFor(Sfx sfx) {
    if (_burstPool.contains(sfx)) return Config.sfxVoicesBurst;
    if (_legacyPool.contains(sfx)) return Config.sfxVoicesLegacy;
    final file = _files[sfx];
    final ms = file == null ? 0 : kSoundDurations[file]?.$1 ?? 0;
    return ms > Config.sfxLongSoundMs
        ? Config.sfxVoicesLong
        : Config.sfxVoicesDefault;
  }

  /// Background-music volume (0..1). Independent of [muted], which only
  /// gates sound effects.
  double get musicVolume => _musicVolume;

  /// Test seam: called with every requested sound (also when [enabled] is
  /// false), before muting applies.
  void Function(Sfx sfx)? onPlay;

  /// Test seam: builds ONE voice for a file (called [voicesFor] times per
  /// pool, sequentially). Defaults to the real low-latency [PlayerVoice]; a
  /// test injects fakes (or returns null: a voice that never became ready)
  /// to run the pool logic without the audioplayers plugin.
  @visibleForTesting
  Future<SfxVoice?> Function(String file)? voiceFactory;

  void play(Sfx sfx) {
    onPlay?.call(sfx);
    if (muted) return;
    // PRD-2.2 §28.2 / §28.3: dropped (never queued) while a full-screen ad
    // is up or another app's call / alarm / assistant holds the audio.
    if (_sfxSilenced) {
      droppedPlays++;
      return;
    }
    onAudible?.call(sfx);
    _markOwnSound(sfx);
    if (!enabled) {
      return;
    }
    final pool = _pools[sfx];
    // While the pool is missing the sound is not played now. A bare
    // FlameAudio.play here would spawn a fresh one-shot AudioPlayer, which
    // the project bans (CLAUDE.md: preloaded low-latency pools only).
    if (pool == null) {
      unawaited(_initPools());
      final failed = _failedAtMs[sfx];
      if (failed != null && _nowMs - failed < Config.sfxRetryFailedMs) return;
      // A missing pool is created now and plays this request once it is
      // ready (if that is quick enough): a lazy pool's first request, and
      // also a core pool the warm-up skipped (2.4.0 (23) Pixel 8: the app
      // was briefly inactive at launch and those sounds stayed silent for
      // the whole session).
      if (_appActive && !_creating.containsKey(sfx)) {
        _pendingFirst[sfx] = DateTime.now();
        unawaited(_ensurePool(sfx));
      }
      return;
    }
    _runEnded.remove(sfx);
    pool.play(_nowMs);
    if (_nowMs - _lastTrimMs >= Config.sfxTrimIntervalMs) _trimPools();
  }

  /// PRD-2.2 §18.4: creates the pools of [cues] without playing them (e.g.
  /// a portal's ride cues when the portal spawns), so their first [play] is
  /// heard. Marks existing pools as used and reserves the batch (the cap
  /// never evicts the latest preload, S7-11).
  ///
  /// PRD-2.2 §33.4 item 3 (S7-11): a preload respects
  /// [Config.sfxMaxLivePools]. Pools alive, being created and the core set
  /// count; when there is no room the least recently used idle pool goes
  /// (never the core set, a ringing pool or this batch); when nothing can
  /// go the rest of the batch is not created now (it is created on its
  /// first [play], as before §18.4).
  void preload(Iterable<Sfx> cues) {
    if (muted || !enabled) return;
    unawaited(_initPools());
    final batch = cues.toSet();
    _reserved = batch;
    final now = _nowMs;
    for (final sfx in batch) {
      final pool = _pools[sfx];
      if (pool != null) {
        pool.lastUsedMs = now;
        _runEnded.remove(sfx);
        continue;
      }
      if (_creating.containsKey(sfx)) continue;
      if (_projectedPools() >= Config.sfxMaxLivePools &&
          !_evictOneFor(batch, now)) {
        continue;
      }
      unawaited(_ensurePool(sfx));
    }
  }

  /// Pools alive or being created, plus the core set still to warm up.
  int _projectedPools() => {
    ..._pools.keys,
    ..._inflight,
    if (enabled) ...prewarmed,
    if (enabled && _sessionPinned) ...sessionWarm,
  }.length;

  /// Whether [pool] has a copy ringing at [now] (played within its length +
  /// margin). A pool that never played is not ringing.
  static bool _ringing(SfxPool pool, int now) {
    final t = pool.lastPlayedMs;
    return t != null &&
        now - t < pool.length.inMilliseconds + Config.sfxStopMarginMs;
  }

  /// Evicts the least recently used idle pool outside [keep] and the core
  /// set. False when there is none.
  bool _evictOneFor(Set<Sfx> keep, int now) {
    MapEntry<Sfx, SfxPool>? lru;
    for (final e in _pools.entries) {
      if (_pinned(e.key) || keep.contains(e.key) || _ringing(e.value, now)) {
        continue;
      }
      if (lru == null || e.value.lastUsedMs < lru.value.lastUsedMs) lru = e;
    }
    if (lru == null) return false;
    _evict(lru.key);
    return true;
  }

  // region P22-33 — §33.3 soak counters (debug / FS_SOAK only)
  /// Low-latency pools alive now (bounded, §33.4 item 3).
  int get poolCount => _pools.length;

  /// Players owned by the live pools.
  int get pooledVoices =>
      _pools.values.fold<int>(0, (n, p) => n + p.voiceCount);

  /// Pools evicted so far (idle or over the cap).
  int evictions = 0;

  /// FS_SOAK diagnostics: told when a play's stop timer fires (file, ms
  /// from play to stop). Set before the first play.
  void Function(String file, int playedMs)? debugOnStop;

  /// Live native audio players (created − disposed) when the FS_SOAK
  /// counter ([CountingAudioPlatform]) is installed; null otherwise.
  int? get livePlayers => CountingAudioPlatform.installed?.live;

  /// One-line counter summary for the soak log (logcat).
  String debugStats() {
    final c = CountingAudioPlatform.installed;
    final steals = _pools.values.fold<int>(0, (n, p) => n + p.steals);
    return 'pools=${_pools.length} pooled=$pooledVoices '
        'evicted=$evictions steals=$steals '
        'loops=${activeLoops.length}'
        '${c == null ? '' : ' players=${c.live} creates=${c.creates} '
                  'disposes=${c.disposes} releases=${c.releases} '
                  'resumes=${c.starts} posPolls=${c.positionPolls}'}';
  }
  // endregion P22-33

  /// True once [sfx]'s pool creation has been started (tests).
  @visibleForTesting
  bool poolRequested(Sfx sfx) => _creating.containsKey(sfx);

  /// [sfx]'s live pool (tests / diagnostics).
  @visibleForTesting
  SfxPool? poolOf(Sfx sfx) => _pools[sfx];

  /// The game's audio context: mixWithOthers (no audio-focus request: the
  /// player's own music keeps playing, PRD-2.2 §28.3) with the Android
  /// usage `USAGE_GAME`, so `MainActivity.kt` can tell the game's players
  /// from another app's music in the active playback configurations.
  /// iOS: the `.ambient` session category (it always mixes with other
  /// apps' audio and follows the silent switch, like a game should;
  /// PORT-IOS §3). AVFoundation forbids the explicit `mixWithOthers` option
  /// on `.ambient`, so the option set stays empty.
  static AudioContext gameAudioContext() {
    final base = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();
    return base.copy(
      android: base.android.copy(usageType: AndroidUsageType.game),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: const {},
      ),
    );
  }

  /// Sets the one global audio context (mixWithOthers: no audio-focus
  /// request, no AudioManager mode write per player; PERF.md §5). Awaited
  /// before any SFX / loop player is created, so each player inherits it.
  Future<void>? _globalContext;
  Future<void> _ensureGlobalContext() => _globalContext ??= () async {
    if (voiceFactory != null) return; // fake voices: no plugin
    try {
      await AudioPlayer.global.setAudioContext(gameAudioContext());
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }();

  /// Warms up the [prewarmed] pools once. No-op when [enabled] is false
  /// (tests) and idempotent afterwards; while it runs (or after a failure)
  /// [play] simply drops those sounds instead of opening a one-shot player.
  Future<void> _initPools() async {
    // iOS round 2b: never create players while the app is not active.
    if (!enabled || _poolsStarted || !_appActive) {
      return;
    }
    _poolsStarted = true;
    final gen = _generation;
    for (final sfx in prewarmed) {
      // S7-10: a teardown stops the warm-up.
      if (gen != _generation) return;
      if (!_appActive) {
        // Not active (round 2b: no player is created): the warm-up runs
        // again on the return ([setAppActive]), so no core sound is left
        // without its pool.
        _poolsStarted = false;
        return;
      }
      await _ensurePool(sfx);
    }
  }

  /// PRD-2.2 §33.6 (S7-19): pins [sessionWarm] and creates its pools once,
  /// one by one after the core set (on Home, before the first run needs
  /// them). Idempotent; no pool while muted or disabled (a later play
  /// creates it on demand, still pinned).
  Future<void> warmSession() async {
    _sessionPinned = true;
    if (!enabled || muted) return;
    final gen = _generation;
    await _initPools();
    for (final sfx in sessionWarm) {
      if (gen != _generation || muted || !_appActive) return;
      if (_pools.containsKey(sfx)) continue;
      await _ensurePool(sfx);
    }
  }

  /// PRD-2.2 §33.4 item 3 / §33.6 (S7-19): the run is over (Home arrival).
  /// Every run-scoped pool (not [prewarmed], not [sessionWarm] once
  /// pinned) is disposed now, or by [maintain] as soon as its last copy has
  /// finished, so each Home visit holds exactly the session set.
  void endRun() {
    final now = _nowMs;
    _reserved = const {};
    for (final e in List.of(_pools.entries)) {
      if (_pinned(e.key)) continue;
      if (_ringing(e.value, now)) {
        _runEnded.add(e.key);
      } else {
        _evict(e.key);
      }
    }
  }

  /// Called every game frame: disposes the run-ended pools whose copies
  /// have finished ([endRun]). Nothing to do (and no work) otherwise.
  void maintain() {
    if (_runEnded.isEmpty) return;
    final now = _nowMs;
    for (final sfx in List.of(_runEnded)) {
      final pool = _pools[sfx];
      if (pool == null) {
        _runEnded.remove(sfx);
      } else if (!_ringing(pool, now)) {
        _evict(sfx);
      }
    }
  }

  /// Run-ended pools still waiting for their last copy (tests).
  @visibleForTesting
  int get runEndedPending => _runEnded.length;

  /// iOS round 2b: no player is created while the app is not active
  /// (background, inactive, locked): creating AVPlayers then fails and kept
  /// the media server resetting (device log 2026-10-15). The request is not
  /// remembered; the next play / preload / warm-up in the foreground creates
  /// the pool.
  Future<void> _ensurePool(Sfx sfx) {
    if (!_appActive) return Future<void>.value();
    return _creating.putIfAbsent(sfx, () => _createPool(sfx));
  }

  Future<SfxVoice?> _newVoice(String file) async {
    try {
      final f = voiceFactory;
      if (f != null) return await f(file);
      return await PlayerVoice.create(file);
    } catch (_) {
      return null; // a voice that failed to load: the pool stays smaller
    }
  }

  /// Creates [sfx]'s pool (never throws). The pool is published with its
  /// first voice (so a first play is as quick as before); the other voices
  /// are created right after, one by one, up to the hard cap. No voice is
  /// ever created by [play].
  Future<void> _createPool(Sfx sfx) async {
    final file = _files[sfx];
    if (file == null) return;
    final length = lengthOf(file);
    final gen = _generation;
    _inflight.add(sfx);
    // S7-10: true (and the voice disposed) when [dispose] ran meanwhile.
    // Synchronous on the normal path (no extra hops in the warm-up).
    bool stale(SfxVoice? voice) {
      if (gen == _generation) return false;
      if (voice != null) unawaited(_discard(voice));
      return true;
    }

    try {
      await _ensureGlobalContext();
      if (stale(null)) return;
      final pool = SfxPool(
        file: file,
        length: length,
        capacity: voicesFor(sfx),
        stopMargin: const Duration(milliseconds: Config.sfxStopMarginMs),
        nowMs: _nowMs,
      )..onStopped = debugOnStop;
      final first = await _newVoice(file);
      if (first == null) {
        // Never became ready: stay silent. iOS round 2: logged, and the
        // creation is forgotten so a later play tries again (a voice that
        // failed once, e.g. while the app was coming back from the
        // background, no longer silences that sound for the session).
        diag('FS-Audio voice FAILED $file (pool not created; retried later)');
        if (gen == _generation) {
          _creating.remove(sfx);
          _failedAtMs[sfx] = _nowMs;
        }
        return;
      }
      if (stale(first)) return;
      pool.add(first);
      _pools[sfx] = pool;
      _failedAtMs.remove(sfx);
      final asked = _pendingFirst.remove(sfx);
      if (asked != null) {
        final waited = DateTime.now().difference(asked);
        if (enabled &&
            !muted &&
            !_sfxSilenced &&
            waited <= firstPlayLateLimit) {
          pool.play(_nowMs);
        } else {
          diag(
            'FS-Audio first play of $file dropped '
            '(${waited.inMilliseconds} ms to load, silenced=$_sfxSilenced)',
          );
        }
      }
      _trimPools();
      await _fillVoices(pool, gen);
    } catch (_) {
      // Audio failure must never take the game down. One bad pool must not
      // stop the remaining sounds from warming up either.
    } finally {
      if (gen == _generation) {
        _pendingFirst.remove(sfx);
        _inflight.remove(sfx);
      }
    }
  }

  /// PRD-2.2 §33.4 item 3: disposes pools not heard for
  /// [Config.sfxPoolIdleDisposeMs], then the least recently used idle ones
  /// while more than [Config.sfxMaxLivePools] are alive. [prewarmed] pools
  /// and pools with a playing voice are kept.
  void _trimPools() {
    final now = _nowMs;
    _lastTrimMs = now;
    // Busy = played within its length + margin (by the same clock as
    // lastPlayedMs, so a pool is never disposed under a ringing copy). A
    // preloaded pool that never played is not busy (S7-11).
    bool evictable(MapEntry<Sfx, SfxPool> e) =>
        !_pinned(e.key) && !_ringing(e.value, now);
    final stale = _pools.entries
        .where(
          (e) =>
              evictable(e) &&
              now - e.value.lastUsedMs >= Config.sfxPoolIdleDisposeMs,
        )
        .map((e) => e.key)
        .toList();
    stale.forEach(_evict);
    if (_pools.length <= Config.sfxMaxLivePools) return;
    // The latest preload (the ride about to happen) is kept (S7-11).
    final lru =
        _pools.entries
            .where((e) => evictable(e) && !_reserved.contains(e.key))
            .toList()
          ..sort((a, b) => a.value.lastUsedMs.compareTo(b.value.lastUsedMs));
    for (final e in lru) {
      if (_pools.length <= Config.sfxMaxLivePools) break;
      _evict(e.key);
    }
  }

  void _evict(Sfx sfx) {
    _runEnded.remove(sfx);
    final pool = _pools.remove(sfx);
    if (pool == null) return;
    _creating.remove(sfx);
    evictions++;
    unawaited(pool.dispose());
  }

  static Future<void> _discard(SfxVoice voice) async {
    try {
      await voice.dispose();
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  /// iOS round 2b: whether the app is active (foreground, not inactive /
  /// locked). The game sets it from the lifecycle. While false, no audio
  /// player is created ([_ensurePool], [_initPools]) and a rebuild only
  /// drops the dead players and is deferred ([rebuildPending]).
  bool get appActive => _appActive;
  bool _appActive = true;

  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    // A deferred rebuild (iOS) recreates everything itself.
    if (active && !_rebuildPending) unawaited(_healPools());
  }

  /// A rebuild was asked for while the app was not active (iOS: a
  /// media-services reset in the background): it runs once, on the return
  /// to the foreground, however many resets came meanwhile.
  bool get rebuildPending => _rebuildPending;
  bool _rebuildPending = false;
  String? _pendingReason;

  /// A rebuild is running now (later requests fold into it).
  bool get rebuilding => _rebuildRun != null;
  Future<void>? _rebuildRun;

  /// iOS round 2 §2: disposes every sound-effect pool and creates the core
  /// and session sets again (fresh native players), keeping the loops and
  /// the music. iOS: after a media-services reset (every AVPlayer is
  /// invalid) and on the return from a long background (a player whose item
  /// failed while the app was suspended plays nothing and never says so).
  /// The global audio context is applied again first.
  ///
  /// Round 2b (device log: a reset every ~7 s while rebuilding ~90 players
  /// in the background): while the app is not active only the dead
  /// players are disposed and the rebuild is deferred to the foreground
  /// (`FS-Audio rebuild deferred (background)`); a request while a rebuild
  /// runs folds into it.
  Future<void> rebuildVoices(String reason) async {
    if (!_appActive) {
      deferredRebuilds++;
      if (!_rebuildPending) {
        diag('FS-Audio rebuild deferred (background): $reason');
      }
      _rebuildPending = true;
      _pendingReason ??= reason;
      if (enabled) await _dropPools();
      return;
    }
    final running = _rebuildRun;
    if (running != null) {
      diag('FS-Audio rebuild folded into the running one ($reason)');
      return running;
    }
    final pending = _pendingReason;
    final why = pending == null ? reason : '$reason; deferred: $pending';
    _rebuildPending = false;
    _pendingReason = null;
    final run = _rebuild(why);
    _rebuildRun = run;
    try {
      await run;
    } finally {
      _rebuildRun = null;
    }
  }

  Future<void> _rebuild(String reason) async {
    rebuilds++;
    if (!enabled) return;
    diag('FS-Audio rebuild voices ($reason): ${debugStats()}');
    await _dropPools();
    if (muted || !_appActive) return;
    if (_sessionPinned) {
      await warmSession();
    } else {
      await _initPools();
    }
    diag('FS-Audio rebuild voices done ($reason): ${debugStats()}');
  }

  /// Adds voices to [pool] up to its capacity while the app is active and
  /// [gen] is current (stops at the first voice that fails).
  Future<void> _fillVoices(SfxPool pool, int gen) async {
    while (!pool.disposed && pool.voiceCount < pool.capacity && _appActive) {
      final voice = await _newVoice(pool.file);
      if (voice == null) return;
      if (gen != _generation) {
        unawaited(_discard(voice));
        return;
      }
      if (!pool.add(voice)) {
        await voice.dispose(); // evicted meanwhile
        return;
      }
    }
  }

  /// Back to active: the parts of the warm-up the inactive app skipped
  /// (core set, pinned session set, pools short of voices) are made up,
  /// one by one. Nothing to do when nothing was skipped.
  Future<void> _healPools() async {
    if (!enabled || muted) return;
    final gen = _generation;
    await _initPools();
    if (_sessionPinned) await warmSession();
    for (final pool in List.of(_pools.values)) {
      if (gen != _generation || !_appActive) return;
      if (pool.voiceCount < pool.capacity && !pool.disposed) {
        await _fillVoices(pool, gen);
      }
    }
  }

  /// Disposes every pool (no new player is created).
  Future<void> _dropPools() async {
    _generation++;
    _poolsStarted = false;
    final pools = List.of(_pools.values);
    _pools.clear();
    _creating.clear();
    _inflight.clear();
    _pendingFirst.clear();
    _runEnded.clear();
    _failedAtMs.clear();
    _globalContext = null;
    await Future.wait(pools.map((p) => p.dispose()));
  }

  /// Full rebuilds run so far (tests / diagnostics).
  int rebuilds = 0;

  /// Rebuild requests deferred while the app was not active.
  int deferredRebuilds = 0;

  /// Teardown: disposes every pool and loop (never needed in a normal
  /// session; tests and the soak use it).
  ///
  /// S7-10: creations still loading are invalidated ([_generation]): they
  /// publish nothing and dispose what they created, and the core warm-up
  /// stops. A later [play] / [preload] starts afresh.
  Future<void> dispose() async {
    _generation++;
    _poolsStarted = false;
    final pools = List.of(_pools.values);
    _pools.clear();
    _creating.clear();
    _inflight.clear();
    _pendingFirst.clear();
    _reserved = const {};
    _runEnded.clear();
    _sessionPinned = false;
    await stopAllLoops();
    await Future.wait(pools.map((p) => p.dispose()));
  }

  /// Starts the looping background music. Idempotent: only the first
  /// successful call starts playback; later calls only re-apply the holds
  /// (PRD-2.2 §28: ads, interruptions, the player's own music, the
  /// background). No plugin call when [enabled] is false.
  Future<void> startMusic() async {
    _musicWanted = true;
    await _syncMusic();
    if (enabled) unawaited(_initPools());
  }

  // region PRD-2.2 §28 — audio around ads, death and other apps

  /// Open [suspend]s (reference-counted like the game's `_adsShowing`).
  int _suspends = 0;

  /// §28.3 a call / alarm / assistant of another app holds the audio.
  bool _interrupted = false;

  /// §28.3 the player's own music was playing at launch / foreground: the
  /// game skips its own music until the next scene change finds it quiet.
  bool _ownMusicSkipped = false;

  /// The app is not in the foreground (the music pauses, as Bgm's observer
  /// did before §28 took the music lifecycle over).
  bool _background = false;

  /// [startMusic] was called (the game wants its music).
  bool _musicWanted = false;

  /// The music player is playing right now (logical; also when disabled).
  bool _musicActive = false;

  /// The track was loaded once: later starts are resumes (position kept).
  bool _musicLoaded = false;

  /// Serialises the music plugin calls.
  Future<void> _musicOps = Future<void>.value();

  /// Sound effects dropped while silenced (tests / diagnostics).
  int droppedPlays = 0;

  /// Test seam: every sound that passed the mute and silence gates (also
  /// when [enabled] is false).
  void Function(Sfx sfx)? onAudible;

  /// Test seam: the music transitions (`start`, `pause`, `resume`), also
  /// when [enabled] is false.
  void Function(String event)? onMusic;

  /// PRD-2.3 §13.4: another app's notification sound (or a short media
  /// sound that started while the game is in the foreground) is playing:
  /// the music pauses, the sound effects keep playing.
  bool _otherSound = false;

  /// PRD-2.3 §13.3: the music diagnostic log.
  final MusicLog musicLog = MusicLog();

  /// PRD-2.3 §13.3: the last `AudioWatch` answer for the log (set by the
  /// game's music guard).
  String Function()? musicWatchLine;

  /// Test seam (PRD-2.3 §13.5): the music player's real state instead of
  /// audioplayers' (`playing`, `paused`, `stopped`, `completed`,
  /// `disposed`, `none`).
  String Function()? musicStateProbe;

  /// [startMusic] was called (the game wants its music).
  bool get musicWanted => _musicWanted;

  /// §13.4 a notification sound holds the music.
  bool get otherSound => _otherSound;

  /// The app is not in the foreground (the music is held).
  bool get background => _background;

  /// The music player's real state (PRD-2.3 §13.3 / §13.4 watchdog):
  /// `none` until the music was started for real.
  String get musicPlayerState {
    final probe = musicStateProbe;
    if (probe != null) return probe();
    if (!enabled || !_musicStarted) return 'none';
    try {
      return musicBackend.state;
    } catch (_) {
      return 'none';
    }
  }

  MusicBackend? _musicBackend;

  /// PRD-2.3 §16.4: the music player (Android: just_audio; iOS: the
  /// runner's `LoopMusic`; Linux: audioplayers' `FlameAudio.bgm`).
  /// Replaceable in tests.
  MusicBackend get musicBackend => _musicBackend ??= MusicBackend.forPlatform(
    audioContext: () =>
        FlameAudio.bgm.audioPlayer.setAudioContext(gameAudioContext()),
  );

  @visibleForTesting
  set musicBackend(MusicBackend backend) => _musicBackend = backend;

  /// PRD-2.3 §13.2 `music_held` reason of the current hold (null = not
  /// held). Background first, then an ad, an interruption or a
  /// notification, then the player's own music.
  String? get musicHoldReason {
    if (_background) return 'background';
    if (_suspends > 0) return 'suspend';
    if (_interrupted || _otherSound) return 'interrupted';
    if (_ownMusicSkipped) return 'own_music';
    return null;
  }

  String get _flags =>
      'susp=$_suspends int=${_interrupted ? 1 : 0} '
      'own=${_ownMusicSkipped ? 1 : 0} bg=${_background ? 1 : 0} '
      'notif=${_otherSound ? 1 : 0} want=${_musicWanted ? 1 : 0} '
      'on=${_musicActive ? 1 : 0}';

  /// PRD-2.3 §13.3: one diagnostic log entry.
  void logMusic(String event) {
    String watch;
    try {
      watch = musicWatchLine?.call() ?? '-';
    } catch (_) {
      watch = '-';
    }
    musicLog.add(
      MusicLogEntry(
        time: DateTime.now(),
        event: event,
        flags: _flags,
        watch: watch,
        player: musicPlayerState,
      ),
    );
  }

  /// §28.2 a full-screen ad is up.
  bool get suspended => _suspends > 0;

  /// §28.3 another app's call / alarm / assistant holds the audio.
  bool get interrupted => _interrupted;

  /// §28.3 the player's own music plays: the game music stays off.
  bool get ownMusicSkipped => _ownMusicSkipped;

  /// The game music is playing now (logical state).
  bool get musicPlaying => _musicActive;

  bool get _sfxSilenced => _suspends > 0 || _interrupted;

  bool get _musicHeld =>
      _suspends > 0 ||
      _interrupted ||
      _ownMusicSkipped ||
      _background ||
      _otherSound;

  /// §28.2 a full-screen ad is shown: the music pauses (position kept),
  /// every loop stops and every [play] is dropped until [resume].
  void suspend() {
    _suspends++;
    logMusic('suspend');
    if (_suspends == 1) {
      _pendingFirst.clear();
      _stopOneShots();
      unawaited(stopAllLoops());
      unawaited(_syncMusic());
    }
  }

  /// Monotonic ms until which the game's own one-shots may still be on the
  /// music stream (S7-13).
  int _ownSoundUntilMs = -1;

  void _markOwnSound(Sfx sfx) {
    final file = _files[sfx];
    if (file == null) return;
    final until =
        _nowMs +
        lengthOf(file).inMilliseconds +
        Config.sfxStopMarginMs +
        (Config.ownMusicRecheckDelay * 1000).round();
    if (until > _ownSoundUntilMs) _ownSoundUntilMs = until;
  }

  /// PRD-2.2 §28.3 (S7-13): the game's own sound may be on the music stream
  /// right now: a one-shot played within its length + margin +
  /// [Config.ownMusicRecheckDelay], or a loop (FEVER crackle, comet, …)
  /// is running. Android's `isMusicActive()` fallback cannot tell it from
  /// another app's music, so an "other music" answer is then confirmed by
  /// the playback list alone (`AudioFocus.isOtherMediaListed`).
  bool get ownSoundRecent =>
      _nowMs < _ownSoundUntilMs || _loops.any((l) => !l.stopped);

  /// §28.2 / §28.3 (S7-09): the one-shots already ringing stop when an ad
  /// shows or an interruption starts (§28.1's "one-shots finish" is for a
  /// death only). Not resumed afterwards.
  void _stopOneShots() {
    for (final p in _pools.values) {
      p.stopAll();
    }
  }

  /// §28.2 the ad closed (dismissed / failed to show): SFX allowed again,
  /// the music resumes from where it was. Interrupted loops do not come
  /// back by themselves (each feature restarts its own).
  void resume() {
    if (_suspends == 0) return;
    _suspends--;
    logMusic('resume-ad');
    if (_suspends == 0) unawaited(_syncMusic());
  }

  /// §28.2 safety: a suspend without its resume (ad SDK crash) is cleared
  /// on the next app resume / scene change.
  void clearSuspend() {
    if (_suspends == 0) return;
    _suspends = 0;
    logMusic('clear-suspend');
    unawaited(_syncMusic());
  }

  /// §28.3 transient audio loss from another app (call, alarm, assistant):
  /// the music pauses and the sound effects (loops included) go quiet
  /// until it ends; then the music resumes.
  void setInterrupted(bool on) {
    if (_interrupted == on) return;
    _interrupted = on;
    logMusic(on ? 'interrupt' : 'interrupt-end');
    if (on) {
      _pendingFirst.clear();
      _stopOneShots();
    }
    for (final l in List.of(_loops)) {
      unawaited(l.applyQuiet(on));
    }
    unawaited(_syncMusic());
  }

  /// §28.3 the player's own music is playing ([active], checked at launch
  /// and on foreground): the game skips its music. A quiet check only
  /// re-enables it when [sceneChange] is set (Home / run start, never
  /// mid-run).
  ///
  /// PRD-2.3 §13.4: the menu re-check (every 2 s while skipped on a menu)
  /// counts as a scene change.
  void setOtherMusicActive(bool active, {bool sceneChange = false}) {
    if (active) {
      if (_ownMusicSkipped) return;
      _ownMusicSkipped = true;
    } else {
      if (!_ownMusicSkipped || !sceneChange) return;
      _ownMusicSkipped = false;
    }
    logMusic(active ? 'skip' : 'unskip');
    unawaited(_syncMusic());
  }

  /// PRD-2.3 §13.4: another app's notification sound plays ([on]): the
  /// music pauses (position kept) and resumes when it ends. Sound effects
  /// are not affected (a notification is not a call).
  void setOtherSound(bool on) {
    if (_otherSound == on) return;
    _otherSound = on;
    logMusic(on ? 'notify' : 'notify-end');
    unawaited(_syncMusic());
  }

  /// PRD-2.3 §13.4 music watchdog: the game thinks the music plays but the
  /// player is not playing (stopped, released, errored). The music restarts
  /// from the start of the loop; logged as `player_dead`.
  Future<void> restartMusic() {
    logMusic('player_dead');
    if (!_musicActive) return _syncMusic();
    _musicActive = false;
    _musicLoaded = false;
    if (enabled) {
      _musicOps = _musicOps.then((_) => _musicCall('stop'));
    }
    return _syncMusic();
  }

  /// The app left / came back to the foreground (the game owns the music
  /// lifecycle since §28: no Bgm observer, so a foreground check can run
  /// before the music comes back).
  void setBackground(bool background) {
    if (_background == background) return;
    _background = background;
    logMusic(background ? 'background' : 'foreground');
    unawaited(_syncMusic());
  }

  Future<void> _syncMusic() {
    final want = _musicWanted && !_musicHeld;
    if (want == _musicActive) return _musicOps;
    _musicActive = want;
    final event = want ? (_musicLoaded ? 'resume' : 'start') : 'pause';
    if (want) _musicLoaded = true;
    onMusic?.call(event);
    logMusic(event);
    if (!enabled) return _musicOps;
    if (kDebugMode) {
      debugPrint(
        'Sound: music $event (suspends $_suspends, interrupted '
        '$_interrupted, own music $_ownMusicSkipped, background $_background)',
      );
    }
    return _musicOps = _musicOps.then((_) => _musicCall(event));
  }

  Future<void> _musicCall(String event) async {
    try {
      // PRD-2.3 §16.4: the plugin calls go through the music backend.
      final music = musicBackend;
      switch (event) {
        case 'start':
          _musicStarted = true;
          await music.start(
            _musicFile,
            volume: _musicVolume * _musicDuck,
            rate: _musicRate,
          );
        case 'pause':
          await music.pause();
        case 'resume':
          await music.resume();
        case 'stop':
          // PRD-2.3 §13.4 watchdog: the next 'start' plays from the top.
          await music.stop();
      }
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
  // endregion PRD-2.2 §28

  /// Stores the music volume (clamped to 0..1) and applies it live when
  /// music is playing. Never touches the plugin when [enabled] is false.
  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0).toDouble();
    if (!enabled || !_musicStarted) {
      return;
    }
    try {
      await musicBackend.setVolume(_musicVolume * _musicDuck);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  // region WP-0b — loop API, music rate and duck (PRD-2 §3.9, §3.30, §5.16)

  /// Test seam: called with every requested loop (also when disabled).
  void Function(SfxLoop loop, double volume)? onLoop;

  final List<_LoopPlayer> _loops = [];

  NativeSfxLoops? _nativeLoops;

  /// iOS round 2 §3: the seamless native loop player on iOS (null
  /// elsewhere, and with fake voices in tests). Replaceable in tests.
  NativeSfxLoops? get nativeLoops {
    if (_nativeLoopsSet) return _nativeLoops;
    if (voiceFactory != null || kIsWeb || !Platform.isIOS) return null;
    return _nativeLoops ??= NativeSfxLoops();
  }

  bool _nativeLoopsSet = false;

  @visibleForTesting
  set nativeLoops(NativeSfxLoops? loops) {
    _nativeLoopsSet = true;
    _nativeLoops = loops;
  }

  /// Loops currently playing (or recorded, when disabled).
  List<LoopHandle> get activeLoops =>
      _loops.where((l) => !l.stopped).toList(growable: false);

  /// Starts [l] looping at [volume] on its own low-latency player (BGM
  /// style, never `FlameAudio.play`). SFX mute applies: a muted service
  /// returns a silent handle. Disabled (tests): a recording no-op handle.
  LoopHandle loop(SfxLoop l, {double volume = 1}) {
    onLoop?.call(l, volume);
    // PRD-2.2 §28.2: no loop starts while a full-screen ad is up.
    final live = enabled && !muted && _suspends == 0;
    final handle = _LoopPlayer(
      l,
      volume,
      live,
      live ? _ensureGlobalContext : null,
      live ? nativeLoops : null,
    ).._quiet = _interrupted;
    if (_suspends > 0) {
      // Born stopped: the feature sees `stopped` and asks again after the
      // ad (interrupted loops never resume by themselves).
      handle._stopped = true;
      return handle;
    }
    _loops.add(handle);
    _loops.removeWhere((x) => x.stopped && !identical(x, handle));
    if (handle.live) unawaited(handle.start());
    return handle;
  }

  /// Stops every loop (end of a run, pause, PRD-2.2 §28.1 the moment of
  /// death, §28.2 a full-screen ad). Every handle is stopped at once
  /// (synchronously marked), then the players are awaited.
  Future<void> stopAllLoops() async {
    final all = List.of(_loops);
    _loops.clear();
    stopAllLoopsCalls++;
    await Future.wait(all.map((l) => l.stop()));
  }

  /// [stopAllLoops] calls so far (PRD-2.2 §28.5 tests).
  int stopAllLoopsCalls = 0;

  double _musicRate = 1;
  double _musicDuck = 1;

  double get musicRate => _musicRate;
  double get musicDuck => _musicDuck;

  /// §3.30 Hourglass: the music plays at [rate] (≈ 0.72).
  Future<void> setMusicRate(double rate) async {
    _musicRate = rate;
    if (!enabled || !_musicStarted) return;
    try {
      await musicBackend.setRate(rate);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  /// §5.9 GET COINS: the music at [factor] × its volume (1 = normal).
  Future<void> duckMusic(double factor) async {
    _musicDuck = factor.clamp(0.0, 1.0).toDouble();
    if (!enabled || !_musicStarted) return;
    try {
      await musicBackend.setVolume(_musicVolume * _musicDuck);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
  // endregion WP-0b
}

class _LoopPlayer implements LoopHandle {
  _LoopPlayer(this.loop, this._volume, this.live, this._context, this._native);

  /// Awaits the service's global audio context (PRD-2.2 §33: no
  /// per-player context).
  final Future<void> Function()? _context;

  /// iOS round 2 §3: the runner's seamless loop player (iOS), else null.
  final NativeSfxLoops? _native;
  int? _nativeId;

  @override
  final SfxLoop loop;
  double _volume;

  /// False when the service is disabled / muted: a silent recorder.
  final bool live;
  AudioPlayer? _player;
  bool _stopped = false;

  /// PRD-2.2 §28.3 interrupted: plays at volume 0, [_volume] kept.
  bool _quiet = false;

  Future<void> applyQuiet(bool quiet) async {
    _quiet = quiet;
    final id = _nativeId;
    if (id != null) {
      _native?.setVolume(id, quiet ? 0 : _volume);
      return;
    }
    try {
      await _player?.setVolume(quiet ? 0 : _volume);
    } catch (_) {}
  }

  @override
  bool get stopped => _stopped;

  @override
  double get volume => _volume;

  @override
  bool get audible => live;

  Future<void> start() async {
    final native = _native;
    if (native != null) {
      if (_stopped) return;
      _nativeId = native.start(loop.file, _quiet ? 0 : _volume);
      return;
    }
    try {
      await _context?.call();
      if (_stopped) return;
      final p = AudioPlayer()..audioCache = FlameAudio.audioCache;
      // PRD-2.2 §33.4 item 2: loops never poll their position.
      p.positionUpdater = null;
      _player = p;
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.loop);
      if (_stopped) {
        await p.dispose();
        return;
      }
      await p.play(AssetSource(loop.file), volume: _quiet ? 0 : _volume);
      if (_stopped) await p.stop();
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    final id = _nativeId;
    if (id != null) {
      _native?.setVolume(id, _quiet ? 0 : volume);
      return;
    }
    try {
      await _player?.setVolume(_quiet ? 0 : volume);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final id = _nativeId;
    _nativeId = null;
    if (id != null) {
      await _native?.stop(id);
      return;
    }
    final p = _player;
    _player = null;
    if (p == null) return;
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}
