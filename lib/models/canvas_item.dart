import 'dart:ui';

// ─── Shape Item ───────────────────────────────────────────────────────────────

class ShapeItem {
  final String id;
  final String shapeType; // 'rectangle' | 'circle' | 'isoscelesTriangle' | 'rightTriangle' | 'arrow' | 'star'
  double x, y, width, height;
  int colorValue;
  double strokeWidth;
  bool filled;

  ShapeItem({
    required this.id,
    required this.shapeType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.colorValue,
    this.strokeWidth = 2.0,
    this.filled = false,
  });

  Offset get center => Offset(x + width / 2, y + height / 2);

  Map<String, dynamic> toJson() => {
        'id': id,
        'shapeType': shapeType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'filled': filled,
      };

  factory ShapeItem.fromJson(Map<String, dynamic> j) => ShapeItem(
        id: j['id'] as String,
        shapeType: j['shapeType'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        colorValue: j['colorValue'] as int,
        strokeWidth: (j['strokeWidth'] as num? ?? 2.0).toDouble(),
        filled: j['filled'] as bool? ?? false,
      );

  ShapeItem copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? colorValue,
    double? strokeWidth,
    bool? filled,
  }) =>
      ShapeItem(
        id: id,
        shapeType: shapeType,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        colorValue: colorValue ?? this.colorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        filled: filled ?? this.filled,
      );
}

// ─── TextBox Item ─────────────────────────────────────────────────────────────

class TextBoxItem {
  final String id;
  double x, y, width;
  String text;
  int colorValue;
  double fontSize;
  bool bold;
  bool italic;

  TextBoxItem({
    required this.id,
    required this.x,
    required this.y,
    this.width = 200,
    this.text = '',
    required this.colorValue,
    this.fontSize = 16,
    this.bold = false,
    this.italic = false,
  });

  Offset get center => Offset(x + width / 2, y + 30);

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'text': text,
        'colorValue': colorValue,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
      };

  factory TextBoxItem.fromJson(Map<String, dynamic> j) => TextBoxItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num? ?? 200).toDouble(),
        text: j['text'] as String? ?? '',
        colorValue: j['colorValue'] as int,
        fontSize: (j['fontSize'] as num? ?? 16).toDouble(),
        bold: j['bold'] as bool? ?? false,
        italic: j['italic'] as bool? ?? false,
      );
}

// ─── Image Item ───────────────────────────────────────────────────────────────

class ImageItem {
  final String id;
  double x, y, width, height;
  double rotation; // radians
  final String filePath;
  /// When true the image is a locked full-page background (imported page/PDF).
  /// It fills the whole canvas, cannot be moved or resized, and draws below ink.
  final bool isPageBackground;

  ImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    required this.filePath,
    this.isPageBackground = false,
  });

  Offset get center => Offset(x + width / 2, y + height / 2);

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'filePath': filePath,
        'isPageBackground': isPageBackground,
      };

  factory ImageItem.fromJson(Map<String, dynamic> j) => ImageItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        rotation: (j['rotation'] as num? ?? 0.0).toDouble(),
        filePath: j['filePath'] as String,
        isPageBackground: j['isPageBackground'] as bool? ?? false,
      );
}

// ─── Table Item ─────────────────────────────────────────────────────────────

class TableItem {
  final String id;
  double x, y;
  double cellWidth;
  double cellHeight;
  int rows;
  int cols;
  // cells[row][col] = text
  List<List<String>> cells;
  int colorValue;

  TableItem({
    required this.id,
    required this.x,
    required this.y,
    this.cellWidth = 80,
    this.cellHeight = 36,
    this.rows = 3,
    this.cols = 3,
    List<List<String>>? cells,
    this.colorValue = 0xFF000000,
  }) : cells = cells ??
            List.generate(rows, (_) => List.generate(cols, (_) => ''));

  Offset get center => Offset(x + (cols * cellWidth) / 2, y + (rows * cellHeight) / 2);
  double get totalWidth => cols * cellWidth;
  double get totalHeight => rows * cellHeight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'cellWidth': cellWidth,
        'cellHeight': cellHeight,
        'rows': rows,
        'cols': cols,
        'cells': cells,
        'colorValue': colorValue,
      };

  factory TableItem.fromJson(Map<String, dynamic> j) => TableItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        cellWidth: (j['cellWidth'] as num? ?? 80).toDouble(),
        cellHeight: (j['cellHeight'] as num? ?? 36).toDouble(),
        rows: j['rows'] as int? ?? 3,
        cols: j['cols'] as int? ?? 3,
        cells: (j['cells'] as List<dynamic>? ?? [])
            .map((row) => (row as List<dynamic>).map((c) => c as String).toList())
            .toList(),
        colorValue: j['colorValue'] as int? ?? 0xFF000000,
      );
}

// ─── Canvas Data ──────────────────────────────────────────────────────────────

class CanvasData {
  List<ShapeItem> shapes;
  List<TextBoxItem> textBoxes;
  List<ImageItem> images;
  List<TableItem> tables;

  CanvasData({
    List<ShapeItem>? shapes,
    List<TextBoxItem>? textBoxes,
    List<ImageItem>? images,
    List<TableItem>? tables,
  })  : shapes = shapes ?? [],
        textBoxes = textBoxes ?? [],
        images = images ?? [],
        tables = tables ?? [];

  Map<String, dynamic> toJson() => {
        'shapes': shapes.map((s) => s.toJson()).toList(),
        'textBoxes': textBoxes.map((t) => t.toJson()).toList(),
        'images': images.map((i) => i.toJson()).toList(),
        'tables': tables.map((t) => t.toJson()).toList(),
      };

  factory CanvasData.fromJson(Map<String, dynamic> j) => CanvasData(
        shapes: (j['shapes'] as List<dynamic>? ?? [])
            .map((s) => ShapeItem.fromJson(s as Map<String, dynamic>))
            .toList(),
        textBoxes: (j['textBoxes'] as List<dynamic>? ?? [])
            .map((t) => TextBoxItem.fromJson(t as Map<String, dynamic>))
            .toList(),
        images: (j['images'] as List<dynamic>? ?? [])
            .map((i) => ImageItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        tables: (j['tables'] as List<dynamic>? ?? [])
            .map((t) => TableItem.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
