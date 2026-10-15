import AVFoundation
import Flutter
import UIKit
import UserNotifications
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// PRD-2.2 §28.3: the iOS side of `flappy_spikes/audio` (kept alive for
  /// the app's lifetime).
  private var audioWatch: AudioWatch?

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    audioWatch = AudioWatch(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Other apps' audio as the game sees it (Dart: `PlatformAudioFocus`, the
/// same channel protocol as Android's `AudioWatch` in MainActivity.kt):
///
/// - `interrupted`: an `AVAudioSession` interruption (call, alarm, Siri) has
///   begun and not ended yet;
/// - `media` / `musicActive`: `secondaryAudioShouldBeSilencedHint`, i.e.
///   another app plays non-mixable audio (music, podcast). The hint never
///   counts the game's own (ambient) audio;
/// - `notification` is always false (iOS gives no notification-sound
///   signal) and `players` is empty.
///
/// The session category is never changed here and no session is activated:
/// the game only observes.
final class AudioWatch: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var interrupted = false
  private let logger = OSLog(subsystem: "com.flappyspikes.flappyspikes", category: "FS-Music")

  init(messenger: FlutterBinaryMessenger) {
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
        result(self.state())
      case "log":
        let line = call.arguments as? String ?? ""
        os_log("%{public}@", log: self.logger, type: .info, line)
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
      self, selector: #selector(onDidBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var otherAudioPlaying: Bool {
    return AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
  }

  private func state() -> [String: Any] {
    let other = otherAudioPlaying
    return [
      "interrupted": interrupted,
      "notification": false,
      "media": other,
      "musicActive": other,
      "stateKnown": true,
      "players": [String](),
    ]
  }

  private func push() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let sink = self.sink else { return }
      sink(self.state())
    }
  }

  @objc private func onInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    let began: Bool
    switch type {
    case .began:
      began = true
    case .ended:
      began = false
    @unknown default:
      return
    }
    // AVAudioSession may post on a background thread: the state is only
    // touched on the main thread.
    DispatchQueue.main.async { [weak self] in
      self?.interrupted = began
      self?.push()
    }
  }

  @objc private func onSilenceHint(_ note: Notification) {
    push()
  }

  /// iOS does not always post the `ended` interruption (e.g. the call ended
  /// while the app was in the background): back in the foreground the
  /// interruption is over.
  @objc private func onDidBecomeActive(_ note: Notification) {
    if interrupted {
      interrupted = false
    }
    push()
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
