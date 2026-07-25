import 'topic.dart';

/// セッション（1問ずつ / 模擬試験）
enum AppSessionMode {
  singleQuestion('1問ずつ'),
  mockExam('模擬試験');

  const AppSessionMode(this.label);
  final String label;
}

/// 練習モード（通常 / シチュエーション）
enum TrainingMode {
  normal('通常'),
  situation('シチュエーション');

  const TrainingMode(this.label);
  final String label;
}

/// 通常モードのタイマーオプション
enum NormalTimerOption {
  sec45,
  sec60,
  prep15speaking60;

  String label() {
    switch (this) {
      case NormalTimerOption.sec45:
        return '45秒';
      case NormalTimerOption.sec60:
        return '60秒';
      case NormalTimerOption.prep15speaking60:
        return '15+60秒';
    }
  }
}

/// 二相タイマーのフェーズ
enum SituationTimerPhase {
  preparation('準備', 15),
  speaking('発話', 60);

  const SituationTimerPhase(this.label, this.durationSeconds);
  final String label;
  final int durationSeconds;
}

/// 模擬試験の問題種別
enum MockExamQuestionKind {
  normal45,
  normal60,
  normal15plus60,
  situationKeigo;

  String stepLabel() {
    switch (this) {
      case MockExamQuestionKind.normal45:
        return '通常（45秒）';
      case MockExamQuestionKind.normal60:
        return '60秒';
      case MockExamQuestionKind.normal15plus60:
        return '準備付き（15+60秒）';
      case MockExamQuestionKind.situationKeigo:
        return '敬語シチュエーション';
    }
  }
}

/// 模擬試験の1ステップ
class MockExamStep {
  MockExamStep({
    required this.kind,
    this.topic,
    this.situation,
  }) : id = Object();

  final Object id;
  final MockExamQuestionKind kind;
  final String? topic;
  final SituationPrompt? situation;
}

/// 音声認識のリリスンループ1サイクルで確定した発話チャンク
class TranscriptChunk {
  const TranscriptChunk({required this.text, required this.recognizedAt});

  final String text;
  final DateTime recognizedAt;
}

/// 待遇表現カテゴリ（尊敬語/謙譲語/丁寧語）ごとの検出結果
class KeigoCategoryResult {
  const KeigoCategoryResult({
    required this.category,
    required this.matchedExpressions,
  });

  final String category;
  final Set<String> matchedExpressions;
}

/// JSST「待遇表現」軸の近似スコア
class KeigoAnalysis {
  const KeigoAnalysis({required this.categories, required this.varietyScore});

  final List<KeigoCategoryResult> categories;

  /// 使用が検出されたカテゴリ数（0〜3）。JSST待遇表現軸の粗い代理指標。
  final int varietyScore;
}

/// 発話単位の構造分類
enum SentenceUnitType { simple, compound, complex }

/// JSST「テキストタイプ」軸の近似スコア
class SentenceComplexityAnalysis {
  const SentenceComplexityAnalysis({
    required this.totalUnits,
    required this.complexUnitCount,
    required this.complexityRatio,
  });

  final int totalUnits;
  final int complexUnitCount;

  /// (重文+複文の発話単位数) / 全発話単位数
  final double complexityRatio;
}

/// 1回の発話フェーズにおける STT セッションの時間枠
class SpeechSessionContext {
  const SpeechSessionContext({
    required this.allottedSeconds,
    this.startedAt,
    this.endedAt,
  });

  /// タイマーで与えられた発話秒数（45 または 60）
  final int allottedSeconds;
  final DateTime? startedAt;
  final DateTime? endedAt;
}

/// JSST「流暢さ／時間の使い方」軸の近似スコア。
/// 書き起こしだけでは分からない沈黙・発話量を、チャンクの時刻と文字数から推定する。
class FluencyAnalysis {
  const FluencyAnalysis({
    required this.allottedSeconds,
    required this.capturedSeconds,
    required this.timeToFirstSpeechSeconds,
    required this.estimatedSpeechSeconds,
    required this.estimatedSilenceSeconds,
    required this.silenceRatio,
    required this.timeUtilization,
    required this.spokenCharacterCount,
    required this.charactersPerAllottedMinute,
    required this.longPauseCount,
    required this.referenceLevel,
  });

  factory FluencyAnalysis.unavailable({required int allottedSeconds}) {
    return FluencyAnalysis(
      allottedSeconds: allottedSeconds,
      capturedSeconds: 0,
      timeToFirstSpeechSeconds: 0,
      estimatedSpeechSeconds: 0,
      estimatedSilenceSeconds: 0,
      silenceRatio: 0,
      timeUtilization: 0,
      spokenCharacterCount: 0,
      charactersPerAllottedMinute: 0,
      longPauseCount: 0,
      referenceLevel: 1,
    );
  }

  final int allottedSeconds;
  final double capturedSeconds;
  final double timeToFirstSpeechSeconds;
  final double estimatedSpeechSeconds;
  final double estimatedSilenceSeconds;
  final double silenceRatio;
  final double timeUtilization;
  final int spokenCharacterCount;
  final double charactersPerAllottedMinute;
  final int longPauseCount;

  /// 1〜4 の参考レベル（JSST 1〜2 / 3〜4 / 5〜6 / 7〜）
  final int referenceLevel;
}

/// 1回の発話フェーズに対する採点結果（永続化はしない）
class ScoringResult {
  ScoringResult({
    required this.transcriptChunks,
    required this.fullTranscript,
    required this.keigo,
    required this.complexity,
    required this.fluency,
    this.session,
  }) : generatedAt = DateTime.now();

  final List<TranscriptChunk> transcriptChunks;
  final String fullTranscript;
  final KeigoAnalysis keigo;
  final SentenceComplexityAnalysis complexity;
  final FluencyAnalysis fluency;
  final SpeechSessionContext? session;
  final DateTime generatedAt;
}
