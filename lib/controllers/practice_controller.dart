import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:uuid/uuid.dart';

import '../data/mock_exam_planner.dart';
import '../data/topic_repository.dart';
import '../models/practice_models.dart';
import '../models/topic.dart';
import '../notifiers/app_settings.dart';
import '../services/app_preferences.dart';
import '../services/android_vosk_warmup.dart';
import '../services/background_audio_keeper.dart';
import '../services/crash_log_service.dart';
import '../services/jsst_scoring_service.dart';
import '../services/native_tts_platform.dart';
import '../services/speech_recognition_service.dart';
import '../services/timer_alert.dart';
import '../services/timer_notification_scheduler.dart';
import '../services/tick_beep_player.dart';
import '../services/topic_speech_reader.dart';

/// iOS `ContentView` のタイマー・模試・TTS ロジックを集約
class PracticeController extends ChangeNotifier {
  PracticeController({
    required AppSettingsNotifier settings,
    required TopicRepository topicRepository,
    required TopicSpeechReader speechReader,
    required TimerAlert timerAlert,
    required SpeechRecognitionService speechRecognition,
    AppPreferences? preferences,
  })  : _settings = settings,
        _topics = topicRepository,
        _speech = speechReader,
        _alert = timerAlert,
        _speechRecognition = speechRecognition,
        _prefs = preferences {
    _speechRecognition.addListener(notifyListeners);
  }

  static const mockExamPostCompletionDelay = Duration(milliseconds: 1200);
  static const mockExamPreCountdownDelay = Duration(milliseconds: 600);
  /// 「15秒間考えてください」読み上げ後、カウント表示までの間（一息）
  static const preparationBreathDelay = Duration(milliseconds: 1000);

  /// 音声案内は日本語スピーチ練習用のため、UI 言語に関わらず日本語のまま。
  String _ttsPrepPrompt(String text) => '$text。15秒間考えてください。';

  static const _ttsAnswerPrompt = 'それでは、答えてください。';

  static const _ttsMockExamQ10Prefix = '問題10は必ず敬語を使って話してください。';

  static const _ttsMockExamComplete = '以上で終了です。お疲れ様でした！';

  final AppSettingsNotifier _settings;
  final TopicRepository _topics;
  final TopicSpeechReader _speech;
  final TimerAlert _alert;
  final SpeechRecognitionService _speechRecognition;
  final AppPreferences? _prefs;
  final _uuid = const Uuid();

  /// 単発お題モードの直前の発話に対する採点結果（待遇表現・テキストタイプの2軸近似）。
  ScoringResult? scoringResult;

  /// 直近5回分の採点結果。履歴OFFのときはお題を引き直す都度リセット。
  final List<ScoringResult> _scoringHistory = [];
  List<ScoringResult> get scoringHistory => List.unmodifiable(_scoringHistory);

  void clearScoringHistory() {
    _scoringHistory.clear();
    scoringResult = null;
    notifyListeners();
  }

  /// 発話終了〜採点結果確定までの間 true。結果シートを即時に開き、
  /// ロード中の表示を出すために main_view から参照される。
  bool isAwaitingScoring = false;

  /// 直前の発話フェーズで STT が記録した秒数（45 または 60）
  int _speechAllottedSeconds = 45;

  /// 原因調査用: 直前の音声認識サイクルのログ（許可状態・認識結果・エラー）
  List<String> get speechRecognitionDebugLog => _speechRecognition.debugLog;

  bool get isOfflineTranscribing => _speechRecognition.isTranscribing;

  bool get isCaptureRecording => _speechRecognition.isCaptureRecording;

  /// 直前の発話フェーズで録音したファイルのパス（再生ボタン用）。
  /// 次の prepareForNewCapture() でクリアされる。
  String? get lastRecordingPath => _speechRecognition.lastRecordingPath;

  double get scoringProgress => _speechRecognition.scoringProgress;

  String get scoringProgressPhaseKey =>
      _speechRecognition.scoringProgressPhaseKey;

  AppSessionMode sessionMode = AppSessionMode.singleQuestion;
  TrainingMode mode = TrainingMode.normal;
  NormalTimerOption normalTimerOption = NormalTimerOption.sec45;
  TopicCategory category = TopicCategory.daily;

  String currentTopic = '';
  SituationPrompt? currentSituation;
  bool hasDrawnTopic = false;

  int remainingSeconds = 45;
  bool isTimerRunning = false;
  SituationTimerPhase situationPhase = SituationTimerPhase.preparation;
  DateTime? backgroundedAt;
  DateTime? activePhaseDeadline;
  bool _isCompletingPreparationPhase = false;

  List<MockExamStep> mockExamSteps = [];
  int mockExamStepIndex = 0;
  bool isMockExamActive = false;
  bool isMockExamFinished = false;
  String mockExamRunId = '';
  int mockExamStartIndex = 0;
  bool showAbortConfirmation = false;

  Timer? _tickTimer;
  int _singleLoopToken = 0;
  int _intervalToken = 0;
  String? _mockExamIntervalRunId;
  bool _scoredQuestionFlowActive = false;

  int intervalRemainingSeconds = 0;
  bool get isInInterval => intervalRemainingSeconds > 0;

  bool get isSpeaking => _speech.isSpeaking;
  bool get isUtteranceActive => _speech.isUtteranceActive;

  bool _isFlowCurrent(int flowToken) => _singleLoopToken == flowToken;

  void _clearIntervalCountdown() {
    if (intervalRemainingSeconds <= 0) return;
    intervalRemainingSeconds = 0;
  }
  bool get isPaused => _speech.isPaused;
  bool get mockExamShowQuestion => _settings.mockExamShowQuestion;

  TrainingMode get activeTrainingMode {
    if (sessionMode == AppSessionMode.mockExam &&
        isMockExamActive &&
        mockExamStepIndex < mockExamSteps.length) {
      switch (mockExamSteps[mockExamStepIndex].kind) {
        case MockExamQuestionKind.normal45:
        case MockExamQuestionKind.normal60:
          return TrainingMode.normal;
        case MockExamQuestionKind.normal15plus60:
        case MockExamQuestionKind.situationKeigo:
          return TrainingMode.situation;
      }
    }
    return mode;
  }

  bool get usesTwoPhaseTimer {
    return activeTrainingMode == TrainingMode.situation ||
        (sessionMode == AppSessionMode.singleQuestion &&
            mode == TrainingMode.normal &&
            normalTimerOption == NormalTimerOption.prep15speaking60);
  }

  bool get isAwaitingSpeakingPhaseStart {
    return usesTwoPhaseTimer &&
        situationPhase == SituationTimerPhase.preparation &&
        remainingSeconds == 0 &&
        !isTimerRunning;
  }

