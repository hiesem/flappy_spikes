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
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/audio_interruptions")
            .setStreamHandler(watch)

        // Debug builds only: `adb shell am broadcast -a
        // com.flappyspikes.DEBUG_RINGTONE` plays the default ringtone for
        // 6 s with ringtone usage, to exercise the §28.3 interruption path
        // on a device without placing a call.
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    try {
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        val tone = RingtoneManager.getRingtone(context, uri)
                        tone.audioAttributes = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .build()
                        tone.play()
                        Handler(Looper.getMainLooper()).postDelayed({ tone.stop() }, 6000)
                    } catch (_: Exception) {
                    }
                }
            }
            val filter = IntentFilter("com.flappyspikes.DEBUG_RINGTONE")
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
