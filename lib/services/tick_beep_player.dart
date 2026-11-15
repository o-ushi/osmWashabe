import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'wav_bytes.dart';

/// iOS `TickBeepPlayer` — 880Hz 合成ビープ
///
/// Swift 版と同様、ソースは一度だけ読み込み、[play] は stop → seek(0) → play のみ。
/// 毎回 setAudioSource すると 1 秒周期のビープがぎこちなくなる。
class TickBeepPlayer {
  TickBeepPlayer._();
  static final TickBeepPlayer instance = TickBeepPlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? _wavPath;
  Future<void>? _loadFuture;
  bool _sourceLoaded = false;

  /// 準備カウント開始前に呼ぶと最初のビープが遅れにくい。
  Future<void> warmUp() => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    _loadFuture ??= _loadSource();
    await _loadFuture;
  }

  Future<void> _loadSource() async {
    _wavPath ??= await _ensureWavFile();
    if (_sourceLoaded) return;
    await _player.setVolume(0.75);
    await _player.setAudioSource(
      AudioSource.file(_wavPath!),
      preload: true,
    );
    _sourceLoaded = true;
  }

  Future<void> play() async {
    try {
      await _ensureLoaded();
      if (_player.playing) {
        await _player.stop();
      }
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } catch (_) {}
  }

  Future<String> _ensureWavFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/osm_tick_beep.wav');
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildWav());
    }
    return file.path;
  }

  Uint8List _buildWav() {
    const sampleRate = 44100;
    const frequency = 880.0;
    const durationSec = 0.055;
    final frameCount = (sampleRate * durationSec).round();
    const fadeFrames = 352;

    final samples = Int16List(frameCount);
    final omega = 2 * pi * frequency / sampleRate;
    for (var i = 0; i < frameCount; i++) {
      var s = sin(omega * i) * 0.75;
      if (i < fadeFrames) s *= i / fadeFrames;
      final tail = frameCount - 1 - i;
      if (tail < fadeFrames) s *= tail / fadeFrames;
      samples[i] = (s * 32767).round().clamp(-32768, 32767);
    }

    return pcm16MonoWav(samples, sampleRate: sampleRate);
  }
}
