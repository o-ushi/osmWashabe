import '../data/jsst_scoring_lexicon.dart';

/// 文字起こしが日本語発話として参考レベル算出に足るかを判定する（オフライン・ルールベース）。
abstract final class JapaneseTranscriptValidity {
  static const int minSignificantLength = 10;

  /// ラテン文字がこの割合を超えると非日本語（ベトナム語ローマ字等）とみなす。
  static const double maxLatinRatio = 0.12;

  /// 有意文字のうち日本語文字（ひらがな・カタカナ・漢字・長音）の最低割合。
  static const double minJapaneseScriptRatio = 0.75;

  /// 日本語文字のうちひらがなの最低割合（長文）。カタカナだらけの幻覚文字起こし対策。
  static const double minHiraganaAmongJapaneseRatio = 0.10;

  static bool isEligibleForReferenceLevel(String text) => analyze(text).eligible;

  static JapaneseTranscriptValidityAnalysis analyze(String text) {
    final trimmed = text.trim();
    if (trimmed.length < minSignificantLength) {
      return const JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.tooShort,
      );
    }

    var hiraganaCount = 0;
    var katakanaCount = 0;
    var kanjiCount = 0;
    var latinCount = 0;
    var digitCount = 0;
    var significantCount = 0;
    var currentKatakanaRun = 0;
    var maxKatakanaRun = 0;

    for (final character in trimmed.split('')) {
      if (_isIgnorable(character)) continue;
      significantCount++;

      if (_isHiragana(character)) {
        hiraganaCount++;
        currentKatakanaRun = 0;
        continue;
      }
      if (_isKatakana(character)) {
        katakanaCount++;
        currentKatakanaRun++;
        maxKatakanaRun = maxKatakanaRun < currentKatakanaRun
            ? currentKatakanaRun
            : maxKatakanaRun;
        continue;
      }
      if (_isKanji(character)) {
        kanjiCount++;
        currentKatakanaRun = 0;
        continue;
      }
      if (_isLatin(character)) {
        latinCount++;
        currentKatakanaRun = 0;
        continue;
      }
      if (_isDigit(character)) {
        digitCount++;
        currentKatakanaRun = 0;
      }
    }

    if (significantCount < minSignificantLength) {
      return const JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.tooShort,
      );
    }

    final japaneseCount = hiraganaCount + katakanaCount + kanjiCount;
    final latinRatio = latinCount / significantCount;
    final japaneseScriptRatio = japaneseCount / significantCount;
    final hiraganaAmongJapaneseRatio =
        japaneseCount > 0 ? hiraganaCount / japaneseCount : 0.0;
    final commonSegmentHits = _countDistinctCommonSegments(trimmed);

    final metrics = JapaneseTranscriptValidityMetrics(
      significantCount: significantCount,
      hiraganaCount: hiraganaCount,
      katakanaCount: katakanaCount,
      kanjiCount: kanjiCount,
      latinCount: latinCount,
      digitCount: digitCount,
      latinRatio: latinRatio,
      japaneseScriptRatio: japaneseScriptRatio,
      hiraganaAmongJapaneseRatio: hiraganaAmongJapaneseRatio,
      commonSegmentHits: commonSegmentHits,
      maxKatakanaRun: maxKatakanaRun,
    );

    if (latinRatio > maxLatinRatio) {
      return JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.tooMuchLatin,
        metrics: metrics,
      );
    }

    if (japaneseScriptRatio < minJapaneseScriptRatio) {
      return JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.insufficientJapaneseScript,
        metrics: metrics,
      );
    }

    final requiredCommonHits = _requiredCommonSegmentHits(significantCount);
    if (commonSegmentHits < requiredCommonHits) {
      return JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.insufficientCommonJapanese,
        metrics: metrics,
      );
    }

    if (significantCount >= 35 &&
        hiraganaAmongJapaneseRatio < minHiraganaAmongJapaneseRatio &&
        commonSegmentHits < 4) {
      return JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.insufficientHiragana,
        metrics: metrics,
      );
    }

    if (significantCount >= 40 &&
        hiraganaCount == 0 &&
        kanjiCount < 3 &&
        maxKatakanaRun >= 35) {
      return JapaneseTranscriptValidityAnalysis.ineligible(
        reason: JapaneseTranscriptIneligibilityReason.katakanaHallucination,
        metrics: metrics,
      );
    }

    return JapaneseTranscriptValidityAnalysis.eligible(metrics: metrics);
  }

  static int _requiredCommonSegmentHits(int significantCount) {
    if (significantCount >= 50) return 3;
    if (significantCount >= 25) return 2;
    return 1;
  }

  static int _countDistinctCommonSegments(String text) {
    var hits = 0;
    for (final segment in _commonSegments) {
      if (text.contains(segment)) hits++;
    }
    return hits;
  }

  static bool _isIgnorable(String character) {
    if (character.trim().isEmpty) return true;
    return '、。！？!?.,;:「」『』（）()[]【】・…'.contains(character);
  }

  static bool _isHiragana(String character) {
    final code = character.codeUnitAt(0);
    return code >= 0x3040 && code <= 0x309F;
  }

  static bool _isKatakana(String character) {
    final code = character.codeUnitAt(0);
    return (code >= 0x30A0 && code <= 0x30FF) || character == 'ー';
  }

  static bool _isKanji(String character) {
    final code = character.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  static bool _isLatin(String character) {
    final code = character.codeUnitAt(0);
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      return true;
    }
    // ベトナム語などのラテン拡張（付加記号付き）
    return code >= 0x00C0 && code <= 0x024F;
  }

  static bool _isDigit(String character) {
    final code = character.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || (code >= 0xFF10 && code <= 0xFF19);
  }

  static final List<String> _commonSegments = [
    'です',
    'ます',
    'した',
    'して',
    'ない',
    'んです',
    'ので',
    'から',
    'けど',
    'けれど',
    'という',
    'って',
    'でした',
    'ました',
    'ません',
    'ている',
    'ていた',
    'てる',
    '私',
    '僕',
    '自分',
    'これ',
    'それ',
    'あれ',
    '思',
    '言',
    '話',
    '聞',
    '見',
    '行',
    '来',
    '子供',
    '家族',
    '仕事',
    '今日',
    '昨日',
    '明日',
    '時間',
    '人',
    '物',
    '好き',
    '大変',
    '難しい',
    '楽し',
    '疲れ',
    ...JsstScoringLexicon.teineigoSttFallbackMarkers,
    ...JsstScoringLexicon.subordinateConnectors,
    ...JsstScoringLexicon.coordinationMarkers,
  ];
}

