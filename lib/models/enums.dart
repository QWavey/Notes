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

enum DrawTool { pen, eraser, move, textBox, shape, lasso, table }

enum EraserMode { precision, stroke }

enum ShapeType {
  rectangle,
  circle,
  isoscelesTriangle,
  rightTriangle,
  leftTriangle,
  arrow,
  star,
}

extension ShapeTypeLabel on ShapeType {
  String get label {
    switch (this) {
      case ShapeType.rectangle:
        return 'Rectangle';
      case ShapeType.circle:
        return 'Circle';
      case ShapeType.isoscelesTriangle:
        return 'Triangle ▲';
      case ShapeType.rightTriangle:
        return 'Right △';
      case ShapeType.leftTriangle:
        return 'Left △';
      case ShapeType.arrow:
        return 'Arrow';
      case ShapeType.star:
        return 'Star';
    }
  }
}

enum PageSize { a4, a5, letter }

extension PageSizeLabel on PageSize {
  String get label {
    switch (this) {
      case PageSize.a4:
        return 'A4';
      case PageSize.a5:
        return 'A5';
      case PageSize.letter:
        return 'Letter';
    }
  }
}
