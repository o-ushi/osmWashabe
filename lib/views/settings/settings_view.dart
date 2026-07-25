import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../notifiers/app_settings.dart';
import '../../services/crash_log_service.dart';
import '../../services/japanese_speech_voice_selector.dart';
import '../../services/jsst_calibration_service.dart';
import '../../services/native_tts_platform.dart';
import '../../services/timer_alert.dart';
import '../../services/timer_completion_sound_catalog.dart';
import '../../services/topic_speech_reader.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';
import '../privacy/privacy_view.dart';
import 'timer_sound_picker_view.dart';
import 'speech_recognition_debug_log_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.settings,
    required this.timerAlert,
    required this.speechReader,
    required this.onResetScoringHistory,
    required this.hasScoringHistory,
  });

  final AppSettingsNotifier settings;
  final TimerAlert timerAlert;
  final TopicSpeechReader speechReader;
  final VoidCallback onResetScoringHistory;
  final bool Function() hasScoringHistory;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _devTapCount = 0;
  final _scrollController = ScrollController();
  late bool _hasHistory;
  bool _isSendingLog = false;

  @override
  void initState() {
    super.initState();
    _hasHistory = widget.hasScoringHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showLogSendDialog(String lang) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('クラッシュログを送信'.tr(lang)),
        content: Text('ログ送信_内容と選択'.tr(lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('キャンセル'.tr(lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'email'),
            child: Text('ログ送信_メール'.tr(lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'webhook'),
            child: Text('ログ送信_Webhook'.tr(lang)),
          ),
        ],
      ),
    );
    if (method == null || !mounted) return;
    setState(() => _isSendingLog = true);
    final result = method == 'email'
        ? await CrashLogService.shareViaEmail(languageCode: lang)
        : await CrashLogService.shareViaWebhook(languageCode: lang);
    if (mounted) {
      setState(() => _isSendingLog = false);
      final message = switch (result) {
        CrashLogShareResult.sent => 'ログを送信しました'.tr(lang),
        CrashLogShareResult.emailComposerOpened => 'ログメール作成画面を開きました'.tr(lang),
        CrashLogShareResult.failed => '送信に失敗しました'.tr(lang),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearLog(String lang) async {
    await CrashLogService.clearLog();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ログをクリア'.tr(lang)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static const _languages = [
    ('en', 'English', '🇺🇸'),
    ('ja', '日本語', '🇯🇵'),
    ('vi', 'Tiếng Việt', '🇻🇳'),
  ];

  AppSettingsNotifier get settings => widget.settings;
  TimerAlert get timerAlert => widget.timerAlert;
  TopicSpeechReader get speechReader => widget.speechReader;

  void _onDevAreaTap() {
    setState(() {
      _devTapCount++;
      if (_devTapCount >= 7) {
        settings.developerModeEnabled = !settings.developerModeEnabled;
        _devTapCount = 0;
        final lang = settings.language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings.developerModeEnabled
                  ? '開発者モードを有効にしました'.tr(lang)
                  : '開発者モードを無効にしました'.tr(lang),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, speechReader]),
        builder: (context, _) {
          final lang = settings.language;
          final showDeveloperTools = settings.developerModeEnabled;
          return WashabeSubpageScaffold(
            title: '設定'.tr(lang),
            appBarColor: AppColors.blue,
            appBarForegroundColor: Colors.white,
            leading: const SizedBox.shrink(),
            body: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ─── 言語 ───────────────────────────────────────────
                _sectionHeader('言語'.tr(lang)),
                _card([
                  for (int i = 0; i < _languages.length; i++) ...[
                    if (i > 0) const _ItemDivider(),
                    _LanguageTile(
                      flag: _languages[i].$3,
                      label: _languages[i].$2,
                      selected: settings.language == _languages[i].$1,
                      onTap: () => settings.language = _languages[i].$1,
                    ),
                  ],
                ]),
                _noteText('アプリの表示言語を変更できます。'.tr(lang)),

                _sectionHeaderWithIcon(Icons.volume_up, '読み上げ'.tr(lang)),
                _card([
                  _VoiceGenderTile(
                    label: '声質'.tr(lang),
                    currentValue: settings.speechVoiceGender.tr(lang),
                    onTap: () => _showGenderPicker(context, lang),
                  ),
                  const _ItemDivider(),
                  _SpeechRateTile(
                    label: '読み上げ速度'.tr(lang),
                    slowLabel: 'ゆっくり'.tr(lang),
                    fastLabel: 'はやい'.tr(lang),
                    rate: settings.speechRate,
                    onChanged: (v) => settings.speechRate = v,
                  ),
                  const _ItemDivider(),
                  _ValueTile(
                    label: '使用中の声'.tr(lang),
                    value: speechReader.activeVoiceDescription(lang),
                  ),
                  const _ItemDivider(),
                  _SwitchTile(
                    label: 'シャッフル後に読み上げ'.tr(lang),
                    value: settings.shakeAutoSpeak,
                    onChanged: (v) => settings.shakeAutoSpeak = v,
                  ),
                ]),
                _noteText(
                  speechReader.isUsingHighQualityVoice
                      ? '使用中の声_高品質'.trFmt(lang, [
                          speechReader.activeVoiceDescription(lang),
                        ])
                      : Platform.isIOS
                          ? 'より自然な声: iPhone の設定 → アクセシビリティ → リーダーと読み上げ → 声 → 日本語 → Kyoko または Otoya の高品質版をダウンロード（iOS によっては「読み上げコンテンツ」と表示）'
                              .tr(lang)
                          : '声質_Android説明'.tr(lang),
                ),
                if (!speechReader.ttsAvailable)
                  _TtsUnavailableNotice(
                    text: (Platform.isIOS ? '読み上げ_音声なし_iOS' : '読み上げ_音声なし')
                        .tr(lang),
                    onTap: () => NativeTtsPlatform.openSettings(),
                  ),

                _sectionHeaderWithIcon(
                  Icons.chat_bubble_outline,
                  'お題'.tr(lang),
                ),
                _card([
                  _SwitchTile(
                    label: '内蔵のお題を使う'.tr(lang),
                    value: settings.useBuiltInTopics,
                    onChanged: (v) => settings.useBuiltInTopics = v,
                  ),
                ]),
                _noteText('内蔵のお題を使う_説明'.tr(lang)),

                _sectionHeader('模擬試験'.tr(lang)),
                _card([
                  _SwitchTile(
                    label: '模擬試験中に質問を表示'.tr(lang),
                    value: settings.mockExamShowQuestion,
                    onChanged: (v) => settings.mockExamShowQuestion = v,
                  ),
                ]),
                _noteText('模擬試験中に質問を表示_説明'.tr(lang)),

                _sectionHeaderWithIcon(
                  Icons.notifications_none,
                  'タイマー設定'.tr(lang),
                ),
                _card([
                  _NavigationTile(
                    label: 'タイマー音'.tr(lang),
                    value: TimerCompletionSoundCatalog.displayName(
                      settings.completionSound,
                      lang,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      fullscreenDismissRoute<void>(
                        builder: (_) => TimerSoundPickerView(
                          settings: settings,
                          timerAlert: timerAlert,
                          languageCode: lang,
                        ),
                      ),
                    ),
                  ),
                  const _ItemDivider(),
                  _SwitchTile(
                    label: 'フェーズ切替音'.tr(lang),
                    value: settings.phaseTransitionSoundEnabled,
                    onChanged: (v) => settings.phaseTransitionSoundEnabled = v,
                  ),
                  const _ItemDivider(),
                  _SwitchTile(
                    label: '終了・切替のバイブレーション'.tr(lang),
                    value: settings.vibrationEnabled,
                    onChanged: (v) => settings.vibrationEnabled = v,
                  ),
                  const _ItemDivider(),
                  _SwitchTile(
                    label: '準備15秒のバイブレーション'.tr(lang),
                    value: settings.preparationTickVibrationEnabled,
                    onChanged: (v) =>
                        settings.preparationTickVibrationEnabled = v,
                  ),
                  const _ItemDivider(),
                  _IntervalTile(
                    label: 'インターバル'.tr(lang),
                    currentSeconds: settings.autoAdvanceInterval,
                    languageCode: lang,
                    onTap: () => _showIntervalPicker(context, lang),
                  ),
                ]),
                _noteText('タイマー音_バイブレーション説明'.tr(lang)),
                _noteText('インターバル_説明'.tr(lang)),

                _sectionHeader('採点履歴'.tr(lang)),
                _card([
                  _SwitchTile(
                    label: '採点履歴を保持する'.tr(lang),
                    value: settings.scoringHistoryEnabled,
                    onChanged: (v) => settings.scoringHistoryEnabled = v,
                  ),
                  const _ItemDivider(),
                  _ResetHistoryTile(
                    lang: lang,
                    enabled: _hasHistory,
                    onReset: () {
                      widget.onResetScoringHistory();
                      setState(() => _hasHistory = false);
                    },
                  ),
                ]),
                _noteText('採点履歴_説明'.tr(lang)),

                _sectionHeader('サポート'.tr(lang)),
                _card([
                  _NavigationTile(
                    label: _isSendingLog
                        ? 'ログ_送信中'.tr(lang)
                        : 'クラッシュログを送信'.tr(lang),
                    onTap:
                        _isSendingLog ? () {} : () => _showLogSendDialog(lang),
                  ),
                  const _ItemDivider(),
                  InkWell(
                    onTap: () => _clearLog(lang),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text(
                        'ログをクリア'.tr(lang),
                        style: const TextStyle(
                          fontSize: 17,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ),
                ]),
                _noteText('クラッシュログ送信_説明'.tr(lang)),

                _sectionHeader('プライバシー'.tr(lang)),
                _card([
                  _NavigationTile(
                    label: '同意とデータ削除'.tr(lang),
                    onTap: () => Navigator.push(
                      context,
                      fullscreenDismissRoute<void>(
                        builder: (_) => PrivacyView(
                          settings: settings,
                          preferences: settings.preferences,
                        ),
                      ),
                    ),
                  ),
                ]),
                _noteText('help.privacy.body'.tr(lang)),

                if (showDeveloperTools) ...[
                  _sectionHeader('開発者向け'.tr(lang)),
                  _card([
                    _calibrationBiasTile(settings, lang),
                    const _ItemDivider(),
                    _NavigationTile(
                      label: '音声認識ログ'.tr(lang),
                      onTap: () {
                        Navigator.of(context).push(
                          fullscreenDismissRoute<void>(
                            builder: (_) => SpeechRecognitionDebugLogView(
                              languageCode: lang,
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                  _noteText('音声認識ログ_設定説明'.tr(lang)),
                ],

                GestureDetector(
                  onTap: _onDevAreaTap,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(height: 40, width: double.infinity),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const _intervalOptions = [0, 3, 5];

  String _intervalLabel(int seconds, String lang) {
    if (seconds == 0) return 'インターバル_なし'.tr(lang);
    return '$seconds${'秒'.tr(lang)}';
  }

  void _showIntervalPicker(BuildContext context, String lang) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        actions: [
          for (final s in _intervalOptions)
            CupertinoActionSheetAction(
              isDefaultAction: settings.autoAdvanceInterval == s,
              onPressed: () {
                settings.autoAdvanceInterval = s;
                Navigator.pop(sheetCtx);
              },
              child: Text(_intervalLabel(s, lang)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: Text('キャンセル'.tr(lang)),
        ),
      ),
    );
  }

  void _showGenderPicker(BuildContext context, String lang) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        actions: [
          for (final g in SpeechVoiceGender.values)
            CupertinoActionSheetAction(
              isDefaultAction: settings.speechVoiceGender == g.rawValue,
              onPressed: () {
                settings.speechVoiceGender = g.rawValue;
                Navigator.pop(sheetCtx);
              },
              child: Text(g.rawValue.tr(lang)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: Text('キャンセル'.tr(lang)),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.labelGray,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _sectionHeaderWithIcon(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.labelGray),
          const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.labelGray,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: children),
    );
  }

  Widget _noteText(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.labelGray, fontSize: 13),
      ),
    );
  }

  Widget _calibrationBiasTile(AppSettingsNotifier settings, String lang) {
    final bias = settings.preferences.calibrationBias;
    final count = settings.preferences.calibrationSampleCount;
    final sign = bias >= 0 ? '+' : '';
    final tendency = JsstCalibrationService.biasLabel(bias).tr(lang);
    final value =
        count == 0 ? '—' : '$sign${bias.toStringAsFixed(2)}（$tendency）';
    return _ValueTile(
      label: '補正係数'.tr(lang),
      value: value,
    );
  }
}

// ─── 再利用コンポーネント ────────────────────────────────────────────

class _ItemDivider extends StatelessWidget {
  const _ItemDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.5,
      indent: 16,
      color: AppColors.inactive,
    );
  }
}

class _ResetHistoryTile extends StatelessWidget {
  const _ResetHistoryTile({
    required this.lang,
    required this.enabled,
    required this.onReset,
  });

  final String lang;
  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.red : AppColors.inactive;
    return InkWell(
      onTap: enabled ? onReset : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          '採点履歴をリセット'.tr(lang),
          style: TextStyle(fontSize: 17, color: color),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 17)),
            ),
            if (selected)
              const Icon(Icons.check, color: AppColors.blue, size: 20),
          ],
        ),
      ),
    );
  }
}

class _VoiceGenderTile extends StatelessWidget {
  const _VoiceGenderTile({
    required this.label,
    required this.currentValue,
    required this.onTap,
  });

  final String label;
  final String currentValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
            Text(
              currentValue,
              style: const TextStyle(
                color: AppColors.labelGray,
                fontSize: 17,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.unfold_more,
              size: 20,
              color: AppColors.labelGray,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechRateTile extends StatelessWidget {
  const _SpeechRateTile({
    required this.label,
    required this.slowLabel,
    required this.fastLabel,
    required this.rate,
    required this.onChanged,
  });

  final String label;
  final String slowLabel;
  final String fastLabel;
  final double rate;
  final ValueChanged<double> onChanged;

  static const _min = 0.35;
  static const _max = 0.68;

  String get _displayRate {
    final normalized = (rate - _min) / (_max - _min);
    final display = normalized * 1.5 + 0.5;
    return '${display.toStringAsFixed(1)}×';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 17)),
              ),
              Text(
                _displayRate,
                style: const TextStyle(
                  color: AppColors.labelGray,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10,
                elevation: 2,
              ),
              activeTrackColor: AppColors.blue,
              inactiveTrackColor: AppColors.inactive,
              trackHeight: 4,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: rate,
              min: _min,
              max: _max,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                slowLabel,
                style: const TextStyle(
                  color: AppColors.labelGray,
                  fontSize: 13,
                ),
              ),
              Text(
                fastLabel,
                style: const TextStyle(
                  color: AppColors.labelGray,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TtsUnavailableNotice extends StatelessWidget {
  const _TtsUnavailableNotice({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.red, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.labelGray,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.green,
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.label,
    required this.onTap,
    this.value,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  softWrap: true,
                  style: const TextStyle(
                    color: AppColors.labelGray,
                    fontSize: 17,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppColors.chevronGray,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalTile extends StatelessWidget {
  const _IntervalTile({
    required this.label,
    required this.currentSeconds,
    required this.languageCode,
    required this.onTap,
  });

  final String label;
  final int currentSeconds;
  final String languageCode;
  final VoidCallback onTap;

  String get _displayValue {
    if (currentSeconds == 0) return 'インターバル_なし'.tr(languageCode);
    return '$currentSeconds${'秒'.tr(languageCode)}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
            Text(
              _displayValue,
              style: const TextStyle(
                color: AppColors.labelGray,
                fontSize: 17,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.unfold_more,
              size: 20,
              color: AppColors.labelGray,
            ),
          ],
        ),
      ),
    );
  }
}
