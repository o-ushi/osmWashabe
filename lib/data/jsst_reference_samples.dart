import '../l10n/app_strings.dart';
import '../models/practice_models.dart';
import '../services/jsst_scoring_service.dart';

/// 公式採点サンプル（文字起こし）から抜粋した参考ベンチマーク。
/// 採点結果画面でユーザーの発話と level 4 / level 9 を並べて比較する。
class JsstReferenceBenchmark {
  const JsstReferenceBenchmark({
    required this.id,
    required this.labelKey,
    required this.excerpt,
    required this.result,
  });

  final String id;
  final String labelKey;
  final String excerpt;
  final ScoringResult result;

  String shortLabel(String languageCode) => labelKey.tr(languageCode);

  int? get combinedLevel => JsstScoringService.combinedReferenceLevel(result);

  int get teineigoHitCount {
    for (final category in result.keigo.categories) {
      if (category.category == 'teineigo') {
        return category.matchedExpressions.length;
      }
    }
    return 0;
  }
}

/// 同一発話枠（45秒 or 60秒）における level 4 / level 9 の参考ペア。
class JsstReferenceBenchmarkSet {
  const JsstReferenceBenchmarkSet({
    required this.allottedSeconds,
    required this.level4,
    required this.level9,
  });

  final int allottedSeconds;
  final JsstReferenceBenchmark level4;
  final JsstReferenceBenchmark level9;

  Iterable<JsstReferenceBenchmark> get all => [level4, level9];
}

abstract final class JsstReferenceSamples {
  static const _levelLabelKeys = {
    1: 'JSST 1〜2',
    2: 'JSST 3〜4',
    3: 'JSST 5〜6',
    4: 'JSST 7〜',
  };

  static const _level4FullText =
      '私の週末はね、子供と一緒に遊ぶこととか、買い物をやって、料理を作ってることです。'
      'あとは生き物も大好きです。今アメリカにオバマです。大好きです。'
      '私の家族はね、私が子供が2人、一番大きな一人は今シンガポールの学校で勉強して、'
      '今18歳、そろそろに18歳です。私がね、辛いものは大好きだから、'
      '辛いものとあと美味しいもの、できるの場所を選んでます。';

  static const _level4Excerpt =
      '私の週末はね、子供と一緒に遊ぶこととか、買い物をやって、料理を作ってることです。'
      'あとは生き物も大好きです。今アメリカにオバマです。大好きです。';

  static const _level9CoreText =
      '私はとても疲れているときはまず外に出ます。散歩が趣味なので、散歩をします。'
      'うちが吉祥寺の近くにありますので、結構井の頭公園に行って散歩しますね。'
      '池があったり、大自然の緑があったり、季節によって植物が違ったりするので、'
      '結構楽しみにいつもしています。';

  static const _level9ExtendedText =
      '私はとても疲れているときはまず外に出ます。散歩が趣味なので、散歩をします。'
      'うちが吉祥寺の近くにありますので、結構井の頭公園に行って散歩しますね。'
      '池があったり、大自然の緑があったり、季節によって植物が違ったりするので、'
      '結構楽しみにいつもしています。私が行ってみたい国はフランスです。'
      'ルーブル博物館があったり、いろんな歴史の建物があったりするのもそうなんですけれども、'
      'あと友達がフランスのレオンっていうところに住んでいまして、'
      'ぜひワインや食べ物がおいしいということなので、ぜひ一度行ってみて、'
      'ガイドさんになってもらいたいと思っています。'
      '産業のグローバル化は、日本の会社しかよくわからないんですけれども、'
      'でもいいことではないかとは思います。';

  static final _cache = <int, JsstReferenceBenchmarkSet>{
    45: _buildSet(allottedSeconds: 45),
    60: _buildSet(allottedSeconds: 60),
  };

  static String levelLabel(int? level, String languageCode) => level == null
      ? '—'
      : (_levelLabelKeys[level]?.tr(languageCode) ?? '—');

  /// 発話フェーズの秒数（45 または 60）に正規化する。
  /// 15+60秒モードの発話フェーズも 60 として扱う。
  static int normalizeAllottedSeconds(int? seconds) =>
      seconds == 60 ? 60 : 45;

  /// ユーザーの発話枠に合わせた level 4 / level 9 参考値。
  static JsstReferenceBenchmarkSet forAllottedSeconds(int? seconds) {
    return _cache[normalizeAllottedSeconds(seconds)]!;
  }

