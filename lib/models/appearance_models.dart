import 'package:flutter/material.dart';

/// カード枠の解決済みスタイル（デフォルト＝パステル）
class FrameResolvedStyle {
  const FrameResolvedStyle({
    required this.cardFill,
    required this.cardBorder,
    required this.accentStrip,
    required this.borderWidth,
    required this.readablePrimaryText,
    required this.readableSecondaryText,
    required this.usesLightText,
  });

  final Color cardFill;
  final Color cardBorder;
  final Color accentStrip;
  final double borderWidth;
  final Color readablePrimaryText;
  final Color readableSecondaryText;
  final bool usesLightText;
}
