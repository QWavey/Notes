import '../models/canvas_item.dart';

// ---------------------------------------------------------------------------
// Global in-memory clipboard — persists across pages AND notebooks
// ---------------------------------------------------------------------------

class CanvasClipboard {
  CanvasClipboard._();
  static final CanvasClipboard instance = CanvasClipboard._();

  List<Map<String, dynamic>> shapes   = [];
  List<Map<String, dynamic>> textBoxes = [];
  List<Map<String, dynamic>> images   = [];
  List<Map<String, dynamic>> tables   = [];
  List<Map<String, dynamic>> strokes  = [];

  bool get isEmpty =>
      shapes.isEmpty && textBoxes.isEmpty &&
      images.isEmpty && tables.isEmpty && strokes.isEmpty;

  void clear() {
    shapes.clear(); textBoxes.clear();
    images.clear(); tables.clear(); strokes.clear();
  }

  void copySelection({
    required List<ShapeItem> shapeList,
    required List<TextBoxItem> textList,
    required List<ImageItem> imageList,
    required List<TableItem> tableList,
    required List<Map<String, dynamic>> strokeList,
  }) {
    clear();
    shapes   = shapeList.map((s) => Map<String, dynamic>.from(s.toJson())).toList();
    textBoxes= textList.map((t) => Map<String, dynamic>.from(t.toJson())).toList();
    images   = imageList.map((i) => Map<String, dynamic>.from(i.toJson())).toList();
    tables   = tableList.map((t) => Map<String, dynamic>.from(t.toJson())).toList();
    strokes  = strokeList.map((s) => Map<String, dynamic>.from(s)).toList();
  }
}
