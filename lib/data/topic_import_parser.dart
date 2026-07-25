import 'dart:math';

import '../models/topic.dart';

enum _ImportSection { unknown, life, work, society, situation }

class BatchImportResult {
  BatchImportResult({
    List<String>? life,
    List<String>? work,
    List<String>? society,
    List<SituationPrompt>? situations,
  })  : life = life != null ? [...life] : <String>[],
        work = work != null ? [...work] : <String>[],
        society = society != null ? [...society] : <String>[],
        situations = situations != null ? [...situations] : <SituationPrompt>[];

  factory BatchImportResult.empty() => BatchImportResult._empty();

  // 確実にミュータブルなリストを生成する専用コンストラクタ
  BatchImportResult._empty()
      : life = <String>[],
        work = <String>[],
        society = <String>[],
        situations = <SituationPrompt>[];

  List<String> life;
  List<String> work;
  List<String> society;
  List<SituationPrompt> situations;

  int get totalCount =>
      life.length + work.length + society.length + situations.length;

  bool get isEmpty => totalCount == 0;
}

/// iOS `TopicImportParser` の Dart 移植
class TopicImportParser {
  static const _noiseLinePrefixes = [
    '以下', '出力', '回答', '---', '===', '```', '【出力', '【注意', '【ルール', 'プロンプト',
  ];

  static const _aiClosingTextMarkers = [
    'お題の作成は以上',
    'お題は以上',
    '作成は以上',
    'スピーチの練習をさらに',
    '練習をさらに効果的',
    'いくつかのステップをご提案',
    'ステップをご提案',
    'ご提案できます',
    '以上です。',
    '以上となります',
    'ほかにご',
    '他にご',
    'お役に立て',
    '必要であれば',
  ];

  static const maxItemsPerSection = 10;
  static const defaultSituationConditionText =
      'この状況を想定し、適切な敬語で話してください。';

  static BatchImportResult parseBatchImport(String rawText) {
    // SituationPrompt の List を避け、すべて String リストで収集する
    var life = <String>[];
    var work = <String>[];
    var society = <String>[];
    // situation/condition を交互に格納: [sit0, cond0, sit1, cond1, ...]
    var situationData = <String>[];
    var currentSection = _ImportSection.unknown;
    final sectionCounts = <_ImportSection, int>{};

    final normalized = _normalizeLineEndings(rawText);
    final trimmed = _trimAiClosingSuffix(normalized);

    for (final line in trimmed.split('\n')) {
      final section = _detectSectionHeader(line);
      if (section != null) {
        currentSection = section;
        continue;
      }

      if (_isAiClosingOrFillerLine(line)) {
        if (currentSection == _ImportSection.situation) {
          currentSection = _ImportSection.unknown;
        }
        continue;
      }

      final situation = _parseSituationLine(line);
      if (situation != null &&
          (currentSection == _ImportSection.situation ||
              currentSection == _ImportSection.unknown) &&
          (sectionCounts[_ImportSection.situation] ?? 0) < maxItemsPerSection) {
        situationData.add(situation.situation);
        situationData.add(situation.condition);
        sectionCounts[_ImportSection.situation] =
            (sectionCounts[_ImportSection.situation] ?? 0) + 1;
        currentSection = _ImportSection.situation;
        continue;
      }

      if (!_looksLikeListItem(line)) continue;
      if (_isAiClosingOrFillerLine(line)) continue;

      final topic = _cleanNormalLine(line);
      if (!_isValidNormalTopic(topic)) continue;

      switch (currentSection) {
        case _ImportSection.life:
          if ((sectionCounts[_ImportSection.life] ?? 0) < maxItemsPerSection) {
            life.add(topic);
            sectionCounts[_ImportSection.life] =
                (sectionCounts[_ImportSection.life] ?? 0) + 1;
          }
          break;
        case _ImportSection.work:
          if ((sectionCounts[_ImportSection.work] ?? 0) < maxItemsPerSection) {
            work.add(topic);
            sectionCounts[_ImportSection.work] =
                (sectionCounts[_ImportSection.work] ?? 0) + 1;
          }
          break;
        case _ImportSection.society:
          if ((sectionCounts[_ImportSection.society] ?? 0) <
              maxItemsPerSection) {
            society.add(topic);
            sectionCounts[_ImportSection.society] =
                (sectionCounts[_ImportSection.society] ?? 0) + 1;
          }
          break;
        case _ImportSection.situation:
          if ((sectionCounts[_ImportSection.situation] ?? 0) <
              maxItemsPerSection) {
            situationData.add(topic);
            situationData.add(defaultSituationConditionText);
            sectionCounts[_ImportSection.situation] =
                (sectionCounts[_ImportSection.situation] ?? 0) + 1;
          }
          break;
        case _ImportSection.unknown:
          break;
      }
    }

    if (life.isEmpty && work.isEmpty && situationData.isEmpty) {
      return _parseBatchImportFallback(normalized);
    }

    // List.generate で SituationPrompt を生成（<SituationPrompt>[].add() を回避）
    final sitCount = situationData.length ~/ 2;
    final situations = List<SituationPrompt>.generate(
      sitCount,
      (i) => SituationPrompt(
        situation: situationData[i * 2],
        condition: situationData[i * 2 + 1],
      ),
    );

    return BatchImportResult(
      life: _deduplicateStrings(life),
      work: _deduplicateStrings(work),
      society: _deduplicateStrings(society),
      situations: _deduplicateSituations(situations),
    );
  }

