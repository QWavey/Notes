import 'dart:ui';

enum PaperType {
  plainWhite,
  plainYellow,
  ruledWhite,
  ruledYellow,
  gridWhite,
  gridYellow,
  dottedWhite,
  dottedYellow,
}

extension PaperTypeLabel on PaperType {
  String get label {
    switch (this) {
      case PaperType.plainWhite:
        return 'Plain White';
      case PaperType.plainYellow:
        return 'Plain Yellow';
      case PaperType.ruledWhite:
        return 'Ruled White';
      case PaperType.ruledYellow:
        return 'Ruled Yellow';
      case PaperType.gridWhite:
        return 'Grid White';
      case PaperType.gridYellow:
        return 'Grid Yellow';
      case PaperType.dottedWhite:
        return 'Dotted White';
      case PaperType.dottedYellow:
        return 'Dotted Yellow';
    }
  }

  String get labelDe {
    switch (this) {
      case PaperType.plainWhite:
        return 'Leer Weiß';
      case PaperType.plainYellow:
        return 'Leer Gelb';
      case PaperType.ruledWhite:
        return 'Liniert Weiß';
      case PaperType.ruledYellow:
        return 'Liniert Gelb';
      case PaperType.gridWhite:
        return 'Kariert Weiß';
      case PaperType.gridYellow:
        return 'Kariert Gelb';
      case PaperType.dottedWhite:
        return 'Gepunktet Weiß';
      case PaperType.dottedYellow:
        return 'Gepunktet Gelb';
    }
  }
}

enum CanvasMode { draw, document }

enum DrawTool { pen, eraser, move, textBox, shape, lasso, table, resize }

enum EraserMode { normal, precision, line }

enum ShapeType {
  rectangle,
  circle,
  triangle,
  rightTriangle,
  leftTriangle,
  arrow,
  lineArrow,
  star,
}

extension ShapeTypeLabel on ShapeType {
  String get label {
    switch (this) {
      case ShapeType.rectangle:
        return 'Rectangle';
      case ShapeType.circle:
        return 'Circle';
      case ShapeType.triangle:
        return 'Triangle ▲';
      case ShapeType.rightTriangle:
        return 'Right △';
      case ShapeType.leftTriangle:
        return 'Left △';
      case ShapeType.arrow:
        return 'Pfeil ↑';
      case ShapeType.lineArrow:
        return 'Linie →';
      case ShapeType.star:
        return 'Stern ★';
    }
  }
}

enum PageSize { a4, a5, a6, letter, custom }

enum PageNavigationMode { swipeHorizontal, scrollVertical }

enum DrawCanvasSize {
  screenFit,
  a4,
  a4landscape,
  a5,
  letter,
  unlimited,
}

extension DrawCanvasSizeLabel on DrawCanvasSize {
  String get label {
    switch (this) {
      case DrawCanvasSize.screenFit:
        return 'Normal';
      case DrawCanvasSize.a4:
        return 'A4';
      case DrawCanvasSize.a4landscape:
        return 'A4 ↔';
      case DrawCanvasSize.a5:
        return 'A5';
      case DrawCanvasSize.letter:
        return 'Letter';
      case DrawCanvasSize.unlimited:
        return '∞ Unendlich';
    }
  }

  Size? get fixedSize {
    switch (this) {
      case DrawCanvasSize.screenFit:
        return null;
      case DrawCanvasSize.a4:
        return const Size(794, 1123);
      case DrawCanvasSize.a4landscape:
        return const Size(1123, 794);
      case DrawCanvasSize.a5:
        return const Size(559, 794);
      case DrawCanvasSize.letter:
        return const Size(816, 1056);
      case DrawCanvasSize.unlimited:
        return const Size(3000, 4000);
    }
  }
}

extension PageSizeLabel on PageSize {
  String get label {
    switch (this) {
      case PageSize.a4:
        return 'A4';
      case PageSize.a5:
        return 'A5';
      case PageSize.a6:
        return 'A6';
      case PageSize.letter:
        return 'Letter';
      case PageSize.custom:
        return 'Custom';
    }
  }

  double get pixelWidth {
    switch (this) {
      case PageSize.a4:
        return 794;
      case PageSize.a5:
        return 559;
      case PageSize.a6:
        return 396;
      case PageSize.letter:
        return 816;
      case PageSize.custom:
        return 794;
    }
  }

  double get pixelHeight {
    switch (this) {
      case PageSize.a4:
        return 1123;
      case PageSize.a5:
        return 794;
      case PageSize.a6:
        return 559;
      case PageSize.letter:
        return 1056;
      case PageSize.custom:
        return 1123;
    }
  }
}