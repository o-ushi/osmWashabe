import 'dart:io';

import 'package:flutter/services.dart';

import 'japanese_speech_voice_selector.dart';

/// iOS / Android ネイティブ TTS への直接ブリッジ
/// gender を渡すことで各 OS 側が性別に応じた日本語音声を直接選択する
/// （flutter_tts の setVoice に依存しない）
abstract final class NativeTtsPlatform {
  static const _channel = MethodChannel('com.osamushikubo.osm_washabe/tts');

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  static Future<bool> ensureReady() async {
    if (!isSupported) return true;
    try {
      return await _channel
              .invokeMethod<bool>('ensureReady')
              .timeout(const Duration(seconds: 8)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// gender に応じた音声で text を読み上げる。
  /// 戻り値: true=完了, false=キャンセル/エラー, null=日本語TTS未インストール（スキップ）
  /// gender: '男性の声' | '女性の声' | 'ランダム'
  static Future<bool?> speak({
    required String text,
    required String gender,
    required double rate,
    double pitch = 1.0,
  }) async {
    if (!isSupported) return false;
    try {
      // invokeMethod<bool?> で null（TTS未対応）も正しく受け取る
      return await _channel
          .invokeMethod<bool?>('speak', {
            'text': text,
            'gender': SpeechVoiceGender.nativeValueFor(gender),
            'rate': rate,
            'pitch': pitch,
          })
          .timeout(const Duration(seconds: 45), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> pause() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  static Future<void> resume() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  /// 端末の設定画面を開く。
  /// Android: 「テキスト読み上げの出力」設定画面
  /// iOS: このアプリの設定ページ（そこからアクセシビリティ→読み上げコンテンツ→声に進んでもらう）
  /// 日本語音声データが未インストールの端末で、案内から直接遷移させるために使う。
  static Future<bool> openSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

}
