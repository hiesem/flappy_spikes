import AVFoundation
import Flutter
import UIKit
import UserNotifications
import Security
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// PRD-2.2 §28.3: the iOS side of `flappy_spikes/audio` (kept alive for
  /// the app's lifetime).
  private var audioWatch: AudioWatch?

  /// iOS round 2: the seamless music loop (`flappy_spikes/music`).
  private var loopMusic: LoopMusic?

  /// iOS round 2: the seamless sound-effect loops (`flappy_spikes/loops`).
  private var sfxLoops: SfxLoops?

  /// iOS round 2: the crisp "button click" rumble (`flappy_spikes/haptics`).
  private var haptics: Haptics?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications README, "iOS setup": reminders show while
    // the app is in the foreground and taps reach the plugin.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // The game never silences the player's own music (PRD-2.2 §28.3): the
    // ambient category mixes with other apps. audioplayers sets the same
    // category from Dart (SoundService.gameAudioContext) before any sound.
    try? AVAudioSession.sharedInstance().setCategory(.ambient)
    FSLog.audio("app launch: session category ambient")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let music = LoopMusic(messenger: messenger)
    loopMusic = music
    let loops = SfxLoops(messenger: messenger)
    sfxLoops = loops
    audioWatch = AudioWatch(messenger: messenger, music: music, loops: loops)
    haptics = Haptics(messenger: messenger)
    // The iOS side of `flappy_spikes/device` (Android: MainActivity.kt).
    // `launchArgs`: the process arguments, so a test run launched with
    // `-FSResetGameCenter` (WebDriverAgent / Xcode only; App Store users
    // can't pass launch arguments) can reset the player's achievements.
    let device = FlutterMethodChannel(name: "flappy_spikes/device", binaryMessenger: messenger)
    device.setMethodCallHandler { call, result in
      switch call.method {
      case "isTestLab":
        result(false)
      case "launchArgs":
        result(ProcessInfo.processInfo.arguments)
      // PRD-2.5 §3.3 WP-GUARD / §3.4 WP-SAVE (fail-open: nil on errors).
      case "integrity":
        result(Integrity.info())
      case "sealKey":
        result(SaveSealKey.ensure())
      case "sealDrop":
        SaveSealKey.drop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    deviceChannel = device
  }

  private var deviceChannel: FlutterMethodChannel?
}

/// Release-visible device log. iOS streams `.default` (and above) to the
/// device console in release builds; `.info` / `.debug` are not shown, so
/// every line here is `.default`. Filter on the category (`FS-Music`,
/// `FS-Game`) or the text `FS-`.
enum FSLog {
  static let subsystem = "com.flappyspikes.flappyspikes"
  static let music = OSLog(subsystem: subsystem, category: "FS-Music")
  static let game = OSLog(subsystem: subsystem, category: "FS-Game")

  static func audio(_ message: String) {
    os_log("FS-Music %{public}@", log: music, type: .default, message)
  }

  static func info(_ message: String) {
    os_log("FS-Game %{public}@", log: game, type: .default, message)
  }
}

/// The game's one audio session: `.ambient` (mixes with the player's own
/// music, follows the silent switch). Activated explicitly whenever the game
/// needs sound again (foreground, an interruption that ended, the music
/// starting / resuming), with the result logged.
enum GameAudioSession {
  @discardableResult
  static func activate(_ reason: String) -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .ambient {
        try session.setCategory(.ambient)
        FSLog.audio("session category -> ambient (\(reason))")
      }
      try session.setActive(true)
      FSLog.audio(
        "session activate ok (\(reason)) other=\(session.isOtherAudioPlaying ? 1 : 0) "
          + "hint=\(session.secondaryAudioShouldBeSilencedHint ? 1 : 0)")
      return true
    } catch {
      let ns = error as NSError
      FSLog.audio("session activate FAILED (\(reason)) code=\(ns.code) \(ns.localizedDescription)")
      return false
    }
  }
}

