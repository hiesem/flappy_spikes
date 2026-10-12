package com.flappyspikes.flappy_spikes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var audioWatch: AudioWatch? = null
    private var debugReceiver: BroadcastReceiver? = null
    private var debugPlayer: android.media.MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // PRD-2.2 §8 / S7-20: the game is the only back consumer. With
        // predictive back (targetSdk 36) the system finishes the activity
        // unless the engine's OnBackInvokedCallback is registered, and the
        // engine only registers it when the framework claims back (normally
        // WidgetsApp, which this game does not use). Claim it here, before
        // Dart runs; the Dart side (SystemBackObserver.install) claims it
        // again and every back lands in FlappySpikesGame.handleSystemBack.
        setFrameworkHandlesBack(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Play pre-launch reports and Firebase Test Lab run on devices that
        // set this system setting; AdMobRewardedAds never loads ads there
        // (robot taps on real ads count as invalid traffic).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTestLab" -> result.success(
                        Settings.System.getString(contentResolver, "firebase.test.lab") == "true"
                    )
                    else -> result.notImplemented()
                }
            }

        // PRD-2.2 §28.3: other apps' audio, observed without requesting
        // audio focus (the game mixes with the player's own music). See
        // docs/p22/ADS.md "§28 audio focus".
        val watch = AudioWatch(getSystemService(Context.AUDIO_SERVICE) as AudioManager)
        audioWatch = watch
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isOtherMusicActive" -> result.success(watch.otherMusicActive())
                    "isOtherMediaListed" -> result.success(watch.otherMediaListed())
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/audio_interruptions")
            .setStreamHandler(watch)

        // Debug builds only: `adb shell am broadcast -a
        // com.flappyspikes.DEBUG_RINGTONE` plays the default ringtone for
        // 6 s with ringtone usage, to exercise the §28.3 interruption path
        // on a device without placing a call; `…DEBUG_MEDIA` plays it 20 s
        // with media usage (stands in for the player's own music).
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    try {
                        // DEBUG_MEDIA: the same tone as "someone else's
                        // music" (USAGE_MEDIA, 20 s) for the own-music check.
                        val media = intent.action == "com.flappyspikes.DEBUG_MEDIA"
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        if (media) {
                            // A plain MediaPlayer: Ringtone skips playing
                            // while the stream volume is 0.
                            val mp = android.media.MediaPlayer()
                            mp.setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .build()
                            )
                            mp.setDataSource(context, uri)
                            mp.isLooping = true
                            mp.prepare()
                            mp.start()
                            debugPlayer = mp // keep it from the GC
                            Handler(Looper.getMainLooper()).postDelayed(
                                { mp.stop(); mp.release(); debugPlayer = null },
                                20000L,
                            )
                            return
                        }
                        val tone = RingtoneManager.getRingtone(context, uri)
                        tone.audioAttributes = AudioAttributes.Builder()
                            .setUsage(
                                if (media) AudioAttributes.USAGE_MEDIA
                                else AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                            )
                            .build()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) tone.isLooping = media
                        tone.play()
                        Handler(Looper.getMainLooper()).postDelayed(
                            { tone.stop() },
                            if (media) 20000L else 6000L,
                        )
                    } catch (_: Exception) {
                    }
                }
            }
            val filter = IntentFilter("com.flappyspikes.DEBUG_RINGTONE").apply {
                addAction("com.flappyspikes.DEBUG_MEDIA")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(r, filter)
            }
            debugReceiver = r
        }
    }

    override fun onDestroy() {
        audioWatch?.onCancel(null)
        debugReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }
}

/**
 * PRD-2.2 §28.3. The game's own players use USAGE_GAME (SoundService
 * `gameAudioContext`), so every other active player belongs to another app
 * (or the system):
 * - USAGE_MEDIA / UNKNOWN playing = the player's own music (or a video);
 * - a call / ringtone / alarm / assistant playing, or the audio mode in a
 *   call or ringing = a transient interruption.
 * Nothing here requests audio focus.
 */
class AudioWatch(private val am: AudioManager) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var last: Boolean? = null
    private var playbackCallback: AudioManager.AudioPlaybackCallback? = null
    private var modeListener: AudioManager.OnModeChangedListener? = null

    private val interruptUsages = setOf(
        AudioAttributes.USAGE_ALARM,
        AudioAttributes.USAGE_NOTIFICATION_RINGTONE,
        AudioAttributes.USAGE_VOICE_COMMUNICATION,
        AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
        AudioAttributes.USAGE_ASSISTANT,
    )

    private fun active(): List<AudioAttributes> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                am.activePlaybackConfigurations.map { it.audioAttributes }
            } catch (_: Exception) {
                emptyList()
            }
        } else {
            emptyList()
        }

    fun otherMusicActive(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return try { am.isMusicActive } catch (_: Exception) { false }
        }
        // The public playback list hides muted players (e.g. media volume 0
        // on the Pixel 8), so isMusicActive() backs it up. The Dart side
        // only asks while the game's own music is not playing (at launch
        // before it starts, on foreground before it resumes, while skipped).
        return otherMediaListed() || try { am.isMusicActive } catch (_: Exception) { false }
    }

    /// Only the public playback list: another app's (unmuted) media player.
    /// Never the game's own players (USAGE_GAME). The Dart side asks this
    /// when the game's own sound may be on the music stream (S7-13).
    fun otherMediaListed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return try { am.isMusicActive } catch (_: Exception) { false }
        }
        return active().any {
            it.usage == AudioAttributes.USAGE_MEDIA || it.usage == AudioAttributes.USAGE_UNKNOWN
        }
    }

    private fun interrupted(): Boolean {
        val mode = try { am.mode } catch (_: Exception) { AudioManager.MODE_NORMAL }
        if (mode == AudioManager.MODE_RINGTONE ||
            mode == AudioManager.MODE_IN_CALL ||
            mode == AudioManager.MODE_IN_COMMUNICATION
        ) {
            return true
        }
        return active().any { it.usage in interruptUsages }
    }

    private fun report() {
        val now = interrupted()
        if (now == last) return
        last = now
        sink?.success(now)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        last = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && playbackCallback == null) {
            val cb = object : AudioManager.AudioPlaybackCallback() {
                override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>?) {
                    report()
                }
            }
            playbackCallback = cb
            try {
                am.registerAudioPlaybackCallback(cb, main)
            } catch (_: Exception) {
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && modeListener == null) {
            val l = AudioManager.OnModeChangedListener { report() }
            modeListener = l
            try {
                am.addOnModeChangedListener({ main.post(it) }, l)
            } catch (_: Exception) {
            }
        }
        report()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            playbackCallback?.let {
                try { am.unregisterAudioPlaybackCallback(it) } catch (_: Exception) {}
            }
        }
        playbackCallback = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modeListener?.let {
                try { am.removeOnModeChangedListener(it) } catch (_: Exception) {}
            }
        }
        modeListener = null
    }
}
