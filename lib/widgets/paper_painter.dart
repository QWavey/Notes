import 'package:flutter/material.dart';
import '../models/enums.dart';

class PaperPainter extends CustomPainter {
  final PaperType paperType;

  PaperPainter(this.paperType);

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bg = _backgroundColor;
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    switch (paperType) {
      case PaperType.plainWhite:
      case PaperType.plainYellow:
        break;
      case PaperType.ruledWhite:
      case PaperType.ruledYellow:
        _drawRuled(canvas, size);
        break;
      case PaperType.gridWhite:
      case PaperType.gridYellow:
        _drawGrid(canvas, size);
        break;
      case PaperType.dottedWhite:
      case PaperType.dottedYellow:
        _drawDotted(canvas, size);
        break;
    }
  }

  Color get _backgroundColor {
    switch (paperType) {
      case PaperType.plainYellow:
      case PaperType.ruledYellow:
      case PaperType.gridYellow:
      case PaperType.dottedYellow:
        return const Color(0xFFFFFDE7);
      default:
        return Colors.white;
    }
  }

  void _drawRuled(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFB0C4DE)
      ..strokeWidth = 0.8;
    const spacing = 28.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    // Red margin line
    final marginPaint = Paint()
      ..color = const Color(0xFFFF6B6B).withOpacity(0.5)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        const Offset(60, 0), Offset(60, size.height), marginPaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFB0C4DE)
      ..strokeWidth = 0.6;
    const spacing = 28.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    // Red margin line
    final marginPaint = Paint()
      ..color = const Color(0xFFFF6B6B).withOpacity(0.5)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        const Offset(60, 0), Offset(60, size.height), marginPaint);
  }

  void _drawDotted(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    for (double y = spacing; y < size.height; y += spacing) {
      for (double x = spacing; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.paperType != paperType;
}
