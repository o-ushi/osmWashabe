import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/practice_controller.dart';
import '../../data/mock_exam_planner.dart';
import '../../data/topic_repository.dart';
import '../../l10n/app_strings.dart';
import '../../models/appearance_models.dart';
import '../../theme/app_colors.dart';
import '../../models/practice_models.dart';
import '../../models/topic.dart';
import '../../notifiers/app_appearance.dart';
import '../../notifiers/app_settings.dart';
import '../../services/app_preferences.dart';
import '../../services/shake_detector_service.dart';
import '../../services/speech_recognition_service.dart';
import '../../services/timer_alert.dart';
import '../../services/android_offline_speech_platform.dart';
import '../../services/vosk_model_manager.dart';
import '../../services/topic_speech_reader.dart';
import '../../widgets/appearance_background_layer.dart';
import '../../widgets/topic_category_picker.dart';
import '../../widgets/washabe_frame_card.dart';
import '../../widgets/washabe_icon_button.dart';
import '../../widgets/washabe_more_actions_menu.dart';
import '../../widgets/washabe_timer_section.dart';
import '../help/help_view.dart';
import '../import/topic_import_view.dart';
import '../practice/scoring_result_view.dart';
import '../privacy/privacy_view.dart';
import '../settings/settings_view.dart';
import '../../widgets/swipe_down_to_dismiss.dart';

/// メイン練習画面
class MainView extends StatefulWidget {
  const MainView({
    super.key,
    required this.appearance,
    required this.settings,
    required this.preferences,
  });

