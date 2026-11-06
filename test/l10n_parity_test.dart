import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:osm_washabe/l10n/app_strings.dart';

Set<String> _extractKeys(String locale) {
  final content = File('lib/l10n/app_strings.dart').readAsStringSync();
  final start = content.indexOf('static const _$locale = <String, String>{');
  expect(start, greaterThan(-1), reason: '_$locale block not found');
  final end = content.indexOf('\n  };', start);
  final block = content.substring(start, end);
  final keys = <String>{};
  for (final match in RegExp(r"\n    '([^']+)':").allMatches(block)) {
    keys.add(match.group(1)!);
  }
  return keys;
}

void main() {
  test('ja / en / vi のキー集合が一致する', () {
    final ja = _extractKeys('ja');
    final en = _extractKeys('en');
    final vi = _extractKeys('vi');

    expect(ja.length, en.length);
    expect(ja.length, vi.length);
    expect(ja.difference(en), isEmpty);
    expect(ja.difference(vi), isEmpty);
  });

  test('採点関連キーは en / vi とも翻訳されている', () {
    const scoringKeys = [
      '採点ON_ヒント',
      '採点OFF_ヒント',
      'help.score.title',
      'help.score.1',
      'JSST 1〜2',
      '参考サンプル_Level4',
      '枠あたりの発話量',
      '3軸の参考値。公式採点とは大きく異なる場合があります。',
    ];

    for (final key in scoringKeys) {
      expect(key.tr('ja'), isNotEmpty);
      expect(key.tr('en'), isNot(equals(key)));
      expect(key.tr('vi'), isNot(equals(key)));
    }
  });
}
