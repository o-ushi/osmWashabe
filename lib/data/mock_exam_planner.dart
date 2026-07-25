import 'dart:math';

import '../models/practice_models.dart';
import '../models/topic.dart';
import 'topic_repository.dart';

/// iOS `MockExamPlanner` と同じ10問構成
abstract final class MockExamPlanner {
  static const int totalCount = 10;
  static const int normalCount = 9;

  static List<MockExamStep> buildSteps(TopicRepository repository) {
    final topics = _uniqueTopics(repository, normalCount);
    final situations = _uniqueSituations(repository, 1);
    final steps = <MockExamStep>[];

    for (final topic in topics.take(7)) {
      steps.add(MockExamStep(kind: MockExamQuestionKind.normal45, topic: topic));
    }

    final topic8 = topics.length > 7 ? topics[7] : (topics.isNotEmpty ? topics.last : '');
    steps.add(MockExamStep(kind: MockExamQuestionKind.normal60, topic: topic8));

    final topic9 = topics.length > 8 ? topics[8] : (topics.isNotEmpty ? topics.last : '');
    steps.add(
      MockExamStep(kind: MockExamQuestionKind.normal15plus60, topic: topic9),
    );

    steps.add(
      MockExamStep(
        kind: MockExamQuestionKind.situationKeigo,
        situation: situations.isNotEmpty ? situations.first : null,
      ),
    );

    return steps;
  }

  static List<String> _uniqueTopics(TopicRepository repository, int count) {
    final pool = List<String>.from(
      repository.allTopics(TopicCategory.random),
    )..shuffle(Random());
    if (pool.length >= count) {
      return pool.take(count).toList();
    }
    final result = List<String>.from(pool);
    while (result.length < count && pool.isNotEmpty) {
      result.add(pool[Random().nextInt(pool.length)]);
    }
    return result;
  }

  static List<SituationPrompt> _uniqueSituations(
    TopicRepository repository,
    int count,
  ) {
    final pool = List<SituationPrompt>.from(repository.allSituations())
      ..shuffle(Random());
    if (pool.length >= count) {
      return pool.take(count).toList();
    }
    final result = List<SituationPrompt>.from(pool);
    while (result.length < count && pool.isNotEmpty) {
      result.add(pool[Random().nextInt(pool.length)]);
    }
    return result;
  }
}
