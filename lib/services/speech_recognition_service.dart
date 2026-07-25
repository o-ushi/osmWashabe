import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/practice_models.dart';
import 'android_offline_speech_platform.dart';
import 'android_vosk_warmup.dart';
import 'background_audio_keeper.dart';
import 'privacy_service.dart';
import 'speech_recognition_debug_log_store.dart';
import 'topic_speech_reader.dart';
import 'vosk_model_manager.dart';

/// 単発お題モードの発話フェーズ中、ユーザーの発話を文字化する。
///
/// iOS / Android ともに「録音 → タイマー終了後に文字起こし」方式。
/// iOS:     AVAudioRecorder で録音 → SFSpeechURLRecognitionRequest で変換（ネイティブ MethodChannel）。
/// Android: 無音録音               → SpeechRecognizer（ファイル入力）→ 失敗時のみVoskにフォールバック。
class SpeechRecognitionService extends ChangeNotifier {
  static const _captureChannelName =
      'com.osamushikubo.osm_washabe/speech_capture';
  final MethodChannel _captureChannel =
      const MethodChannel(_captureChannelName);

  bool _sessionActive = false;
  bool _recording = false;
  bool _isTranscribing = false;
  double _scoringProgress = 0;
  String _scoringProgressPhaseKey = '採点中_音声解析';

  final List<TranscriptChunk> _chunks = [];
  final List<String> _debugLog = [];

  String? _lastRecordingPath;
  DateTime? _sessionStartedAt;
  DateTime? _sessionEndedAt;

  bool _pausedKeeperForListening = false;
  bool _stoppedKeeperForListening = false;

  // ── 採点1回分（1お題）の冪等性を守る3変数 ──────────────────────────────
  // `drawTopic()` は前の採点の完了を待たず unawaited で
  // stopSession() を呼べるため、同じお題に対して stopSession() が複数回
  // 実行されうる。この3つで「今回のお題は録音が始まったか」「文字起こし
  // 済みか」を判定し、二重の文字起こし・多重 notifyListeners() を防ぐ。
  //   _captureAttempt         : お題が変わるたびに +1 する通し番号。
  //   _finalizedCaptureAttempt: 文字起こしが完了した _captureAttempt の値。
  //                             現在値と一致していれば「このお題は処理済み」。
  //   _captureRecordingStarted: 今回のお題で実際に録音が開始したか。
  int _captureAttempt = 0;
  int? _finalizedCaptureAttempt;
  bool _captureRecordingStarted = false;

  static const _modelPrepProgressShare = 0.3;

  // ── 公開ゲッター ──────────────────────────────────────────────────────────

  List<TranscriptChunk> get chunks => List.unmodifiable(_chunks);
  String? get lastRecordingPath => _lastRecordingPath;
  List<String> get debugLog => List.unmodifiable(_debugLog);

  /// 発話フェーズ中（録音中）
  bool get isCaptureRecording => _recording;

  /// タイマー終了後の文字起こし処理中
  bool get isTranscribing => _isTranscribing;

  /// 文字起こし全体進捗（0.0〜1.0）。Android のみ更新。iOS は常に 0。
  double get scoringProgress => _scoringProgress;

  /// [scoringProgress] の説明文キー
  String get scoringProgressPhaseKey => _scoringProgressPhaseKey;

  /// 今回のお題で録音が実際に始まっているか。
  bool get hasCaptureForCurrentAttempt =>
      _captureRecordingStarted &&
      (_sessionActive || _finalizedCaptureAttempt == _captureAttempt);

  // ── 公開 API ──────────────────────────────────────────────────────────────

  /// TTS 再生中に Vosk モデルをバックグラウンド準備する（Android のみ有効）。
  Future<void> preWarm() async {
    if (_sessionActive || !Platform.isAndroid) return;
    _log('preWarm (Android)');
    AndroidVoskWarmup.scheduleIfNeeded(scoringEnabled: true);
  }

