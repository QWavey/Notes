import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/canvas_item.dart';
import '../models/enums.dart';

// ---------------------------------------------------------------------------
// ShapePainter
// ---------------------------------------------------------------------------

class ShapePainter extends CustomPainter {
  final List<ShapeItem> shapes;
  final String? selectedId;
  final DrawTool tool;
  final ShapeItem? ghost;

  ShapePainter({
    required this.shapes,
    this.selectedId,
    required this.tool,
    this.ghost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      _drawShape(canvas, shape, shape.id == selectedId, alpha: 255);
    }
    if (ghost != null) {
      _drawShape(canvas, ghost!, false, alpha: 90);
    }
  }

  void _drawShape(Canvas canvas, ShapeItem shape, bool selected,
      {int alpha = 255}) {
    final color = Color(shape.colorValue).withAlpha(alpha);
    final paint = Paint()
      ..color = color
      ..strokeWidth = shape.strokeWidth
      ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

    switch (shape.shapeType) {
      case 'rectangle':
        canvas.drawRect(rect, paint);
        break;
      case 'circle':
        canvas.drawOval(rect, paint);
        break;
      // unified triangle — resizable in both directions
      case 'triangle':
      case 'isoscelesTriangle':
        _drawIsoscelesTriangle(canvas, rect, paint);
        break;
      // legacy shapes kept for backwards compat
      case 'rightTriangle':
        _drawRightTriangle(canvas, rect, paint);
        break;
      case 'leftTriangle':
        _drawLeftTriangle(canvas, rect, paint);
        break;
      case 'arrow':
        _drawArrow(canvas, rect, paint);
        break;
      case 'lineArrow':
        _drawLineArrow(canvas, rect, paint);
        break;
      case 'star':
        _drawStar(canvas, rect, paint);
        break;
    }

    if (selected && tool == DrawTool.move) {
      _drawSelectionHandles(canvas, rect);
    }
  }

