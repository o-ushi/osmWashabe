import 'package:flutter/foundation.dart';

import '../services/app_preferences.dart';

/// 設定値の ChangeNotifier（iOS @AppStorage 相当）
class AppSettingsNotifier extends ChangeNotifier {
  late AppPreferences _prefs;

  void bind(AppPreferences prefs) {
    _prefs = prefs;
  }

  String get completionSound => _prefs.completionSound;
  set completionSound(String value) {
    _prefs.completionSound = value;
    notifyListeners();
  }

  bool get vibrationEnabled => _prefs.vibrationEnabled;
  set vibrationEnabled(bool value) {
    _prefs.vibrationEnabled = value;
    notifyListeners();
  }

  bool get phaseTransitionSoundEnabled => _prefs.phaseTransitionSoundEnabled;
  set phaseTransitionSoundEnabled(bool value) {
    _prefs.phaseTransitionSoundEnabled = value;
    notifyListeners();
  }

  bool get preparationTickVibrationEnabled =>
      _prefs.preparationTickVibrationEnabled;
  set preparationTickVibrationEnabled(bool value) {
    _prefs.preparationTickVibrationEnabled = value;
    notifyListeners();
  }

  bool get mockExamShowQuestion => _prefs.mockExamShowQuestion;
  set mockExamShowQuestion(bool value) {
    _prefs.mockExamShowQuestion = value;
    notifyListeners();
  }

  bool get useBuiltInTopics => _prefs.useBuiltInTopics;
  set useBuiltInTopics(bool value) {
    _prefs.useBuiltInTopics = value;
    notifyListeners();
  }

  bool get shakeAutoSpeak => _prefs.shakeAutoSpeak;
  set shakeAutoSpeak(bool value) {
    _prefs.shakeAutoSpeak = value;
    notifyListeners();
  }

  bool get scoringEnabled => _prefs.scoringEnabled;
  set scoringEnabled(bool value) {
    _prefs.scoringEnabled = value;
    notifyListeners();
  }

  bool get scoringHistoryEnabled => _prefs.scoringHistoryEnabled;
  set scoringHistoryEnabled(bool value) {
    _prefs.scoringHistoryEnabled = value;
    notifyListeners();
  }

  bool get developerModeEnabled => _prefs.developerModeEnabled;
  set developerModeEnabled(bool value) {
    _prefs.developerModeEnabled = value;
    notifyListeners();
  }

  String get speechVoiceGender => _prefs.speechVoiceGender;
  set speechVoiceGender(String value) {
    _prefs.speechVoiceGender = value;
    notifyListeners();
  }

  double get speechRate => _prefs.speechRate;
  set speechRate(double value) {
    _prefs.speechRate = value;
    notifyListeners();
  }

  String get language => _prefs.language;
  set language(String value) {
    _prefs.language = value;
    notifyListeners();
  }

  int get autoAdvanceInterval => _prefs.autoAdvanceInterval;
  set autoAdvanceInterval(int value) {
    _prefs.autoAdvanceInterval = value;
    notifyListeners();
  }

  AppPreferences get preferences => _prefs;

  void refreshAfterDataDeletion() => notifyListeners();
}
