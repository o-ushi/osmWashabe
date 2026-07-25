import AudioToolbox
import AVFoundation
import Flutter
import Speech
import UIKit

// ネイティブ osmWashabe と同じ UIKit シェイク検出（CMMotionManager / HighFrequency HID を使わない）
extension Notification.Name {
  static let osmDeviceDidShake = Notification.Name("osmWashabe.deviceDidShake")
}

extension UIWindow {
  open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    super.motionEnded(motion, with: event)
    if motion == .motionShake {
      NotificationCenter.default.post(name: .osmDeviceDidShake, object: nil)
    }
  }
}

private final class DeviceShakeStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    observer = NotificationCenter.default.addObserver(
      forName: .osmDeviceDidShake,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.sink?(true)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
    observer = nil
    sink = nil
    return nil
  }
}

// iOS ネイティブ TTS: 既知の識別子を直接試行して音声を確実に選択
private class NativeTtsHandler: NSObject, AVSpeechSynthesizerDelegate {
  private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
  private var pendingResult: FlutterResult?
  // 発話インスタンスを追跡し、古い didCancel/didFinish が新しい pendingResult を誤解決しないようにする
  private var pendingUtterance: AVSpeechUtterance?

  // iOS の識別子フォーマットは時期によって異なるため新旧両方を網羅
  // Siri ボイス識別子は siriIdentifiers にのみ含める（男性/女性 の fallback に使わない）
  private static let maleIdentifiers: [String] = [
    "com.apple.voice.premium.ja-JP.Otoya",
    "com.apple.voice.enhanced.ja-JP.Otoya",
    "com.apple.voice.compact.ja-JP.Otoya",
    "com.apple.ttsbundle.Otoya-premium",
    "com.apple.ttsbundle.Otoya-compact",
  ]

  private static let femaleIdentifiers: [String] = [
    "com.apple.voice.premium.ja-JP.Kyoko",
    "com.apple.voice.enhanced.ja-JP.Kyoko",
    "com.apple.voice.compact.ja-JP.Kyoko",
    "com.apple.ttsbundle.Kyoko-premium",
    "com.apple.ttsbundle.Kyoko-compact",
  ]