/// Other apps' audio as the game sees it (Dart: `PlatformAudioFocus`, the
/// same channel protocol as Android's `AudioWatch` in MainActivity.kt):
///
/// - `interrupted`: an `AVAudioSession` interruption (call, alarm, Siri) has
///   begun and not ended yet. iOS does not always post the `ended`:
///   - an interruption that only says "the app was suspended" (reason
///     `appWasSuspended` / the suspended key; iOS delivers it late, when the
///     app runs again, and never ends it) is ignored;
///   - coming back to the foreground (`didBecomeActive`) ends any
///     interruption and re-activates the session;
///   - while the app is active, a re-check (`snapshot`, polled by the music
///     guard every 0.5 s while held) more than 3 s after the `began` tries
///     to re-activate the session: success means it is over.
/// - `media` / `musicActive`: `secondaryAudioShouldBeSilencedHint`, i.e.
///   another app plays non-mixable audio (music, podcast). The hint never
///   counts the game's own (ambient) audio;
/// - `notification` is always false (iOS gives no notification-sound
///   signal); `players` carries diagnostics (`hint=`, `other=`);
/// - `resets`: how many times the media services were reset (every player
///   is invalid then: the game rebuilds its sound-effect voices).
final class AudioWatch: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let music: LoopMusic
  private let loops: SfxLoops
  private var sink: FlutterEventSink?
  private var interrupted = false
  private var interruptedAt: Date?
  private var resets = 0

  init(messenger: FlutterBinaryMessenger, music: LoopMusic, loops: SfxLoops) {
    self.music = music
    self.loops = loops
    methods = FlutterMethodChannel(name: "flappy_spikes/audio", binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: "flappy_spikes/audio_interruptions", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "isOtherMusicActive", "isOtherMediaListed":
        result(self.otherAudioPlaying)
      case "snapshot":
        self.recheckInterruption()
        result(self.state())
      case "log":
        // The Dart music log (PRD-2.3 §13.3). `.default`: visible in
        // release builds (round 2; `.info` never reached the console).
        let line = call.arguments as? String ?? ""
        FSLog.audio(line)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    events.setStreamHandler(self)
    let session = AVAudioSession.sharedInstance()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(onInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: session)
    center.addObserver(
      self, selector: #selector(onSilenceHint(_:)),
      name: AVAudioSession.silenceSecondaryAudioHintNotification, object: session)
    center.addObserver(
      self, selector: #selector(onMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    center.addObserver(
      self, selector: #selector(onDidBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onWillResignActive(_:)),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onDidEnterBackground(_:)),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onWillEnterForeground(_:)),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var otherAudioPlaying: Bool {
    return AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
  }

  private func state() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let other = otherAudioPlaying
    return [
      "interrupted": interrupted,
      "notification": false,
      "media": other,
      "musicActive": other,
      "stateKnown": true,
      "players": [
        "hint=\(other ? 1 : 0)", "other=\(session.isOtherAudioPlaying ? 1 : 0)",
      ],
      "resets": resets,
    ]
  }

  private func push() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let sink = self.sink else { return }
      sink(self.state())
    }
  }

  private func setInterrupted(_ on: Bool, _ why: String) {
    if interrupted != on {
      FSLog.audio("interrupted \(interrupted ? 1 : 0) -> \(on ? 1 : 0) (\(why))")
    }
    interrupted = on
    interruptedAt = on ? Date() : nil
  }

  @objc private func onInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
    // "AVAudioSessionInterruptionWasSuspendedKey" (deprecated constant,
    // spelled out) and reason 1 (`appWasSuspended`): the system suspended
    // the app; no `ended` ever follows.
    let suspended =
      (note.userInfo?["AVAudioSessionInterruptionWasSuspendedKey"] as? Bool) == true
      || reason == 1
    let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    // AVAudioSession may post on a background thread: the state is only
    // touched on the main thread.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let appState = UIApplication.shared.applicationState.rawValue
      let reasonText = reason.map { String($0) } ?? "-"
      switch type {
      case .began:
        FSLog.audio(
          "interruption began reason=\(reasonText) suspended=\(suspended ? 1 : 0) app=\(appState)")
        if suspended {
          FSLog.audio("interruption ignored (app was suspended; iOS never ends it)")
          return
        }
        self.setInterrupted(true, "began")
      case .ended:
        FSLog.audio("interruption ended shouldResume=\(options & 1) app=\(appState)")
        self.setInterrupted(false, "ended")
        if UIApplication.shared.applicationState == .active {
          GameAudioSession.activate("interruption-ended")
          self.music.recover("interruption-ended")
          self.loops.recover("interruption-ended")
        }
      @unknown default:
        return
      }
      self.push()
    }
  }

  /// A stale interruption while the app is active: the session can be
  /// activated again = the interruption is over (iOS sent no `ended`).
  private func recheckInterruption() {
    guard interrupted, UIApplication.shared.applicationState == .active,
      let since = interruptedAt, Date().timeIntervalSince(since) >= 3
    else { return }
    if GameAudioSession.activate("stale-interruption-probe") {
      setInterrupted(false, "session re-activated while active")
      music.recover("stale-interruption")
      loops.recover("stale-interruption")
    } else {
      // Try again in 3 s (not on every 0.5 s poll).
      interruptedAt = Date()
    }
  }

  @objc private func onSilenceHint(_ note: Notification) {
    let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt ?? 99
    FSLog.audio("silence hint type=\(raw) hint=\(otherAudioPlaying ? 1 : 0)")
    push()
  }

  /// A media-services reset happened while the app was not active: the
  /// session / engines are set up again on the next `didBecomeActive`.
  private var resetPending = false

  /// The media server restarted: every AVPlayer / engine is invalid.
  ///
  /// Round 2b (device log 2026-10-15: a reset every ~7 s in the background,
  /// each one answered with a session activation that failed with '!pla'
  /// and ~90 new players): while the app is not active nothing is activated
  /// or created here. The dead engines are only dropped; the session, the
  /// music engine and the loop engine come back on `didBecomeActive`, once.
  /// Dart gets the count (`resets`) and defers its own player rebuild the
  /// same way.
  @objc private func onMediaServicesReset(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.resets += 1
      let active = UIApplication.shared.applicationState == .active
      FSLog.audio("media services were reset (#\(self.resets)) active=\(active ? 1 : 0)")
      self.music.mediaServicesReset(rebuild: active)
      self.loops.mediaServicesReset()
      if active {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        GameAudioSession.activate("media-services-reset")
      } else {
        self.resetPending = true
        FSLog.audio("media reset: session + engines deferred to didBecomeActive")
      }
      self.push()
    }
  }

  /// Back in the foreground: any interruption is over (iOS does not always
  /// post `ended`, e.g. a call that ended while the app was in the
  /// background or the screen was locked), and the session is activated
  /// again explicitly.
  @objc private func onDidBecomeActive(_ note: Notification) {
    FSLog.audio(
      "app didBecomeActive interrupted=\(interrupted ? 1 : 0) resetPending=\(resetPending ? 1 : 0)")
    if interrupted {
      setInterrupted(false, "didBecomeActive")
    }
    if resetPending {
      resetPending = false
      try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }
    GameAudioSession.activate("didBecomeActive")
    music.recover("didBecomeActive")
    loops.recover("didBecomeActive")
    push()
  }

  @objc private func onWillResignActive(_ note: Notification) {
    FSLog.audio("app willResignActive")
  }

  @objc private func onDidEnterBackground(_ note: Notification) {
    FSLog.audio("app didEnterBackground")
  }

  @objc private func onWillEnterForeground(_ note: Notification) {
    FSLog.audio("app willEnterForeground")
  }

  // MARK: FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

