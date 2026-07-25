import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../notifiers/app_settings.dart';
import '../../services/app_preferences.dart';
import '../../services/privacy_service.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

Future<bool> showSpeechConsentDialog(
  BuildContext context, {
  required String languageCode,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('プライバシー_音声認識タイトル'.tr(languageCode)),
      content: SingleChildScrollView(
        child: Text('プライバシー_音声認識同意本文'.tr(languageCode)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('プライバシー_同意しない'.tr(languageCode)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('プライバシー_同意する'.tr(languageCode)),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await PrivacyService.grantSpeechConsent();
    return true;
  }
  await PrivacyService.revokeSpeechConsent();
  return false;
}

class PrivacyView extends StatefulWidget {
  const PrivacyView({
    super.key,
    required this.settings,
    required this.preferences,
  });

  final AppSettingsNotifier settings;
  final AppPreferences preferences;

  @override
  State<PrivacyView> createState() => _PrivacyViewState();
}

class _PrivacyViewState extends State<PrivacyView> {
  bool _speechConsent = false;
  bool _deleting = false;

  String get _lang => widget.settings.language;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    final value = await PrivacyService.hasCurrentSpeechConsent();
    if (mounted) setState(() => _speechConsent = value);
  }

  Future<void> _setConsent(bool value) async {
    if (value) {
      final accepted = await showSpeechConsentDialog(
        context,
        languageCode: _lang,
      );
      if (mounted) setState(() => _speechConsent = accepted);
      return;
    }
    await PrivacyService.revokeSpeechConsent();
    widget.settings.scoringEnabled = false;
    if (mounted) setState(() => _speechConsent = false);
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('全データを削除'.tr(_lang)),
        content: Text('プライバシー_全データ削除確認'.tr(_lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('キャンセル'.tr(_lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '削除'.tr(_lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    await PrivacyService.deleteAllData(widget.preferences);
    widget.settings.refreshAfterDataDeletion();
    if (!mounted) return;
    setState(() {
      _speechConsent = false;
      _deleting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('プライバシー_全データ削除完了'.tr(_lang))),
    );
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return WashabeSubpageScaffold(
      title: 'プライバシー'.tr(_lang),
      leading: const SizedBox.shrink(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('プライバシー_音声認識タイトル'.tr(_lang)),
            subtitle: Text('プライバシー_音声認識設定説明'.tr(_lang)),
            value: _speechConsent,
            onChanged: _setConsent,
          ),
          const Divider(),
          _section(
            'プライバシー_録音セクション見出し',
            'プライバシー_録音セクション本文',
          ),
          _section(
            'プライバシー_診断ログセクション見出し',
            'プライバシー_診断ログセクション本文',
          ),
          _section(
            'プライバシー_設定お題セクション見出し',
            'プライバシー_設定お題セクション本文',
          ),
          _section(
            'プライバシー_GoogleAIセクション見出し',
            'プライバシー_GoogleAIセクション本文',
          ),
          _section(
            'プライバシー_保持削除セクション見出し',
            'プライバシー_保持削除セクション本文',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Appleプライバシーポリシー'.tr(_lang)),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open('https://www.apple.com/legal/privacy/'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Googleプライバシーポリシー'.tr(_lang)),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open('https://policies.google.com/privacy'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _deleting ? null : _deleteAll,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              _deleting ? '削除中…'.tr(_lang) : '全データを削除'.tr(_lang),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String titleKey, String bodyKey) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleKey.tr(_lang),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              bodyKey.tr(_lang),
              style: const TextStyle(height: 1.45, color: Colors.black54),
            ),
          ],
        ),
      );
}
