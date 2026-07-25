import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../controllers/practice_controller.dart';
import '../../data/jsst_reference_samples.dart';
import '../../l10n/app_strings.dart';
import '../../models/practice_models.dart';
import '../../notifiers/app_settings.dart';
import '../../services/app_preferences.dart';
import '../../services/jsst_calibration_service.dart';
import '../../services/jsst_scoring_service.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';
import 'scoring_indicator_glossary_view.dart';

/// 単発お題モードの発話を、JSST採点基準のうち「待遇表現」「テキストタイプ」「流暢さ」の
/// 3軸だけで近似した結果を表示する。公式の採点（文法・発音・総合レベル）は含まない。
///
/// タイマー終了直後、採点（発話確定＋スコア計算）が終わる前にこの画面を開けるよう、
/// 静的な結果ではなく [PracticeController] を直接観測してロード中→結果の状態遷移を描く。
class ScoringResultView extends StatefulWidget {
  const ScoringResultView({
    super.key,
    required this.controller,
    required this.languageCode,
    this.settings,
    this.preferences,
  });

  final PracticeController controller;
  final String languageCode;
  final AppSettingsNotifier? settings;
  final AppPreferences? preferences;

  static const _categoryLabelKeys = {
    'sonkeigo': '尊敬語',
    'kenjougo': '謙譲語',
    'teineigo': '丁寧語',
  };

  @override
  State<ScoringResultView> createState() => _ScoringResultViewState();
}