/// iOS round 2 §1: the music loop, seamless (Dart: `NativeLoopMusic`
/// on `flappy_spikes/music`).
///
/// `FlappySpikesRemix_loopE.m4a` (Runner bundle;
/// `tool/make_music_loop_remix.py`; the remix looped as option E, 48 kHz,
/// L = 8 485 344 frames = 176.778 s) is AAC with 3072 frames before the loop
/// (1024 encoder priming + 2048 pre-roll of the loop's own end, skipped by
/// the MP4 edit list) and 544 padding frames. The loop is the file segment
/// [offset, offset + loopFrames), scheduled back to back on an
/// `AVAudioPlayerNode` (always one whole loop queued ahead), which plays
/// scheduled segments sample-exactly one after the other: no gap and no
/// click at the wrap (AVPlayer's loop re-seeks and leaves a gap).
/// `offset` comes from `AVAudioFile.length` (whether Core Audio applied the
/// MP4 edit list / sample table): see the tool's docstring.
///
/// Hourglass (§3.30) plays slower through an `AVAudioUnitTimePitch` (the
/// pitch stays, as on Android). The engine is re-started explicitly after
/// interruptions, route changes and a media-services reset; [state] says
/// `stopped` when the music should play but the engine / node is not
/// running, so the Dart watchdog (PRD-2.3 §13.4) restarts it.
final class LoopMusic: NSObject {
  static let loopFrames: AVAudioFramePosition = 8_485_344
  static let primingFrames: AVAudioFramePosition = 3072
  static let remainderFrames: AVAudioFramePosition = 544

