import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'notifiers/app_appearance.dart';
import 'notifiers/app_settings.dart';
import 'services/android_vosk_warmup.dart';
import 'services/android_ringtone_service.dart';
import 'services/app_preferences.dart';
import 'services/crash_log_service.dart';
import 'services/privacy_service.dart';
import 'services/timer_completion_sound_catalog.dart';
import 'services/timer_notification_scheduler.dart';
import 'views/main/main_view.dart';

final AppSettingsNotifier appSettings = AppSettingsNotifier();
const AppAppearance appAppearance = AppAppearance();
late final AppPreferences appPreferences;

Future<void> bootstrap({bool initializeNotifications = true}) async {
  WidgetsFlutterBinding.ensureInitialized();
  appPreferences = await AppPreferences.load();
  appSettings.bind(appPreferences);
  if (!await PrivacyService.hasCurrentSpeechConsent()) {
    appSettings.scoringEnabled = false;
  }
  appSettings.completionSound =
      TimerCompletionSoundCatalog.normalizedStoredValue(
    appSettings.completionSound,
  );
  // Android: iOSのサウンドIDが残っていたら端末の通知音先頭をデフォルトにする
  if (Platform.isAndroid &&
      !appSettings.completionSound.startsWith('android_ringtone:')) {
    final ringtones = await AndroidRingtoneService.getRingtones();
    if (ringtones.isNotEmpty) {
      appSettings.completionSound = ringtones.first.storedValue;
    }
  }

  if (initializeNotifications) {
    await TimerNotificationScheduler.instance.initialize(
      languageCode: appSettings.language,
    );
  }

  AndroidVoskWarmup.scheduleIfNeeded(
      scoringEnabled: appSettings.scoringEnabled);
}

Future<void> main() async {
  await bootstrap();
  await CrashLogService.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await WakelockPlus.enable();
  runZonedGuarded(
    () => runApp(const OsmWashabeApp()),
    (error, stack) => unawaited(CrashLogService.logCrash(error, stack)),
  );
}

class OsmWashabeApp extends StatefulWidget {
  const OsmWashabeApp({super.key});

  @override
  State<OsmWashabeApp> createState() => _OsmWashabeAppState();
}

class _OsmWashabeAppState extends State<OsmWashabeApp> {
  @override
  void initState() {
    super.initState();
    appSettings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    appSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    AndroidVoskWarmup.scheduleIfNeeded(
      scoringEnabled: appSettings.scoringEnabled,
    );
    setState(() {});
  }

  Locale get _locale => switch (appSettings.language) {
        'en' => const Locale('en'),
        'ja' => const Locale('ja'),
        _ => const Locale('vi'),
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'osmWAshabe',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppAppearance.brandBlue,
        ),
        useMaterial3: true,
      ),
      home: MainView(
        appearance: appAppearance,
        settings: appSettings,
        preferences: appPreferences,
      ),
    );
  }
}
