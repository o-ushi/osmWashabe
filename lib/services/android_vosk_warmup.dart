import 'dart:async';
import 'dart:io';

import 'vosk_model_manager.dart';

/// Android 採点ON時に Vosk モデルをバックグラウンドで準備する。
abstract final class AndroidVoskWarmup {
  static void scheduleIfNeeded({required bool scoringEnabled}) {
    if (!Platform.isAndroid || !scoringEnabled) return;
    unawaited(_prepare());
  }

  static Future<void> _prepare() async {
    try {
      if (await VoskModelManager.isReady()) return;
      await VoskModelManager.ensureReady();
    } catch (_) {
      // 回線不良などは次回起動・採点時に再試行する。
    }
  }
}