  private let channel: FlutterMethodChannel
  private var engine: AVAudioEngine?
  private var node: AVAudioPlayerNode?
  private var timePitch: AVAudioUnitTimePitch?
  private var file: AVAudioFile?
  private var fileName: String?
  private var offset: AVAudioFramePosition = 0
  private var loopLength: AVAudioFramePosition = LoopMusic.loopFrames
  private var sampleRate: Double = 44100

  /// Dart wants the music playing (start / resume, not paused / stopped).
  private var wanted = false
  private var stopped = true
  private var generation = 0
  private var volume: Float = 1
  private var rate: Float = 1

  /// Loop position (frames) where the current schedule started, and when.
  private var playBase: AVAudioFramePosition = 0
  private var playStartedAt: CFTimeInterval = 0
  private var savedPosition: AVAudioFramePosition = 0
  private var consumed = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "flappy_spikes/music", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        let name = args["file"] as? String ?? ""
        let volume = (args["volume"] as? NSNumber)?.floatValue ?? 1
        let rate = (args["rate"] as? NSNumber)?.floatValue ?? 1
        self.start(file: name, volume: volume, rate: rate)
      case "pause":
        self.pause()
      case "resume":
        self.resume()
      case "stop":
        self.stop()
      case "setVolume":
        self.volume = (args["volume"] as? NSNumber)?.floatValue ?? self.volume
        self.node?.volume = self.volume
      case "setRate":
        self.setRate((args["rate"] as? NSNumber)?.floatValue ?? 1)
      case "state":
        break
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(self.state)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// `none`, `playing`, `paused`, `stopped` (also: should play but the
  /// engine / node is not running).
  var state: String {
    if fileName == nil { return "none" }
    if stopped { return "stopped" }
    if !wanted { return "paused" }
    if let e = engine, let n = node, e.isRunning, n.isPlaying { return "playing" }
    return "stopped"
  }

  private var playingNow: Bool {
    guard wanted, let e = engine, let n = node else { return false }
    return e.isRunning && n.isPlaying
  }

  func start(file name: String, volume: Float, rate: Float) {
    self.volume = volume
    self.rate = rate
    if fileName != name || engine == nil {
      fileName = name
      guard build() else { return }
    }
    node?.volume = volume
    applyRate()
    wanted = true
    stopped = false
    savedPosition = 0
    play(from: 0, reason: "start")
  }

