import 'dart:io';

import 'package:flutter/services.dart';

/// Android の SpeechRecognizer が listen() 開始時に鳴らすシステムビープを抑制する。
///
/// [muteForSttStart] を `_stt.listen()` の直前に呼ぶと、Kotlin 側が
/// STREAM_NOTIFICATION / STREAM_SYSTEM を短時間ミュートする（STREAM_MUSIC は TTS 用のため触らない）。
class AndroidAudioUtils {
  static const _channel =
      MethodChannel('com.osamushikubo.osm_washabe/audio_utils');

  static Future<void> muteForSttStart() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('muteForSttStart');
    } catch (_) {}
  }
}
