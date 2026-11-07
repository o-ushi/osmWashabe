import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../main.dart';

/// スタートアップ・使い方画面の下端に固定する「次回から表示しない」と確定ボタン。
/// 構成は osm日日是好日と同じ。短い画面では上下を詰める。
class StartupBottomBar extends StatelessWidget {
  const StartupBottomBar({
    super.key,
    required this.dontShowAgain,
    required this.onDontShowAgainChanged,
    required this.label,
    required this.onPressed,
  });

  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowAgainChanged;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height <= 700;
    final fg = appAppearance.foregroundOn(appAppearance.sceneColor);
    final accent = appAppearance.accentColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, short ? 4 : 8, 24, short ? 12 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onDontShowAgainChanged(!dontShowAgain),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: dontShowAgain,
                      onChanged: (v) => onDontShowAgainChanged(v ?? false),
                      side: BorderSide(color: fg, width: 1.5),
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? accent
                            : Colors.transparent,
                      ),
                      checkColor:
                          appAppearance.foregroundOn(appAppearance.accentColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '次回から表示しない'.tr(appSettings.language),
                      style: TextStyle(fontSize: 15, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor:
                    appAppearance.foregroundOn(appAppearance.accentColor),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
