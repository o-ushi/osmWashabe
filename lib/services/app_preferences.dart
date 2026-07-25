import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences での永続化（キーは歴史的に iOS UserDefaults 由来）
class AppPreferences {
  AppPreferences(this._prefs);

  static const completionSoundKey = 'completionSoundPreset';
  static const vibrationEnabledKey = 'vibrationEnabled';
  static const phaseTransitionSoundEnabledKey = 'phaseTransitionSoundEnabled';
  static const preparationTickVibrationEnabledKey =
      'preparationTickVibrationEnabled';
  static const mockExamShowQuestionKey = 'osmWashabe.mockExam.showQuestion';
  static const useBuiltInTopicsKey = 'osmWashabe.useBuiltInTopics';
  static const shakeAutoSpeakKey = 'osmWashabe.shakeAutoSpeak';
  static const scoringEnabledKey = 'osmWashabe.scoringEnabled';
  static const developerModeEnabledKey = 'osmWashabe.developerModeEnabled';
  static const speechVoiceGenderKey = 'osmWashabe.speech.voiceGender';
  static const speechRateKey = 'osmWashabe.speech.rate';
  static const languageKey = 'osmWashabe.language';
  static const importedLifeKey = 'osmWashabe.importedTopics.life';
  static const importedWorkKey = 'osmWashabe.importedTopics.work';
  static const importedSocietyKey = 'osmWashabe.importedTopics.society';
  static const importedSituationsKey = 'osmWashabe.importedTopics.situations';
  static const autoAdvanceIntervalKey = 'osmWashabe.autoAdvanceInterval';
  static const scoringHistoryEnabledKey = 'osmWashabe.scoringHistoryEnabled';
  static const calibrationBiasKey = 'osmWashabe.calibration.bias';
  static const calibrationSampleCountKey = 'osmWashabe.calibration.sampleCount';

  // タイマー状態永続化（Android バックグラウンドキル対策）
  static const _timerDeadlineKey = 'osmWashabe.timer.deadline';
  static const _timerModeKey = 'osmWashabe.timer.mode';
  static const _timerNormalOptionKey = 'osmWashabe.timer.normalOption';
  static const _timerSituationPhaseKey = 'osmWashabe.timer.situationPhase';
  static const _timerTopicKey = 'osmWashabe.timer.topic';
  static const _timerSituationJsonKey = 'osmWashabe.timer.situationJson';
  static const _timerHasDrawnTopicKey = 'osmWashabe.timer.hasDrawnTopic';

  static const defaultCompletionSound = '1307';
  static const defaultSpeechRate = 0.53;
  static const defaultVoiceGender = '女性の声';
  static const defaultLanguage = 'vi';

  final SharedPreferences _prefs;

