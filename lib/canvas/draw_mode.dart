import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as dart_ui;
import 'package:flutter/rendering.dart';
import 'image_helper_io.dart'
    if (dart.library.html) 'image_helper_web.dart' as imgHelper;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
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
// App-level settings singleton
// ---------------------------------------------------------------------------
class DrawSettings {
  DrawSettings._();
  static final DrawSettings instance = DrawSettings._();
  bool allowFingerDrawing = true; // default ON so finger drawing works out of the box
  bool enableShapeRecognition = false; // [BETA]
  bool ultraLowLatency = false; // [BETA]
  DrawCanvasSize canvasSize = DrawCanvasSize.a4; // default to A4
}

// ---------------------------------------------------------------------------
// Pen sub-type
// ---------------------------------------------------------------------------
enum PenType { fountainPen, ballpoint, brushPen }

extension PenTypeLabel on PenType {
  String get label {
    switch (this) {
      case PenType.fountainPen: return 'Füllfederhalter';
      case PenType.ballpoint:   return 'Kugelschreiber';
      case PenType.brushPen:    return 'Pinselstift';
    }
  }
  IconData get icon {
    switch (this) {
      case PenType.fountainPen: return Icons.edit;
      case PenType.ballpoint:   return Icons.create;
      case PenType.brushPen:    return Icons.brush;
    }
  }
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
  EraserMode _eraserMode = EraserMode.normal;
  bool _showSubMenu = false;

  // ── Toolbar position (draggable) ─────────────────────────────────────────
  Alignment _toolbarAlignment = Alignment.topCenter;
  double _toolbarOffsetX = 0.0;

  // ── Fullscreen ────────────────────────────────────────────────────────────
  bool _isFullscreen = false;

  // ── Color palette corner ──────────────────────────────────────────────────
  Alignment _paletteCorner = Alignment.bottomRight;
  Offset _paletteDragBaseOffset = Offset.zero;

  // ── Active text formatting overlay ────────────────────────────────────────
  String? _focusedTextBoxId;

  // ── Straight-line snap ────────────────────────────────────────────────────
  bool _snapToLine = false;
  Offset? _snapLineStart;
  Timer? _snapLineTimer;

  // ── Pen settings (GoodNotes-style panel) ─────────────────────────────────
  PenType _penType = PenType.ballpoint;
  double _tipSharpness = 50.0;
  double _pressureSensitivity = 50.0;
  double _strokeStabilization = 0.0;
  bool _drawAndHold = true;
  bool _showPenPanel = false;

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

  // ── Active pointer count ──────────────────────────────────────────────────
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
  Offset? _lassoMenuCanvasPos;

  // ── Resize tool ───────────────────────────────────────────────────────────
  bool _drawingResizeLasso = false;
  bool _resizeLassoReady = false;
  List<Offset> _resizeLassoPoints = [];
  Set<String> _resizeShapeIds = {};
  Set<String> _resizeTextIds = {};
  Set<String> _resizeImageIds = {};
  Set<String> _resizeTableIds = {};
  Set<int> _resizeStrokeIdxs = {};
  // Scale handle drag
  Offset? _resizeHandleStart;
  double _resizeBaseScale = 1.0;
  Rect? _resizeSelectionRect; // bounding rect of selection in canvas space
  Map<String, Rect> _resizeBaseRects = {}; // original rects per id
  Map<int, List<Offset>> _resizeBaseStrokes = {}; // original stroke points
  // Move-inside-resize-selection drag
  Offset? _resizeMoveStart;
  final Map<String, Offset> _resizeMoveBasePos = {};

  // ── Image context menu ────────────────────────────────────────────────────
  String? _imageMenuId;
  Offset? _imageMenuPos;

  // ── Image interactive state ───────────────────────────────────────────────
  // Tracks per-image drag-resize (bottom-right handle) state
  final Map<String, Offset> _imgResizeStart = {};
  final Map<String, Size> _imgResizeBaseSize = {};
  final Map<String, double> _imgRotateStart = {};
  final Map<String, double> _imgRotateBaseAngle = {};

  // ── Toolbar drag state ────────────────────────────────────────────────────
  double _toolbarDx = 0.0; // horizontal offset from default centre position
  bool _toolbarDragActive = false;

  // ── Palette drag state ────────────────────────────────────────────────────
  // Four corners: TL, TR, BL, BR — user drags to switch
  int _paletteCornerIdx = 3; // 0=TL,1=TR,2=BL,3=BR

  // ── Paste indicator ───────────────────────────────────────────────────────
  Offset? _pasteIndicatorScreenPos;

  // ── Move tool ─────────────────────────────────────────────────────────────
  String? _selectedShapeId;
  String? _selectedTextBoxId;
  String? _selectedImageId;
  String? _selectedTableId;
  Offset? _moveStart;
  double _moveBaseX = 0, _moveBaseY = 0;

  // When in `DrawTool.move`, dragging the blue selection handles should resize
  // the selected shape (instead of only moving).
  String? _moveResizeHandle; // 'topLeft' | 'topCenter' | ...
  Rect? _moveResizeBaseRect;
  Offset? _moveResizeStartPos;

  // ── TextBox controllers ───────────────────────────────────────────────────
  final Map<String, TextEditingController> _teControllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // ── Table cell controllers ────────────────────────────────────────────────
  final Map<String, TextEditingController> _cellControllers = {};
  final Map<String, FocusNode> _cellFocusNodes = {};

  // ── Image scale (pinch) ───────────────────────────────────────────────────
  final Map<String, Size> _imgScaleStart = {};

  // ── Shape recognition BETA ───────────────────────────────────────────────
  DateTime? _penHoldStart;
  Timer? _shapeRecTimer;
  Offset? _lastShapeRecPos; // jitter filter for Android stylus events

  // ── Page-fit tracking ──────────────────────────────────────────────────
  bool _pageFitDone = false;
  DrawCanvasSize _activeCanvasSize = DrawCanvasSize.a4;

  // ── Circle-to-lasso ───────────────────────────────────────────────────────
  bool _circleLassoReady = false;
  List<Offset> _circleLassoPoints = [];
  Timer? _circleLassoExpireTimer;
  Timer? _circleLassoHoldTimer;
  bool _circleLassoConverted = false;

  // ── Lasso marching ants animation ─────────────────────────────────────────
  double _marchOffset = 0.0;
  Timer? _marchTimer;

  // ── Ultra-low-latency raw painting ────────────────────────────────────────
  final _inkRepaintNotifier = _InkRepaintNotifier();

  // ── RepaintBoundary key for PDF/image export ──────────────────────────────
  final GlobalKey _repaintKey = GlobalKey();

  // ── Manual long-press ─────────────────────────────────────────────────────
  Timer? _longPressTimer;
  Offset? _longPressPos;

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
    _shapeRecTimer?.cancel();
    _circleLassoExpireTimer?.cancel();
    _circleLassoHoldTimer?.cancel();
    _marchTimer?.cancel();
    _longPressTimer?.cancel();
    _snapLineTimer?.cancel();
    for (final imgId in _imgScaleStart.keys.toList()) { _imgScaleStart.remove(imgId); }
    _inkRepaintNotifier.dispose();
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
      focus.addListener(() {
        // Trigger a rebuild so the focused-text-box toolbar reacts instantly.
        if (!mounted) return;
        setState(() {});
      });
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
      images: _images.map((i) => ImageItem.fromJson(i.toJson())).toList(),
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
        _images = snap.images;
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
        _images = snap.images;
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
        images: _images.map((i) => ImageItem.fromJson(i.toJson())).toList(),
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
  // Coordinate helpers
  // ─────────────────────────────────────────────────────────────────────────

  Offset _toCanvas(Offset screenPos) {
    final matrix = Matrix4.copy(_xfCtrl.value);
    matrix.invert();
    final dx = screenPos.dx;
    final dy = screenPos.dy;
    final m = matrix.storage;
    final rx = m[0] * dx + m[4] * dy + m[12];
    final ry = m[1] * dx + m[5] * dy + m[13];
    return Offset(rx, ry);
  }

  Offset _toScreen(Offset canvasPos) {
    final m = _xfCtrl.value.storage;
    final sx = m[0] * canvasPos.dx + m[4] * canvasPos.dy + m[12];
    final sy = m[1] * canvasPos.dx + m[5] * canvasPos.dy + m[13];
    return Offset(sx, sy);
  }

