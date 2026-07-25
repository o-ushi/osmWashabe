import 'package:flutter/material.dart';

import '../controllers/practice_controller.dart';
import '../l10n/app_strings.dart';
import '../models/appearance_models.dart';
import '../models/practice_models.dart';
import '../notifiers/app_appearance.dart';
import 'washabe_frame_card.dart';
import 'washabe_icon_button.dart';

/// iOS `timerSection` 相当
class WashabeTimerSection extends StatelessWidget {
  const WashabeTimerSection({
    super.key,
    required this.controller,
    required this.appearance,
    required this.scene,
    required this.frameStyle,
    required this.accent,
    required this.languageCode,
  });

  final PracticeController controller;
  final AppAppearance appearance;
  final Color scene;
  final FrameResolvedStyle frameStyle;
  final Color accent;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final canToggle = controller.isTimerRunning ||
        controller.isAwaitingSpeakingPhaseStart ||
        (!controller.isTimerFinished && controller.remainingSeconds > 0);

    final readableAccent =
        appearance.readableAccent(frameStyle.cardFill);
    final chipSelected = appearance.accentChipFill(
      frameStyle.cardFill,
      selected: controller.isTimerRunning,
    );
    final chipMuted = readableAccent.withValues(alpha: 0.12);

    return WashabeFrameCard(
      style: frameStyle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.isInInterval) ...[
            Text(
              '次の問題まで'.tr(languageCode),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: frameStyle.readableSecondaryText,
              ),
            ),
            Text(
              '${controller.intervalRemainingSeconds}',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: frameStyle.readableSecondaryText,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: WashabeIconButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: 'スタート'.tr(languageCode),
                    onPressed: null,
                    enabled: false,
                    expand: true,
                    backgroundColor: chipSelected,
                    foregroundColor: frameStyle.readablePrimaryText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WashabeIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'リセット'.tr(languageCode),
                    onPressed: controller.resetTimer,
                    expand: true,
                    backgroundColor: chipMuted,
                    foregroundColor: frameStyle.readablePrimaryText,
                  ),
                ),
              ],
            ),
          ] else ...[
            if (controller.usesTwoPhaseTimer)
              Text(
                controller.situationPhase == SituationTimerPhase.preparation
                    ? '準備'.tr(languageCode)
                    : '発話'.tr(languageCode),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: frameStyle.readableSecondaryText,
                ),
              ),
            Text(
              '${controller.remainingSeconds}',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: frameStyle.readablePrimaryText,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: WashabeIconButton(
                    icon: controller.isTimerRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: controller.isTimerRunning
                        ? 'ストップ'.tr(languageCode)
                        : 'スタート'.tr(languageCode),
                    onPressed: canToggle ? controller.toggleTimer : null,
                    enabled: canToggle,
                    expand: true,
                    backgroundColor: chipSelected,
                    foregroundColor: frameStyle.readablePrimaryText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WashabeIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'リセット'.tr(languageCode),
                    onPressed: controller.resetTimer,
                    expand: true,
                    backgroundColor: chipMuted,
                    foregroundColor: frameStyle.readablePrimaryText,
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
