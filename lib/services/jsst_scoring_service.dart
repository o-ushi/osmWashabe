import 'dart:math';

import '../data/jsst_scoring_lexicon.dart';
import '../models/practice_models.dart';
import 'japanese_transcript_validity.dart';

/// JSST採点基準のうち「待遇表現」「テキストタイプ」「流暢さ（時間の使い方）」を近似する。
/// 文法・発音・公式の総合レベルは判定しない（公式採点の代替ではない）。
abstract final class JsstScoringService {
  /// 日本語会話のおおよその発話速度（文字/秒）。参考 MP3 の level9 実測に合わせた概算。
  static const double charsPerSecondEstimate = 5.5;

  /// チャンク間ギャップがこれ以上なら「長い沈黙」とみなす（秒）
  static const double longPauseThresholdSeconds = 4.0;

  static ScoringResult score(
    List<TranscriptChunk> chunks, {
    SpeechSessionContext? session,
  }) {
    final fullText = chunks.map((c) => c.text).join('');
    final allotted = session?.allottedSeconds ?? 45;
    return ScoringResult(
      transcriptChunks: chunks,
      fullTranscript: fullText,
      keigo: _scoreKeigo(fullText),
      complexity: _scoreComplexity(chunks),
      fluency: _scoreFluency(chunks, session, allotted),
      session: session,
    );
  }

  static int keigoReferenceLevel(ScoringResult result) {
    final keigo = result.keigo;
    if (keigo.varietyScore > 0) return 4;

    final text = result.fullTranscript;
    final chunkCount = result.transcriptChunks.length;
    final fluency = result.fluency;

    // STT は母語話者の です/ます を落とすことがある（level9 文字起こし 65 件 vs 実機 STT 0 件）。
    // 流暢さ・発話量が level9 相当なら JSST 1-2 には落とさない。
    if (fluency.referenceLevel >= 4 && text.length >= 80 && chunkCount >= 5) {
      return 4;
    }
    if (text.length >= 40 || chunkCount >= 3) return 3;
    return 1;
  }

  static int? complexityReferenceLevel(SentenceComplexityAnalysis complexity) {
    if (complexity.totalUnits == 0) return null;
    if (complexity.complexityRatio == 0) return 1;
    if (complexity.complexityRatio <= 0.10) return 2;
    if (complexity.complexityRatio <= 0.33) return 3;
    return 4;
  }

  static int fluencyReferenceLevel(FluencyAnalysis fluency) =>
      fluency.referenceLevel;

  /// 文字起こしが日本語発話として参考レベル算出に足るか。
  static bool isEligibleForReferenceLevel(ScoringResult result) {
    return JapaneseTranscriptValidity.isEligibleForReferenceLevel(
      result.fullTranscript,
    );
  }

  static JapaneseTranscriptValidityAnalysis referenceLevelEligibility(
    ScoringResult result,
  ) {
    return JapaneseTranscriptValidity.analyze(result.fullTranscript);
  }

  /// 3軸のうち最も低い参考レベル。
  /// null は複雑度未計測、または日本語として不十分な文字起こし。
  static int? combinedReferenceLevel(ScoringResult result) {
    if (!isEligibleForReferenceLevel(result)) return null;
    final kl = keigoReferenceLevel(result);
    final cl = complexityReferenceLevel(result.complexity);
    final fl = fluencyReferenceLevel(result.fluency);
    if (cl == null) return null;
    return min(kl, min(cl, fl));
  }

  static bool keigoPossiblyMissedByStt(ScoringResult result) {
    return result.keigo.varietyScore == 0 &&
        keigoReferenceLevel(result) >= 3 &&
        result.fullTranscript.length >= 60;
  }

