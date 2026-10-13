package com.flappyspikes.flappy_spikes

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
import android.util.Log
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
                    // PRD-2.3 §13.3 / §13.4: the polled state and the music
                    // diagnostic log (logcat tag FS-Music).
                    "snapshot" -> result.success(watch.snapshot())
                    "log" -> {
                        Log.i("FS-Music", call.arguments as? String ?: "")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/audio_interruptions")
            .setStreamHandler(watch)

        // Debug builds only: `adb shell am broadcast -a
        // com.flappyspikes.DEBUG_RINGTONE` plays the default ringtone for
        // 6 s with ringtone usage, to exercise the §28.3 interruption path
        // on a device without placing a call; `…DEBUG_MEDIA` plays it 20 s
        // with media usage (stands in for the player's own music);
        // `…DEBUG_NOTIFICATION` (PRD-2.3 §13.3) posts a heads-up notification
        // on a channel with the default notification sound: the owner's
        // "notification with sound on Home" case without a real message.
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    try {
                        if (intent.action == "com.flappyspikes.DEBUG_NOTIFICATION") {
                            postDebugNotification(context)
                            return
                        }
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
                addAction("com.flappyspikes.DEBUG_NOTIFICATION")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(r, filter)
            }
            debugReceiver = r
        }
    }

    /** PRD-2.3 §13.3: a local heads-up notification with sound (debug only). */
    private fun postDebugNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "fs_debug_sound"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channelId, "Debug: notification with sound",
                NotificationManager.IMPORTANCE_HIGH,
            )
            ch.setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            nm.createNotificationChannel(ch)
        }
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND)
        }
        val n = b.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Flappy Spikes debug")
            .setContentText("PRD-2.3 §13.3 test notification")
            .setAutoCancel(true)
            .build()
        nm.notify(4713 + (debugNotificationCount++ % 5), n)
        Log.i("FS-Music", "debug notification posted")
    }

    private var debugNotificationCount = 0

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
 * PRD-2.2 §28.3 / PRD-2.3 §13. The game's own players use USAGE_GAME
 * (SoundService `gameAudioContext`), so every other active player belongs to
 * another app (or the system):
 * - USAGE_MEDIA / UNKNOWN playing = the player's own music (or a video, or a
 *   plain-MediaPlayer notification sound: the Dart side tells them apart by
 *   how long it plays);
 * - USAGE_NOTIFICATION* playing = a notification sound (§13.4: the music
 *   pauses, the sound effects keep playing);
 * - a call / ringtone / alarm / assistant playing, or the audio mode in a
 *   call or ringing = a transient interruption.
 * §13.4: a player counts only while it is actually playing. The public list
 * also holds paused / stopped players that are not released yet; the player
 * state is read where the platform gives it (the hidden `getPlayerState`, by
 * reflection); when it cannot be read, every listed player counts and the
 * Dart side's 0.5 s re-check plus `isMusicActive()` confirm the answer.
 * Nothing here requests audio focus.
 */
class AudioWatch(private val am: AudioManager) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var last: List<Boolean>? = null
    private var playbackCallback: AudioManager.AudioPlaybackCallback? = null
    private var modeListener: AudioManager.OnModeChangedListener? = null

    private val interruptUsages = setOf(
        AudioAttributes.USAGE_ALARM,
        AudioAttributes.USAGE_NOTIFICATION_RINGTONE,
        AudioAttributes.USAGE_VOICE_COMMUNICATION,
        AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
        AudioAttributes.USAGE_ASSISTANT,
    )

    /** §13.4 notification sounds, whatever usage the sending app picked. */
    @Suppress("DEPRECATION")
    private val notificationUsages = setOf(
        AudioAttributes.USAGE_NOTIFICATION,
        AudioAttributes.USAGE_NOTIFICATION_EVENT,
        AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST,
        AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT,
        AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_DELAYED,
    )

    private val mediaUsages = setOf(AudioAttributes.USAGE_MEDIA, AudioAttributes.USAGE_UNKNOWN)

    /** `AudioPlaybackConfiguration.getPlayerState()` (hidden API). */
    private val stateMethod: java.lang.reflect.Method? = try {
        AudioPlaybackConfiguration::class.java.getMethod("getPlayerState")
    } catch (_: Throwable) {
        null
    }

    /** One listed player: its usage and whether it is playing (null = unknown). */
    private data class Player(val usage: Int, val playing: Boolean?)

    private fun players(): List<Player> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                am.activePlaybackConfigurations.map {
                    val state = try {
                        stateMethod?.invoke(it) as? Int
                    } catch (_: Throwable) {
                        null
                    }
                    // PLAYER_STATE_STARTED = 2.
                    Player(it.audioAttributes.usage, state?.let { s -> s == 2 })
                }
            } catch (_: Exception) {
                emptyList()
            }
        } else {
            emptyList()
        }

    /** Playing (or, when the state is unknown, listed) players. */
    private fun playing(): List<Player> = players().filter { it.playing != false }

    private fun musicActive(): Boolean = try { am.isMusicActive } catch (_: Exception) { false }

    fun otherMusicActive(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return musicActive()
        // The public playback list hides muted players (e.g. media volume 0
        // on the Pixel 8), so isMusicActive() backs it up. The Dart side
        // only asks while the game's own music is not playing (at launch
        // before it starts, on foreground before it resumes, while skipped).
        return otherMediaListed() || musicActive()
    }

    /// Only the public playback list: another app's (unmuted) media player
    /// that is playing. Never the game's own players (USAGE_GAME).
    fun otherMediaListed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return musicActive()
        return playing().any { it.usage in mediaUsages }
    }

    private fun modeInterrupts(): Boolean {
        val mode = try { am.mode } catch (_: Exception) { AudioManager.MODE_NORMAL }
        return mode == AudioManager.MODE_RINGTONE ||
            mode == AudioManager.MODE_IN_CALL ||
            mode == AudioManager.MODE_IN_COMMUNICATION
    }

    /** [interrupted, notification, media] of the playing players. */
    private fun flags(list: List<Player>): List<Boolean> {
        val live = list.filter { it.playing != false }
        return listOf(
            modeInterrupts() || live.any { it.usage in interruptUsages },
            live.any { it.usage in notificationUsages },
            live.any { it.usage in mediaUsages },
        )
    }

    /** PRD-2.3 §13.3 / §13.4: the full state (polled; also every event). */
    fun snapshot(): Map<String, Any> {
        val list = players()
        val f = flags(list)
        return mapOf(
            "interrupted" to f[0],
            "notification" to f[1],
            "media" to f[2],
            "musicActive" to musicActive(),
            "mode" to (try { am.mode } catch (_: Exception) { -1 }),
            "stateKnown" to (list.isEmpty() || list.all { it.playing != null }),
            // "usage:state": state 1 = playing, 0 = listed but not playing,
            // ? = unknown.
            "players" to list.map {
                "${it.usage}:${when (it.playing) { true -> "1"; false -> "0"; null -> "?" }}"
            },
        )
    }

    private fun report() {
        val snap = snapshot()
        val key = listOf(
            snap["interrupted"] as Boolean,
            snap["notification"] as Boolean,
            snap["media"] as Boolean,
        )
        if (key == last) return
        last = key
        sink?.success(snap)
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
