import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ai_prompt_template.dart';
import '../../data/topic_import_parser.dart';
import '../../data/topic_repository.dart';
import '../../l10n/app_strings.dart';
import '../../services/background_audio_keeper.dart';
import '../../services/google_ai_link.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

/// iOS `WashabeTopicImportView` と同じ取り込みフロー
class TopicImportView extends StatefulWidget {
  const TopicImportView({
    super.key,
    required this.repository,
    required this.languageCode,
  });

  final TopicRepository repository;
  final String languageCode;

  @override
  State<TopicImportView> createState() => _TopicImportViewState();
}

class _TopicImportViewState extends State<TopicImportView>
    with WidgetsBindingObserver {
  final _pasteController = TextEditingController();
  final _scrollController = ScrollController();
  bool _didOpenChromeAi = false;
  String? _importMessage;
  bool _importMessageIsSuccess = false;
  int _importedDailyCount = 0;
  int _importedBusinessCount = 0;
  int _importedSituationCount = 0;
  bool _isImporting = false;
  late String _batchPrompt;
  bool _startedKeeperForSession = false;

  String get _pasteText => _pasteController.text;

  bool get _canImport => !_isImporting;

  @override
  void initState() {
    super.initState();
    _batchPrompt = AiPromptTemplate.batchPrompt;
    WidgetsBinding.instance.addObserver(this);
    _pasteController.addListener(_onPasteTextChanged);
    _refreshImportedSummaryCounts();
    if (Platform.isAndroid) {
      unawaited(_ensureKeepAliveForExternalApp());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadClipboardIfAvailable();
    });
  }

  @override
  void dispose() {
    _stopKeepAliveIfOwned();
    WidgetsBinding.instance.removeObserver(this);
    _pasteController.removeListener(_onPasteTextChanged);
    _pasteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Chrome 往復時にプロセスが生きたまま残るよう、練習タイマーと同様の無音キープアライブを使う。
  Future<void> _ensureKeepAliveForExternalApp() async {
    if (!Platform.isAndroid) return;
    if (BackgroundAudioKeeper.instance.isRunning) return;
    await BackgroundAudioKeeper.instance.start();
    _startedKeeperForSession = true;
  }

  void _stopKeepAliveIfOwned() {
    if (!_startedKeeperForSession) return;
    _startedKeeperForSession = false;
    unawaited(BackgroundAudioKeeper.instance.stop());
  }


  void _onPasteTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 復帰直後は UI を先に描画し、オーディオ・クリップボードは後から処理する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _loadClipboardIfAvailable(showMessage: _pasteText.trim().isEmpty),
        );
        if (_startedKeeperForSession &&
            !BackgroundAudioKeeper.instance.isActuallyPlaying) {
          Future<void>.delayed(const Duration(milliseconds: 400), () {
            if (!mounted || !_startedKeeperForSession) return;
            unawaited(BackgroundAudioKeeper.instance.recoverIfNeeded());
          });
        }
      });
    }
  }

  void _refreshImportedSummaryCounts() {
    final summary = widget.repository.importedSummary;
    setState(() {
      _importedDailyCount = summary.dailyCount;
      _importedBusinessCount = summary.businessCount;
      _importedSituationCount = summary.situationCount;
    });
  }

  Future<void> _openChromeAi() async {
    setState(() => _batchPrompt = AiPromptTemplate.batchPrompt);
    // 初回起動が数百ms かかりうるため待たない（待つとタップ直後扱いされずChromeが開かないことがある）。
    unawaited(_ensureKeepAliveForExternalApp());
    await GoogleAiLink.openWithPrompt(_batchPrompt);
    if (!mounted) return;
    setState(() => _didOpenChromeAi = true);
  }

  Future<void> _loadClipboardIfAvailable({bool showMessage = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !TopicImportParser.looksLikeAiImport(text)) {
      if (showMessage) {
        setState(() {
          _importMessage =
              'クリップボードに AI の回答が見つかりませんでした。Chrome で回答を長押し→すべて選択→コピー してから再度お試しください。'
                  .tr(widget.languageCode);
          _importMessageIsSuccess = false;
        });
      }
      return;
    }

    final alreadyLoaded = _pasteText.trim() == text;
    _pasteController.text = text;
    if (!showMessage && alreadyLoaded) return;

    setState(() {
      _importMessage =
          'クリップボードから読み込みました。内容を確認して「お題を取り込む」を押してください。'
              .tr(widget.languageCode);
      _importMessageIsSuccess = true;
    });
  }

  Future<void> _importPastedText() async {
    final text = _pasteText.trim();
    if (_isImporting) return;
    if (text.isEmpty) {
      final msg =
          'まず「クリップボードから読み込む」で AI の回答を貼り付けてください。'.tr(widget.languageCode);
      setState(() {
        _importMessage = msg;
        _importMessageIsSuccess = false;
      });
      _showResultSnackBar(msg, isSuccess: false);
      return;
    }

    setState(() {
      _importMessage = null;
      _isImporting = true;
    });

    try {
      final batch = TopicImportParser.parseBatchImport(text);
      if (batch.isEmpty) {
        final msg =
            'お題を読み取れませんでした。【日常の身近な話題】【ビジネスシーン】【シチュエーション】の見出し付きで貼り付けてください。'
                .tr(widget.languageCode);
        setState(() {
          _importMessage = msg;
          _importMessageIsSuccess = false;
        });
        _scrollToTop();
        _showResultSnackBar(msg, isSuccess: false);
        return;
      }

      final result = widget.repository.mergeImportedBatch(batch);
      if (!mounted) return;

      if (result.totalAdded == 0) {
        final msg = '新しいお題はありませんでした（すべて重複しています）。'.tr(widget.languageCode);
        setState(() {
          _importMessage = msg;
          _importMessageIsSuccess = false;
        });
        _scrollToTop();
        _showResultSnackBar(msg, isSuccess: false);
        return;
      }

      _pasteController.clear();
      final msg =
          '日常の身近な話題 %lld 件、ビジネスシーン %lld 件、シチュエーション %lld 件を追加しました。'
              .trFmt(widget.languageCode, [
        '${result.dailyAdded}',
        '${result.businessAdded}',
        '${result.situationAdded}',
      ]);
      setState(() {
        _importMessage = msg;
        _importMessageIsSuccess = true;
      });
      _scrollToTop();
      _showResultSnackBar(msg, isSuccess: true);
      _refreshImportedSummaryCounts();
    } catch (error, stackTrace) {
      debugPrint('Topic import failed: $error\n$stackTrace');
      if (!mounted) return;
      final msg = 'お題の取り込みに失敗しました。もう一度お試しください。'.tr(widget.languageCode);
      setState(() {
        _importMessage = msg;
        _importMessageIsSuccess = false;
      });
      _scrollToTop();
      _showResultSnackBar(msg, isSuccess: false);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showResultSnackBar(String message, {required bool isSuccess}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isSuccess ? Colors.green.shade700 : Colors.orange.shade800,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearAll() async {
    widget.repository.clearImportedTopics();
    if (!mounted) return;
    setState(() {
      _importMessage =
          '取り込み済みのお題をすべて削除しました。'.tr(widget.languageCode);
      _importMessageIsSuccess = true;
    });
    _refreshImportedSummaryCounts();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.languageCode;

    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _stopKeepAliveIfOwned();
      },
      child: WashabeSubpageScaffold(
      title: 'お題の取り込み'.tr(lang),
      leading: const SizedBox.shrink(),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          _quickActionsSection(lang),
          const SizedBox(height: 20),
          _aiPromptSection(lang),
          const SizedBox(height: 20),
          _pasteEditorSection(lang),
        ],
      ),
      ),
      ),
    );
  }

  Widget _quickActionsSection(String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'お題の取り込み'.tr(lang),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _stepsGuide(lang),
        const SizedBox(height: 16),
        Row(
          children: [
            _actionIcon(
              icon: _didOpenChromeAi ? Icons.check_circle : Icons.auto_awesome,
              label: _didOpenChromeAi
                  ? 'Chrome AI を開きました'.tr(lang)
                  : 'Chrome AI で開く'.tr(lang),
              onPressed: _openChromeAi,
            ),
            const SizedBox(width: 8),
            _actionIcon(
              icon: Icons.content_paste,
              label: 'クリップボードから読み込む'.tr(lang),
              onPressed: () => _loadClipboardIfAvailable(showMessage: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('topicImportSubmitButton'),
            onPressed: _canImport ? _importPastedText : null,
            icon: _isImporting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.download),
            label: Text('お題を取り込む（インポート）'.tr(lang)),
          ),
        ),
        if (_importMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _importMessage!,
            style: TextStyle(
              color: _importMessageIsSuccess ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const Divider(height: 32),
        Text(
          '取り込み済みのお題'.tr(lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _countRow('日常の身近な話題'.tr(lang), _importedDailyCount, lang),
        _countRow('ビジネスシーン'.tr(lang), _importedBusinessCount, lang),
        _countRow('シチュエーション'.tr(lang), _importedSituationCount, lang),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _clearAll,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: Text(
            '取り込み済みお題をすべて削除'.tr(lang),
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _stepsGuide(String lang) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '操作手順'.tr(lang),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: primary,
            ),
          ),
          const SizedBox(height: 10),
          _step('①', '「Chrome AI で開く」ボタンをタップ'.tr(lang)),
          _step('②', 'Chrome が開いたら、回答が出るまで少し待つ'.tr(lang)),
          _step('③', '画面を一番下までスクロールする'.tr(lang)),
          _stepHighlighted(
            '④',
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14),
                children: [
                  TextSpan(text: 'コピーボタン（'.tr(lang)),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: const Icon(Icons.content_copy, size: 16),
                  ),
                  TextSpan(text: '）をタップ'.tr(lang)),
                ],
              ),
            ),
            'ボタンが見つからない・反応しない場合：\n回答を長押し →「すべて選択」→「コピー」'
                .tr(lang),
          ),
          _step('⑤', 'このアプリに戻る（回答が自動で読み込まれます）'.tr(lang)),
          _step('⑥', '「お題を取り込む」ボタンをタップして完了！'.tr(lang)),
        ],
      ),
    );
  }

  Widget _step(String number, String text) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number ',
            style: TextStyle(fontWeight: FontWeight.bold, color: primary),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _stepHighlighted(String number, Widget textWidget, String subText) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$number ',
                style: TextStyle(fontWeight: FontWeight.bold, color: primary),
              ),
              Expanded(child: textWidget),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 3),
            child: Text(
              subText,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiPromptSection(String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chrome AI 用プロンプト'.tr(lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Chrome の AI モードを開き、検索欄にプロンプトをセットします（osmStroll の「Google AIで調べる」と同じ方式）。'
              .tr(lang),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(_batchPrompt),
        ),
      ],
    );
  }

  Widget _pasteEditorSection(String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI の出力（確認・編集）'.tr(lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '通常は自動で読み込まれます。うまく読み込まれない場合はここに貼り付けてください。'
              .tr(lang),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('topicImportPasteField'),
          controller: _pasteController,
          maxLines: 10,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'AI出力プレースホルダー'.tr(lang),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _canImport ? _importPastedText : null,
            icon: const Icon(Icons.download),
            label: Text('お題を取り込む（インポート）'.tr(lang)),
          ),
        ),
      ],
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Expanded(
      child: Tooltip(
        message: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.25),
            foregroundColor: enabled
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onPrimary.withValues(alpha: 0.45),
          ),
          child: Icon(icon),
        ),
      ),
    );
  }

  Widget _countRow(String title, int count, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text('%lld 件'.trFmt(lang, ['$count'])),
        ],
      ),
    );
  }
}
