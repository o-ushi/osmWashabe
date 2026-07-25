import 'package:flutter/material.dart';

/// iOS `washabeIconButton` 相当
class WashabeIconButton extends StatelessWidget {
  const WashabeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.backgroundColor,
    this.foregroundColor,
    this.enabled = true,
    this.expand = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color? foregroundColor;
  final bool enabled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: expand ? double.infinity : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expand ? 0 : 12,
                vertical: 8,
              ),
              child: Icon(
                icon,
                color: enabled ? fg : fg.withValues(alpha: 0.38),
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
