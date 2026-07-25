import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

import 'background_audio_keeper.dart';

/// iOS / Android システム効果音を MethodChannel 経由で再生
abstract final class SystemSoundPlayer {
  static const _channel = MethodChannel('com.osamushikubo.osm_washabe/system_sound');

  static Future<void> play(int soundId, {bool prepareSession = true}) async {
    if (prepareSession) {
      await _prepareAudioSession();
    }
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('play', soundId);
        return;
      } catch (_) {}
    }
    await SystemSound.play(SystemSoundType.alert);
  }

  static Future<void> _prepareAudioSession() async {
    if (BackgroundAudioKeeper.instance.isRunning) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
      ));
      await session.setActive(true);
    } catch (_) {}
  }
}
