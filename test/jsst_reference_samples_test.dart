import 'package:flutter_test/flutter_test.dart';

import 'package:osm_washabe/data/jsst_reference_samples.dart';

void main() {
  group('JsstReferenceSamples', () {
    for (final allotted in [45, 60]) {
      test('$allotted秒枠: level4 は JSST 3〜4 相当', () {
        final benchmarks = JsstReferenceSamples.forAllottedSeconds(allotted);
        expect(benchmarks.allottedSeconds, allotted);
        expect(benchmarks.level4.combinedLevel, lessThanOrEqualTo(3));
        expect(benchmarks.level4.teineigoHitCount, greaterThan(0));
        expect(benchmarks.level4.excerpt, isNotEmpty);
        expect(benchmarks.level4.result.fluency.allottedSeconds, allotted);
      });

      test('$allotted秒枠: level9 は JSST 7〜 相当', () {
        final benchmarks = JsstReferenceSamples.forAllottedSeconds(allotted);
        expect(benchmarks.level9.combinedLevel, greaterThanOrEqualTo(4));
        expect(benchmarks.level9.teineigoHitCount, greaterThan(0));
        expect(benchmarks.level9.result.fluency.allottedSeconds, allotted);
      });

      test('$allotted秒枠: level9 は level4 より発話量・利用率が高い', () {
        final benchmarks = JsstReferenceSamples.forAllottedSeconds(allotted);
        final l4 = benchmarks.level4.result.fluency;
        final l9 = benchmarks.level9.result.fluency;
        expect(l9.charactersPerAllottedMinute, greaterThan(l4.charactersPerAllottedMinute));
        expect(l9.timeUtilization, greaterThan(l4.timeUtilization));
      });
    }

    test('normalizeAllottedSeconds は 60 のみ 60、それ以外は 45', () {
      expect(JsstReferenceSamples.normalizeAllottedSeconds(60), 60);
      expect(JsstReferenceSamples.normalizeAllottedSeconds(45), 45);
      expect(JsstReferenceSamples.normalizeAllottedSeconds(15), 45);
      expect(JsstReferenceSamples.normalizeAllottedSeconds(null), 45);
    });

    test('levelLabel は既知レベルをラベル化する', () {
      expect(JsstReferenceSamples.levelLabel(4, 'ja'), 'JSST 7〜');
      expect(JsstReferenceSamples.levelLabel(4, 'en'), 'JSST 7+');
      expect(JsstReferenceSamples.levelLabel(null, 'ja'), '—');
    });
  });
}
