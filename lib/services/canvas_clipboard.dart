import '../models/canvas_item.dart';
import 'package:flutter/material.dart';
// ---------------------------------------------------------------------------
// Global clipboard — survives page and notebook navigation
// ---------------------------------------------------------------------------

class CanvasClipboard {
  CanvasClipboard._();
  static final CanvasClipboard instance = CanvasClipboard._();

  List<_ClipShape> shapes = [];
  List<_ClipText> textBoxes = [];
  List<_ClipImage> images = [];
  List<_ClipTable> tables = [];
  List<_ClipStroke> strokes = [];

  bool get isEmpty =>
      shapes.isEmpty &&
      textBoxes.isEmpty &&
      images.isEmpty &&
      tables.isEmpty &&
      strokes.isEmpty;

  void clear() {
    shapes.clear();
    textBoxes.clear();
    images.clear();
    tables.clear();
    strokes.clear();
  }

  /// Copy all passed items (deep copy from JSON)
  void copyItems({
    required List<ShapeItem> shapes,
    required List<TextBoxItem> textBoxes,
    required List<ImageItem> images,
    required List<TableItem> tables,
    required List<dynamic> strokes, // _Stroke — passed as serialisable maps
    required Offset centroid,
  }) {
    clear();
    this.shapes = shapes
        .map((s) => _ClipShape(s.toJson(), centroid))
        .toList();
    this.textBoxes = textBoxes
        .map((t) => _ClipText(t.toJson(), centroid))
        .toList();
    this.images = images
        .map((i) => _ClipImage(i.toJson(), centroid))
        .toList();
    this.tables = tables
        .map((t) => _ClipTable(t.toJson(), centroid))
        .toList();
    this.strokes = strokes
        .map((s) => _ClipStroke(s as Map<String, dynamic>, centroid))
        .toList();
  }
}

class _ClipShape {
  final Map<String, dynamic> json;
  final Offset centroid;
  _ClipShape(this.json, this.centroid);
}

class _ClipText {
  final Map<String, dynamic> json;
  final Offset centroid;
  _ClipText(this.json, this.centroid);
}

class _ClipImage {
  final Map<String, dynamic> json;
  final Offset centroid;
  _ClipImage(this.json, this.centroid);
}

class _ClipTable {
  final Map<String, dynamic> json;
  final Offset centroid;
  _ClipTable(this.json, this.centroid);
}

class _ClipStroke {
  final Map<String, dynamic> json;
  final Offset centroid;
  _ClipStroke(this.json, this.centroid);
}