  static Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _registerDefaults(prefs);
    final appPrefs = AppPreferences(prefs);
    await appPrefs.migratePlatformSpecificSettings();
    return appPrefs;
  }

  /// 'Siriの声' はどのプラットフォームでも選択肢から削除されたため正規化する
  Future<void> migratePlatformSpecificSettings() async {
    if (_prefs.getString(speechVoiceGenderKey) == 'Siriの声') {
      await _prefs.setString(speechVoiceGenderKey, defaultVoiceGender);
    }
  }

  /// 'Siriの声' が保存されていた場合にデフォルトへ正規化する
  static String normalizeVoiceGender(String raw) {
    if (raw == 'Siriの声') return defaultVoiceGender;
    return raw;
  }

  static Future<void> _registerDefaults(SharedPreferences prefs) async {
    final defaults = <String, Object>{
      completionSoundKey: defaultCompletionSound,
      vibrationEnabledKey: true,
      phaseTransitionSoundEnabledKey: true,
      preparationTickVibrationEnabledKey: true,
      mockExamShowQuestionKey: true,
      useBuiltInTopicsKey: true,
      shakeAutoSpeakKey: false,
      scoringEnabledKey: false,
      scoringHistoryEnabledKey: true,
      developerModeEnabledKey: false,
      speechVoiceGenderKey: defaultVoiceGender,
      speechRateKey: defaultSpeechRate,
      languageKey: defaultLanguage,
      importedLifeKey: '[]',
      importedWorkKey: '[]',
      importedSocietyKey: '[]',
      importedSituationsKey: '[]',
      autoAdvanceIntervalKey: 5,
    };

    for (final entry in defaults.entries) {
      if (!prefs.containsKey(entry.key)) {
        final value = entry.value;
        if (value is bool) {
          await prefs.setBool(entry.key, value);
        } else if (value is double) {
          await prefs.setDouble(entry.key, value);
        } else if (value is int) {
          await prefs.setInt(entry.key, value);
        } else if (value is String) {
          await prefs.setString(entry.key, value);
        }
      }
    }
  }

  Future<void> clearAllAndRestoreDefaults() async {
    await _prefs.clear();
    await _registerDefaults(_prefs);
  }

  String get completionSound =>
      _prefs.getString(completionSoundKey) ?? defaultCompletionSound;
  set completionSound(String value) =>
      _prefs.setString(completionSoundKey, value);

  bool get vibrationEnabled => _prefs.getBool(vibrationEnabledKey) ?? true;
  set vibrationEnabled(bool value) =>
      _prefs.setBool(vibrationEnabledKey, value);

  bool get phaseTransitionSoundEnabled =>
      _prefs.getBool(phaseTransitionSoundEnabledKey) ?? true;
  set phaseTransitionSoundEnabled(bool value) =>
      _prefs.setBool(phaseTransitionSoundEnabledKey, value);

  bool get preparationTickVibrationEnabled =>
      _prefs.getBool(preparationTickVibrationEnabledKey) ?? true;
  set preparationTickVibrationEnabled(bool value) =>
      _prefs.setBool(preparationTickVibrationEnabledKey, value);

  bool get mockExamShowQuestion =>
      _prefs.getBool(mockExamShowQuestionKey) ?? true;
  set mockExamShowQuestion(bool value) =>
      _prefs.setBool(mockExamShowQuestionKey, value);

  bool get useBuiltInTopics => _prefs.getBool(useBuiltInTopicsKey) ?? true;
  set useBuiltInTopics(bool value) =>
      _prefs.setBool(useBuiltInTopicsKey, value);

  bool get shakeAutoSpeak => _prefs.getBool(shakeAutoSpeakKey) ?? false;
  set shakeAutoSpeak(bool value) => _prefs.setBool(shakeAutoSpeakKey, value);

  bool get scoringEnabled => _prefs.getBool(scoringEnabledKey) ?? false;
  set scoringEnabled(bool value) => _prefs.setBool(scoringEnabledKey, value);

  bool get scoringHistoryEnabled =>
      _prefs.getBool(scoringHistoryEnabledKey) ?? true;
  set scoringHistoryEnabled(bool value) =>
      _prefs.setBool(scoringHistoryEnabledKey, value);

  bool get developerModeEnabled =>
      _prefs.getBool(developerModeEnabledKey) ?? false;
  set developerModeEnabled(bool value) =>
      _prefs.setBool(developerModeEnabledKey, value);

  String get speechVoiceGender => normalizeVoiceGender(
      _prefs.getString(speechVoiceGenderKey) ?? defaultVoiceGender);

  set speechVoiceGender(String value) =>
      _prefs.setString(speechVoiceGenderKey, normalizeVoiceGender(value));

  double get speechRate => _prefs.getDouble(speechRateKey) ?? defaultSpeechRate;
  set speechRate(double value) {
    final clamped = value.clamp(0.35, 0.68);
    _prefs.setDouble(speechRateKey, clamped);
  }

  String get language => _prefs.getString(languageKey) ?? defaultLanguage;
  set language(String value) => _prefs.setString(languageKey, value);

  String get importedLifeJson => _prefs.getString(importedLifeKey) ?? '[]';
  set importedLifeJson(String value) {
    _prefs.setString(importedLifeKey, value);
  }

  Future<bool> saveImportedLifeJson(String value) =>
      _prefs.setString(importedLifeKey, value);

  String get importedWorkJson => _prefs.getString(importedWorkKey) ?? '[]';
  set importedWorkJson(String value) {
    _prefs.setString(importedWorkKey, value);
  }

  Future<bool> saveImportedWorkJson(String value) =>
      _prefs.setString(importedWorkKey, value);

  String get importedSocietyJson =>
      _prefs.getString(importedSocietyKey) ?? '[]';
  set importedSocietyJson(String value) {
    _prefs.setString(importedSocietyKey, value);
  }

  Future<bool> saveImportedSocietyJson(String value) =>
      _prefs.setString(importedSocietyKey, value);

  String get importedSituationsJson =>
      _prefs.getString(importedSituationsKey) ?? '[]';
  set importedSituationsJson(String value) {
    _prefs.setString(importedSituationsKey, value);
  }

  Future<bool> saveImportedSituationsJson(String value) =>
      _prefs.setString(importedSituationsKey, value);

  int get autoAdvanceInterval => _prefs.getInt(autoAdvanceIntervalKey) ?? 5;
  set autoAdvanceInterval(int value) =>
      _prefs.setInt(autoAdvanceIntervalKey, value);

  double get calibrationBias => _prefs.getDouble(calibrationBiasKey) ?? 0.0;
  set calibrationBias(double value) =>
      _prefs.setDouble(calibrationBiasKey, value);

  int get calibrationSampleCount =>
      _prefs.getInt(calibrationSampleCountKey) ?? 0;
  set calibrationSampleCount(int value) =>
      _prefs.setInt(calibrationSampleCountKey, value);

  void clearCalibration() {
    _prefs.remove(calibrationBiasKey);
    _prefs.remove(calibrationSampleCountKey);
  }

  void saveTimerState({
    required DateTime deadline,
    required String mode,
    required String normalTimerOption,
    required String situationPhase,
    required String topic,
    required bool hasDrawnTopic,
    String? situationJson,
  }) {
    _prefs.setInt(_timerDeadlineKey, deadline.millisecondsSinceEpoch);
    _prefs.setString(_timerModeKey, mode);
    _prefs.setString(_timerNormalOptionKey, normalTimerOption);
    _prefs.setString(_timerSituationPhaseKey, situationPhase);
    _prefs.setString(_timerTopicKey, topic);
    _prefs.setBool(_timerHasDrawnTopicKey, hasDrawnTopic);
    if (situationJson != null) {
      _prefs.setString(_timerSituationJsonKey, situationJson);
    } else {
      _prefs.remove(_timerSituationJsonKey);
    }
  }

  void clearTimerState() {
    _prefs.remove(_timerDeadlineKey);
  }

  Map<String, Object?>? loadTimerState() {
    final ms = _prefs.getInt(_timerDeadlineKey);
    if (ms == null) return null;
    return {
      'deadlineMs': ms,
      'mode': _prefs.getString(_timerModeKey),
      'normalTimerOption': _prefs.getString(_timerNormalOptionKey),
      'situationPhase': _prefs.getString(_timerSituationPhaseKey),
      'topic': _prefs.getString(_timerTopicKey),
      'hasDrawnTopic': _prefs.getBool(_timerHasDrawnTopicKey),
      'situationJson': _prefs.getString(_timerSituationJsonKey),
    };
  }
}