  static KeigoAnalysis _scoreKeigo(String text) {
    final sonkeigo = <String>{};
    for (final marker in JsstScoringLexicon.sonkeigoMarkers) {
      if (text.contains(marker)) sonkeigo.add(marker);
    }
    for (final match
        in JsstScoringLexicon.sonkeigoPrefixPattern.allMatches(text)) {
      final value = match.group(0);
      if (value != null) sonkeigo.add(value);
    }

    final kenjougo = <String>{};
    for (final marker in JsstScoringLexicon.kenjougoMarkers) {
      if (text.contains(marker)) kenjougo.add(marker);
    }

    final teineigo = <String>{
      for (final match in JsstScoringLexicon.teineigoPattern.allMatches(text))
        if (match.group(0) != null) match.group(0)!,
    };
    for (final marker in JsstScoringLexicon.teineigoSttFallbackMarkers) {
      if (text.contains(marker)) teineigo.add(marker);
    }

    final categories = [
      KeigoCategoryResult(category: 'sonkeigo', matchedExpressions: sonkeigo),
      KeigoCategoryResult(category: 'kenjougo', matchedExpressions: kenjougo),
      KeigoCategoryResult(category: 'teineigo', matchedExpressions: teineigo),
    ];
    final varietyScore =
        categories.where((c) => c.matchedExpressions.isNotEmpty).length;
    return KeigoAnalysis(categories: categories, varietyScore: varietyScore);
  }

  static SentenceComplexityAnalysis _scoreComplexity(
      List<TranscriptChunk> chunks) {
    final fullText = chunks.map((chunk) => chunk.text).join('');
    var units = _splitIntoUnits(fullText);
    // STT は句点を付けないため全文が 1 ユニットになることがある。
    // その場合はチャンク（ポーズ）単位にフォールバックする。
    if (units.length <= 1 && chunks.length > 1) {
      units =
          chunks.map((c) => c.text.trim()).where((u) => u.isNotEmpty).toList();
    }
    if (units.isEmpty) {
      return const SentenceComplexityAnalysis(
        totalUnits: 0,
        complexUnitCount: 0,
        complexityRatio: 0,
      );
    }

    var complexUnitCount = 0;
    for (final unit in units) {
      if (_classifyUnit(unit) != SentenceUnitType.simple) complexUnitCount++;
    }

    return SentenceComplexityAnalysis(
      totalUnits: units.length,
      complexUnitCount: complexUnitCount,
      complexityRatio: complexUnitCount / units.length,
    );
  }

  static FluencyAnalysis _scoreFluency(
    List<TranscriptChunk> chunks,
    SpeechSessionContext? session,
    int allottedSeconds,
  ) {
    final started = session?.startedAt;
    final ended = session?.endedAt;
    if (chunks.isEmpty || started == null || ended == null) {
      return FluencyAnalysis.unavailable(allottedSeconds: allottedSeconds);
    }

    final sorted = [...chunks]
      ..sort((a, b) => a.recognizedAt.compareTo(b.recognizedAt));
    final capturedSeconds = max(
      0.0,
      ended.difference(started).inMilliseconds / 1000.0,
    );
    if (capturedSeconds <= 0) {
      return FluencyAnalysis.unavailable(allottedSeconds: allottedSeconds);
    }

    final fullText = sorted.map((c) => c.text).join('');
    final spokenCharacterCount = fullText.length;

    final timeToFirstSpeechSeconds = max(
      0.0,
      sorted.first.recognizedAt.difference(started).inMilliseconds / 1000.0,
    );

    var estimatedSpeechSeconds = 0.0;
    for (final chunk in sorted) {
      estimatedSpeechSeconds += _estimateChunkSpeechSeconds(chunk.text);
    }

    var estimatedSilenceSeconds = timeToFirstSpeechSeconds;
    var longPauseCount = 0;
    for (var i = 0; i < sorted.length - 1; i++) {
      final gapSeconds = sorted[i + 1]
              .recognizedAt
              .difference(sorted[i].recognizedAt)
              .inMilliseconds /
          1000.0;
      // チャンク i の発話終了〜チャンク i+1 開始の間を沈黙として推定する。
      // ここで i+1 の発話長を引くと沈黙量が不安定になるため、必ず i を使う。
      final pauseSeconds =
          gapSeconds - _estimateChunkSpeechSeconds(sorted[i].text);
      if (pauseSeconds >= longPauseThresholdSeconds) longPauseCount++;
      if (pauseSeconds > 0) estimatedSilenceSeconds += pauseSeconds;
    }

    estimatedSpeechSeconds = min(estimatedSpeechSeconds, capturedSeconds);
    estimatedSilenceSeconds = min(estimatedSilenceSeconds, capturedSeconds);

    final silenceRatio =
        allottedSeconds > 0 ? estimatedSilenceSeconds / allottedSeconds : 0.0;
    final timeUtilization =
        allottedSeconds > 0 ? estimatedSpeechSeconds / allottedSeconds : 0.0;
    final charactersPerAllottedMinute = allottedSeconds > 0
        ? spokenCharacterCount / (allottedSeconds / 60.0)
        : 0.0;

    final referenceLevel = _fluencyReferenceLevel(
      allottedSeconds: allottedSeconds,
      timeUtilization: timeUtilization,
      silenceRatio: silenceRatio,
      charactersPerAllottedMinute: charactersPerAllottedMinute,
      timeToFirstSpeechSeconds: timeToFirstSpeechSeconds,
      longPauseCount: longPauseCount,
      spokenCharacterCount: spokenCharacterCount,
    );

    return FluencyAnalysis(
      allottedSeconds: allottedSeconds,
      capturedSeconds: capturedSeconds,
      timeToFirstSpeechSeconds: timeToFirstSpeechSeconds,
      estimatedSpeechSeconds: estimatedSpeechSeconds,
      estimatedSilenceSeconds: estimatedSilenceSeconds,
      silenceRatio: silenceRatio,
      timeUtilization: timeUtilization,
      spokenCharacterCount: spokenCharacterCount,
      charactersPerAllottedMinute: charactersPerAllottedMinute,
      longPauseCount: longPauseCount,
      referenceLevel: referenceLevel,
    );
  }

