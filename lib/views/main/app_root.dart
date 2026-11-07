import 'package:flutter/material.dart';

import '../../main.dart';
import '../../widgets/edge_swipe_listener.dart';
import '../startup/startup_screen.dart';
import '../startup/usage_screen.dart';
import 'main_view.dart';

/// アプリのルート。スタートアップ → 使い方 → メイン画面の順に切り替える
/// （osm日日是好日と同じ流れ）。
///
/// osm日日是好日の AppRootShell と同じく、メイン画面は push せず重ねて保持し、
/// 表示の切り替えだけで行き来する（メイン画面の状態を保つため）。スタートアップ
/// 画面の設定がオンなら、メイン画面で左端から右へスワイプすると戻る。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, @visibleForTesting this.home});

  /// テスト用の差し替え。省略時は [MainView]。
  final Widget? home;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late bool _showingStartup = appSettings.showStartupScreen;
  bool _showingUsage = false;

  /// 一度メイン画面を出したら、スタートアップに戻っても作り直さない。
  late bool _homeBuilt = !_showingStartup;

  void _finishStartup(bool dontShowAgain) {
    // チェック ON だと使い方も OFF になるので、その前の値で今回の着地を決める。
    final showUsageNow = appSettings.showUsageScreen;
    if (dontShowAgain) appSettings.showStartupScreen = false;
    setState(() {
      _showingStartup = false;
      _showingUsage = showUsageNow;
      _homeBuilt = _homeBuilt || !showUsageNow;
    });
  }

  void _finishUsage(bool dontShowAgain) {
    if (dontShowAgain) appSettings.showUsageScreen = false;
    setState(() {
      _showingUsage = false;
      _homeBuilt = true;
    });
  }

  /// メイン画面で左端から右へスワイプしたとき（osmGradus の仕様 D）。
  /// スタートアップが ON のときだけ、使い方が ON なら使い方、OFF ならスタートアップへ。
  void _onSwipeFromHome() {
    if (!appSettings.showStartupScreen) return;
    setState(() {
      if (appSettings.showUsageScreen) {
        _showingUsage = true;
      } else {
        _showingStartup = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final covered = _showingStartup || _showingUsage;
        return Stack(
          children: [
            if (_homeBuilt)
              Positioned.fill(
                child: Offstage(
                  offstage: covered,
                  child: TickerMode(
                    enabled: !covered,
                    child: EdgeSwipeListener(
                      onSwipe: _onSwipeFromHome,
                      child: widget.home ??
                          MainView(
                            appearance: appAppearance,
                            settings: appSettings,
                            preferences: appPreferences,
                          ),
                    ),
                  ),
                ),
              ),
            if (_showingUsage && !_showingStartup)
              UsageScreen(onContinue: _finishUsage),
            if (_showingStartup) StartupScreen(onContinue: _finishStartup),
          ],
        );
      },
    );
  }
}
