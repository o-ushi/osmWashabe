import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../widgets/startup_bottom_bar.dart';

/// スタートアップの「はじめる」の後（設定で有効なとき）に出す、
/// お題の取り込み（Chrome の AI モード）の使い方の画面。
/// 「次回から表示しない」と確定ボタンは画面下に固定する。
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key, required this.onContinue});

  /// [dontShowAgain]がtrueなら、呼び出し側で次回表示オフを保存する。
  final ValueChanged<bool> onContinue;

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final lang = appSettings.language;
    final scene = appAppearance.sceneColor;
    final fg = appAppearance.foregroundOn(scene);
    final body = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: fg.withValues(alpha: 0.75),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: scene,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '使い方'.tr(lang),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '使い方_Chrome見出し'.tr(lang),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('使い方_コピー本文'.tr(lang), style: body),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ColoredBox(
                          color: Colors.white,
                          child: Image.asset(
                            'assets/images/chrome_ai_copy_button.png',
                            width: double.infinity,
                            fit: BoxFit.contain,
                            semanticLabel: '使い方_コピー画像ラベル'.tr(lang),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StartupBottomBar(
                dontShowAgain: _dontShowAgain,
                onDontShowAgainChanged: (v) =>
                    setState(() => _dontShowAgain = v),
                label: 'ホーム画面へ'.tr(lang),
                onPressed: () => widget.onContinue(_dontShowAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