  final AppAppearance appearance;
  final AppSettingsNotifier settings;
  final AppPreferences preferences;

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> with WidgetsBindingObserver {
  late final TopicSpeechReader _speechReader;
  late final TimerAlert _timerAlert;
  late final SpeechRecognitionService _speechRecognition;
  late final PracticeController _controller;
  late final TopicRepository _topicRepository;
  final _shakeDetector = ShakeDetectorService();
  final _moreButtonKey = GlobalKey();
  final _innerNavigatorKey = GlobalKey<NavigatorState>();
  bool _isScoringSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speechReader = TopicSpeechReader(widget.settings);
    _timerAlert = TimerAlert(widget.settings);
    _speechRecognition = SpeechRecognitionService();
    _topicRepository = TopicRepository(widget.preferences);
    _controller = PracticeController(
      settings: widget.settings,
      topicRepository: _topicRepository,
      speechReader: _speechReader,
      timerAlert: _timerAlert,
      speechRecognition: _speechRecognition,
      preferences: widget.preferences,
    )..startTicking();
    _controller.restorePersistedTimerState();
    _speechReader.addListener(_onSpeechChanged);
    _controller.addListener(_onControllerChanged);
    widget.settings.addListener(_syncShakeDetector);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncShakeDetector());
  }

  void _onSpeechChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onControllerChanged() {
    if (!_isScoringSheetOpen && _controller.isAwaitingScoring) {
      _isScoringSheetOpen = true;
      _openSheet(
        ScoringResultView(
          controller: _controller,
          languageCode: _lang,
          settings: widget.settings,
          preferences: widget.preferences,
        ),
      ).whenComplete(() => _isScoringSheetOpen = false);
    }
  }

  void _openScoringSheet({bool allowEmpty = false}) {
    if (_isScoringSheetOpen) return;
    if (!allowEmpty &&
        _controller.scoringHistory.isEmpty &&
        !_controller.isAwaitingScoring) {
      return;
    }
    _isScoringSheetOpen = true;
    _openSheet(
      ScoringResultView(
        controller: _controller,
        languageCode: _lang,
        settings: widget.settings,
        preferences: widget.preferences,
      ),
    ).whenComplete(() => _isScoringSheetOpen = false);
  }

  void _onScoringButtonLongPress() {
    if (!widget.settings.scoringEnabled) return;
    if (_controller.scoringHistory.isEmpty && !_controller.isAwaitingScoring) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('採点結果がありません'.tr(_lang))),
      );
      return;
    }
    _openScoringSheet(allowEmpty: true);
  }

  void _onScoringButtonTap() {
    _handleScoringEnable();
  }

  Future<void> _handleScoringEnable() async {
    if (widget.settings.scoringEnabled) {
      widget.settings.scoringEnabled = false;
      return;
    }

    final consented = await showSpeechConsentDialog(
      context,
      languageCode: _lang,
    );
    if (!consented || !mounted) return;

    // iOS は OS 組み込み STT を使うためモデル不要。
    if (!Platform.isAndroid) {
      widget.settings.scoringEnabled = true;
      return;
    }

    // Android: 採点 ON 前にマイク権限を取得する。
    // タイマー走行中ではなくここで取得することで、ユーザーが落ち着いて許可できる。
    final permitted =
        await AndroidOfflineSpeechPlatform.requestRecordPermission();
    if (!mounted) return;
    if (!permitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('マイク権限なし'.tr(_lang))),
      );
      return;
    }

    // モデルがすでに展開済みならそのまま有効化。
    if (await VoskModelManager.isReady()) {
      widget.settings.scoringEnabled = true;
      return;
    }

    if (!mounted) return;

    // APK にバンドル済み ZIP を展開してから有効化する。
    // 展開が終わる前に採点 ON にすると、録音開始と同時に 47MB の
    // アセット読み込みが走り AudioRecord 初期化と競合するため先に完了させる。
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoskDownloadProgressDialog(languageCode: _lang),
    );
    if ((success ?? false) && mounted) {
      widget.settings.scoringEnabled = true;
    }
  }

  void _syncShakeDetector() {
    _shakeDetector.start(() => _controller.handleShakeGesture());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleLifecycleChange(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speechReader.removeListener(_onSpeechChanged);
    _controller.removeListener(_onControllerChanged);
    widget.settings.removeListener(_syncShakeDetector);
    _controller.disposeTicking();
    _controller.dispose();
    _speechReader.dispose();
    _speechRecognition.dispose();
    _shakeDetector.dispose();
    super.dispose();
  }

  String get _lang => widget.settings.language;

  Future<void> _openSheet(Widget child) async {
    await _speechReader.stop();
    if (!mounted) return;
    final navigator = _innerNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push<void>(
      fullscreenDismissRoute(builder: (_) => child),
    );
  }

  Route<void> _onInnerRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      builder: (_) => _buildMainPracticePage(),
      settings: settings,
    );
  }

  Future<void> _openTopicImport() => _openSheet(
        TopicImportView(
          repository: _topicRepository,
          languageCode: _lang,
        ),
      );

  void _showMoreMenu(BuildContext context) {
    final box = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(context);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: screen.width - offset.dx - size.width,
            top: offset.dy + size.height + 6,
            child: WashabeMoreActionsMenu(
              languageCode: _lang,
              onTopicImport: () {
                Navigator.pop(ctx);
                _openTopicImport();
              },
              onSettings: () {
                Navigator.pop(ctx);
                _openSheet(
                  SettingsView(
                    settings: widget.settings,
                    timerAlert: _timerAlert,
                    speechReader: _speechReader,
                    onResetScoringHistory: _controller.clearScoringHistory,
                    hasScoringHistory: () =>
                        _controller.scoringHistory.isNotEmpty,
                  ),
                );
              },
              onHelp: () {
                Navigator.pop(ctx);
                _openSheet(
                  HelpView(
                    settings: widget.settings,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _innerNavigatorKey,
      initialRoute: '/',
      onGenerateRoute: _onInnerRoute,
    );
  }

  Widget _buildMainPracticePage() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.settings,
        _controller,
        _speechReader,
      ]),
      builder: (context, _) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final scene = widget.appearance.sceneColorFor(platformBrightness);
        final effectiveScheme =
            widget.appearance.effectiveColorScheme(platformBrightness);
        final accent = widget.appearance.readableAccent(scene);
        final fg = widget.appearance.foregroundOn(scene);
        final muted = widget.appearance.mutedOn(scene);
        final frameStyle = widget.appearance.resolvedFrameStyle();
        final lang = _lang;

        final showTimer =
            _controller.sessionMode == AppSessionMode.singleQuestion ||
                (_controller.sessionMode == AppSessionMode.mockExam &&
                    _controller.isMockExamActive);

        final dialogBg = effectiveScheme == Brightness.dark
            ? const Color(0xFF2C2C38)
            : Colors.white;
        // 時刻・バッテリーをシーン色に溶け込ませない（暗いシーンでは白）
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: effectiveScheme == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: accent,
                brightness: effectiveScheme,
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: dialogBg,
                titleTextStyle: TextStyle(
                  color: fg,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                contentTextStyle: TextStyle(color: fg),
              ),
              listTileTheme: ListTileThemeData(
                textColor: fg,
                iconColor: fg,
              ),
            ),
            child: Scaffold(
              backgroundColor: scene,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  AppearanceBackgroundLayer(
                    sceneColor: scene,
                    colorScheme: effectiveScheme,
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SessionBar(
                            controller: _controller,
                            settings: widget.settings,
                            appearance: widget.appearance,
                            scene: scene,
                            fg: fg,
                            moreButtonKey: _moreButtonKey,
                            lang: lang,
                            onMore: () => _showMoreMenu(context),
                            onOpenScoring: _onScoringButtonLongPress,
                            onScoringTap: _onScoringButtonTap,
                          ),
                          const SizedBox(height: 10),
                          if (_controller.sessionMode ==
                              AppSessionMode.singleQuestion)
                            _CompactTrainingBar(
                              controller: _controller,
                              appearance: widget.appearance,
                              scene: scene,
                              fg: fg,
                              lang: lang,
                            ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _controller.sessionMode ==
                                        AppSessionMode.mockExam &&
                                    !_controller.isMockExamActive &&
                                    !_controller.isMockExamFinished
                                ? _MockExamIntro(
                                    controller: _controller,
                                    appearance: widget.appearance,
                                    frameStyle: frameStyle,
                                    scene: scene,
                                    fg: fg,
                                    muted: muted,
                                    lang: lang,
                                  )
                                : _PracticeBody(
                                    controller: _controller,
                                    speechReader: _speechReader,
                                    appearance: widget.appearance,
                                    frameStyle: frameStyle,
                                    scene: scene,
                                    fg: fg,
                                    muted: muted,
                                    lang: lang,
                                    onCategoryChanged: _controller.setCategory,
                                  ),
                          ),
                          if (showTimer) ...[
                            const SizedBox(height: 10),
                            WashabeTimerSection(
                              controller: _controller,
                              appearance: widget.appearance,
                              scene: scene,
                              frameStyle: frameStyle,
                              accent: accent,
                              languageCode: lang,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.controller,
    required this.settings,
    required this.appearance,
    required this.scene,
    required this.fg,
    required this.moreButtonKey,
    required this.lang,
    required this.onMore,
    required this.onOpenScoring,
    required this.onScoringTap,
  });

  final PracticeController controller;
  final AppSettingsNotifier settings;
  final AppAppearance appearance;
  final Color scene;
  final Color fg;
  final GlobalKey moreButtonKey;
  final String lang;
  final VoidCallback onMore;
  final VoidCallback onOpenScoring;
  final VoidCallback onScoringTap;

  static const _scoringOnFill = AppColors.green;
  static const _scoringOnIcon = Colors.white;

  @override
  Widget build(BuildContext context) {
    final isMockExam = controller.sessionMode == AppSessionMode.mockExam;
    final scoringOn = settings.scoringEnabled && !isMockExam;
    return Row(
      children: [
        Tooltip(
          message: scoringOn ? '採点ON_ヒント'.tr(lang) : '採点OFF_ヒント'.tr(lang),
          child: Material(
            color:
                scoringOn ? _scoringOnFill : appearance.subtleFill(scene, 0.14),
            shape: const CircleBorder(),
            elevation: scoringOn ? 2 : 0,
            shadowColor: scoringOn
                ? const Color(0xFF248A3D).withValues(alpha: 0.45)
                : Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isMockExam ? null : onScoringTap,
              onLongPress: scoringOn ? onOpenScoring : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  scoringOn ? Icons.assessment : Icons.assessment_outlined,
                  color: scoringOn ? _scoringOnIcon : fg,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sessionButton(
            icon: Icons.looks_one_rounded,
            label: '1問ずつ'.tr(lang),
            selected: controller.sessionMode == AppSessionMode.singleQuestion,
            onTap: () =>
                controller.setSessionMode(AppSessionMode.singleQuestion),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sessionButton(
            icon: Icons.format_list_numbered,
            label: '模擬試験'.tr(lang),
            selected: controller.sessionMode == AppSessionMode.mockExam,
            onTap: () => controller.setSessionMode(AppSessionMode.mockExam),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'その他'.tr(lang),
          child: Material(
            key: moreButtonKey,
            color: appearance.subtleFill(scene, 0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onMore,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.more_horiz, color: fg, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sessionButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return WashabeIconButton(
      icon: icon,
      tooltip: label,
      onPressed: onTap,
      expand: true,
      backgroundColor: appearance.accentChipFill(scene, selected: selected),
      foregroundColor: fg,
    );
  }
}

class _CompactTrainingBar extends StatelessWidget {
  const _CompactTrainingBar({
    required this.controller,
    required this.appearance,
    required this.scene,
    required this.fg,
    required this.lang,
  });

  final PracticeController controller;
  final AppAppearance appearance;
  final Color scene;
  final Color fg;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return _compactBar(
      height: 32,
      radius: 8,
      background: appearance.subtleFill(scene, 0.12),
      children: [
        _compactTab(
          label: '通常オプション_45秒'.tr(lang),
          selected: controller.normalTimerOption == NormalTimerOption.sec45,
          onTap: () => controller.setNormalTimerOption(NormalTimerOption.sec45),
        ),
        _compactTab(
          label: '通常オプション_60秒'.tr(lang),
          selected: controller.normalTimerOption == NormalTimerOption.sec60,
          onTap: () => controller.setNormalTimerOption(NormalTimerOption.sec60),
        ),
        _compactTab(
          label: '通常オプション_15+60秒'.tr(lang),
          selected: controller.normalTimerOption ==
              NormalTimerOption.prep15speaking60,
          onTap: () => controller.setNormalTimerOption(
            NormalTimerOption.prep15speaking60,
          ),
        ),
      ],
    );
  }

  Widget _compactBar({
    required double height,
    required double radius,
    required Color background,
    required List<Widget> children,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(
        height: height,
        child: Row(children: children),
      ),
    );
  }

  Widget _compactTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: appearance.accentChipFill(scene, selected: selected),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox.expand(
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MockExamIntro extends StatelessWidget {
  const _MockExamIntro({
    required this.controller,
    required this.appearance,
    required this.frameStyle,
    required this.scene,
    required this.fg,
    required this.muted,
    required this.lang,
  });

  final PracticeController controller;
  final AppAppearance appearance;
  final FrameResolvedStyle frameStyle;
  final Color scene;
  final Color fg;
  final Color muted;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '模擬試験紹介'.tr(lang),
          style: TextStyle(color: muted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        WashabeFrameCard(
          style: frameStyle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _formatRow(
                '模擬試験内訳_通常'.tr(lang),
                7,
                frameStyle.readablePrimaryText,
                frameStyle.readableSecondaryText,
              ),
              _formatRow(
                '模擬試験内訳_60秒'.tr(lang),
                1,
                frameStyle.readablePrimaryText,
                frameStyle.readableSecondaryText,
              ),
              _formatRow(
                '模擬試験内訳_準備付き'.tr(lang),
                1,
                frameStyle.readablePrimaryText,
                frameStyle.readableSecondaryText,
              ),
              _formatRow(
                '模擬試験内訳_敬語'.tr(lang),
                1,
                frameStyle.readablePrimaryText,
                frameStyle.readableSecondaryText,
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '開始問題'.tr(lang),
                      style: TextStyle(
                        color: frameStyle.readablePrimaryText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.mockExamStartIndex > 0
                        ? () => controller.setMockExamStartIndex(
                              controller.mockExamStartIndex - 1,
                            )
                        : null,
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: frameStyle.readablePrimaryText,
                    ),
                  ),
                  Text(
                    '${controller.mockExamStartIndex + 1}',
                    style: TextStyle(
                      color: frameStyle.readableSecondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.mockExamStartIndex <
                            MockExamPlanner.totalCount - 1
                        ? () => controller.setMockExamStartIndex(
                              controller.mockExamStartIndex + 1,
                            )
                        : null,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: frameStyle.readablePrimaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: appearance.accentChipFill(scene, selected: true),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => controller.startMockExam(),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: fg,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _formatRow(
    String title,
    int count,
    Color primary,
    Color secondary,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: secondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeBody extends StatelessWidget {
  const _PracticeBody({
    required this.controller,
    required this.speechReader,
    required this.appearance,
    required this.frameStyle,
    required this.scene,
    required this.fg,
    required this.muted,
    required this.lang,
    required this.onCategoryChanged,
  });

  final PracticeController controller;
  final TopicSpeechReader speechReader;
  final AppAppearance appearance;
  final FrameResolvedStyle frameStyle;
  final Color scene;
  final Color fg;
  final Color muted;
  final String lang;
  final ValueChanged<TopicCategory> onCategoryChanged;

  String _mockStepLabel(MockExamQuestionKind kind) {
    return switch (kind) {
      MockExamQuestionKind.normal45 => '模擬試験ラベル_通常'.tr(lang),
      MockExamQuestionKind.normal60 => '模擬試験ラベル_60秒'.tr(lang),
      MockExamQuestionKind.normal15plus60 => '模擬試験ラベル_準備付き'.tr(lang),
      MockExamQuestionKind.situationKeigo => '模擬試験ラベル_敬語'.tr(lang),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (controller.sessionMode == AppSessionMode.mockExam &&
        controller.isMockExamFinished) {
      return _MockExamFinished(
        controller: controller,
        appearance: appearance,
        scene: scene,
        fg: fg,
        muted: muted,
        lang: lang,
      );
    }

    if (controller.sessionMode == AppSessionMode.singleQuestion) {
      return _NormalModeContent(
        controller: controller,
        speechReader: speechReader,
        appearance: appearance,
        frameStyle: frameStyle,
        scene: scene,
        fg: fg,
        muted: muted,
        lang: lang,
        onCategoryChanged: onCategoryChanged,
      );
    }

    return _MockExamActiveContent(
      controller: controller,
      speechReader: speechReader,
      appearance: appearance,
      frameStyle: frameStyle,
      scene: scene,
      fg: fg,
      muted: muted,
      lang: lang,
      mockStepLabel: _mockStepLabel,
    );
  }
}

class _PrimaryActionRow extends StatelessWidget {
  const _PrimaryActionRow({
    required this.primaryIcon,
    required this.primaryTooltip,
    required this.onPrimary,
    required this.primaryEnabled,
    required this.readAloudEnabled,
    required this.onReadAloud,
    required this.appearance,
    required this.scene,
    required this.fg,
    required this.lang,
    required this.isSpeaking,
    required this.isPaused,
  });

  final IconData primaryIcon;
  final String primaryTooltip;
  final VoidCallback onPrimary;
  final bool primaryEnabled;
  final bool readAloudEnabled;
  final VoidCallback? onReadAloud;
  final AppAppearance appearance;
  final Color scene;
  final Color fg;
  final String lang;
  final bool isSpeaking;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final IconData speakerIcon;
    final String speakerTooltip;
    if (isPaused) {
      speakerIcon = Icons.play_arrow_rounded;
      speakerTooltip = '読み上げ再開'.tr(lang);
    } else if (isSpeaking) {
      speakerIcon = Icons.pause_rounded;
      speakerTooltip = '読み上げ一時停止'.tr(lang);
    } else {
      speakerIcon = Icons.record_voice_over;
      speakerTooltip = '読み上げ'.tr(lang);
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: WashabeIconButton(
            icon: primaryIcon,
            tooltip: primaryTooltip,
            onPressed: primaryEnabled ? onPrimary : null,
            enabled: primaryEnabled,
            expand: true,
            backgroundColor: appearance.accentChipFill(
              scene,
              selected: primaryEnabled,
            ),
            foregroundColor: fg,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: WashabeIconButton(
            icon: speakerIcon,
            tooltip: speakerTooltip,
            onPressed: (readAloudEnabled || isPaused) ? onReadAloud : null,
            enabled: readAloudEnabled || isPaused,
            expand: true,
            backgroundColor: appearance.subtleFill(
              scene,
              (readAloudEnabled || isPaused) ? 0.16 : 0.08,
            ),
            foregroundColor: fg,
          ),
        ),
      ],
    );
  }
}

class _NormalModeContent extends StatelessWidget {
  const _NormalModeContent({
    required this.controller,
    required this.speechReader,
    required this.appearance,
    required this.frameStyle,
    required this.scene,
    required this.fg,
    required this.muted,
    required this.lang,
    required this.onCategoryChanged,
  });

  final PracticeController controller;
  final TopicSpeechReader speechReader;
  final AppAppearance appearance;
  final FrameResolvedStyle frameStyle;
  final Color scene;
  final Color fg;
  final Color muted;
  final String lang;
  final ValueChanged<TopicCategory> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final is15plus60 =
        controller.normalTimerOption == NormalTimerOption.prep15speaking60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TopicCategoryPicker(
          category: controller.category,
          languageCode: lang,
          foregroundColor: fg,
          onChanged: onCategoryChanged,
          availableCategories: is15plus60
              ? const [
                  TopicCategory.daily,
                  TopicCategory.business,
                  TopicCategory.situation,
                  TopicCategory.random,
                ]
              : const [
                  TopicCategory.daily,
                  TopicCategory.business,
                  TopicCategory.random,
                ],
        ),
        const SizedBox(height: 8),
        _PrimaryActionRow(
          primaryIcon: Icons.casino_rounded,
          primaryTooltip: 'お題を引く'.tr(lang),
          onPrimary: controller.shuffleTopic,
          primaryEnabled: !controller.isInInterval,
          readAloudEnabled:
              controller.hasDrawnTopic && !controller.isInInterval,
          onReadAloud: controller.toggleReadAloud,
          appearance: appearance,
          scene: scene,
          fg: fg,
          lang: lang,
          isSpeaking: speechReader.isSpeaking,
          isPaused: controller.isPaused,
        ),
        const SizedBox(height: 8),
        if (controller.hasDrawnTopic)
          Expanded(
            child: SingleChildScrollView(
              child: WashabeFrameCard(
                style: frameStyle,
                child: Text(
                  controller.currentTopic,
                  style: TextStyle(
                    color: frameStyle.readablePrimaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Text(
                'ボタンを押してお題を引いてください'.tr(lang),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MockExamActiveContent extends StatelessWidget {
  const _MockExamActiveContent({
    required this.controller,
    required this.speechReader,
    required this.appearance,
    required this.frameStyle,
    required this.scene,
    required this.fg,
    required this.muted,
    required this.lang,
    required this.mockStepLabel,
  });

  final PracticeController controller;
  final TopicSpeechReader speechReader;
  final AppAppearance appearance;
  final FrameResolvedStyle frameStyle;
  final Color scene;
  final Color fg;
  final Color muted;
  final String lang;
  final String Function(MockExamQuestionKind kind) mockStepLabel;

  Future<void> _confirmAbort(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('模擬試験を中断しますか'.tr(lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('続ける'.tr(lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('中断する'.tr(lang)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.abortMockExam();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = controller.currentMockExamStep;
    final showQuestion = controller.mockExamShowQuestion;

    return Column(
      children: [
        if (step != null) ...[
          Text(
            '第 %lld 問 / %lld 問'.trFmt(lang, [
              '${controller.mockExamStepIndex + 1}',
              '${controller.mockExamSteps.length}',
            ]),
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          Text(
            mockStepLabel(step.kind),
            style: TextStyle(color: muted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        if (step != null &&
            showQuestion &&
            controller.displayTopicText.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              child: WashabeFrameCard(
                style: frameStyle,
                child: Text(
                  controller.displayTopicText,
                  style: TextStyle(
                    color: frameStyle.readablePrimaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          )
        else if (step != null)
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: WashabeIconButton(
                icon: speechReader.isSpeaking ? Icons.volume_up : Icons.hearing,
                tooltip: speechReader.isSpeaking
                    ? '聞き返し中'.tr(lang)
                    : '質問を聞き返す'.tr(lang),
                onPressed: () => controller.repeatMockExamQuestion(step),
                expand: true,
                backgroundColor: appearance.accentChipFill(
                  scene,
                  selected: speechReader.isSpeaking,
                ),
                foregroundColor: fg,
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(height: 8),
        Material(
          color: appearance.subtleFill(scene, 0.12),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _confirmAbort(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_rounded, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '模擬試験を終了'.tr(lang),
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MockExamFinished extends StatelessWidget {
  const _MockExamFinished({
    required this.controller,
    required this.appearance,
    required this.scene,
    required this.fg,
    required this.muted,
    required this.lang,
  });

  final PracticeController controller;
  final AppAppearance appearance;
  final Color scene;
  final Color fg;
  final Color muted;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle, color: Colors.green, size: 56),
        const SizedBox(height: 16),
        Text(
          '模擬試験が終了しました'.tr(lang),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fg,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '模擬試験完了メッセージ'.tr(lang),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: WashabeIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'もう一度受ける'.tr(lang),
                onPressed: () => controller.startMockExam(),
                expand: true,
                backgroundColor:
                    appearance.accentChipFill(scene, selected: true),
                foregroundColor: fg,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WashabeIconButton(
                icon: Icons.undo_rounded,
                tooltip: '模擬試験紹介に戻る'.tr(lang),
                onPressed: controller.returnToMockExamIntro,
                expand: true,
                backgroundColor: appearance.subtleFill(scene, 0.12),
                foregroundColor: fg,
              ),
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }
}

// ─── Vosk モデルのダウンロード進捗ダイアログ ───────────────────────────────

class _VoskDownloadProgressDialog extends StatefulWidget {
  const _VoskDownloadProgressDialog({required this.languageCode});
  final String languageCode;

  @override
  State<_VoskDownloadProgressDialog> createState() =>
      _VoskDownloadProgressDialogState();
}

class _VoskDownloadProgressDialogState
    extends State<_VoskDownloadProgressDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await VoskModelManager.ensureReady(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.languageCode;
    return AlertDialog(
      title: Text('採点中_モデル準備'.tr(lang)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _error == null ? _progress : null),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              '${'モデルDL_エラー'.tr(lang)}\n$_error',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('キャンセル'.tr(lang)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
