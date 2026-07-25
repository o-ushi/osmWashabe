import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../notifiers/app_settings.dart';
import 'android_ringtone_service.dart';
import 'system_sound_player.dart';
import 'tick_beep_player.dart';
import 'timer_completion_sound_catalog.dart';

/// iOS `TimerAlert` に対応
class TimerAlert {
  TimerAlert(this._settings);

  final AppSettingsNotifier _settings;

  static const _phaseTransitionSoundId = 1057;

  Future<void> playCompletion() async {
    final raw = _settings.completionSound;
    if (Platform.isAndroid) {
      final ringtone = AndroidRingtoneService.fromStoredValue(raw);
      if (ringtone != null) {
        await AndroidRingtoneService.playRingtone(ringtone.uri);
      } else {
        await SystemSoundPlayer.play(0);
      }
    } else if (Platform.isIOS) {
      final item = TimerCompletionSoundCatalog.itemFor(raw);
      if (item != null &&
          item.playable &&
          item.soundId != null &&
          item.storedValue != TimerCompletionSoundCatalog.noneStoredValue) {
        await SystemSoundPlayer.play(item.soundId!);
      }
    }
    if (_settings.vibrationEnabled) {
      await HapticFeedback.heavyImpact();
    }
  }

  Future<void> playPhaseTransition() async {
    if (_settings.phaseTransitionSoundEnabled) {
      await SystemSoundPlayer.play(_phaseTransitionSoundId, prepareSession: false);
    }
    await _vibrateForPhaseTransition();
  }

  Future<void> playTick() async {
    if (_settings.phaseTransitionSoundEnabled) {
      // iOS 準備カウント: システム音（セッション再設定なし）で等間隔を保つ
      if (Platform.isIOS) {
        unawaited(SystemSoundPlayer.play(_phaseTransitionSoundId, prepareSession: false));
      } else {
        unawaited(TickBeepPlayer.instance.play());
      }
    }
    if (_settings.preparationTickVibrationEnabled) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  Future<void> previewSound(String storedValue) async {
    final item = TimerCompletionSoundCatalog.itemFor(storedValue);
    if (item == null || !item.playable || item.soundId == null) return;
    await SystemSoundPlayer.play(item.soundId!);
  }

  Future<void> _vibrateForPhaseTransition() async {
    if (!_settings.preparationTickVibrationEnabled) return;
    await HapticFeedback.mediumImpact();
  }
}