  static JsstReferenceBenchmarkSet _buildSet({required int allottedSeconds}) {
    final level9Text =
        allottedSeconds >= 60 ? _level9ExtendedText : _level9CoreText;
    final level9Gap = allottedSeconds >= 60 ? 4.0 : 3.5;

    return JsstReferenceBenchmarkSet(
      allottedSeconds: allottedSeconds,
      level4: _buildLevel4(allottedSeconds),
      level9: _buildLevel9(allottedSeconds, level9Text, chunkGapSeconds: level9Gap),
    );
  }

  static JsstReferenceBenchmark _buildLevel4(int allottedSeconds) {
    final start = DateTime(2026, 1, 1, 12);
    final List<TranscriptChunk> chunks;
    if (allottedSeconds >= 60) {
      chunks = _sparseSttChunks(_level4FullText, start, gapSeconds: 10.0);
    } else {
      // 45秒枠: 発話量が少なく沈黙が多い典型パターン（校正テストと同型）
      chunks = [
        TranscriptChunk(
          text: '私の週末はね、',
          recognizedAt: start.add(const Duration(seconds: 6)),
        ),
        TranscriptChunk(
          text: '子供と一緒に遊ぶこととか、買い物をやって、料理を作ってることです。',
          recognizedAt: start.add(const Duration(seconds: 14)),
        ),
        TranscriptChunk(
          text: 'あとは生き物も大好きです。今アメリカにオバマです。大好きです。',
          recognizedAt: start.add(const Duration(seconds: 28)),
        ),
      ];
    }
    final result = JsstScoringService.score(
      chunks,
      session: _session(start, allottedSeconds),
    );

    return JsstReferenceBenchmark(
      id: 'level4',
      labelKey: '参考サンプル_Level4',
      excerpt: _level4Excerpt,
      result: result,
    );
  }

  static JsstReferenceBenchmark _buildLevel9(
    int allottedSeconds,
    String fullText, {
    required double chunkGapSeconds,
  }) {
    final start = DateTime(2026, 1, 1, 12);
    final chunks = _fluidSttChunks(fullText, start, chunkGapSeconds: chunkGapSeconds);
    final result = JsstScoringService.score(
      chunks,
      session: _session(start, allottedSeconds),
    );

    return JsstReferenceBenchmark(
      id: 'level9',
      labelKey: '参考サンプル_Level9',
      excerpt: _level9CoreText,
      result: result,
    );
  }

  static SpeechSessionContext _session(DateTime start, int allottedSeconds) {
    return SpeechSessionContext(
      allottedSeconds: allottedSeconds,
      startedAt: start,
      endedAt: start.add(Duration(seconds: allottedSeconds)),
    );
  }

  static List<TranscriptChunk> _fluidSttChunks(
    String text,
    DateTime start, {
    required double chunkGapSeconds,
  }) {
    return _sttLikeChunks(text, start, chunkGapSeconds: chunkGapSeconds);
  }

  static List<TranscriptChunk> _sparseSttChunks(
    String text,
    DateTime start, {
    required double gapSeconds,
  }) {
    return _sttLikeChunks(text, start, chunkGapSeconds: gapSeconds, firstOffset: 5.0);
  }

  static List<TranscriptChunk> _sttLikeChunks(
    String text,
    DateTime start, {
    required double chunkGapSeconds,
    double firstOffset = 2.0,
  }) {
    final chunks = <TranscriptChunk>[];
    final parts = text.split(RegExp(r'(?<=です|ます|ね|けど|ので|から|した|したい|思います|ません|でした)'));
    var buf = '';
    var elapsed = firstOffset;
    for (final part in parts) {
      buf += part;
      if (buf.trim().length >= 25) {
        chunks.add(TranscriptChunk(
          text: buf.trim(),
          recognizedAt: start.add(Duration(milliseconds: (elapsed * 1000).round())),
        ));
        buf = '';
        elapsed += chunkGapSeconds;
      }
    }
    if (buf.trim().isNotEmpty) {
      chunks.add(TranscriptChunk(
        text: buf.trim(),
        recognizedAt: start.add(Duration(milliseconds: (elapsed * 1000).round())),
      ));
    }
    return chunks;
  }
}
