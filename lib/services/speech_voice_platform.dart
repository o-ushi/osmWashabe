import 'dart:io';

import 'package:flutter/services.dart';

import 'japanese_speech_voice_selector.dart';

/// ネイティブ iOS / Android から日本語音声情報を取得する
abstract final class SpeechVoicePlatform {
  static const _channel = MethodChannel('com.osamushikubo.osm_washabe/speech_voices');

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  /// 指定した性別で実際に使われる音声情報を返す（識別子直接試行ロジック使用）
  /// gender は '男性の声' / '女性の声' / 'ランダム'
  static Future<Map<String, String>?> getVoiceInfoForGender(String gender) async {
    if (!isSupported) return null;
    try {
      final nativeGender = SpeechVoiceGender.nativeValueFor(gender);
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getVoiceInfoForGender',
        nativeGender,
      );
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {
      return null;
    }
  }
}
