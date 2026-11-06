import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// ヘルプと設定で使う開閉カード（左の色のバー・丸いアイコン・見出し・開閉の印）。
/// 閉じている間は中身を作らない。
class WashabeExpandCard extends StatelessWidget {
  const WashabeExpandCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      // 中身の高さが変わるので、バーは左の枠線で描く。
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: open,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 14, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Icon(
                        open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppColors.labelGray,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (open) child,
          ],
        ),
      ),
    );
  }
}

/// 番号付きの手順（折り返した行は文の頭にそろえる）。
class WashabeStepList extends StatelessWidget {
  const WashabeStepList({super.key, required this.steps, required this.color});

  final List<String> steps;

  /// 番号の色。
  final Color color;

  @override
  Widget build(BuildContext context) {
    const height = 1.45;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      height: height,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 14,
                      height: height,
                      color: AppColors.labelGray,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
