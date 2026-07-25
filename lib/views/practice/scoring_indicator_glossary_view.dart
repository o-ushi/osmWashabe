import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

class ScoringIndicatorGlossaryView extends StatefulWidget {
  const ScoringIndicatorGlossaryView({super.key, required this.lang});

  final String lang;

  @override
  State<ScoringIndicatorGlossaryView> createState() =>
      _ScoringIndicatorGlossaryViewState();
}

class _ScoringIndicatorGlossaryViewState
    extends State<ScoringIndicatorGlossaryView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final unitLabel = '字/分'.tr(lang);
    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: WashabeSubpageScaffold(
        title: '各指標の定義'.tr(lang),
        leading: const SizedBox.shrink(),
        body: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _IndicatorCard(
              lang: lang,
              name: '枠あたりの発話量'.tr(lang),
              definitionKey: '指標定義_枠あたりの発話量',
              thresholds: [
                (level: 'Lv.2', condition: '< 85$unitLabel'),
                (level: 'Lv.3', condition: '85〜154$unitLabel'),
                (level: 'Lv.4', condition: '≥ 155$unitLabel'),
              ],
            ),
            const SizedBox(height: 12),
            _IndicatorCard(
              lang: lang,
              name: '時間の利用率'.tr(lang),
              definitionKey: '指標定義_時間の利用率',
              thresholds: [
                (level: 'Lv.2', condition: '≤ 38%'),
                (level: 'Lv.3', condition: '39〜48%'),
                (level: 'Lv.4', condition: '≥ 49%'),
              ],
            ),
            const SizedBox(height: 12),
            _IndicatorCard(
              lang: lang,
              name: '推定沈黙の割合'.tr(lang),
              definitionKey: '指標定義_推定沈黙の割合',
              thresholds: [
                (level: 'Lv.2', condition: '≥ 62%'),
                (level: 'Lv.3', condition: '45〜61%'),
                (level: 'Lv.4', condition: '< 45%'),
              ],
            ),
            const SizedBox(height: 12),
            _IndicatorCard(
              lang: lang,
              name: '複雑度'.tr(lang),
              definitionKey: '指標定義_複雑度',
              thresholds: [
                (level: 'Lv.1', condition: '0%'),
                (level: 'Lv.2', condition: '1〜10%'),
                (level: 'Lv.3', condition: '11〜33%'),
                (level: 'Lv.4', condition: '> 33%'),
              ],
            ),
            const SizedBox(height: 12),
            _IndicatorCard(
              lang: lang,
              name: '丁寧語検出数'.tr(lang),
              definitionKey: '指標定義_丁寧語の検出数',
              thresholds: null,
            ),
            const SizedBox(height: 20),
            Text(
              '各指標の定義_注記'.tr(lang),
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  const _IndicatorCard({
    required this.lang,
    required this.name,
    required this.definitionKey,
    required this.thresholds,
  });

  final String lang;
  final String name;
  final String definitionKey;
  final List<({String level, String condition})>? thresholds;

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
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              definitionKey.tr(lang),
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.75),
                height: 1.5,
              ),
            ),
            if (thresholds != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                '各指標の定義_閾値'.tr(lang),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 6),
              for (final t in thresholds!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _LevelBadge(t.level),
                      const SizedBox(width: 10),
                      Text(t.condition, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                '各指標の定義_参考のみ'.tr(lang),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge(this.level);

  final String level;

  static Color _color(String level) => switch (level) {
        'Lv.4' => AppColors.green,
        'Lv.3' => AppColors.blue,
        'Lv.2' => const Color(0xFFFF9500),
        _ => const Color(0xFFAEAEB2),
      };

  @override
  Widget build(BuildContext context) {
    final c = _color(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        level,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}