class _ScoringResultViewState extends State<ScoringResultView> {
  final _scrollController = ScrollController();
  int _historyIndex = 0;
  DateTime? _latestHeadGeneratedAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant ScoringResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    _latestHeadGeneratedAt = null;
    _historyIndex = 0;
    widget.controller.addListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    final history = widget.controller.scoringHistory;
    if (history.isEmpty) {
      _latestHeadGeneratedAt = null;
      return;
    }
    final currentHeadGeneratedAt = history.first.generatedAt;
    final previousHeadGeneratedAt = _latestHeadGeneratedAt;
    _latestHeadGeneratedAt = currentHeadGeneratedAt;
    if (previousHeadGeneratedAt == null) return;
    if (currentHeadGeneratedAt.isAfter(previousHeadGeneratedAt) &&
        _historyIndex != 0) {
      if (!mounted) return;
      setState(() => _historyIndex = 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.languageCode;
    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: WashabeSubpageScaffold(
        titleWidget: _ScoringResultTitle(lang: lang),
        leading: const SizedBox.shrink(),
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final history = widget.controller.scoringHistory;
            final clampedIndex = history.isEmpty
                ? 0
                : _historyIndex.clamp(0, history.length - 1);
            final result = history.isEmpty ? null : history[clampedIndex];
            final isLoading = widget.controller.isAwaitingScoring ||
                widget.controller.isOfflineTranscribing;
            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'JSSTの「待遇表現」「テキストタイプ」「時間の使い方（流暢さ）」の3軸を近似したものです。公式の採点とは異なります。'
                      .tr(lang),
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 20),
                if (!isLoading && history.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: clampedIndex < history.length - 1
                              ? () => setState(
                                  () => _historyIndex = clampedIndex + 1)
                              : null,
                        ),
                        Text(
                          '${history.length - clampedIndex} / ${history.length}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: clampedIndex > 0
                              ? () => setState(
                                  () => _historyIndex = clampedIndex - 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                // 録音再生ボタン: 最新結果のみ表示（ローディング中・履歴表示中は非表示）
                if (!isLoading &&
                    clampedIndex == 0 &&
                    widget.controller.lastRecordingPath != null)
                  _RecordingPlaybackCard(
                    path: widget.controller.lastRecordingPath!,
                    lang: lang,
                  ),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        if (Platform.isAndroid &&
                            (widget.controller.isOfflineTranscribing ||
                                widget.controller.scoringProgress > 0)) ...[
                          SizedBox(
                            width: double.infinity,
                            child: LinearProgressIndicator(
                              value: widget.controller.scoringProgress > 0
                                  ? widget.controller.scoringProgress
                                      .clamp(0.02, 1.0)
                                  : null,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (widget.controller.scoringProgress > 0) ...[
                            Text(
                              '${(widget.controller.scoringProgress * 100).round()}%',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.75),
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            widget.controller.scoringProgressPhaseKey.tr(lang),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                          ),
                        ] else ...[
                          const CircularProgressIndicator(),
                          if (Platform.isAndroid) ...[
                            const SizedBox(height: 16),
                            Text(
                              '採点中_音声解析'.tr(lang),
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  )
                else if (history.isEmpty)
                  Text(
                    '発話を認識できませんでした'.tr(lang),
                    style:
                        TextStyle(color: Colors.black.withValues(alpha: 0.6)),
                  )
                else
                  _ScoringResultContent(
                    result: result!,
                    lang: lang,
                    preferences:
                        (widget.settings?.developerModeEnabled ?? false)
                            ? widget.preferences
                            : null,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScoringResultTitle extends StatelessWidget {
  const _ScoringResultTitle({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).appBarTheme.foregroundColor ?? Colors.black;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '採点結果_見出し'.tr(lang),
            style: TextStyle(
              color: fg,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          Text(
            '採点結果_試験版'.tr(lang),
            style: TextStyle(
              color: fg.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoringResultContent extends StatelessWidget {
  const _ScoringResultContent({
    required this.result,
    required this.lang,
    this.preferences,
  });

  final ScoringResult result;
  final String lang;
  final AppPreferences? preferences;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JudgmentSummaryCard(result: result, lang: lang),
        const SizedBox(height: 16),
        _ReferenceComparisonCard(result: result, lang: lang),
        const SizedBox(height: 16),
        _SectionCard(
          title: '発話内容'.tr(lang),
          child: Text(
            result.fullTranscript.isEmpty ? '—' : result.fullTranscript,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '待遇表現'.tr(lang),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final category in result.keigo.categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _KeigoCategoryRow(category: category, lang: lang),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'テキストタイプ'.tr(lang),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetricRow(
                label: '発話単位数'.tr(lang),
                value: '${result.complexity.totalUnits}',
              ),
              _MetricRow(
                label: '複文・重文の数'.tr(lang),
                value: '${result.complexity.complexUnitCount}',
              ),
              _MetricRow(
                label: '複雑度'.tr(lang),
                value: '${(result.complexity.complexityRatio * 100).round()}%',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '時間の使い方'.tr(lang),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetricRow(
                label: '発話枠'.tr(lang),
                value: '${result.fluency.allottedSeconds}${'秒'.tr(lang)}',
              ),
              _MetricRow(
                label: '発話文字数'.tr(lang),
                value: '${result.fluency.spokenCharacterCount}',
              ),
              _MetricRow(
                label: '枠あたりの発話量'.tr(lang),
                value:
                    '${result.fluency.charactersPerAllottedMinute.round()}${'字/分'.tr(lang)}',
              ),
              _MetricRow(
                label: '推定発話時間'.tr(lang),
                value:
                    '${result.fluency.estimatedSpeechSeconds.round()}${'秒'.tr(lang)}',
              ),
              _MetricRow(
                label: '時間の利用率'.tr(lang),
                value: '${(result.fluency.timeUtilization * 100).round()}%',
              ),
              _MetricRow(
                label: '推定沈黙の割合'.tr(lang),
                value: '${(result.fluency.silenceRatio * 100).round()}%',
              ),
              _MetricRow(
                label: '長い沈黙（4秒以上）'.tr(lang),
                value: '${result.fluency.longPauseCount}${'回'.tr(lang)}',
              ),
              if (result.fluency.timeToFirstSpeechSeconds > 0)
                _MetricRow(
                  label: '最初の発話まで'.tr(lang),
                  value:
                      '${result.fluency.timeToFirstSpeechSeconds.toStringAsFixed(1)}${'秒'.tr(lang)}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              fullscreenDismissRoute<void>(
                builder: (_) => ScoringIndicatorGlossaryView(lang: lang),
              ),
            ),
            child: Text('${'各指標の定義'.tr(lang)} ›'),
          ),
        ),
        if (preferences != null) ...[
          const SizedBox(height: 8),
          _CalibrationCard(
            appLevel: JsstScoringService.combinedReferenceLevel(result),
            preferences: preferences!,
            lang: lang,
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              softWrap: true,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeigoCategoryRow extends StatelessWidget {
  const _KeigoCategoryRow({required this.category, required this.lang});

  final KeigoCategoryResult category;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final label = (ScoringResultView._categoryLabelKeys[category.category] ??
            category.category)
        .tr(lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (category.matchedExpressions.isEmpty)
          Text(
            '検出された表現はありません'.tr(lang),
            style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final expression in category.matchedExpressions)
                Chip(
                  label: Text(expression),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _LabelValueRow(
      label: label,
      value: value,
      valueBold: true,
    );
  }
}

/// ラベル＋値の2列行。長い文言・文字拡大でも折り返してオーバーフローしない。
class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({
    required this.label,
    required this.value,
    this.valueBold = false,
  });

  final String label;
  final String value;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.87),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontWeight: valueBold ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JudgmentSummaryCard extends StatelessWidget {
  const _JudgmentSummaryCard({required this.result, required this.lang});

  final ScoringResult result;
  final String lang;

  String _levelText(ScoringResult result, int? combined) {
    if (combined != null) {
      return JsstReferenceSamples.levelLabel(combined, lang);
    }
    if (result.fluency.spokenCharacterCount == 0) return '—';
    final messageKey =
        JsstScoringService.referenceLevelEligibility(result).messageKey;
    if (messageKey != null) return messageKey.tr(lang);
    return '—';
  }

  String _keigoText() {
    final v = result.keigo.varietyScore;
    if (v == 0) {
      if (JsstScoringService.keigoPossiblyMissedByStt(result)) {
        return '丁寧語は検出されず（STTがです/ますを落とした可能性）'.tr(lang);
      }
      return '敬語の使用は検出されませんでした'.tr(lang);
    }
    if (v == 1) return '丁寧語のみ'.tr(lang);
    if (v == 2) {
      final hasSonkeigo = result.keigo.categories.any(
          (c) => c.category == 'sonkeigo' && c.matchedExpressions.isNotEmpty);
      return hasSonkeigo ? '丁寧語＋尊敬語'.tr(lang) : '丁寧語＋謙譲語'.tr(lang);
    }
    return '尊敬語・謙譲語・丁寧語のすべてを使用'.tr(lang);
  }

  String _complexityText() {
    final c = result.complexity;
    if (c.totalUnits == 0) return '—';
    if (c.complexityRatio == 0) return '単文のみ'.tr(lang);
    if (c.complexityRatio <= 0.10) return '単文が中心'.tr(lang);
    if (c.complexityRatio <= 0.33) return '複文・重文を使用'.tr(lang);
    return '複文・重文が中心'.tr(lang);
  }

  String _fluencyText() {
    final f = result.fluency;
    if (f.spokenCharacterCount == 0) return '発話が検出されませんでした'.tr(lang);
    if (f.timeUtilization >= 0.48 && f.silenceRatio < 0.45) {
      return '枠をよく使って話している'.tr(lang);
    }
    if (f.timeUtilization >= 0.38 || f.charactersPerAllottedMinute >= 85) {
      return 'ある程度まとめて話している'.tr(lang);
    }
    return '沈黙が多く、発話量が少ない'.tr(lang);
  }

  @override
  Widget build(BuildContext context) {
    final combined = JsstScoringService.combinedReferenceLevel(result);

    return _SectionCard(
      title: '判定まとめ'.tr(lang),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JudgmentRow(label: '待遇表現の幅'.tr(lang), value: _keigoText()),
          _JudgmentRow(label: 'テキストの複雑さ'.tr(lang), value: _complexityText()),
          _JudgmentRow(label: '時間の使い方'.tr(lang), value: _fluencyText()),
          const Divider(height: 24),
          _JudgmentRow(
            label: '参考レベル感'.tr(lang),
            value: _levelText(result, combined),
            valueBold: true,
          ),
          const SizedBox(height: 4),
          Text(
            '3軸の参考値。公式採点とは大きく異なる場合があります。'.tr(lang),
            style: TextStyle(
                fontSize: 11, color: Colors.black.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

class _ReferenceComparisonCard extends StatelessWidget {
  const _ReferenceComparisonCard({required this.result, required this.lang});

  final ScoringResult result;
  final String lang;

  String _teineigoCell(ScoringResult scoring, {required bool isUser}) {
    final count = scoring.keigo.categories
        .where((c) => c.category == 'teineigo')
        .fold(0, (sum, c) => sum + c.matchedExpressions.length);
    if (count > 0) return '$count';
    if (isUser && JsstScoringService.keigoPossiblyMissedByStt(scoring)) {
      return '0*';
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final userLevel = JsstScoringService.combinedReferenceLevel(result);
    final allottedSeconds = JsstReferenceSamples.normalizeAllottedSeconds(
      result.session?.allottedSeconds ?? result.fluency.allottedSeconds,
    );
    final benchmarks = JsstReferenceSamples.forAllottedSeconds(allottedSeconds);
    final level4 = benchmarks.level4;
    final level9 = benchmarks.level9;

    return _SectionCard(
      title: '参考サンプルとの比較'.tr(lang),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '参考サンプル_説明'.trFmt(lang, ['$allottedSeconds']),
            style: TextStyle(
                fontSize: 12, color: Colors.black.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final baseWidth = constraints.maxWidth;
              final textScale =
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.5);
              final tableWidth = baseWidth * textScale;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: const {
                      0: FlexColumnWidth(2.4),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(1),
                    },
                    children: [
                      TableRow(
                        children: [
                          const SizedBox.shrink(),
                          _ComparisonHeader('あなた'.tr(lang), emphasized: true),
                          _ComparisonHeader('レベル4参考'.tr(lang)),
                          _ComparisonHeader('レベル9参考'.tr(lang)),
                        ],
                      ),
                      _comparisonRow(
                        '参考レベル感'.tr(lang),
                        JsstReferenceSamples.levelLabel(userLevel, lang),
                        JsstReferenceSamples.levelLabel(
                            level4.combinedLevel, lang),
                        JsstReferenceSamples.levelLabel(
                            level9.combinedLevel, lang),
                        emphasizeFirst: true,
                      ),
                      _comparisonRow(
                        '枠あたりの発話量'.tr(lang),
                        '${result.fluency.charactersPerAllottedMinute.round()}',
                        '${level4.result.fluency.charactersPerAllottedMinute.round()}',
                        '${level9.result.fluency.charactersPerAllottedMinute.round()}',
                      ),
                      _comparisonRow(
                        '時間の利用率'.tr(lang),
                        '${(result.fluency.timeUtilization * 100).round()}%',
                        '${(level4.result.fluency.timeUtilization * 100).round()}%',
                        '${(level9.result.fluency.timeUtilization * 100).round()}%',
                      ),
                      _comparisonRow(
                        '推定沈黙の割合'.tr(lang),
                        '${(result.fluency.silenceRatio * 100).round()}%',
                        '${(level4.result.fluency.silenceRatio * 100).round()}%',
                        '${(level9.result.fluency.silenceRatio * 100).round()}%',
                      ),
                      _comparisonRow(
                        '複雑度'.tr(lang),
                        '${(result.complexity.complexityRatio * 100).round()}%',
                        '${(level4.result.complexity.complexityRatio * 100).round()}%',
                        '${(level9.result.complexity.complexityRatio * 100).round()}%',
                      ),
                      _comparisonRow(
                        '丁寧語検出数'.tr(lang),
                        _teineigoCell(result, isUser: true),
                        _teineigoCell(level4.result, isUser: false),
                        _teineigoCell(level9.result, isUser: false),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (JsstScoringService.keigoPossiblyMissedByStt(result)) ...[
            const SizedBox(height: 8),
            Text(
              '* ${'丁寧語は検出されず（STTがです/ますを落とした可能性）'.tr(lang)}',
              style: TextStyle(
                  fontSize: 11, color: Colors.black.withValues(alpha: 0.45)),
            ),
          ],
          const SizedBox(height: 8),
          for (final sample in benchmarks.all)
            Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${sample.shortLabel(lang)}: ${'参考抜粋を見る'.tr(lang)}',
                    softWrap: true,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        sample.excerpt,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  TableRow _comparisonRow(
    String label,
    String user,
    String level4,
    String level9, {
    bool emphasizeFirst = false,
  }) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            softWrap: true,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
          ),
        ),
        _ComparisonCell(user, emphasized: emphasizeFirst),
        _ComparisonCell(level4),
        _ComparisonCell(level9),
      ],
    );
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader(this.text, {this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        softWrap: true,
        style: TextStyle(
          fontSize: 12,
          fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
        ),
      ),
    );
  }
}

class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell(this.text, {this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        softWrap: true,
        style: TextStyle(
          fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
          fontSize: emphasized ? 14 : 13,
        ),
      ),
    );
  }
}

class _JudgmentRow extends StatelessWidget {
  const _JudgmentRow({
    required this.label,
    required this.value,
    this.valueBold = false,
  });

  final String label;
  final String value;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              value,
              style: valueBold
                  ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)
                  : const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationCard extends StatefulWidget {
  const _CalibrationCard({
    required this.appLevel,
    required this.preferences,
    required this.lang,
  });

  final int? appLevel;
  final AppPreferences preferences;
  final String lang;

  @override
  State<_CalibrationCard> createState() => _CalibrationCardState();
}

class _CalibrationCardState extends State<_CalibrationCard> {
  late int _selectedJsstLevel;

  @override
  void initState() {
    super.initState();
    final appLevel = widget.appLevel;
    _selectedJsstLevel = appLevel != null
        ? JsstCalibrationService.internalToJsstDefault(appLevel)
        : 5;
  }

  void _applyCalibration() {
    final appLevel = widget.appLevel;
    if (appLevel == null) return;
    final userInternal =
        JsstCalibrationService.jsstLevelToInternal(_selectedJsstLevel);
    final newBias = JsstCalibrationService.updateBias(
      currentBias: widget.preferences.calibrationBias,
      userInternalLevel: userInternal,
      appInternalLevel: appLevel,
    );
    widget.preferences.calibrationBias = newBias;
    widget.preferences.calibrationSampleCount =
        widget.preferences.calibrationSampleCount + 1;
    setState(() {});
  }

  void _resetCalibration() {
    widget.preferences.clearCalibration();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bias = widget.preferences.calibrationBias;
    final sampleCount = widget.preferences.calibrationSampleCount;
    final appLevel = widget.appLevel;
    final adjustedLevel = JsstCalibrationService.adjustedLevel(appLevel, bias);
    final biasLabel = JsstCalibrationService.biasLabel(bias);
    final biasSign = bias >= 0 ? '+' : '';

    final lang = widget.lang;
    return _SectionCard(
      title: 'キャリブレーション（開発者）'.tr(lang),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (appLevel == null)
            Text(
              '参考レベルが算出できませんでした。キャリブレーションは利用できません。'.tr(lang),
              style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
            )
          else ...[
            _LabelValueRow(
              label: '補正係数'.tr(lang),
              value: '$biasSign${bias.toStringAsFixed(2)}',
              valueBold: true,
            ),
            _LabelValueRow(
              label: '評価傾向'.tr(lang),
              value: biasLabel.tr(lang),
              valueBold: true,
            ),
            _LabelValueRow(
              label: '学習回数'.tr(lang),
              value: '$sampleCount ${'回'.tr(lang)}',
            ),
            if (adjustedLevel != null)
              _LabelValueRow(
                label: '補正後レベル'.tr(lang),
                value: JsstReferenceSamples.levelLabel(adjustedLevel, lang),
                valueBold: true,
              ),
            const Divider(height: 24),
            Text(
              '自己評価を入力 (JSST 1–10)'.tr(lang),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('1',
                    style:
                        TextStyle(color: Colors.black.withValues(alpha: 0.5))),
                Expanded(
                  child: Slider(
                    value: _selectedJsstLevel.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_selectedJsstLevel',
                    onChanged: (v) =>
                        setState(() => _selectedJsstLevel = v.round()),
                  ),
                ),
                Text('10',
                    style:
                        TextStyle(color: Colors.black.withValues(alpha: 0.5))),
              ],
            ),
            Center(
              child: Text(
                'JSST $_selectedJsstLevel',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _resetCalibration,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text('リセット'.tr(lang)),
                ),
                ElevatedButton(
                  onPressed: _applyCalibration,
                  child: Text('適用'.tr(lang)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 録音ファイルの再生コントロール。just_audio で再生。
/// [path] が null またはファイルが読み込めない場合は何も表示しない。
class _RecordingPlaybackCard extends StatefulWidget {
  const _RecordingPlaybackCard({required this.path, required this.lang});

  final String path;
  final String lang;

  @override
  State<_RecordingPlaybackCard> createState() => _RecordingPlaybackCardState();
}

class _RecordingPlaybackCardState extends State<_RecordingPlaybackCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (Platform.isIOS) {
      final audioSession = await AudioSession.instance;
      await audioSession.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      ));
      await audioSession.setActive(true);
    }
    final player = AudioPlayer();
    try {
      await player.setAudioSource(AudioSource.uri(Uri.file(widget.path)));
      if (mounted) {
        setState(() => _player = player);
      } else {
        await player.dispose();
      }
    } catch (_) {
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin required
    final player = _player;
    if (player == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _SectionCard(
        title: '録音を聞き直す'.tr(widget.lang),
        child: StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final isPlaying = state?.playing == true;
            final isCompleted =
                state?.processingState == ProcessingState.completed;
            return Row(
              children: [
                IconButton(
                  iconSize: 36,
                  icon: Icon(
                    isPlaying && !isCompleted
                        ? Icons.pause_circle
                        : Icons.play_circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () async {
                    if (isCompleted) {
                      await player.seek(Duration.zero);
                      await player.play();
                    } else if (isPlaying) {
                      await player.pause();
                    } else {
                      await player.play();
                    }
                  },
                ),
                const SizedBox(width: 4),
                StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  builder: (context, durSnap) {
                    return StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnap) {
                        final dur = durSnap.data ?? Duration.zero;
                        final pos = posSnap.data ?? Duration.zero;
                        return Text(
                          '${_fmt(pos)} / ${_fmt(dur)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
