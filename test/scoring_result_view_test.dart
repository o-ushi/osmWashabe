import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:osm_washabe/controllers/practice_controller.dart';
import 'package:osm_washabe/data/topic_repository.dart';
import 'package:osm_washabe/main.dart';
import 'package:osm_washabe/models/practice_models.dart';
import 'package:osm_washabe/services/jsst_scoring_service.dart';
import 'package:osm_washabe/services/speech_recognition_service.dart';
import 'package:osm_washabe/services/timer_alert.dart';
import 'package:osm_washabe/services/topic_speech_reader.dart';
import 'package:osm_washabe/views/practice/scoring_result_view.dart';

ScoringResult _sampleResult({int allottedSeconds = 45}) {
  final start = DateTime(2026, 1, 1, 12);
  final chunks = [
    TranscriptChunk(
      text: '私はとても疲れているときはまず外に出ます。散歩が趣味なので、散歩をします。',
      recognizedAt: start.add(const Duration(seconds: 2)),
    ),
    TranscriptChunk(
      text: 'うちが吉祥寺の近くにありますので、井の頭公園に行って散歩しますね。',
      recognizedAt: start.add(const Duration(seconds: 10)),
    ),
    TranscriptChunk(
      text: '天気がいい日は、公園で一時間くらい歩くこともあります。',
      recognizedAt: start.add(const Duration(seconds: 20)),
    ),
  ];
  return JsstScoringService.score(
    chunks,
    session: SpeechSessionContext(
      allottedSeconds: allottedSeconds,
      startedAt: start,
      endedAt: start.add(Duration(seconds: allottedSeconds)),
    ),
  );
}

PracticeController _controller() {
  return PracticeController(
    settings: appSettings,
    topicRepository: TopicRepository(appPreferences),
    speechReader: TopicSpeechReader(appSettings),
    timerAlert: TimerAlert(appSettings),
    speechRecognition: SpeechRecognitionService(),
    preferences: appPreferences,
  );
}

Future<void> _pumpScoringResult(
  WidgetTester tester, {
  required String lang,
  required ScoringResult result,
  double textScale = 2.0,
}) async {
  appSettings.language = lang;
  final controller = _controller()..scoringResult = result;

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ScoringResultView(
          controller: controller,
          languageCode: lang,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await bootstrap(initializeNotifications: false);
  });

  group('ScoringResultView layout', () {
    for (final lang in ['ja', 'en', 'vi']) {
      testWidgets('$lang: 2x text scale でオーバーフローしない (45s)', (tester) async {
        await _pumpScoringResult(tester, lang: lang, result: _sampleResult());

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en: 2x text scale でオーバーフローしない (60s)', (tester) async {
      await _pumpScoringResult(
        tester,
        lang: 'en',
        result: _sampleResult(allottedSeconds: 60),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