  func pause() {
    if wanted { savedPosition = position() }
    wanted = false
    node?.pause()
    engine?.pause()
    FSLog.audio("music pause at=\(savedPosition)")
  }

  func resume() {
    if playingNow { return }
    wanted = true
    stopped = false
    if engine == nil {
      // Round 2b: nothing is built while the app is not active; recover()
      // on didBecomeActive builds and plays it.
      if UIApplication.shared.applicationState != .active {
        FSLog.audio("music resume deferred: app not active (engine dropped)")
        return
      }
      guard fileName != nil, build() else { return }
    }
    play(from: savedPosition, reason: "resume")
  }

  func stop() {
    wanted = false
    stopped = true
    generation += 1
    node?.stop()
    engine?.stop()
    savedPosition = 0
    FSLog.audio("music stop")
  }

  /// The app is active again / an interruption ended: a music that should
  /// play but whose engine stopped is started again where it was.
  func recover(_ reason: String) {
    guard wanted, !stopped, UIApplication.shared.applicationState == .active else { return }
    if playingNow { return }
    let at = position()
    FSLog.audio(
      "music recover (\(reason)) engine=\(engine?.isRunning == true ? 1 : 0) "
        + "node=\(node?.isPlaying == true ? 1 : 0) at=\(at)")
    if engine == nil {
      guard build() else { return }
    }
    play(from: at, reason: "recover-\(reason)")
  }

  /// Every engine is invalid after a media-services reset: dropped now.
  /// With [rebuild] (the app is active) it is built again and plays on if it
  /// was playing; otherwise (round 2b) the next `resume` / `recover` in the
  /// foreground builds it (the engine is nil), never in the background.
  func mediaServicesReset(rebuild: Bool) {
    let at = position()
    if wanted { savedPosition = at }
    teardown()
    FSLog.audio("music engine dropped (media reset) rebuild=\(rebuild ? 1 : 0)")
    guard rebuild, fileName != nil else { return }
    if wanted && !stopped {
      if build() { play(from: at, reason: "media-reset") }
    }
  }

  private func setRate(_ r: Float) {
    // Rebase the clock so the position stays right across the change.
    if playingNow {
      playBase = position()
      playStartedAt = CACurrentMediaTime()
    }
    rate = r
    applyRate()
  }

  private func applyRate() {
    timePitch?.rate = rate
    timePitch?.bypass = abs(rate - 1) < 0.0001
  }

  private func teardown() {
    generation += 1
    if let e = engine {
      NotificationCenter.default.removeObserver(
        self, name: .AVAudioEngineConfigurationChange, object: e)
      node?.stop()
      e.stop()
    }
    engine = nil
    node = nil
    timePitch = nil
    file = nil
  }

  private func build() -> Bool {
    teardown()
    guard let name = fileName else { return false }
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    guard let url = Bundle.main.url(forResource: base, withExtension: ext) else {
      FSLog.audio("music file MISSING in the bundle: \(name)")
      return false
    }
    do {
      let f = try AVAudioFile(forReading: url)
      let length = f.length
      let L = LoopMusic.loopFrames
      let p = LoopMusic.primingFrames
      let r = LoopMusic.remainderFrames
      switch length {
      case L, L + r:
        offset = 0
      case L + p, L + p + r:
        offset = p
      default:
        offset = length > L ? min(p, length - L) : 0
        FSLog.audio("music unexpected length \(length) (expected \(L) / +\(r) / +\(p) / +\(p + r))")
      }
      loopLength = min(L, length - offset)
      let format = f.processingFormat
      sampleRate = format.sampleRate
      let e = AVAudioEngine()
      let n = AVAudioPlayerNode()
      let tp = AVAudioUnitTimePitch()
      e.attach(n)
      e.attach(tp)
      e.connect(n, to: tp, format: format)
      e.connect(tp, to: e.mainMixerNode, format: format)
      e.prepare()
      engine = e
      node = n
      timePitch = tp
      file = f
      n.volume = volume
      applyRate()
      NotificationCenter.default.addObserver(
        self, selector: #selector(onConfigurationChange(_:)),
        name: .AVAudioEngineConfigurationChange, object: e)
      FSLog.audio(
        "music load \(name) length=\(length) offset=\(offset) loop=\(loopLength) "
          + "sr=\(Int(format.sampleRate)) ch=\(format.channelCount)")
      return true
    } catch {
      FSLog.audio("music load FAILED \(name): \(error.localizedDescription)")
      teardown()
      return false
    }
  }