  private static let siriIdentifiers: [String] = [
    "com.apple.ttsbundle.siri_female_ja-JP_compact",
    "com.apple.ttsbundle.siri_O-Ren_ja-JP_compact",
    "com.apple.ttsbundle.siri_male_ja-JP_compact",
    "com.apple.ttsbundle.siri_Hattori_ja-JP_compact",
  ]

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  // 性別に応じた音声を選択: speechVoices() に頼らず識別子を直接試行
  static func voiceForGender(_ gender: String) -> AVSpeechSynthesisVoice? {
    let candidates: [String]
    switch gender {
    case "male":
      candidates = maleIdentifiers
    case "female":
      candidates = femaleIdentifiers
    case "siri":
      candidates = siriIdentifiers
    default: // random — 男女をランダムに優先して選択
      candidates = Bool.random() ? maleIdentifiers + femaleIdentifiers : femaleIdentifiers + maleIdentifiers
    }

    for id in candidates {
      if let voice = AVSpeechSynthesisVoice(identifier: id), voice.language.hasPrefix("ja") {
        return voice
      }
    }

    // speechVoices() から性別でフィルタ（iOS 13+）— Siri ボイスは除外する
    // システム言語が日本語以外（例: ベトナム語）だと、上の既知識別子が端末に
    // インストールされておらず nil になるケースがある。その場合でも
    // 性別違いの日本語ボイスがあればそちらを優先する（無音/誤言語よりまし）
    if #available(iOS 13.0, *) {
      let isMale: Bool
      if gender == "male" {
        isMale = true
      } else if gender == "random" {
        isMale = Bool.random()
      } else {
        isMale = false
      }
      let target: AVSpeechSynthesisVoiceGender = isMale ? .male : .female
      let japaneseVoices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("ja") && !$0.identifier.contains("siri") }
        .sorted { $0.quality.rawValue > $1.quality.rawValue }
      if let genderMatch = japaneseVoices.first(where: { $0.gender == target }) {
        return genderMatch
      }
      if let anyJapanese = japaneseVoices.first {
        return anyJapanese
      }
    }

    // 最終フォールバック。AVSpeechSynthesisVoice(language:) は日本語音声データが
    // 端末に一切無い場合、別言語（システム言語）のボイスを返すことがあるため、
    // 返り値が本当に日本語かどうかを必ず検証する
    if let fallback = AVSpeechSynthesisVoice(language: "ja-JP"), fallback.language.hasPrefix("ja") {
      return fallback
    }

    return nil
  }

  // 選択された音声のメタ情報を返す（設定画面の「使用中の声」表示用）
  static func voiceInfo(for gender: String) -> [String: String] {
    guard let voice = voiceForGender(gender) else {
      return ["name": "Kyoko", "quality": "default"]
    }
    var quality = "default"
    switch voice.quality {
    case .premium: quality = "premium"
    case .enhanced: quality = "enhanced"
    default: quality = "default"
    }
    return ["name": voice.name, "quality": quality, "identifier": voice.identifier]
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      guard let args = call.arguments as? [String: Any],
            let text = args["text"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
        return
      }
      let gender = args["gender"] as? String ?? "female"
      let rate = Float((args["rate"] as? Double) ?? 0.5)
      let pitch = Float((args["pitch"] as? Double) ?? 1.0)
      doSpeak(text: text, gender: gender, rate: rate, pitch: pitch, result: result)

    case "stop":
      let r = pendingResult
      pendingResult = nil
      pendingUtterance = nil
      synthesizer.stopSpeaking(at: .immediate)
      r?(false)
      result(nil)

    case "pause":
      synthesizer.pauseSpeaking(at: .word)
      result(nil)

    case "resume":
      synthesizer.continueSpeaking()
      result(nil)

    case "openSettings":
      result(NativeTtsHandler.openIosSettings())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // このアプリの設定ページを開く（そこから アクセシビリティ→読み上げコンテンツ→声 に
  // 進んでもらう。iOS には特定の設定画面に直接ディープリンクする公開APIが無いため）
  static func openIosSettings() -> Bool {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
    DispatchQueue.main.async {
      UIApplication.shared.open(url)
    }
    return true
  }

  private func doSpeak(text: String, gender: String, rate: Float, pitch: Float,
                       result: @escaping FlutterResult) {
    let prev = pendingResult
    pendingResult = nil
    pendingUtterance = nil
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
      prev?(false)
    }

    // 性別に応じた音声を直接設定 — flutter_tts の setVoice を経由しない
    // 日本語音声が端末上で1つも見つからない場合は Android の
    // 「TTS未インストール」パスと同様に nil を返し、誤言語での発話を避ける
    guard let voice = NativeTtsHandler.voiceForGender(gender) else {
      result(nil)
      return
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = rate
    utterance.pitchMultiplier = pitch
    utterance.voice = voice

    pendingResult = result
    pendingUtterance = utterance
    synthesizer.speak(utterance)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                         didFinish utterance: AVSpeechUtterance) {
    // 古い発話の didFinish/didCancel が新しい pendingResult を誤解決しないよう照合する
    guard utterance === pendingUtterance else { return }
    let r = pendingResult
    pendingResult = nil
    pendingUtterance = nil
    r?(true)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                         didCancel utterance: AVSpeechUtterance) {
    guard utterance === pendingUtterance else { return }
    let r = pendingResult
    pendingResult = nil
    pendingUtterance = nil
    r?(false)
  }
}

