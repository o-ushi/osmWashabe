import 'package:flutter_test/flutter_test.dart';

import 'package:osm_washabe/models/practice_models.dart';
import 'package:osm_washabe/services/japanese_transcript_validity.dart';
import 'package:osm_washabe/services/jsst_scoring_service.dart';

void main() {
  group('JapaneseTranscriptValidity', () {
    test('通常の日本語発話は eligible', () {
      const text = '私の週末は子供と一緒に遊ぶこととか、買い物をやって、料理を作っていることです。';
      expect(
          JapaneseTranscriptValidity.isEligibleForReferenceLevel(text), isTrue);
    });

    test('ベトナム語ローマ字は ineligible', () {
      const text =
          'Tôi là người Việt Nam và hôm nay tôi muốn nói về việc học tiếng Nhật của tôi vì tôi thích văn hóa Nhật Bản rất nhiều.';
      expect(JapaneseTranscriptValidity.isEligibleForReferenceLevel(text),
          isFalse);
      expect(
        JapaneseTranscriptValidity.analyze(text).reason,
        JapaneseTranscriptIneligibilityReason.tooMuchLatin,
      );
    });

    test('カタカナだらけの幻覚文字起こしは ineligible', () {
      const text =
          'アルファベットカタカナノミノナガイモジレツデヘンドウクワタシノアトサンゴカゲツベトナムニアンタイシテイルノダケドキョウワテンスイダトンネルメイドトユウコトヲマンイチュウアルヨウニハナシタイナトオモッテイル';
      expect(JapaneseTranscriptValidity.isEligibleForReferenceLevel(text),
          isFalse);
    });

    test('短すぎる文字起こしは ineligible', () {
      expect(JapaneseTranscriptValidity.isEligibleForReferenceLevel('こんにちは'),
          isFalse);
    });
  });

  group('JsstScoringService combinedReferenceLevel + 日本語妥当性', () {
    TranscriptChunk chunk(String text, {DateTime? at}) =>
        TranscriptChunk(text: text, recognizedAt: at ?? DateTime(2026, 1, 1));

    SpeechSessionContext session({
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

    List<TranscriptChunk> fluentChunks(String text, DateTime start) {
      final chunks = <TranscriptChunk>[];
      var t = 2.0;
      final parts = text.split('。').where((p) => p.trim().isNotEmpty);
      for (final part in parts) {
        chunks.add(TranscriptChunk(
          text: '$part。',
          recognizedAt: start.add(Duration(milliseconds: (t * 1000).round())),
        ));
        t += 6.0;
      }
      if (chunks.isEmpty) {
        chunks.add(chunk(text, at: start.add(const Duration(seconds: 2))));
      }
      return chunks;
    }

    test('ベトナム語相当の文字起こしでは参考レベルが算出されない', () {
      const text =
          'アルファベットカタカナノミノナガイモジレツデヘンドウクワタシノアトサンゴカゲツベトナムニアンタイシテイルノダケドキョウワテンスイダトンネルメイドトユウコトヲマンイチュウアルヨウニハナシタイナトオモッテイル';
      final start = DateTime(2026, 1, 1, 12);
      final result = JsstScoringService.score(
        fluentChunks(text, start),
        session: session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );

      expect(result.fluency.spokenCharacterCount, greaterThan(40));
      expect(JsstScoringService.isEligibleForReferenceLevel(result), isFalse);
      expect(JsstScoringService.combinedReferenceLevel(result), isNull);
    });

    test('母語話者の実機STT（です/ますなし）でも参考レベルは算出される', () {
      const text =
          '酢スマホのアプリを作り始め、ま最近ていた梅田の1月位iPhone用のたのはあのアンドロイド用のアプリも作るフラットソフトを1つのコードで両方かな馴染みもうもらおうと思ったしたほうがい学びこの調子で、あのいろんなアプリテレビに教師できたらいいかなぁって言うんね';
      final start = DateTime(2026, 1, 1, 12);
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
      final result = JsstScoringService.score(
        chunks,
        session: session(
            started: start, ended: start.add(const Duration(seconds: 45))),
      );

      expect(JsstScoringService.isEligibleForReferenceLevel(result), isTrue);
      expect(JsstScoringService.combinedReferenceLevel(result), isNotNull);
    });
  });
}
