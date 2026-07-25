import 'package:flutter/material.dart';

import '../models/appearance_models.dart';
import '../theme/appearance_resolver.dart';

/// アプリ固定のデフォルト外見（ユーザー切替なし）
class AppAppearance {
  const AppAppearance();

  static const brandBlue = AppearanceResolver.brandBlue;

  Color get accentColor => AppearanceResolver.accentColor;

  Color sceneColorFor(Brightness platformBrightness) =>
      AppearanceResolver.sceneColor(platformBrightness);

  Brightness effectiveColorScheme(Brightness platformBrightness) {
    return isLightBackground(sceneColorFor(platformBrightness))
        ? Brightness.light
        : Brightness.dark;
  }

  FrameResolvedStyle resolvedFrameStyle() => AppearanceResolver.resolveFrame();

  Color readableAccent(Color surface) =>
      AppearanceResolver.readableAccent(accentColor, surface);

  Color accentChipFill(Color surface, {bool selected = false}) =>
      AppearanceResolver.accentChipFill(
        accentColor,
        surface,
        selected: selected,
      );

  Color subtleFill(Color surface, double opacity) {
    if (isLightBackground(surface)) {
      return Colors.black.withValues(alpha: opacity * 0.55);
    }
    return Colors.white.withValues(alpha: opacity);
  }

  bool isLightBackground(Color color) => color.computeLuminance() > 0.18;

  Color foregroundOn(Color background) {
    return isLightBackground(background) ? Colors.black87 : Colors.white;
  }

  Color mutedOn(Color background) {
    return isLightBackground(background)
        ? const Color.fromRGBO(97, 97, 107, 1)
        : Colors.white.withValues(alpha: 0.75);
  }
}