  /// 新しいお題の採点を始める前に呼ぶ。
  /// 前回の認識テキストを無効化し、録音ファイルを削除する。
  void prepareForNewCapture() {
    _captureAttempt++;
    _finalizedCaptureAttempt = null;
    _captureRecordingStarted = false;
    _chunks.clear();
    final prevPath = _lastRecordingPath;
    if (prevPath != null) {
      _lastRecordingPath = null;
      unawaited(() async {
        try {
          await File(prevPath).delete();
        } catch (_) {}
      }());
    }
    if (!_sessionActive) {
      _sessionStartedAt = null;
      _sessionEndedAt = null;
    }
  }

  /// 発話フェーズ開始時に呼ぶ。録音を開始する。録音が開始できたら true。
  Future<bool> startSession() async {
    if (!await PrivacyService.hasCurrentSpeechConsent()) {
      _log('録音開始を中止: 現行版の音声認識同意なし');
      return false;
    }
    _chunks.clear();
    _debugLog.clear();
    _sessionStartedAt = null;
    _sessionEndedAt = null;
    _sessionActive = true;
    _captureRecordingStarted = false;
    _log('--- 発話セッション開始 ---');
    notifyListeners();

    if (Platform.isAndroid) return _startAndroidSession();
    return _startIosSession();
  }

  /// 発話フェーズ終了時に呼ぶ。録音停止 → 文字起こし → チャンクを返す。
  ///
  /// [resumeKeeper] を false にするとキープアライブ復帰を遅延できる。
  /// 完了音など別の AVAudio 処理の直前に使い競合を避ける。
  Future<List<TranscriptChunk>> stopSession({
    bool resumeKeeper = true,
    bool transcribe = true,
  }) async {
    // 冪等性: _recording が残っていれば停止処理を続行する。
    // drawTopic() が unawaited で stopSession() を呼ぶため二重呼び出しが起きうる。
    final needsFinalize = transcribe && (_sessionActive || _recording);
    // iOS: stopIosCapture() で先に録音を止めた後でも文字起こしが必要な場合がある
    final needsIosTranscription = !Platform.isAndroid &&
        transcribe &&
        !_recording &&
        _lastRecordingPath != null &&
        _finalizedCaptureAttempt != _captureAttempt;
    if (!_sessionActive && !needsFinalize && !needsIosTranscription) {
      if (_finalizedCaptureAttempt == _captureAttempt) {
        return List.unmodifiable(_chunks);
      }
      return const [];
    }

    _sessionActive = false;

    if (Platform.isAndroid) {
      return _stopAndroidSession(
          resumeKeeper: resumeKeeper, transcribe: transcribe);
    }
    return _stopIosSession(resumeKeeper: resumeKeeper, transcribe: transcribe);
  }

  /// iOS のみ: AVAudioRecorder を停止してパスをキャッシュする（文字起こしは行わない）。
  /// 完了音を鳴らす前に AVAudioSession を録音モードから解放するために使う。
  /// 続けて [stopSession] を呼ぶと文字起こしが実行される。
  Future<void> stopIosCapture() async {
    if (!Platform.isIOS || !_recording) return;
    _sessionActive = false;
    _sessionEndedAt = DateTime.now();
    try {
      final path = await _captureChannel
          .invokeMethod<String>('stopCapture')
          .timeout(const Duration(seconds: 5));
      _recording = false;
      if (path != null) _lastRecordingPath = path;
    } catch (e) {
      _log('stopIosCapture 失敗: $e');
      _recording = false;
    }
    notifyListeners();
  }

