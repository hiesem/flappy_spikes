import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

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
  // region anchors — append below (WP-3h generated sounds)
  // endregion anchors
}

/// Looping sounds (PRD-2 §3.9, §5.16): one looping player each, owned by
/// [SoundService.loop]. Shipped as .wav so the loop is seamless (mp3
/// padding clicks) and plays on iOS too.
enum SfxLoop {
  cometLoop('pu_comet_loop.wav'),
  sqHold('sq_hold.wav'),
  // region anchors — append below (WP-3h saw hums, FEVER crackle)
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
  static const Set<Sfx> _burstPool = {Sfx.bnCoin, Sfx.skTick};

  static const String _musicFile = 'HappyBeat_8-Bit_Retro_Game_Loop.mp3';

  bool muted;

  /// Master switch for audio output. Headless tests set this to false so no
  /// calls reach the audioplayers platform channel (which has no test
  /// backend and would throw [MissingPluginException]).
  bool enabled;

  double _musicVolume = 0.6;
  bool _musicStarted = false;
  bool _bgmInitialized = false;

  /// Preloaded low-latency pools, one per SFX. Without these, FlameAudio.play
  /// creates a brand-new AudioPlayer (decoder + AudioTrack + audio-focus
  /// request) for EVERY effect — that made flap sounds laggy and churned CPU
  /// on the Pixel 8 (2026-07-22).
  ///
  /// The pools use SoundPool mode ([PlayerMode.lowLatency]): sounds are
  /// decoded ONCE at warmup and each play is a sub-millisecond queue on an
  /// open stream. The default MediaPlayer mode made every play open+close an
  /// audio route, which stalled frames on the Pixel 8 (few-frame freeze on
  /// every flap, 2026-07-22). Caveat of SoundPool mode: onPlayerComplete
  /// never fires, so [play] stops each sound after its measured duration to
  /// return the player to the pool.
  final Map<Sfx, AudioPool> _pools = {};
  final Map<Sfx, Duration> _durations = {};
  bool _poolsStarted = false;

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
    // A pool is only ready together with its stop duration (see [_initPools]);
    // while either is missing the sound is dropped and warm-up is (re)tried.
    // A bare FlameAudio.play here would spawn a fresh one-shot AudioPlayer,
    // which the project bans (CLAUDE.md: preloaded low-latency pools only), so
    // a sound requested this early is simply silent.
    final duration = _durations[sfx];
    if (pool == null || duration == null) {
      unawaited(_initPools());
      return;
    }
    unawaited(_playPool(pool, duration));
  }

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

  /// Creates the SFX pools once. No-op when [enabled] is false (tests) and
  /// idempotent afterwards; while it runs (or after a failure) [play] simply
  /// drops the sound instead of opening a one-shot player.
  Future<void> _initPools() async {
    if (!enabled || _poolsStarted) {
      return;
    }
    _poolsStarted = true;
    for (final entry in _files.entries) {
      try {
        final legacy = _legacyPool.contains(entry.key);
        final burst = _burstPool.contains(entry.key);
        final pool =
            await (poolFactory?.call(entry.value, legacy) ??
                AudioPool.create(
                  source: AssetSource(entry.value),
                  audioCache: FlameAudio.audioCache,
                  minPlayers: burst ? 3 : (legacy ? 2 : 1),
                  maxPlayers: burst ? 6 : (legacy ? 4 : 2),
                  playerMode: PlayerMode.lowLatency,
                  audioContext: AudioContextConfig(
                    focus: AudioContextConfigFocus.mixWithOthers,
                  ).build(),
                ));
        if (pool == null) continue; // never became ready: stay silent
        // Publish the pool and its stop duration TOGETHER: until the metadata
        // is known the pool is not ready and [play] keeps dropping the sound,
        // so a warm-up play can never dereference a missing duration (a
        // partially initialized pool stays silent instead).
        _durations[entry.key] =
            await pool.getDuration() ?? const Duration(milliseconds: 500);
        _pools[entry.key] = pool;
      } catch (_) {
        // Audio failure must never take the game down. One bad pool must not
        // stop the remaining sounds from warming up either.
      }
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
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
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
