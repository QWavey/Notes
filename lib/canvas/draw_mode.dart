import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'image_helper_io.dart'
    if (dart.library.html) 'image_helper_web.dart' as imgHelper;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../app_localizations.dart';
import '../models/canvas_item.dart';
import '../models/enums.dart';
import '../models/note_page.dart';
import '../services/storage_service.dart';
import '../services/canvas_clipboard.dart';
import '../services/export_service.dart';
import '../widgets/color_palette.dart';
import '../widgets/paper_painter.dart';
import '../widgets/shape_painter.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// App-level setting: allow finger (touch) drawing
// ---------------------------------------------------------------------------
class DrawSettings {
  DrawSettings._();
  static final DrawSettings instance = DrawSettings._();
  bool allowFingerDrawing = false; // OFF by default — pen/mouse only
}

// ---------------------------------------------------------------------------
// DrawMode
// ---------------------------------------------------------------------------

class DrawMode extends StatefulWidget {
  final NotePage page;
  final VoidCallback onDirty;
  final bool forceTextBoxTool;

  const DrawMode({
    super.key,
    required this.page,
    required this.onDirty,
    this.forceTextBoxTool = false,
  });

  @override
  State<DrawMode> createState() => DrawModeState();
}

class DrawModeState extends State<DrawMode> {
  final _storage = StorageService();

  // ── Zoom ──────────────────────────────────────────────────────────────────
  final TransformationController _xfCtrl = TransformationController();

  // ── Tool ─────────────────────────────────────────────────────────────────
  DrawTool _tool = DrawTool.pen;
  ShapeType _shapeType = ShapeType.rectangle;
  Color _color = Colors.black;
  double _penWidth = 3.0;
  double _eraserSize = 28.0;
  EraserMode _eraserMode = EraserMode.precision;
  bool _showSubMenu = false;

  // ── Ink strokes ───────────────────────────────────────────────────────────
  List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  Offset? _eraserPos;

  // ── Canvas items ──────────────────────────────────────────────────────────
  List<ShapeItem> _shapes = [];
  List<TextBoxItem> _textBoxes = [];
  List<ImageItem> _images = [];
  List<TableItem> _tables = [];

  // ── Undo/Redo ─────────────────────────────────────────────────────────────
  final List<_Snapshot> _undoStack = [];
  final List<_Snapshot> _redoStack = [];

  // ── Active pointer count (for pinch-to-zoom guard) ───────────────────────
  int _activePointers = 0;

  // ── Shape drawing ─────────────────────────────────────────────────────────
  bool _drawingShape = false;
  Offset? _shapeStart;
  ShapeItem? _ghostShape;

  // ── Lasso ─────────────────────────────────────────────────────────────────
  bool _drawingLasso = false;
  bool _lassoReady = false;
  List<Offset> _lassoPoints = [];
  Set<String> _lassoShapeIds = {};
  Set<String> _lassoTextIds = {};
  Set<String> _lassoImageIds = {};
  Set<String> _lassoTableIds = {};
  Set<int> _lassoStrokeIdxs = {};
  Offset? _lassoMoveStart;
  final Map<String, Offset> _lassoBasePos = {};
  // Menu anchor for the floating context menu (canvas coords)
  Offset? _lassoMenuCanvasPos;

  // ── Image context menu ────────────────────────────────────────────────────
  String? _imageMenuId; // which image has its menu open
  Offset? _imageMenuPos; // canvas coords of the menu

  // ── Move tool ─────────────────────────────────────────────────────────────
  String? _selectedShapeId;
  String? _selectedTextBoxId;
  String? _selectedImageId;
  String? _selectedTableId;
  Offset? _moveStart;
  double _moveBaseX = 0, _moveBaseY = 0;

  // ── TextBox controllers ───────────────────────────────────────────────────
  final Map<String, TextEditingController> _teControllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // ── Table cell controllers ────────────────────────────────────────────────
  final Map<String, TextEditingController> _cellControllers = {};
  final Map<String, FocusNode> _cellFocusNodes = {};

