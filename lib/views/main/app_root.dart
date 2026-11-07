import 'package:flutter/material.dart';

import '../../main.dart';
import '../startup/startup_screen.dart';
import '../startup/usage_screen.dart';
import 'main_view.dart';

/// アプリのルート。スタートアップ → 使い方 → メイン画面の順に切り替える
/// （osm日日是好日と同じ流れ）。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late bool _showingStartup = appSettings.showStartupScreen;
  bool _showingUsage = false;

  void _finishStartup(bool dontShowAgain) {
    // チェック ON だと使い方も OFF になるので、その前の値で今回の着地を決める。
    final showUsageNow = appSettings.showUsageScreen;
    if (dontShowAgain) appSettings.showStartupScreen = false;
    setState(() {
      _showingStartup = false;
      _showingUsage = showUsageNow;
    });
  }

  void _finishUsage(bool dontShowAgain) {
    if (dontShowAgain) appSettings.showUsageScreen = false;
    setState(() => _showingUsage = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        if (_showingStartup) return StartupScreen(onContinue: _finishStartup);
        if (_showingUsage) return UsageScreen(onContinue: _finishUsage);
        return MainView(
          appearance: appAppearance,
          settings: appSettings,
          preferences: appPreferences,
        );
      },
    );
  }
}
