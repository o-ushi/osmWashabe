import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences.dart';
import 'crash_log_service.dart';
import 'speech_recognition_debug_log_store.dart';
import 'vosk_model_manager.dart';

abstract final class PrivacyService {
  static const speechConsentVersion = 1;
  static const _speechConsentVersionKey =
      'osmWashabe.privacy.speechConsentVersion';
  static const _nativeLogChannel =
      MethodChannel('com.osamushikubo.osm_washabe/log_share');

  static Future<bool> hasCurrentSpeechConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_speechConsentVersionKey) == speechConsentVersion;
  }

  static Future<void> grantSpeechConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_speechConsentVersionKey, speechConsentVersion);
  }

  static Future<void> revokeSpeechConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_speechConsentVersionKey);
  }

  /// Removes user-created content, recordings, Dart/native diagnostic logs,
  /// preferences, and the regenerable Android Vosk cache.
  static Future<void> deleteAllData(AppPreferences preferences) async {
    await CrashLogService.clearLog();
    await SpeechRecognitionDebugLogStore.clear();
    if (Platform.isAndroid) {
      try {
        await _nativeLogChannel.invokeMethod<void>('clearNativeCrashLog');
      } catch (_) {}
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      for (final entity in docs.listSync()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}

    await VoskModelManager.clearCache();
    await preferences.clearAllAndRestoreDefaults();
  }
}
