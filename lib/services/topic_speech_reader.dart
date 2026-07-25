import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../notifiers/app_settings.dart';
import 'background_audio_keeper.dart';
import 'japanese_speech_text_formatter.dart';
import 'japanese_speech_voice_selector.dart';
import 'native_tts_platform.dart';
import 'speech_voice_platform.dart';

/// iOS `TopicSpeechReader` に対応
///
/// iOS / Android: 各 OS のネイティブ TTS（NativeTtsPlatform）を使用し、
///      音声選択を確実にする
/// その他のプラットフォームでは TTS は無効（flutter_tts 依存を排除）
class TopicSpeechReader extends ChangeNotifier {
  TopicSpeechReader(this._settings) {
    _settings.addListener(_onSettingsChanged);
    _configureTts();
  }

  final AppSettingsNotifier _settings;

  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _utteranceActive = false;
  int _speakEpoch = 0;
  bool _sessionKeepAlive = false;
  String? _lockedGender;
  // 日本語 TTS が端末で利用可能かどうか（初回 speak() までは未チェックのため true）
  bool _ttsAvailable = true;
  SpeechVoiceInfo _activeVoiceInfo = const SpeechVoiceInfo(
    name: 'Kyoko',
    qualityLabelKey: '声_標準',
    isHighQuality: false,
  );

  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  /// speak() の await 中（TTS 開始前の準備を含む）
  bool get isUtteranceActive => _utteranceActive || _isSpeaking;
  bool get isUsingHighQualityVoice => _activeVoiceInfo.isHighQuality;
  /// false のとき日本語 TTS が端末にインストールされていない
  bool get ttsAvailable => _ttsAvailable;

  String activeVoiceDescription(String languageCode) {
    final quality = _activeVoiceInfo.qualityLabelKey.tr(languageCode);
    return '${_activeVoiceInfo.name}（$quality）';
  }

  Future<void> _configureTts() async {
    await _applyVoiceSettings();
  }

  void _onSettingsChanged() {
    _applyVoiceSettings();
  }

  Future<void> _applyVoiceSettings() async {
    if (NativeTtsPlatform.isSupported) {
      final info = await SpeechVoicePlatform.getVoiceInfoForGender(
        _settings.speechVoiceGender,
      );
      if (info != null) {
        final qualityKey = _qualityLabelKey(
          info['quality'] ?? '',
          info['identifier'] ?? '',
        );
        final isHQ =
            info['quality'] == 'premium' || info['quality'] == 'enhanced';
        _activeVoiceInfo = SpeechVoiceInfo(
          name: info['name'] ?? 'Kyoko',
          qualityLabelKey: qualityKey,
          isHighQuality: isHQ,
        );
      }
    }
    notifyListeners();
  }

  static String _qualityLabelKey(String quality, String identifier) {
    if (quality == 'premium' || identifier.toLowerCase().contains('premium')) return '声_プレミアム';
    if (quality == 'enhanced' || identifier.toLowerCase().contains('enhanced')) return '声_高品質';
    return '声_標準';
  }

  Future<void> setSessionKeepAlive(bool keepAlive) async {
    _sessionKeepAlive = keepAlive;
    if (keepAlive) {
      await ensureSpeechAudioSession();
    } else if (!_isSpeaking) {
      await _deactivateSessionIfPossible();
    }
  }

  Future<bool> speak({
    required String text,
    double pitchMultiplier = 1.0,
    double rateBoost = 0.0,
    VoidCallback? onFinish,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onFinish?.call();
      return true;
    }

    final epoch = ++_speakEpoch;
    _utteranceActive = true;
    notifyListeners();

    try {
      if (_isSpeaking) {
        _isPaused = false;
        _isSpeaking = false;
        if (NativeTtsPlatform.isSupported) {
          await NativeTtsPlatform.stop();
        }
      }

      if (epoch != _speakEpoch) return false;

      final keeperWasRunning = BackgroundAudioKeeper.instance.isRunning;
      var restartKeeperAfterTts = false;
      if (keeperWasRunning) {
        if (Platform.isAndroid) {
          await BackgroundAudioKeeper.instance.stop();
          restartKeeperAfterTts = _sessionKeepAlive;
        } else {
          await BackgroundAudioKeeper.instance.pauseForSpeech();
        }
      }

      try {
        await ensureSpeechAudioSession();

        if (epoch != _speakEpoch) return false;

        if (NativeTtsPlatform.isSupported) {
          return await _speakNative(
            text: trimmed,
            epoch: epoch,
            pitchMultiplier: pitchMultiplier,
            rateBoost: rateBoost,
            onFinish: onFinish,
          );
        }
        return false;
      } finally {
        if (epoch == _speakEpoch) {
          if (restartKeeperAfterTts) {
            await BackgroundAudioKeeper.instance.start();
          } else if (keeperWasRunning && _sessionKeepAlive) {
            await BackgroundAudioKeeper.instance.resumeAfterSpeech();
          }
        }
      }
    } finally {
      if (epoch == _speakEpoch) {
        _utteranceActive = false;
        notifyListeners();
      }
    }
  }

