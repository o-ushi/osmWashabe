class SpeechVoiceInfo {
  const SpeechVoiceInfo({
    required this.name,
    required this.qualityLabelKey,
    required this.isHighQuality,
    this.voiceMap,
  });

  final String name;
  final String qualityLabelKey;
  final bool isHighQuality;
  final Map<String, String>? voiceMap;
}

enum SpeechVoiceGender {
  male('男性の声', 'male'),
  female('女性の声', 'female'),
  random('ランダム', 'random');

  const SpeechVoiceGender(this.rawValue, this.nativeValue);
  final String rawValue;

  /// ネイティブ（iOS / Android）に渡す識別子。
  final String nativeValue;

  static SpeechVoiceGender fromStored(String raw) {
    return SpeechVoiceGender.values.firstWhere(
      (g) => g.rawValue == raw,
      orElse: () => SpeechVoiceGender.female,
    );
  }

  /// 保存値（例: '男性の声'）からネイティブ識別子（例: 'male'）へ変換する。
  static String nativeValueFor(String raw) => fromStored(raw).nativeValue;
}