  void _drawIsoscelesTriangle(Canvas canvas, Rect r, Paint paint) {
    final path = Path()
      ..moveTo(r.left + r.width / 2, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawRightTriangle(Canvas canvas, Rect r, Paint paint) {
    final path = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawLeftTriangle(Canvas canvas, Rect r, Paint paint) {
    final path = Path()
      ..moveTo(r.right, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawLineArrow(Canvas canvas, Rect r, Paint paint) {
    // Simple horizontal arrow: line + arrowhead
    final y = r.top + r.height / 2;
    final headSize = math.min(r.width * 0.25, r.height * 0.6);
    // Line body
    canvas.drawLine(
      Offset(r.left, y),
      Offset(r.right - headSize * 0.8, y),
      paint,
    );
    // Arrowhead
    final headPath = Path()
      ..moveTo(r.right, y)
      ..lineTo(r.right - headSize, y - headSize * 0.5)
      ..lineTo(r.right - headSize, y + headSize * 0.5)
      ..close();
    canvas.drawPath(headPath,
        Paint()..color = paint.color..style = PaintingStyle.fill);
  }

  void _drawArrow(Canvas canvas, Rect r, Paint paint) {
    final cx = r.left + r.width / 2;
    final headH = r.height * 0.4;
    final bodyW = r.width * 0.15;
    final path = Path()
      ..moveTo(cx, r.top)
      ..lineTo(r.right, r.top + headH)
      ..lineTo(cx + bodyW, r.top + headH)
      ..lineTo(cx + bodyW, r.bottom)
      ..lineTo(cx - bodyW, r.bottom)
      ..lineTo(cx - bodyW, r.top + headH)
      ..lineTo(r.left, r.top + headH)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawStar(Canvas canvas, Rect r, Paint paint) {
    final cx = r.left + r.width / 2;
    final cy = r.top + r.height / 2;
    final outerR = r.shortestSide / 2;
    final innerR = outerR * 0.42;
    const pts = 5;
    final path = Path();
    for (int i = 0; i < pts * 2; i++) {
      final angle = (i * math.pi / pts) - math.pi / 2;
      final radius = i.isEven ? outerR : innerR;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSelectionHandles(Canvas canvas, Rect r) {
    canvas.drawRect(
      r.inflate(4),
      Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    final fill = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final pt in [
      r.topLeft, r.topCenter, r.topRight,
      r.centerLeft, r.centerRight,
      r.bottomLeft, r.bottomCenter, r.bottomRight,
    ]) {
      canvas.drawCircle(pt, 5.5, fill);
      canvas.drawCircle(pt, 5.5, border);
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) =>
      old.shapes != shapes ||
      old.selectedId != selectedId ||
      old.tool != tool ||
      old.ghost != ghost;
}

// ---------------------------------------------------------------------------
// Helper: convert a ShapeItem into outline points for erasing
// ---------------------------------------------------------------------------

List<Offset> shapeToPoints(ShapeItem shape, {int samples = 60}) {
  final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
  final List<Offset> pts = [];

  void addLine(Offset a, Offset b) {
    for (int i = 0; i <= samples; i++) {
      final t = i / samples;
      pts.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
    }
  }

  switch (shape.shapeType) {
    case 'rectangle':
      addLine(rect.topLeft, rect.topRight);
      addLine(rect.topRight, rect.bottomRight);
      addLine(rect.bottomRight, rect.bottomLeft);
      addLine(rect.bottomLeft, rect.topLeft);
      break;
    case 'circle':
      final cx = rect.center.dx;
      final cy = rect.center.dy;
      final rx = rect.width / 2;
      final ry = rect.height / 2;
      for (int i = 0; i <= samples; i++) {
        final a = 2 * math.pi * i / samples;
        pts.add(Offset(cx + rx * math.cos(a), cy + ry * math.sin(a)));
      }
      break;
    case 'triangle':
    case 'isoscelesTriangle':
      final apex = Offset(rect.left + rect.width / 2, rect.top);
      addLine(apex, rect.bottomRight);
      addLine(rect.bottomRight, rect.bottomLeft);
      addLine(rect.bottomLeft, apex);
      break;
    case 'rightTriangle':
      addLine(rect.topLeft, rect.bottomRight);
      addLine(rect.bottomRight, rect.bottomLeft);
      addLine(rect.bottomLeft, rect.topLeft);
      break;
    case 'leftTriangle':
      addLine(rect.topRight, rect.bottomRight);
      addLine(rect.bottomRight, rect.bottomLeft);
      addLine(rect.bottomLeft, rect.topRight);
      break;
    case 'arrow':
      final cx = rect.left + rect.width / 2;
      final headH = rect.height * 0.4;
      final bodyW = rect.width * 0.15;
      final verts = [
        Offset(cx, rect.top),
        Offset(rect.right, rect.top + headH),
        Offset(cx + bodyW, rect.top + headH),
        Offset(cx + bodyW, rect.bottom),
        Offset(cx - bodyW, rect.bottom),
        Offset(cx - bodyW, rect.top + headH),
        Offset(rect.left, rect.top + headH),
        Offset(cx, rect.top),
      ];
      for (int i = 0; i < verts.length - 1; i++) addLine(verts[i], verts[i+1]);
      break;
    case 'star':
      final cx2 = rect.left + rect.width / 2;
      final cy2 = rect.top + rect.height / 2;
      final or2 = rect.shortestSide / 2;
      final ir2 = or2 * 0.42;
      const pts5 = 5;
      final starVerts = List.generate(pts5 * 2, (i) {
        final angle = (i * math.pi / pts5) - math.pi / 2;
        final r = i.isEven ? or2 : ir2;
        return Offset(cx2 + r * math.cos(angle), cy2 + r * math.sin(angle));
      });
      for (int i = 0; i < starVerts.length; i++) {
        addLine(starVerts[i], starVerts[(i + 1) % starVerts.length]);
      }
      break;
  }
  return pts;
}

// ---------------------------------------------------------------------------
// Lasso painter
// ---------------------------------------------------------------------------

class LassoPainter extends CustomPainter {
  final List<Offset> points;
  final bool closed;
  /// Animated offset 0.0–1.0 for marching-ants effect.  Pass a [Listenable]
  /// and update this field each tick to animate.
  final double marchOffset;
  LassoPainter(this.points, {this.closed = false, this.marchOffset = 0.0});

  // FIX: draw the actual lasso points as a smooth closed path instead of an
  // inflated ellipse, so the selection outline matches what the user drew.
  Path _buildClosedPath() {
    if (points.length < 3) return Path();
    // Start at midpoint between last and first point for smooth join
    final start = Offset(
      (points.last.dx + points.first.dx) / 2,
      (points.last.dy + points.first.dy) / 2,
    );
    final path = Path()..moveTo(start.dx, start.dy);
    for (int i = 0; i < points.length; i++) {      
      final next = points[(i + 1) % points.length];
      final mid = Offset(
        (points[i].dx + next.dx) / 2,
        (points[i].dy + next.dy) / 2,
      );
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  Path _buildDrawingPath() {
    if (points.length < 2) return Path();
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length - 1; i++) {
      final mid = Offset(
        (points[i].dx + points[i + 1].dx) / 2,
        (points[i].dy + points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = closed ? _buildClosedPath() : _buildDrawingPath();
    final metrics = path.computeMetrics();
    const dashLen = 9.0;
    const gapLen = 5.0;
    final dashPaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    final period = dashLen + gapLen;
    final phase = (marchOffset % 1.0) * period;

    for (final metric in metrics) {
      // Start negative so the pattern slides in smoothly.
      double distance = -phase;
      bool draw = phase < dashLen;

      while (distance < metric.length) {
        final len = draw ? dashLen : gapLen;
        final start = math.max(0.0, distance);
        final end = math.min(distance + len, metric.length);
        if (draw && end > start) {
          canvas.drawPath(metric.extractPath(start, end), dashPaint);
        }
        distance += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(LassoPainter old) =>
      old.points != points || old.closed != closed ||
      old.marchOffset != marchOffset;
}