  @objc private func onConfigurationChange(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      FSLog.audio("music engine configuration change (route / session) wanted=\(self.wanted ? 1 : 0)")
      self.recover("configuration-change")
    }
  }

  /// The loop position now (frames): the node's own clock while it renders,
  /// else the wall clock since the schedule started.
  private func position() -> AVAudioFramePosition {
    let len = max(loopLength, 1)
    if let e = engine, e.isRunning, let n = node, n.isPlaying,
      let nt = n.lastRenderTime, nt.isSampleTimeValid,
      let pt = n.playerTime(forNodeTime: nt)
    {
      return ((playBase + pt.sampleTime) % len + len) % len
    }
    if !wanted { return savedPosition }
    let elapsed = (CACurrentMediaTime() - playStartedAt) * sampleRate * Double(rate)
    return ((playBase + AVAudioFramePosition(elapsed)) % len + len) % len
  }

  private func play(from pos: AVAudioFramePosition, reason: String) {
    guard let e = engine, let n = node else { return }
    // Round 2b: never activate the session / start the engine while the
    // app is not active ('!pla'); `recover` on didBecomeActive plays it.
    if UIApplication.shared.applicationState != .active {
      if wanted { savedPosition = pos }
      FSLog.audio("music play (\(reason)) deferred: app not active")
      return
    }
    GameAudioSession.activate("music-\(reason)")
    if !e.isRunning {
      do {
        try e.start()
      } catch {
        let ns = error as NSError
        FSLog.audio("music engine start FAILED (\(reason)) code=\(ns.code) \(ns.localizedDescription)")
        // Rebuilt on the next start / resume / recover.
        teardown()
        return
      }
    }
    generation += 1
    n.stop()  // flushes the old schedule (its callbacks see the old generation)
    let len = max(loopLength, 1)
    let p = (pos % len + len) % len
    playBase = p
    playStartedAt = CACurrentMediaTime()
    let gen = generation
    schedule(gen, from: p)
    schedule(gen, from: 0)
    n.play()
    FSLog.audio(
      "music play (\(reason)) at=\(p) engine=\(e.isRunning ? 1 : 0) node=\(n.isPlaying ? 1 : 0) "
        + "vol=\(volume) rate=\(rate)")
  }

  /// Queues the segment [from, loopLength) of the loop; when it has been
  /// consumed the next whole loop is queued (one loop always ahead).
  private func schedule(_ gen: Int, from start: AVAudioFramePosition) {
    guard gen == generation, let n = node, let f = file else { return }
    let count = AVAudioFrameCount(max(loopLength - start, 1))
    n.scheduleSegment(
      f, startingFrame: offset + start, frameCount: count, at: nil,
      completionCallbackType: .dataConsumed
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self, gen == self.generation else { return }
        self.consumed += 1
        if self.consumed <= 3 || self.consumed % 10 == 0 {
          FSLog.audio("music segment consumed #\(self.consumed): next loop queued (seamless wrap)")
        }
        self.schedule(gen, from: 0)
      }
    }
  }
}

