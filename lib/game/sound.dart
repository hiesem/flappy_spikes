import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'audio_counter.dart';
import 'config.dart';
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

  static const String _musicFile = 'HappyBeat_8-Bit_Retro_Game_Loop.mp3';

  bool muted;

  /// Master switch for audio output. Headless tests set this to false so no
  /// calls reach the audioplayers platform channel (which has no test
  /// backend and would throw [MissingPluginException]).
  bool enabled;

  double _musicVolume = Config.defaultMusicVolume;
  bool _musicStarted = false;
  bool _bgmInitialized = false;

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

  /// First plays of lazily created pools, waiting for their pool (when the
  /// request was made).
  final Map<Sfx, DateTime> _pendingFirst = {};

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
    if (muted || !enabled) {
      return;
    }
    final pool = _pools[sfx];
    // While the pool is missing the sound is not played now. A bare
    // FlameAudio.play here would spawn a fresh one-shot AudioPlayer, which
    // the project bans (CLAUDE.md: preloaded low-latency pools only).
    if (pool == null) {
      unawaited(_initPools());
      if (!prewarmed.contains(sfx) && !_creating.containsKey(sfx)) {
        // First request of a lazy pool: create it and play this request
        // once it is ready (if that is quick enough).
        _pendingFirst[sfx] = DateTime.now();
        unawaited(_ensurePool(sfx));
      }
      return;
    }
    pool.play(_nowMs);
    if (_nowMs - _lastTrimMs >= Config.sfxTrimIntervalMs) _trimPools();
  }

  /// PRD-2.2 §18.4: creates the pools of [cues] without playing them (e.g.
  /// a portal's ride cues when the portal spawns), so their first [play] is
  /// heard. Marks existing pools as used (no eviction right before use).
  void preload(Iterable<Sfx> cues) {
    if (muted || !enabled) return;
    unawaited(_initPools());
    for (final sfx in cues) {
      final pool = _pools[sfx];
      if (pool != null) {
        pool.lastUsedMs = _nowMs;
      } else {
        unawaited(_ensurePool(sfx));
      }
    }
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

  /// Sets the one global audio context (mixWithOthers: no audio-focus
  /// request, no AudioManager mode write per player; PERF.md §5). Awaited
  /// before any SFX / loop player is created, so each player inherits it.
  Future<void>? _globalContext;
  Future<void> _ensureGlobalContext() => _globalContext ??= () async {
    if (voiceFactory != null) return; // fake voices: no plugin
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }();

  /// Warms up the [prewarmed] pools once. No-op when [enabled] is false
  /// (tests) and idempotent afterwards; while it runs (or after a failure)
  /// [play] simply drops those sounds instead of opening a one-shot player.
  Future<void> _initPools() async {
    if (!enabled || _poolsStarted) {
      return;
    }
    _poolsStarted = true;
    for (final sfx in prewarmed) {
      await _ensurePool(sfx);
    }
  }

  Future<void> _ensurePool(Sfx sfx) =>
      _creating.putIfAbsent(sfx, () => _createPool(sfx));

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
    try {
      await _ensureGlobalContext();
      final pool = SfxPool(
        file: file,
        length: length,
        capacity: voicesFor(sfx),
        stopMargin: const Duration(milliseconds: Config.sfxStopMarginMs),
        nowMs: _nowMs,
      )..onStopped = debugOnStop;
      final first = await _newVoice(file);
      if (first == null) return; // never became ready: stay silent
      pool.add(first);
      _pools[sfx] = pool;
      final asked = _pendingFirst.remove(sfx);
      if (asked != null &&
          enabled &&
          !muted &&
          DateTime.now().difference(asked) <= firstPlayLateLimit) {
        pool.play(_nowMs);
      }
      _trimPools();
      while (!pool.disposed && pool.voiceCount < pool.capacity) {
        final voice = await _newVoice(file);
        if (voice == null) break;
        if (!pool.add(voice)) {
          await voice.dispose(); // evicted meanwhile
          break;
        }
      }
    } catch (_) {
      // Audio failure must never take the game down. One bad pool must not
      // stop the remaining sounds from warming up either.
    } finally {
      _pendingFirst.remove(sfx);
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
    // lastUsedMs, so a pool is never disposed under a ringing copy).
    bool evictable(MapEntry<Sfx, SfxPool> e) =>
        !prewarmed.contains(e.key) &&
        now - e.value.lastUsedMs >=
            e.value.length.inMilliseconds + Config.sfxStopMarginMs;
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
    final lru = _pools.entries.where(evictable).toList()
      ..sort((a, b) => a.value.lastUsedMs.compareTo(b.value.lastUsedMs));
    for (final e in lru) {
      if (_pools.length <= Config.sfxMaxLivePools) break;
      _evict(e.key);
    }
  }

  void _evict(Sfx sfx) {
    final pool = _pools.remove(sfx);
    if (pool == null) return;
    _creating.remove(sfx);
    evictions++;
    unawaited(pool.dispose());
  }

  /// Teardown: disposes every pool and loop (never needed in a normal
  /// session; tests and the soak use it).
  Future<void> dispose() async {
    final pools = List.of(_pools.values);
    _pools.clear();
    _creating.clear();
    await stopAllLoops();
    await Future.wait(pools.map((p) => p.dispose()));
  }

  /// Starts the looping background music. Idempotent: only the first
  /// successful call starts playback. No-op when [enabled] is false.
  Future<void> startMusic() async {
    if (!enabled || _musicStarted) {
      return;
    }
    try {
      if (!_bgmInitialized) {
        // Registers Bgm's WidgetsBinding observer so the music pauses when
        // the app backgrounds and resumes on foreground.
        await FlameAudio.bgm.initialize();
        // PRD-2.2 §33.4 item 2: the music never polls its position (it
        // polled 60×/s all session, also on Home).
        FlameAudio.bgm.audioPlayer.positionUpdater = null;
        _bgmInitialized = true;
      }
      await FlameAudio.bgm.play(_musicFile, volume: _musicVolume);
      _musicStarted = true;
    } catch (_) {
      // Audio failure must never take the game down.
    }
    unawaited(_initPools());
  }

  /// Stores the music volume (clamped to 0..1) and applies it live when
  /// music is playing. Never touches the plugin when [enabled] is false.
  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0).toDouble();
    if (!enabled || !_musicStarted) {
      return;
    }
    try {
      await FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  // region WP-0b — loop API, music rate and duck (PRD-2 §3.9, §3.30, §5.16)

  /// Test seam: called with every requested loop (also when disabled).
  void Function(SfxLoop loop, double volume)? onLoop;

  final List<_LoopPlayer> _loops = [];

  /// Loops currently playing (or recorded, when disabled).
  List<LoopHandle> get activeLoops =>
      _loops.where((l) => !l.stopped).toList(growable: false);

  /// Starts [l] looping at [volume] on its own low-latency player (BGM
  /// style, never `FlameAudio.play`). SFX mute applies: a muted service
  /// returns a silent handle. Disabled (tests): a recording no-op handle.
  LoopHandle loop(SfxLoop l, {double volume = 1}) {
    onLoop?.call(l, volume);
    final handle = _LoopPlayer(
      l,
      volume,
      enabled && !muted,
      enabled && !muted ? _ensureGlobalContext : null,
    );
    _loops.add(handle);
    _loops.removeWhere((x) => x.stopped && !identical(x, handle));
    if (handle.live) unawaited(handle.start());
    return handle;
  }

  /// Stops every loop (end of a run, pause).
  Future<void> stopAllLoops() async {
    for (final l in List.of(_loops)) {
      await l.stop();
    }
    _loops.clear();
  }

  double _musicRate = 1;
  double _musicDuck = 1;

  double get musicRate => _musicRate;
  double get musicDuck => _musicDuck;

  /// §3.30 Hourglass: the music plays at [rate] (≈ 0.72).
  Future<void> setMusicRate(double rate) async {
    _musicRate = rate;
    if (!enabled || !_musicStarted) return;
    try {
      await FlameAudio.bgm.audioPlayer.setPlaybackRate(rate);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  /// §5.9 GET COINS: the music at [factor] × its volume (1 = normal).
  Future<void> duckMusic(double factor) async {
    _musicDuck = factor.clamp(0.0, 1.0).toDouble();
    if (!enabled || !_musicStarted) return;
    try {
      await FlameAudio.bgm.audioPlayer.setVolume(_musicVolume * _musicDuck);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
  // endregion WP-0b
}

class _LoopPlayer implements LoopHandle {
  _LoopPlayer(this.loop, this._volume, this.live, this._context);

  /// Awaits the service's global audio context (PRD-2.2 §33: no
  /// per-player context).
  final Future<void> Function()? _context;

  @override
  final SfxLoop loop;
  double _volume;

  /// False when the service is disabled / muted: a silent recorder.
  final bool live;
  AudioPlayer? _player;
  bool _stopped = false;

  @override
  bool get stopped => _stopped;

  @override
  double get volume => _volume;

  @override
  bool get audible => live;

  Future<void> start() async {
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
      await p.play(AssetSource(loop.file), volume: _volume);
      if (_stopped) await p.stop();
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    try {
      await _player?.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final p = _player;
    _player = null;
    if (p == null) return;
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}