  static double _estimateChunkSpeechSeconds(String text) {
    final length = text.length;
    if (length == 0) return 0;
    return max(0.4, length / charsPerSecondEstimate);
  }

  /// 参考 MP3（level_4 / level_9）の 45 秒枠分析に基づく閾値。
  /// 比率指標（利用率・沈黙率）は枠の長さに依存しない。
  /// 長い沈黙回数だけ発話枠に比例して緩和する（60秒・15+60秒の発話フェーズ対応）。
  static int _fluencyReferenceLevel({
    required int allottedSeconds,
    required double timeUtilization,
    required double silenceRatio,
    required double charactersPerAllottedMinute,
    required double timeToFirstSpeechSeconds,
    required int longPauseCount,
    required int spokenCharacterCount,
  }) {
    if (spokenCharacterCount < 15) return 1;

    final utilizationLevel = timeUtilization <= 0.38
        ? 2
        : timeUtilization <= 0.48
            ? 3
            : 4;

    final outputLevel = charactersPerAllottedMinute < 85
        ? 2
        : charactersPerAllottedMinute < 155
            ? 3
            : 4;

    final silenceLevel = silenceRatio >= 0.62
        ? 2
        : silenceRatio >= 0.45
            ? 3
            : 4;

    var level = min(utilizationLevel, min(outputLevel, silenceLevel));

    if (timeToFirstSpeechSeconds > 8) {
      level = min(level, 2);
    } else if (timeToFirstSpeechSeconds > 5) {
      level = min(level, 3);
    }

    if (longPauseCount >= _scaledPauseCutoff(allottedSeconds, baseFor45: 5)) {
      level = min(level, 2);
    } else if (longPauseCount >=
        _scaledPauseCutoff(allottedSeconds, baseFor45: 3)) {
      level = min(level, 3);
    }

    return max(1, level);
  }

  static int _scaledPauseCutoff(int allottedSeconds, {required int baseFor45}) {
    if (allottedSeconds <= 45) return baseFor45;
    return (baseFor45 * allottedSeconds / 45).ceil();
  }

  static SentenceUnitType _classifyUnit(String unit) {
    for (final connector in JsstScoringLexicon.subordinateConnectors) {
      if (unit.contains(connector)) return SentenceUnitType.complex;
    }
    for (final marker in JsstScoringLexicon.coordinationMarkers) {
      if (unit.contains(marker)) return SentenceUnitType.compound;
    }
    return SentenceUnitType.simple;
  }

  /// リリスンループの区切りが粗い場合のフォールバック: 句読点でさらに分割する
  static List<String> _splitIntoUnits(String text) {
    final units = <String>[];
    var current = '';
    for (final character in text.split('')) {
      current += character;
      if ('。！？!?'.contains(character)) {
        final trimmed = current.trim();
        if (trimmed.isNotEmpty) units.add(trimmed);
        current = '';
      }
    }
    final remaining = current.trim();
    if (remaining.isNotEmpty) units.add(remaining);
    return units;
  }
}
