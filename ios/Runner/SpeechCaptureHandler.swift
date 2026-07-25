import AVFoundation
import Flutter
import Speech

/// 発話フェーズの録音と、タイマー終了後のファイルベース文字起こしを担当する。
/// Android の「無音録音 → Vosk 文字起こし」と同じ構造を iOS で実現する。
///
/// Flutter MethodChannel: com.osamushikubo.osm_washabe/speech_capture
/// startCapture(outputPath: String) → Bool
/// stopCapture()                   → String? (録音ファイルパス)
/// transcribeFile(path: String)    → String  (文字起こし結果)
final class SpeechCaptureHandler: NSObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var audioRecorder: AVAudioRecorder?
    private var recordingOutputPath: String?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCapture":
            guard let args = call.arguments as? [String: Any],
                  let path = args["outputPath"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            requestMicrophonePermission { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    result(FlutterError(
                        code: "MIC_DENIED",
                        message: "Microphone permission denied",
                        details: nil
                    ))
                    return
                }
                do {
                    try self.startRecording(to: path)
                    result(true)
                } catch {
                    result(FlutterError(code: "START_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }

        case "stopCapture":
            result(stopRecording())

        case "transcribeFile":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            transcribe(path: path, flutterResult: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Private

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    private func startRecording(to path: String) throws {
        stopRecording() // 前回の録音が残っていれば停止

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        if session.isInputGainSettable {
            try? session.setInputGain(1.0)
        }

        let url = URL(fileURLWithPath: path)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
        ]
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        recordingOutputPath = path
    }

    @discardableResult
    private func stopRecording() -> String? {
        audioRecorder?.stop()
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
        let path = recordingOutputPath
        recordingOutputPath = nil
        return path
    }

    /// 単語ごとのタイムスタンプ付きセグメントを返す。
    /// 戻り値: [[String: Any]] — 各要素は {"text": String, "timestamp": Double, "duration": Double}
    /// 権限/前提条件エラーは FlutterError(code:) として返し、Dart 側のログに理由が残るようにする。
    private func transcribe(path: String, flutterResult: @escaping FlutterResult) {
        guard FileManager.default.fileExists(atPath: path) else {
            flutterResult(FlutterError(code: "NO_FILE", message: "Recording file missing", details: nil))
            return
        }

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    flutterResult(FlutterError(
                        code: "SPEECH_DENIED",
                        message: "Speech recognition permission denied",
                        details: nil
                    ))
                    return
                }
                self.performTranscription(path: path, flutterResult: flutterResult)
            }
        }
    }

    private func performTranscription(path: String, flutterResult: @escaping FlutterResult) {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            flutterResult(FlutterError(
                code: "SPEECH_UNAVAILABLE",
                message: "Speech recognizer unavailable",
                details: nil
            ))
            return
        }

        let url = URL(fileURLWithPath: path)
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true

        var responded = false
        var latestSegments: [[String: Any]] = []

        func finish(with segments: [[String: Any]]) {
            guard !responded else { return }
            responded = true
            flutterResult(segments)
        }

        func mapSegments(_ transcription: SFTranscription) -> [[String: Any]] {
            transcription.segments.map { seg in
                ["text": seg.substring, "timestamp": seg.timestamp, "duration": seg.duration]
            }
        }

        let task = recognizer.recognitionTask(with: request) { recognitionResult, error in
            if let recognitionResult = recognitionResult {
                latestSegments = mapSegments(recognitionResult.bestTranscription)
                if recognitionResult.isFinal {
                    finish(with: latestSegments)
                }
            }

            if let error = error {
                // 途中結果があればそれを返す（無音判定エラーでも拾えるようにする）
                finish(with: latestSegments)
                if latestSegments.isEmpty {
                    NSLog("SpeechCapture transcribe error: \(error.localizedDescription)")
                }
            }
        }

        // isFinal が来ないケースの保険（シミュレーター等）
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            guard !responded else { return }
            task.cancel()
            finish(with: latestSegments)
        }
    }
}