  static List<String> parseNormalTopics(String rawText) {
    return _deduplicateStrings(
      rawText
          .split('\n')
          .map(_cleanNormalLine)
          .where(_isValidNormalTopic)
          .toList(),
    );
  }

  static List<SituationPrompt> parseSituations(String rawText) {
    var data = <String>[];
    final normalized = _trimAiClosingSuffix(_normalizeLineEndings(rawText));

    for (final line in normalized.split('\n')) {
      if (_isAiClosingOrFillerLine(line)) break;
      final prompt = _parseSituationLine(line);
      if (prompt != null) {
        data.add(prompt.situation);
        data.add(prompt.condition);
        if (data.length >= maxItemsPerSection * 2) break;
      }
    }

    if (data.isEmpty) {
      data = _parseSituationBlocksAsData(normalized);
    }

    final count = min(data.length ~/ 2, maxItemsPerSection);
    final built = List<SituationPrompt>.generate(
      count,
      (i) => SituationPrompt(situation: data[i * 2], condition: data[i * 2 + 1]),
    );
    return _deduplicateSituations(built);
  }

  static BatchImportResult _parseBatchImportFallback(String normalized) {
    final parsedSituations = parseSituations(normalized);
    final topics = parseNormalTopics(normalized);

    if (topics.isEmpty) {
      return BatchImportResult(situations: parsedSituations);
    }

    if (parsedSituations.isEmpty && topics.length >= 3) {
      final chunk = max(1, topics.length ~/ 3);
      final remainder = topics.skip(chunk * 2).toList();
      return BatchImportResult(
        life: topics.take(chunk).toList(),
        work: topics.skip(chunk).take(chunk).toList(),
        situations: remainder
            .map(
              (t) => SituationPrompt(
                situation: t,
                condition: defaultSituationConditionText,
              ),
            )
            .toList(),
      );
    }

    return BatchImportResult(
      life: topics,
      situations: parsedSituations,
    );
  }

