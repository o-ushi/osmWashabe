import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_strings.dart';
import '../../notifiers/app_settings.dart';
import '../../theme/app_colors.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_expand_card.dart';
import '../privacy/privacy_view.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

class HelpView extends StatefulWidget {
  const HelpView({
    super.key,
    required this.settings,
  });

  final AppSettingsNotifier settings;

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  String? _versionLabel;
  final _scrollController = ScrollController();

  /// 開いている節。
  final Set<String> _openSections = {};

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionLabel = 'バージョン %@ (%@)'.trFmt(
        widget.settings.language,
        [info.version, info.buildNumber],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.language;
    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: WashabeSubpageScaffold(
        title: 'ヘルプ'.tr(lang),
        leading: const SizedBox.shrink(),
        body: ListView(
          controller: _scrollController,
          children: [
            const SizedBox(height: 12),
            Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/image_icon.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'osmWAshabe',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (_versionLabel != null)
                  Text(
                    _versionLabel!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'ヘルプ紹介文'.tr(lang),
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final section in _visibleSections) _card(section, lang),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.black12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: const ValueKey('help-privacy'),
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: Colors.teal,
                  ),
                  title: Text(
                    'プライバシー'.tr(lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.chevronGray,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    fullscreenDismissRoute<void>(
                      builder: (_) => PrivacyView(
                        settings: widget.settings,
                        preferences: widget.settings.preferences,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 上から 練習 → 閲覧 → 困った時 の順。色はまとまりごとに揃える。
  List<_HelpSection> get _visibleSections => [
        const _HelpSection('one', Icons.timer_outlined, Colors.orange, 3),
        const _HelpSection(
            'prep', Icons.hourglass_top_rounded, Colors.orange, 3),
        const _HelpSection(
          'mock',
          Icons.format_list_numbered,
          Colors.orange,
          2,
        ),
        const _HelpSection('read', Icons.volume_up, Colors.orange, 1),
        const _HelpSection('import', Icons.download_outlined, Colors.orange, 2),
        const _HelpSection(
            'score', Icons.assessment_outlined, AppColors.blue, 3),
        const _HelpSection('last', Icons.history_rounded, AppColors.blue, 1),
        // 高品質な声のダウンロードは iPhone の手順。
        if (Platform.isIOS)
          const _HelpSection(
            'voice',
            Icons.record_voice_over_outlined,
            Colors.purple,
            2,
          ),
        const _HelpSection(
            'crash', Icons.bug_report_outlined, Colors.purple, 1),
      ];

  Widget _card(_HelpSection section, String lang) {
    return Padding(
      key: ValueKey('help-section-${section.id}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: WashabeExpandCard(
        title: 'help.${section.id}.title'.tr(lang),
        icon: section.icon,
        accent: section.accent,
        open: _openSections.contains(section.id),
        onToggle: () => setState(() {
          if (!_openSections.remove(section.id)) {
            _openSections.add(section.id);
          }
        }),
        child: WashabeStepList(
          color: section.accent,
          steps: [
            for (var i = 1; i <= section.stepCount; i++)
              'help.${section.id}.$i'.tr(lang),
          ],
        ),
      ),
    );
  }
}

/// ヘルプの 1 節。文言は `help.<id>.title` と `help.<id>.1`〜。
class _HelpSection {
  const _HelpSection(this.id, this.icon, this.accent, this.stepCount);

  final String id;
  final IconData icon;
  final Color accent;
  final int stepCount;
}