  /// [stopSession] で遅延したキープアライブ復帰を別の音声処理の後に呼ぶ。
  Future<void> resumeKeeperIfPaused() async {
    try {
      await _resumeKeeperIfNeeded().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  SpeechSessionContext sessionContext({required int allottedSeconds}) =>
      SpeechSessionContext(
        allottedSeconds: allottedSeconds,
        startedAt: _sessionStartedAt,
        endedAt: _sessionEndedAt,
      );

  @override
  void dispose() {
    _sessionActive = false;
    if (Platform.isAndroid) {
      unawaited(AndroidOfflineSpeechPlatform.cancelRecording());
    } else {
      unawaited(
          _captureChannel.invokeMethod<void>('stopCapture').catchError((_) {}));
    }
    super.dispose();
  }

  // ── iOS ──────────────────────────────────────────────────────────────────

  Future<bool> _startIosSession() async {
    await _pauseKeeperForListening();
    if (!_sessionActive) return false;

    final String outputPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      outputPath = '${dir.path}/last_recording.m4a';
    } catch (e) {
      _log('録音パス取得失敗: $e');
      return _abortStart();
    }
    if (!_sessionActive) return false;

    try {
      final ok = await _captureChannel.invokeMethod<bool>('startCapture',
          {'outputPath': outputPath}).timeout(const Duration(seconds: 5));
      if (ok != true) {
        _log('startCapture: 開始失敗');
        return _abortStart();
      }
      _recording = true;
      _sessionStartedAt = DateTime.now();
      _captureRecordingStarted = true;
      _log('録音開始(iOS)');
      notifyListeners();
      return true;
    } catch (e) {
      _log('startCapture例外: $e');
      return _abortStart();
    }
  }

  Future<List<TranscriptChunk>> _stopIosSession({
    required bool resumeKeeper,
    required bool transcribe,
  }) async {
    _sessionEndedAt ??= DateTime.now();
    _log('stopSession(iOS)');

    String? path;
    if (_recording) {
      // まだ録音中なら停止する
      try {
        path = await _captureChannel
            .invokeMethod<String>('stopCapture')
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _log('録音停止失敗: $e');
      }
      _recording = false;
      if (path != null) _lastRecordingPath = path;
    } else {
      // stopIosCapture() で先に停止済みの場合はキャッシュ済みパスを使う
      path = _lastRecordingPath;
    }

    if (path != null) {
      _lastRecordingPath = path;
      if (transcribe) {
        _isTranscribing = true;
        notifyListeners();
        try {
          final sessionStart =
              _sessionStartedAt ?? _sessionEndedAt ?? DateTime.now();
          final raw = await _captureChannel.invokeMethod<List<dynamic>>(
              'transcribeFile',
              {'path': path}).timeout(const Duration(seconds: 30));
          final iOSChunks =
              _chunksFromIosSegments(raw ?? [], sessionStart: sessionStart);
          _chunks.addAll(iOSChunks);
          final totalChars = iOSChunks.fold(0, (n, c) => n + c.text.length);
          _log('文字起こし完了: ${iOSChunks.length}フレーズ $totalChars字');
        } catch (e) {
          _log('文字起こし失敗: $e');
        } finally {
          _isTranscribing = false;
        }
      }
    } else if (transcribe) {
      _log('stopSession(iOS): 録音ファイルなし');
    }

    return _finalize(resumeKeeper: resumeKeeper);
  }

  // ── Android ───────────────────────────────────────────────────────────────

  Future<bool> _startAndroidSession() async {
    if (!_sessionActive) return false;
    await _pauseKeeperForListening();
    if (!_sessionActive) return false;

    var permitted = await AndroidOfflineSpeechPlatform.hasRecordPermission();
    if (!permitted) {
      permitted = await AndroidOfflineSpeechPlatform.requestRecordPermission();
    }
    _log('録音許可: $permitted');
    if (!permitted) return _abortStart();

    try {
      await ensureSpeechCaptureAudioSession();
      await Future.delayed(const Duration(milliseconds: 350));
      if (!_sessionActive) return false;

      final ok = await AndroidOfflineSpeechPlatform.startRecording();
      if (!ok) {
        _log('録音開始失敗');
        return _abortStart();
      }
      _recording = true;
      _sessionStartedAt = DateTime.now();
      _captureRecordingStarted = true;
      _log('録音開始(Android)');
      notifyListeners();
      return true;
    } catch (e) {
      _log('録音開始例外: $e');
      _recording = false;
      _sessionActive = false;
      await AndroidOfflineSpeechPlatform.cancelRecording();
      await _resumeKeeperIfNeeded();
      notifyListeners();
      return false;
    }
  }

  Future<List<TranscriptChunk>> _stopAndroidSession({
    required bool resumeKeeper,
    required bool transcribe,
  }) async {
    _sessionEndedAt = DateTime.now();
    _log('stopSession(Android)');

    String? wavPath;
    if (_recording) {
      try {
        wavPath = await AndroidOfflineSpeechPlatform.stopRecording()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _log('録音停止失敗: $e');
      }
      _recording = false;
    } else {
      await AndroidOfflineSpeechPlatform.cancelRecording();
    }

    if (wavPath != null) {
      _log('録音ファイル: ${await File(wavPath).length()}bytes');
      if (transcribe) await _androidTranscribe(wavPath);
      // 再生ボタン用に documents へ保存
      try {
        final dir = await getApplicationDocumentsDirectory();
        final savePath = '${dir.path}/last_recording.wav';
        await File(wavPath).copy(savePath);
        _lastRecordingPath = savePath;
        await File(wavPath).delete();
      } catch (_) {
        try {
          await File(wavPath).delete();
        } catch (_) {}
      }
    } else if (transcribe) {
      _log('stopSession(Android): 録音ファイルなし');
    }

    try {
      await ensureSpeechAudioSession();
    } catch (_) {}

    return _finalize(resumeKeeper: resumeKeeper);
  }

  Future<void> _androidTranscribe(String wavPath) async {
    _isTranscribing = true;
    _resetScoringProgress();
    notifyListeners();
    StreamSubscription<double>? progressSub;
    try {
      _setScoringProgress(0, phaseKey: '採点中_音声解析');
      notifyListeners();
      final onlineText = await AndroidOfflineSpeechPlatform.recognizeOnline(
        wavPath,
        onFailureReason: (reason) => _log('オンライン認識失敗理由: $reason'),
      );
      if (onlineText != null) {
        final started = _sessionStartedAt ?? DateTime.now();
        _chunks.add(TranscriptChunk(text: onlineText, recognizedAt: started));
        _setScoringProgress(1, phaseKey: '採点中_音声解析');
        _log('文字起こし完了(オンライン): ${onlineText.length}字');
        return;
      }
      _log('オンライン認識不可、Voskにフォールバック');

      final modelReady = await VoskModelManager.isReady();
      if (!modelReady) {
        _setScoringProgress(0, phaseKey: '採点中_モデル準備');
        notifyListeners();
        await VoskModelManager.ensureReady(
          onProgress: (p) {
            _setScoringProgress(p * _modelPrepProgressShare,
                phaseKey: '採点中_モデル準備');
            notifyListeners();
          },
        ).timeout(const Duration(minutes: 10));
      }
      final base = modelReady ? 0.0 : _modelPrepProgressShare;
      final span = modelReady ? 1.0 : 1.0 - _modelPrepProgressShare;
      _setScoringProgress(base, phaseKey: '採点中_音声解析');
      notifyListeners();

      progressSub =
          AndroidOfflineSpeechPlatform.transcribeProgressStream().listen((f) {
        if (f > 1.0) {
          _setScoringProgress(0, phaseKey: '採点中_モデル読み込み');
        } else {
          _setScoringProgress(base + f * span, phaseKey: '採点中_音声解析');
        }
        notifyListeners();
      });

      final modelPath = await VoskModelManager.modelPath();
      _log('文字起こし開始');
      final segments = await AndroidOfflineSpeechPlatform.transcribe(
        modelPath: modelPath,
        wavPath: wavPath,
      ).timeout(const Duration(seconds: 120));
      _chunks.addAll(_chunksFromSegments(segments));
      _setScoringProgress(1, phaseKey: '採点中_音声解析');
      _log('文字起こし完了: segments=${segments.length} chunks=${_chunks.length}');
    } catch (e) {
      _log('文字起こし失敗: $e');
    } finally {
      await progressSub?.cancel();
      _isTranscribing = false;
      _resetScoringProgress();
    }
  }

  /// Apple STT の単語セグメント列を、0.8秒以上のポーズでフレーズ単位に束ねる。
  /// recognizedAt にはセッション開始時刻 + 各フレーズの開始オフセットを使う。
  List<TranscriptChunk> _chunksFromIosSegments(
    List<dynamic> segments, {
    required DateTime sessionStart,
  }) {
    if (segments.isEmpty) return const [];
    const phraseBreakGap = 0.8; // 秒: これ以上の語間ポーズで新フレーズ
    final chunks = <TranscriptChunk>[];
    final buf = StringBuffer();
    var phraseStartTs = 0.0;
    var prevEndTs = 0.0;

    for (final raw in segments) {
      final seg = Map<String, dynamic>.from(raw as Map);
      final word = (seg['text'] as String? ?? '').trim();
      if (word.isEmpty) continue;
      final ts = (seg['timestamp'] as num?)?.toDouble() ?? 0.0;
      final dur = (seg['duration'] as num?)?.toDouble() ?? 0.2;

      if (buf.isNotEmpty && ts - prevEndTs > phraseBreakGap) {
        chunks.add(TranscriptChunk(
          text: buf.toString().trim(),
          recognizedAt: sessionStart
              .add(Duration(milliseconds: (phraseStartTs * 1000).round())),
        ));
        buf.clear();
        phraseStartTs = ts;
      }
      if (buf.isEmpty) phraseStartTs = ts;
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(word);
      prevEndTs = ts + dur;
    }
    if (buf.isNotEmpty) {
      chunks.add(TranscriptChunk(
        text: buf.toString().trim(),
        recognizedAt: sessionStart
            .add(Duration(milliseconds: (phraseStartTs * 1000).round())),
      ));
    }
    return chunks;
  }

  List<TranscriptChunk> _chunksFromSegments(
      List<OfflineSpeechSegment> segments) {
    final started = _sessionStartedAt;
    if (started == null || segments.isEmpty) return const [];
    return segments
        .map((s) => TranscriptChunk(
              text: s.text,
              recognizedAt: started
                  .add(Duration(milliseconds: (s.startSec * 1000).round())),
            ))
        .toList(growable: false);
  }

  // ── 共通ヘルパー ──────────────────────────────────────────────────────────

  Future<void> _pauseKeeperForListening() async {
    if (!BackgroundAudioKeeper.instance.isRunning) return;
    if (Platform.isAndroid) {
      _stoppedKeeperForListening = true;
      try {
        await BackgroundAudioKeeper.instance
            .stop()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      return;
    }
    _pausedKeeperForListening = true;
    try {
      await BackgroundAudioKeeper.instance
          .pauseForSpeech()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _resumeKeeperIfNeeded() async {
    if (_stoppedKeeperForListening) {
      _stoppedKeeperForListening = false;
      try {
        await BackgroundAudioKeeper.instance
            .start()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      return;
    }
    if (!_pausedKeeperForListening) return;
    _pausedKeeperForListening = false;
    await BackgroundAudioKeeper.instance.resumeAfterSpeech();
  }

  /// 録音開始失敗時の共通後始末。常に false を返す。
  Future<bool> _abortStart() async {
    _sessionActive = false;
    await _resumeKeeperIfNeeded();
    notifyListeners();
    return false;
  }

  /// stopSession 末尾の共通処理（keeper 復帰・フラグ確定・通知）。
  Future<List<TranscriptChunk>> _finalize({required bool resumeKeeper}) async {
    if (resumeKeeper) {
      try {
        await _resumeKeeperIfNeeded().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _finalizedCaptureAttempt = _captureAttempt;
    _log('stopSession: 完了 (chunks=${_chunks.length})');
    notifyListeners();
    return List.unmodifiable(_chunks);
  }

  void _resetScoringProgress() {
    _scoringProgress = 0;
    _scoringProgressPhaseKey = '採点中_音声解析';
  }

  void _setScoringProgress(double value, {String? phaseKey}) {
    _scoringProgress = value.clamp(0.0, 1.0);
    if (phaseKey != null) _scoringProgressPhaseKey = phaseKey;
  }

  void _log(String message) {
    final stamped =
        '${DateTime.now().toIso8601String().substring(11, 19)} $message';
    _debugLog.add(stamped);
    if (_debugLog.length > 30) _debugLog.removeAt(0);
    unawaited(SpeechRecognitionDebugLogStore.append(stamped));
  }
}
