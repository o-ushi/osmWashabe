import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:osm_washabe/services/wav_bytes.dart';

/// 以前それぞれのサービスに書いていた組み立て方（比べるための写し）。
Uint8List _legacy(Int16List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final wav = BytesBuilder();
  void append32(int v) => wav
      .add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void append16(int v) => wav
      .add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  wav.add('RIFF'.codeUnits);
  append32(36 + dataSize);
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
  for (final s in samples) {
    wav.add((ByteData(2)..setInt16(0, s, Endian.little)).buffer.asUint8List());
  }
  return wav.toBytes();
}

void main() {
  test('無音 0.1 秒は、以前と同じバイト列', () {
    final silent = Int16List(4410);
    expect(pcm16MonoWav(silent), _legacy(silent, 44100));
    expect(pcm16MonoWav(silent).length, 44 + 8820);
  });

  test('音のある波形も、以前と同じバイト列', () {
    final samples = Int16List.fromList([0, 1, -1, 32767, -32768, 1234]);
    expect(pcm16MonoWav(samples, sampleRate: 22050), _legacy(samples, 22050));
  });
}
