import 'dart:convert';

import '../models/topic.dart';
import '../services/app_preferences.dart';
import 'jsst_topic_bank.dart';
import 'topic_import_parser.dart';

/// お題プールの読み取り・インポート永続化
class TopicRepository {
  TopicRepository(this._prefs);

  final AppPreferences _prefs;

  List<String> allTopics(TopicCategory category) {
    final imported = switch (category) {
      TopicCategory.daily => _decodeTopics(_prefs.importedLifeJson),
      TopicCategory.business => _decodeTopics(_prefs.importedWorkJson),
      TopicCategory.situation =>
        _decodeSituations(_prefs.importedSituationsJson)
            .map((s) => s.readableText)
            .toList(),
      TopicCategory.random =>
        _decodeTopics(_prefs.importedLifeJson) +
            _decodeTopics(_prefs.importedWorkJson) +
            _decodeTopics(_prefs.importedSocietyJson),
    };
    final builtIn =
        _prefs.useBuiltInTopics ? JsstTopicBank.builtInTopics(category) : [];
    return _deduplicateTopics([...builtIn, ...imported]);
  }

  /// 15+60秒モードのランダムプール（daily・business・supplement・situationを混在）
  List<String> allTopicsForPrep15Random() {
    final imported = _decodeTopics(_prefs.importedLifeJson) +
        _decodeTopics(_prefs.importedWorkJson) +
        _decodeTopics(_prefs.importedSocietyJson) +
        _decodeSituations(_prefs.importedSituationsJson)
            .map((s) => s.readableText)
            .toList();
    final builtIn = _prefs.useBuiltInTopics
        ? [
            ...JsstTopicBank.dailyTopics,
            ...JsstTopicBank.businessTopics,
            ...JsstTopicBank.supplementTopics,
            ...JsstTopicBank.situationPrompts.map((s) => s.readableText),
          ]
        : <String>[];
    return _deduplicateTopics([...builtIn, ...imported]);
  }

  List<SituationPrompt> allSituations() {
    final imported = _decodeSituations(_prefs.importedSituationsJson);
    final builtIn =
        _prefs.useBuiltInTopics ? JsstTopicBank.situationPrompts : [];
    return _deduplicateSituations([...builtIn, ...imported]);
  }

  ImportedSummary get importedSummary {
    final life = _decodeTopics(_prefs.importedLifeJson);
    final work = _decodeTopics(_prefs.importedWorkJson);
    final society = _decodeTopics(_prefs.importedSocietyJson);
    final situations = _decodeSituations(_prefs.importedSituationsJson);
    return ImportedSummary(
      dailyCount: life.length + society.length,
      businessCount: work.length,
      situationCount: situations.length,
    );
  }

  ImportMergeResult mergeImportedBatch(BatchImportResult batch) {
    final dailyAdded = _mergeTopics(batch.life, _TopicBucket.life);
    final businessAdded = _mergeTopics(batch.work, _TopicBucket.work);
    final societyAdded = _mergeTopics(batch.society, _TopicBucket.society);
    final situationAdded = _mergeSituations(batch.situations);
    return ImportMergeResult(
      dailyAdded: dailyAdded + societyAdded,
      businessAdded: businessAdded,
      situationAdded: situationAdded,
    );
  }

  void clearImportedTopics() {
    _prefs.importedLifeJson = '[]';
    _prefs.importedWorkJson = '[]';
    _prefs.importedSocietyJson = '[]';
    _prefs.importedSituationsJson = '[]';
  }

  int _mergeTopics(List<String> parsed, _TopicBucket bucket) {
    if (parsed.isEmpty) return 0;
    final existingJson = _jsonFor(bucket);
    final existing = _decodeTopics(existingJson).toSet();
    final newItems = parsed.where((t) => !existing.contains(t)).toList();
    if (newItems.isEmpty) return 0;
    final merged = [..._decodeTopics(existingJson), ...newItems];
    _setJsonFor(bucket, jsonEncode(merged));
    return newItems.length;
  }

  int _mergeSituations(List<SituationPrompt> parsed) {
    if (parsed.isEmpty) return 0;
    final existing = _decodeSituations(_prefs.importedSituationsJson)
        .map((s) => s.id)
        .toSet();
    final newItems = parsed.where((s) => !existing.contains(s.id)).toList();
    if (newItems.isEmpty) return 0;
    final merged = [
      ..._decodeSituations(_prefs.importedSituationsJson),
      ...newItems,
    ];
    _prefs.importedSituationsJson = jsonEncode(
      merged.map((s) => s.toJson()).toList(),
    );
    return newItems.length;
  }

  String _jsonFor(_TopicBucket bucket) => switch (bucket) {
        _TopicBucket.life => _prefs.importedLifeJson,
        _TopicBucket.work => _prefs.importedWorkJson,
        _TopicBucket.society => _prefs.importedSocietyJson,
      };

  void _setJsonFor(_TopicBucket bucket, String json) {
    switch (bucket) {
      case _TopicBucket.life:
        _prefs.importedLifeJson = json;
      case _TopicBucket.work:
        _prefs.importedWorkJson = json;
      case _TopicBucket.society:
        _prefs.importedSocietyJson = json;
    }
  }

  List<String> _decodeTopics(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  List<SituationPrompt> _decodeSituations(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => SituationPrompt.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  List<String> _deduplicateTopics(List<String> items) {
    final seen = <String>{};
    final unique = <String>[];
    for (final item in items) {
      if (seen.add(item)) unique.add(item);
    }
    return unique;
  }

  List<SituationPrompt> _deduplicateSituations(List<SituationPrompt> items) {
    final seen = <String>{};
    final unique = <SituationPrompt>[];
    for (final item in items) {
      if (seen.add(item.id)) unique.add(item);
    }
    return unique;
  }
}

enum _TopicBucket { life, work, society }

class ImportedSummary {
  const ImportedSummary({
    required this.dailyCount,
    required this.businessCount,
    required this.situationCount,
  });

  final int dailyCount;
  final int businessCount;
  final int situationCount;
}

class ImportMergeResult {
  const ImportMergeResult({
    required this.dailyAdded,
    required this.businessAdded,
    required this.situationAdded,
  });

  final int dailyAdded;
  final int businessAdded;
  final int situationAdded;

  int get totalAdded => dailyAdded + businessAdded + situationAdded;
}