/// iOS round 2 §3: the sound-effect loops (Dart: `NativeSfxLoops` on
/// `flappy_spikes/loops`). Android loops them on SoundPool (seamless); here
/// each loop asset (`assets/audio/*.wav`, read from the Flutter assets in
/// the app bundle) is decoded once into a PCM buffer and played on its own
/// `AVAudioPlayerNode` with `.loops` (sample-exact), all on one engine.
/// AVPlayer (audioplayers) re-seeks at the end of the item: a gap every
/// 4-7 s.
final class SfxLoops: NSObject {
  private let channel: FlutterMethodChannel
  private var engine: AVAudioEngine?
  private var nodes: [Int: AVAudioPlayerNode] = [:]
  private var buffersOf: [Int: AVAudioPCMBuffer] = [:]
  private var cache: [String: AVAudioPCMBuffer] = [:]
  private var started = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "flappy_spikes/loops", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      let id = (args["id"] as? NSNumber)?.intValue ?? 0
      switch call.method {
      case "start":
        let asset = args["asset"] as? String ?? ""
        let volume = (args["volume"] as? NSNumber)?.floatValue ?? 1
        self.start(id: id, asset: asset, volume: volume)
      case "setVolume":
        self.nodes[id]?.volume = (args["volume"] as? NSNumber)?.floatValue ?? 1
      case "stop":
        self.stop(id: id)
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func buffer(for asset: String) -> AVAudioPCMBuffer? {
    if let b = cache[asset] { return b }
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      FSLog.audio("loop asset MISSING: \(asset)")
      return nil
    }
    do {
      let f = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      guard
        let b = AVAudioPCMBuffer(
          pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))
      else { return nil }
      try f.read(into: b)
      cache[asset] = b
      FSLog.audio("loop load \(asset) frames=\(b.frameLength) sr=\(Int(f.processingFormat.sampleRate))")
      return b
    } catch {
      FSLog.audio("loop load FAILED \(asset): \(error.localizedDescription)")
      return nil
    }
  }

  private func ensureEngine(_ reason: String) -> AVAudioEngine? {
    // Round 2b: nothing is started while the app is not active.
    if UIApplication.shared.applicationState != .active { return nil }
    let e: AVAudioEngine
    if let existing = engine {
      e = existing
    } else {
      e = AVAudioEngine()
      _ = e.mainMixerNode
      engine = e
      NotificationCenter.default.addObserver(
        self, selector: #selector(onConfigurationChange(_:)),
        name: .AVAudioEngineConfigurationChange, object: e)
    }
    if !e.isRunning {
      GameAudioSession.activate("loops-\(reason)")
      do {
        try e.start()
      } catch {
        FSLog.audio("loops engine start FAILED (\(reason)): \(error.localizedDescription)")
        return nil
      }
    }
    return e
  }

  private func start(id: Int, asset: String, volume: Float) {
    guard let b = buffer(for: asset), let e = ensureEngine("start") else { return }
    let n = AVAudioPlayerNode()
    e.attach(n)
    e.connect(n, to: e.mainMixerNode, format: b.format)
    n.volume = volume
    n.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
    n.play()
    nodes[id] = n
    buffersOf[id] = b
    started += 1
    if started <= 3 || started % 20 == 0 {
      FSLog.audio("loop start #\(started) \(asset) live=\(nodes.count)")
    }
  }

  private func stop(id: Int) {
    guard let n = nodes.removeValue(forKey: id) else { return }
    buffersOf.removeValue(forKey: id)
    n.stop()
    engine?.detach(n)
    // No loop left: the engine stops (no idle I/O).
    if nodes.isEmpty, let e = engine, e.isRunning {
      e.pause()
    }
  }

  /// The engine stopped under live loops (interruption, route change): the
  /// loops start again from their top.
  func recover(_ reason: String) {
    guard !nodes.isEmpty else { return }
    guard let e = engine, !e.isRunning || nodes.values.contains(where: { !$0.isPlaying }) else {
      return
    }
    FSLog.audio("loops recover (\(reason)) live=\(nodes.count)")
    guard ensureEngine("recover") != nil else { return }
    for (id, n) in nodes {
      guard let b = buffersOf[id] else { continue }
      n.stop()
      n.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
      n.play()
    }
  }

  /// Every engine is invalid after a media-services reset: dropped; the
  /// game's features start their loops again when they need them.
  func mediaServicesReset() {
    if let e = engine {
      NotificationCenter.default.removeObserver(
        self, name: .AVAudioEngineConfigurationChange, object: e)
    }
    nodes.removeAll()
    buffersOf.removeAll()
    engine = nil
  }

  @objc private func onConfigurationChange(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.recover("configuration-change")
    }
  }
}