  static _ImportSection? _detectSectionHeader(String line) {
    var text = line.trim().replaceAll('\uFEFF', '').replaceAll('\t', '');
    if (text.isEmpty) return null;

    final compact = text
        .replaceAll('**', '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('【', '')
        .replaceAll('】', '')
        .replaceAll(' ', '')
        .replaceAll('　', '');

    final looksLikeHeader = text.startsWith('#') ||
        text.startsWith('【') ||
        text.startsWith('[') ||
        text.startsWith('■') ||
        text.startsWith('●') ||
        text.startsWith('◆') ||
        text.contains('分野') ||
        text.contains('10問') ||
        text.contains('10個') ||
        (text.length <= 28 && !text.endsWith('？') && !text.endsWith('?'));

    if (!looksLikeHeader) return null;

    if (compact.contains('シチュエーション') ||
        compact.toLowerCase().contains('situation')) {
      return _ImportSection.situation;
    }
    if (compact.contains('ビジネス') ||
        compact.contains('会社') ||
        compact.contains('仕事') ||
        compact.toLowerCase().contains('business') ||
        compact.toLowerCase().contains('work')) {
      return _ImportSection.work;
    }
    if (compact.contains('日常') ||
        compact.contains('身近') ||
        compact.contains('生活') ||
        compact.toLowerCase().contains('daily') ||
        compact.toLowerCase().contains('life')) {
      return _ImportSection.life;
    }
    if (compact.contains('社会') || compact.toLowerCase().contains('society')) {
      return _ImportSection.society;
    }
    return null;
  }

  static String _cleanNormalLine(String line) {
    var text = line.trim();
    if (text.isEmpty) return '';

    text = text.replaceAll('**', '').replaceAll('__', '');

    const stripPatterns = [
      r'^#+\s*',
      r'^[0-9０-９]+[\.．、\)、]\s*',
      r'^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫]+\s*',
      r'^[-*•・]\s*',
      r'^【[^】]+】\s*',
      r'^\[[^\]]+\]\s*',
      r'^(質問|お題|Q|Topic)[：:\s]+',
      r'^[0-9０-９]+\s+',
    ];

    for (final pattern in stripPatterns) {
      text = text.replaceFirst(RegExp(pattern), '');
    }

    text = _stripWrappingQuotes(text);
    return text.trim();
  }

  static bool _isValidNormalTopic(String line) {
    if (line.length < 8) return false;
    if (line.startsWith('#')) return false;
    if (line == '---' || line == '===') return false;
    if (line.startsWith('```')) return false;
    if (_noiseLinePrefixes.any(line.startsWith)) return false;
    if (_isAiClosingOrFillerLine(line)) return false;
    if (line.contains('状況：') || line.contains('状況:')) return false;
    if (line.contains('条件：') || line.contains('条件:')) return false;
    return true;
  }

  static String _normalizeLineEndings(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static String _trimAiClosingSuffix(String text) {
    final lines = text.split('\n');
    final cutIndex =
        lines.indexWhere((line) => _isAiClosingOrFillerLine(line));
    if (cutIndex < 0) return text;
    return lines.take(cutIndex).join('\n');
  }

  static bool _isAiClosingOrFillerLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    final compact = _cleanNormalLine(trimmed);
    if (_aiClosingTextMarkers
        .any((m) => trimmed.contains(m) || compact.contains(m))) {
      return true;
    }

    final number = _listItemNumber(trimmed);
    if (number != null && number > maxItemsPerSection) return true;
    return false;
  }

  static int? _listItemNumber(String line) {
    final trimmed = line.trim();
    final match = RegExp(r'^([0-9０-９]+)[.．、）)\s]').firstMatch(trimmed);
    if (match == null) return null;
    final digits = match.group(1)!.replaceAllMapped(
          RegExp(r'[０-９]'),
          (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
        );
    return int.tryParse(digits);
  }

  static bool _looksLikeListItem(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^[0-9０-９]+[.．、）)\s]').hasMatch(trimmed)) return true;
    if (RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫]').hasMatch(trimmed)) return true;
    return trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('• ');
  }

  static SituationPrompt? _parseSituationLine(String line) {
    var text = _cleanNormalLine(line);
    if (text.isEmpty) return null;
    text = text.replaceAll('／', '/');

    const patterns = [
      r'状況[：:]\s*(.+?)\s*/\s*条件[：:]\s*(.+)',
      r'状況[：:]\s*(.+?)\s*条件[：:]\s*(.+)',
    ];

    for (final pattern in patterns) {
      final match = RegExp(pattern).firstMatch(text);
      if (match == null || match.groupCount < 2) continue;
      final situation = match.group(1)!.trim();
      final condition = match.group(2)!.trim();
      if (situation.length < 4 || condition.length < 4) continue;
      if (_isAiClosingOrFillerLine(situation)) continue;
      if (_isAiClosingOrFillerLine(condition)) continue;
      return SituationPrompt(situation: situation, condition: condition);
    }
    return null;
  }

  static List<String> _parseSituationBlocksAsData(String text) {
    final data = <String>[];
    for (final block in text.split('\n\n')) {
      var situation = '';
      var condition = '';
      for (final line in block.split('\n')) {
        final cleaned = _cleanNormalLine(line);
        if (cleaned.startsWith('状況')) {
          situation = cleaned.replaceFirst(RegExp(r'^状況[：:]\s*'), '');
        } else if (cleaned.startsWith('条件')) {
          condition = cleaned.replaceFirst(RegExp(r'^条件[：:]\s*'), '');
        }
      }
      if (situation.length >= 4 &&
          condition.length >= 4 &&
          !_isAiClosingOrFillerLine(situation) &&
          !_isAiClosingOrFillerLine(condition)) {
        data.add(situation);
        data.add(condition);
        if (data.length >= maxItemsPerSection * 2) break;
      }
    }
    return data;
  }

  static List<String> _deduplicateStrings(List<String> items) {
    final seen = <String>{};
    final unique = <String>[];
    for (final item in items) {
      if (seen.add(item)) unique.add(item);
    }
    return unique;
  }

  static List<SituationPrompt> _deduplicateSituations(
    List<SituationPrompt> items,
  ) {
    final seen = <String>{};
    return items.where((item) => seen.add(item.id)).toList();
  }

  static String _stripWrappingQuotes(String text) {
    var value = text;
    const pairs = [
      ('"', '"'),
      ('「', '」'),
      ('『', '』'),
      ('“', '”'),
      ('‘', '’'),
    ];
    for (final (open, close) in pairs) {
      if (value.startsWith(open) &&
          value.endsWith(close) &&
          value.length > open.length + close.length) {
        value = value.substring(open.length, value.length - close.length);
      }
    }
    return value;
  }

  /// iOS `looksLikeAIImport`
  static bool looksLikeAiImport(String text) {
    if (text.contains('【日常の身近な話題】') || text.contains('【ビジネスシーン】')) {
      return true;
    }
    if (text.contains('[日常の身近な話題]') || text.contains('[ビジネスシーン]')) {
      return true;
    }
    if (text.contains('日常の身近な話題') && text.contains('ビジネスシーン')) {
      return true;
    }
    if (text.contains('【生活】') ||
        text.contains('【会社】') ||
        text.contains('【社会】')) {
      return true;
    }
    if (text.contains('【シチュエーション】') || text.contains('[シチュエーション]')) {
      return true;
    }
    if (text.contains('状況：') || text.contains('状況:')) return true;

    final numberedLines = text
        .split('\n')
        .where(
          (line) => RegExp(r'^[0-9０-９]+[\.．、\)]').hasMatch(line.trim()),
        )
        .length;
    if (numberedLines >= 3 && text.length >= 80) return true;

    final questionMarks = '?'.allMatches(text).length + '？'.allMatches(text).length;
    return questionMarks >= 3 && text.length >= 80;
  }
}
