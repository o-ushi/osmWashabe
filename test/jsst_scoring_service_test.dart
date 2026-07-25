import 'package:flutter_test/flutter_test.dart';

import 'package:osm_washabe/models/practice_models.dart';
import 'package:osm_washabe/services/jsst_scoring_service.dart';

TranscriptChunk _chunk(String text, {DateTime? at}) =>
    TranscriptChunk(text: text, recognizedAt: at ?? DateTime(2026, 1, 1));

SpeechSessionContext _session({
  required DateTime started,
  required DateTime ended,
  int allotted = 45,
}) {
  return SpeechSessionContext(
    allottedSeconds: allotted,
    startedAt: started,
    endedAt: ended,
  );
}

void main() {
  group('JsstScoringService.score 待遇表現', () {
    test('尊敬語・謙譲語・丁寧語をすべて使うとvarietyScoreが3になる', () {
      final result = JsstScoringService.score([
        _chunk('お客様がいらっしゃいました。'),
        _chunk('資料を拝見いたします。'),
        _chunk('ありがとうございます。'),
      ]);

      expect(result.keigo.varietyScore, 3);
      final byCategory = {
        for (final c in result.keigo.categories) c.category: c,
      };
      expect(byCategory['sonkeigo']!.matchedExpressions, isNotEmpty);
      expect(byCategory['kenjougo']!.matchedExpressions, isNotEmpty);
      expect(byCategory['teineigo']!.matchedExpressions, isNotEmpty);
    });

    test('丁寧語のみだとvarietyScoreが1になる', () {
      final result = JsstScoringService.score([
        _chunk('今日は天気がいいです。散歩します。'),
      ]);

      expect(result.keigo.varietyScore, 1);
    });

    test('発話が空ならすべてのカテゴリが未検出になる', () {
      final result = JsstScoringService.score([]);
      expect(result.keigo.varietyScore, 0);
      expect(result.fullTranscript, '');
      expect(result.fluency.referenceLevel, 1);
    });
  });

  group('JsstScoringService.score テキストタイプ', () {
    test('従属節接続語があるユニットは複雑判定になる', () {
      final result = JsstScoringService.score([
        _chunk('雨が降ったので、家にいました。'),
        _chunk('散歩しました。'),
      ]);

      expect(result.complexity.totalUnits, 2);
      expect(result.complexity.complexUnitCount, 1);
      expect(result.complexity.complexityRatio, 0.5);
    });

    test('単文のみなら複雑度は0になる', () {
      final result = JsstScoringService.score([
        _chunk('猫が好きです。'),
        _chunk('犬も好きです。'),
      ]);

      expect(result.complexity.complexUnitCount, 0);
      expect(result.complexity.complexityRatio, 0);
    });

    test('1チャンクに複数文が含まれる場合は句読点で分割される', () {
      final result = JsstScoringService.score([
        _chunk('猫が好きです。雨が降ったので散歩はやめました。'),
      ]);

      expect(result.complexity.totalUnits, 2);
      expect(result.complexity.complexUnitCount, 1);
    });

    test('複数STTチャンクは結合してから分割する', () {
      final result = JsstScoringService.score([
        _chunk('猫が好きです。雨が降った'),
        _chunk('ので散歩はやめました。'),
      ]);

      expect(result.complexity.totalUnits, 2);
      expect(result.complexity.complexUnitCount, 1);
    });
  });

  group('JsstScoringService.score 流暢さ', () {
    test('沈黙推定は直前チャンク長を基準に計算される', () {
      final start = DateTime(2026, 1, 1, 12);
      final chunks = [
        _chunk('あ', at: start.add(const Duration(seconds: 1))),
        _chunk(
          'これは非常に長い発話チャンクで、次チャンク基準だと沈黙推定が負になるケース',
          at: start.add(const Duration(seconds: 7)),
        ),
      ];
      final result = JsstScoringService.score(
        chunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );

      // 1文字チャンクは約0.4秒と推定されるため、6秒ギャップなら沈黙は明確に正になる。
      expect(result.fluency.estimatedSilenceSeconds, greaterThan(5.0));
      expect(result.fluency.longPauseCount, 1);
    });

    test('level9相当: 45秒枠をよく使い沈黙が少ない', () {
      final start = DateTime(2026, 1, 1, 12);
      final chunks = [
        _chunk('私はとても疲れているときはまず外に出ます。',
            at: start.add(const Duration(seconds: 2))),
        _chunk('散歩が趣味なので、散歩をします。', at: start.add(const Duration(seconds: 8))),
        _chunk('うちが吉祥寺の近くにありますので、井の頭公園に行って散歩しますね。',
            at: start.add(const Duration(seconds: 16))),
        _chunk('池があったり、緑があったり、季節によって植物が違ったりするので楽しみにしています。',
            at: start.add(const Duration(seconds: 26))),
        _chunk('あと、たまにボートにも乗ります。', at: start.add(const Duration(seconds: 36))),
      ];
      final result = JsstScoringService.score(
        chunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );

      expect(result.fluency.referenceLevel, greaterThanOrEqualTo(4));
      expect(result.fluency.timeUtilization, greaterThan(0.5));
    });

    test('level4相当: 発話量が少なく沈黙が多い', () {
      final start = DateTime(2026, 1, 1, 12);
      final chunks = [
        _chunk('私の週末はね、', at: start.add(const Duration(seconds: 6))),
        _chunk('子供と遊びます。', at: start.add(const Duration(seconds: 14))),
        _chunk('あとは生き物も大好きです。', at: start.add(const Duration(seconds: 28))),
      ];
      final result = JsstScoringService.score(
        chunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );

      expect(result.fluency.referenceLevel, lessThanOrEqualTo(3));
      expect(result.fluency.timeUtilization, lessThan(0.4));
    });

    test('60秒枠でも level9 相当の流暢さを判定できる', () {
      final start = DateTime(2026, 1, 1, 12);
      final chunks = [
        _chunk('私はとても疲れているときはまず外に出ます。',
            at: start.add(const Duration(seconds: 2))),
        _chunk('散歩が趣味なので、散歩をします。', at: start.add(const Duration(seconds: 8))),
        _chunk('うちが吉祥寺の近くにありますので、井の頭公園に行って散歩しますね。',
            at: start.add(const Duration(seconds: 16))),
        _chunk('池があったり、緑があったり、季節によって植物が違ったりするので楽しみにしています。',
            at: start.add(const Duration(seconds: 26))),
        _chunk('あと、たまにボートにも乗ります。', at: start.add(const Duration(seconds: 36))),
        _chunk('友達と一緒に行くことも多いです。', at: start.add(const Duration(seconds: 44))),
        _chunk('季節によって景色が変わるので、いつ行っても楽しめます。',
            at: start.add(const Duration(seconds: 52))),
      ];
      final result = JsstScoringService.score(
        chunks,
        session: _session(
            started: start,
            ended: start.add(const Duration(seconds: 60)),
            allotted: 60),
      );

      expect(result.fluency.allottedSeconds, 60);
      expect(result.fluency.referenceLevel, greaterThanOrEqualTo(3));
      expect(result.fluency.timeUtilization, greaterThan(0.45));
    });
  });

  group('サンプルテキスト（評点校正）', () {
    List<TranscriptChunk> sttLikeChunks(String text, DateTime start) {
      final chunks = <TranscriptChunk>[];
      final parts =
          text.split(RegExp(r'(?<=です|ます|ね|けど|ので|から|した|したい|思います|ません|でした)'));
      var buf = '';
      var elapsed = 2.0;
      for (final part in parts) {
        buf += part;
        if (buf.trim().length >= 25) {
          chunks.add(TranscriptChunk(
            text: buf.trim(),
            recognizedAt:
                start.add(Duration(milliseconds: (elapsed * 1000).round())),
          ));
          buf = '';
          elapsed += 3.5;
        }
      }
      if (buf.trim().isNotEmpty) {
        chunks.add(TranscriptChunk(
          text: buf.trim(),
          recognizedAt:
              start.add(Duration(milliseconds: (elapsed * 1000).round())),
        ));
      }
      return chunks;
    }

    test('level9（ネイティブ）は JSST 7〜 相当', () {
      final text =
          r'''私はとても疲れているときはまず外に出ます。散歩が趣味なので、散歩をします。うちが吉祥寺の近くにありますので、結構井の頭公園に行って散歩しますね。池があったり、大自然の緑があったり、季節によって植物が違ったりするので、結構楽しみにいつもしています。私が行ってみたい国はフランスです。ルーブル博物館があったり、いろんな歴史の建物があったりするのもそうなんですけれども、あと友達がフランスのレオンっていうところに住んでいまして、ぜひワインや食べ物がおいしいということなので、ぜひ一度行ってみて、ガイドさんになってもらいたいと思っています。産業のグローバル化は、日本の会社しかよくわからないんですけれども、でもいいことではないかとは思います。申し訳ございませんが、チェックイン時間まであと1時間ございますので、ちょっとまだお部屋の用意ができておりませんが、ロビーでお待ちする形になってしまうんですけど、少々お待ちいただけないでしょうか。''';

      final start = DateTime(2026, 1, 1, 12);
      final chunks = sttLikeChunks(text, start);
      final sttResult = JsstScoringService.score(
        chunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );
      expect(JsstScoringService.combinedReferenceLevel(sttResult),
          greaterThanOrEqualTo(4));
    });

    test('level4（学習者）は JSST 3〜4 相当', () {
      final text =
          r'''私の週末はね、子供と一緒に遊ぶこととか、買い物をやって、料理を作ってることです。あとは生き物も大好きです。今アメリカにオバマです。大好きです。私の家族はね、私が子供が2人、一番大きな一人は今シンガポールの学校で勉強して、今18歳、そろそろに18歳です。私がね、辛いものは大好きだから、辛いものとあと美味しいもの、できるの場所を選んでます。これはあまりわからないんです。皆さん、おはようございます。私の名前はマです。''';

      final start = DateTime(2026, 1, 1, 12);
      final chunks = sttLikeChunks(text, start);
      // level4 は長い沈黙を挟みながらゆっくり話す想定
      final sparseChunks = <TranscriptChunk>[];
      var t = 5.0;
      for (final c in chunks) {
        sparseChunks.add(TranscriptChunk(
          text: c.text,
          recognizedAt: start.add(Duration(milliseconds: (t * 1000).round())),
        ));
        t += 8.0;
      }
      final sttResult = JsstScoringService.score(
        sparseChunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );
      expect(JsstScoringService.combinedReferenceLevel(sttResult),
          lessThanOrEqualTo(3));
    });

    test('母語話者の実機STT（です/ますなし）でも過小評価しない', () {
      const text =
          '酢スマホのアプリを作り始め、ま最近ていた梅田の1月位iPhone用のたのはあのアンドロイド用のアプリも作るフラットソフトを1つのコードで両方かな馴染みもうもらおうと思ったしたほうがい学びこの調子で、あのいろんなアプリテレビに教師できたらいいかなぁって言うんね';
      final start = DateTime(2026, 1, 1, 12);
      // 実機ログ相当: 20 チャンク前後
      final chunks = sttLikeChunks(text, start);
      final result = JsstScoringService.score(
        chunks,
        session: _session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );
      expect(result.keigo.varietyScore, greaterThanOrEqualTo(1));
      expect(JsstScoringService.combinedReferenceLevel(result),
          greaterThanOrEqualTo(4));
    });
  });
}
