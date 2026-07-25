import 'package:shared_preferences/shared_preferences.dart';

/// 音声認識の調査用ログを端末に永続化する。
/// フリーズ・クラッシュ後も設定画面から直前のログを確認できる。
abstract final class SpeechRecognitionDebugLogStore {
  static const _key = 'osmWashabe.speechRecognition.lastDebugLog';
  static const _maxLines = 100;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_key) ?? const []);
  }

  static Future<void> append(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final lines = List<String>.from(prefs.getStringList(_key) ?? const []);
    lines.add(message);
    while (lines.length > _maxLines) {
      lines.removeAt(0);
    }
    await prefs.setStringList(_key, lines);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
