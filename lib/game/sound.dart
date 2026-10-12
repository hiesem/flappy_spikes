import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';

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

  /// Low-latency pools, one per SFX. Without these, FlameAudio.play
  /// creates a brand-new AudioPlayer (decoder + AudioTrack + audio-focus
  /// request) for EVERY effect — that made flap sounds laggy and churned CPU
  /// on the Pixel 8 (2026-07-22).
  ///
  /// The pools use SoundPool mode ([PlayerMode.lowLatency]): sounds are
  /// decoded ONCE when the pool is created and each play is a
  /// sub-millisecond queue on an open stream. The default MediaPlayer mode
  /// made every play open+close an audio route, which stalled frames on the
  /// Pixel 8 (few-frame freeze on every flap, 2026-07-22). Caveat of
  /// SoundPool mode: onPlayerComplete never fires, so [play] stops each
  /// sound after its measured duration to return the player to the pool.
  ///
  /// PRD-2 has ~170 cues, so pools are created lazily (WP-P1int): only
  /// [prewarmed] warms up at start; every other pool is created on its first
  /// [play].
  final Map<Sfx, AudioPool> _pools = {};
  final Map<Sfx, Duration> _durations = {};
  bool _poolsStarted = false;

  /// One creation per sound (also when it failed: no retry storm).
  final Map<Sfx, Future<void>> _creating = {};

  /// First plays of lazily created pools, waiting for their pool (when the
  /// request was made).
  final Map<Sfx, DateTime> _pendingFirst = {};

  /// The core run sounds, warmed up at start (PRD-2 §7, WP-P1int): flap,
  /// point, the rim tonk, the perfect / streak set — plus the 1.0 game-over
  /// and the menu click, which every session plays.
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

  /// Background-music volume (0..1). Independent of [muted], which only
  /// gates sound effects.
  double get musicVolume => _musicVolume;

  /// Test seam: called with every requested sound (also when [enabled] is
  /// false), before muting applies.
  void Function(Sfx sfx)? onPlay;

  /// Test seam: builds one pool per file. Defaults to the real low-latency
  /// [AudioPool]; a test injects a factory (e.g. one returning null, a pool
  /// that never became ready) to exercise [play]'s drop path without the
  /// audioplayers plugin.
  @visibleForTesting
  Future<AudioPool?> Function(String file, bool legacy)? poolFactory;

  void play(Sfx sfx) {
    onPlay?.call(sfx);
    if (muted || !enabled) {
      return;
    }
    final pool = _pools[sfx];
    // A pool is only ready together with its stop duration (see
    // [_createPool]); while either is missing the sound is not played now.
    // A bare FlameAudio.play here would spawn a fresh one-shot AudioPlayer,
    // which the project bans (CLAUDE.md: preloaded low-latency pools only).
    final duration = _durations[sfx];
    if (pool == null || duration == null) {
      unawaited(_initPools());
      if (!prewarmed.contains(sfx) && !_creating.containsKey(sfx)) {
        // First request of a lazy pool: create it and play this request
        // once it is ready (if that is quick enough).
        _pendingFirst[sfx] = DateTime.now();
        unawaited(_ensurePool(sfx));
      }
      return;
    }
    unawaited(_playPool(pool, duration));
  }

  /// True once [sfx]'s pool creation has been started (tests).
  @visibleForTesting
  bool poolRequested(Sfx sfx) => _creating.containsKey(sfx);

  /// Plays one low-latency pool hit and returns the borrowed player after the
  /// known duration — SoundPool mode never fires onPlayerComplete, so only the
  /// timer releases it (see the `_pools` field comment).
  ///
  /// Both the start and the stop Future are error-contained: a native audio
  /// failure must never take the game down (or escape as an uncaught Future).
  Future<void> _playPool(AudioPool pool, Duration duration) async {
    try {
      final stop = await pool.start();
      Timer(duration + const Duration(milliseconds: 100), () async {
        try {
          await stop();
        } catch (_) {
          // Audio failure must never take the game down.
        }
      });
    } catch (_) {
      // A rejected start simply drops this sound.
    }
  }

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

  /// Creates [sfx]'s low-latency pool (never throws).
  Future<void> _createPool(Sfx sfx) async {
    final file = _files[sfx];
    if (file == null) return;
    try {
      final legacy = _legacyPool.contains(sfx);
      final burst = _burstPool.contains(sfx);
      final pool =
          await (poolFactory?.call(file, legacy) ??
              AudioPool.create(
                source: AssetSource(file),
                audioCache: FlameAudio.audioCache,
                minPlayers: burst ? 3 : (legacy ? 2 : 1),
                maxPlayers: burst ? 6 : (legacy ? 4 : 2),
                playerMode: PlayerMode.lowLatency,
                audioContext: AudioContextConfig(
                  focus: AudioContextConfigFocus.mixWithOthers,
                ).build(),
              ));
      if (pool == null) return; // never became ready: stay silent
      // Publish the pool and its stop duration TOGETHER: until the metadata
      // is known the pool is not ready and [play] keeps dropping the sound,
      // so a warm-up play can never dereference a missing duration (a
      // partially initialized pool stays silent instead).
      final duration =
          await pool.getDuration() ?? const Duration(milliseconds: 500);
      _durations[sfx] = duration;
      _pools[sfx] = pool;
      final asked = _pendingFirst.remove(sfx);
      if (asked != null &&
          enabled &&
          !muted &&
          DateTime.now().difference(asked) <= firstPlayLateLimit) {
        unawaited(_playPool(pool, duration));
      }
    } catch (_) {
      // Audio failure must never take the game down. One bad pool must not
      // stop the remaining sounds from warming up either.
    } finally {
      _pendingFirst.remove(sfx);
    }
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
    final handle = _LoopPlayer(l, volume, enabled && !muted);
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
  _LoopPlayer(this.loop, this._volume, this.live);

  @override
  final SfxLoop loop;
  double _volume;

  /// False when the service is disabled / muted: a silent recorder.
  final bool live;
  AudioPlayer? _player;
  bool _stopped = false;

  @override
  bool get stopped => _stopped;

  double get volume => _volume;

  Future<void> start() async {
    try {
      final p = AudioPlayer()..audioCache = FlameAudio.audioCache;
      _player = p;
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
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
