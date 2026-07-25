import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/topic.dart';
import '../theme/app_colors.dart';

/// iOS `Picker(.menu)` + 「分野」ラベル相当（ボトムシートで選択、見た目はインライン）
class TopicCategoryPicker extends StatelessWidget {
  const TopicCategoryPicker({
    super.key,
    required this.category,
    required this.languageCode,
    required this.foregroundColor,
    required this.onChanged,
    this.availableCategories,
  });

  final TopicCategory category;
  final String languageCode;
  final Color foregroundColor;
  final ValueChanged<TopicCategory> onChanged;
  /// null のときは全カテゴリを表示する
  final List<TopicCategory>? availableCategories;

  Future<void> _openPicker(BuildContext context) async {
    final categories = availableCategories ?? TopicCategory.values;
    final sheetBg = Theme.of(context).dialogTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final selected = await showModalBottomSheet<TopicCategory>(
      context: context,
      useRootNavigator: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '分野'.tr(languageCode),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in categories)
                  _CategoryRow(
                    label: item.label.tr(languageCode),
                    selected: item == category,
                    textColor: textColor,
                    onTap: () => Navigator.of(sheetContext).pop(item),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '分野'.tr(languageCode),
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  category.label.tr(languageCode),
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: foregroundColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            if (selected) const Icon(Icons.check, color: AppColors.blue),
          ],
        ),
      ),
    );
  }
}
