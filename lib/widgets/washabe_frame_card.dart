import 'package:flutter/material.dart';

import '../models/appearance_models.dart';

/// iOS `WashabeFrameCard` 相当
class WashabeFrameCard extends StatelessWidget {
  const WashabeFrameCard({
    super.key,
    required this.style,
    required this.child,
  });

  final FrameResolvedStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: style.usesLightText
            ? const ColorScheme.dark()
            : const ColorScheme.light(),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: style.readablePrimaryText),
        child: IconTheme(
          data: IconThemeData(color: style.readablePrimaryText),
          // Container が BoxDecoration を持ち高さを確実に確保する
          // （以前は DecoratedBox(child: SizedBox(width: inf)) で高さ0になっていた）
          child: Container(
            decoration: BoxDecoration(
              color: style.cardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: style.cardBorder,
                width: style.borderWidth,
              ),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 8,
                  top: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: style.accentStrip,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const SizedBox(width: 4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