  // ── Image scale (pinch) ───────────────────────────────────────────────────
  final Map<String, Size> _imgScaleStart = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.forceTextBoxTool) _tool = DrawTool.textBox;
    _loadAll();
  }

  @override
  void dispose() {
    _xfCtrl.dispose();
    for (final c in _teControllers.values) c.dispose();
    for (final f in _focusNodes.values) f.dispose();
    for (final c in _cellControllers.values) c.dispose();
    for (final f in _cellFocusNodes.values) f.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Load / Save
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    final drawingJson = await _storage.loadDrawingJson(widget.page.id);
    List<_Stroke> strokes = [];
    if (drawingJson != null) {
      try {
        final list = drawingJson['strokes'] as List<dynamic>? ?? [];
        strokes = list
            .map((s) => _Stroke.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final canvasData = await _storage.loadCanvasData(widget.page.id);
    if (!mounted) return;
    setState(() {
      _strokes = strokes;
      _shapes = canvasData.shapes;
      _textBoxes = canvasData.textBoxes;
      _images = canvasData.images;
      _tables = canvasData.tables;
    });
    _initTextControllers();
    _initCellControllers();
  }

  Future<void> saveAll() async {
    try {
      await _storage.saveDrawingJson(widget.page.id, {
        'version': 1,
        'strokes': _strokes.map((s) => s.toJson()).toList(),
      });
    } catch (_) {}
    await _storage.saveCanvasData(
      widget.page.id,
      CanvasData(
          shapes: _shapes,
          textBoxes: _textBoxes,
          images: _images,
          tables: _tables),
    );
  }

  void _initTextControllers() {
    for (final tb in _textBoxes) {
      if (_teControllers.containsKey(tb.id)) continue;
      final ctrl = TextEditingController(text: tb.text);
      final focus = FocusNode();
      _teControllers[tb.id] = ctrl;
      _focusNodes[tb.id] = focus;
      ctrl.addListener(() {
        final idx = _textBoxes.indexWhere((t) => t.id == tb.id);
        if (idx >= 0) {
          _textBoxes[idx].text = ctrl.text;
          widget.onDirty();
        }
      });
    }
  }

  void _initCellControllers() {
    for (final tbl in _tables) {
      for (int r = 0; r < tbl.rows; r++) {
        for (int c = 0; c < tbl.cols; c++) {
          final key = '${tbl.id}:$r:$c';
          if (_cellControllers.containsKey(key)) continue;
          final ctrl = TextEditingController(text: tbl.cells[r][c]);
          final focus = FocusNode();
          _cellControllers[key] = ctrl;
          _cellFocusNodes[key] = focus;
          ctrl.addListener(() {
            final ti = _tables.indexWhere((t) => t.id == tbl.id);
            if (ti >= 0) {
              _tables[ti].cells[r][c] = ctrl.text;
              widget.onDirty();
            }
          });
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Undo/Redo
  // ─────────────────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(_Snapshot(
      strokes: _strokes.map((s) => s.copy()).toList(),
      shapes: _shapes.map((s) => ShapeItem.fromJson(s.toJson())).toList(),
      textBoxes:
          _textBoxes.map((t) => TextBoxItem.fromJson(t.toJson())).toList(),
      tables: _tables.map((t) => TableItem.fromJson(t.toJson())).toList(),
    ));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(_currentSnapshot());
      final snap = _undoStack.removeLast();
      setState(() {
        _strokes = snap.strokes;
        _shapes = snap.shapes;
        _textBoxes = snap.textBoxes;
        _tables = snap.tables;
      });
      _syncControllers();
    }
    widget.onDirty();
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(_currentSnapshot());
      final snap = _redoStack.removeLast();
      setState(() {
        _strokes = snap.strokes;
        _shapes = snap.shapes;
        _textBoxes = snap.textBoxes;
        _tables = snap.tables;
      });
      _syncControllers();
    }
    widget.onDirty();
  }

  _Snapshot _currentSnapshot() => _Snapshot(
        strokes: _strokes.map((s) => s.copy()).toList(),
        shapes: _shapes.map((s) => ShapeItem.fromJson(s.toJson())).toList(),
        textBoxes:
            _textBoxes.map((t) => TextBoxItem.fromJson(t.toJson())).toList(),
        tables: _tables.map((t) => TableItem.fromJson(t.toJson())).toList(),
      );

  void _syncControllers() {
    final tbIds = _textBoxes.map((t) => t.id).toSet();
    for (final k
        in _teControllers.keys.where((k) => !tbIds.contains(k)).toList()) {
      _teControllers.remove(k)?.dispose();
      _focusNodes.remove(k)?.dispose();
    }
    _initTextControllers();
    for (final k in _cellControllers.keys.toList()) {
      _cellControllers.remove(k)?.dispose();
      _cellFocusNodes.remove(k)?.dispose();
    }
    _initCellControllers();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Coordinate conversion (screen → canvas)
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert a screen-space pointer position to canvas coordinates,
  /// accounting for the current zoom/pan transform.
  Offset _toCanvas(Offset screenPos) {
    final matrix = Matrix4.copy(_xfCtrl.value);
    matrix.invert();
    // Use vector_math-style point transform: apply the inverted matrix to the point
    final dx = screenPos.dx;
    final dy = screenPos.dy;
    final m = matrix.storage;
    // 4x4 column-major: transform a 2D point (x, y, 0, 1)
    final rx = m[0] * dx + m[4] * dy + m[12];
    final ry = m[1] * dx + m[5] * dy + m[13];
    return Offset(rx, ry);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Eraser
  // ─────────────────────────────────────────────────────────────────────────

  /// Current zoom scale extracted from the transformation matrix.
  double get _zoomScale {
    final m = _xfCtrl.value.storage;
    return math.sqrt(m[0] * m[0] + m[1] * m[1]);
  }

  void _applyPrecisionErase(Offset pos) {
    // Eraser radius is in canvas coordinates, so divide screen-space size by zoom
    final r = (_eraserSize / 2) / _zoomScale;
    final List<_Stroke> result = [];
    bool changed = false;

    for (final stroke in _strokes) {
      final List<int> erased = [];
      for (int i = 0; i < stroke.points.length; i++) {
        if ((stroke.points[i] - pos).distance <= r) erased.add(i);
      }
      for (int i = 0; i < stroke.points.length - 1; i++) {
        if (_segInCircle(stroke.points[i], stroke.points[i + 1], pos, r)) {
          erased.add(i);
          erased.add(i + 1);
        }
      }
      if (erased.isEmpty) {
        result.add(stroke);
        continue;
      }
      changed = true;
      final erasedSet = erased.toSet();
      List<Offset> cur = [];
      for (int i = 0; i < stroke.points.length; i++) {
        if (erasedSet.contains(i)) {
          if (cur.length >= 2) {
            result.add(_Stroke(
                points: List.from(cur),
                color: stroke.color,
                width: stroke.width));
          }
          cur = [];
        } else {
          cur.add(stroke.points[i]);
        }
      }
      if (cur.length >= 2) {
        result.add(_Stroke(
            points: List.from(cur),
            color: stroke.color,
            width: stroke.width));
      }
    }

    // Shapes: only erase when circle hits the visible outline edges
    final List<ShapeItem> remainingShapes = [];
    for (final shape in _shapes) {
      if (_shapeOutlineHitsCircle(shape, pos, r)) {
        changed = true;
      } else {
        remainingShapes.add(shape);
      }
    }

    if (changed) {
      setState(() {
        _strokes = result;
        _shapes = remainingShapes;
      });
      widget.onDirty();
    }
  }

  void _applyStrokeErase(Offset pos) {
    final r = (_eraserSize / 2) / _zoomScale;
    bool changed = false;

    final List<_Stroke> result = _strokes.where((stroke) {
      final hit = stroke.points.any((p) => (p - pos).distance <= r) ||
          () {
            for (int i = 0; i < stroke.points.length - 1; i++) {
              if (_segInCircle(stroke.points[i], stroke.points[i + 1], pos, r))
                return true;
            }
            return false;
          }();
      if (hit) changed = true;
      return !hit;
    }).toList();

    final List<ShapeItem> remainingShapes = [];
    for (final shape in _shapes) {
      if (_shapeOutlineHitsCircle(shape, pos, r)) {
        changed = true;
      } else {
        remainingShapes.add(shape);
      }
    }

    if (changed) {
      setState(() {
        _strokes = result;
        _shapes = remainingShapes;
      });
      widget.onDirty();
    }
  }

  bool _segInCircle(Offset a, Offset b, Offset center, double r) {
    final ab = b - a;
    final ac = center - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (a - center).distance <= r;
    final t = ((ac.dx * ab.dx + ac.dy * ab.dy) / len2).clamp(0.0, 1.0);
    final closest = a + Offset(ab.dx * t, ab.dy * t);
    return (closest - center).distance <= r;
  }

  /// True only if the eraser circle intersects the shape's visible outline segments.
  bool _shapeOutlineHitsCircle(ShapeItem shape, Offset center, double r) {
    final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
    final segs = <List<Offset>>[];

    switch (shape.shapeType) {
      case 'rectangle':
        segs.addAll([
          [rect.topLeft, rect.topRight],
          [rect.topRight, rect.bottomRight],
          [rect.bottomRight, rect.bottomLeft],
          [rect.bottomLeft, rect.topLeft],
        ]);
        break;
      case 'circle':
        final cx = rect.center.dx, cy = rect.center.dy;
        final rx = rect.width / 2, ry = rect.height / 2;
        const n = 48;
        for (int i = 0; i < n; i++) {
          final a1 = 2 * math.pi * i / n;
          final a2 = 2 * math.pi * (i + 1) / n;
          segs.add([
            Offset(cx + rx * math.cos(a1), cy + ry * math.sin(a1)),
            Offset(cx + rx * math.cos(a2), cy + ry * math.sin(a2)),
          ]);
        }
        break;
      case 'isoscelesTriangle':
        final apex = Offset(rect.left + rect.width / 2, rect.top);
        segs.addAll([
          [apex, rect.bottomRight],
          [rect.bottomRight, rect.bottomLeft],
          [rect.bottomLeft, apex],
        ]);
        break;
      case 'rightTriangle':
        segs.addAll([
          [rect.topLeft, rect.bottomRight],
          [rect.bottomRight, rect.bottomLeft],
          [rect.bottomLeft, rect.topLeft],
        ]);
        break;
      case 'leftTriangle':
        segs.addAll([
          [rect.topRight, rect.bottomRight],
          [rect.bottomRight, rect.bottomLeft],
          [rect.bottomLeft, rect.topRight],
        ]);
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
        ];
        for (int i = 0; i < verts.length; i++) {
          segs.add([verts[i], verts[(i + 1) % verts.length]]);
        }
        break;
      case 'star':
        final scx = rect.left + rect.width / 2;
        final scy = rect.top + rect.height / 2;
        final or2 = rect.shortestSide / 2;
        final ir2 = or2 * 0.42;
        const pts5 = 5;
        final sv = List.generate(pts5 * 2, (i) {
          final angle = (i * math.pi / pts5) - math.pi / 2;
          final rad = i.isEven ? or2 : ir2;
          return Offset(scx + rad * math.cos(angle), scy + rad * math.sin(angle));
        });
        for (int i = 0; i < sv.length; i++) {
          segs.add([sv[i], sv[(i + 1) % sv.length]]);
        }
        break;
    }
    return segs.any((seg) => _segInCircle(seg[0], seg[1], center, r));
  }

  void _applyErase(Offset pos) {
    if (_eraserMode == EraserMode.precision) {
      _applyPrecisionErase(pos);
    } else {
      _applyStrokeErase(pos);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Coordinate helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert a canvas-space position to screen space (for overlays outside InteractiveViewer).
  Offset _toScreen(Offset canvasPos) {
    final m = _xfCtrl.value.storage;
    final sx = m[0] * canvasPos.dx + m[4] * canvasPos.dy + m[12];
    final sy = m[1] * canvasPos.dx + m[5] * canvasPos.dy + m[13];
    return Offset(sx, sy);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lasso helpers
  // ─────────────────────────────────────────────────────────────────────────

  bool _pointInPoly(Offset pt, List<Offset> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      final xi = poly[i].dx, yi = poly[i].dy;
      final xj = poly[j].dx, yj = poly[j].dy;
      if (((yi > pt.dy) != (yj > pt.dy)) &&
          (pt.dx < (xj - xi) * (pt.dy - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  void _finalizeLasso() {
    if (_lassoPoints.length < 3) {
      setState(() {
        _drawingLasso = false;
        _lassoPoints = [];
        _lassoReady = false;
      });
      return;
    }

    _lassoShapeIds = _shapes
        .where((s) => _pointInPoly(s.center, _lassoPoints))
        .map((s) => s.id)
        .toSet();
    _lassoTextIds = _textBoxes
        .where((t) => _pointInPoly(t.center, _lassoPoints))
        .map((t) => t.id)
        .toSet();
    _lassoImageIds = _images
        .where((i) => _pointInPoly(i.center, _lassoPoints))
        .map((i) => i.id)
        .toSet();
    _lassoTableIds = _tables
        .where((t) => _pointInPoly(t.center, _lassoPoints))
        .map((t) => t.id)
        .toSet();
    _lassoStrokeIdxs = {};
    for (int i = 0; i < _strokes.length; i++) {
      if (_strokes[i].points.any((p) => _pointInPoly(p, _lassoPoints))) {
        _lassoStrokeIdxs.add(i);
      }
    }

    _lassoBasePos.clear();
    for (final s in _shapes.where((s) => _lassoShapeIds.contains(s.id))) {
      _lassoBasePos['shape:${s.id}'] = Offset(s.x, s.y);
    }
    for (final t in _textBoxes.where((t) => _lassoTextIds.contains(t.id))) {
      _lassoBasePos['text:${t.id}'] = Offset(t.x, t.y);
    }
    for (final i in _images.where((i) => _lassoImageIds.contains(i.id))) {
      _lassoBasePos['img:${i.id}'] = Offset(i.x, i.y);
    }
    for (final t in _tables.where((t) => _lassoTableIds.contains(t.id))) {
      _lassoBasePos['tbl:${t.id}'] = Offset(t.x, t.y);
    }
    for (final idx in _lassoStrokeIdxs) {
      if (_strokes[idx].points.isNotEmpty) {
        _lassoBasePos['stroke:$idx'] = _strokes[idx].points.first;
      }
    }

    // Compute bounding box top-centre for menu anchor
    if (_lassoPoints.isNotEmpty) {
      double minX = _lassoPoints.first.dx, maxX = _lassoPoints.first.dx;
      double minY = _lassoPoints.first.dy;
      for (final p in _lassoPoints) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
      }
      _lassoMenuCanvasPos = Offset((minX + maxX) / 2, minY);
    }

    setState(() {
      _drawingLasso = false;
      _lassoReady = true;
    });
  }

  void _clearLasso() {
    setState(() {
      _lassoReady = false;
      _lassoPoints = [];
      _lassoShapeIds = {};
      _lassoTextIds = {};
      _lassoImageIds = {};
      _lassoTableIds = {};
      _lassoStrokeIdxs = {};
      _lassoMenuCanvasPos = null;
    });
  }

  void _applyLassoMove(Offset delta) {
    for (int i = 0; i < _shapes.length; i++) {
      if (_lassoShapeIds.contains(_shapes[i].id)) {
        _shapes[i] = _shapes[i].copyWith(
            x: _shapes[i].x + delta.dx, y: _shapes[i].y + delta.dy);
      }
    }
    for (final tb in _textBoxes) {
      if (_lassoTextIds.contains(tb.id)) {
        tb.x += delta.dx;
        tb.y += delta.dy;
      }
    }
    for (final img in _images) {
      if (_lassoImageIds.contains(img.id)) {
        img.x += delta.dx;
        img.y += delta.dy;
      }
    }
    for (final tbl in _tables) {
      if (_lassoTableIds.contains(tbl.id)) {
        tbl.x += delta.dx;
        tbl.y += delta.dy;
      }
    }
    for (final idx in _lassoStrokeIdxs) {
      final stroke = _strokes[idx];
      _strokes[idx] = _Stroke(
        points: stroke.points.map((p) => p + delta).toList(),
        color: stroke.color,
        width: stroke.width,
      );
    }
    _lassoPoints = _lassoPoints.map((p) => p + delta).toList();
    if (_lassoMenuCanvasPos != null) {
      _lassoMenuCanvasPos = _lassoMenuCanvasPos! + delta;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Clipboard
  // ─────────────────────────────────────────────────────────────────────────

  void _lassoCopy() {
    final cb = CanvasClipboard.instance;
    cb.copySelection(
      shapeList: _shapes.where((s) => _lassoShapeIds.contains(s.id)).toList(),
      textList: _textBoxes.where((t) => _lassoTextIds.contains(t.id)).toList(),
      imageList: _images.where((i) => _lassoImageIds.contains(i.id)).toList(),
      tableList: _tables.where((t) => _lassoTableIds.contains(t.id)).toList(),
      strokeList: _lassoStrokeIdxs.map((i) => _strokes[i].toJson()).toList(),
    );
    setState(() {}); // refresh paste button state
  }

  void _lassoCut() {
    _lassoCopy();
    _lassoDelete();
  }

  void _lassoDelete() {
    _pushUndo();
    final shapeIds = Set<String>.from(_lassoShapeIds);
    final textIds = Set<String>.from(_lassoTextIds);
    final imgIds = Set<String>.from(_lassoImageIds);
    final tblIds = Set<String>.from(_lassoTableIds);
    final strokeIdxs = Set<int>.from(_lassoStrokeIdxs);

    for (final id in textIds) {
      _teControllers.remove(id)?.dispose();
      _focusNodes.remove(id)?.dispose();
    }
    for (final t in _tables.where((t) => tblIds.contains(t.id))) {
      for (int r = 0; r < t.rows; r++) {
        for (int c = 0; c < t.cols; c++) {
          _cellControllers.remove('${t.id}:$r:$c')?.dispose();
          _cellFocusNodes.remove('${t.id}:$r:$c')?.dispose();
        }
      }
    }

    final newStrokes = <_Stroke>[];
    for (int i = 0; i < _strokes.length; i++) {
      if (!strokeIdxs.contains(i)) newStrokes.add(_strokes[i]);
    }

    setState(() {
      _shapes.removeWhere((s) => shapeIds.contains(s.id));
      _textBoxes.removeWhere((t) => textIds.contains(t.id));
      _images.removeWhere((i) => imgIds.contains(i.id));
      _tables.removeWhere((t) => tblIds.contains(t.id));
      _strokes = newStrokes;
    });
    _clearLasso();
    widget.onDirty();
  }

  void _lassoPaste() {
    final cb = CanvasClipboard.instance;
    if (cb.isEmpty) return;
    _pushUndo();
    const off = Offset(24, 24);

    for (final sj in cb.shapes) {
      final j = Map<String, dynamic>.from(sj);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      setState(() => _shapes.add(ShapeItem.fromJson(j)));
    }
    for (final tj in cb.textBoxes) {
      final j = Map<String, dynamic>.from(tj);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      final tb = TextBoxItem.fromJson(j);
      final ctrl = TextEditingController(text: tb.text);
      final focus = FocusNode();
      _teControllers[tb.id] = ctrl;
      _focusNodes[tb.id] = focus;
      ctrl.addListener(() {
        final idx = _textBoxes.indexWhere((t) => t.id == tb.id);
        if (idx >= 0) {
          _textBoxes[idx].text = ctrl.text;
          widget.onDirty();
        }
      });
      setState(() => _textBoxes.add(tb));
    }
    for (final ij in cb.images) {
      final j = Map<String, dynamic>.from(ij);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      setState(() => _images.add(ImageItem.fromJson(j)));
    }
    for (final tj in cb.tables) {
      final j = Map<String, dynamic>.from(tj);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      final tbl = TableItem.fromJson(j);
      setState(() => _tables.add(tbl));
      _initCellControllers();
    }
    for (final stj in cb.strokes) {
      final j = Map<String, dynamic>.from(stj);
      final pts = (j['points'] as List).map((p) {
        return {
          'x': (p['x'] as num) + off.dx,
          'y': (p['y'] as num) + off.dy
        };
      }).toList();
      j['points'] = pts;
      setState(() => _strokes.add(_Stroke.fromJson(j)));
    }
    // Clear clipboard after paste so the paste button goes grey
    CanvasClipboard.instance.clear();
    setState(() {}); // refresh paste button grey state
    widget.onDirty();
  }

  void _showCanvasPasteMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: const Text('Einfügen', style: TextStyle(fontSize: 16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: const Text('Inhalt aus Zwischenablage einfügen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _lassoPaste();
            },
            child: const Text('Einfügen'),
          ),
        ],
      ),
    );
  }

  void _copyImage(String id) {
    final img = _images.firstWhere((i) => i.id == id,
        orElse: () =>
            ImageItem(id: '', x: 0, y: 0, width: 0, height: 0, filePath: ''));
    if (img.id.isEmpty) return;
    CanvasClipboard.instance.copySelection(
      shapeList: [],
      textList: [],
      imageList: [img],
      tableList: [],
      strokeList: [],
    );
    setState(() {});
  }

  void _cutImage(String id) {
    _copyImage(id);
    _deleteImage(id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pointer handling
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns true if this pointer event should be ignored (finger when finger drawing is off).
  bool _ignoredKind(PointerDeviceKind kind) {
    if (DrawSettings.instance.allowFingerDrawing) return false;
    return kind == PointerDeviceKind.touch;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_ignoredKind(e.kind)) return;

    // Eraser button on stylus
    if (e.kind == PointerDeviceKind.stylus && e.buttons == 2) {
      setState(() {
        _tool = DrawTool.eraser;
        _showSubMenu = false;
      });
    }

    // Close image menu on any tap
    if (_imageMenuId != null) {
      setState(() {
        _imageMenuId = null;
        _imageMenuPos = null;
      });
    }

    final pos = _toCanvas(e.localPosition);

    // Lasso: if ready, start move or deselect
    if (_lassoReady) {
      if (_pointInPoly(pos, _lassoPoints)) {
        _pushUndo();
        _lassoMoveStart = pos;
        return;
      } else {
        _clearLasso();
        // If not in lasso tool, don't fall through to draw
        if (_tool != DrawTool.lasso && _tool != DrawTool.pen &&
            _tool != DrawTool.eraser && _tool != DrawTool.shape) return;
      }
    }

    switch (_tool) {
      case DrawTool.pen:
        _pushUndo();
        final stroke =
            _Stroke(points: [pos], color: _color, width: _penWidth);
        setState(() {
          _currentStroke = stroke;
          _strokes.add(stroke);
        });
        break;

      case DrawTool.eraser:
        _pushUndo();
        setState(() => _eraserPos = pos);
        _applyErase(pos);
        break;

      case DrawTool.shape:
        _pushUndo();
        setState(() {
          _drawingShape = true;
          _shapeStart = pos;
          _ghostShape = null;
        });
        break;

      case DrawTool.lasso:
        setState(() {
          _drawingLasso = true;
          _lassoReady = false;
          _lassoPoints = [pos];
        });
        break;

      case DrawTool.textBox:
        _placeTextBox(pos);
        break;

      case DrawTool.table:
        _placeTable(pos);
        break;

      case DrawTool.move:
        _handleMoveStart(pos);
        break;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_ignoredKind(e.kind)) return;
    final pos = _toCanvas(e.localPosition);

    if (_lassoReady && _lassoMoveStart != null) {
      final delta = pos - _lassoMoveStart!;
      _lassoMoveStart = pos;
      setState(() => _applyLassoMove(delta));
      widget.onDirty();
      return;
    }

    switch (_tool) {
      case DrawTool.pen:
        if (_currentStroke != null) {
          setState(() => _currentStroke!.points.add(pos));
          widget.onDirty();
        }
        break;

      case DrawTool.eraser:
        setState(() => _eraserPos = pos);
        _applyErase(pos);
        break;

      case DrawTool.shape:
        if (_drawingShape && _shapeStart != null) {
          setState(
              () => _ghostShape = _makeShape(_shapeStart!, pos, ghost: true));
        }
        break;

      case DrawTool.lasso:
        if (_drawingLasso) {
          setState(() => _lassoPoints.add(pos));
        }
        break;

      case DrawTool.move:
        if (_moveStart != null) {
          _applyMove(pos.dx - _moveStart!.dx, pos.dy - _moveStart!.dy);
        }
        break;

      default:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_ignoredKind(e.kind)) return;

    if (_lassoReady && _lassoMoveStart != null) {
      _lassoMoveStart = null;
      return;
    }

    switch (_tool) {
      case DrawTool.pen:
        setState(() => _currentStroke = null);
        widget.onDirty();
        break;

      case DrawTool.eraser:
        setState(() => _eraserPos = null);
        break;

      case DrawTool.shape:
        if (_drawingShape && _shapeStart != null) {
          final pos = _toCanvas(e.localPosition);
          final s = _makeShape(_shapeStart!, pos, ghost: false);
          if (s.width.abs() > 6 && s.height.abs() > 6) {
            setState(() => _shapes.add(s));
            widget.onDirty();
          }
          setState(() {
            _drawingShape = false;
            _shapeStart = null;
            _ghostShape = null;
          });
        }
        break;

      case DrawTool.lasso:
        _finalizeLasso();
        break;

      case DrawTool.move:
        _moveStart = null;
        break;

      default:
        break;
    }
  }

  ShapeItem _makeShape(Offset a, Offset b, {required bool ghost}) {
    final x = math.min(a.dx, b.dx);
    final y = math.min(a.dy, b.dy);
    final w = (b.dx - a.dx).abs();
    final h = (b.dy - a.dy).abs();
    return ShapeItem(
      id: ghost ? '_ghost_' : _uuid.v4(),
      shapeType: _shapeType.name,
      x: x, y: y, width: w, height: h,
      colorValue: _color.value,
      strokeWidth: _penWidth,
    );
  }

  void _handleMoveStart(Offset pos) {
    for (final s in _shapes.reversed) {
      if (Rect.fromLTWH(s.x, s.y, s.width, s.height).contains(pos)) {
        setState(() {
          _selectedShapeId = s.id;
          _selectedTextBoxId = null;
          _selectedImageId = null;
          _selectedTableId = null;
          _moveStart = pos;
          _moveBaseX = s.x;
          _moveBaseY = s.y;
        });
        return;
      }
    }
    for (final tb in _textBoxes.reversed) {
      if (Rect.fromLTWH(tb.x, tb.y, tb.width, 60).contains(pos)) {
        setState(() {
          _selectedTextBoxId = tb.id;
          _selectedShapeId = null;
          _selectedImageId = null;
          _selectedTableId = null;
          _moveStart = pos;
          _moveBaseX = tb.x;
          _moveBaseY = tb.y;
        });
        return;
      }
    }
    for (final tbl in _tables.reversed) {
      if (Rect.fromLTWH(tbl.x, tbl.y, tbl.totalWidth, tbl.totalHeight)
          .contains(pos)) {
        setState(() {
          _selectedTableId = tbl.id;
          _selectedShapeId = null;
          _selectedTextBoxId = null;
          _selectedImageId = null;
          _moveStart = pos;
          _moveBaseX = tbl.x;
          _moveBaseY = tbl.y;
        });
        return;
      }
    }
    for (final img in _images.reversed) {
      if (Rect.fromLTWH(img.x, img.y, img.width, img.height).contains(pos)) {
        setState(() {
          _selectedImageId = img.id;
          _selectedShapeId = null;
          _selectedTextBoxId = null;
          _selectedTableId = null;
          _moveStart = pos;
          _moveBaseX = img.x;
          _moveBaseY = img.y;
        });
        return;
      }
    }
    setState(() {
      _selectedShapeId = null;
      _selectedTextBoxId = null;
      _selectedImageId = null;
      _selectedTableId = null;
      _moveStart = null;
    });
  }

  void _applyMove(double dx, double dy) {
    if (_selectedShapeId != null) {
      final idx = _shapes.indexWhere((s) => s.id == _selectedShapeId);
      if (idx >= 0) {
        setState(() => _shapes[idx] =
            _shapes[idx].copyWith(x: _moveBaseX + dx, y: _moveBaseY + dy));
        widget.onDirty();
      }
    } else if (_selectedTextBoxId != null) {
      final idx = _textBoxes.indexWhere((t) => t.id == _selectedTextBoxId);
      if (idx >= 0) {
        setState(() {
          _textBoxes[idx].x = _moveBaseX + dx;
          _textBoxes[idx].y = _moveBaseY + dy;
        });
        widget.onDirty();
      }
    } else if (_selectedTableId != null) {
      final idx = _tables.indexWhere((t) => t.id == _selectedTableId);
      if (idx >= 0) {
        setState(() {
          _tables[idx].x = _moveBaseX + dx;
          _tables[idx].y = _moveBaseY + dy;
        });
        widget.onDirty();
      }
    } else if (_selectedImageId != null) {
      final idx = _images.indexWhere((i) => i.id == _selectedImageId);
      if (idx >= 0) {
        setState(() {
          _images[idx].x = _moveBaseX + dx;
          _images[idx].y = _moveBaseY + dy;
        });
        widget.onDirty();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Place helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _placeTextBox(Offset pos) {
    final id = _uuid.v4();
    final tb =
        TextBoxItem(id: id, x: pos.dx, y: pos.dy, colorValue: _color.value);
    _pushUndo();
    final ctrl = TextEditingController();
    final focus = FocusNode();
    _teControllers[id] = ctrl;
    _focusNodes[id] = focus;
    ctrl.addListener(() {
      final idx = _textBoxes.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        _textBoxes[idx].text = ctrl.text;
        widget.onDirty();
      }
    });
    setState(() => _textBoxes.add(tb));
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    widget.onDirty();
  }

  void _placeTable(Offset pos) {
    _showTableSetupDialog(pos);
  }

  Future<void> _showTableSetupDialog(Offset pos) async {
    int rows = 3, cols = 3;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Tabelle erstellen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('Zeilen: ', style: TextStyle(fontSize: 14)),
                IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        setLocal(() => rows = math.max(1, rows - 1))),
                Text('$rows',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        setLocal(() => rows = math.min(20, rows + 1))),
              ]),
              Row(children: [
                const Text('Spalten:', style: TextStyle(fontSize: 14)),
                IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        setLocal(() => cols = math.max(1, cols - 1))),
                Text('$cols',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        setLocal(() => cols = math.min(20, cols + 1))),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Erstellen')),
          ],
        ),
      ),
    ).then((result) {
      if (result == true) {
        final id = _uuid.v4();
        final tbl =
            TableItem(id: id, x: pos.dx, y: pos.dy, rows: rows, cols: cols);
        _pushUndo();
        setState(() => _tables.add(tbl));
        _initCellControllers();
        widget.onDirty();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delete helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _deleteShape(String id) {
    _pushUndo();
    setState(() {
      _shapes.removeWhere((s) => s.id == id);
      if (_selectedShapeId == id) _selectedShapeId = null;
    });
    widget.onDirty();
  }

  void _deleteTextBox(String id) {
    _pushUndo();
    _teControllers.remove(id)?.dispose();
    _focusNodes.remove(id)?.dispose();
    setState(() {
      _textBoxes.removeWhere((t) => t.id == id);
      if (_selectedTextBoxId == id) _selectedTextBoxId = null;
    });
    widget.onDirty();
  }

  void _deleteImage(String id) {
    _pushUndo();
    setState(() {
      _images.removeWhere((i) => i.id == id);
      if (_selectedImageId == id) _selectedImageId = null;
      if (_imageMenuId == id) {
        _imageMenuId = null;
        _imageMenuPos = null;
      }
    });
    widget.onDirty();
  }

  void _deleteTable(String id) {
    _pushUndo();
    final tbl = _tables.firstWhere((t) => t.id == id,
        orElse: () => TableItem(id: '', x: 0, y: 0));
    for (int r = 0; r < tbl.rows; r++) {
      for (int c = 0; c < tbl.cols; c++) {
        final key = '$id:$r:$c';
        _cellControllers.remove(key)?.dispose();
        _cellFocusNodes.remove(key)?.dispose();
      }
    }
    setState(() {
      _tables.removeWhere((t) => t.id == id);
      if (_selectedTableId == id) _selectedTableId = null;
    });
    widget.onDirty();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Import / Export
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showExportImportDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importieren / Exportieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('Importieren'),
              subtitle: const Text('PDF, Bild, Word, PowerPoint'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.showImportDialog(context, _onImport);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Exportieren'),
              subtitle: const Text('PDF, Bild, Word, PowerPoint'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.showExportDialog(context, widget.page.name);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  void _onImport(String filePath, String fileType) {
    if (['jpg', 'jpeg', 'png'].contains(fileType)) {
      _pushUndo();
      setState(() => _images.add(ImageItem(
            id: _uuid.v4(),
            x: 40,
            y: 40,
            width: 300,
            height: 220,
            filePath: filePath,
          )));
      widget.onDirty();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Datei importiert: $filePath\n(Vollvorschau wird vorbereitet)'),
            duration: const Duration(seconds: 3)),
      );
    }
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alles löschen'),
        content: const Text('Alle Zeichnungen auf dieser Seite entfernen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _pushUndo();
              for (final c in _teControllers.values) c.dispose();
              for (final f in _focusNodes.values) f.dispose();
              for (final c in _cellControllers.values) c.dispose();
              for (final f in _cellFocusNodes.values) f.dispose();
              setState(() {
                _strokes.clear();
                _shapes.clear();
                _textBoxes.clear();
                _images.clear();
                _tables.clear();
                _teControllers.clear();
                _focusNodes.clear();
                _cellControllers.clear();
                _cellFocusNodes.clear();
              });
              widget.onDirty();
            },
            child:
                const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _importImage() async {
    try {
      final xfile =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      _pushUndo();
      setState(() => _images.add(ImageItem(
            id: _uuid.v4(),
            x: 60,
            y: 60,
            width: 200,
            height: 150,
            filePath: xfile.path,
          )));
      widget.onDirty();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _exportShare() async {
    try {
      await Share.share('Exportiert aus Notes – ${widget.page.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings
  // ─────────────────────────────────────────────────────────────────────────

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Einstellungen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Fingerzeichnen erlauben'),
                subtitle: const Text(
                    'Standardmäßig sind nur Stift & Maus aktiv'),
                value: DrawSettings.instance.allowFingerDrawing,
                onChanged: (v) {
                  setLocal(
                      () => DrawSettings.instance.allowFingerDrawing = v);
                  setState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen')),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        _buildToolbar(l10n),
        if (_showSubMenu) _buildSubMenu(),
        Expanded(
          child: Stack(
            children: [
              // ── Main canvas with zoom ────────────────────────────────────
              // Finger long-press on empty canvas → paste menu
              GestureDetector(
                onLongPress: () {
                  // Only trigger for touch (finger), not pen/mouse
                  // Show paste popup at center of screen if clipboard has content
                  if (!CanvasClipboard.instance.isEmpty) {
                    _showCanvasPasteMenu();
                  }
                },
                child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  setState(() => _activePointers++);
                  if (_activePointers < 2) _onPointerDown(e);
                },
                onPointerMove: (e) {
                  if (_activePointers < 2) _onPointerMove(e);
                },
                onPointerUp: (e) {
                  _onPointerUp(e);
                  setState(
                      () => _activePointers = math.max(0, _activePointers - 1));
                },
                onPointerCancel: (_) {
                  setState(
                      () => _activePointers = math.max(0, _activePointers - 1));
                },
                child: InteractiveViewer(
                  transformationController: _xfCtrl,
                  panEnabled: false,
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                        // ── Paper background (zooms with everything) ────────
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: PaperPainter(widget.page.paperType),
                            ),
                          ),
                        ),

                        // ── Ink ────────────────────────────────────────────
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _InkPainter(strokes: _strokes),
                            ),
                          ),
                        ),

                        // ── Images ─────────────────────────────────────────
                        ..._buildImages(),

                        // ── Shapes ─────────────────────────────────────────
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: ShapePainter(
                                shapes: _shapes,
                                selectedId: _selectedShapeId,
                                tool: _tool,
                                ghost: _ghostShape,
                              ),
                            ),
                          ),
                        ),

                        // ── Shape delete handle ────────────────────────────
                        if (_tool == DrawTool.move &&
                            _selectedShapeId != null)
                          _shapeDeleteHandle(),

                        // ── Text boxes ─────────────────────────────────────
                        ..._buildTextBoxes(),

                        // ── Tables ─────────────────────────────────────────
                        ..._buildTables(),

                        // ── Lasso outline ──────────────────────────────────
                        if (_drawingLasso || _lassoReady)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: LassoPainter(_lassoPoints,
                                    closed: _lassoReady),
                              ),
                            ),
                          ),

                        // ── Eraser cursor (canvas-space, radius already in canvas coords) ──────
                        if (_tool == DrawTool.eraser && _eraserPos != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _EraserCursorPainter(
                                  position: _eraserPos!,
                                  radius: (_eraserSize / 2) / _zoomScale,
                                ),
                              ),
                            ),
                          ),

                        // ── Page info ──────────────────────────────────────
                        Positioned(
                          bottom: 8,
                          right: 60,
                          child: IgnorePointer(
                            child: Text(
                              _pageInfo(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ), // end GestureDetector (finger long-press paste)

              // ── Lasso context menu (screen-space overlay, outside Listener) ──────
              if (_lassoReady && _lassoMenuCanvasPos != null)
                Builder(builder: (_) {
                  final sp = _toScreen(_lassoMenuCanvasPos!);
                  return Positioned(
                    left: (sp.dx - 100).clamp(4.0, double.infinity),
                    top: math.max(4.0, sp.dy - 52),
                    child: _buildContextMenu(
                      onDelete: _lassoDelete,
                      onCut: _lassoCut,
                      onCopy: _lassoCopy,
                      onPaste: CanvasClipboard.instance.isEmpty
                          ? null
                          : _lassoPaste,
                    ),
                  );
                }),

              // ── Image context menu (screen-space overlay, outside Listener) ──────
              if (_imageMenuId != null && _imageMenuPos != null)
                Builder(builder: (_) {
                  final sp = _toScreen(_imageMenuPos!);
                  return Positioned(
                    left: (sp.dx - 100).clamp(4.0, double.infinity),
                    top: math.max(4.0, sp.dy - 52),
                    child: _buildContextMenu(
                      onDelete: () => _deleteImage(_imageMenuId!),
                      onCut: () => _cutImage(_imageMenuId!),
                      onCopy: () => _copyImage(_imageMenuId!),
                      onPaste: CanvasClipboard.instance.isEmpty
                          ? null
                          : _lassoPaste,
                    ),
                  );
                }),

              // ── Table add-row/col overlay buttons (screen-space, outside Listener) ──
              ..._buildTableOverlayButtons(),

              // ── Colour bubble (outside zoom) ───────────────────────────
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingColorBubble(
                  color: _color,
                  onColorChanged: (c) => setState(() => _color = c),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _pageInfo() {
    final d = widget.page.createdAt;
    final pad = (int n) => n.toString().padLeft(2, '0');
    return 'Seite ${widget.page.order + 1}  •  ${pad(d.day)}.${pad(d.month)}.${d.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Context menu widget (lasso + image)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildContextMenu({
    required VoidCallback onDelete,
    required VoidCallback onCut,
    required VoidCallback onCopy,
    VoidCallback? onPaste,
  }) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ctxBtn(Icons.delete_outline, Colors.red, 'Löschen', onDelete),
            _ctxDivider(),
            _ctxBtn(Icons.content_cut, Colors.orange.shade700, 'Ausschneiden',
                onCut),
            _ctxDivider(),
            _ctxBtn(
                Icons.copy, Colors.blue.shade700, 'Kopieren', onCopy),
            _ctxDivider(),
            _ctxBtn(
              Icons.content_paste,
              onPaste != null ? Colors.green.shade700 : Colors.grey.shade400,
              'Einfügen',
              onPaste,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctxBtn(
          IconData icon, Color color, String tooltip, VoidCallback? onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );

  Widget _ctxDivider() => Container(
        width: 1,
        height: 22,
        color: Colors.grey.shade200,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Image widgets
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildImages() {
    return _images.map((img) {
      final isSel = _selectedImageId == img.id && _tool == DrawTool.move;
      final menuOpen = _imageMenuId == img.id;
      // Track whether a pan/scale is happening to suppress long-press
      bool _isGesturing = false;
      return Positioned(
        left: img.x,
        top: img.y,
        width: img.width,
        height: img.height,
        child: GestureDetector(
          onPanStart: _tool == DrawTool.move ? (_) { _isGesturing = true; } : null,
          onPanUpdate: _tool == DrawTool.move
              ? (d) {
                  setState(() {
                    img.x += d.delta.dx;
                    img.y += d.delta.dy;
                  });
                  widget.onDirty();
                }
              : null,
          onPanEnd: _tool == DrawTool.move ? (_) { _isGesturing = false; } : null,
          // Long-press (finger only) opens the context menu
          onLongPress: () {
            if (_isGesturing) return;
            setState(() {
              _imageMenuId = img.id;
              _imageMenuPos = Offset(img.x + img.width / 2, img.y);
            });
          },
          onScaleStart: (d) {
            _isGesturing = true;
            _imgScaleStart[img.id] = Size(img.width, img.height);
          },
          onScaleUpdate: (d) {
            final base = _imgScaleStart[img.id];
            if (base == null) return;
            if (_tool == DrawTool.move) {
              setState(() {
                img.width = math.max(40, base.width * d.scale);
                img.height = math.max(30, base.height * d.scale);
                img.rotation += d.rotation * 0.3;
              });
              widget.onDirty();
            }
          },
          onScaleEnd: (_) {
            _imgScaleStart.remove(img.id);
            Future.delayed(const Duration(milliseconds: 100), () {
              _isGesturing = false;
            });
          },
          child: Transform.rotate(
            angle: img.rotation,
            child: Stack(
              children: [
                Positioned.fill(
                    child: imgHelper.buildFileImage(img.filePath)),
                if (isSel)
                  Positioned(
                      top: 0,
                      right: 0,
                      child: _delBtn(() => _deleteImage(img.id))),
                if (_tool == DrawTool.move && !menuOpen)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6)),
                      ),
                      child: const Icon(Icons.open_in_full,
                          size: 14, color: Colors.white),
                    ),
                  ),
                // Long-press hint badge
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(6)),
                    ),
                    child: const Icon(Icons.more_horiz,
                        size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TextBox widgets
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildTextBoxes() {
    return _textBoxes.map((tb) {
      final ctrl = _teControllers[tb.id];
      final focus = _focusNodes[tb.id];
      if (ctrl == null || focus == null) return const SizedBox.shrink();
      final inLasso = _lassoReady && _lassoTextIds.contains(tb.id);
      return Positioned(
        left: tb.x,
        top: tb.y,
        width: tb.width,
        child: GestureDetector(
          onPanUpdate: _tool == DrawTool.move
              ? (d) {
                  setState(() {
                    tb.x += d.delta.dx;
                    tb.y += d.delta.dy;
                  });
                  widget.onDirty();
                }
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  border: Border.all(
                    color: inLasso
                        ? Colors.blue
                        : _tool == DrawTool.move
                            ? Colors.blue.withOpacity(0.5)
                            : Colors.grey.shade300,
                    width: inLasso ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextField(
                  controller: ctrl,
                  focusNode: focus,
                  maxLines: null,
                  style: TextStyle(
                    fontSize: tb.fontSize,
                    color: Color(tb.colorValue),
                    fontWeight:
                        tb.bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle:
                        tb.italic ? FontStyle.italic : FontStyle.normal,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Type here…',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ),
              if (_tool == DrawTool.move)
                Positioned(
                    top: -10,
                    right: -10,
                    child: _delBtn(() => _deleteTextBox(tb.id))),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Table widgets
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildTables() {
    return _tables.map((tbl) {
      final isSel = _selectedTableId == tbl.id && _tool == DrawTool.move;
      final inLasso = _lassoReady && _lassoTableIds.contains(tbl.id);
      return Positioned(
        left: tbl.x,
        top: tbl.y,
        child: GestureDetector(
          onPanUpdate: _tool == DrawTool.move
              ? (d) {
                  setState(() {
                    tbl.x += d.delta.dx;
                    tbl.y += d.delta.dy;
                  });
                  widget.onDirty();
                }
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: inLasso
                        ? Colors.blue
                        : isSel
                            ? Colors.blue.withOpacity(0.7)
                            : Color(tbl.colorValue),
                    width: inLasso || isSel ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(tbl.rows, (r) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(tbl.cols, (c) {
                        final key = '${tbl.id}:$r:$c';
                        final ctrl = _cellControllers[key];
                        final focus = _cellFocusNodes[key];
                        return Container(
                          width: tbl.cellWidth,
                          height: tbl.cellHeight,
                          decoration: BoxDecoration(
                            border: Border(
                              right: c < tbl.cols - 1
                                  ? BorderSide(
                                      color: Color(tbl.colorValue),
                                      width: 0.8)
                                  : BorderSide.none,
                              bottom: r < tbl.rows - 1
                                  ? BorderSide(
                                      color: Color(tbl.colorValue),
                                      width: 0.8)
                                  : BorderSide.none,
                            ),
                          ),
                          child: ctrl != null && focus != null
                              ? TextField(
                                  controller: ctrl,
                                  focusNode: focus,
                                  style: const TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 8),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      }),
                    );
                  }),
                ),
              ),
              if (isSel || _tool == DrawTool.move)
                Positioned(
                    top: -12,
                    right: -12,
                    child: _delBtn(() => _deleteTable(tbl.id))),
            ],
          ),
        ),
      );
    }).toList();
  }

  // Screen-space overlay buttons for selected table (add row / add column)
  List<Widget> _buildTableOverlayButtons() {
    if (_tool != DrawTool.move || _selectedTableId == null) return [];
    final tblIdx = _tables.indexWhere((t) => t.id == _selectedTableId);
    if (tblIdx < 0) return [];
    final tbl = _tables[tblIdx];
    final bottomLeft = _toScreen(Offset(tbl.x, tbl.y + tbl.totalHeight));
    final topRight   = _toScreen(Offset(tbl.x + tbl.totalWidth, tbl.y));
    return [
      Positioned(
        left: bottomLeft.dx,
        top: bottomLeft.dy + 4,
        child: _tableBtn(Icons.add, 'Zeile', () {
          setState(() {
            tbl.rows++;
            tbl.cells.add(List.generate(tbl.cols, (_) => ''));
          });
          _initCellControllers();
          widget.onDirty();
        }),
      ),
      Positioned(
        left: topRight.dx + 4,
        top: topRight.dy,
        child: _tableBtn(Icons.add, 'Sp.', () {
          setState(() {
            tbl.cols++;
            for (final row in tbl.cells) row.add('');
          });
          _initCellControllers();
          widget.onDirty();
        }),
      ),
    ];
  }

  Widget _tableBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.blue.shade700),
              Text(label,
                  style:
                      TextStyle(fontSize: 10, color: Colors.blue.shade700)),
            ],
          ),
        ),
      );

  Widget _shapeDeleteHandle() {
    final shape = _shapes.firstWhere(
      (s) => s.id == _selectedShapeId,
      orElse: () => ShapeItem(
          id: '',
          shapeType: '',
          x: 0,
          y: 0,
          width: 0,
          height: 0,
          colorValue: 0),
    );
    if (shape.id.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: shape.x + shape.width / 2 - 12,
      top: math.max(0, shape.y - 32),
      child: _delBtn(() => _deleteShape(_selectedShapeId!)),
    );
  }

  Widget _delBtn(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration:
              const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 16, color: Colors.white),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Toolbar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildToolbar(AppLocalizations l10n) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _toolBtn(Icons.edit, DrawTool.pen, l10n.pen),
            if (_tool == DrawTool.pen) ...[
              const Text('W:', style: TextStyle(fontSize: 11)),
              SizedBox(
                width: 100,
                child: Slider(
                    value: _penWidth,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: _penWidth.round().toString(),
                    onChanged: (v) => setState(() => _penWidth = v.roundToDouble())),
              ),
              Text('${_penWidth.round()}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
              const SizedBox(width: 4),
            ],
            _toolBtnCustom(
              icon: Icons.auto_fix_high,
              tool: DrawTool.eraser,
              tooltip: l10n.eraser,
              badge: _tool == DrawTool.eraser
                  ? (_eraserMode == EraserMode.precision ? 'P' : 'L')
                  : null,
              onTap: () {
                if (_tool == DrawTool.eraser) {
                  setState(() => _eraserMode =
                      _eraserMode == EraserMode.precision
                          ? EraserMode.stroke
                          : EraserMode.precision);
                } else {
                  setState(() {
                    _tool = DrawTool.eraser;
                    _showSubMenu = false;
                  });
                }
              },
            ),
            if (_tool == DrawTool.eraser) ...[
              Text(
                _eraserMode == EraserMode.precision
                    ? 'Präzision'
                    : 'Linie',
                style: const TextStyle(fontSize: 10, color: Colors.blue),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 70,
                child: Slider(
                    value: _eraserSize,
                    min: 8,
                    max: 80,
                    onChanged: (v) => setState(() => _eraserSize = v)),
              ),
            ],
            _toolBtn(Icons.open_with, DrawTool.move, l10n.move),
            _toolBtn(Icons.text_fields, DrawTool.textBox, l10n.textBox),
            _toolBtn(
                Icons.table_chart_outlined, DrawTool.table, 'Tabelle'),
            _toolBtn(Icons.category_outlined, DrawTool.shape, l10n.shape,
                onTapOverride: () => setState(() {
                      _tool = DrawTool.shape;
                      _showSubMenu = !_showSubMenu;
                    })),
            _toolBtn(Icons.gesture, DrawTool.lasso, l10n.lasso),
            const SizedBox(width: 4),
            // Paste shortcut
            Tooltip(
              message: 'Einfügen',
              child: IconButton(
                icon: Icon(Icons.content_paste,
                    size: 22,
                    color: CanvasClipboard.instance.isEmpty
                        ? Colors.grey.shade300
                        : Colors.green.shade600),
                onPressed: CanvasClipboard.instance.isEmpty
                    ? null
                    : _lassoPaste,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 36),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _showColorDialog,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.grey.shade400, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _actionBtn(Icons.undo, l10n.undo, _undo),
            _actionBtn(Icons.redo, l10n.redo, _redo),
            _actionBtn(Icons.delete_forever, l10n.clearAll, _clearAll),
            _actionBtn(Icons.add_photo_alternate, l10n.importImage,
                _importImage),
            _actionBtn(Icons.import_export, 'Import / Export',
                _showExportImportDialog),
            _actionBtn(Icons.ios_share, l10n.exportShare, _exportShare),
            _actionBtn(Icons.settings_outlined, 'Einstellungen',
                _showSettings),
            _actionBtn(Icons.save_outlined, l10n.save, () async {
              await saveAll();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Gespeichert!'),
                    duration: Duration(seconds: 1)));
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, DrawTool tool, String tooltip,
      {VoidCallback? onTapOverride}) {
    final active = _tool == tool;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTapOverride ??
            () => setState(() {
                  _tool = tool;
                  if (tool != DrawTool.shape) _showSubMenu = false;
                  // Clear lasso when switching away from lasso tool
                  if (tool != DrawTool.lasso) _clearLasso();
                }),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 22,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _toolBtnCustom({
    required IconData icon,
    required DrawTool tool,
    required String tooltip,
    String? badge,
    required VoidCallback onTap,
  }) {
    final active = _tool == tool;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 22,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600),
              if (badge != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 22, color: Colors.grey.shade600),
          onPressed: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minWidth: 36),
        ),
      );

  void _showColorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Farbe wählen'),
        content: ColorPalette(
          selectedColor: _color,
          onColorChanged: (c) {
            setState(() => _color = c);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen')),
        ],
      ),
    );
  }

  Widget _buildSubMenu() {
    return Container(
      height: 42,
      color: Colors.grey.shade50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: ShapeType.values
            .map((st) => _chip(st.label, _shapeType == st, () {
                  setState(() {
                    _shapeType = st;
                    _showSubMenu = false;
                  });
                }))
            .toList(),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Colors.grey.shade700,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
              )),
        ),
      );
}

// ---------------------------------------------------------------------------
// Stroke model
// ---------------------------------------------------------------------------

class _Stroke {
  List<Offset> points;
  final Color color;
  final double width;

  _Stroke({required this.points, required this.color, required this.width});

  _Stroke copy() =>
      _Stroke(points: List.from(points), color: color, width: width);

  Map<String, dynamic> toJson() => {
        'color': color.value,
        'width': width,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      };

  factory _Stroke.fromJson(Map<String, dynamic> j) => _Stroke(
        color: Color(j['color'] as int),
        width: (j['width'] as num).toDouble(),
        points: (j['points'] as List<dynamic>)
            .map((p) => Offset((p['x'] as num).toDouble(),
                (p['y'] as num).toDouble()))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Ink painter
// ---------------------------------------------------------------------------

class _InkPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _InkPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) _paintStroke(canvas, s);
  }

  void _paintStroke(Canvas canvas, _Stroke s) {
    if (s.points.isEmpty) return;
    if (s.points.length == 1) {
      canvas.drawCircle(
          s.points.first,
          s.width / 2,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.fill);
      return;
    }
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length - 1; i++) {
      final mid = Offset(
        (s.points[i].dx + s.points[i + 1].dx) / 2,
        (s.points[i].dy + s.points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(
          s.points[i].dx, s.points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(s.points.last.dx, s.points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}

// ---------------------------------------------------------------------------
// Eraser cursor
// ---------------------------------------------------------------------------

class _EraserCursorPainter extends CustomPainter {
  final Offset position;
  final double radius;
  _EraserCursorPainter({required this.position, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = Colors.white.withOpacity(0.01)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = Colors.black.withOpacity(0.7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    canvas.drawCircle(
        position,
        radius - 1,
        Paint()
          ..color = Colors.grey.withOpacity(0.15)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_EraserCursorPainter old) =>
      old.position != position || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Snapshot for undo/redo
// ---------------------------------------------------------------------------

class _Snapshot {
  final List<_Stroke> strokes;
  final List<ShapeItem> shapes;
  final List<TextBoxItem> textBoxes;
  final List<TableItem> tables;

  const _Snapshot({
    required this.strokes,
    required this.shapes,
    required this.textBoxes,
    required this.tables,
  });
}