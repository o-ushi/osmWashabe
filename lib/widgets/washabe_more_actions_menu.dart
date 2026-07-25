import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// iOS `WashabeMoreActionsMenuView` 相当
class WashabeMoreActionsMenu extends StatelessWidget {
  const WashabeMoreActionsMenu({
    super.key,
    required this.languageCode,
    required this.onTopicImport,
    required this.onSettings,
    required this.onHelp,
  });

  final String languageCode;
  final VoidCallback onTopicImport;
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  static const _iconFg = Color(0xFF141414);
  static const _iconBg = Color(0xFFE0E0E0);
  static const _iconBorder = Color(0xFF8C8C8C);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuButton(
              icon: Icons.download_outlined,
              label: 'お題の取り込み'.tr(languageCode),
              onTap: onTopicImport,
            ),
            const SizedBox(width: 16),
            _menuButton(
              icon: Icons.settings_outlined,
              label: '設定'.tr(languageCode),
              onTap: onSettings,
            ),
            const SizedBox(width: 16),
            _menuButton(
              icon: Icons.help_outline,
              label: 'ヘルプ'.tr(languageCode),
              onTap: onHelp,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _iconBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _iconBorder, width: 1.5),
          ),
          child: Icon(icon, color: _iconFg, size: 26),
        ),
      ),
    );
  }
}