  bool get needsTimerBackgroundSync {
    // Android: keeper が起動していても実際に再生していない場合（OS が停止）も同期が必要
    if (Platform.isAndroid) {
      return !BackgroundAudioKeeper.instance.isActuallyPlaying;
    }
    // iOS 準備15秒はキープアライブを意図的に止めている（ティック音優先）ので同期不要
    if (usesTwoPhaseTimer &&
        situationPhase == SituationTimerPhase.preparation &&
        isTimerRunning) {
      return false;
    }
    return !BackgroundAudioKeeper.instance.isRunning;
  }

  bool get isTimerFinished {
    if (usesTwoPhaseTimer) {
      return situationPhase == SituationTimerPhase.speaking &&
          remainingSeconds == 0;
    }
    return remainingSeconds == 0;
  }

  MockExamStep? get currentMockExamStep {
    if (sessionMode != AppSessionMode.mockExam ||
        !isMockExamActive ||
        mockExamStepIndex >= mockExamSteps.length) {
      return null;
    }
    return mockExamSteps[mockExamStepIndex];
  }

  String get phaseLabel {
    if (!isTimerRunning && remainingSeconds > 0) {
      return usesTwoPhaseTimer
          ? '${situationPhase.label}・停止中'
          : '停止中';
    }
    if (isTimerFinished && !isTimerRunning) return '時間終了';
    if (usesTwoPhaseTimer) return '${situationPhase.label}中';
    return isTimerRunning ? '計測中' : '停止中';
  }

