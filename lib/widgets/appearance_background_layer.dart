import 'package:flutter/material.dart';

/// シーン色オーバーレイ＋既定テクスチャ（方眼＋ドット）
class AppearanceBackgroundLayer extends StatelessWidget {
  const AppearanceBackgroundLayer({
    super.key,
    required this.sceneColor,
    required this.colorScheme,
  });

  final Color sceneColor;
  final Brightness colorScheme;

  @override
  Widget build(BuildContext context) {
    final overlayOpacity = colorScheme == Brightness.dark ? 0.70 : 0.92;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: sceneColor.withValues(alpha: overlayOpacity)),
          CustomPaint(
            painter: _PaperDefaultPainter(
              isLight: colorScheme == Brightness.light,
            ),
            size: Size.infinite,
          ),
        ],
      ),
    );
  }
}

class _PaperDefaultPainter extends CustomPainter {
  _PaperDefaultPainter({required this.isLight});

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 28.0;
    final gOp = isLight ? 0.12 : 0.18;
    final dOp = isLight ? 0.09 : 0.12;
    final gridPaint = Paint()
      ..color = const Color.fromRGBO(140, 115, 71, 1).withValues(alpha: gOp)
      ..strokeWidth = 0.45
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var x = 0.0; x <= size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final dotPaint = Paint()
      ..color = const Color.fromRGBO(51, 140, 89, 1).withValues(alpha: dOp);
    for (var y = 0.0; y <= size.height + step; y += step) {
      for (var x = 0.0; x <= size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 0.6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperDefaultPainter oldDelegate) {
    return oldDelegate.isLight != isLight;
  }
}