enum JapaneseTranscriptIneligibilityReason {
  none,
  tooShort,
  tooMuchLatin,
  insufficientJapaneseScript,
  insufficientCommonJapanese,
  insufficientHiragana,
  katakanaHallucination,
}

class JapaneseTranscriptValidityMetrics {
  const JapaneseTranscriptValidityMetrics({
    required this.significantCount,
    required this.hiraganaCount,
    required this.katakanaCount,
    required this.kanjiCount,
    required this.latinCount,
    required this.digitCount,
    required this.latinRatio,
    required this.japaneseScriptRatio,
    required this.hiraganaAmongJapaneseRatio,
    required this.commonSegmentHits,
    required this.maxKatakanaRun,
  });

  final int significantCount;
  final int hiraganaCount;
  final int katakanaCount;
  final int kanjiCount;
  final int latinCount;
  final int digitCount;
  final double latinRatio;
  final double japaneseScriptRatio;
  final double hiraganaAmongJapaneseRatio;
  final int commonSegmentHits;
  final int maxKatakanaRun;
}

class JapaneseTranscriptValidityAnalysis {
  const JapaneseTranscriptValidityAnalysis._({
    required this.eligible,
    required this.reason,
    this.metrics,
  });

  const JapaneseTranscriptValidityAnalysis.eligible({
    required JapaneseTranscriptValidityMetrics metrics,
  }) : this._(
          eligible: true,
          reason: JapaneseTranscriptIneligibilityReason.none,
          metrics: metrics,
        );

  const JapaneseTranscriptValidityAnalysis.ineligible({
    required JapaneseTranscriptIneligibilityReason reason,
    JapaneseTranscriptValidityMetrics? metrics,
  }) : this._(eligible: false, reason: reason, metrics: metrics);

  final bool eligible;
  final JapaneseTranscriptIneligibilityReason reason;
  final JapaneseTranscriptValidityMetrics? metrics;

  /// 採点結果画面用の説明文キー（[eligible] が false のときのみ）
  String? get messageKey {
    if (eligible) return null;
    return switch (reason) {
      JapaneseTranscriptIneligibilityReason.tooShort =>
        '参考レベル_発話が短すぎます',
      JapaneseTranscriptIneligibilityReason.tooMuchLatin =>
        '参考レベル_日本語として不十分',
      JapaneseTranscriptIneligibilityReason.insufficientJapaneseScript =>
        '参考レベル_日本語として不十分',
      JapaneseTranscriptIneligibilityReason.insufficientCommonJapanese =>
        '参考レベル_日本語として不十分',
      JapaneseTranscriptIneligibilityReason.insufficientHiragana =>
        '参考レベル_日本語として不十分',
      JapaneseTranscriptIneligibilityReason.katakanaHallucination =>
        '参考レベル_日本語として不十分',
      JapaneseTranscriptIneligibilityReason.none => null,
    };
  }
}