  String get displayTopicText {
    if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
      final step = currentMockExamStep;
      if (step == null) return '';
      switch (step.kind) {
        case MockExamQuestionKind.normal45:
        case MockExamQuestionKind.normal60:
        case MockExamQuestionKind.normal15plus60:
          return currentTopic;
        case MockExamQuestionKind.situationKeigo:
          return currentSituation?.readableText ?? '';
      }
    }
    return currentTopic;
  }

  void startTicking() {
    _tickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => tickTimer());
  }

  void disposeTicking() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  // --- Session / mode changes ---

  /// セッション・モード切り替え前の共通クリーンアップ。
  void _resetForModeSwitch() {
    _singleLoopToken++;
    intervalRemainingSeconds = 0;
    scoringResult = null;
    isAwaitingScoring = false;
    _speechRecognition.prepareForNewCapture();
    unawaited(endSingleQuestionKeepAlive());
    unawaited(_speechRecognition.stopSession(transcribe: false));
    unawaited(_speech.stop());
    stopTimer();
  }

  void setSessionMode(AppSessionMode value) {
    if (sessionMode == value) return;
    _resetForModeSwitch();
    resetMockExamState();
    sessionMode = value;
    if (value == AppSessionMode.singleQuestion) {
      resetTimerState(activeTrainingMode);
      // Android: 採点ONなら Vosk モデルをバックグラウンドで準備。
      if (Platform.isAndroid && _settings.scoringEnabled) {
        AndroidVoskWarmup.scheduleIfNeeded(scoringEnabled: true);
      }
    }
    notifyListeners();
  }

  void setNormalTimerOption(NormalTimerOption value) {
    if (normalTimerOption == value ||
        sessionMode != AppSessionMode.singleQuestion) {
      return;
    }
    normalTimerOption = value;
    mode = TrainingMode.normal;
    // シチュエーションカテゴリは15+60秒モード専用なので、他のモードへ切替時にリセット
    if (value != NormalTimerOption.prep15speaking60 &&
        category == TopicCategory.situation) {
      category = TopicCategory.daily;
    }
    drawTopic();
  }

  void setCategory(TopicCategory value) {
    if (category == value) return;
    category = value;
    drawTopic();
  }

  // --- Topic drawing ---

  /// drawTopic の共通クリーンアップ。
  void _tearDownForNewQuestion({
    bool skipAudioTeardown = false,
    bool endKeepAlive = true,
  }) {
    _singleLoopToken++;
    intervalRemainingSeconds = 0;
    scoringResult = null;
    if (!_settings.scoringHistoryEnabled) _scoringHistory.clear();
    isAwaitingScoring = false;
    if (!skipAudioTeardown) {
      _speechRecognition.prepareForNewCapture();
      unawaited(_speechRecognition.stopSession(transcribe: false));
      unawaited(_speech.stop());
    }
    _speech.clearGenderLock();
    stopTimer();
    resetTimerState(activeTrainingMode);
    if (endKeepAlive) unawaited(endSingleQuestionKeepAlive());
  }

  void drawTopic({bool endKeepAlive = true, bool skipAudioTeardown = false}) {
    _scoredQuestionFlowActive = false;
    _tearDownForNewQuestion(
      skipAudioTeardown: skipAudioTeardown,
      endKeepAlive: endKeepAlive,
    );
    // 15+60秒のランダムはシチュエーションも含む専用プールを使う
    final pool = (normalTimerOption == NormalTimerOption.prep15speaking60 &&
            category == TopicCategory.random)
        ? _topics.allTopicsForPrep15Random()
        : _topics.allTopics(category);
    if (pool.isEmpty) return;
    currentTopic = pool[Random().nextInt(pool.length)];
    hasDrawnTopic = true;
    currentSituation = null;
    notifyListeners();
  }

  /// 次のお題へ進む前に読み上げ・採点用 STT を止め、TTS 向けに playback へ戻す。
  Future<void> _stopSpeechAndScoringForNewQuestion() async {
    await _speech.stop();
    _speechRecognition.prepareForNewCapture();
    await _speechRecognition.stopSession(transcribe: false);
    await _speechRecognition.resumeKeeperIfPaused();
    await BackgroundAudioKeeper.instance.stop();
    await _speech.setSessionKeepAlive(false);
    await ensureSpeechAudioSession();
  }

  /// iOS 準備15秒中はキープアライブを止める（無音ループとティック音が競合するため）。
  Future<void> _suspendKeepAliveForPreparation() async {
    if (Platform.isAndroid) return;
    await BackgroundAudioKeeper.instance.stop();
    await _speech.setSessionKeepAlive(false);
  }

  /// 採点ONの単発お題モードでは、自動進行の代わりにサイコロボタンが
  /// 「次のお題を引いて読み上げ開始」を兼ねる
  Future<void> shuffleTopic() async {
    if (sessionMode == AppSessionMode.mockExam) return;

    // 前回フローがハングした場合の復旧（連打ブロックの解除）
    if (_scoredQuestionFlowActive) {
      await _speech.stop();
      _speechRecognition.prepareForNewCapture();
      await _speechRecognition.stopSession(transcribe: false);
      _scoredQuestionFlowActive = false;
    }
    if (_speech.isUtteranceActive) return;

    final autoSpeak =
        sessionMode == AppSessionMode.singleQuestion && _settings.scoringEnabled;

    if (!autoSpeak) {
      drawTopic();
      return;
    }

    _scoredQuestionFlowActive = true;
    try {
      await _stopSpeechAndScoringForNewQuestion();
      drawTopic(endKeepAlive: true, skipAudioTeardown: true);
      if (!hasDrawnTopic || currentTopic.isEmpty) return;
      final flowToken = _singleLoopToken;
      final text = currentTopic;
      if (normalTimerOption == NormalTimerOption.prep15speaking60) {
        await _runScoredTwoPhaseQuestion(flowToken: flowToken, text: text);
      } else {
        await _runScoredNormalQuestion(flowToken: flowToken, text: text);
      }
    } finally {
      _scoredQuestionFlowActive = false;
      notifyListeners();
    }
  }

  /// iOS `handleShakeGesture()` 相当（1問ずつのみ）
  Future<void> handleShakeGesture() async {
    if (sessionMode != AppSessionMode.singleQuestion) return;
    // タイマー計測中・インターバル中・トピック読み上げ中のシェイクは誤操作として無視する
    if (isTimerRunning ||
        isInInterval ||
        _speech.isUtteranceActive ||
        _scoredQuestionFlowActive) {
      return;
    }
    // autoSpeak 時は drawTopic の endSingleQuestionKeepAlive を
    // スキップし、keepalive を維持したまま読み上げを開始する（Android 音声セッション競合回避）
    final autoSpeak = _settings.shakeAutoSpeak;
    drawTopic(endKeepAlive: !autoSpeak);
    if (!autoSpeak || !hasDrawnTopic || currentTopic.isEmpty) {
      return;
    }
    if (normalTimerOption == NormalTimerOption.prep15speaking60) {
      await startTwoPhaseSpeechAndTimer(currentTopic);
    } else {
      await startNormalSpeechAndTimer(currentTopic);
    }
  }

  // --- Timer controls ---

  void toggleTimer() {
    if (isTimerRunning) {
      stopTimer();
    } else if (isAwaitingSpeakingPhaseStart) {
      recoverStuckPreparationPhaseIfNeeded(force: true);
    } else if (!isTimerFinished && remainingSeconds > 0) {
      if (usesTwoPhaseTimer &&
          situationPhase == SituationTimerPhase.preparation) {
        startPreparationCountdown();
      } else {
        markPhaseDeadlineFromRemainingSeconds();
        isTimerRunning = true;
        _persistTimerState();
        _scheduleCompletionNotificationIfNeeded();
      }
    }
    notifyListeners();
  }

  void resetTimer() {
    _singleLoopToken++;
    intervalRemainingSeconds = 0;
    stopTimer();
    resetTimerState(activeTrainingMode);
    endSingleQuestionKeepAlive();
    notifyListeners();
  }

  void stopTimer() {
    isTimerRunning = false;
    activePhaseDeadline = null;
    unawaited(TimerNotificationScheduler.instance.cancel());
    _clearPersistedTimerState();
  }

  void resetTimerState(TrainingMode timerMode) {
    situationPhase = SituationTimerPhase.preparation;
    activePhaseDeadline = null;

    if (sessionMode == AppSessionMode.mockExam) {
      final step = currentMockExamStep;
      if (step != null) {
        remainingSeconds = switch (step.kind) {
          MockExamQuestionKind.normal45 => 45,
          MockExamQuestionKind.normal60 => 60,
          MockExamQuestionKind.normal15plus60 ||
          MockExamQuestionKind.situationKeigo =>
            SituationTimerPhase.preparation.durationSeconds,
        };
        return;
      }
    }

    switch (timerMode) {
      case TrainingMode.normal:
        if (normalTimerOption == NormalTimerOption.prep15speaking60) {
          remainingSeconds =
              SituationTimerPhase.preparation.durationSeconds;
        } else {
          remainingSeconds = normalTimerOption == NormalTimerOption.sec60
              ? 60
              : 45;
        }
      case TrainingMode.situation:
        remainingSeconds = SituationTimerPhase.preparation.durationSeconds;
    }
  }

  // --- Speech + timer flows ---

  Future<void> _prepareAndroidTts() async {
    if (!Platform.isAndroid) return;
    await NativeTtsPlatform.ensureReady();
    await ensureSpeechAudioSession();
  }

  void _startNormalTimerPhase() {
    markPhaseDeadlineFromRemainingSeconds();
    isTimerRunning = true;
    _persistTimerState();
    _scheduleCompletionNotificationIfNeeded();
    if (_tickTimer == null) startTicking();
    notifyListeners();
  }

  Future<void> _speakTopicText(
    String text, {
    required int flowToken,
    VoidCallback? onSpeakFinished,
  }) async {
    await _prepareAndroidTts();
    if (!_isFlowCurrent(flowToken)) return;

    final spoke = await _speech.speak(
      text: text,
      onFinish: onSpeakFinished,
    );
    if (!_isFlowCurrent(flowToken)) return;

    if (!spoke && Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!_isFlowCurrent(flowToken)) return;
      await _prepareAndroidTts();
      final retrySpoke = await _speech.speak(
        text: text,
        onFinish: onSpeakFinished,
      );
      if (!retrySpoke) onSpeakFinished?.call();
    }
  }

  /// _runScoredNormalQuestion / _runScoredTwoPhaseQuestion の共通初期化。
  void _resetScoredQuestionState(TrainingMode timerMode) {
    stopTimer();
    resetTimerState(timerMode);
    scoringResult = null;
    isAwaitingScoring = false;
    _speechRecognition.prepareForNewCapture();
  }

  Future<void> _runScoredNormalQuestion({
    required int flowToken,
    required String text,
  }) async {
    _resetScoredQuestionState(TrainingMode.normal);

    var timerStarted = false;
    void tryStartTimer() {
      if (timerStarted || !_isFlowCurrent(flowToken)) return;
      timerStarted = true;
      _startNormalTimerPhase();
    }

    if (Platform.isAndroid) {
      await _speakTopicText(
        text,
        flowToken: flowToken,
        onSpeakFinished: tryStartTimer,
      );
      if (!_isFlowCurrent(flowToken)) return;
      tryStartTimer();
      if (!_isFlowCurrent(flowToken)) return;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!_isFlowCurrent(flowToken)) return;
      await _startSpeechCaptureIfNeeded(flowToken: flowToken);
      if (!_isFlowCurrent(flowToken)) return;
      await beginSingleQuestionKeepAlive();
    } else {
      if (!_isFlowCurrent(flowToken)) return;
      final spoke = await _speech.speak(text: text, onFinish: tryStartTimer);
      if (!_isFlowCurrent(flowToken)) return;
      if (!spoke) return;
      tryStartTimer();
      if (!_isFlowCurrent(flowToken)) return;
      await _startSpeechCaptureIfNeeded(flowToken: flowToken);
      if (!_isFlowCurrent(flowToken)) return;
      await beginSingleQuestionKeepAlive();
    }
  }

  Future<void> _runScoredTwoPhaseQuestion({
    required int flowToken,
    required String text,
  }) async {
    _resetScoredQuestionState(activeTrainingMode);

    final prompt = _ttsPrepPrompt(text);

    if (Platform.isAndroid) {
      await _speakTopicText(
        prompt,
        flowToken: flowToken,
      );
      if (!_isFlowCurrent(flowToken)) return;
    } else {
      if (!_isFlowCurrent(flowToken)) return;
      await _suspendKeepAliveForPreparation();
      final spoke = await _speech.speak(text: prompt);
      if (!_isFlowCurrent(flowToken)) return;
      if (!spoke) return;
    }
    await beginPreparationCountdownAfterBreath(flowToken: flowToken);
  }

  /// 案内読み上げの余韻を残してから準備15秒を始める。
  Future<void> beginPreparationCountdownAfterBreath({int? flowToken}) async {
    await Future.delayed(preparationBreathDelay);
    if (flowToken != null && !_isFlowCurrent(flowToken)) return;
    startPreparationCountdown();
  }

  Future<void> startNormalSpeechAndTimer(String text) async {
    if (_settings.scoringEnabled &&
        sessionMode == AppSessionMode.singleQuestion) {
      if (_scoredQuestionFlowActive || _speech.isUtteranceActive) return;
      _scoredQuestionFlowActive = true;
      try {
        final flowToken = _singleLoopToken;
        await _runScoredNormalQuestion(flowToken: flowToken, text: text);
      } finally {
        _scoredQuestionFlowActive = false;
        notifyListeners();
      }
      return;
    }

    _clearIntervalCountdown();
    stopTimer();
    resetTimerState(TrainingMode.normal);
    _singleLoopToken++;
    final flowToken = _singleLoopToken;
    var timerStarted = false;
    void tryStartTimer() {
      if (timerStarted || !_isFlowCurrent(flowToken)) return;
      timerStarted = true;
      _startNormalTimerPhase();
    }
    if (Platform.isIOS) {
      final spoke = await _speech.speak(text: text, onFinish: tryStartTimer);
      if (spoke && _isFlowCurrent(flowToken)) tryStartTimer();
      await beginSingleQuestionKeepAlive();
    } else {
      await _speakTopicText(text, flowToken: flowToken, onSpeakFinished: tryStartTimer);
      if (!_isFlowCurrent(flowToken)) return;
      tryStartTimer();
      if (_isFlowCurrent(flowToken)) await beginSingleQuestionKeepAlive();
    }
    await _startSpeechCaptureIfNeeded();
    notifyListeners();
  }

  Future<void> startTwoPhaseSpeechAndTimer(String text) async {
    if (_settings.scoringEnabled &&
        sessionMode == AppSessionMode.singleQuestion) {
      if (_scoredQuestionFlowActive || _speech.isUtteranceActive) return;
      _scoredQuestionFlowActive = true;
      try {
        final flowToken = _singleLoopToken;
        await _runScoredTwoPhaseQuestion(flowToken: flowToken, text: text);
      } finally {
        _scoredQuestionFlowActive = false;
        notifyListeners();
      }
      return;
    }

    _clearIntervalCountdown();
    stopTimer();
    resetTimerState(activeTrainingMode);
    _singleLoopToken++;
    final flowToken = _singleLoopToken;
    if (Platform.isIOS) {
      await _suspendKeepAliveForPreparation();
      final spoke = await _speech.speak(
        text: _ttsPrepPrompt(text),
      );
      if (spoke && _isFlowCurrent(flowToken)) {
        await beginPreparationCountdownAfterBreath(flowToken: flowToken);
      }
    } else {
      var prepScheduled = false;
      void trySchedulePreparation() {
        if (prepScheduled || !_isFlowCurrent(flowToken)) return;
        prepScheduled = true;
        // keep-alive の await より先に予約する（45/60秒の tryStartTimer と同じ）。
        // beginSingleQuestionKeepAlive が端末で詰まっても準備15秒は始まる。
        unawaited(beginPreparationCountdownAfterBreath(flowToken: flowToken));
      }

      await _speakTopicText(
        _ttsPrepPrompt(text),
        flowToken: flowToken,
        onSpeakFinished: trySchedulePreparation,
      );
      if (!_isFlowCurrent(flowToken)) return;
      trySchedulePreparation();
      if (_isFlowCurrent(flowToken)) {
        await beginSingleQuestionKeepAlive();
      }
    }
    notifyListeners();
  }

  Future<void> speakQuestionThenThinkPrompt(String questionText) async {
    await _speech.speak(
      text: _ttsPrepPrompt(questionText),
    );
  }

  void startPreparationCountdown() {
    if (!Platform.isAndroid) {
      unawaited(_suspendKeepAliveForPreparation());
    }
    remainingSeconds = SituationTimerPhase.preparation.durationSeconds;
    markPhaseDeadlineFromRemainingSeconds();
    isTimerRunning = true;
    _persistTimerState();
    unawaited(TickBeepPlayer.instance.warmUp());
    _scheduleCompletionNotificationIfNeeded();
    if (_settings.scoringEnabled &&
        sessionMode == AppSessionMode.singleQuestion &&
        Platform.isAndroid) {
      // Android: Vosk モデルを準備中に温める。
      // iOS は STT 初期化が playAndRecord に切り替えて 2 回目の TTS を壊すため、
      // 「答えてください」後の _prepareSpeechCaptureAfterAnswerPrompt で行う。
      unawaited(_speechRecognition.preWarm());
    }
    notifyListeners();
    // 周期タイマーをリセットして次のティックが1秒後に来るよう揃える（二重ビープ防止）
    disposeTicking();
    startTicking();
  }

  Future<void> readAloudCurrent() async {
    final text = displayTopicText;
    if (text.isEmpty) return;
    if (isTimerRunning) {
      await _speech.speak(text: text);
      return;
    }
    if (isAwaitingSpeakingPhaseStart) {
      recoverStuckPreparationPhaseIfNeeded(force: true);
      return;
    }
    if (usesTwoPhaseTimer) {
      await startTwoPhaseSpeechAndTimer(text);
    } else {
      await startNormalSpeechAndTimer(text);
    }
  }

  /// 読み上げ中→一時停止、一時停止中→再開、停止中→読み上げ開始
  Future<void> toggleReadAloud() async {
    if (_speech.isPaused) {
      _speech.resume();
      return;
    }
    if (_speech.isSpeaking) {
      _speech.pause();
      return;
    }
    await readAloudCurrent();
  }

  // --- Mock exam ---

  void setMockExamStartIndex(int value) {
    mockExamStartIndex = value.clamp(0, MockExamPlanner.totalCount - 1);
    notifyListeners();
  }

  Future<void> startMockExam() async {
    if (isMockExamActive) return;
    isMockExamActive = true;
    isMockExamFinished = false;
    notifyListeners();
    await _speech.setSessionKeepAlive(true);
    unawaited(BackgroundAudioKeeper.instance.start());
    await _speech.stop();
    stopTimer();

    mockExamRunId = _uuid.v4();
    mockExamSteps = MockExamPlanner.buildSteps(_topics);
    if (mockExamSteps.isEmpty) {
      isMockExamActive = false;
      notifyListeners();
      await _speech.setSessionKeepAlive(false);
      return;
    }

    final startAt = min(mockExamStartIndex, mockExamSteps.length - 1);
    mockExamStepIndex = startAt;
    applyMockExamStep(startAt);
    notifyListeners();
    await beginMockExamQuestionCycle();
    notifyListeners();
  }

  Future<void> abortMockExam() async {
    await BackgroundAudioKeeper.instance.stop();
    await _speech.setSessionKeepAlive(false);
    mockExamRunId = _uuid.v4();
    await _speech.stop();
    stopTimer();
    resetMockExamState();
    notifyListeners();
  }

  void resetMockExamState() {
    mockExamRunId = _uuid.v4();
    mockExamSteps = [];
    mockExamStepIndex = 0;
    isMockExamActive = false;
    isMockExamFinished = false;
    currentTopic = '';
    currentSituation = null;
    hasDrawnTopic = false;
    situationPhase = SituationTimerPhase.preparation;
    remainingSeconds = 45;
  }

  void returnToMockExamIntro() {
    resetMockExamState();
    notifyListeners();
  }

  void applyMockExamStep(int index) {
    if (index >= mockExamSteps.length) return;
    final step = mockExamSteps[index];
    _speech.stop();
    _speech.clearGenderLock();

    switch (step.kind) {
      case MockExamQuestionKind.normal45:
      case MockExamQuestionKind.normal60:
      case MockExamQuestionKind.normal15plus60:
        currentTopic = step.topic ?? '';
        hasDrawnTopic = true;
        currentSituation = null;
        resetTimerState(TrainingMode.normal);
      case MockExamQuestionKind.situationKeigo:
        currentSituation = step.situation;
        currentTopic = '';
        hasDrawnTopic = false;
        resetTimerState(TrainingMode.situation);
    }
  }

  Future<void> beginMockExamQuestionCycle() async {
    if (sessionMode != AppSessionMode.mockExam ||
        !isMockExamActive ||
        currentMockExamStep == null) {
      return;
    }

    final step = currentMockExamStep!;
    final runId = mockExamRunId;
    stopTimer();
    resetTimerState(activeTrainingMode);

    final isTwoPhase = step.kind == MockExamQuestionKind.normal15plus60 ||
        step.kind == MockExamQuestionKind.situationKeigo;
    final baseText = mockExamReadableText(step);

    void startTimer() {
      Future.delayed(mockExamPreCountdownDelay, () {
        if (sessionMode != AppSessionMode.mockExam ||
            !isMockExamActive ||
            mockExamRunId != runId ||
            currentMockExamStep?.id != step.id) {
          return;
        }
        if (isTwoPhase) {
          startPreparationCountdown();
        } else {
          isTimerRunning = true;
          markPhaseDeadlineFromRemainingSeconds();
          notifyListeners();
        }
      });
    }

    if (step.kind == MockExamQuestionKind.situationKeigo) {
      await _speech.speak(
        text: '$_ttsMockExamQ10Prefix$baseText',
        onFinish: startTimer,
      );
    } else if (isTwoPhase) {
      await speakQuestionThenThinkPrompt(baseText);
      startTimer();
    } else {
      await _speech.speak(text: baseText, onFinish: startTimer);
    }
    notifyListeners();
  }

  Future<void> repeatMockExamQuestion(MockExamStep step) async {
    if (sessionMode != AppSessionMode.mockExam || !isMockExamActive) return;
    final text = mockExamReadableText(step);
    if (text.isEmpty) return;

    if (isTimerRunning) {
      await _speech.speak(text: text);
      notifyListeners();
      return;
    }

    final runId = mockExamRunId;
    final isTwoPhase = step.kind == MockExamQuestionKind.normal15plus60 ||
        step.kind == MockExamQuestionKind.situationKeigo;

    void startTimer() {
      Future.delayed(mockExamPreCountdownDelay, () {
        if (sessionMode != AppSessionMode.mockExam ||
            !isMockExamActive ||
            mockExamRunId != runId ||
            currentMockExamStep?.id != step.id ||
            isTimerRunning) {
          return;
        }
        if (isTwoPhase) {
          startPreparationCountdown();
        } else {
          isTimerRunning = true;
          markPhaseDeadlineFromRemainingSeconds();
          notifyListeners();
        }
      });
    }

    if (step.kind == MockExamQuestionKind.normal15plus60) {
      await speakQuestionThenThinkPrompt(text);
      startTimer();
    } else {
      await _speech.speak(text: text, onFinish: startTimer);
    }
    notifyListeners();
  }

  String mockExamReadableText(MockExamStep step) {
    switch (step.kind) {
      case MockExamQuestionKind.normal45:
      case MockExamQuestionKind.normal60:
      case MockExamQuestionKind.normal15plus60:
        return step.topic ?? '';
      case MockExamQuestionKind.situationKeigo:
        return step.situation?.readableText ?? '';
    }
  }

  Future<void> finishMockExamTimedPhase() async {
    stopTimer();
    await _alert.playCompletion();

    final runId = mockExamRunId;
    final interval = _settings.autoAdvanceInterval;
    if (interval <= 0) {
      Future.delayed(mockExamPostCompletionDelay, () async {
        if (sessionMode != AppSessionMode.mockExam ||
            !isMockExamActive ||
            mockExamRunId != runId) {
          return;
        }
        await advanceMockExamAfterQuestionIfNeeded();
      });
    } else {
      _mockExamIntervalRunId = runId;
      intervalRemainingSeconds = interval;
    }
    notifyListeners();
  }

  Future<void> advanceMockExamAfterQuestionIfNeeded() async {
    if (sessionMode != AppSessionMode.mockExam || !isMockExamActive) return;

    if (mockExamStepIndex + 1 >= mockExamSteps.length) {
      isMockExamActive = false;
      isMockExamFinished = true;
      await _speech.speak(
        text: _ttsMockExamComplete,
        onFinish: () async {
          await _speech.setSessionKeepAlive(false);
          await BackgroundAudioKeeper.instance.stop();
          notifyListeners();
        },
      );
      notifyListeners();
      return;
    }

    mockExamStepIndex += 1;
    applyMockExamStep(mockExamStepIndex);
    await beginMockExamQuestionCycle();
    notifyListeners();
  }

  // --- Timer tick engine ---

  void tickTimer() {
    if (intervalRemainingSeconds > 0) {
      if (sessionMode == AppSessionMode.mockExam) {
        if (!isMockExamActive || mockExamRunId != _mockExamIntervalRunId) {
          intervalRemainingSeconds = 0;
          notifyListeners();
          return;
        }
        intervalRemainingSeconds--;
        notifyListeners();
        if (intervalRemainingSeconds == 0) {
          unawaited(advanceMockExamAfterQuestionIfNeeded());
        }
        return;
      }
      if (_singleLoopToken != _intervalToken ||
          sessionMode != AppSessionMode.singleQuestion) {
        intervalRemainingSeconds = 0;
        notifyListeners();
        return;
      }
      intervalRemainingSeconds--;
      notifyListeners();
      if (intervalRemainingSeconds == 0) {
        final token = _intervalToken;
        unawaited(_autoAdvanceSingleQuestion(expectedToken: token));
      }
      return;
    }

    recoverStuckPreparationPhaseIfNeeded();
    if (!isTimerRunning) return;

    if (usesTwoPhaseTimer) {
      tickSituationModeTimer();
    } else {
      tickNormalModeTimer();
    }
  }

  void markPhaseDeadlineFromRemainingSeconds() {
    if (remainingSeconds <= 0) {
      activePhaseDeadline = null;
      return;
    }
    activePhaseDeadline =
        DateTime.now().add(Duration(seconds: remainingSeconds));
  }

  int remainingSecondsUntil(DateTime deadline) {
    final diff = deadline.difference(DateTime.now()).inSeconds;
    return max(1, diff);
  }

  Future<void> completePreparationPhase() async {
    if (_isCompletingPreparationPhase ||
        situationPhase != SituationTimerPhase.preparation) {
      return;
    }
    _isCompletingPreparationPhase = true;
    try {
      enterSpeakingPhase();
      notifyListeners();
      unawaited(_alert.playPhaseTransition());
      await speakAnswerPromptNow();
    } finally {
      _isCompletingPreparationPhase = false;
      notifyListeners();
    }
  }

  void enterSpeakingPhase() {
    if (situationPhase != SituationTimerPhase.preparation) return;
    situationPhase = SituationTimerPhase.speaking;
    remainingSeconds = SituationTimerPhase.speaking.durationSeconds;
    markPhaseDeadlineFromRemainingSeconds();
    isTimerRunning = true;
    _persistTimerState();
    _scheduleCompletionNotificationIfNeeded();
    if (!Platform.isAndroid &&
        sessionMode == AppSessionMode.singleQuestion) {
      // 準備15秒のティック音と無音キープアライブの競合を避け、発話フェーズから開始する。
      unawaited(beginSingleQuestionKeepAlive());
    }
    disposeTicking();
    startTicking();
    notifyListeners();
  }

  Future<bool> _startSpeechCaptureIfNeeded({int? flowToken}) async {
    if (sessionMode != AppSessionMode.singleQuestion) return false;
    if (!_settings.scoringEnabled) return false;
    if (flowToken != null && !_isFlowCurrent(flowToken)) return false;
    _speechAllottedSeconds = _currentSpeechAllottedSeconds();
    final captureStarted = await _speechRecognition.startSession();
    if (!captureStarted) {
      debugPrint(
        'osmWashabe: 発話キャプチャ開始に失敗しました (${Platform.operatingSystem})',
      );
    }
    return captureStarted;
  }

  int _currentSpeechAllottedSeconds() {
    if (usesTwoPhaseTimer && situationPhase == SituationTimerPhase.speaking) {
      return SituationTimerPhase.speaking.durationSeconds;
    }
    return normalTimerOption == NormalTimerOption.sec60 ? 60 : 45;
  }

  Future<void> speakAnswerPromptNow() async {
    final flowToken = _singleLoopToken;
    if (Platform.isAndroid) {
      await NativeTtsPlatform.ensureReady();
    }
    await ensureSpeechAudioSession();
    try {
      await _speech
          .speak(text: _ttsAnswerPrompt)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
    if (!_isFlowCurrent(flowToken)) return;
    unawaited(_prepareSpeechCaptureAfterAnswerPrompt(flowToken: flowToken));
  }

  /// 「答えてください」直後にバックグラウンドで録音／認識を始める。
  /// タイマー開始をブロックしない（iOS の STT 初期化は数秒かかることがある）。
  Future<void> _prepareSpeechCaptureAfterAnswerPrompt({
    required int flowToken,
  }) async {
    if (!_isFlowCurrent(flowToken)) return;
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!_isFlowCurrent(flowToken)) return;
    } else if (_settings.scoringEnabled &&
        sessionMode == AppSessionMode.singleQuestion) {
      await _speechRecognition.preWarm();
      if (!_isFlowCurrent(flowToken)) return;
    }
    await _startSpeechCaptureIfNeeded(flowToken: flowToken);
    if (!_isFlowCurrent(flowToken)) return;
    if (Platform.isAndroid) {
      await beginSingleQuestionKeepAlive();
    }
  }

  void recoverStuckPreparationPhaseIfNeeded({bool force = false}) {
    if (!needsTimerBackgroundSync) return;

    if (usesTwoPhaseTimer &&
        situationPhase == SituationTimerPhase.preparation &&
        isTimerRunning &&
        activePhaseDeadline != null &&
        DateTime.now().isAfter(activePhaseDeadline!)) {
      unawaited(completePreparationPhase());
      return;
    }

    if (!isAwaitingSpeakingPhaseStart) return;
    if (!force && _speech.isSpeaking) return;
    _speech.stop();
    enterSpeakingPhase();
    unawaited(speakAnswerPromptNow());
    notifyListeners();
  }

  void tickNormalModeTimer() {
    if (remainingSeconds <= 0) return;
    // deadline があれば wall-clock で補正（バックグラウンド復帰後のずれを修正）
    if (activePhaseDeadline != null) {
      if (DateTime.now().isAfter(activePhaseDeadline!)) {
        remainingSeconds = 0;
      } else {
        remainingSeconds = remainingSecondsUntil(activePhaseDeadline!);
      }
    } else {
      remainingSeconds -= 1;
    }
    if (remainingSeconds == 0) {
      if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
        unawaited(finishMockExamTimedPhase());
      } else {
        unawaited(completeSingleQuestionTimedPhase());
      }
    }
    notifyListeners();
  }

  void tickSituationModeTimer() {
    if (activePhaseDeadline != null) {
      if (DateTime.now().isAfter(activePhaseDeadline!)) {
        if (situationPhase == SituationTimerPhase.preparation) {
          unawaited(completePreparationPhase());
        } else if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
          remainingSeconds = 0;
          unawaited(finishMockExamTimedPhase());
        } else {
          remainingSeconds = 0;
          unawaited(completeSingleQuestionTimedPhase());
        }
        return;
      }

      // 準備フェーズは 1 秒ずつ減らす（壁時計への一括追いつきで 15→13 に飛ばない）
      if (remainingSeconds > 0) {
        if (situationPhase == SituationTimerPhase.preparation) {
          unawaited(_alert.playTick());
        }
        remainingSeconds -= 1;
        notifyListeners();
      }
      return;
    }

    if (remainingSeconds <= 0) return;
    if (situationPhase == SituationTimerPhase.preparation) {
      unawaited(_alert.playTick());
    }
    remainingSeconds -= 1;

    if (remainingSeconds != 0) {
      notifyListeners();
      return;
    }

    if (situationPhase == SituationTimerPhase.preparation) {
      unawaited(completePreparationPhase());
    } else if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
      unawaited(finishMockExamTimedPhase());
    } else {
      unawaited(completeSingleQuestionTimedPhase());
    }
  }

  Future<void> completeSingleQuestionTimedPhase() async {
    // 15+60 など二段階モードでは「発話フェーズ」終了時だけ採点する（準備15秒では採点しない）
    if (usesTwoPhaseTimer &&
        situationPhase != SituationTimerPhase.speaking) {
      return;
    }

    stopTimer();
    final isScoredSingleQuestion =
        sessionMode == AppSessionMode.singleQuestion && _settings.scoringEnabled;
    if (Platform.isAndroid && isScoredSingleQuestion) {
      unawaited(CrashLogService.log(
        'タイマー終了: 採点開始 recording=${_speechRecognition.isCaptureRecording}',
      ));
    }
    if (isScoredSingleQuestion) {
      // 前回の結果が残ったまま表示されないよう、新しい採点開始時にクリアする
      scoringResult = null;
      isAwaitingScoring = true;
      // notifyListeners() は完了音再生後に _finalizeSpeechCaptureAndPlayCompletion() 内で呼ぶ
      unawaited(_finalizeSpeechCaptureAndPlayCompletion());
      // 採点ONの単発お題モードは自動進行せず、サイコロボタンで次に進むまで待つ
      return;
    }
    final token = ++_singleLoopToken;
    await _alert.playCompletion();
    final interval = _settings.autoAdvanceInterval;
    if (interval <= 0) {
      Future.delayed(mockExamPostCompletionDelay, () async {
        if (_singleLoopToken != token ||
            sessionMode != AppSessionMode.singleQuestion) {
          return;
        }
        await _autoAdvanceSingleQuestion(expectedToken: token);
      });
    } else {
      _intervalToken = token;
      intervalRemainingSeconds = interval;
    }
    notifyListeners();
  }

  /// 発話フェーズ終了時の音声認識停止＋採点。タイマーの自動進行をブロックしないよう
  /// fire-and-forget で呼ぶが、最後の発話チャンクの確定だけは待つ。
  Future<void> _finalizeSpeechCapture({bool resumeKeeper = true}) async {
    final token = _singleLoopToken;
    List<TranscriptChunk> chunks = const [];
    try {
      final timeout = Platform.isAndroid
          ? const Duration(seconds: 130)
          : const Duration(seconds: 10);
      chunks = await _speechRecognition
          .stopSession(resumeKeeper: resumeKeeper)
          .timeout(timeout);
    } catch (_) {}
    // stopSession() の待機中に新しいお題が引かれた場合は結果を捨てる。
    // （旧い結果が次のお題の採点シートを誤って上書きするのを防ぐ）
    if (_singleLoopToken != token) return;
    isAwaitingScoring = false;
    if (!_speechRecognition.hasCaptureForCurrentAttempt) {
      scoringResult = null;
      notifyListeners();
      return;
    }
    if (chunks.isNotEmpty) {
      final result = JsstScoringService.score(
        chunks,
        session: _speechRecognition.sessionContext(
          allottedSeconds: _speechAllottedSeconds,
        ),
      );
      scoringResult = result;
      _scoringHistory.insert(0, result);
      final maxHistory = _settings.scoringHistoryEnabled ? 5 : 1;
      while (_scoringHistory.length > maxHistory) {
        _scoringHistory.removeLast();
      }
    } else {
      scoringResult = null;
    }
    notifyListeners();
  }

  /// 完了音 → 画面切替 → 文字起こし の順で実行する（iOS / Android 共通）。
  /// iOS は先に録音だけ止めて AVAudioSession を解放してから音を鳴らす。
  Future<void> _finalizeSpeechCaptureAndPlayCompletion() async {
    if (Platform.isAndroid) {
      await _alert.playCompletion();
      notifyListeners(); // 音の後に採点待ち画面へ切替
      await _finalizeSpeechCapture(resumeKeeper: false);
      await _speechRecognition.resumeKeeperIfPaused();
      return;
    }
    // iOS: 録音停止（AVAudioSession 解放）→ keeper 復帰（.playback セッション確立）
    //      → 完了音 → 画面切替 → 文字起こし
    await _speechRecognition.stopIosCapture();
    await _speechRecognition.resumeKeeperIfPaused();
    await _alert.playCompletion();
    notifyListeners(); // 音の後に採点待ち画面へ切替
    await _finalizeSpeechCapture(resumeKeeper: false);
  }

  Future<void> _autoAdvanceSingleQuestion({required int expectedToken}) async {
    if (sessionMode != AppSessionMode.singleQuestion) return;
    if (_singleLoopToken != expectedToken) return;
    _singleLoopToken++;
    _clearIntervalCountdown();
    drawTopic(endKeepAlive: false);
    if (!hasDrawnTopic || currentTopic.isEmpty) {
      await endSingleQuestionKeepAlive();
      return;
    }
    if (normalTimerOption == NormalTimerOption.prep15speaking60) {
      await startTwoPhaseSpeechAndTimer(currentTopic);
    } else {
      await startNormalSpeechAndTimer(currentTopic);
    }
    notifyListeners();
  }

  // --- Lifecycle ---

  void handleLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        if (needsTimerBackgroundSync &&
            isTimerRunning &&
            backgroundedAt == null) {
          backgroundedAt = DateTime.now();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (needsTimerBackgroundSync) {
          if (isTimerRunning || isAwaitingSpeakingPhaseStart) {
            backgroundedAt = DateTime.now();
          }
        }
      case AppLifecycleState.resumed:
        unawaited(TimerNotificationScheduler.instance.cancel());
        _speech.recoverFromSuspension();
        unawaited(BackgroundAudioKeeper.instance.recoverIfNeeded());
        if (needsTimerBackgroundSync) {
          syncTimerStateAfterForeground();
        }
        backgroundedAt = null;
        notifyListeners();
      case AppLifecycleState.detached:
        break;
    }
  }

  void syncTimerStateAfterForeground() {
    if (isAwaitingSpeakingPhaseStart) {
      recoverStuckPreparationPhaseIfNeeded(force: true);
      return;
    }

    if (usesTwoPhaseTimer) {
      syncTwoPhaseTimerAfterForeground();
      return;
    }

    if (!isTimerRunning) return;
    if (activePhaseDeadline != null) {
      syncSinglePhaseTimerToDeadline(activePhaseDeadline!);
    } else if (backgroundedAt != null) {
      final elapsed = max(
        0,
        DateTime.now().difference(backgroundedAt!).inSeconds,
      );
      if (elapsed > 0) applyElapsedSeconds(elapsed);
    }
    notifyListeners();
  }

  void syncTwoPhaseTimerAfterForeground() {
    if (isAwaitingSpeakingPhaseStart) {
      recoverStuckPreparationPhaseIfNeeded(force: true);
      return;
    }

    switch (situationPhase) {
      case SituationTimerPhase.preparation:
        if (isTimerRunning && activePhaseDeadline != null) {
          if (DateTime.now().isAfter(activePhaseDeadline!)) {
            unawaited(completePreparationPhase());
          } else {
            remainingSeconds = remainingSecondsUntil(activePhaseDeadline!);
          }
        } else if (isTimerRunning && backgroundedAt != null) {
          final elapsed = max(
            0,
            DateTime.now().difference(backgroundedAt!).inSeconds,
          );
          if (elapsed > 0) applyElapsedSeconds(elapsed);
        }
      case SituationTimerPhase.speaking:
        if (!isTimerRunning) return;
        if (activePhaseDeadline != null) {
          if (DateTime.now().isAfter(activePhaseDeadline!)) {
            remainingSeconds = 0;
            if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
              unawaited(finishMockExamTimedPhase());
            } else {
              unawaited(completeSingleQuestionTimedPhase());
            }
          } else {
            remainingSeconds = remainingSecondsUntil(activePhaseDeadline!);
          }
        } else if (backgroundedAt != null) {
          final elapsed = max(
            0,
            DateTime.now().difference(backgroundedAt!).inSeconds,
          );
          if (elapsed > 0) applyElapsedSeconds(elapsed);
        }
    }
    notifyListeners();
  }

  void syncSinglePhaseTimerToDeadline(DateTime deadline) {
    if (DateTime.now().isAfter(deadline)) {
      remainingSeconds = 0;
      unawaited(completeSingleQuestionTimedPhase());
    } else {
      remainingSeconds = remainingSecondsUntil(deadline);
    }
  }

  void applyElapsedSeconds(int seconds) {
    if (usesTwoPhaseTimer) {
      if (situationPhase == SituationTimerPhase.preparation) {
        if (seconds < remainingSeconds) {
          remainingSeconds -= seconds;
          markPhaseDeadlineFromRemainingSeconds();
          return;
        }
        unawaited(completePreparationPhase());
        return;
      }
      final newRemaining = max(0, remainingSeconds - seconds);
      remainingSeconds = newRemaining;
      if (newRemaining == 0) {
        if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
          unawaited(finishMockExamTimedPhase());
        } else {
          unawaited(completeSingleQuestionTimedPhase());
        }
      } else {
        markPhaseDeadlineFromRemainingSeconds();
      }
    } else {
      final newRemaining = max(0, remainingSeconds - seconds);
      remainingSeconds = newRemaining;
      if (newRemaining == 0) {
        if (sessionMode == AppSessionMode.mockExam && isMockExamActive) {
          unawaited(finishMockExamTimedPhase());
        } else {
          unawaited(completeSingleQuestionTimedPhase());
        }
      } else {
        markPhaseDeadlineFromRemainingSeconds();
      }
    }
    notifyListeners();
  }

  // --- Keep-alive & notifications ---

  Future<void> beginSingleQuestionKeepAlive() async {
    if (sessionMode != AppSessionMode.singleQuestion) return;
    await _speech.setSessionKeepAlive(true);
    await BackgroundAudioKeeper.instance.start();
  }

  Future<void> endSingleQuestionKeepAlive() async {
    await _speech.setSessionKeepAlive(false);
    await BackgroundAudioKeeper.instance.stop();
  }

  void _scheduleCompletionNotificationIfNeeded() {
    if (BackgroundAudioKeeper.instance.isRunning) {
      unawaited(TimerNotificationScheduler.instance.cancel());
      return;
    }
    if (sessionMode != AppSessionMode.singleQuestion) return;
    if (usesTwoPhaseTimer &&
        situationPhase == SituationTimerPhase.preparation) {
      unawaited(TimerNotificationScheduler.instance.cancel());
      return;
    }
    if (isTimerRunning) {
      unawaited(
        TimerNotificationScheduler.instance.schedule(
          remainingSeconds,
          languageCode: _settings.language,
        ),
      );
    }
  }

  void onTimerRunningChanged() {
    if (sessionMode != AppSessionMode.singleQuestion) return;
    if (isTimerRunning) {
      _scheduleCompletionNotificationIfNeeded();
    } else {
      unawaited(TimerNotificationScheduler.instance.cancel());
    }
  }

  // --- タイマー状態永続化（Android バックグラウンドキル対策）---

  void _persistTimerState() {
    if (!Platform.isAndroid) return;
    if (sessionMode != AppSessionMode.singleQuestion) return;
    if (!isTimerRunning || activePhaseDeadline == null) {
      _clearPersistedTimerState();
      return;
    }
    _prefs?.saveTimerState(
      deadline: activePhaseDeadline!,
      mode: mode.name,
      normalTimerOption: normalTimerOption.name,
      situationPhase: situationPhase.name,
      topic: currentTopic,
      hasDrawnTopic: hasDrawnTopic,
      situationJson: currentSituation != null
          ? jsonEncode(currentSituation!.toJson())
          : null,
    );
  }

  void _clearPersistedTimerState() {
    if (!Platform.isAndroid) return;
    _prefs?.clearTimerState();
  }

  /// Android: プロセス再起動後にタイマー状態を復元する（initState 後に呼ぶ）
  void restorePersistedTimerState() {
    if (!Platform.isAndroid) return;
    final saved = _prefs?.loadTimerState();
    if (saved == null) return;
    final deadlineMs = saved['deadlineMs'] as int?;
    if (deadlineMs == null) return;
    final deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
    if (DateTime.now().isAfter(deadline)) {
      _clearPersistedTimerState();
      return;
    }
    mode = TrainingMode.normal;
    normalTimerOption = NormalTimerOption.values.firstWhere(
      (e) => e.name == (saved['normalTimerOption'] as String?),
      orElse: () => NormalTimerOption.sec45,
    );
    // 旧 situation モードの永続化は 15+60 に畳む
    if ((saved['mode'] as String?) == TrainingMode.situation.name) {
      normalTimerOption = NormalTimerOption.prep15speaking60;
    }
    situationPhase = SituationTimerPhase.values.firstWhere(
      (e) => e.name == (saved['situationPhase'] as String?),
      orElse: () => SituationTimerPhase.preparation,
    );
    currentTopic = saved['topic'] as String? ?? '';
    hasDrawnTopic = saved['hasDrawnTopic'] as bool? ?? false;
    final situationJson = saved['situationJson'] as String?;
    if (situationJson != null) {
      try {
        currentSituation = SituationPrompt.fromJson(
          jsonDecode(situationJson) as Map<String, dynamic>,
        );
        if (currentTopic.isEmpty && currentSituation != null) {
          currentTopic = currentSituation!.readableText;
          hasDrawnTopic = true;
          currentSituation = null;
        }
      } catch (_) {}
    }
    activePhaseDeadline = deadline;
    remainingSeconds = remainingSecondsUntil(deadline);
    isTimerRunning = true;
    sessionMode = AppSessionMode.singleQuestion;
    // BackgroundAudioKeeper を再起動して再びバックグラウンドに落ちた際もキープアライブ
    unawaited(BackgroundAudioKeeper.instance.start());
    notifyListeners();
  }

  @override
  void dispose() {
    disposeTicking();
    super.dispose();
  }
}
