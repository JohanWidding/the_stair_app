import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  const GridPainter({
    required this.origin,
    required this.cellSize,
  });

  final Offset origin;
  final double cellSize;

  // Grid levels in grid units (1 unit = 10 mm)
  static const _fine = 5;    // 5 cm
  static const _med = 50;    // 50 cm
  static const _coarse = 100; // 1 m

  // Minimum pixel spacing before a level fades in fully
  static const _fadeMin = 4.0;
  static const _fadeRange = 8.0;

  static double _alpha(double pixelSpacing) {
    return ((pixelSpacing - _fadeMin) / _fadeRange).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.origin != origin || old.cellSize != cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final alphaCourse = _alpha(cellSize * _coarse);
    final alphaMed    = _alpha(cellSize * _med)    * 0.85;
    final alphaFine   = _alpha(cellSize * _fine)   * 0.65;

    if (alphaCourse > 0) _drawLevel(canvas, size, _coarse, alphaCourse * 0.45);
    if (alphaMed > 0)    _drawLevel(canvas, size, _med,    alphaMed    * 0.30);
    if (alphaFine > 0)   _drawLevel(canvas, size, _fine,   alphaFine   * 0.20);
  }

  void _drawLevel(Canvas canvas, Size size, int step, double alpha) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, alpha)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final s = step.toDouble();
    final firstGx = (((-origin.dx / cellSize) / s).floor() * s) - s;
    final lastGx  = (((size.width - origin.dx) / cellSize / s).ceil() * s) + s;
    final firstGy = (((-origin.dy / cellSize) / s).floor() * s) - s;
    final lastGy  = (((size.height - origin.dy) / cellSize / s).ceil() * s) + s;

    for (var gx = firstGx; gx <= lastGx; gx += s) {
      final x = origin.dx + gx * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var gy = firstGy; gy <= lastGy; gy += s) {
      final y = origin.dy + gy * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
}
