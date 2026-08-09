import 'package:flutter/material.dart';

import '../models/appearance_models.dart';

/// デフォルト外見（標準テーマ・パステル枠）の解決。
/// シーン色は osmGradus / osmGenki と同様、端末の明暗設定に依存しない。
abstract final class AppearanceResolver {
  static const brandBlue = Color.fromRGBO(61, 89, 147, 1);
  static const accentColor = Color(0xFF007AFF);

  /// 固定のシーン背景色（昼夜で変えない）。
  static Color get sceneColor => brandBlue;

  static FrameResolvedStyle resolveFrame() {
    const fill = Color.fromRGBO(255, 250, 242, 1);
    return const FrameResolvedStyle(
      cardFill: fill,
      cardBorder: Color.fromRGBO(245, 199, 153, 1),
      accentStrip: Color.fromRGBO(255, 153, 51, 1),
      borderWidth: 1.0,
      readablePrimaryText: Color.fromRGBO(26, 26, 31, 1),
      readableSecondaryText: Color.fromRGBO(97, 97, 107, 1),
      usesLightText: false,
    );
  }

  static Color readableAccent(Color accent, Color surface) {
    final lum = surface.computeLuminance();
    if (lum > 0.18) return accent;
    return Color.lerp(accent, Colors.white, 0.25) ?? accent;
  }

  static Color accentChipFill(
    Color accent,
    Color surface, {
    bool selected = false,
  }) {
    final lum = surface.computeLuminance();
    final opacity = selected
        ? (lum > 0.18 ? 0.20 : 0.32)
        : (lum > 0.18 ? 0.10 : 0.16);
    return readableAccent(accent, surface).withValues(alpha: opacity);
  }
}