  /// ネイティブ TTS: 性別を OS 側に渡し、日本語音声を直接選択して発話
  Future<bool> _speakNative({
    required String text,
    required int epoch,
    required double pitchMultiplier,
    required double rateBoost,
    VoidCallback? onFinish,
  }) async {
    final rate = (_settings.speechRate + rateBoost).clamp(0.35, 0.68);
    final rawGender = _settings.speechVoiceGender;
    // ランダムの場合は質問ごとに男女を1度だけ決定し、同じ質問内の全発話に同じ声を使う
    final String gender;
    if (SpeechVoiceGender.fromStored(rawGender) == SpeechVoiceGender.random) {
      _lockedGender ??= Random().nextBool()
          ? SpeechVoiceGender.male.rawValue
          : SpeechVoiceGender.female.rawValue;
      gender = _lockedGender!;
    } else {
      gender = rawGender;
    }

    _isSpeaking = true;
    notifyListeners();

    final chunks = JapaneseSpeechTextFormatter.utteranceChunks(text);
    // TTS 結果の分類:
    //   true  = 正常完了
    //   false = キャンセル / エンジンエラー（タイマー開始しない）
    //   null  = 日本語TTS未インストール（スキップ扱い→タイマー開始する）
    bool allSucceeded = true;
    bool ttsSkipped = false;
    for (final chunk in chunks) {
      if (epoch != _speakEpoch || !_isSpeaking) break;
      final ok = await NativeTtsPlatform.speak(
        text: chunk,
        gender: gender,
        rate: rate,
        pitch: pitchMultiplier,
      );
      if (epoch != _speakEpoch || !_isSpeaking) break;
      if (ok == null) {
        // 日本語 TTS 未インストール — フラグ更新してタイマーは通常通り開始
        ttsSkipped = true;
        if (_ttsAvailable) {
          _ttsAvailable = false;
        }
        break;
      }
      if (!ok) {
        allSucceeded = false;
        break;
      }
    }

    if (epoch != _speakEpoch) {
      return false;
    }

    if (_isSpeaking) {
      _isSpeaking = false;
      notifyListeners();
      final succeeded = allSucceeded || ttsSkipped;
      if (succeeded) {
        onFinish?.call();
      }
      return succeeded;
    }

    if (!_sessionKeepAlive) {
      await _deactivateSessionIfPossible();
    }
    return false;
  }

  void clearGenderLock() => _lockedGender = null;

  Future<void> stop() async {
    _speakEpoch++;
    final wasSpeakingOrPaused = _isSpeaking || _isPaused || _utteranceActive;
    _utteranceActive = false;
    _isSpeaking = false;
    _isPaused = false;
    if (!wasSpeakingOrPaused) return;
    if (NativeTtsPlatform.isSupported) {
      await NativeTtsPlatform.stop();
    }
    notifyListeners();
    if (!_sessionKeepAlive) {
      await _deactivateSessionIfPossible();
    }
  }

  void pause() {
    if (!_isSpeaking || _isPaused) return;
    _isPaused = true;
    if (NativeTtsPlatform.isSupported) {
      NativeTtsPlatform.pause();
    }
    notifyListeners();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    if (NativeTtsPlatform.isSupported) {
      NativeTtsPlatform.resume();
    }
    notifyListeners();
  }

  void recoverFromSuspension() {
    if (_isSpeaking) {
      _isSpeaking = false;
      notifyListeners();
    }
    if (_sessionKeepAlive) {
      ensureSpeechAudioSession();
    }
  }

  Future<void> _deactivateSessionIfPossible() async {
    if (_sessionKeepAlive || BackgroundAudioKeeper.instance.isRunning) return;
    try {
      final session = await AudioSession.instance;
      // Re-check: state may have changed while awaiting (Android race condition)
      if (_sessionKeepAlive || BackgroundAudioKeeper.instance.isRunning) return;
      await session.setActive(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}

/// 読み上げ前にオーディオセッションを playback に戻す。
/// STT 後に playAndRecord のまま残ると iOS で TTS が無音になる。
/// キープアライブ稼働中は mixWithOthers を維持するが、TTS 一時停止中は外す。
Future<void> ensureSpeechAudioSession() async {
  try {
    final session = await AudioSession.instance;
    final keeper = BackgroundAudioKeeper.instance;
    final keeperRunning = !Platform.isAndroid && keeper.isRunning;
    final useMixWithOthers =
        keeperRunning && !keeper.isPausedForSpeech;
    if (useMixWithOthers) {
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
      ));
    } else {
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
      ));
    }
    await session.setActive(true);
  } catch (_) {}
}

/// Android STT 直前にマイク向けセッションへ切り替える（無音キープアライブと競合しないよう keeper は停止済み想定）
Future<void> ensureSpeechCaptureAudioSession() async {
  if (!Platform.isAndroid) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
        flags: AndroidAudioFlags.audibilityEnforced,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    await session.setActive(true);
  } catch (_) {}
}
