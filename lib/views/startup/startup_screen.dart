import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../widgets/startup_bottom_bar.dart';

/// 起動時（設定で有効なとき）の案内画面。osm日日是好日と同じ構成で、
/// 「次回から表示しない」と「はじめる」は画面下に固定する。
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.onContinue});

  /// [dontShowAgain]がtrueなら、呼び出し側で次回表示オフを保存する。
  final ValueChanged<bool> onContinue;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final lang = appSettings.language;
    final scene = appAppearance.sceneColor;
    final fg = appAppearance.foregroundOn(scene);
    final muted = fg.withValues(alpha: 0.75);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeData.estimateBrightnessForColor(scene) == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: scene,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 12, 0),
                  child: const _LanguageFlagButton(),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/app_icon.png',
                              width: 140,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 28),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'osmWAshabe',
                              maxLines: 1,
                              softWrap: false,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: fg,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ヘルプ紹介文'.tr(lang),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              StartupBottomBar(
                dontShowAgain: _dontShowAgain,
                onDontShowAgainChanged: (v) =>
                    setState(() => _dontShowAgain = v),
                label: 'はじめる'.tr(lang),
                onPressed: () => widget.onContinue(_dontShowAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageFlagButton extends StatelessWidget {
  const _LanguageFlagButton();

  static const _languages = [
    ('en', 'English', '🇺🇸'),
    ('ja', '日本語', '🇯🇵'),
    ('vi', 'Tiếng Việt', '🇻🇳'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _languages.firstWhere(
      (l) => l.$1 == appSettings.language,
      orElse: () => _languages.last,
    );
    return PopupMenuButton<String>(
      tooltip: '言語'.tr(appSettings.language),
      onSelected: (code) => appSettings.language = code,
      itemBuilder: (_) => [
        for (final l in _languages)
          PopupMenuItem(value: l.$1, child: Text('${l.$3} ${l.$2}')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(current.$3, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
