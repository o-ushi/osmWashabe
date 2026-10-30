import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../notifiers/app_settings.dart';
import '../../theme/app_colors.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

class HelpView extends StatefulWidget {
  const HelpView({
    super.key,
    required this.settings,
  });

  final AppSettingsNotifier settings;

  /// Google スライド操作マニュアル（言語別・閲覧用 preview）。
  /// 共有は「リンクを知っている全員」。編集 URL ではなく preview を開く。
  /// 英語・ベトナム語は同じファイルを上書き更新する前提（ID は固定）。
  static const userManualPresentationIdJa =
      '1z40A2lvJK4UUnBNcvAC5vGWfLwaa9ZmCjFMZlPQ-h_0';
  static const userManualPresentationIdEn =
      '1F0O1UzMktD5VMwhOdNF1KoOG7Fl1lFMz1EEpgxgVapM';
  static const userManualPresentationIdVi =
      '114UigCR54j4tQdUayjALDJPrCLAoOGbTXMDlv_UtEDU';

  static String userManualUrlFor(String language) {
    final id = switch (language) {
      'en' => userManualPresentationIdEn,
      'ja' => userManualPresentationIdJa,
      _ => userManualPresentationIdVi,
    };
    return 'https://docs.google.com/presentation/d/$id/preview';
  }

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  String? _versionLabel;
  final _scrollController = ScrollController();

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
                  'osmWashabe',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _HelpManualLink(
                lang: lang,
                onTap: () => launchUrl(
                  Uri.parse(HelpView.userManualUrlFor(lang)),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            _section('基本操作'.tr(lang), [
              _HelpRow(
                icon: CupertinoIcons.chat_bubble_text_fill,
                color: Colors.blue,
                titleKey: 'help.normal.title',
                bodyKey: 'help.normal.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: CupertinoIcons.person_2_fill,
                color: Colors.green,
                titleKey: 'help.situation.title',
                bodyKey: 'help.situation.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: CupertinoIcons.list_number,
                color: Colors.indigo,
                titleKey: 'help.mock.title',
                bodyKey: 'help.mock.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: CupertinoIcons.timer,
                color: Colors.orange,
                titleKey: 'help.timer.title',
                bodyKey: 'help.timer.body',
                languageCode: lang,
              ),
            ]),
            _section('help.scoring.section'.tr(lang), [
              _HelpRow(
                icon: Icons.assessment,
                color: AppColors.green,
                titleKey: 'help.scoring.title',
                bodyKey: 'help.scoring.body',
                languageCode: lang,
              ),
            ]),
            _section('読み上げとお題'.tr(lang), [
              _HelpRow(
                icon: CupertinoIcons.speaker_2_fill,
                color: Colors.purple,
                titleKey: 'help.speech.title',
                bodyKey: 'help.speech.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: CupertinoIcons.square_arrow_down,
                color: Colors.indigo,
                titleKey: 'help.import.title',
                bodyKey: 'help.import.body',
                languageCode: lang,
              ),
            ]),
            _section('各種設定'.tr(lang), [
              _HelpRow(
                icon: CupertinoIcons.globe,
                color: Colors.blue,
                titleKey: 'help.settings.language.title',
                bodyKey: 'help.settings.language.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: CupertinoIcons.bell,
                color: Colors.orange,
                titleKey: 'help.settings.timer.title',
                bodyKey: 'help.settings.timer.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: Icons.history,
                color: Colors.teal,
                titleKey: 'help.settings.history.title',
                bodyKey: 'help.settings.history.body',
                languageCode: lang,
              ),
              _HelpRow(
                icon: Icons.privacy_tip_outlined,
                color: Colors.blueGrey,
                titleKey: 'help.privacy.title',
                bodyKey: 'help.privacy.body',
                languageCode: lang,
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _HelpManualLink extends StatelessWidget {
  const _HelpManualLink({
    required this.lang,
    required this.onTap,
  });

  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('help_user_manual'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu_book_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '操作マニュアル'.tr(lang),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '図解で画面ごとの使い方を見る'.tr(lang),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.color,
    required this.titleKey,
    required this.bodyKey,
    required this.languageCode,
  });

  final IconData icon;
  final Color color;
  final String titleKey;
  final String bodyKey;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titleKey.tr(languageCode),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bodyKey.tr(languageCode),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}
