import 'dart:typed_data';

/// 16bit・モノラルの PCM [samples] を WAV のバイト列にする（無音の素材・合図の音で共通）。
Uint8List pcm16MonoWav(Int16List samples, {int sampleRate = 44100}) {
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;
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
  final data = ByteData(dataSize);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  wav.add(data.buffer.asUint8List());
  return wav.toBytes();
}
