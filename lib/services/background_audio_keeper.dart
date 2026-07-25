import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// iOS `BackgroundAudioKeeper` — 無音ループでバックグラウンド動作を維持
class BackgroundAudioKeeper {
  BackgroundAudioKeeper._();
  static final BackgroundAudioKeeper instance = BackgroundAudioKeeper._();

  final AudioPlayer _player = AudioPlayer();
  bool _isRunning = false;
  bool _pausedForSpeech = false;
  String? _silencePath;

  bool get isRunning => _isRunning;

  /// TTS のため一時停止中か（[pauseForSpeech] 済みで [resumeAfterSpeech] 前）
  bool get isPausedForSpeech => _pausedForSpeech;

  /// 実際にプレイヤーが再生中かどうか（Android でOS が再生を止めた場合を検知）
  bool get isActuallyPlaying => _isRunning && _player.playing;

  /// TTS 再生のため無音ループを一時停止
  Future<void> pauseForSpeech() async {
    if (!_isRunning || _pausedForSpeech) return;
    _pausedForSpeech = true;
    try {
      await _player.pause();
      if (Platform.isAndroid) {
        // Android では TTS エンジンが音声フォーカスを自律管理するため、
        // ここでセッション設定を変更すると OS 10–12 で TTS がフォーカスを
        // 取得できなくなる場合がある。プレイヤーを停止するだけにとどめる。
        return;
      }
      // iOS: mixWithOthers を外して TTS が適切なフォーカスを取得できるよう再設定
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
      ));
    } catch (_) {}
  }

  Future<void> resumeAfterSpeech() async {
    if (!_isRunning || !_pausedForSpeech) return;
    _pausedForSpeech = false;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
      ));
      await session.setActive(true);
    } catch (_) {}
    await recoverIfNeeded();
  }

  Future<void> start() async {
    if (_isRunning) {
      if (_pausedForSpeech) {
        _pausedForSpeech = false;
        await recoverIfNeeded();
      }
      return;
    }
    _isRunning = true;
    try {
      // 先にサイレンスファイルとプレイヤーを準備（resumeAfterSpeech でも使えるよう）
      _silencePath ??= await _ensureSilenceFile();
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(0);
      await _player.setAudioSource(AudioSource.file(_silencePath!));

      // ここで await が来た後に _pausedForSpeech が立っていれば TTS が発話中なので
      // mixWithOthers でセッションを上書きせず、再生も開始しない。
      // resumeAfterSpeech() が適切なタイミングで再設定・再開する。
      if (_pausedForSpeech) return;

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
      ));
      await session.setActive(true);
      await _player.play();
    } catch (_) {
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _pausedForSpeech = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> recoverIfNeeded() async {
    if (!_isRunning) return;
    if (_player.playing) return;
    try {
      if (_silencePath != null) {
        await _player.setAudioSource(AudioSource.file(_silencePath!));
        await _player.play();
      }
    } catch (_) {}
  }

  Future<String> _ensureSilenceFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/osm_silence.wav');
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildMinimalWav());
    }
    return file.path;
  }

  /// 0.1秒の無音 PCM WAV（iOS TickBeepPlayer と同様の生成方式）
  Uint8List _buildMinimalWav() {
    const sampleRate = 44100;
    const frameCount = 4410;
    const dataSize = frameCount * 2;
    const fileSize = 36 + dataSize;
    final wav = BytesBuilder();
    void append32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      wav.add(b.buffer.asUint8List());
    }

    void append16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      wav.add(b.buffer.asUint8List());
    }

    wav.add('RIFF'.codeUnits);
    append32(fileSize);
    wav.add('WAVEfmt '.codeUnits);
    append32(16);
    append16(1);
    append16(1);
    append32(sampleRate);
    append32(sampleRate * 2);
    append16(2);
    append16(16);
    wav.add('data'.codeUnits);
    append32(dataSize);
    wav.add(Uint8List(dataSize));
    return wav.toBytes();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