/// iOS round 2 §4: the soft rumble (`Rumble.knock`) as a physical-button
/// click: `UIImpactFeedbackGenerator(style: .rigid)` at full intensity (a
/// short, crisp tap; `.light` was barely felt). The hard rumble (shake)
/// stays on the vibration plugin.
final class Haptics: NSObject {
  private let channel: FlutterMethodChannel
  private var rigid: UIImpactFeedbackGenerator?
  private var clicks = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "flappy_spikes/haptics", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "click":
        self.click()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func click() {
    let g = rigid ?? UIImpactFeedbackGenerator(style: .rigid)
    rigid = g
    g.impactOccurred(intensity: 1.0)
    // Keeps the Taptic Engine warm for the next click (low latency).
    g.prepare()
    clicks += 1
    if clicks <= 3 || clicks % 50 == 0 {
      FSLog.info("haptics click #\(clicks) (rigid, intensity 1.0)")
    }
  }
}

/// PRD-2.5 §3.3 WP-GUARD: the embedded provisioning profile's team. App
/// Store and TestFlight builds carry none (Apple re-signs them); our own
/// dev / ad-hoc builds carry our team; a re-signed sideload another team.
/// Compared in Dart.
enum Integrity {
  static func info() -> [String: Any] {
    var out: [String: Any] = [
      "sandboxReceipt":
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    ]
    if let team = provisionTeam() {
      out["provisionTeam"] = team
    }
    return out
  }

  private static func provisionTeam() -> String? {
    guard
      let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
      let data = FileManager.default.contents(atPath: path),
      let text = String(data: data, encoding: .isoLatin1),
      let start = text.range(of: "<?xml"),
      let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex)
    else { return nil }
    let xml = String(text[start.lowerBound..<end.upperBound])
    guard
      let plistData = xml.data(using: .isoLatin1),
      let plist = try? PropertyListSerialization.propertyList(
        from: plistData, options: [], format: nil) as? [String: Any],
      let teams = plist["TeamIdentifier"] as? [String],
      let team = teams.first
    else { return nil }
    return team
  }
}

/// PRD-2.5 §3.4 WP-SAVE: the device key of the tamper-evident save, a
/// 32-byte random Keychain generic password (AfterFirstUnlock, not
/// ThisDeviceOnly: it moves with encrypted backups together with the
/// preferences). The MACs are computed in Dart.
enum SaveSealKey {
  private static let service = "com.flappyspikes.saveseal"
  private static let account = "v1"

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  /// ["existed": Bool, "key": bytes], or nil when the Keychain fails.
  static func ensure() -> [String: Any]? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let key = item as? Data, key.count >= 16 {
      return ["existed": true, "key": FlutterStandardTypedData(bytes: key)]
    }
    if status != errSecItemNotFound && status != errSecSuccess { return nil }
    if status == errSecSuccess { SecItemDelete(baseQuery as CFDictionary) }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      return nil
    }
    let key = Data(bytes)
    var add = baseQuery
    add[kSecValueData as String] = key
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
    return ["existed": false, "key": FlutterStandardTypedData(bytes: key)]
  }

  static func drop() {
    SecItemDelete(baseQuery as CFDictionary)
  }
}