@main
@MainActor
@objc class AppDelegate: FlutterAppDelegate {
  /// SceneDelegate が参照する。viewDidLoad より前に run() して Engine を完全初期化する。
  let flutterEngine = FlutterEngine(name: "osm_washabe_engine")
  private var ttsHandler: NativeTtsHandler?
  private var captureHandler: SpeechCaptureHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    registerCustomPlugins(with: flutterEngine)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
    } catch {
      // 失敗してもアプリは継続する
    }
  }

  private func registerCustomPlugins(with registry: FlutterPluginRegistry) {
    // システム効果音
    let soundReg = registry.registrar(forPlugin: "OsmWashabeSystemSound")!
    let soundCh = FlutterMethodChannel(
      name: "com.osamushikubo.osm_washabe/system_sound",
      binaryMessenger: soundReg.messenger()
    )
    soundCh.setMethodCallHandler { call, result in
      guard call.method == "play", let soundId = call.arguments as? Int else {
        result(FlutterMethodNotImplemented); return
      }
      AudioServicesPlaySystemSound(SystemSoundID(UInt32(soundId)))
      result(nil)
    }

    // 音声情報チャンネル（設定画面表示 + 「使用中の声」用）
    let voicesReg = registry.registrar(forPlugin: "OsmWashabeSpeechVoices")!
    let voicesCh = FlutterMethodChannel(
      name: "com.osamushikubo.osm_washabe/speech_voices",
      binaryMessenger: voicesReg.messenger()
    )
    voicesCh.setMethodCallHandler { call, result in
      if call.method == "getJapaneseVoices" {
        let voices = AVSpeechSynthesisVoice.speechVoices()
          .filter { $0.language.hasPrefix("ja") }
          .map { v -> [String: String] in
            var d: [String: String] = [:]
            d["identifier"] = v.identifier
            d["name"] = v.name
            d["locale"] = v.language
            if #available(iOS 13.0, *) {
              switch v.gender {
              case .male: d["gender"] = "male"
              case .female: d["gender"] = "female"
              default: d["gender"] = "unspecified"
              }
            }
            switch v.quality {
            case .premium: d["quality"] = "premium"
            case .enhanced: d["quality"] = "enhanced"
            default: d["quality"] = "default"
            }
            return d
          }
        result(voices)
      } else if call.method == "getVoiceInfoForGender",
                let gender = call.arguments as? String {
        // 実際に使われる音声情報を返す（識別子直接試行ロジック使用）
        result(NativeTtsHandler.voiceInfo(for: gender))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // ネイティブ TTS チャンネル
    let handler = NativeTtsHandler()
    ttsHandler = handler
    let ttsReg = registry.registrar(forPlugin: "OsmWashabeNativeTts")!
    let ttsCh = FlutterMethodChannel(
      name: "com.osamushikubo.osm_washabe/tts",
      binaryMessenger: ttsReg.messenger()
    )
    ttsCh.setMethodCallHandler { [weak handler] call, result in
      handler?.handle(call, result: result)
    }

    // シェイク検出（UIKit motionEnded → EventChannel）
    let shakeReg = registry.registrar(forPlugin: "OsmWashabeDeviceShake")!
    let shakeChannel = FlutterEventChannel(
      name: "com.osamushikubo.osm_washabe/device_shake",
      binaryMessenger: shakeReg.messenger()
    )
    shakeChannel.setStreamHandler(DeviceShakeStreamHandler())

    // 発話採点用録音（AVAudioRecorder）＋ファイルベース STT チャンネル
    let captureHandler = SpeechCaptureHandler()
    self.captureHandler = captureHandler
    let captureReg = registry.registrar(forPlugin: "OsmWashabeSpeechCapture")!
    let captureCh = FlutterMethodChannel(
      name: "com.osamushikubo.osm_washabe/speech_capture",
      binaryMessenger: captureReg.messenger()
    )
    captureCh.setMethodCallHandler { [weak captureHandler] call, result in
      captureHandler?.handle(call, result: result)
    }
  }
}