  double get _zoomScale {
    final m = _xfCtrl.value.storage;
    return math.sqrt(m[0] * m[0] + m[1] * m[1]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Eraser
  // ─────────────────────────────────────────────────────────────────────────

  void _applyPrecisionErase(Offset pos) {
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
                width: stroke.width,
                penType: stroke.penType));
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
            width: stroke.width,
            penType: stroke.penType));
      }
    }

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
      case 'triangle':
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
    switch (_eraserMode) {
      case EraserMode.normal:
        _applyPrecisionEraseWide(pos); // wider/sloppier hit-test
        break;
      case EraserMode.precision:
        _applyPrecisionErase(pos); // exact circle hit-test (precision)
        break;
      case EraserMode.line:
        _applyStrokeErase(pos); // removes entire stroke (was 'stroke')
        break;
    }
  }

  // Precision erase: bigger eraser radius, otherwise same as normal
  void _applyPrecisionEraseWide(Offset pos) {
    final savedSize = _eraserSize;
    _eraserSize = _eraserSize * 2.5;
    _applyPrecisionErase(pos);
    _eraserSize = savedSize;
  }

  double get _effectiveEraserSize {
    // Cursor must match the radius used by the current eraser mode.
    switch (_eraserMode) {
      case EraserMode.normal:
        return _eraserSize * 2.5;
      case EraserMode.precision:
      case EraserMode.line:
        return _eraserSize;
    }
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

  bool _strokeIntersectsLasso(List<Offset> strokePts, List<Offset> lasso) {
    if (strokePts.any((p) => _pointInPoly(p, lasso))) return true;
    for (int i = 0; i < strokePts.length - 1; i++) {
      for (int j = 0; j < lasso.length; j++) {
        if (_segmentsIntersect(
            strokePts[i], strokePts[i + 1],
            lasso[j], lasso[(j + 1) % lasso.length])) {
          return true;
        }
      }
    }
    return false;
  }

  bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final d1 = _cross(d - c, a - c);
    final d2 = _cross(d - c, b - c);
    final d3 = _cross(b - a, c - a);
    final d4 = _cross(b - a, d - a);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) return true;
    return false;
  }

  double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

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
      if (_strokeIntersectsLasso(_strokes[i].points, _lassoPoints)) {
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
    _startMarchTimer();
  }

  void _clearLasso() {
    _stopMarchTimer();
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

  void _startMarchTimer() {
    _marchTimer?.cancel();
    _marchTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      setState(() {
        _marchOffset = (_marchOffset + 0.02) % 1.0;
      });
    });
  }

  void _stopMarchTimer() {
    _marchTimer?.cancel();
    _marchTimer = null;
    _marchOffset = 0.0;
  }

  void _checkCircleLasso(List<Offset> pts) {
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w < 20 || h < 20) return;

    double totalLen = 0;
    for (int i = 1; i < pts.length; i++) {
      totalLen += (pts[i] - pts[i - 1]).distance;
    }

    final firstLast = (pts.last - pts.first).distance;
    if (firstLast > totalLen * 0.25) return;

    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final radii = pts.map((p) => (p - Offset(cx, cy)).distance).toList();
    final avgR = radii.reduce((a, b) => a + b) / radii.length;
    final variance = radii
        .map((r) => (r - avgR) * (r - avgR))
        .reduce((a, b) => a + b) /
        radii.length;
    final stdDev = math.sqrt(variance);
    if (stdDev / avgR > 0.22) return;

    _circleLassoExpireTimer?.cancel();
    setState(() {
      _circleLassoReady = true;
      _circleLassoPoints = List<Offset>.from(pts);
      _circleLassoConverted = false;
    });
    _circleLassoExpireTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _circleLassoReady = false;
          _circleLassoPoints = [];
        });
      }
    });
  }

  void _convertCircleToLasso() {
    if (!_circleLassoReady || _circleLassoConverted) return;
    _circleLassoExpireTimer?.cancel();
    _circleLassoHoldTimer?.cancel();

    if (_strokes.isNotEmpty && _circleLassoPoints.length > 4) {
      final last = _strokes.last;
      if (last.points.length == _circleLassoPoints.length) {
        _pushUndo();
        _strokes.removeLast();
      }
    }

    setState(() {
      _circleLassoConverted = true;
      _circleLassoReady = false;
      _tool = DrawTool.lasso;
      _lassoPoints = List<Offset>.from(_circleLassoPoints);
      _drawingLasso = false;
    });

    _finalizeLasso();
    widget.onDirty();
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
        penType: stroke.penType,
      );
    }
    _lassoPoints = _lassoPoints.map((p) => p + delta).toList();
    if (_lassoMenuCanvasPos != null) {
      _lassoMenuCanvasPos = _lassoMenuCanvasPos! + delta;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Resize tool helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _finalizeResizeLasso() {
    if (_resizeLassoPoints.length < 3) {
      setState(() {
        _drawingResizeLasso = false;
        _resizeLassoPoints = [];
        _resizeLassoReady = false;
      });
      return;
    }

    _resizeShapeIds = _shapes
        .where((s) => _pointInPoly(s.center, _resizeLassoPoints))
        .map((s) => s.id)
        .toSet();
    _resizeTextIds = _textBoxes
        .where((t) => _pointInPoly(t.center, _resizeLassoPoints))
        .map((t) => t.id)
        .toSet();
    _resizeImageIds = _images
        .where((i) => _pointInPoly(i.center, _resizeLassoPoints))
        .map((i) => i.id)
        .toSet();
    _resizeTableIds = _tables
        .where((t) => _pointInPoly(t.center, _resizeLassoPoints))
        .map((t) => t.id)
        .toSet();
    _resizeStrokeIdxs = {};
    for (int i = 0; i < _strokes.length; i++) {
      if (_strokeIntersectsLasso(_strokes[i].points, _resizeLassoPoints)) {
        _resizeStrokeIdxs.add(i);
      }
    }

    _resizeBaseRects = {};
    _resizeBaseStrokes = {};

    for (final s in _shapes.where((s) => _resizeShapeIds.contains(s.id))) {
      _resizeBaseRects['shape:${s.id}'] = Rect.fromLTWH(s.x, s.y, s.width, s.height);
    }
    for (final t in _textBoxes.where((t) => _resizeTextIds.contains(t.id))) {
      _resizeBaseRects['text:${t.id}'] = Rect.fromLTWH(t.x, t.y, t.width, 60);
    }
    for (final i in _images.where((i) => _resizeImageIds.contains(i.id))) {
      _resizeBaseRects['img:${i.id}'] = Rect.fromLTWH(i.x, i.y, i.width, i.height);
    }
    for (final t in _tables.where((t) => _resizeTableIds.contains(t.id))) {
      _resizeBaseRects['tbl:${t.id}'] = Rect.fromLTWH(t.x, t.y, t.totalWidth, t.totalHeight);
    }
    for (final idx in _resizeStrokeIdxs) {
      _resizeBaseStrokes[idx] = List<Offset>.from(_strokes[idx].points);
    }

    Rect? bounds;
    for (final r in _resizeBaseRects.values) {
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    for (final pts in _resizeBaseStrokes.values) {
      for (final p in pts) {
        final r = Rect.fromLTWH(p.dx, p.dy, 0, 0);
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
    }
    _resizeSelectionRect = bounds;

    setState(() {
      _drawingResizeLasso = false;
      _resizeLassoReady = true;
    });
  }

  void _clearResizeLasso() {
    setState(() {
      _resizeLassoReady = false;
      _resizeLassoPoints = [];
      _resizeShapeIds = {};
      _resizeTextIds = {};
      _resizeImageIds = {};
      _resizeTableIds = {};
      _resizeStrokeIdxs = {};
      _resizeSelectionRect = null;
      _resizeBaseRects = {};
      _resizeBaseStrokes = {};
    });
  }

  void _applyResizeScale(double scale) {
    final bounds = _resizeSelectionRect;
    if (bounds == null) return;
    final origin = bounds.topLeft;

    for (int i = 0; i < _shapes.length; i++) {
      final key = 'shape:${_shapes[i].id}';
      final base = _resizeBaseRects[key];
      if (base == null) continue;
      _shapes[i] = _shapes[i].copyWith(
        x: origin.dx + (base.left - origin.dx) * scale,
        y: origin.dy + (base.top - origin.dy) * scale,
        width: math.max(10, base.width * scale),
        height: math.max(10, base.height * scale),
      );
    }
    for (final tb in _textBoxes) {
      final key = 'text:${tb.id}';
      final base = _resizeBaseRects[key];
      if (base == null) continue;
      tb.x = origin.dx + (base.left - origin.dx) * scale;
      tb.y = origin.dy + (base.top - origin.dy) * scale;
      tb.width = math.max(60, base.width * scale);
      tb.fontSize = math.max(8, 16 * scale);
    }
    for (final img in _images) {
      final key = 'img:${img.id}';
      final base = _resizeBaseRects[key];
      if (base == null) continue;
      img.x = origin.dx + (base.left - origin.dx) * scale;
      img.y = origin.dy + (base.top - origin.dy) * scale;
      img.width = math.max(20, base.width * scale);
      img.height = math.max(20, base.height * scale);
    }
    for (final tbl in _tables) {
      final key = 'tbl:${tbl.id}';
      final base = _resizeBaseRects[key];
      if (base == null) continue;
      tbl.x = origin.dx + (base.left - origin.dx) * scale;
      tbl.y = origin.dy + (base.top - origin.dy) * scale;
      tbl.cellWidth = math.max(20, (base.width / tbl.cols) * scale);
      tbl.cellHeight = math.max(20, (base.height / tbl.rows) * scale);
    }
    for (final idx in _resizeStrokeIdxs) {
      final basePts = _resizeBaseStrokes[idx];
      if (basePts == null) continue;
      _strokes[idx] = _Stroke(
        points: basePts.map((p) => Offset(
          origin.dx + (p.dx - origin.dx) * scale,
          origin.dy + (p.dy - origin.dy) * scale,
        )).toList(),
        color: _strokes[idx].color,
        width: _strokes[idx].width,
        penType: _strokes[idx].penType,
      );
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
    setState(() {});
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

  void _lassoPaste({Offset? atPos}) {
    final cb = CanvasClipboard.instance;
    if (cb.isEmpty) return;
    _pushUndo();

    // FIX: place pasted content so its top-left lands at [atPos]
    Offset off;
    if (atPos != null) {
      double? minX, minY;
      void chk(double x, double y) {
        minX = minX == null ? x : (x < minX! ? x : minX!);
        minY = minY == null ? y : (y < minY! ? y : minY!);
      }
      for (final sj in cb.shapes)    { chk((sj['x'] as num).toDouble(), (sj['y'] as num).toDouble()); }
      for (final tj in cb.textBoxes) { chk((tj['x'] as num).toDouble(), (tj['y'] as num).toDouble()); }
      for (final ij in cb.images)    { chk((ij['x'] as num).toDouble(), (ij['y'] as num).toDouble()); }
      for (final tj in cb.tables)    { chk((tj['x'] as num).toDouble(), (tj['y'] as num).toDouble()); }
      for (final stj in cb.strokes) {
        for (final p in (stj['points'] as List)) {
          chk((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
        }
      }
      off = minX != null ? Offset(atPos.dx - minX!, atPos.dy - minY!) : atPos;
    } else {
      off = const Offset(24, 24);
    }

    final newShapeIds = <String>{};
    final newTextIds = <String>{};
    final newImgIds = <String>{};
    final newTblIds = <String>{};
    final newStrokeIdxs = <int>{};

    for (final sj in cb.shapes) {
      final j = Map<String, dynamic>.from(sj);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      final s = ShapeItem.fromJson(j);
      newShapeIds.add(s.id);
      setState(() => _shapes.add(s));
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
      newTextIds.add(tb.id);
      setState(() => _textBoxes.add(tb));
    }
    for (final ij in cb.images) {
      final j = Map<String, dynamic>.from(ij);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      final img = ImageItem.fromJson(j);
      newImgIds.add(img.id);
      setState(() => _images.add(img));
    }
    for (final tj in cb.tables) {
      final j = Map<String, dynamic>.from(tj);
      j['id'] = _uuid.v4();
      j['x'] = (j['x'] as num).toDouble() + off.dx;
      j['y'] = (j['y'] as num).toDouble() + off.dy;
      final tbl = TableItem.fromJson(j);
      newTblIds.add(tbl.id);
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
      final idx = _strokes.length;
      setState(() => _strokes.add(_Stroke.fromJson(j)));
      newStrokeIdxs.add(idx);
    }

    setState(() {
      _tool = DrawTool.lasso;
      _lassoReady = true;
      _lassoShapeIds = newShapeIds;
      _lassoTextIds = newTextIds;
      _lassoImageIds = newImgIds;
      _lassoTableIds = newTblIds;
      _lassoStrokeIdxs = newStrokeIdxs;
      _pasteIndicatorScreenPos = null;
      _lassoPoints = _buildBoundingLasso(
        newShapeIds, newTextIds, newImgIds, newTblIds, newStrokeIdxs);
      _lassoMenuCanvasPos = _lassoPoints.isNotEmpty
          ? Offset(_lassoPoints.first.dx, _lassoPoints.first.dy - 30)
          : null;
    });

    widget.onDirty();
  }

  List<Offset> _buildBoundingLasso(
    Set<String> shapeIds, Set<String> textIds,
    Set<String> imgIds, Set<String> tblIds, Set<int> strokeIdxs) {
    double? minX, minY, maxX, maxY;
    void expand(double x, double y) {
      minX = math.min(minX ?? x, x);
      minY = math.min(minY ?? y, y);
      maxX = math.max(maxX ?? x, x);
      maxY = math.max(maxY ?? y, y);
    }
    for (final s in _shapes.where((s) => shapeIds.contains(s.id))) {
      expand(s.x, s.y); expand(s.x + s.width, s.y + s.height);
    }
    for (final t in _textBoxes.where((t) => textIds.contains(t.id))) {
      expand(t.x, t.y); expand(t.x + t.width, t.y + 60);
    }
    for (final i in _images.where((i) => imgIds.contains(i.id))) {
      expand(i.x, i.y); expand(i.x + i.width, i.y + i.height);
    }
    for (final t in _tables.where((t) => tblIds.contains(t.id))) {
      expand(t.x, t.y); expand(t.x + t.totalWidth, t.y + t.totalHeight);
    }
    for (final idx in strokeIdxs) {
      for (final p in _strokes[idx].points) expand(p.dx, p.dy);
    }
    if (minX == null) return [];
    const pad = 12.0;
    return [
      Offset(minX! - pad, minY! - pad),
      Offset(maxX! + pad, minY! - pad),
      Offset(maxX! + pad, maxY! + pad),
      Offset(minX! - pad, maxY! + pad),
    ];
  }

  void _showCanvasPasteMenu(Offset? screenPos) {
    final canvasPos = screenPos != null ? _toCanvas(screenPos) : null;
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: const Text('Einf\u00fcgen', style: TextStyle(fontSize: 16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: const Text('Inhalt aus Zwischenablage einf\u00fcgen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _lassoPaste(atPos: canvasPos);
            },
            child: const Text('Einf\u00fcgen'),
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
  // Shape recognition BETA
  // ─────────────────────────────────────────────────────────────────────────

  // Corner counting for shape recognition
  int _countCorners(List<Offset> pts) {
    if (pts.length < 4) return pts.length;
    final n = pts.length;
    const windowSize = 8;
    final smoothed = <Offset>[];
    for (int i = 0; i < n; i++) {
      final start = math.max(0, i - windowSize ~/ 2);
      final end = math.min(n - 1, i + windowSize ~/ 2);
      double sx = 0, sy = 0;
      for (int j = start; j <= end; j++) { sx += pts[j].dx; sy += pts[j].dy; }
      smoothed.add(Offset(sx / (end - start + 1), sy / (end - start + 1)));
    }
    int corners = 0;
    const angleThresh = 50.0;
    const minSegLen = 10.0;
    for (int i = 2; i < smoothed.length - 2; i++) {
      final a = smoothed[i] - smoothed[i - 2];
      final b = smoothed[i + 2] - smoothed[i];
      if (a.distance < minSegLen || b.distance < minSegLen) continue;
      final dot = a.dx * b.dx + a.dy * b.dy;
      final angle = math.acos((dot / (a.distance * b.distance)).clamp(-1.0, 1.0));
      if (angle * 180 / math.pi >= angleThresh) {
        corners++;
        i += 3;
      }
    }
    return corners;
  }

  void _startShapeRecTimer() {
    if (!DrawSettings.instance.enableShapeRecognition) return;
    if (_currentStroke == null || _currentStroke!.points.isEmpty) return;
    final curPos = _currentStroke!.points.last;
    if (_lastShapeRecPos != null &&
        (curPos - _lastShapeRecPos!).distance < 3.0) {
      return;
    }
    _lastShapeRecPos = curPos;
    _penHoldStart = DateTime.now();
    _shapeRecTimer?.cancel();
    _shapeRecTimer = Timer(const Duration(milliseconds: 700), () {
      if (_currentStroke != null && mounted) {
        _tryRecognizeShape();
      }
    });
  }

  void _cancelShapeRec() {
    _shapeRecTimer?.cancel();
    _penHoldStart = null;
    _lastShapeRecPos = null;
  }

  void _tryRecognizeShape() {
    final stroke = _currentStroke;
    if (stroke == null || stroke.points.length < 4) return;
    final pts = stroke.points;
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = maxX - minX;
    final h = maxY - minY;

    final totalLen = () {
      double l = 0;
      for (int i = 1; i < pts.length; i++) {
        l += (pts[i] - pts[i - 1]).distance;
      }
      return l;
    }();
    final directDist = (pts.last - pts.first).distance;

    _pushUndo();
    _strokes.removeLast();

    // Only snap to a line if the stroke is really straight.
    bool isMostlyStraight() {
      if (pts.length < 3) return true;
      final a = pts.first;
      final b = pts.last;
      final ab = b - a;
      final len = ab.distance;
      if (len < 1e-3) return false;
      final nx = -ab.dy / len;
      final ny = ab.dx / len;
      double maxDist = 0.0;
      for (final p in pts) {
        final ap = p - a;
        final d = (ap.dx * nx + ap.dy * ny).abs();
        if (d > maxDist) maxDist = d;
      }
      return maxDist <= 10.0;
    }

    if (directDist / totalLen > 0.88 && isMostlyStraight()) {
      setState(() {
        _strokes.add(_Stroke(
          points: [pts.first, pts.last],
          color: stroke.color,
          width: stroke.width,
          penType: stroke.penType,
        ));
        _currentStroke = null;
      });
    } else if (w > 20 && h > 20) {
      final firstLast = (pts.last - pts.first).distance;
      final isClosed = firstLast < totalLen * 0.2;

      if (isClosed) {
        final cx = (minX + maxX) / 2;
        final cy = (minY + maxY) / 2;
        final radii = pts.map((p) => (p - Offset(cx, cy)).distance).toList();
        final avgR = radii.reduce((a, b) => a + b) / radii.length;
        final variance = radii.map((r) => (r - avgR) * (r - avgR)).reduce((a, b) => a + b) / radii.length;
        final stdDev = math.sqrt(variance);

        if (stdDev / avgR < 0.18) {
          setState(() {
            _shapes.add(ShapeItem(
              id: _uuid.v4(), shapeType: 'circle',
              x: minX, y: minY, width: w, height: h,
              colorValue: stroke.color.value, strokeWidth: stroke.width,
            ));
            _currentStroke = null;
          });
        } else {
          final corners = _countCorners(pts);
          final shapeName = corners <= 3 ? 'triangle' : 'rectangle';
          setState(() {
            _shapes.add(ShapeItem(
              id: _uuid.v4(), shapeType: shapeName,
              x: minX, y: minY, width: w, height: h,
              colorValue: stroke.color.value, strokeWidth: stroke.width,
            ));
            _currentStroke = null;
          });
        }
      }
    }
    widget.onDirty();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pointer handling
  // ─────────────────────────────────────────────────────────────────────────

  bool _ignoredKind(PointerDeviceKind kind) {
    if (DrawSettings.instance.allowFingerDrawing) return false;
    return kind == PointerDeviceKind.touch;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_ignoredKind(e.kind)) return;

    if (e.kind == PointerDeviceKind.stylus && e.buttons == 2) {
      setState(() {
        _tool = DrawTool.eraser;
        _showSubMenu = false;
      });
    }

    if (_imageMenuId != null) {
      setState(() {
        _imageMenuId = null;
        _imageMenuPos = null;
      });
    }

    if (_pasteIndicatorScreenPos != null) {
      setState(() => _pasteIndicatorScreenPos = null);
    }

    final pos = _toCanvas(e.localPosition);

    if (_lassoReady) {
      if (_pointInPoly(pos, _lassoPoints)) {
        _pushUndo();
        _lassoMoveStart = pos;
        return;
      } else {
        _clearLasso();
        if (_tool != DrawTool.lasso && _tool != DrawTool.pen &&
            _tool != DrawTool.eraser && _tool != DrawTool.shape) return;
      }
    }

    if (_resizeLassoReady) {
      if (_resizeSelectionRect != null) {
        final inflated = _resizeSelectionRect!.inflate(12);
        final handlePos = inflated.bottomRight;
        if ((pos - handlePos).distance < 28 / _zoomScale) {
          _resizeHandleStart = pos;
          _resizeBaseScale = 1.0;
          return;
        }
        if (_resizeSelectionRect!.contains(pos)) {
          _pushUndo();
          _resizeMoveStart = pos;
          _resizeMoveBasePos.clear();
          for (final s in _shapes.where((s) => _resizeShapeIds.contains(s.id))) {
            _resizeMoveBasePos['shape:${s.id}'] = Offset(s.x, s.y);
          }
          for (final t in _textBoxes.where((t) => _resizeTextIds.contains(t.id))) {
            _resizeMoveBasePos['text:${t.id}'] = Offset(t.x, t.y);
          }
          for (final i in _images.where((i) => _resizeImageIds.contains(i.id))) {
            _resizeMoveBasePos['img:${i.id}'] = Offset(i.x, i.y);
          }
          for (final t in _tables.where((t) => _resizeTableIds.contains(t.id))) {
            _resizeMoveBasePos['tbl:${t.id}'] = Offset(t.x, t.y);
          }
          for (final idx in _resizeStrokeIdxs) {
            if (_strokes[idx].points.isNotEmpty) {
              _resizeMoveBasePos['stroke:$idx'] = _strokes[idx].points.first;
            }
          }
          if (_resizeSelectionRect != null) {
            _resizeMoveBasePos['__rect__'] = _resizeSelectionRect!.topLeft;
          }
          return;
        }
        if (!inflated.contains(pos)) {
          _clearResizeLasso();
          return;
        }
      }
      return;
    }

    switch (_tool) {
      case DrawTool.pen:
        _pushUndo();
        _cancelShapeRec();
        _circleLassoHoldTimer?.cancel();
        if (_circleLassoReady && !_circleLassoConverted) {
          _circleLassoHoldTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted && _circleLassoReady && !_circleLassoConverted) {
              _convertCircleToLasso();
            }
          });
        }
        final stroke = _Stroke(
            points: [pos],
            color: _color,
            width: _penWidth,
            penType: _penType);
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

      case DrawTool.resize:
        setState(() {
          _drawingResizeLasso = true;
          _resizeLassoReady = false;
          _resizeLassoPoints = [pos];
        });
        break;

      case DrawTool.textBox:
        _placeTextBox(pos);
        break;

      case DrawTool.table:
        _placeTable(pos);
        break;

      case DrawTool.move:
        _moveResizeHandle = null;
        _moveResizeBaseRect = null;
        _moveResizeStartPos = null;
        _handleMoveStart(pos);
        if (_selectedShapeId != null) {
          final idx =
              _shapes.indexWhere((s) => s.id == _selectedShapeId);
          if (idx >= 0) {
            final s = _shapes[idx];
            final baseRect = Rect.fromLTWH(s.x, s.y, s.width, s.height);
            final handle = _hitTestMoveResizeHandle(baseRect, pos);
            if (handle != null) {
              _pushUndo();
              setState(() {
                _moveStart = null;
                _moveResizeHandle = handle;
                _moveResizeBaseRect = baseRect;
                _moveResizeStartPos = pos;
              });
            }
          }
        }
        break;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_ignoredKind(e.kind)) return;
    final pos = _toCanvas(e.localPosition);

    if (_tool == DrawTool.pen) {
      if (DrawSettings.instance.enableShapeRecognition) {
        _startShapeRecTimer();
      } else {
        _cancelShapeRec();
      }
      _circleLassoHoldTimer?.cancel();
    }

    if (_lassoReady && _lassoMoveStart != null) {
      final delta = pos - _lassoMoveStart!;
      _lassoMoveStart = pos;
      setState(() => _applyLassoMove(delta));
      widget.onDirty();
      return;
    }

    if (_resizeLassoReady && _resizeHandleStart != null) {
      final bounds = _resizeSelectionRect;
      if (bounds != null) {
        final baseSize = bounds.size;
        final dx = pos.dx - _resizeHandleStart!.dx;
        final dy = pos.dy - _resizeHandleStart!.dy;
        final scaleFactor = math.max(0.1,
            1.0 + (dx + dy) / (baseSize.width + baseSize.height) * 2);
        setState(() => _applyResizeScale(scaleFactor));
        widget.onDirty();
      }
      return;
    }

    if (_resizeLassoReady && _resizeMoveStart != null) {
      final d = pos - _resizeMoveStart!;
      setState(() {
        for (int i = 0; i < _shapes.length; i++) {
          final base = _resizeMoveBasePos['shape:${_shapes[i].id}'];
          if (base != null) _shapes[i] = _shapes[i].copyWith(x: base.dx + d.dx, y: base.dy + d.dy);
        }
        for (final tb in _textBoxes) {
          final base = _resizeMoveBasePos['text:${tb.id}'];
          if (base != null) { tb.x = base.dx + d.dx; tb.y = base.dy + d.dy; }
        }
        for (final img in _images) {
          final base = _resizeMoveBasePos['img:${img.id}'];
          if (base != null) { img.x = base.dx + d.dx; img.y = base.dy + d.dy; }
        }
        for (final tbl in _tables) {
          final base = _resizeMoveBasePos['tbl:${tbl.id}'];
          if (base != null) { tbl.x = base.dx + d.dx; tbl.y = base.dy + d.dy; }
        }
        for (final idx in _resizeStrokeIdxs) {
          final origPts = _resizeBaseStrokes[idx];
          if (origPts != null) {
            _strokes[idx] = _Stroke(
              points: origPts.map((p) => p + d).toList(),
              color: _strokes[idx].color, width: _strokes[idx].width,
              penType: _strokes[idx].penType,
            );
          }
        }
        final baseRect = _resizeMoveBasePos['__rect__'];
        if (baseRect != null && _resizeSelectionRect != null) {
          _resizeSelectionRect = Rect.fromLTWH(
            baseRect.dx + d.dx, baseRect.dy + d.dy,
            _resizeSelectionRect!.width, _resizeSelectionRect!.height,
          );
        }
      });
      widget.onDirty();
      return;
    }

    switch (_tool) {
      case DrawTool.pen:
        if (_currentStroke != null) {
          _currentStroke!.points.add(pos);
          if (DrawSettings.instance.ultraLowLatency) {
            _inkRepaintNotifier.notifyListeners();
            SchedulerBinding.instance.ensureVisualUpdate();
          } else {
            setState(() {});
          }
          widget.onDirty();
        }
        break;

      case DrawTool.eraser:
        setState(() => _eraserPos = pos);
        _applyErase(pos);
        break;

      case DrawTool.shape:
        if (_drawingShape && _shapeStart != null) {
          setState(() => _ghostShape = _makeShape(_shapeStart!, pos, ghost: true));
        }
        break;

      case DrawTool.lasso:
        if (_drawingLasso) {
          setState(() => _lassoPoints.add(pos));
        }
        break;

      case DrawTool.resize:
        if (_drawingResizeLasso) {
          setState(() => _resizeLassoPoints.add(pos));
        }
        break;

      case DrawTool.move:
        if (_moveResizeHandle != null) {
          _applyMoveResizeShape(pos);
        } else if (_moveStart != null) {
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

    if (_resizeLassoReady && _resizeHandleStart != null) {
      _resizeHandleStart = null;
      _resizeBaseRects = {};
      _resizeBaseStrokes = {};
      for (final s in _shapes.where((s) => _resizeShapeIds.contains(s.id))) {
        _resizeBaseRects['shape:${s.id}'] = Rect.fromLTWH(s.x, s.y, s.width, s.height);
      }
      for (final t in _textBoxes.where((t) => _resizeTextIds.contains(t.id))) {
        _resizeBaseRects['text:${t.id}'] = Rect.fromLTWH(t.x, t.y, t.width, 60);
      }
      for (final i in _images.where((i) => _resizeImageIds.contains(i.id))) {
        _resizeBaseRects['img:${i.id}'] = Rect.fromLTWH(i.x, i.y, i.width, i.height);
      }
      for (final t in _tables.where((t) => _resizeTableIds.contains(t.id))) {
        _resizeBaseRects['tbl:${t.id}'] = Rect.fromLTWH(t.x, t.y, t.totalWidth, t.totalHeight);
      }
      for (final idx in _resizeStrokeIdxs) {
        _resizeBaseStrokes[idx] = List<Offset>.from(_strokes[idx].points);
      }
      Rect? bounds;
      for (final r in _resizeBaseRects.values) {
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
      _resizeSelectionRect = bounds;
      return;
    }

    if (_resizeLassoReady && _resizeMoveStart != null) {
      _resizeMoveStart = null;
      _resizeMoveBasePos.clear();
      return;
    }

    switch (_tool) {
      case DrawTool.pen:
        _cancelShapeRec();
        _circleLassoHoldTimer?.cancel();
        final completedStroke = _currentStroke;
        setState(() => _currentStroke = null);
        if (completedStroke != null && completedStroke.points.length >= 8) {
          _checkCircleLasso(completedStroke.points);
        }
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

      case DrawTool.resize:
        _finalizeResizeLasso();
        break;

      case DrawTool.move:
        _moveStart = null;
        _moveResizeHandle = null;
        _moveResizeBaseRect = null;
        _moveResizeStartPos = null;
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
    final typeName = _shapeType.name;
    return ShapeItem(
      id: ghost ? '_ghost_' : _uuid.v4(),
      shapeType: typeName,
      x: x, y: y, width: w, height: h,
      colorValue: _color.value,
      strokeWidth: _penWidth,
    );
  }

  void _handleMoveStart(Offset pos) {
    for (final s in _shapes.reversed) {
      if (Rect.fromLTWH(s.x, s.y, s.width, s.height).inflate(10).contains(pos)) {
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

  String? _hitTestMoveResizeHandle(Rect r, Offset pos) {
    const thresh = 12.0; // in canvas coordinates
    final handles = <String, Offset>{
      'topLeft': r.topLeft,
      'topCenter': r.topCenter,
      'topRight': r.topRight,
      'centerLeft': r.centerLeft,
      'centerRight': r.centerRight,
      'bottomLeft': r.bottomLeft,
      'bottomCenter': r.bottomCenter,
      'bottomRight': r.bottomRight,
    };

    String? best;
    var bestD = double.infinity;
    for (final e in handles.entries) {
      final d = (pos - e.value).distance;
      if (d <= thresh && d < bestD) {
        best = e.key;
        bestD = d;
      }
    }
    return best;
  }

  void _applyMoveResizeShape(Offset pos) {
    final handle = _moveResizeHandle;
    final baseRect = _moveResizeBaseRect;
    final startPos = _moveResizeStartPos;
    final selectedId = _selectedShapeId;

    if (handle == null ||
        baseRect == null ||
        startPos == null ||
        selectedId == null) return;

    final idx = _shapes.indexWhere((s) => s.id == selectedId);
    if (idx < 0) return;

    final dx = pos.dx - startPos.dx;
    final dy = pos.dy - startPos.dy;

    double left = baseRect.left;
    double right = baseRect.right;
    double top = baseRect.top;
    double bottom = baseRect.bottom;

    final lower = handle.toLowerCase();
    final moveLeft = lower.contains('left');
    final moveRight = lower.contains('right');
    final moveTop = lower.contains('top');
    final moveBottom = lower.contains('bottom');

    if (moveLeft) left += dx;
    if (moveRight) right += dx;
    if (moveTop) top += dy;
    if (moveBottom) bottom += dy;

    const minW = 12.0;
    const minH = 12.0;
    if (right - left < minW) {
      if (moveLeft && !moveRight) {
        left = right - minW;
      } else {
        right = left + minW;
      }
    }
    if (bottom - top < minH) {
      if (moveTop && !moveBottom) {
        top = bottom - minH;
      } else {
        bottom = top + minH;
      }
    }

    setState(() {
      _shapes[idx] = _shapes[idx].copyWith(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
    });
    widget.onDirty();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Place helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _placeTextBox(Offset pos) {
    final id = _uuid.v4();
    final tb = TextBoxItem(id: id, x: pos.dx, y: pos.dy, colorValue: _color.value);
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

  void _placeTable(Offset pos) => _showTableSetupDialog(pos);

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
                IconButton(icon: const Icon(Icons.remove), onPressed: () => setLocal(() => rows = math.max(1, rows - 1))),
                Text('$rows', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add), onPressed: () => setLocal(() => rows = math.min(20, rows + 1))),
              ]),
              Row(children: [
                const Text('Spalten:', style: TextStyle(fontSize: 14)),
                IconButton(icon: const Icon(Icons.remove), onPressed: () => setLocal(() => cols = math.max(1, cols - 1))),
                Text('$cols', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add), onPressed: () => setLocal(() => cols = math.min(20, cols + 1))),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Erstellen')),
          ],
        ),
      ),
    ).then((result) {
      if (result == true) {
        final id = _uuid.v4();
        final tbl = TableItem(id: id, x: pos.dx, y: pos.dy, rows: rows, cols: cols);
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

  /// Public entry-point called by CanvasPageState.triggerImport()
  Future<void> showImportExportDialog() => _showExportImportDialog();

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
              onTap: () async {
                Navigator.pop(ctx);
                await ExportService.showImportDialog(context, _onImport);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Exportieren'),
              subtitle: const Text('PDF, Bild, Word, PowerPoint'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.showExportDialog(
                    context, widget.page.name, repaintKey: _repaintKey);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  Future<void> _onImport(String filePath, String fileType) async {
    if (['jpg', 'jpeg', 'png'].contains(fileType)) {
      await _importImageAsNewPages(filePath);
    } else if (fileType == 'pdf') {
      await _importPdfPages(filePath);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Format .$fileType wird noch nicht vollst\u00e4ndig unterst\u00fctzt.'),
            duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<List<NotePage>> _createInsertedPages(int insertCount) async {
    // Insert new pages AFTER the current page (by order).
    final insertAfterOrder = widget.page.order;
    final pages = _storage.getPagesForNotebook(widget.page.notebookId);

    // Shift existing pages forward to make space.
    for (final p in pages) {
      if (p.order > insertAfterOrder) {
        p.order += insertCount;
        await _storage.savePage(p);
      }
    }

    final created = <NotePage>[];
    for (int i = 0; i < insertCount; i++) {
      final order = insertAfterOrder + 1 + i;
      final page = NotePage(
        id: _uuid.v4(),
        notebookId: widget.page.notebookId,
        name: 'Seite ${order + 1}',
        order: order,
        paperTypeIndex: widget.page.paperTypeIndex,
      );
      await _storage.savePage(page);
      created.add(page);
    }
    return created;
  }

  Future<void> _importImageAsNewPages(String imagePath) async {
    try {
      final created = await _createInsertedPages(1);
      if (created.isEmpty) return;

      // Keep existing display sizing but store image on its own page.
      final imageItem = ImageItem(
        id: _uuid.v4(),
        x: 40,
        y: 40,
        width: 320,
        height: 240,
        filePath: imagePath,
      );
      await _storage.saveCanvasData(
        created.first.id,
        CanvasData(images: [imageItem]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image Import fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _importPdfPages(String pdfPath) async {
    try {
      final doc = await PdfDocument.openFile(pdfPath);
      final pageCount = doc.pages.length;
      if (pageCount == 0) {
        await doc.dispose();
        return;
      }

      int startPage = 1, endPage = pageCount;
      if (pageCount > 1 && mounted) {
        final range = await _showPdfPageRangeDialog(pageCount);
        if (range == null) return;
        startPage = range[0]; endPage = range[1];
      }

      final created = await _createInsertedPages(endPage - startPage + 1);
      if (created.isEmpty) {
        await doc.dispose();
        return;
      }

      // Render at higher resolution, then display scaled down for quality.
      const displayW = 320.0;
      const renderW = 1600.0; // ~5x more pixels than display

      for (int i = startPage; i <= endPage; i++) {
        final page = doc.pages[i - 1];
        final aspect = page.height / page.width;
        final imgHDisplay = displayW * aspect;
        final imgHRender = renderW * aspect;

        final img = await page.render(
          fullWidth: renderW,
          fullHeight: imgHRender,
          backgroundColor: const Color(0xFFFFFFFF),
        );
        if (img == null) continue;
        final uiImage = await img.createImage();
        final pngBytes = await uiImage.toByteData(format: dart_ui.ImageByteFormat.png);
        if (pngBytes == null) continue;
        final tmpDir = await getTemporaryDirectory();
        final tmpFile = File('${tmpDir.path}/pdf_page_${i}_${_uuid.v4()}.png');
        await tmpFile.writeAsBytes(pngBytes.buffer.asUint8List());
        img.dispose();

        final targetPage = created[(i - startPage)];
        final imageItem = ImageItem(
          id: _uuid.v4(),
          x: 40,
          y: 40,
          width: displayW,
          height: imgHDisplay,
          filePath: tmpFile.path,
        );
        await _storage.saveCanvasData(
          targetPage.id,
          CanvasData(images: [imageItem]),
        );
      }
      await doc.dispose();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF Import fehlgeschlagen: $e')));
    }
  }

  Future<List<int>?> _showPdfPageRangeDialog(int totalPages) async {
    int start = 1, end = totalPages;
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('PDF-Seiten importieren'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$totalPages Seiten gefunden'),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Von: '),
                Expanded(child: Slider(
                  value: start.toDouble(), min: 1, max: totalPages.toDouble(),
                  divisions: math.max(1, totalPages - 1),
                  label: '$start',
                  onChanged: (v) => setLocal(() => start = v.round()),
                )),
                Text('$start'),
              ]),
              Row(children: [
                const Text('Bis:  '),
                Expanded(child: Slider(
                  value: end.toDouble(), min: 1, max: totalPages.toDouble(),
                  divisions: math.max(1, totalPages - 1),
                  label: '$end',
                  onChanged: (v) => setLocal(() => end = v.round()),
                )),
                Text('$end'),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, [math.min(start, end), math.max(start, end)]),
              child: const Text('Importieren'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alles l\u00f6schen'),
        content: const Text('Alle Zeichnungen auf dieser Seite entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
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
            child: const Text('L\u00f6schen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _importImage() async {
    try {
      final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      await _importImageAsNewPages(xfile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final xfile = await ImagePicker().pickImage(source: ImageSource.camera);
      if (xfile == null) return;
      _pushUndo();
      setState(() => _images.add(ImageItem(
            id: _uuid.v4(), x: 60, y: 60, width: 240, height: 180,
            filePath: xfile.path,
          )));
      widget.onDirty();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Kamera fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _exportShare() async {
    try {
      await Share.share('Exportiert aus Notes \u2013 ${widget.page.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _quickShare() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seite konnte nicht erfasst werden')));
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: dart_ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/quickshare_${widget.page.name}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, name: '${widget.page.name}.png', mimeType: 'image/png')],
        text: 'Notiz: ${widget.page.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('QuickShare fehlgeschlagen: $e')));
      }
    }
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> clearPageFromOutside() async {
    for (final c in _teControllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    for (final c in _cellControllers.values) {
      c.dispose();
    }
    for (final f in _cellFocusNodes.values) {
      f.dispose();
    }
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
    await saveAll();
    widget.onDirty();
  }

  Future<void> rotatePageContent90({required bool clockwise}) async {
    Rect? bounds;
    void expand(Offset p) {
      final r = Rect.fromLTWH(p.dx, p.dy, 0, 0);
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }

    for (final s in _strokes) {
      for (final p in s.points) {
        expand(p);
      }
    }
    for (final s in _shapes) {
      final r = Rect.fromLTWH(s.x, s.y, s.width, s.height);
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }
    for (final t in _textBoxes) {
      final r = Rect.fromLTWH(t.x, t.y, t.width, 60);
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }
    for (final i in _images) {
      final r = Rect.fromLTWH(i.x, i.y, i.width, i.height);
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }
    for (final t in _tables) {
      final r = Rect.fromLTWH(t.x, t.y, t.totalWidth, t.totalHeight);
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }
    if (bounds == null) return;

    final c = bounds!.center;
    Offset rot(Offset p) {
      final v = p - c;
      return clockwise
          ? Offset(c.dx + v.dy, c.dy - v.dx)
          : Offset(c.dx - v.dy, c.dy + v.dx);
    }

    Rect rotRect(Rect r) {
      final pts = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map(rot);
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final p in pts) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        final s = _strokes[i];
        _strokes[i] = _Stroke(
          points: s.points.map(rot).toList(),
          color: s.color,
          width: s.width,
          penType: s.penType,
        );
      }
      for (int i = 0; i < _shapes.length; i++) {
        final s = _shapes[i];
        final rr = rotRect(Rect.fromLTWH(s.x, s.y, s.width, s.height));
        _shapes[i] = s.copyWith(
          x: rr.left,
          y: rr.top,
          width: rr.width,
          height: rr.height,
        );
      }
      for (final tb in _textBoxes) {
        final rr = rotRect(Rect.fromLTWH(tb.x, tb.y, tb.width, 60));
        tb.x = rr.left;
        tb.y = rr.top;
      }
      for (final img in _images) {
        final rr = rotRect(Rect.fromLTWH(img.x, img.y, img.width, img.height));
        img.x = rr.left;
        img.y = rr.top;
        img.width = rr.width;
        img.height = rr.height;
      }
      for (final tbl in _tables) {
        final rr = rotRect(Rect.fromLTWH(tbl.x, tbl.y, tbl.totalWidth, tbl.totalHeight));
        tbl.x = rr.left;
        tbl.y = rr.top;
      }
    });

    await saveAll();
    widget.onDirty();
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Fingerzeichnen erlauben'),
                  subtitle: const Text('Standardm\u00e4\u00dfig sind nur Stift & Maus aktiv'),
                  value: DrawSettings.instance.allowFingerDrawing,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.allowFingerDrawing = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('[BETA] Formerkennung'),
                  subtitle: const Text('Stift halten \u2192 Linie/Form automatisch einrasten'),
                  value: DrawSettings.instance.enableShapeRecognition,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.enableShapeRecognition = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('[BETA] Ultra-minimierte Stiftverz\u00f6gerung'),
                  subtitle: const Text('Reduziert Verz\u00f6gerung bei schnellem Zeichnen'),
                  value: DrawSettings.instance.ultraLowLatency,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.ultraLowLatency = v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schlie\u00dfen')),
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
        if (!_isFullscreen) _buildToolbar(l10n),
        if (!_isFullscreen && _showSubMenu) _buildSubMenu(),
        if (!_isFullscreen && _showPenPanel && _tool == DrawTool.pen)
          _buildPenPanel(),
        Expanded(
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (_pasteIndicatorScreenPos != null) {
                    setState(() => _pasteIndicatorScreenPos = null);
                  }
                  if (e.kind != PointerDeviceKind.stylus &&
                      !CanvasClipboard.instance.isEmpty) {
                    _longPressPos = e.localPosition;
                    _longPressTimer?.cancel();
                    _longPressTimer =
                        Timer(const Duration(milliseconds: 600), () {
                      if (mounted && _longPressPos != null) {
                        setState(() =>
                            _pasteIndicatorScreenPos = _longPressPos);
                        Future.delayed(
                            const Duration(milliseconds: 800), () {
                          if (mounted &&
                              _pasteIndicatorScreenPos != null) {
                            _showCanvasPasteMenu(
                                _pasteIndicatorScreenPos);
                          }
                        });
                      }
                    });
                  }
                  final prevCount = _activePointers;
                  setState(() => _activePointers++);
                  if (prevCount == 0) {
                    _onPointerDown(e);
                  } else if (prevCount == 1) {
                    _longPressTimer?.cancel();
                    _longPressPos = null;
                    _cancelShapeRec();
                    if (_currentStroke != null && _strokes.isNotEmpty) {
                      setState(() {
                        _strokes.removeLast();
                        _currentStroke = null;
                        if (_undoStack.isNotEmpty) _undoStack.removeLast();
                      });
                    }
                    setState(() {
                      _drawingShape = false;
                      _shapeStart = null;
                      _ghostShape = null;
                      _drawingLasso = false;
                      _drawingResizeLasso = false;
                    });
                  }
                },
                onPointerMove: (e) {
                  _longPressTimer?.cancel();
                  _longPressPos = null;
                  if (_activePointers < 2) _onPointerMove(e);
                },
                onPointerUp: (e) {
                  _longPressTimer?.cancel();
                  _longPressPos = null;
                  _onPointerUp(e);
                  setState(() =>
                      _activePointers = math.max(0, _activePointers - 1));
                },
                onPointerCancel: (e) {
                  _longPressTimer?.cancel();
                  _longPressPos = null;
                  setState(() =>
                      _activePointers = math.max(0, _activePointers - 1));
                },
                child: InteractiveViewer(
                  transformationController: _xfCtrl,
                  panEnabled: false,
                  minScale: 0.2,
                  maxScale: 5.0,
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: SizedBox.expand(
                      child: Stack(
                        children: [
                          // ── Paper background ─────────────────────────────
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: PaperPainter(widget.page.paperType),
                              ),
                            ),
                          ),

                          // ── Images (background — ink draws ON TOP) ───────
                          ..._buildImages(),

                          // ── Ink strokes (above images) ───────────────────
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ListenableBuilder(
                                listenable: _inkRepaintNotifier,
                                builder: (_, __) => CustomPaint(
                                  painter: _InkPainter(
                                    strokes: _strokes,
                                    useHighQuality:
                                        !DrawSettings.instance.ultraLowLatency,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Shapes ───────────────────────────────────────
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

                          // ── Shape delete handle ──────────────────────────
                          if (_tool == DrawTool.move && _selectedShapeId != null)
                            _shapeDeleteHandle(),

                          // ── Text boxes ───────────────────────────────────
                          ..._buildTextBoxes(),

                          // ── Tables ───────────────────────────────────────
                          ..._buildTables(),

                          // ── Lasso outline ────────────────────────────────
                          if (_drawingLasso || _lassoReady)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: LassoPainter(
                                    _lassoPoints,
                                    closed: _lassoReady,
                                    marchOffset: _marchOffset,
                                  ),
                                ),
                              ),
                            ),

                          // ── Resize lasso outline ─────────────────────────
                          if (_drawingResizeLasso || _resizeLassoReady)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _ResizeLassoPainter(
                                    _resizeLassoPoints,
                                    closed: _resizeLassoReady,
                                    selectionRect: _resizeSelectionRect,
                                  ),
                                ),
                              ),
                            ),

                          // ── Eraser cursor ────────────────────────────────
                          if (_tool == DrawTool.eraser && _eraserPos != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _EraserCursorPainter(
                                    position: _eraserPos!,
                                    radius: (_effectiveEraserSize / 2) / _zoomScale,
                                  ),
                                ),
                              ),
                            ),

                          // ── Page info ────────────────────────────────────
                          Positioned(
                            bottom: 8, right: 60,
                            child: IgnorePointer(
                              child: Text(
                                _pageInfo(),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Paste indicator ──────────────────────────────────────────
              if (_pasteIndicatorScreenPos != null)
                Positioned(
                  left: _pasteIndicatorScreenPos!.dx - 20,
                  top: _pasteIndicatorScreenPos!.dy - 20,
                  child: IgnorePointer(
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.green.shade400.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.green.shade200, blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: const Icon(Icons.content_paste, color: Colors.white, size: 20),
                    ),
                  ),
                ),

              // ── Lasso context menu ───────────────────────────────────────
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
                      onPaste: CanvasClipboard.instance.isEmpty ? null : _lassoPaste,
                    ),
                  );
                }),

              // ── Image context menu ───────────────────────────────────────
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
                      onPaste: CanvasClipboard.instance.isEmpty ? null : _lassoPaste,
                    ),
                  );
                }),

              // ── Table overlay buttons ────────────────────────────────────
              ..._buildTableOverlayButtons(),

              // ── Colour bubble ────────────────────────────────────────────
              Positioned.fill(
                child: Align(
                  alignment: _paletteCornerAlignment,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onPanEnd: (d) {
                        final vx = d.velocity.pixelsPerSecond.dx;
                        final vy = d.velocity.pixelsPerSecond.dy;
                        setState(() {
                          if (vx < 0 && vy < 0) _paletteCornerIdx = 0;
                          else if (vx >= 0 && vy < 0) _paletteCornerIdx = 1;
                          else if (vx < 0 && vy >= 0) _paletteCornerIdx = 2;
                          else _paletteCornerIdx = 3;
                        });
                      },
                      child: FloatingColorBubble(
                        color: _color,
                        onColorChanged: (c) => setState(() => _color = c),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Alignment get _paletteCornerAlignment {
    switch (_paletteCornerIdx) {
      case 0: return Alignment.topLeft;
      case 1: return Alignment.topRight;
      case 2: return Alignment.bottomLeft;
      default: return Alignment.bottomRight;
    }
  }

  String _pageInfo() {
    final d = widget.page.createdAt;
    final pad = (int n) => n.toString().padLeft(2, '0');
    return 'Seite ${widget.page.order + 1}  \u2022  ${pad(d.day)}.${pad(d.month)}.${d.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Context menu
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
            _ctxBtn(Icons.delete_outline, Colors.red, 'L\u00f6schen', onDelete),
            _ctxDivider(),
            _ctxBtn(Icons.content_cut, Colors.orange.shade700, 'Ausschneiden', onCut),
            _ctxDivider(),
            _ctxBtn(Icons.copy, Colors.blue.shade700, 'Kopieren', onCopy),
            _ctxDivider(),
            _ctxBtn(
              Icons.content_paste,
              onPaste != null ? Colors.green.shade700 : Colors.grey.shade400,
              'Einf\u00fcgen', onPaste,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctxBtn(IconData icon, Color color, String tooltip, VoidCallback? onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );

  Widget _ctxDivider() => Container(
        width: 1, height: 22, color: Colors.grey.shade200,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Image widgets
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildImages() {
    // When tool is not move/lasso, images are IgnorePointer so pen events pass through
    final imgInteractive = _tool == DrawTool.move || _tool == DrawTool.lasso || _lassoReady;

    return _images.map((img) {
      final isSelected = _selectedImageId == img.id && _tool == DrawTool.move;
      final canInteract = !_lassoReady;

      // When not in move/lasso mode, images are transparent to pen events
      if (!imgInteractive) {
        return Positioned(
          left: img.x, top: img.y, width: img.width, height: img.height,
          child: Transform.rotate(
            angle: img.rotation,
            child: IgnorePointer(child: imgHelper.buildFileImage(img.filePath)),
          ),
        );
      }
      return Positioned(
        left: img.x,
        top: img.y,
        width: img.width,
        height: img.height,
        child: GestureDetector(
          onPanUpdate: canInteract ? (d) {
            setState(() { img.x += d.delta.dx; img.y += d.delta.dy; });
            widget.onDirty();
          } : null,
          onScaleStart: (d) {
            _imgScaleStart[img.id] = Size(img.width, img.height);
          },
          onScaleUpdate: (d) {
            final base = _imgScaleStart[img.id];
            if (base == null) return;
            setState(() {
              img.width  = math.max(40.0, base.width  * d.scale);
              img.height = math.max(30.0, base.height * d.scale);
              img.rotation += d.rotation;
            });
            widget.onDirty();
          },
          onScaleEnd: (_) => _imgScaleStart.remove(img.id),
          onLongPress: () => _showImageContextSheet(img.id),
          child: Transform.rotate(
            angle: img.rotation,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: imgHelper.buildFileImage(img.filePath)),
                if (isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 4, right: 4,
                  child: GestureDetector(
                    onTap: () => _showImageContextSheet(img.id),
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: GestureDetector(
                    onPanStart: (d) {
                      _imgResizeStart[img.id]    = d.globalPosition;
                      _imgResizeBaseSize[img.id] = Size(img.width, img.height);
                    },
                    onPanUpdate: (d) {
                      final start = _imgResizeStart[img.id];
                      final base  = _imgResizeBaseSize[img.id];
                      if (start == null || base == null) return;
                      final delta = d.globalPosition - start;
                      setState(() {
                        img.width  = math.max(40.0, base.width  + delta.dx);
                        img.height = math.max(30.0, base.height + delta.dy);
                      });
                      widget.onDirty();
                    },
                    onPanEnd: (_) {
                      _imgResizeStart.remove(img.id);
                      _imgResizeBaseSize.remove(img.id);
                    },
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.85),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                        ),
                      ),
                      child: const Icon(Icons.open_in_full, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  top: 0, right: 32,
                  child: GestureDetector(
                    onPanStart: (d) {
                      _imgRotateStart[img.id]     = d.globalPosition.direction;
                      _imgRotateBaseAngle[img.id] = img.rotation;
                    },
                    onPanUpdate: (d) {
                      final startAngle = _imgRotateStart[img.id];
                      final baseAngle  = _imgRotateBaseAngle[img.id];
                      if (startAngle == null || baseAngle == null) return;
                      final center = Offset(
                        img.x + img.width / 2,
                        img.y + img.height / 2,
                      );
                      final globalOff = d.globalPosition - center;
                      setState(() => img.rotation = globalOff.direction - math.pi / 2);
                      widget.onDirty();
                    },
                    onPanEnd: (_) {
                      _imgRotateStart.remove(img.id);
                      _imgRotateBaseAngle.remove(img.id);
                    },
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.rotate_right, size: 15, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  void _showImageContextSheet(String id) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.blue),
              title: const Text('Kopieren'),
              onTap: () { Navigator.pop(ctx); _copyImage(id); },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut, color: Colors.orange),
              title: const Text('Ausschneiden'),
              onTap: () { Navigator.pop(ctx); _cutImage(id); },
            ),
            ListTile(
              leading: const Icon(Icons.flip, color: Colors.purple),
              title: const Text('Horizontal spiegeln'),
              onTap: () {
                Navigator.pop(ctx);
                final idx = _images.indexWhere((i) => i.id == id);
                if (idx >= 0) setState(() => _images[idx].rotation = -_images[idx].rotation);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('L\u00f6schen'),
              onTap: () { Navigator.pop(ctx); _deleteImage(id); },
            ),
          ],
        ),
      ),
    );
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
      final isFocused = focus.hasFocus;

      return Positioned(
        left: tb.x, top: tb.y, width: tb.width,
        child: GestureDetector(
          onPanUpdate: _tool == DrawTool.move
              ? (d) {
                  setState(() { tb.x += d.delta.dx; tb.y += d.delta.dy; });
                  widget.onDirty();
                }
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (isFocused)
                Positioned(
                  top: -46,
                  left: 0,
                  child: _buildTextFormatBar(tb),
                ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  border: Border.all(
                    color: isFocused ? Colors.blue.shade600
                        : inLasso ? Colors.blue
                        : _tool == DrawTool.move ? Colors.blue.withOpacity(0.5)
                        : Colors.grey.shade300,
                    width: isFocused || inLasso ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isFocused ? [
                    BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 6)
                  ] : null,
                ),
                child: TextField(
                  controller: ctrl, focusNode: focus, maxLines: null,
                  style: TextStyle(
                    fontSize: tb.fontSize, color: Color(tb.colorValue),
                    fontWeight: tb.bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: tb.italic ? FontStyle.italic : FontStyle.normal,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none, isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Hier tippen\u2026',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ),
              if (_tool == DrawTool.move)
                Positioned(top: -10, right: -10, child: _delBtn(() => _deleteTextBox(tb.id))),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTextFormatBar(TextBoxItem tb) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fmtBtn(
              icon: Icons.format_bold,
              active: tb.bold,
              onTap: () => setState(() { tb.bold = !tb.bold; widget.onDirty(); }),
              tooltip: 'Fett',
            ),
            _fmtDivider(),
            _fmtBtn(
              icon: Icons.format_italic,
              active: tb.italic,
              onTap: () => setState(() { tb.italic = !tb.italic; widget.onDirty(); }),
              tooltip: 'Kursiv',
            ),
            _fmtDivider(),
            _fmtBtn(
              icon: Icons.text_decrease,
              active: false,
              onTap: () => setState(() { tb.fontSize = math.max(8, tb.fontSize - 2); widget.onDirty(); }),
              tooltip: 'Kleiner',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${tb.fontSize.round()}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
            _fmtBtn(
              icon: Icons.text_increase,
              active: false,
              onTap: () => setState(() { tb.fontSize = math.min(72, tb.fontSize + 2); widget.onDirty(); }),
              tooltip: 'Gr\u00f6\u00dfer',
            ),
            _fmtDivider(),
            GestureDetector(
              onTap: () => _showColorDialog(),
              child: Tooltip(
                message: 'Farbe',
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: Color(tb.colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fmtBtn({required IconData icon, required bool active, required VoidCallback onTap, required String tooltip}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active ? Colors.blue.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18,
                color: active ? Colors.blue.shade700 : Colors.grey.shade700),
          ),
        ),
      );

  Widget _fmtDivider() => Container(
        width: 1, height: 20, color: Colors.grey.shade200,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Table widgets
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildTables() {
    return _tables.map((tbl) {
      final isSel = _selectedTableId == tbl.id && _tool == DrawTool.move;
      final inLasso = _lassoReady && _lassoTableIds.contains(tbl.id);
      return Positioned(
        left: tbl.x, top: tbl.y,
        child: GestureDetector(
          onPanUpdate: _tool == DrawTool.move
              ? (d) {
                  setState(() { tbl.x += d.delta.dx; tbl.y += d.delta.dy; });
                  widget.onDirty();
                }
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: inLasso ? Colors.blue
                        : isSel ? Colors.blue.withOpacity(0.7)
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
                                  ? BorderSide(color: Color(tbl.colorValue), width: 0.8)
                                  : BorderSide.none,
                              bottom: r < tbl.rows - 1
                                  ? BorderSide(color: Color(tbl.colorValue), width: 0.8)
                                  : BorderSide.none,
                            ),
                          ),
                          child: ctrl != null && focus != null
                              ? TextField(
                                  controller: ctrl, focusNode: focus,
                                  style: const TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center, maxLines: 1,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none, isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                Positioned(top: -12, right: -12, child: _delBtn(() => _deleteTable(tbl.id))),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildTableOverlayButtons() {
    if (_tool != DrawTool.move || _selectedTableId == null) return [];
    final tblIdx = _tables.indexWhere((t) => t.id == _selectedTableId);
    if (tblIdx < 0) return [];
    final tbl = _tables[tblIdx];
    final bottomLeft = _toScreen(Offset(tbl.x, tbl.y + tbl.totalHeight));
    final topRight   = _toScreen(Offset(tbl.x + tbl.totalWidth, tbl.y));
    return [
      Positioned(
        left: bottomLeft.dx, top: bottomLeft.dy + 4,
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
        left: topRight.dx + 4, top: topRight.dy,
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
            color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.blue.shade700),
              Text(label, style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
            ],
          ),
        ),
      );

  Widget _shapeDeleteHandle() {
    final shape = _shapes.firstWhere(
      (s) => s.id == _selectedShapeId,
      orElse: () => ShapeItem(id: '', shapeType: '', x: 0, y: 0, width: 0, height: 0, colorValue: 0),
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
          width: 24, height: 24,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 16, color: Colors.white),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Toolbar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildToolbar(AppLocalizations l10n) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (_toolbarDragActive) {
          setState(() => _toolbarDx += d.delta.dx);
        }
      },
      onLongPressStart: (_) => setState(() => _toolbarDragActive = true),
      onLongPressEnd: (_)   => setState(() => _toolbarDragActive = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        transform: Matrix4.translationValues(_toolbarDx, 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          boxShadow: _toolbarDragActive
              ? [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 8)]
              : null,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
          children: [
            Tooltip(
              message: l10n.pen,
              child: GestureDetector(
                onTap: () {
                  if (_tool == DrawTool.pen) {
                    setState(() => _showPenPanel = !_showPenPanel);
                  } else {
                    setState(() {
                      _tool = DrawTool.pen;
                      _showSubMenu = false;
                      _clearLasso();
                      _clearResizeLasso();
                      _showPenPanel = false;
                    });
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: _tool == DrawTool.pen
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _penType == PenType.fountainPen
                        ? Icons.edit
                        : _penType == PenType.brushPen
                            ? Icons.brush
                            : Icons.create,
                    size: 22,
                    color: _tool == DrawTool.pen
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            if (_tool == DrawTool.pen) ...[
              const SizedBox(width: 4),
              ...[1.5, 3.0, 6.0].map((w) => GestureDetector(
                onTap: () => setState(() => _penWidth = w),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 14),
                  width: w * 3 + 8,
                  height: w * 3 + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _penWidth == w ? _color : Colors.transparent,
                    border: Border.all(
                      color: _penWidth == w ? _color : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                ),
              )),
              const SizedBox(width: 4),
            ],
            _toolBtnCustom(
              icon: Icons.auto_fix_high,
              tool: DrawTool.eraser,
              tooltip: l10n.eraser,
              badge: null,
              onTap: () => setState(() {
                _tool = DrawTool.eraser;
                _showSubMenu = false;
                _showPenPanel = false;
              }),
            ),
            if (_tool == DrawTool.eraser) ...[
              GestureDetector(
                onTap: () => setState(() {
                  _eraserMode = EraserMode.values[(_eraserMode.index + 1) % EraserMode.values.length];
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _eraserMode == EraserMode.normal ? Icons.auto_fix_normal
                            : _eraserMode == EraserMode.precision ? Icons.auto_fix_high
                            : Icons.horizontal_rule,
                        size: 13, color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _eraserMode == EraserMode.normal ? 'Normal'
                            : _eraserMode == EraserMode.precision ? 'Pr\u00e4zision'
                            : 'Linie',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_right, size: 13, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              ...[16.0, 28.0, 48.0].map((sz) => GestureDetector(
                onTap: () => setState(() => _eraserSize = sz),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
                  width: sz * 0.45 + 8,
                  height: sz * 0.45 + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _eraserSize == sz ? Colors.grey.shade300 : Colors.transparent,
                    border: Border.all(
                      color: _eraserSize == sz ? Colors.blueAccent : Colors.grey.shade400,
                      width: _eraserSize == sz ? 2.0 : 1.5,
                    ),
                  ),
                ),
              )),
            ],
            _toolBtn(Icons.open_with, DrawTool.move, l10n.move),
            _toolBtn(Icons.text_fields, DrawTool.textBox, l10n.textBox),
            _toolBtn(Icons.table_chart_outlined, DrawTool.table, 'Tabelle'),
            _toolBtn(Icons.category_outlined, DrawTool.shape, l10n.shape,
                onTapOverride: () => setState(() {
                      _tool = DrawTool.shape;
                      _showSubMenu = !_showSubMenu;
                    })),
            _toolBtn(Icons.gesture, DrawTool.lasso, l10n.lasso),
            _toolBtn(Icons.open_in_full, DrawTool.resize, 'Gr\u00f6\u00dfe \u00e4ndern'),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Einf\u00fcgen',
              child: IconButton(
                icon: Icon(Icons.content_paste, size: 22,
                    color: CanvasClipboard.instance.isEmpty
                        ? Colors.grey.shade300 : Colors.green.shade600),
                onPressed: CanvasClipboard.instance.isEmpty ? null : _lassoPaste,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 36),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _showColorDialog,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _color, shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _actionBtn(Icons.undo, l10n.undo, _undo),
            _actionBtn(Icons.redo, l10n.redo, _redo),
            _actionBtn(Icons.delete_forever, l10n.clearAll, _clearAll),
            _actionBtn(Icons.settings_outlined, 'Einstellungen', _showSettings),
            // QuickShare button
            Tooltip(
              message: 'QuickShare (AirDrop)',
              child: IconButton(
                icon: const Icon(Icons.share, size: 22, color: Colors.teal),
                onPressed: _quickShare,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 36),
              ),
            ),
            // Fullscreen toggle
            Tooltip(
              message: _isFullscreen ? 'Vollbild verlassen' : 'Vollbild',
              child: IconButton(
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 22, color: Colors.grey.shade600,
                ),
                onPressed: _toggleFullscreen,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 36),
              ),
            ),
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
    ),
  );
  }

  Widget _toolBtn(IconData icon, DrawTool tool, String tooltip,
      {VoidCallback? onTapOverride}) {
    final active = _tool == tool;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTapOverride ?? () => setState(() {
              _tool = tool;
              if (tool != DrawTool.shape) _showSubMenu = false;
              if (tool != DrawTool.lasso) _clearLasso();
              if (tool != DrawTool.resize) _clearResizeLasso();
            }),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22,
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
            color: active ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600),
              if (badge != null)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)),
                    child: Text(badge, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
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
        title: const Text('Farbe w\u00e4hlen'),
        content: ColorPalette(
          selectedColor: _color,
          onColorChanged: (c) {
            setState(() => _color = c);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schlie\u00dfen')),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GoodNotes-style Pen Settings Panel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPenPanel() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: PenType.values.map((pt) {
              final selected = _penType == pt;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _penType = pt),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? Colors.grey.shade700 : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Icon(pt.icon, color: selected ? Colors.white : Colors.grey.shade400, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          pt.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? Colors.white : Colors.grey.shade500,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _penSlider('SCH\u00c4RFE DER SPITZE', _tipSharpness,
              (v) => setState(() => _tipSharpness = v)),
          _penSlider('DRUCKEMPFINDLICHKEIT', _pressureSensitivity,
              (v) => setState(() => _pressureSensitivity = v)),
          _penSlider('STRICH-STABILISIERUNG', _strokeStabilization,
              (v) => setState(() { _strokeStabilization = v; DrawSettings.instance.ultraLowLatency = v < 20; })),
          const SizedBox(height: 4),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 4),
          Text('EINSTELLUNGEN',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500, letterSpacing: 1)),
          Row(
            children: [
              Expanded(
                child: Text('Zeichnen und Halten',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
              Switch(
                value: _drawAndHold,
                onChanged: (v) {
                  setState(() {
                    _drawAndHold = v;
                    DrawSettings.instance.enableShapeRecognition = v;
                  });
                },
                activeColor: const Color(0xFF2E6DA4),
              ),
            ],
          ),
          GestureDetector(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Stiftgesten',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Text(
              'Eingabestift Trennen',
              style: TextStyle(color: Colors.red.shade400, fontSize: 14),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _penSlider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500, letterSpacing: 0.8),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF5BAEF5),
                inactiveTrackColor: Colors.grey.shade700,
                thumbColor: const Color(0xFF5BAEF5),
                overlayColor: Colors.blue.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${value.round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubMenu() {
    return Container(
      height: 48,
      color: Colors.grey.shade50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: ShapeType.values.map((st) {
          final active = _shapeType == st;
          return GestureDetector(
            onTap: () => setState(() { _shapeType = st; _showSubMenu = false; }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? Colors.blue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active ? Colors.blue : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _shapeIcon(st, active),
                  const SizedBox(width: 5),
                  Text(
                    st.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: active ? Colors.white : Colors.grey.shade700,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _shapeIcon(ShapeType st, bool active) {
    final color = active ? Colors.white : Colors.grey.shade700;
    switch (st) {
      case ShapeType.rectangle:   return Icon(Icons.rectangle_outlined, size: 14, color: color);
      case ShapeType.circle:      return Icon(Icons.circle_outlined, size: 14, color: color);
      case ShapeType.triangle:    return _miniSvgTriangle(color, 'up');
      case ShapeType.rightTriangle: return _miniSvgTriangle(color, 'right');
      case ShapeType.leftTriangle:  return _miniSvgTriangle(color, 'left');
      case ShapeType.arrow:       return Icon(Icons.arrow_upward, size: 14, color: color);
      case ShapeType.lineArrow:   return Icon(Icons.arrow_forward, size: 14, color: color);
      case ShapeType.star:        return Icon(Icons.star_border, size: 14, color: color);
    }
  }

  Widget _miniSvgTriangle(Color color, String direction) {
    return CustomPaint(
      size: const Size(14, 14),
      painter: _MiniTrianglePainter(color: color, direction: direction),
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
          child: Text(label, style: TextStyle(
            fontSize: 12,
            color: active ? Colors.white : Colors.grey.shade700,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
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
  final PenType penType;

  _Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.penType,
  });

  _Stroke copy() => _Stroke(
        points: List.from(points),
        color: color,
        width: width,
        penType: penType,
      );

  Map<String, dynamic> toJson() => {
        'color': color.value,
        'width': width,
        'penType': penType.index,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      };

  factory _Stroke.fromJson(Map<String, dynamic> j) => _Stroke(
        color: Color(j['color'] as int),
        width: (j['width'] as num).toDouble(),
        penType: PenType.values[j['penType'] as int? ?? PenType.ballpoint.index],
        points: (j['points'] as List<dynamic>)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Ink painter — supports 3 pen types
// ---------------------------------------------------------------------------

class _InkPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final bool useHighQuality;
  _InkPainter({
    required this.strokes,
    this.useHighQuality = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) _paintStroke(canvas, s);
  }

  void _paintStroke(Canvas canvas, _Stroke s) {
    if (s.points.isEmpty) return;
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2,
          Paint()..color = s.color..style = PaintingStyle.fill);
      return;
    }
    switch (s.penType) {
      case PenType.fountainPen: _paintFountainStroke(canvas, s); break;
      case PenType.brushPen:    _paintBrushStroke(canvas, s); break;
      case PenType.ballpoint:   _paintBallpointStroke(canvas, s); break;
    }
  }

  // Ballpoint: smooth bezier, uniform width
  void _paintBallpointStroke(Canvas canvas, _Stroke s) {
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    if (!useHighQuality) {
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) path.lineTo(s.points[i].dx, s.points[i].dy);
      canvas.drawPath(path, paint);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length - 1; i++) {
      final mid = Offset((s.points[i].dx + s.points[i+1].dx)/2, (s.points[i].dy + s.points[i+1].dy)/2);
      path.quadraticBezierTo(s.points[i].dx, s.points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(s.points.last.dx, s.points.last.dy);
    canvas.drawPath(path, paint);
  }

  // Fountain pen: tapers at start and end, thicker in the middle
  void _paintFountainStroke(Canvas canvas, _Stroke s) {
    final n = s.points.length;
    if (n < 2) return;
    for (int i = 0; i < n - 1; i++) {
      final t = i / (n - 1).toDouble();
      final envelope = math.sin(math.pi * t); // 0→1→0
      final w = s.width * (0.35 + 0.75 * envelope);
      final paint = Paint()
        ..color = s.color.withOpacity(0.82 + 0.18 * envelope)
        ..strokeWidth = w.clamp(0.5, s.width * 1.8)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      canvas.drawLine(s.points[i], s.points[i + 1], paint);
    }
  }

  // Brush pen: thick when slow, thin when fast
  void _paintBrushStroke(Canvas canvas, _Stroke s) {
    final n = s.points.length;
    if (n < 2) return;
    final speeds = <double>[for (int i = 0; i < n-1; i++) (s.points[i+1] - s.points[i]).distance];
    final maxSpd = speeds.isEmpty ? 1.0 : speeds.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    for (int i = 0; i < n - 1; i++) {
      final spd = speeds[i] / maxSpd;
      final w = s.width * (1.8 - spd * 1.2);
      final paint = Paint()
        ..color = s.color.withOpacity((0.7 + spd * 0.3).clamp(0.0, 1.0))
        ..strokeWidth = w.clamp(0.3, s.width * 2.8)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      canvas.drawLine(s.points[i], s.points[i + 1], paint);
    }
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
    canvas.drawCircle(position, radius,
        Paint()..color = Colors.white.withOpacity(0.01)..style = PaintingStyle.fill);
    canvas.drawCircle(position, radius,
        Paint()..color = Colors.black.withOpacity(0.7)..strokeWidth = 1.5..style = PaintingStyle.stroke);
    canvas.drawCircle(position, radius - 1,
        Paint()..color = Colors.grey.withOpacity(0.15)..strokeWidth = 1.0..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_EraserCursorPainter old) =>
      old.position != position || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Resize lasso painter
// ---------------------------------------------------------------------------

class _ResizeLassoPainter extends CustomPainter {
  final List<Offset> points;
  final bool closed;
  final Rect? selectionRect;

  _ResizeLassoPainter(this.points, {this.closed = false, this.selectionRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = Colors.orange.shade600
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (closed && selectionRect != null) {
      final r = selectionRect!.inflate(12);
      final path = Path()..addRect(r);
      final metrics = path.computeMetrics();
      const dashLen = 9.0;
      const gapLen = 5.0;
      for (final metric in metrics) {
        double distance = 0.0;
        bool draw = true;
        while (distance < metric.length) {
          final len = draw ? dashLen : gapLen;
          if (draw) {
            canvas.drawPath(
              metric.extractPath(distance, math.min(distance + len, metric.length)),
              paint,
            );
          }
          distance += len;
          draw = !draw;
        }
      }
      final handle = r.bottomRight;
      canvas.drawCircle(handle, 10,
          Paint()..color = Colors.orange.shade600..style = PaintingStyle.fill);
      canvas.drawCircle(handle, 10,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawLine(handle + const Offset(-5, -5), handle + const Offset(5, 5),
          Paint()..color = Colors.white..strokeWidth = 2..strokeCap = StrokeCap.round);
      canvas.drawLine(handle + const Offset(0, -5), handle + const Offset(5, 5),
          Paint()..color = Colors.white..strokeWidth = 2..strokeCap = StrokeCap.round);
      canvas.drawLine(handle + const Offset(-5, 0), handle + const Offset(5, 5),
          Paint()..color = Colors.white..strokeWidth = 2..strokeCap = StrokeCap.round);
    } else {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length - 1; i++) {
        final mid = Offset(
          (points[i].dx + points[i + 1].dx) / 2,
          (points[i].dy + points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ResizeLassoPainter old) => true;
}

// ---------------------------------------------------------------------------
// Ink repaint notifier
// ---------------------------------------------------------------------------

class _InkRepaintNotifier extends ChangeNotifier {
  void notifyListeners() => super.notifyListeners();
}

// ---------------------------------------------------------------------------
// Snapshot for undo/redo
// ---------------------------------------------------------------------------

class _Snapshot {
  final List<_Stroke> strokes;
  final List<ShapeItem> shapes;
  final List<TextBoxItem> textBoxes;
  final List<TableItem> tables;
  final List<ImageItem> images;

  const _Snapshot({
    required this.strokes,
    required this.shapes,
    required this.textBoxes,
    required this.tables,
    required this.images,
  });
}

// ---------------------------------------------------------------------------
// Mini triangle icon painter for shape submenu
// ---------------------------------------------------------------------------

class _MiniTrianglePainter extends CustomPainter {
  final Color color;
  final String direction; // 'up', 'right', 'left'

  _MiniTrianglePainter({required this.color, required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width, h = size.height;
    final path = Path();
    switch (direction) {
      case 'up':
        path.moveTo(w / 2, 0);
        path.lineTo(w, h);
        path.lineTo(0, h);
        break;
      case 'right':
        path.moveTo(0, 0);
        path.lineTo(w, h);
        path.lineTo(0, h);
        break;
      case 'left':
        path.moveTo(w, 0);
        path.lineTo(w, h);
        path.lineTo(0, h);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniTrianglePainter old) =>
      old.color != color || old.direction != direction;
}
