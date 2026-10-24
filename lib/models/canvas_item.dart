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

  factory TableItem.fromJson(Map<String, dynamic> j) {
    final rows = j['rows'] as int? ?? 3;
    final cols = j['cols'] as int? ?? 3;
    return TableItem(
      id: j['id'] as String,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      cellWidth: (j['cellWidth'] as num? ?? 80).toDouble(),
      cellHeight: (j['cellHeight'] as num? ?? 36).toDouble(),
      rows: rows,
      cols: cols,
      cells: _normalizeCells(j['cells'], rows, cols),
      colorValue: j['colorValue'] as int? ?? 0xFF000000,
    );
  }

  /// Returns a rows x cols grid. Missing or malformed entries become empty
  /// strings and extra entries are dropped, so cells[row][col] is always valid.
  static List<List<String>> _normalizeCells(Object? raw, int rows, int cols) {
    final source = raw is List ? raw : const <dynamic>[];
    final rowCount = rows < 0 ? 0 : rows;
    final colCount = cols < 0 ? 0 : cols;
    return List.generate(rowCount, (r) {
      final row = r < source.length && source[r] is List
          ? source[r] as List
          : const <dynamic>[];
      return List.generate(colCount,
          (c) => c < row.length && row[c] is String ? row[c] as String : '');
    });
  }
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

  /// Decodes every entry on its own. An entry that cannot be read is described
  /// in [skipped] (when given) and left out, so one bad item does not discard
  /// the valid ones on the same page.
  factory CanvasData.fromJson(Map<String, dynamic> j,
          {List<String>? skipped}) =>
      CanvasData(
        shapes: _decodeEach(j['shapes'], 'shapes', ShapeItem.fromJson, skipped),
        textBoxes: _decodeEach(
            j['textBoxes'], 'textBoxes', TextBoxItem.fromJson, skipped),
        images: _decodeEach(j['images'], 'images', ImageItem.fromJson, skipped),
        tables: _decodeEach(j['tables'], 'tables', TableItem.fromJson, skipped),
      );

  static List<T> _decodeEach<T>(
    Object? raw,
    String kind,
    T Function(Map<String, dynamic>) decode,
    List<String>? skipped,
  ) {
    if (raw == null) return <T>[];
    if (raw is! List) {
      skipped?.add('$kind: not a list');
      return <T>[];
    }
    final out = <T>[];
    for (var i = 0; i < raw.length; i++) {
      try {
        out.add(decode(raw[i] as Map<String, dynamic>));
      } catch (e) {
        skipped?.add('$kind[$i]: $e');
      }
    }
    return out;
  }
}
